require "lutaml/model"
require_relative "namespaces"

module Metanorma
  class Collection
    module Config
      # Serializable wrapper for a single <doc-container> element.
      #
      # The body of a doc-container is the inline presentation XML of an
      # individual document, in a flavour-specific namespace (e.g. bipm,
      # iso, ietf). We round-trip it as an opaque string via `map_all`
      # so the underlying XML adapter (Nokogiri) preserves the inner xmlns
      # declaration; if we let lutaml-model parse the body into typed
      # children it would lose the inner namespace.
      class DocContainer < ::Lutaml::Model::Serializable
        attribute :id, :string
        attribute :content, :string

        xml do
          element "doc-container"
          namespace MetanormaCollectionNamespace
          map_attribute "id", to: :id
          map_all to: :content
        end
      end
    end
  end
end
