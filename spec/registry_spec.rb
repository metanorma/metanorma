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
    expect(registry.supported_backends).to eq [:new]
    expect(registry.processors[:new]).to be_instance_of NewProcessor
    expect(registry.output_formats.to_s).to eq "{:new=>{:xyz=>\"xyz\"}}"
  end

  it "warns when registered class is not a Metanorma processor" do
    registry = Metanorma::Registry.instance
    #expect{registry.register(Metanorma)}.to raise_error(Metanorma::Registry::Error) 
    expect{registry.register(Metanorma)}.to raise_error(Error) 
  end
end
