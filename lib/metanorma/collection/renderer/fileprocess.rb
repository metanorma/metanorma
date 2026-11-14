# frozen_string_literal: true

require "isodoc"
require "metanorma-utils"
require "concurrent-ruby"
# eprun (via twitter_cldr, via isodoc) sets its active Unicode version as a
# thread-local at require time, on whichever thread first loads it. Load it
# here, before the member pool starts, so that require happens once on the
# main thread and the pool workers can then set their own thread-local
# (initialise_pool_thread) instead of racing over who first requires the
# gem mid-render.
require "eprun"
require_relative "fileparse"
require_relative "filelocation"
require_relative "../artifact_store"
require "json"

module Metanorma
  class Collection
    class Renderer
      # One member's rendering failure, buffered until the member pool joins
      # so that failures can be reported in manifest order regardless of
      # completion order.
      MemberFailure = Struct.new(:index, :identifier, :errors, :missing)

      # compile and output individual file in collection
      # warn "metanorma compile -x html #{f.path}"
      def file_compile(file, filename, identifier, index)
        sectionsplit_val = @files.get(identifier, :sectionsplit)
        sectionsplit_val and return
        opts = compile_options_base(identifier)
          .merge(compile_options_update(identifier))
          .merge(compile_options_bare_after_first(index))

        compile = member_compile(file, opts)
        @files.set(identifier, :outputs, {})
        file_compile_formats(filename, identifier, opts,
                             member_processor(compile))
        file_compile_verify(identifier, index, compile.errors)
      end

      # Run one member's conversion on its own Compile instance
      # (metanorma#705): each member's error pool collects only that
      # member's failures, so attribution is order-independent under the
      # member pool. The previous design sliced a shared @compile.errors by
      # array-position delta, which was only sound while members compiled
      # sequentially. Construction cost is negligible (~0.1ms incl. flavour
      # load) next to a member render; the renderer-level @compile remains
      # for flavour loading and the collection-level font/PDF handling.
      def member_compile(file, opts)
        compile = Compile.new
        compile.load_flavor(@flavor)
        compile.compile file, opts
        compile
      end

      # The flavour processor for output-path mapping: a compile that
      # returned early (unsupported extensions, unreadable input) never
      # reached its processor; the registry resolves the same processor
      # object the compile would, so path mapping stays deterministic and
      # independent of member order.
      def member_processor(compile)
        compile.processor ||
          @registry.find_processor(Util::taste2flavor(@flavor).to_sym)
      end

      # bare-after-first: the directive previously mutated the shared compile
      # options as the sequential loop walked the keys; under the member pool
      # it becomes a per-member option keyed by the member's position in the
      # file lookup (the first key renders bare-free, all later ones bare).
      def compile_options_bare_after_first(index)
        bare = index.positive? &&
          @directives.detect { |d| d.key == "bare-after-first" }
        bare ? { bare: true } : {}
      end

      # A member whose rendering raised produces no output file, but the
      # collection build used to continue, exit 0, and link the absent
      # document from index.html -- silent data loss (#586). Two
      # complementary checks close that hole. (1) Each member compiles with
      # its own Compile instance (#705), whose error pool therefore holds
      # only this member's conversion failures -- attribution is independent
      # of execution order (the format-level pool inside a compile joins
      # before compile returns). (2) Independently of whether anything was
      # pooled, verify the outputs registered for the member exist on
      # disk. Failures are buffered here and accumulated; the collection
      # renders every remaining member before finalise_member_failures
      # reports them and Collection#render aborts, so one run reports all
      # failed members.
      def file_compile_verify(identifier, index, errors)
        # Section-split parts (marked with :parentid) register format
        # slots they never produce -- their :xml slot in particular is
        # never written, and under filename renaming it aliases to the
        # parent's name -- so verifying them is a false positive. #586
        # was scoped to the non-sectionsplit path; parts are excluded
        # like their parents (which return early above).
        @files.get(identifier, :parentid) and return
        missing = (@files.get(identifier, :outputs) || {})
          .reject { |_fmt, path| File.exist?(path) }
        errors.empty? && missing.empty? and return
        record_member_failure(index, identifier, errors, missing)
      end

      # Buffer a member failure under the mutex: pool workers complete out
      # of manifest order, and appends from multiple threads are not a
      # synchronisation point we rely on.
      def record_member_failure(index, identifier, errors, missing)
        @failures_mutex.synchronize do
          @member_failures << MemberFailure.new(index, identifier, errors,
                                                missing)
        end
      end

      # Flush the buffered member failures in manifest order: the error
      # lines, the log entries (and so the .err.html artifact) and the
      # fatal_errors list are ordered by the manifest, never by completion
      # order. Runs before Collection#render aborts on fatal_errors (#586).
      def finalise_member_failures
        @member_failures.sort_by(&:index).each do |failure|
          file_compile_failure_log(failure.identifier, failure.errors,
                                   failure.missing)
          msg = file_compile_failure_msg(failure.identifier, failure.errors,
                                         failure.missing)
          ::Metanorma::Util.log("[metanorma] Error: #{msg}", :error)
          fatal_errors << msg
        end
      end

      def file_compile_failure_log(identifier, errors, missing)
        missing.each_value do |path|
          @log&.add("METANORMA_4", nil, params: [identifier, path])
        end
        errors.each do |e|
          @log&.add("METANORMA_5", nil, params: [identifier, e])
        end
      end

      def file_compile_failure_msg(identifier, errors, missing)
        ret = []
        missing.empty? or
          ret << "expected output not generated: " \
                 "#{missing.values.join(', ')}"
        ret += errors
        "Failed to render collection member #{identifier}: #{ret.join('; ')}"
      end

      def compile_options_base(identifier)
        e = @files.get(identifier, :extract_opts)
        {
          format: :asciidoc,
          extension_keys: @files.get(identifier, :format),
          fonts: e&.dig(:fonts),
          output_dir: @outdir,
          pdffile: @files.get(identifier, :pdffile),
          type: Util::taste2flavor(@flavor),
        }
      end

      def compile_options_update(identifier)
        ret = @compile_options.dup
        @directives.detect { |d| d.key == "presentation-xml" } ||
          @files.get(identifier, :presentationxml) and
          ret.merge!(passthrough_presentation_xml: true)
        @files.get(identifier, :sectionsplit) == true and
          ret.merge!(sectionsplit: true)
        @files.get(identifier, :bare) == true and
          ret.merge!(bare: true)
        ret
      end

      #       def allowed_extension_keys
      #         ret = @format.dup
      #         @directives.detect { |d| d.key == "individual-pdf" } or
      #           ret.delete(:pdf)
      #         @directives.detect { |d| d.key == "individual-doc" } or
      #           ret.delete(:doc)
      #         ret
      #       end

      # process each file in the collection
      # files are held in memory, and altered as postprocessing
      #
      # Members are rendered on a bounded pool (metanorma#705): members are
      # independent render units, and the sequential design existed for
      # error attribution, not data dependence. Shared-state audit:
      # - FileLookup entries are keyed per member; the only entry a member
      #   writes is its own :outputs hash. Distinct keys, distinct hashes.
      # - each member builds its own Compile instance, so no compile state
      #   (errors, processor, log) is shared between members;
      # - the cross-reference passes mutate only the member's own XML tree
      #   and per-member memo structures (localised in fileparse.rb); the
      #   renderer-level memos the passes read (svg hotspot index) are pure
      #   functions of the file lookup, which is frozen once init completes;
      # - attachment copies and the DisambigFiles nametable stay on the main
      #   thread;
      # - failures are buffered under a mutex and flushed in manifest order
      #   once the pool joins, and the navigation/coverpage/concatenation
      #   passes are built from the manifest afterwards (navigation.rb), so
      #   completion order never leaks into the output.
      def files # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
        warn "\n\n\n\n\nRender Files: #{DateTime.now.strftime('%H:%M:%S')}"
        internal_refs = locate_internal_refs
        jobs = []
        @files.keys.each_with_index do |ident, i|
          if @files.get(ident, :attachment) then copy_file_to_dest(ident)
          else
            # Distributed reinflation: the manifest carries every member
            # (their stored files feed the anchors and cross-reference
            # passes) but this run renders only the selected slice; the
            # other members' sections are rendered by sibling runs over
            # the same store.
            @only_members and !render_member?(ident) and next
            jobs << [i, ident]
          end
        end
        render_members(jobs, internal_refs)
        finalise_member_failures
      end

      # Render the selected members on a bounded pool. Default 4 workers,
      # overridable with the :member_pool_size render option.
      def render_members(jobs, internal_refs)
        jobs.empty? and return
        pool = Concurrent::FixedThreadPool.new(member_pool_size)
        jobs.each do |(index, ident)|
          pool.post { render_member(index, ident, internal_refs) }
        end
        pool.shutdown
        pool.wait_for_termination
      end

      # One member render unit: cross-reference passes over the member's own
      # tree, then compile and output. A member whose processing raises is
      # recorded as that member's failure -- a raising job must never take
      # its worker thread down or abort the pool, so the remaining members
      # still render and the run reports all failures (#586).
      def render_member(index, ident, internal_refs)
        initialise_pool_thread
        file, fname = @files.targetfile_id(ident, read: true)
        @preserve_unresolved && member_stored?(ident, file) and return
        warn "\n\n\n\n\nProcess #{fname}: #{DateTime.now.strftime('%H:%M:%S')}"
        xml = member_collection_xml(file, ident, internal_refs)
        xml_path = write_member_collection_xml(fname, xml)
        file_compile(xml_path, fname, ident, index)
        FileUtils.rm_f(xml_path)
      rescue StandardError => e
        record_member_failure(index, ident, ["#{e.class}: #{e.message}"], {})
      end

      # Cross-reference the member's tree against the collection; a staging
      # build additionally persists the stub-bearing artefacts to the store.
      def member_collection_xml(file, ident, internal_refs)
        collection_xml = update_xrefs(file, ident, internal_refs)
        @preserve_unresolved and
          store_member_artefacts(ident, file, collection_xml)
        collection_xml
      end

      # Write the member's cross-referenced XML to a temp file for the
      # compile. The temp basename drives the compiled output filenames, so
      # it stays the member's own (per-collection-disambiguated) basename --
      # distinct across members, so pool workers never share a temp path.
      def write_member_collection_xml(fname, collection_xml)
        # Strip .xml or .html extension, but NOT section numbers like .0
        fname_base = File.basename(fname)
        collection_filename = fname_base
        /\.(xml|html)$/.match?(fname_base) and
          collection_filename = fname_base.sub(/\.(xml|html)$/, "")
        collection_xml_path = File.join(Dir.tmpdir,
                                        "#{collection_filename}.xml")
        File.write(collection_xml_path, collection_xml, encoding: "UTF-8")
        collection_xml_path
      end

      # Re-establish the per-thread gem defaults a fresh worker thread
      # lacks. eprun keeps the active Unicode version in a thread-local
      # that require time sets only on the loading thread (eprun.rb's
      # `Eprun.current_version = Eprun::UcdVersion.latest`); on any other
      # thread it reads nil and isodoc's index collation crashes with
      # NoMethodError inside Eprun::UcdVersion.get. The gem itself is
      # required up front (see the require block above), so every worker
      # starts its job by giving its thread the same latest version the
      # loading thread received.
      def initialise_pool_thread
        Eprun.current_version ||= Eprun::UcdVersion.latest
      end

      # Persist an isolated member's stub-bearing Semantic XML and its anchor
      # contribution to the content-addressed store, so a later reinflation pass
      # can relink the stubs and a re-run can resume without recompiling.
      # Within-campaign content key for a member. (Cross-build soundness needs
      # the full input closure -- source + includes + templates + schemas +
      # versions; see the plan gotcha. Here the source bytes + tool version
      # suffice because inputs are frozen across a single build campaign.)
      def member_content_hash(source)
        ArtifactStore.content_hash(source, ::Metanorma::VERSION)
      end

      # Only-members selects docref identifiers; section-split outputs are
      # derivative entries added at renderer init under their own keys,
      # each carrying :parentid. A split output renders whenever its
      # parent is selected, or a sliced reinflate ships index pages whose
      # section pages are missing (iso-10303#811).
      def render_member?(ident)
        @only_member_keys.include?(ident) ||
          @only_member_keys.include?(@files.get(ident, :parentid))
      end

      # Resume predicate: is this member already compiled and stored for its
      # current input content? If so the isolated compile can skip it.
      def member_stored?(ident, source)
        @artifact_store.key?(ident, member_content_hash(source), :semantic)
      end

      def store_member_artefacts(ident, source, semantic_xml)
        hash = member_content_hash(source)
        @artifact_store.write(ident, hash, :semantic, semantic_xml)
        @artifact_store.write(ident, hash, :anchors,
                              JSON.generate(@files.get(ident, :anchors) || {}))
        @keep_cache or @artifact_store.prune_superseded(ident, hash)
      end

      # gather internal bibitem references
      def gather_internal_refs
        @files.keys.each_with_object({}) do |i, refs|
          @files.get(i, :attachment) and next
          @files.get(i, :sectionsplit) and next
          file, = @files.targetfile_id(i, read: true)
          gather_internal_refs1(file, i, refs)
        end
      end

      def gather_internal_refs1(file, ident, refs)
        f = Nokogiri::XML(file, &:huge)
        !@files.get(ident, :sectionsplit) and
          gather_internal_refs_indirect(f, refs)
        key = @files.get(ident, :indirect_key) and
          gather_internal_refs_sectionsplit(f, ident, key, refs)
      end

      def gather_internal_refs_indirect(doc, refs)
        doc.xpath(ns("//bibitem[@type = 'internal']/" \
                     "docidentifier[@type = 'repository']")).each do |d|
                       a = d.text.split(%r{/}, 2)
                       a.size > 1 or next
                       refs[a[0]] ||= {}
                       refs[a[0]][a[1]] = false
                     end
      end

      def gather_internal_refs_sectionsplit(_doc, ident, key, refs)
        refs[key] ||= {}
        @files.get(ident, :ids).each_key do |k|
          refs[key][k] = false
        end
      end

      def populate_internal_refs(refs)
        @files.keys.reject do |k|
          @files.get(k, :attachment) || @files.get(k, :sectionsplit)
        end.each do |ident|
          locate_internal_refs1(refs, ident,
                                @isodoc.docid_prefix("", ident.dup))
        end
        refs
      end

      # resolve file location for the target of each internal reference
      def locate_internal_refs
        warn "\n\n\n\n\nInternal Refs: #{DateTime.now.strftime('%H:%M:%S')}"
        refs = populate_internal_refs(gather_internal_refs)
        refs.each do |schema, ids|
          ids.each do |id, key|
            key and next
            refs[schema][id] = "Missing:#{schema}:#{id}"
            @log&.add("METANORMA_1", nil, params: [refs[schema][id]])
          end
        end
        refs
      end

      def locate_internal_refs1(refs, identifier, ident)
        file, = @files.targetfile_id(ident, read: true)
        t = locate_internal_refs1_prep(file)
        refs.each do |schema, ids|
          ids.keys.select { |id| t[id] }.each do |id|
            t[id].at("./ancestor-or-self::*[@type = '#{schema}']") and
              refs[schema][id] = identifier
          end
        end
      end

      def locate_internal_refs1_prep(file)
        xml = Nokogiri::XML(file, &:huge)
        r = xml.root["document_suffix"]
        ret = xml.xpath("//*[@id]").each_with_object({}) do |i, x|
          x[i["id"]] = i
          r and x[i["id"].sub(/_#{r}$/, "")] = i
        end
        xml.xpath("//*[@anchor]").each do |i|
          ret[i["anchor"]] = i
          r and ret[i["anchor"].sub(/_#{r}$/, "")] = i
        end
        ret
      end

      def update_bibitem(bib, identifier)
        newbib, url, attachment = update_bibitem_prep(bib, identifier)
        newbib or return
        dest = begin
          newbib.at("./docidentifier") || newbib.at(ns("./docidentifier"))
        rescue StandardError
          nil
        end
        dest or dest = newbib.elements[-1]
        # An attachment carries both a <uri type="attachment"> (which drives
        # isodoc's fmt-link attachment="true") and the citation uri; the
        # attachment uri goes first. metanorma/iso-10303#208.
        attachment and dest.previous = "<uri type='attachment'>#{url}</uri>"
        dest.previous = "<uri type='citation'>#{url}</uri>"
        bib.replace(newbib)
      end

      def update_bibitem_prep(bib, identifier)
        docid = get_bibitem_docid(bib, identifier) or return [nil, nil, nil]
        newbib = dup_bibitem(docid, bib)
        attachment = @files.get(docid, :attachment)
        url = @files.url(docid, relative: true, doc: !attachment)
        current_html = referencing_html_location(identifier, attachment)
        url = make_relative_path(current_html, url) if current_html
        [newbib, url, attachment]
      end

      # Location of the HTML that will carry the cross-reference to the target,
      # used as the base for relativising the attachment/citation URL.
      #
      # Normally this is the referencing document's own output (:outputs[:html]
      # after compilation, else :out_path converted to .html before it).
      #
      # But when the referencing document is sectionsplit, its content is not
      # emitted at its own out_path: it is split into section files written at
      # the sectionsplit output location (the collection root, unless a
      # sectionsplit_filename directory is configured). Relativising an
      # attachment URL against the unsplit out_path then overshoots -- the
      # ../../ climbs above the split file and the attachment link breaks
      # (https://github.com/metanorma/iso-10303/issues/208). So for attachment
      # targets of a sectionsplit document, base the relative path on the
      # sectionsplit output directory instead.
      def referencing_html_location(identifier, attachment)
        attachment && @files.get(identifier, :sectionsplit) and
          return sectionsplit_ref_html(identifier)
        document_ref_html(identifier)
      end

      # The split section files sit at the sectionsplit output directory: the
      # collection root, or the directory of a configured sectionsplit_filename.
      def sectionsplit_ref_html(identifier)
        d = @files.preserve_directory_structure?(identifier)
        d ? File.join(File.dirname(d), "x.html") : "x.html"
      end

      # Use :outputs[:html] if available (after compilation), otherwise convert
      # :out_path to HTML (before compilation), following ref_file_xml2html.
      def document_ref_html(identifier)
        @files.get(identifier, :outputs)&.dig(:html) ||
          out_path_to_html(@files.get(identifier, :out_path))
      end

      def out_path_to_html(out_path)
        out_path or return nil
        out_path.end_with?(".xml") and return out_path.sub(/\.xml$/, ".html")
        "#{out_path}.html"
      end
    end
  end
end
