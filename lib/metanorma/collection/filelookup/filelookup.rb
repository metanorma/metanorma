require "isodoc"
require "htmlentities"
require "metanorma-utils"
require "marcel"
require_relative "filelookup_sectionsplit"
require_relative "base"
require_relative "utils"

module Metanorma
  class Collection
    class FileLookup
      attr_accessor :files_to_delete, :parent

      # hash for each document in collection of document identifier to:
      # document reference (fileref or id), type of document reference,
      # and bibdata entry for that file
      # @param path [String] path to collection
      def initialize(path, parent)
        @c = HTMLEntities.new
        @files = {}
        @parent = parent
        @xml = parent.xml
        @isodoc = parent.isodoc
        @isodoc_presxml = parent.isodoc_presxml
        @path = path
        @compile = parent.compile
        @documents = parent.documents
        @files_to_delete = []
        @disambig = Util::DisambigFiles.new
        @manifest = parent.manifest
        read_files(@manifest.entry, parent.manifest)
      end

      def read_files(entries, parent, idx = 0)
        Array(entries).each do |e|
          derive_format(e, parent)
          if e.file
            read_file(e, idx)
            idx += 1
          end
          idx = read_files(e.entry, e, idx)
        end
        idx
      end

      def derive_format(entry, parent)
        entry.attachment and return
        entry.format ||= parent.format || %w(xml presentation html)
        entry.format |= ["xml", "presentation"]
      end

      def read_file(manifest, idx)
        i, k = read_file_idents(manifest)
        entry = file_entry(manifest, k, idx) or return
        bibdata_process(entry, i)
        bibitem_process(entry)
        @files[key(i)] = entry
      end

      def read_file_idents(manifest)
        id = manifest.identifier
        sanitised_id = key(@isodoc.docid_prefix("", manifest.identifier.dup))
        #       if manifest.bibdata and # NO, DO NOT FISH FOR THE GENUINE IDENTIFIER IN BIBDATA
        #         d = manifest.bibdata.docidentifier.detect { |x| x.primary } ||
        #           manifest.bibdata.docidentifier.first
        #         k = d.id
        #         i = key(@isodoc.docid_prefix(d.type, d.id.dup))
        #       end
        [id, sanitised_id]
      end

      def bibdata_process(entry, ident)
        if entry[:attachment]
          entry[:bibdata] =
            Metanorma::Collection::Document.attachment_bibitem(ident).root
        else
          file, _filename = targetfile(entry, read: true)
          xml = Nokogiri::XML(file, &:huge)
          add_document_suffix(ident, xml)
          entry.merge!(bibdata_extract(xml))
        end
      end

      def bibdata_extract(xml)
        anchors = read_anchors(xml)
        { anchors: anchors, anchors_lookup: anchors_lookup(anchors),
          ids: read_ids(xml),
          bibdata: xml.at(ns("//bibdata")),
          document_suffix: xml.root["document_suffix"] }
      end

      def bibitem_process(entry)
        entry[:bibitem] = entry[:bibdata].dup
        entry[:bibitem].name = "bibitem"
        entry[:bibitem]["hidden"] = "true"
        entry[:bibitem].at("./*[local-name() = 'ext']")&.remove
      end

      # ref is the absolute source file address
      # rel_path is the relative source file address, relative to the YAML location
      # out_path is the destination file address, with any references outside
      # the working directory (../../...) truncated, and based on relative path
      # identifier is the id with only spaces, no nbsp
      # idx is the index of the document in the manifest
      def file_entry(ref, identifier, idx)
        ref.file or return
        abs = @documents[Util::key identifier].file
        # For sectionsplit outputs from YAML manifest, we need to compute the full path
        # by combining sectionsplit_filename directory with ref.file basename
        sso = ref.respond_to?(:sectionsplit_output) && ref.sectionsplit_output
        out_path, rel_path = file_entry_paths(ref, idx, sso)
        ret = if ref.file
                { type: "fileref", ref: abs, rel_path: rel_path, url: ref.url,
                  out_path: out_path, idx: idx,
                  output_filename: ref.output_filename,
                  sectionsplit_filename: ref.sectionsplit_filename,
                  pdffile: ref.pdffile, format: ref.format&.map(&:to_sym) }
                  .compact
              else { type: "id", ref: ref.id }
              end
        file_entry_copy(ref, ret)
        ret.compact
      end


      # ref is the absolute source file address
      # rel_path is the relative source file address, relative to the YAML location
      # out_path is the destination file address, with any references outside
      # the working directory (../../...) truncated, and based on relative path
      # identifier is the id with only spaces, no nbsp
      # extract_opts are the compilation options extracted as document attributes
      def file_entry_struct(ref, abs)
        adoc = abs.sub(/\.xml$/, ".adoc")
        if adoc.end_with?(".adoc") && File.exist?(adoc)
          opts = Metanorma::Input::Asciidoc.new.extract_options(File.read(adoc))
        end
        { type: "fileref", ref: abs, rel_path: ref.file, url: ref.url,
          out_path: output_file_path(ref), pdffile: ref.pdffile,
          format: ref.format&.map(&:to_sym), extract_opts: opts }.compact
      end

      def file_entry_paths(ref, idx, sso)
        base = File.basename(ref.file, ".xml")
        if sso && ref.respond_to?(:sectionsplit_filename) &&
            ref.sectionsplit_filename
          # Extract directory from sectionsplit_filename
          dir = File.dirname(ref.sectionsplit_filename)
          if dir == "." # No directory in pattern
            [output_file_path(ref, idx), ref.file]
          else # Pattern has directory, prepend it
            full_path = File.join(dir, base)
            [full_path, "#{full_path}.xml"]
          end
        else [output_file_path(ref, idx), ref.file]
        end
      end

      # Substitute special strings in filename patterns
      # @param pattern [String] filename pattern with placeholders
      # @param options [Hash] substitution values
      # @option options [Integer] :document_num document index
      # @option options [String] :basename filename without extension
      # @option options [String] :basename_legacy full filename with extension
      # @option options [Integer] :sectionsplit_num sectionsplit index
      def substitute_filename_pattern(pattern, options = {})
        pattern or return pattern
        result = pattern.dup
        options[:document_num] and
          result.gsub!(/\{document-num\}/, options[:document_num].to_s)
        result.gsub!(/\{basename\}/, options[:basename]) if options[:basename]
        options[:basename_legacy] and
          result.gsub!(/\{basename_legacy\}/, options[:basename_legacy])
        options[:sectionsplit_num] and
          result.gsub!(/\{sectionsplit-num\}/, options[:sectionsplit_num].to_s)
        result
      end

      # TODO make the output file location reflect source location universally,
      # not just for attachments: no File.basename
      #
      # For files with custom directory structure, construct path with directory
      # For files with output_filename, use that (with substitutions)
      # For others, use basename of ref.file
      def output_file_path(ref, idx)
        has_custom_dir, file_has_dir, params = output_file_path_prep(ref, idx)
        # Apply sectionsplit_filename directory structure if:
        # 1. File has sectionsplit enabled (parent document being split), OR
        # 2. File is a sectionsplit output (from collection or single-file sectionsplit)
        # Regular files that inherit sectionsplit_filename from collection level
        # but are not sectionsplit outputs should NOT use it
        is_sectionsplit_output = ref.respond_to?(:sectionsplit_output) && ref.sectionsplit_output
        use_sectionsplit_dir = ref.sectionsplit_filename && has_custom_dir &&
          (ref.sectionsplit || is_sectionsplit_output || file_has_dir)
        f = if use_sectionsplit_dir
              # For sectionsplit outputs, return just the basename
              # The directory will be applied during file_compile_format
              # via preserve_directory_structure?
              File.basename(ref.file)
            elsif file_has_dir
              ref.file # Preserve directory structure already in ref.file
            elsif ref.output_filename
              substitute_filename_pattern(ref.output_filename, **params)
            else File.basename(ref.file)
            end
        ref.attachment and f = ref.file
        @disambig.source2dest_filename(f)
      end

      def output_file_path_prep(ref, idx)
        b = File.basename(ref.file)
        b_no_ext = File.basename(ref.file, ".*")
        # Check for sectionsplit_filename (for both parent and split output files)
        # or output_filename
        custom_filename = ref.sectionsplit_filename || ref.output_filename
        has_custom_dir = custom_filename && File.dirname(custom_filename) != "."
        # Also check if ref.file itself contains a directory
        file_has_dir = File.dirname(ref.file) != "."
        params = { document_num: idx, basename: b_no_ext, basename_legacy: b }
        [has_custom_dir, file_has_dir, params]
      end

      def file_entry_copy(ref, ret)
        %w(attachment sectionsplit index presentation-xml url
           bare-after-first output_filename sectionsplit_filename
           sectionsplit_output).each do |s|
          ref.respond_to?(s.to_sym) and
            ret[s.delete("-").to_sym] = ref.send(s)
        end
      end

      def add_document_suffix(identifier, doc)
        document_suffix = Metanorma::Utils::to_ncname(identifier)
        ids = doc.xpath("./@id | .//@id").map(&:value)
        Util::anchor_id_attributes.each do |(tag_name, attr_name)|
          Util::add_suffix_to_attrs(doc, document_suffix, tag_name, attr_name,
                                    @isodoc)
        end
        Util::url_in_css_styles(doc, ids, document_suffix)
        doc.root["document_suffix"] ||= ""
        doc.root["document_suffix"] += document_suffix
      end

      # return citation url for file
      # @param doc [Boolean] I am a Metanorma document,
      # so my URL should end with html or pdf or whatever
      def url(ident, options)
        data = get(ident)
        data[:url] || targetfile(data, options)[1]
      end

      # return file contents + output filename for each file in the collection,
      # given a docref entry
      # @param data [Hash] docref entry
      # @param read [Boolean] read the file in and return it
      # @param doc [Boolean] I am a Metanorma document,
      # so my URL should end with html or pdf or whatever
      # @param relative [Boolean] Return output path,
      # formed relative to YAML file, not input path, relative to calling function
      # @return [Array<String, nil>]
      def targetfile(data, options)
        options = { read: false, doc: true, relative: false }.merge(options)
        path = options[:relative] ? data[:rel_path] : data[:ref]
        if data[:type] == "fileref"
          ref_file path, data[:out_path], options[:read], options[:doc]
        else
          xml_file data[:id], options[:read]
        end
      end

      def targetfile_id(ident, options)
        targetfile(get(ident), options)
      end

      def ref_file(ref, out, read, doc)
        file = File.read(ref, encoding: "utf-8") if read
        filename = out.dup
        if doc
          filename = ref_file_xml2html(filename)
        end
        [file, filename]
      end

      # Check if file has a recognized MIME type (other than XML)
      # If so, don't append .html (e.g., .svg, .png, .jpg, etc.)
      # Only process if it doesn't have a recognized non-XML extension
      # If filename ends in .xml, replace with .html
      # Otherwise (including sectionsplit files like "file.xml.0" or
      # custom titles), append .html
      def ref_file_xml2html(filename)
        unless Util::mime_file_recognised?(filename) &&
            !filename.end_with?(".xml")
          filename = if filename.end_with?(".xml")
                       filename.sub(/\.xml$/, ".html")
                     else "#{filename}.html"
                     end
        end
        filename
      end

      def xml_file(id, read)
        file = @xml.at(ns("//doc-container[@id = '#{id}']")).to_xml if read
        filename = "#{id}.html"
        [file, filename]
      end

      # map locality type and label (e.g. "clause" "1") to id = anchor for
      # a document
      # Note: will only key clauses, which have unambiguous reference label in
      # locality. Notes, examples etc with containers are just plunked against
      # UUIDs, so that their IDs can at least be registered to be tracked
      # as existing.
      def read_anchors(xml)
        xrefs = @isodoc.xref_init(@lang, @script, @isodoc, @isodoc.i18n,
                                  { locale: @locale })
        xrefs.parse xml
        xrefs.get.each_with_object({}) do |(k, v), ret|
          read_anchors1(k, v, ret)
        end
      end

      def read_anchors1(key, val, ret)
        val[:type] ||= "clause"
        ret[val[:type]] ||= {}
        index = if val[:container] || val[:label].nil? || val[:label].empty?
                  UUIDTools::UUID.random_create.to_s
                else val[:label].gsub(%r{<[^>]+>}, "")
                end
        ret[val[:type]][index] = key
        v = val[:value] and ret[val[:type]][v.gsub(%r{<[^>]+>}, "")] = key
      end

      # Also parse all ids in doc (including ones which won't be xref targets)
      def read_ids(xml)
        ret = {}
        xml.traverse do |x|
          x.text? and next
          x["id"] and ret[x["id"]] = true
        end
        ret
      # Check if we should preserve directory structure for an identifier
      # Returns the custom filename if directory structure should be preserved,
      # nil otherwise
      def preserve_directory_structure?(ident)
        ret = if get(ident, :sectionsplit_output)
                # For sectionsplit outputs, use rel_path which has the directory
                get(ident, :rel_path) || get(ident, :out_path)
              elsif get(ident, :sectionsplit)
                get(ident, :sectionsplit_filename)
              else get(ident, :output_filename)
              end
        # Return the custom filename only if it contains a directory
        ret && File.dirname(ret) != "." ? ret : nil
      end
    end
  end
end
