require "spec_helper"

RSpec.describe Metanorma::Config do
  before { restore_to_default_config }
  after { restore_to_default_config }

  describe ".configure" do
    it "allows us to set our configuration" do
      logs_types = ["warning", :error]

      Metanorma.configuration.logs = logs_types

      expect(Metanorma.configuration.logs).to eq(logs_types)
    end
  end

  def restore_to_default_config
    Metanorma.configuration.logs = [:warning, :error]
  end
end
