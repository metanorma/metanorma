require "lutaml/xml"

module Metanorma
  class Collection
    module Config
      class MetanormaCollectionNamespace < ::Lutaml::Xml::Namespace
        uri "http://metanorma.org"
        element_form_default :qualified
      end
    end
  end
end
