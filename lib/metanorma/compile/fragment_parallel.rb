# frozen_string_literal: true

require "fileutils"
require "yaml"

module Metanorma
  class Compile
    # Spike: fragment-based parallel semantic compilation (metanorma#620).
    #
    # Opt in with METANORMA_PARALLEL_CLAUSES=<N> (N >= 2; default off). The
    # AsciiDoc source is split into clause fragments, each fragment is
    # compiled to semantic XML by a worker forked off this process, and
    # the fragment XMLs are stitched back into one semantic document that
    # the ordinary output pipeline consumes as today.
    #
    # Forking over spawning: a fresh interpreter per fragment re-pays the
    # flavor boot and -- fatally for vocabulary corpora -- the glossarist
    # dataset load (tens of seconds per fragment). A forked worker
    # inherits everything the parent already loaded. Before the first
    # fork, the parent preloads the document's glossarist datasets once
    # (opt-in plugin store cache, METANORMA_GLOSSARIST_SHARED_DATASETS),
    # so the workers read the loaded models copy-on-write instead of
    # re-parsing them.
    #
    # Split rules:
    # - includes are resolved inline, recursively;
    # - text before the first top-level heading (document header, preamble,
    #   floating-title forewords) belongs to the first fragment;
    # - each top-level (`==`) clause is one fragment;
    # - a clause whose body is a single `[yaml2text,<file>,<var>]` block
    #   over an array-valued YAML file is split further: each fragment
    #   repeats the clause's heading chain and the block template verbatim,
    #   but feeds it a generated YAML file holding one chunk of entries.
    #   That is what makes vocabulary corpora (per-schema terms loops)
    #   parallelisable without understanding their expansion.
    #
    # Stitching merges root-level children by element name: preface,
    # sections, bibliography and metanorma-extension children are merged
    # (wrapper clauses carrying the same anchor or title are unified;
    # non-wrapper duplicates are dropped), annex/indexsect/colophon are
    # appended in source order. Auto-generated boilerplate (foreword,
    # boilerplate) is taken from the first fragment only.
    #
    # Known spike gaps: per-fragment validation is skipped (the stitched
    # document flows through the normal pipeline, where validation and
    # presentation run as today); bibitem pruning that keys on citations
    # sees only the owning fragment's citations; shorthand `<<bibitem>>`
    # references to bibitems declared in another fragment degrade to
    # xref; glossarist <concept> cross-references to terms owned by
    # another fragment degrade to <errormsg> unless the reference is
    # unqualified and the repair pass can reconstruct it (domain-qualified
    # concept resolution needs the glossarist dataset, which no fragment
    # holds for the whole document); generated element ids differ between
    # any two compiles, so stitched output is canon-equivalent to a serial
    # compile (identical modulo generated ids and whitespace-only text at
    # splice points), not byte-identical.
    class FragmentParallel
      HEADING1 = /^==(?!=)/.freeze
      STYLE_ATTR = /^(\[\[.+?\]\]|\[[^\[\]]+\])$/.freeze
      FRAME_TITLE = /^\.[^\s]/.freeze
      INCLUDE = /^include::(\S+?)\[\]\s*$/.freeze
      # [yaml2text,file,var] and [data2text,var=file]
      DATA2TEXT = /\[(yaml2text|data2text),(.+?)\]\s*$/.freeze
      MAX_INCLUDE_DEPTH = 8

      # Mirrors the plugin's DatasetPreprocessor header directive.
      DATASET_ATTR = /^:glossarist-dataset:\s*(.*)$/.freeze

      # The metanorma-plugin-glossarist store-cache gate (its
      # DatasetRegistry::SHARED_STORE_ENV; spelled out here because the
      # plugin may be absent entirely).
      SHARED_DATASETS_ENV = "METANORMA_GLOSSARIST_SHARED_DATASETS"

      SKIP_ROOT = %w[bibdata boilerplate].freeze
      MERGE_ROOT = %w[preface sections bibliography
                      metanorma-extension].freeze
      WRAPPERS = %w[clause terms references introduction].freeze
      NONBASE_PREFACE_SKIP = %w[foreword].freeze
      # Canonical root-child order of metanorma semantic XML (standoc emits
      # bibliography last, annexes after sections); the stitch reorders to
      # match, since fragments append in source order.
      ROOT_ORDER = %w[bibdata metanorma-extension boilerplate preface
                      sections annex indexsect colophon bibliography].freeze

      def initialize(filename, _options, workers)
        @filename = filename
        @workers = workers
        @dir = File.realpath(File.dirname(File.expand_path(filename)))
        @base = File.basename(filename, ".*")
        @prefix = ".#{@base}.frag"
      end

      def run
        text = resolve_includes(
          File.read(@filename, encoding: "utf-8"), 0
        )
        fragments = build_fragments(text)
        warn "[fragment-parallel] #{@filename}: #{fragments.size} fragments," \
             " #{@workers} workers"
        warm_shared_datasets(text)
        compile_fragments(fragments)
        t = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        xml = stitch(fragments.map { |f| f[:path].sub(/\.adoc$/, ".xml") })
        warn format("[fragment-parallel] stitched in %.1fs",
                    Process.clock_gettime(Process::CLOCK_MONOTONIC) - t)
        xml
      ensure
        cleanup
      end

      private

      # -- splitting

      def build_fragments(text)
        lines = text.split("\n")
        header, segments = segmentize(lines)
        fragments = []
        segments.each do |seg|
          if (mega = data2text_mega(seg))
            mega_fragments(fragments, header, seg, mega)
          else
            fragments << new_fragment(fragments.size, header, seg[:lines])
          end
        end
        fragments
      end

      def new_fragment(i, header, body_lines)
        path = File.join(@dir, "#{@prefix}-#{i}.adoc")
        File.write(path, (header + body_lines).join("\n").concat("\n"),
                   encoding: "UTF-8")
        { path: path, lines: header + body_lines }
      end

      # Returns [header_lines, [{lines:}, ...]]; header is everything
      # before the first segment boundary. A boundary opens at a top-level
      # heading, an include, or a run of attribute/anchor/frame-title lines
      # immediately preceding one; the heading itself is part of that
      # segment and does not open another.
      def segmentize(lines)
        bounds = []
        i = 0
        while i < lines.size
          if boundary_start(lines, i)
            # the boundary opens at the attribute-run start (or the bare
            # heading); blank lines separating the previous clause travel
            # with the fragment that follows them, so inter-clause
            # spacing survives the split
            b = i
            b -= 1 while b.positive? && lines[b - 1].strip.empty?
            bounds << b
            i = boundary_start_resume(lines, i) || lines.size
          else
            i += 1
          end
        end
        return [[], [{ lines: lines }]] if bounds.empty?

        header = lines[0...bounds.first]
        segs = bounds.each_with_index.map do |b, k|
          { lines: lines[b...(bounds[k + 1] || lines.size)] }
        end
        [header, segs]
      end

      # Index where the boundary scan resumes: past the heading/include
      # that closes the attribute run opened at +i+.
      def boundary_start_resume(lines, i)
        return i + 1 if seg_boundary_line?(lines[i])

        j = i
        loop do
          j += 1
          j += 1 while j < lines.size && lines[j].strip.empty?
          return j + 1 if j < lines.size && seg_boundary_line?(lines[j])
          return nil unless j < lines.size &&
                            (lines[j].match?(STYLE_ATTR) ||
                             lines[j].match?(FRAME_TITLE))
        end
      end

      # Index of the heading/include that closes the attribute run
      # opening at line +i+, or nil when lines[i] opens no boundary.
      def boundary_start(lines, i)
        return i if seg_boundary_line?(lines[i])

        return nil unless lines[i].match?(STYLE_ATTR) ||
                          lines[i].match?(FRAME_TITLE)

        j = i
        loop do
          j += 1
          j += 1 while j < lines.size && lines[j].strip.empty?
          return nil if j >= lines.size
          return j if seg_boundary_line?(lines[j])
          return nil unless lines[j].match?(STYLE_ATTR) ||
                            lines[j].match?(FRAME_TITLE)
        end
      end

      def seg_boundary_line?(line)
        line.match?(HEADING1) || line.match?(INCLUDE)
      end

      def resolve_includes(text, depth, base = @dir)
        return text if depth >= MAX_INCLUDE_DEPTH

        text.gsub(INCLUDE) do
          inc = Regexp.last_match[1]
          path = File.expand_path(inc, base)
          if File.exist?(path)
            resolve_includes(File.read(path, encoding: "utf-8"), depth + 1,
                             File.dirname(path))
          else
            Regexp.last_match[0]
          end
        end
      end

      # A segment is mega-splittable when it holds exactly one
      # yaml2text/data2text open block whose data file parses to an
      # array of at least two entries.
      def data2text_mega(seg)
        attr_i = seg[:lines].each_index.find do |i|
          seg[:lines][i].match?(DATA2TEXT)
        end
        return nil unless attr_i

        m = seg[:lines][attr_i].match(DATA2TEXT)
        delim = seg[:lines][attr_i + 1]
        return nil unless delim && delim.match?(/^-{4,}$/)

        close = ((attr_i + 2)...seg[:lines].size).find do |j|
          seg[:lines][j] == delim
        end
        return nil unless close

        file, var = parse_data2text_args(m[2])
        return nil unless file && var

        data_path = File.expand_path(file, @dir)
        return nil unless File.exist?(data_path)

        begin
          entries = YAML.safe_load(File.read(data_path))
        rescue Psych::SyntaxError
          return nil
        end
        return nil unless entries.is_a?(Array) && entries.size >= 2

        { attr_i: attr_i, close: close, delim: delim, kind: m[1],
          template: seg[:lines][(attr_i + 2)...close],
          var: var, entries: entries, data_path: data_path }
      end

      # "[yaml2text,]file,var" or "[data2text,]var=file" -> [file, var].
      # The data file is the argument naming an existing YAML file.
      def parse_data2text_args(raw)
        if raw.include?(",")
          a, b = raw.split(",", 2)
          [[b, a], [a, b]].each do |file, var|
            return [file, var] if data_file_arg?(file) && ident_arg?(var)
          end
          [nil, nil]
        elsif (p = raw.split("=", 2)).size == 2
          data_file_arg?(p[1]) && ident_arg?(p[0]) ? [p[1], p[0]] : [nil, nil]
        else
          [nil, nil]
        end
      end

      def data_file_arg?(arg)
        arg.match?(/\.ya?ml\z/i) && File.exist?(File.expand_path(arg, @dir))
      end

      def ident_arg?(arg)
        arg.match?(/\A[A-Za-z_][A-Za-z0-9_]*\z/)
      end

      def mega_fragments(fragments, header, seg, mega)
        # one chunk per worker: the chunks left over after the first wave
        # land on workers that just finished, keeping every worker fed
        chunks = [mega[:entries].size, @workers].min
        size = (mega[:entries].size / chunks.to_f).ceil
        head = header + seg[:lines][0...mega[:attr_i]]
        base_idx = fragments.size
        mega[:entries].each_slice(size).with_index do |slice, i|
          idx = base_idx + i
          data_name = "#{@prefix}-#{idx}.data.yaml"
          data_path = File.join(@dir, data_name)
          File.write(data_path, YAML.dump(slice), encoding: "UTF-8")
          directive = if mega[:kind] == "data2text"
                        "[data2text,#{mega[:var]}=#{data_name}]"
                      else
                        "[yaml2text,#{data_name},#{mega[:var]}]"
                      end
          path = File.join(@dir, "#{@prefix}-#{idx}.adoc")
          File.write(path, [
            head,
            directive,
            mega[:delim], mega[:template], mega[:delim],
          ].flatten.join("\n").concat("\n"), encoding: "UTF-8")
          fragments << { path: path, mega: true }
        end
      end

      # -- dataset preload

      # Load the document's glossarist datasets once, in this process,
      # before any worker is forked. The plugin's opt-in store cache
      # (METANORMA_GLOSSARIST_SHARED_DATASETS) memoizes the parsed
      # datasets process-wide; the forked workers then answer their own
      # registry lookups from the shared, copy-on-write models instead of
      # re-parsing tens of thousands of YAML files per fragment.
      #
      # Skipped without the plugin, or when the datasets cannot be
      # resolved: the fragments then behave exactly as on the spike --
      # each loads what it needs, in its own fork.
      def warm_shared_datasets(text)
        return unless defined?(Metanorma::Plugin::Glossarist::DatasetRegistry)
        return unless Metanorma::Plugin::Glossarist::DatasetRegistry
                      .respond_to?(:shared_store_for)

        paths = glossarist_dataset_paths(text)
        return if paths.empty?

        # An explicit "0" is a user opt-out: leave the plugin gate off
        # and skip the preload -- the workers re-load per fork, as before.
        gate = ENV.fetch(SHARED_DATASETS_ENV, nil)
        gate = ENV[SHARED_DATASETS_ENV] = "1" if gate.nil? || gate.empty?
        return if gate == "0"

        registry = Metanorma::Plugin::Glossarist::DatasetRegistry.new
        t = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        paths.each { |p| registry.concepts_at(p) }
        # Give the workers a compacted, shared heap to fork from.
        GC.start
        warn format("[fragment-parallel] preloaded %d glossarist dataset(s)" \
                    " in %.1fs; workers share them copy-on-write",
                    paths.size,
                    Process.clock_gettime(Process::CLOCK_MONOTONIC) - t)
      rescue StandardError => e
        warn "[fragment-parallel] glossarist dataset preload skipped:" \
             " #{e.message}"
      end

      # Registered dataset paths in document-header order, resolved
      # against the docfile directory the same way the plugin resolves
      # them for a fragment (:glossarist-dataset: name:path;name:path).
      def glossarist_dataset_paths(text)
        text.scan(DATASET_ATTR)
            .flat_map { |(contexts)| contexts.split(";") }
            .filter_map do |entry|
              _, rel = entry.split(":", 2)&.map(&:strip)
              next unless rel && !rel.empty?

              path = File.expand_path(rel, @dir)
              File.directory?(path) ? path : nil
            end.uniq
      end

      # -- compilation

      # Bounded fork scheduler: keep @workers children alive until the
      # fragments run out, reap any exited child, then raise the first
      # failure after all scheduled work has drained.
      def compile_fragments(fragments)
        queue = fragments.dup
        running = {}
        failure = nil
        until queue.empty? && running.empty?
          until queue.empty? || running.size >= @workers
            f = queue.shift
            begin
              t = Process.clock_gettime(Process::CLOCK_MONOTONIC)
              running[spawn_fragment(f)] = [f, t]
            rescue StandardError => e
              failure ||= e.message
            end
          end
          break if running.empty?

          pid, status = Process.waitpid2(-1, 0)
          f, t = running.delete(pid)
          next unless f

          warn format("[fragment-parallel] [%d/%d] %s %.1fs",
                      fragments.size - queue.size - running.size,
                      fragments.size, File.basename(f[:path]),
                      Process.clock_gettime(Process::CLOCK_MONOTONIC) - t)
          unless status.success?
            failure ||= "fragment compile failed" \
                        " (#{status.exitstatus || "signal #{status.termsig}"}):" \
                        " #{f[:path]}, see #{f[:path]}.log"
          end
        end
        raise failure if failure
      end

      # Fork one worker for +f+. The child rebinds stdout/stderr to the
      # fragment log, drops this env var so the nested compile does not
      # recurse into fragment-parallel again, and exits without running
      # the parent's at-exit handlers: the parent owns the run's
      # lifecycle.
      def spawn_fragment(f)
        log = File.open("#{f[:path]}.log", "w:UTF-8")
        if (pid = Process.fork).nil?
          $stdout.reopen(log)
          $stderr.reopen(log)
          log.close
          ENV["METANORMA_PARALLEL_CLAUSES"] = nil
          begin
            compile_fragment(f)
            $stdout.flush
            $stderr.flush
            exit!(0)
          rescue StandardError => e
            warn e.full_message
            exit!(1)
          end
        end
        log.close
        pid
      end

      # The child-side body of one fragment compile. Runs in a forked copy
      # of this process: the flavor libraries, the metanorma registry and
      # the preloaded glossarist datasets are all inherited, so the
      # fragment pays only its own expansion and conversion.
      def compile_fragment(f)
        Metanorma::Compile.new.compile(
          f[:path], format: :asciidoc, extension_keys: [:xml],
          novalid: true, agree_to_terms: true
        )
      end

      # -- stitching

      def stitch(paths)
        base = parse(paths.first)
        ns = base.root.namespace&.href
        paths[1..].each do |p|
          stitch_fragment_root(base, parse(p), ns)
        end
        reorder_root(base)
        repair_concept_refs(base, ns)
        base.to_xml
      end

      # Concept cross-references whose target term lives in another
      # fragment fail resolution inside that fragment and come back as
      # <errormsg> payloads carrying the reference texts verbatim. This
      # pass repairs the unqualified subset: when the referenced id (or
      # its glossarist "term-" prefixed anchor) names a term in the
      # assembled document, the resolved refterm/renderterm/xref form is
      # reconstructed. Domain-qualified references (the bulk in the
      # iso-10303-2 corpus) resolve through the glossarist dataset, which
      # the stitched document does not carry -- those remain errormsg and
      # are the spike's principal known gap.
      def repair_concept_refs(base, ns)
        terms = base.root.xpath(".//xmlns:term[@anchor]", xmlns: ns)
                     .each_with_object({}) { |t, m| m[t["anchor"]] = t }
        repaired = 0
        base.root.xpath(".//xmlns:concept/xmlns:errormsg", xmlns: ns)
            .each do |err|
          tts = err.xpath(".//xmlns:tt", xmlns: ns).map(&:text)
          next unless tts.size == 3

          # the error payload carries the raw concept id; the rendered
          # anchor carries the glossarist "term-" prefix
          id = tts[2]
          id = "term-#{id}" unless terms.key?(id)
          next unless terms.key?(id)

          refterm = base.document.create_element("refterm")
          refterm.content = tts[0]
          renderterm = base.document.create_element("renderterm")
          renderterm.content = tts[1]
          xref = base.document.create_element("xref")
          xref["target"] = id
          err.replace(refterm)
          refterm.next = renderterm
          renderterm.next = xref
          repaired += 1
        end
        warn "[fragment-parallel] repaired #{repaired} cross-fragment" \
             " concept references" if repaired.positive?
      end

      # Merge one fragment's root into +base+. Layout note: standoc emits
      # root children adjacent, with a newline after the root open tag and
      # one before the root close; whitespace-only text travels with the
      # element it precedes/follows, so appends reproduce the fragment's
      # own layout at the splice point.
      def stitch_fragment_root(base, d, ns)
        pairs = []
        ws = +""
        d.root.children.each do |c|
          if c.text?
            ws << c.text
          else
            pairs << [ws, c]
            ws = +""
          end
        end
        last = nil
        pairs.each do |lead, el|
          name = el.name
          if SKIP_ROOT.include?(name)
            last = :skip
          elsif MERGE_ROOT.include?(name) &&
                (t = base.root.at_xpath("./xmlns:#{name}", xmlns: ns))
            merge_children(t, el, ns, name)
            last = :merge
          else
            drop_trailing_ws(base.root)
            base.root.add_child(
              base.root.document.create_text_node(lead)
            ) unless lead.empty?
            adopt(base, el, ns).each { |n| base.root.add_child(n) }
            last = :append
          end
        end
        return unless last == :append && !ws.empty?

        drop_trailing_ws(base.root)
        base.root.add_child(base.root.document.create_text_node(ws))
      end

      def drop_trailing_ws(root)
        t = root.children.last
        t.remove if t&.text? && t.text.strip.empty?
      end

      # Root children are emitted in the canonical semantic-XML order;
      # each element keeps the whitespace-only text node that preceded it.
      # Everything is detached and re-added in order: libxml2's in-place
      # node moves do not reliably reposition text nodes.
      def reorder_root(base)
        pairs = []
        ws = nil
        base.root.children.each do |c|
          if c.text? && c.text.strip.empty?
            ws = c
          else
            pairs << [ws, c]
            ws = nil
          end
        end
        rank = ->(p, i) { [ROOT_ORDER.index(p[1].name) || ROOT_ORDER.size, i] }
        ordered = pairs.sort_by.with_index { |p, i| rank.call(p, i) }
        base.root.children.each(&:remove)
        ordered.each do |lead, el|
          base.root.add_child(
            base.root.document.create_text_node(lead.text)
          ) if lead
          base.root.add_child(el)
        end
        base.root.add_child(
          base.root.document.create_text_node(ws.text)
        ) if ws
      end

      def parse(path)
        Nokogiri::XML(File.read(path, encoding: "UTF-8"), &:huge)
      end

      # Copy `el` (from another document) into `base`'s document, dropping
      # the default-namespace declaration so it inherits the target's.
      def adopt(base, el, ns)
        s = el.to_xml
        s = s.gsub(%r{ xmlns="#{Regexp.quote(ns)}"}, "") if ns
        Nokogiri::XML::DocumentFragment.new(base.document, s).children
      end

      def merge_children(base_el, frag_el, ns, rootname)
        skip = rootname == "preface" ? NONBASE_PREFACE_SKIP : []
        pending = +""
        landed = false
        frag_el.children.each do |child|
          if child.text?
            pending << child.text
            next
          end
          twin = base_el.elements.find { |c| elem_key(c, ns) ==
                                            elem_key(child, ns) }
          if skip.include?(child.name)
            pending = +""
          elsif twin && WRAPPERS.include?(child.name)
            base_el.add_child(
              base_el.document.create_text_node(pending)
            ) unless pending.empty?
            pending = +""
            landed = true
            merge_children(twin, child, ns, rootname)
          elsif twin
            # duplicate generated metadata or boilerplate: keep base's
            pending = +""
          else
            base_el.add_child(
              base_el.document.create_text_node(pending)
            ) unless pending.empty?
            pending = +""
            landed = true
            adopt(base_el.document, child, ns).each do |n|
              base_el.add_child(n)
            end
          end
        end
        return unless landed && !pending.empty?

        # trailing whitespace of the fragment's own layout
        base_el.add_child(base_el.document.create_text_node(pending))
      end

      # Wrapper clauses of the same mega-clause carry the same explicit
      # anchor, or -- when the source names no anchor -- the same title.
      def elem_key(el, ns)
        return [el.name, "##{el['anchor']}"] if el["anchor"]

        t = ns ? el.at_xpath("./xmlns:title", xmlns: ns) : el.at("./title")
        [el.name, t&.text]
      end

      def cleanup
        return if ENV["METANORMA_PARALLEL_KEEP"] == "1"

        # every artifact of this run carries the run prefix (fragment
        # sources, chunk data files, fragment XML, child logs, the
        # glossarist per-document log)
        Dir.glob("#{@dir}/#{@prefix}-*").each do |p|
          File.unlink(p) if File.file?(p)
        end
      end
    end
  end
end
