module Metanorma
  module Input
    class Base
      def process(_file, _filename, _type)
        raise "This is an abstract class"
      end
    end
  end
end
