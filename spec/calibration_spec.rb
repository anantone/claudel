# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe Claudel::Calibration do
  let(:corpus) do
    [
      [fake_analysis(%w[la bɛl], %w[pa bel]), fake_analysis(%w[ʁɛ bɛl], %w[ʁo bel])],
      [fake_analysis(%w[ʁɛʃ ʃɛʁ], %w[pa bel])],
      [fake_analysis(%w[la bɛ ʁo zi], %w[pa bel ro zi]), fake_analysis(%w[mi nu], %w[mi nu])]
    ]
  end
  let(:results) { corpus.map { |poem| Claudel.score(poem) } }
  let(:calibration) { described_class.fit(results) }

  it 'retient moyenne et écart-type (population) de la densité de chaque critère' do
    densities = results.map { |r| r.criteria[:repetition_positionnelle][:density] }
    mean = densities.sum / densities.size
    sd = Math.sqrt(densities.sum { |d| (d - mean)**2 } / densities.size)
    expect(calibration.n).to eq(3)
    expect(calibration.stats.keys).to match_array(Claudel::Criteria.all.map(&:key))
    expect(calibration.stats[:repetition_positionnelle][:mean]).to be_within(1e-12).of(mean)
    expect(calibration.stats[:repetition_positionnelle][:sd]).to be_within(1e-12).of(sd)
  end

  it 'ignore les poèmes sans phones, refuse un corpus vide' do
    with_empty = results + [Claudel.score([])]
    expect(described_class.fit(with_empty).stats).to eq(calibration.stats)
    expect { described_class.fit([Claudel.score([])]) }.to raise_error(ArgumentError, /corpus vide/)
  end

  it 'centre-réduit une densité ; 0 si le critère est constant sur le corpus' do
    stats = { a: { mean: 0.2, sd: 0.05 }, b: { mean: 0.1, sd: 0.0 } }
    cal = described_class.new(stats: stats, n: 2, settings: {})
    expect(cal.standardize(:a, 0.3)).to be_within(1e-12).of(2.0)
    expect(cal.standardize(:b, 0.5)).to eq(0.0)
    expect { cal.standardize(:zzz, 0.1) }.to raise_error(ArgumentError, /zzz absent/)
  end

  it 'se sauve et se recharge à l’identique, réglages compris (symboles inclus)' do
    config = { proximity_lambda: 60.0, unit_weights: { inversee: :length }, weights: { patterns_rythmiques: 2.0 } }
    cal = described_class.fit(results, config: config)
    expect(cal.settings).not_to have_key(:weights) # les poids ne changent pas les densités
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'cal.json')
      cal.save(path)
      loaded = described_class.load(path)
      expect(loaded.stats).to eq(cal.stats)
      expect(loaded.n).to eq(3)
      expect(loaded.matches?(config)).to be(true)
      expect(loaded.matches?(config.merge(weights: {}))).to be(true)
      expect(loaded.matches?({ proximity_lambda: 40.0 })).to be(false)
    end
  end

  it 'enregistre les réglages effectifs, défauts compris (un défaut modifié invalide la calibration)' do
    expect(calibration.settings).to include(rhyme_plateau: 3, proximity_lambda: 40.0)
    stale = described_class.new(stats: calibration.stats, n: 3, settings: calibration.settings.except(:rhyme_lambda))
    expect(stale.matches?({})).to be(false)
  end

  it 'la calibration de référence livrée correspond aux réglages par défaut' do
    reference = described_class.reference
    expect(reference.n).to eq(104)
    expect(reference.stats.keys).to match_array(Claudel::Criteria.all.map(&:key))
    expect(reference.matches?({})).to be(true) # sinon : régénérer data/calibration.json
  end

  it 'refuse un fichier de calibration invalide' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'cal.json')
      File.write(path, '{"n": 3}')
      expect { described_class.load(path) }.to raise_error(ArgumentError, /calibration invalide/)
      File.write(path, 'pas du json')
      expect { described_class.load(path) }.to raise_error(ArgumentError, /calibration invalide/)
    end
  end

  describe 'Claudel.score avec config[:calibration]' do
    it 'combine les densités standardisées (poids égaux -> moyenne des z)' do
      result = Claudel.score(corpus.first, config: { calibration: calibration })
      z = result.criteria.values.map { |c| c[:standardized] }
      expect(result.calibrated).to be(true)
      expect(z).to all(be_a(Float))
      expect(result.score).to be_within(1e-12).of(z.sum / z.size)
    end

    it 'respecte les poids sur les z' do
      config = { calibration: calibration, weights: { repetition_generale: 0.0, patterns_rythmiques: 0.0 } }
      result = Claudel.score(corpus.first, config: config)
      expect(result.score).to be_within(1e-12).of(result.criteria[:repetition_positionnelle][:standardized])
    end

    it 'centre le corpus de calibration : score moyen ≈ 0' do
      scores = corpus.map { |poem| Claudel.score(poem, config: { calibration: calibration }).score }
      expect(scores.sum / scores.size).to be_within(1e-12).of(0.0)
    end

    it 'sans calibration : densités brutes, standardized nil' do
      result = Claudel.score(corpus.first)
      expect(result.calibrated).to be(false)
      expect(result.criteria.values.map { |c| c[:standardized] }).to all(be_nil)
    end
  end
end
