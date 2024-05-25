module Shale
  module Adapter
    module Nokogiri
      class Node
        def content
          @node
        end

        def to_xml
          @node.to_xml
        end
      end
    end
  end
end
