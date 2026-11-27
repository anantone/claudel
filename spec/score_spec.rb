# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Claudel do
  let(:poem) { [fake_analysis(%w[la bɛl], %w[pa bel]), fake_analysis(%w[la bɛl], %w[pa bel])] }

  it 'calcule un score global pondéré, normalisé par le nombre de phones' do
    result = described_class.score(poem)
    expect(result.verses).to eq(2)
    expect(result.total_phones).to eq(10)
    expect(result.criteria.keys).to contain_exactly(
      :repetition_generale, :repetition_positionnelle, :patterns_rythmiques
    )
    expected = result.criteria.values.sum { |c| c[:weight] * c[:density] } /
               result.criteria.values.sum { |c| c[:weight] }
    expect(result.score).to be_within(1e-9).of(expected)
    expect(result.score).to be >= 0.0
  end

  it 'respecte les poids passés en config (poids 0 -> critère exclu)' do
    config = { weights: { repetition_generale: 0.0, repetition_positionnelle: 0.0, patterns_rythmiques: 0.0 } }
    expect(described_class.score(poem, config: config).score).to eq(0.0)
    only_pos = { weights: { repetition_generale: 0.0, patterns_rythmiques: 0.0 } }
    result = described_class.score(poem, config: only_pos)
    expect(result.score).to be_within(1e-9).of(result.criteria[:repetition_positionnelle][:density])
  end

  it 'accepte des vers (String) et les scansionne' do
    result = described_class.score(['la substance de mort s additionne au vécu'], mode: :contemporain)
    expect(result.verses).to eq(1)
    expect(result.total_phones).to be_positive
    expect(result.score).to be_positive
  end

  it 'transporte les répétitions détaillées dans le résultat (pas de double calcul côté CLI)' do
    result = described_class.score(poem)
    reps = result.criteria[:repetition_generale][:repetitions]
    expect(reps.sum(&:total)).to be_within(1e-9).of(result.criteria[:repetition_generale][:raw])
    expect(result.criteria[:patterns_rythmiques][:repetitions]).to be_nil # pas d'explain
  end
end

RSpec.describe 'explain (rapport détaillé des répétitions)' do
  let(:poem) { [fake_analysis(%w[ʁɛʃ ʃɛʁ], %w[pa bel])] }

  it 'RepetitionGenerale.explain : total == raw_score, trié par total décroissant' do
    reps = Claudel::Criteria::RepetitionGenerale.explain(poem)
    expect(reps.sum(&:total)).to be_within(1e-9).of(Claudel::Criteria::RepetitionGenerale.raw_score(poem))
    expect(reps.map(&:total)).to eq(reps.map(&:total).sort.reverse)
    expect(reps.map { |r| [r.type, r.form] }).to contain_exactly([:phone, 'ʁ'], [:phone, 'ɛ'], [:phone, 'ʃ'])
    expect(reps.sum { |r| r.occurrences.size }).to eq(6) # 3 unités × 2 occurrences
  end

  it 'RepetitionGenerale.explain : ex aequo départagés par type puis forme (ordre stable)' do
    tied = [fake_analysis(%w[ba ba], %w[xx yy])] # b et a : même distance -> même total
    reps = Claudel::Criteria::RepetitionGenerale.explain(tied, unit_weights: { voyelle: 1.0, consonne: 1.0 })
    phones = reps.select { |r| r.type == :phone }
    expect(phones.map(&:total).uniq.size).to eq(1)
    expect(phones.map(&:form)).to eq(%w[a b])
  end

  it 'RepetitionPositionnelle.explain : paires avec classe de position et poids retenu' do
    rhyme_poem = [fake_analysis(%w[la bɛl], %w[pa bel]), fake_analysis(%w[ʁɛ bɛl], %w[ʁo bel])]
    reps = Claudel::Criteria::RepetitionPositionnelle.explain(rhyme_poem)
    expect(reps.size).to eq(1)
    expect(reps.first.form).to eq('bɛl')
    expect(reps.first.total).to be_within(0.001).of(3.0)
    expect(reps.first.pairs.first[:weight]).to eq(1.0)
    expect(reps.first.occurrences.map(&:klass)).to eq(%i[fin_de_vers fin_de_vers])
  end
end

samples_dir = File.expand_path('../../../samples', __dir__) # poems/ruby/samples (hors dépôt)

RSpec.describe 'échantillons poems/ruby/samples', if: File.directory?(samples_dir) do
  define_method(:sample_score) do |name|
    lines = File.readlines(File.join(samples_dir, name), chomp: true).map(&:strip).reject(&:empty?)
    Claudel.score(lines)
  end

  it 'dioptre4.txt est plus dense que 2008-11-13-personal-data.txt, surtout en positionnel' do
    dioptre = sample_score('dioptre4.txt')
    personal = sample_score('2008-11-13-personal-data.txt')
    expect(dioptre.score).to be > personal.score
    expect(dioptre.criteria[:repetition_positionnelle][:raw])
      .to be > personal.criteria[:repetition_positionnelle][:raw]
  end
end
