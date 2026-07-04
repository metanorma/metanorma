# frozen_string_literal: true

require "fileutils"
require "digest"

module Metanorma
  class Collection
    # Durable, content-addressed store for staged collection-build artefacts.
    #
    # Enables incremental (batched) builds and resumption across runs: an
    # artefact is named +<docid-slug>.<content-hash>.<stage>.<format>+, so a
    # document already built with identical inputs is detected by filename alone
    # and reused, and an interrupted run resumes by recomputing which artefacts
    # are already present.
    #
    # Reuse is keyed on the caller-supplied content hash of the document's
    # *input closure* (source + resolved includes + templates + referenced
    # schemas + tool versions + options) -- never on file presence alone. See
    # metanorma/iso-10303#455 for why presence-keyed reuse of compiled XML is
    # unsound; the store deliberately requires a content hash it does not infer.
    #
    # Disabled by default: the collection renderer uses NullArtifactStore unless
    # an incremental build is explicitly requested (opt-in, never default).
    class ArtifactStore
      DEFAULT_DIRNAME = ".metanorma-collection-cache"

      # The artefact-stage vocabulary, and the one non-redundant property each
      # stage carries: the format it is serialised as (also its file extension).
      # THIS IS ITS HOME: every producer and consumer names its stage from this
      # table by symbol, never a bare string literal elsewhere; an unknown stage
      # raises (KeyError via +fetch+), so the vocabulary cannot drift outside
      # this file. The stage's *name* is the filename token, so it is not stored
      # here -- that would just restate the key. The stages trace the pipeline
      # (isolated compile -> index -> reinflate); each role is documented inline:
      STAGE_FORMATS = {
        # Compiled Semantic XML, unresolved cross-document repo:() references
        # PRESERVED as deterministic stubs (neither stripped nor resolved). The
        # unit of an isolated per-document compile; a pure function of the
        # document's input closure, hence content-addressable and reusable.
        semantic: "xml",
        # This document's contribution to the global anchor index: its anchors
        # and ids (type => {label/UUID => anchor-id}). Aggregated across all
        # documents to build the anchor -> owning-document index used at
        # reinflation.
        anchors: "json",
        # Reinflated Presentation XML: the preserved stubs resolved against the
        # global index into real cross-document links. Shared source for the PDF
        # and Word collection outputs, and per-document for HTML.
        presentation: "xml",
      }.freeze

      attr_reader :dir

      def initialize(dir)
        @dir = dir
        FileUtils.mkdir_p(@dir)
      end

      # <docid-slug>.<content-hash>.<stage>.<format>
      # +stage+ must be a key of STAGE_FORMATS; an unknown stage raises KeyError.
      def path(docid, content_hash, stage)
        format = STAGE_FORMATS.fetch(stage)
        File.join(@dir, "#{slug(docid)}.#{content_hash}.#{stage}.#{format}")
      end

      # Is this exact (document, input-closure, stage) artefact already present?
      # This is the resumption / skip predicate: a hit is byte-identical to a
      # fresh build because the hash covers every input that determines output.
      def key?(docid, content_hash, stage)
        File.exist?(path(docid, content_hash, stage))
      end

      def read(docid, content_hash, stage)
        f = path(docid, content_hash, stage)
        File.exist?(f) ? File.read(f, encoding: "UTF-8") : nil
      end

      # Idempotent write: the same (docid, content_hash, stage) always maps to
      # the same path and the content is a pure function of the hash, so a re-run
      # overwrites with identical bytes -- no side effects on repeat.
      def write(docid, content_hash, stage, content)
        f = path(docid, content_hash, stage)
        File.write(f, content, encoding: "UTF-8")
        f
      end

      # SHA256 over the input closure. Each input is hashed to a fixed-width
      # digest and the digests concatenated before the final hash, so no two
      # distinct closures collide regardless of input content or separators. The
      # caller assembles the closure; the store does not infer it.
      def self.content_hash(*inputs)
        digests = inputs.map { |i| Digest::SHA256.hexdigest(i.to_s) }
        Digest::SHA256.hexdigest(digests.join)
      end

      private

      def slug(docid)
        docid.to_s.gsub(/[^A-Za-z0-9._-]+/, "-")
          .gsub(/-{2,}/, "-").gsub(/\A-|-\z/, "")
      end
    end

    # Null object: the store disabled (the default). Never reports a hit, never
    # writes. Lets the renderer treat "no incremental build" as the no-store
    # path without a conditional at every call site (open/closed).
    class NullArtifactStore
      def path(*_args) = nil
      def key?(*_args) = false
      def read(*_args) = nil
      def write(*_args) = nil
    end
  end
end
