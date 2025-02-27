module Metanorma
  class Compile
    class OutputFilename
      def initialize(source_filename, output_dir = nil, processor = nil)
        @source_filename = source_filename
        @output_dir = output_dir
        @processor = processor
      end

      def semantic_xml
        with_extension("xml")
      end

      def presentation_xml
        with_extension("presentation.xml")
      end

      def for_format(format)
        ext = @processor&.output_formats&.[](format)
        ext ? with_extension(ext) : nil
      end

      def with_extension(ext)
        base = change_output_dir
        base.sub(/\.[^.]+$/, ".#{ext}")
      end

      private

      def change_output_dir
        if @output_dir
          File.join(@output_dir, File.basename(@source_filename))
        else
          @source_filename
        end
      end
    end
  end
end
