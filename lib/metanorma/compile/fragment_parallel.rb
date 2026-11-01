# frozen_string_literal: true

require "fileutils"
require "open3"
require "yaml"

module Metanorma
  class Compile
    # Spike: fragment-based parallel semantic compilation (metanorma#620).
    #
    # Opt in with METANORMA_PARALLEL_CLAUSES=<N> (N >= 2; default off). The
    # AsciiDoc source is split into clause fragments, each fragment is
    # compiled to semantic XML by its own metanorma process (isolating the
    # Asciidoctor/glossarist global state), and the fragment XMLs are
    # stitched back into one semantic document that the ordinary output
    # pipeline consumes as today.
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
    # xref (standoc resolves erefs only within the compiling document);
    # generated element ids differ between any two compiles, so stitched
    # output is canon-equivalent to a serial compile (identical modulo
    # generated ids and whitespace-only text at splice points), not
    # byte-identical.
    class FragmentParallel
      HEADING1 = /^==(?!=)/.freeze
      STYLE_ATTR = /^(\[\[.+?\]\]|\[[^\[\]]+\])$/.freeze
      FRAME_TITLE = /^\.[^\s]/.freeze
      INCLUDE = /^include::(\S+?)\[\]\s*$/.freeze
      # [yaml2text,file,var] and [data2text,var=file]
      DATA2TEXT = /\[(yaml2text|data2text),(.+?)\]\s*$/.freeze
      MAX_INCLUDE_DEPTH = 8

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

      CHILD_SCRIPT = <<~RUBY.freeze
        require "metanorma"
        (ENV["METANORMA_PARALLEL_CHILD_REQUIRES"] || "")
          .split(",").each { |g| require g }
        Metanorma::Compile.new.compile(
          ARGV[0], format: :asciidoc, extension_keys: [:xml],
          novalid: true, agree_to_terms: true
        )
      RUBY

      def initialize(filename, options, workers)
        @filename = filename
        @workers = workers
        @dir = File.realpath(File.dirname(File.expand_path(filename)))
        @base = File.basename(filename, ".*")
        @prefix = ".#{@base}.frag"
        @requires = [options[:type] && "metanorma-#{options[:type]}"]
        if (r = ENV["METANORMA_PARALLEL_CHILD_REQUIRES"])
          @requires = r.split(",")
        end
        @requires.compact!
      end

      def run
        fragments = build_fragments
        warn "[fragment-parallel] #{@filename}: #{fragments.size} fragments," \
             " #{@workers} workers"
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

      def build_fragments
        lines = resolve_includes(
          File.read(@filename, encoding: "utf-8"), 0
        ).split("\n")
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
        # one chunk per worker: each child re-loads the glossarist
        # dataset, so more chunks mostly re-pay that fixed cost
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

      # -- compilation

      def compile_fragments(fragments)
        pool = ::Metanorma::Util::WorkersPool.new(@workers)
        lock = Mutex.new
        done = 0
        failures = []
        fragments.each_with_index do |f, i|
          pool.schedule do
            t = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            begin
              child_compile(f[:path])
            rescue StandardError => e
              # a raise here would kill the pool thread and deadlock
              # WorkersPool#shutdown; surface it after the pool drains
              lock.synchronize { failures << e }
            end
            dt = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t
            lock.synchronize do
              done += 1
              warn format("[fragment-parallel] [%d/%d] %s %.1fs",
                          done, fragments.size, File.basename(f[:path]), dt)
            end
          end
        end
        pool.shutdown
        raise failures.first unless failures.empty?
      end

      def child_compile(path)
        env = {
          "METANORMA_PARALLEL_CLAUSES" => nil,
          "METANORMA_PARALLEL_CHILD_REQUIRES" => @requires.join(","),
        }
        out, err, status = Open3.capture3(env, RbConfig.ruby, "-e",
                                          CHILD_SCRIPT, path, chdir: @dir)
        File.write("#{path}.log", [out, err].join, encoding: "UTF-8")
        return if status.success?

        raise "fragment compile failed (#{status.exitstatus}): #{path}," \
              " see #{path}.log"
      end

      # -- stitching

      def stitch(paths)
        base = parse(paths.first)
        ns = base.root.namespace&.href
        paths[1..].each do |p|
          stitch_fragment_root(base, parse(p), ns)
        end
        reorder_root(base)
        base.to_xml
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
