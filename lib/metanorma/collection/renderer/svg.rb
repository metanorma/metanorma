module Metanorma
  class Collection
    class Renderer
      SVG_NS = "http://www.w3.org/2000/svg".freeze
      XLINK_NS = "http://www.w3.org/1999/xlink".freeze

      class << self
        # Reference-type svgmap targets (eref[@bibitemid]) resolve to the
        # reference list. Where a flavor's references are ALSO declared as
        # page anchors, the flavor registers a resolver mapping its
        # reference identity to an anchor record; the registry is empty in
        # core, which carries no domain knowledge. A resolver receives
        # (reference_name, lookup) and returns an anchor record
        # ({ key:, id:, url: }) or nil; lookup maps a plain anchor base to
        # a record, edition-suffix chains included.
        def reference_anchor_resolvers
          @reference_anchor_resolvers ||= []
        end

        def register_reference_anchor_resolver(&resolver)
          reference_anchor_resolvers << resolver
        end
      end

      # Converts SVG images to data URIs for inline embedding
      def svg_datauri(docxml, docid)
        rel = @files.get(docid, :rel_path)
        parent = @files.get(docid, :parentid) and
          rel = @files.get(parent, :rel_path)
        # if sectionsplit, use orig file dir
        dir = File.join(@dirname, File.dirname(rel))
        datauri_encode(docxml, dir)
      end

      # Resolves SVG map references and processes SVG ID disambiguation.
      #
      # Delegates SVG manipulation to Vectory gem, which handles:
      # 1. Document-level suffixing for cross-document ID disambiguation
      # 2. Index-based suffixing for multiple svgmaps within one document
      # 3. Link remapping and SVG extraction
      #
      # Metanorma's role: State requirements and coordinate the workflow.
      # Vectory's role: Handle all SVG ID manipulation internally.
      #
      # @param docxml [Nokogiri::XML::Document] The document XML to process
      # @param docid [String] Document identifier for retrieving suffix
      # @param presxml [Boolean, nil] Whether this is presentation XML
      def svgmap_resolve(docxml, docid, presxml)
        ids, docxml, isodoc, tag = svgmap_resolve_prep(docxml, docid, presxml)

        # Stage 1: Resolve EREF references to their targets
        resolve_svgmap_erefs(docxml, tag, isodoc, ids, presxml)

        # Stage 1b: Re-key the svgmap xref targets that a reinflated render
        # carries from the staging build: they name anchors in the compile-
        # time document shape, which on a sectionsplit page sit behind this
        # render's suffix chain and possibly on a sibling member page.
        # Targets that resolve against the collection anchor index are
        # rewritten to links at the owning page, so Vectory maps the SVG
        # hotspots onto working addresses. A plain build skips this stage:
        # its targets are already in the form the rest of the pipeline
        # expects.
        @reinflate and resolve_svgmap_bare_targets(docxml, docid, ids)

        # Stage 2: Normalize prefixes (Vectory expects eref, not fmt-eref)
        normalize_svgmap_prefixes(docxml, ids)

        # Stage 3: Process with Vectory
        # Pass document suffix to Vectory as id_suffix for proper SVG ID disambiguation.
        # Vectory handles both id_suffix (document-level) and index suffix internally.
        # It parses its own copy and returns the processed document, so the
        # result must be adopted here or none of its work reaches the tree.
        doc_suffix = @files.get(docid, :document_suffix)
        mapped = Vectory::SvgMapping.new(docxml, "", id_suffix: doc_suffix).call
        docxml = Nokogiri::XML(mapped.to_xml, &:huge)

        # Stage 4: Extract processed SVG content
        extract_svgmap_content(docxml, isodoc)

        # Stage 5: Re-key hotspot anchors. Vectory remaps an SVG hotspot to
        # the value of its svgmap target, which names an anchor in the
        # compile-time document shape. On a sectionsplit page the declaration
        # carries this render's suffix chain and may live on a sibling
        # section page, so the fragment needs re-pointing at the member page
        # that owns it.
        @reinflate and svgmap_hotspot_rekey(docxml, docid)
        docxml
      end

      # Prepares document and context for svgmap resolution
      def svgmap_resolve_prep(docxml, docid, presxml)
        ids = @files.get(docid, :ids)
        docxml = svg_unnest(svg_datauri(docxml, docid))
        isodoc = IsoDoc::PresentationXMLConvert.new({})
        isodoc.bibitem_lookup(docxml)
        tag = presxml ? "fmt-eref" : "eref"
        [ids, docxml, isodoc, tag]
      end

      private

      # Resolves EREF elements within svgmap to their actual link targets
      def resolve_svgmap_erefs(docxml, tag, isodoc, ids, presxml)
        docxml.xpath(ns("//svgmap//#{tag}")).each do |e|
          svgmap_resolve_eref(e, isodoc, docxml, ids, presxml)
        end
      end

      # Converts fmt-eref/fmt-link/fmt-xref back to eref/link/xref
      # Vectory expects non-prefixed element names for proper processing
      def normalize_svgmap_prefixes(docxml, ids)
        svgmap_fmt_prefix_remove(docxml, ids)
      end

      # Extracts processed SVG content from svgmap elements
      def extract_svgmap_content(docxml, isodoc)
        docxml.xpath(ns("//svgmap")).each { |s| isodoc.svgmap_extract(s) }
      end

      # Converts Presentation XML fmt- prefix back to standard element names
      # Vectory expects eref/link/xref, not fmt-eref/fmt-link/fmt-xref.
      #
      # A target carrying an unresolved fmt-xref/fmt-eref companion next to a
      # resolvable bare node keeps the bare node: the companion is the
      # anchor-type xref the cross-reference machinery fell back to when it
      # could not resolve the reference (its target names a hidden bibitem,
      # not a page anchor), and replacing the target's children with it would
      # have Vectory remap the SVG hotspots to that dead anchor. Dropping the
      # companion leaves the bare eref/xref as the target, so an unresolved
      # svgmap keeps its wrapper (the figure renders once through its
      # extracted copy) and the hotspots are left untouched.
      def svgmap_fmt_prefix_remove(docxml, ids)
        docxml.xpath(ns("//svgmap/target")).each do |t|
          # A target Stage 1b already resolved to a link is final.
          t.at(ns("./link")) and next
          n = t.at(ns(".//fmt-link | .//fmt-xref | .//fmt-eref")) or next
          if n.name != "fmt-link" && t.at(ns("./eref | ./xref")) &&
              !ids&.key?(n["target"])
            svgmap_drop_unresolved_companion(n)
            next
          end
          n.name = n.name.sub(/^fmt-/, "")
          t.children = n
        end
      end

      # Remove the semx companion carrying +node+, leaving the target's bare
      # semantic child in place.
      def svgmap_drop_unresolved_companion(node)
        (sm = node.at("./ancestor::xmlns:semx")) and sm.remove
      end

      # Removes nested image elements within svgmap, flattening the structure
      def svg_unnest(docxml)
        docxml.xpath(ns("//svgmap//image[.//*[name() = 'image']]")).each do |i|
          s = i.elements.detect { |e| e.name == "svg" } and
            i.replace(s)
        end
        docxml
      end

      # Resolves a single EREF element to its target link
      def svgmap_resolve_eref(eref, isodoc, _docxml, ids, presxml)
        href = isodoc.eref_target(eref) or return
        href = href[:link]
        href == "##{eref['bibitemid']}" ||
          (href =~ /^#/ && !ids[href.sub(/^#/, "")]) and return
        eref["target"] = href.strip
        eref.name = presxml ? "fmt-link" : "link"
        eref.elements&.remove
      end

      # Re-key svgmap xref targets whose anchor lives outside the current
      # section page. The svg_xrefs pass composes these targets as
      # +<xref target='anchor_suffix'/>+ from the SVG hotspot hrefs, naming
      # the anchor in the compile-time document shape; on a sectionsplit page
      # the declaration carries this render's suffix chain and may live on a
      # sibling member page. Resolvable targets are rewritten to links at the
      # owning page, so Vectory maps the SVG hotspots onto working addresses;
      # unresolvable ones are left for Stage 2.
      def resolve_svgmap_bare_targets(docxml, docid, ids)
        idx = hotspot_anchor_index
        docxml.xpath(ns("//svgmap/target/xref")).each do |x|
          ids&.key?(x["target"]) and next
          t = x["target"]
          rec = idx[t] || idx[hotspot_anchor_base(t, docid)] or next
          href = hotspot_target_href(rec, docid) or next
          x.name = "link"
          x["target"] = href
        end
        # Reference-type targets (eref[@bibitemid]) resolve to the reference
        # list. Where a domain's references are ALSO declared as page
        # anchors, that domain registers a resolver mapping the reference
        # identity to an anchor record; core registers none and carries no
        # domain knowledge. Resolvers receive (reference_name, lookup),
        # where lookup maps a plain anchor base to a record.
        lookup = ->(base) { hotspot_prefix_lookup(idx, base) }
        docxml.xpath(ns("//svgmap/target/eref[@bibitemid]")).each do |e|
          rec = self.class.reference_anchor_resolvers.lazy.map do |resolver|
            resolver.call(e["bibitemid"], lookup)
          end.find(&:itself) or next
          href = hotspot_target_href(rec, docid) or next
          e.name = "link"
          e["target"] = href
          e.attribute_nodes.each { |at| at.remove unless at.name == "target" }
        end
      end

      # Rewrites the fragment hrefs of SVG hotspot anchors that do not
      # resolve on the current split-section page to the member page that
      # carries the declaration, with that page's full anchor id. Both
      # fragment-only (+#anchor+) and page-qualified (page.html#anchor)
      # hrefs are re-keyed; bare ordinal hrefs belong to the svgmap list
      # mapping and are left to the target machinery.
      def svgmap_hotspot_rekey(docxml, docid)
        idx = hotspot_anchor_index
        page_ids = docxml.xpath("//*[@id]")
          .each_with_object({}) { |e, m| m[e["id"]] = true }
        svg_ids = docxml.xpath("//m:svg//@id", "m" => SVG_NS)
          .each_with_object({}) { |n, m| m[n.value] = true }
        docxml.xpath("//m:svg//m:a[@href] | //m:svg//m:a[@xlink:href]",
                     "m" => SVG_NS, "xlink" => XLINK_NS).each do |a|
          attr = a.attribute("href") ? "href" : "xlink:href"
          split = hotspot_split_href(a[attr])
          next unless split
          page, frag = split
          if page.nil? && page_ids.key?(frag)
            # The id exists on this page, but Vectory left the href as a
            # bare relative name (no #): re-point it as the in-page anchor.
            a[attr] = "##{frag}" unless a[attr].start_with?("#")
            next
          end
          base = hotspot_anchor_base(frag, docid)
          # An SVG element id in this document: anchor the hotspot in-page.
          in_page = if svg_ids.key?(frag)
            frag
          else
            svg_ids.keys.find { |i| i.start_with?("#{base}_") }
          end
          if in_page
            a[attr] = "##{in_page}"
            next
          end
          rec = idx[frag] || idx[base] ||
            hotspot_prefix_lookup(idx, base)
          unless rec
            # Unresolvable bare name: a dead link (relative file or
            # dangling fragment) is worse than no link; drop the href.
            a.remove_attribute(attr)
            next
          end
          href = hotspot_target_href(rec, docid) or next
          href = "#{page}#{href}" if page && rec[:key] == docid
          a[attr] = href unless href == a[attr]
        end
      end

      # Split an href into [relative page or nil, fragment]; bare values are
      # treated as fragments, except ordinals, which are not anchors.
      def hotspot_split_href(href)
        return nil if href.nil? || href.empty? || /\A\d+\z/.match?(href)

        return [nil, href] unless (m = href.match(/\A([^#]*)#(.+)\z/))

        [m[1].empty? ? nil : m[1], m[2]]
      end

      # Reduce a fragment carrying document-suffix chains or the sectionsplit
      # indirect key to its base anchor id, by iteratively stripping the
      # NCName suffixes of the collection's member keys.
      def hotspot_anchor_base(frag, docid)
        frag = frag.to_s.sub(/\A#/, "")
        if (key = @files.get(docid, :indirect_key))
          frag = frag.sub(/^#{Regexp.escape(key)}_/, "")
        end
        suffixes = hotspot_anchor_suffixes
        loop do
          s = suffixes.find { |x| frag.end_with?("_#{x}") } or break
          frag = frag[0...(-1 * (s.size + 1))]
        end
        frag
      end

      # NCName suffixes that link anchors in this render may carry, longest
      # first: the keys of the collection's members and split outputs, which
      # compose the render's suffix chains, plus the suffix the staging
      # build stamped the stored documents with (captured before the
      # reinflate suffix swap re-keys the ids; the SVG hotspot hrefs are not
      # ids and so keep the stored flavour).
      def hotspot_anchor_suffixes
        @hotspot_anchor_suffixes ||= begin
          keys = @files.keys
            .reject { |k| @files.get(k, :attachment) }
            .map { |k| Metanorma::Utils::to_ncname(k) }
          keys << @svgmap_stored_suffix if @svgmap_stored_suffix
          keys.uniq.sort_by(&:length).reverse
        end
      end

      # base anchor id => { key, id, url } for every member of the
      # collection; ambiguous bases (the same base resolving to different
      # final ids) map to nil. Split outputs register their render-time
      # suffix chain (parent suffix + split-instance key), mirroring the
      # swap_document_suffix + add_document_suffix discipline; other members
      # register their stored ids untouched, which is what reinflation
      # renders them with.
      def hotspot_anchor_index
        @hotspot_anchor_index ||= build_hotspot_anchor_index
      end

      def build_hotspot_anchor_index
        idx = {}
        @files.keys.each do |key|
          # Attachments carry no pages; a sectionsplit parent has no page of
          # its own -- its content lives on the split outputs, whose ids are
          # indexed instead.
          @files.get(key, :attachment) and next
          @files.get(key, :sectionsplit) and next
          ids = @files.get(key, :ids) or next
          pid = @files.get(key, :parentid)
          url = @files.url(key, relative: true, doc: true)
          ids.each_key do |id|
            # The split outputs carry this render's parent suffix (the
            # pre-split pass re-keys the stored ids to it); other members
            # carry their identifier suffix. The base is the anchor without
            # that suffix; the final id is what the render's suffix
            # discipline produces on the page.
            base = if pid
              id.sub(/_#{Regexp.escape(Metanorma::Utils::to_ncname(pid))}\z/,
                     "")
            else
              id.sub(/_#{Regexp.escape(Metanorma::Utils::to_ncname(key))}\z/,
                     "")
            end
            final = if pid
              "#{id}_#{Metanorma::Utils::to_ncname(key)}"
            else
              id
            end
            if !idx.key?(base)
              idx[base] = { key: key, id: final, url: url }
            elsif idx[base] && idx[base][:id] != final
              idx[base] = nil
            end
          end
        end
        idx
      end

      # The member page's URL relative to the page being rendered; the index
      # stores it collection-root-relative.
      def hotspot_relative_url(url, docid)
        @hotspot_rel_urls ||= {}
        @hotspot_rel_urls[[url, docid]] ||= begin
          cur = referencing_html_location(docid, false)
          cur ? make_relative_path(cur, url) : url
        end
      end

      # Address of the anchor record from the page being rendered.
      def hotspot_target_href(rec, docid)
        rec[:key] == docid and return "##{rec[:id]}"
        rec[:url] or return nil
        "#{hotspot_relative_url(rec[:url], docid)}##{rec[:id]}"
      end

      # Exact base first, then a unique prefix match: a declaration id
      # carries the owning member's edition suffix chain behind the plain
      # name (geometry_schema.cartesian_point_ISO_10303-42_2025_...), so
      # the plain name resolves by prefix. Multiple equal-length matches
      # are ambiguous and refuse, as do differing ids at the same key.
      def hotspot_prefix_lookup(idx, prefix)
        return idx[prefix] if idx[prefix]

        candidates = idx.select { |k, r| r && k.start_with?("#{prefix}_") }
        return nil if candidates.empty?

        shortest = candidates.min_by { |k, _| k.length }
        ties = candidates.count { |k, _| k.length == shortest[0].length }
        ties == 1 ? shortest[1] : nil
      end
    end
  end
end
