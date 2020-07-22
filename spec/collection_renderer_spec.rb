# frozen_string_literal: true

RSpec.describe Metanorma::CollectionRenderer do
  it 'Render HTML & build DOC, PDF, XML files from XML collection' do # rubocop:disable Metrics/BlockLength
    file = 'spec/fixtures/collection/collection1.xml'
    xml = File.read file, encoding: 'UTF-8'
    of = 'spec/fixtures/ouput'
    Metanorma::CollectionRenderer.render(
      xml, File.dirname(file),
      format: %i[html pdf xml doc],
      output_folder: of,
      coverpage: 'spec/fixtures/collection/collection_cover.html'
    )
    expect(File.exist?('spec/fixtures/ouput/index.html')).to be true
    expect(File.read('spec/fixtures/ouput/index.html', encoding: 'UTF-8'))
      .to include '<h1>ISO Collection 1</h1>'
    expect(File.exist?('spec/fixtures/ouput/dummy.html')).to be true
    expect(File.exist?('spec/fixtures/ouput/dummy.doc')).to be true
    expect(File.exist?('spec/fixtures/ouput/dummy.pdf')).to be true
    expect(File.exist?('spec/fixtures/ouput/dummy.xml')).to be true
    expect(File.exist?('spec/fixtures/ouput/rice-amd.final.html')).to be true
    expect(File.exist?('spec/fixtures/ouput/rice-amd.final.doc')).to be true
    expect(File.exist?('spec/fixtures/ouput/rice-amd.final.pdf')).to be true
    expect(File.exist?('spec/fixtures/ouput/rice-amd.final.xml')).to be true
    expect(File.exist?('spec/fixtures/ouput/rice-en.final.html')).to be true
    expect(File.exist?('spec/fixtures/ouput/rice-en.final.doc')).to be true
    expect(File.exist?('spec/fixtures/ouput/rice-en.final.pdf')).to be true
    expect(File.exist?('spec/fixtures/ouput/rice-en.final.xml')).to be true
    expect(File.exist?('spec/fixtures/ouput/rice1-en.final.html')).to be true
    expect(File.exist?('spec/fixtures/ouput/rice1-en.final.doc')).to be true
    expect(File.exist?('spec/fixtures/ouput/rice1-en.final.pdf')).to be true
    expect(File.exist?('spec/fixtures/ouput/rice1-en.final.xml')).to be true
    FileUtils.rm_rf of
  end

  it 'raise ArgumentError if format is not specified' do
    file = 'spec/fixtures/collection/collection1.xml'
    xml = File.read file, encoding: 'UTF-8'
    expect do
      Metanorma::CollectionRenderer.render(xml, filename: file)
    end.to raise_error ArgumentError
  end

  it 'raise ArgumentError if format is HTML & coverpage not specified' do
    file = 'spec/fixtures/collection/collection1.xml'
    xml = File.read file, encoding: 'UTF-8'
    of = 'spec/fixtures/ouput'
    expect do
      Metanorma::CollectionRenderer.render(
        xml, filename: file, format: [:html], output_folder: of
      )
    end.to raise_error ArgumentError
  end
end
