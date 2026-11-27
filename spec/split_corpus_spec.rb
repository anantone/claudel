# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require_relative '../script/split_corpus'

RSpec.describe SplitCorpus do
  it '--poems N coupe aux suites d’au moins N lignes vides (pas aux plus courtes)' do
    text = "a\n\nb\n\n\nc\n\n\n\nd\ne\n"
    expect(described_class.units(text, mode: :poems, n: 3)).to eq([%w[a b c], %w[d e]])
  end

  it '--blocks N découpe en blocs pleins, après le titre (--skip-title)' do
    text = (['Titre'] + (1..7).map { |i| "v#{i}" }).join("\n")
    expect(described_class.units(text, mode: :blocks, n: 3, skip_title: true))
      .to eq([%w[v1 v2 v3], %w[v4 v5 v6]])
  end

  it 'écrit une unité par fichier et applique --exclude' do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'piece.txt'), "T\nv1\nv2\nv3\nv4\n")
      File.write(File.join(dir, 'piece-64.txt'), "T\nx1\nx2\n")
      out = File.join(dir, 'out')
      argv = ['--blocks', '2', '--skip-title', '--exclude', '-\d\d\.txt\z', '-o', out, *Dir["#{dir}/*.txt"]]
      expect { described_class.run(argv) }.to output(/1 sources -> 2 unités/).to_stdout
      expect(Dir.children(out).sort).to eq(%w[piece-001.txt piece-002.txt])
      expect(File.read(File.join(out, 'piece-002.txt'))).to eq("v3\nv4\n")
    end
  end
end
