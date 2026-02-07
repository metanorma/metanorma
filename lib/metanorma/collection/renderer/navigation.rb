module Metanorma
  class Collection
    class Renderer
      # @param elm [Nokogiri::XML::Element]
      # @return [String]
      def indexfile_title(entry)
        if entry.bibdata &&
            x = entry.bibdata.title.detect { |t| t.type == "main" } ||
                entry.bibdata.title.first
          x.title.content
        else
          entry.title
        end
      end

      # uses the identifier to label documents; other attributes (title) can be
      # looked up in @files[id][:bibdata]
      #
      # @param mnf [Collection::Manifest]
      # @param builder [Nokogiri::XML::Builder]
      def indexfile_docref(mnf, builder)
        Array(mnf.entry).detect(&:index) or return ""
        builder.ul { |b| docrefs(mnf, b) }
      end

      def docrefs(mnf, builder)
        ident = docref_ident(mnf)
        builder.li do |li|
          li.a href: index_link(mnf, ident) do |a|
            a << ident.split(/([<>&])/).map do |x|
              /[<>&]/.match?(x) ? x : @c.encode(x, :hexadecimal)
            end.join
          end
        end
      end

      def docref_ident(docref)
        ident = docref.identifier.dup
        @c.decode(@isodoc.docid_prefix(nil, ident))
      end

      # Check if file has a recognized MIME type (other than XML)
      # If so, don't append .html (e.g., .svg, .png, .jpg, etc.)
      def index_link(docref, ident)
        if docref.file
          out_path = @files.get(ident, :out_path)
          # Ensure the path ends with .html for documents, but not for recognized file types
          if Util::mime_file_recognised?(out_path) && !out_path.end_with?(".xml")
            # File has a recognized extension (like .svg, .png), keep it as is
            out_path
          elsif out_path.end_with?(".xml")
            out_path.sub(/\.xml$/, ".html")
          elsif out_path.end_with?(".html")
            out_path
          else
            "#{out_path}.html"
          end

        else "#{docref.id}.html"
        end
      end

      # single level navigation list, with hierarchical nesting
      def indexfile(mnf)
        mnfs = Array(mnf)
        mnfs.empty? and return ""
        mnfs.map { |m| "<ul>#{indexfile1(m)}</ul>" }.join("\n")
      end

      def index?(mnf)
        mnf.index and return true
        mnf.entry&.detect { |e| index?(e) }
      end

      def indexfile1(mnf)
        index?(mnf) or return ""
        cleanup_indexfile1(build_indexfile1(mnf))
      end

      def build_indexfile1(mnf)
        Nokogiri::HTML::Builder.new do |b|
          if mnf.file then docrefs(mnf, b)
          else
            b.li do |l|
              l << indexfile_title(mnf)
              l.ul do |u|
                Array(mnf.entry).each { |e| u << indexfile1(e) }
              end
            end
          end
        end
      end

      def cleanup_indexfile1(ret)
        ret = ret.doc.root
        ret.xpath("/ul").each do |u|
          if u.at("./li/ul") && !u.at("./li[text()]")
            u.replace(u.xpath("./li/ul"))
          end
        end
        ret.to_html
      end

      # object to construct navigation out of in Liquid
      def index_object(mnf)
        mnf = Array(mnf).first
        ret = { title: indexfile_title(mnf), level: mnf.type,
                docrefs: index_object_docrefs(mnf),
                children: index_object_children(mnf) }.compact
        ret.keys == [:children] and ret = ret[:children]
        ret
      end

      def index_object_children(mnf)
        nonfiles = Array(mnf.entry).reject(&:file)
        c = nonfiles.each_with_object([]) do |d, b|
          b << index_object(d)
        end.flatten
        c.empty? and c = nil
        c
      end

      def index_object_docrefs(mnf)
        files = Array(mnf.entry).select(&:file)
        files.empty? and return nil
        r = Nokogiri::HTML::Builder.new do |b|
          b.ul do |u|
            files.each { |f| docrefs(f, u) }
          end
        end
        r.doc.root&.to_html&.tr("\n", " ")
      end

      def liquid_docrefs(mnfs)
        Array(mnfs).select(&:index).each_with_object([]) do |d, m|
          if d.file
            ident = @c.decode(@isodoc.docid_prefix(nil, d.identifier.dup))
            m << { "identifier" => ident, "file" => index_link(d, ident),
                   "title" => indexfile_title(d), "level" => d.type }
          else
            liquid_docrefs(d.entry).each { |m1| m << m1 }
          end
        end
      end
    end
  end
end
