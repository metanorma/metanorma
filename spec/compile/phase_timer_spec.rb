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

  it "yields without logging when disabled" do
    allow(Metanorma::Util).to receive(:log)
    timer = described_class.new(false)
    expect(timer.time("x") { 42 }).to eq 42
    timer.report
    expect(Metanorma::Util).not_to have_received(:log)
  end

  it "logs one info line per phase and a total when enabled" do
    lines = []
    allow(Metanorma::Util).to receive(:log) { |msg, type| lines << [msg, type] }
    timer = described_class.new(true)
    expect(timer.time("semantic") { :ok }).to eq :ok
    timer.report
    expect(lines.map(&:last)).to eq %i[info info]
    expect(lines.first.first).to match(/Timing: semantic: \d+\.\d{3}s/)
    expect(lines.last.first).to match(/Timing: total: \d+\.\d{3}s/)
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
      lines = []
      allow(Metanorma::Util).to receive(:log).and_wrap_original do |m, *args|
        lines << args.first
        m.call(*args)
      end
      Metanorma::Compile.new.compile(
        input, { type: "iso", output_dir: dir, install_fonts: false,
                 extension_keys: %i[xml presentation html doc] }.merge(options)
      )
      lines.grep(/Timing:/)
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
