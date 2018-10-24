
module Metanorma
  module Input

    class Base

      def process(file, filename, type)
        raise "This is an abstract class"
      end

    end
  end
end
