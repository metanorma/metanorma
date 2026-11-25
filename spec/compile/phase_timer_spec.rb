require "spec_helper"
require "tmpdir"

RSpec.describe Metanorma::Compile::PhaseTimer do
  describe ".enabled?" do
    around do |example|
      saved = ENV.fetch("METANORMA_PROFILE", nil)
      example.run
    ensure
      ENV["METANORMA_PROFILE"] = saved
    end

    it "is off by default" do
      ENV.delete("METANORMA_PROFILE")
      expect(described_class.enabled?({})).to be false
    end

    it "is on with METANORMA_PROFILE set" do
      ENV["METANORMA_PROFILE"] = "1"
      expect(described_class.enabled?({})).to be true
    end

    it "treats 0 and false as off" do
      %w[0 false].each do |v|
        ENV["METANORMA_PROFILE"] = v
        expect(described_class.enabled?({})).to be false
      end
    end

    it "lets the :profile option override the environment" do
      ENV["METANORMA_PROFILE"] = "1"
      expect(described_class.enabled?(profile: false)).to be false
      ENV.delete("METANORMA_PROFILE")
      expect(described_class.enabled?(profile: true)).to be true
    end
  end

  it "prints nothing when disabled" do
    timer = described_class.new(false)
    expect do
      expect(timer.time("x") { 42 }).to eq 42
      timer.report
    end.not_to output.to_stdout
  end

  it "prints one line per phase and a total when enabled" do
    timer = described_class.new(true)
    expect do
      expect(timer.time("semantic") { :ok }).to eq :ok
      timer.report
    end.to output(
      /Timing: semantic: \d+\.\d{3}s\n.*Timing: total: \d+\.\d{3}s\n/m,
    ).to_stdout
  end

  it "prints under the default log configuration, which excludes :info" do
    expect(Metanorma.configuration.logs).not_to include(:info)
    timer = described_class.new(true)
    expect { timer.time("semantic") { :ok } }
      .to output(/Timing: semantic: /).to_stdout
  end

  describe "Compile with a minimal ISO document" do
    let(:dir) { Dir.mktmpdir }
    let(:input) do
      File.join(dir, "doc.adoc").tap do |f|
        File.write(f, <<~ADOC)
          = Document title
          Author
          :docfile: doc.adoc
          :nodoc:
          :no-isobib:

          == Scope

          Text.
        ADOC
      end
    end

    after { FileUtils.remove_entry(dir) }

    def compile_logs(options)
      out = StringIO.new
      saved = $stdout
      $stdout = out
      begin
        Metanorma::Compile.new.compile(
          input,
          { type: "iso", output_dir: dir, install_fonts: false,
            extension_keys: %i[xml presentation html doc] }.merge(options),
        )
      ensure
        $stdout = saved
      end
      out.string.lines.grep(/Timing:/)
    end

    it "logs semantic, presentation, each format and total when on" do
      lines = compile_logs(profile: true)
      %w[semantic relaton/extract presentation html doc total].each do |phase|
        expect(lines).to include(a_string_matching(/Timing: #{phase}: /))
      end
    end

    it "logs no timing lines when off" do
      expect(compile_logs(profile: false)).to be_empty
    end
  end
end
