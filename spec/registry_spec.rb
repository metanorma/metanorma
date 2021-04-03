require_relative "spec_helper"

RSpec.describe Metanorma::Registry do
  it "has a registry" do
    class NewProcessor < Metanorma::Processor
      def initialize
        @short = :new
      end

      def output_formats
        { xyz: "xyz" }
      end
    end
    registry = Metanorma::Registry.instance
    registry.register(NewProcessor)
    expect(registry.find_processor(:new)).to be_instance_of NewProcessor
    expect(registry.supported_backends).to include :new
    expect(registry.processors[:new]).to be_instance_of NewProcessor
    expect(registry.output_formats[:new]&.to_s).to eq '{:xyz=>"xyz"}'
  end

  it "deals with multiple aliases" do
    class NewProcessor < Metanorma::Processor
      def initialize
        @short = %i[new new2]
      end

      def output_formats
        { xyz: "xyz" }
      end
    end
    registry = Metanorma::Registry.instance
    registry.register(NewProcessor)
    expect(registry.find_processor(:new)).to be_instance_of NewProcessor
    expect(registry.find_processor(:new2)).to be_instance_of NewProcessor
    expect(registry.supported_backends).to include :new
    expect(registry.supported_backends).to include :new2
    expect(registry.processors[:new]).to be_instance_of NewProcessor
    expect(registry.processors[:new2]).to be_instance_of NewProcessor
    expect(registry.output_formats[:new]&.to_s).to eq '{:xyz=>"xyz"}'
    expect(registry.output_formats[:new2]&.to_s).to eq '{:xyz=>"xyz"}'
  end

  it "warns when registered class is not a Metanorma processor" do
    registry = Metanorma::Registry.instance
    expect { registry.register(Metanorma) }.to raise_error(Error)
  end

  it "detects root tag of iso" do
    class NewProcessor < Metanorma::Processor
      def initialize
        @short = :iso
        @asciidoctor_backend = :iso
      end

      def output_formats
        { xyz: "xyz" }
      end
    end
    require "metanorma-iso"
    registry = Metanorma::Registry.instance
    registry.register(NewProcessor)
    expect(registry.root_tags[:iso]).to eq "iso-standard"
  end
end
