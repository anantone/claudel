# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'

RSpec.describe Claudel::Criteria do
  it 'enregistre les trois critères' do
    expect(described_class.all.map(&:name)).to contain_exactly(
      :repetition_generale, :repetition_positionnelle, :patterns_rythmiques
    )
  end
end

RSpec.describe Claudel::Criteria::RepetitionGenerale do
  let(:poem) { [fake_analysis(%w[ʁɛʃ ʃɛʁ], %w[pa bel])] }

  # proximité(d) = (d/(d+2)) · e^(−d/40)
  def prox(distance)
    (distance / (distance + 2.0)) * Math.exp(-distance / 40.0)
  end

  # poids explicites avec toutes les classes de phones actives
  let(:weights_phones) do
    { unit_weights: { phone: 1.0, voyelle: 1.0, consonne: 1.0, syllabe: 1.5, inversee: :length } }
  end

  it 'distingue assonance (voyelle) et allitération (consonne) au niveau phone' do
    weights = described_class::DEFAULTS[:unit_weights]
    expect(weights[:consonne]).to eq(0.0) # allitération : 0 par défaut
    expect(weights[:voyelle]).to be > weights[:consonne] # assonance valorisée
    # poème ʁɛʃ/ʃɛʁ : seules les voyelles comptent par défaut (ɛ en [1,4], d=3)
    expect(described_class.raw_score(poem)).to be_within(0.001).of(weights[:voyelle] * prox(3))
    expect(described_class.raw_score(poem, **weights_phones)).to be > described_class.raw_score(poem)
  end

  it 'compte k−1 répétitions pondérées par la distance absolue en phones' do
    # phones ʁ[0,5] d=5, ɛ[1,4] d=3, ʃ[2,3] d=1 ; syllabes/inversées : 1 occurrence -> 0
    expect(described_class.raw_score(poem, **weights_phones))
      .to be_within(0.001).of(prox(5) + prox(3) + prox(1))
  end

  it 'pénalise une répétition venant du même mot (×0.1)' do
    distinct = [fake_analysis(%w[ʁa ʁa], %w[aa bb])]
    same = [fake_analysis(%w[ʁa ʁa], %w[aa aa])]
    # unités : phone ʁ d=2, phone a d=2, syllabe ʁa (1.5) d=2, inversée aʁ (2.0) d=2
    expected = (1.0 + 1.0 + 1.5 + 2.0) * prox(2)
    expect(described_class.raw_score(distinct, **weights_phones)).to be_within(0.001).of(expected)
    expect(described_class.raw_score(same, **weights_phones)).to be_within(0.001).of(expected * 0.1)
  end

  it 'proximité pénalise le trop proche et décroît au loin' do
    cfg = described_class::DEFAULTS
    expect(described_class.proximite(1, cfg)).to be < described_class.proximite(9, cfg)
    expect(described_class.proximite(9, cfg)).to be > described_class.proximite(200, cfg)
  end

  it 'détecte même mot et dérivés par préfixe commun' do
    expect(described_class.same_or_derived?('aimer', 'aimés', 4)).to be(true)
    expect(described_class.same_or_derived?('maison', 'maisons', 4)).to be(true)
    expect(described_class.same_or_derived?('chat', 'chien', 4)).to be(false)
    expect(described_class.same_or_derived?(nil, 'a', 4)).to be(false)
  end

  it 'ignore les syllabes/inversées de mots fonctionnels' do
    poem = [fake_analysis(%w[de ʁɛ], %w[de rɛ]), fake_analysis(%w[de ʁo], %w[de ro])]
    reps = described_class.explain(poem)
    expect(reps.reject { |r| r.type == :phone }.map(&:form)).not_to include('de', 'əd')
    with = described_class.raw_score(poem)
    without = described_class.raw_score(poem, drop_function_word_syllables: false)
    expect(without).to be > with
  end

  it 'ne compte les phones de mots fonctionnels qu’en paire intra-vers' do
    phone_of = lambda do |poem, form|
      described_class.explain(poem, **weights_phones).find { |r| r.type == :phone && r.form == form }
    end
    same_verse = [fake_analysis(%w[de de], %w[de de])]
    cross = [fake_analysis(['de'], ['de']), fake_analysis(['de'], ['de'])]
    content_cross = [fake_analysis(['ʁa'], ['alpha']), fake_analysis(['ʁa'], ['beta'])]
    expect(phone_of.call(same_verse, 'd').total).to be > 0 # intra-vers : compté
    expect(phone_of.call(cross, 'd').total).to eq(0.0) # inter-vers + mot fonctionnel : ignoré
    expect(phone_of.call(content_cross, 'ʁ').total).to be > 0 # mots pleins : la paire inter-vers compte
  end

  it 'détecte les mots fonctionnels (listes scansion + fragments clitiques)' do
    expect(described_class.function_word?('de')).to be(true)
    expect(described_class.function_word?('n’est')).to be(true)
    expect(described_class.function_word?('l’ombre')).to be(false)
    expect(described_class.function_word?('qu’amer')).to be(false)
    expect(described_class.function_word?('miroir')).to be(false)
    expect(described_class.function_word?(nil)).to be(false)
  end

  it 'valorise une inversée selon sa longueur en phones' do
    weights = { phone: 1.0, voyelle: 1.0, consonne: 1.0, syllabe: 1.5, inversee: :length }
    expect(described_class.unit_value(:inversee, 'ʃɛʁ', weights)).to eq(3.0)
    expect(described_class.unit_value(:phone, 'ʁ', weights)).to eq(1.0)
    expect(described_class.unit_value(:syllabe, 'ʃɛʁ', weights)).to eq(1.5)
  end

  it 'classe un phone en voyelle (assonance) ou consonne (allitération), avec repli :phone' do
    defaults = described_class::DEFAULTS[:unit_weights]
    expect(described_class.unit_value(:phone, 'ɛ', defaults)).to eq(0.8) # voyelle
    expect(described_class.unit_value(:phone, 'ʁ', defaults)).to eq(0.0) # consonne
    repli = { phone: 0.5, syllabe: 1.5, inversee: :length } # sans classes -> repli :phone
    expect(described_class.unit_value(:phone, 'ɛ', repli)).to eq(0.5)
    expect(described_class.phone_class("ɑ\u0303")).to eq(:voyelle) # nasale = voyelle
    expect(described_class.phone_class('j')).to eq(:consonne) # glide = consonne
  end
end

RSpec.describe Claudel::Criteria::RepetitionPositionnelle do
  it 'compte la rime de fin de vers (poids 1.0) entre deux vers' do
    poem = [fake_analysis(%w[la bɛl], %w[pa bel]), fake_analysis(%w[ʁɛ bɛl], %w[ʁo bel])]
    # fin de vers 'bɛl' dans les deux vers -> 1 paire, valeur 3 phones × min(1.0, 1.0)
    # césures (vers pairs -> milieu) : 'la' vs 'ʁɛ', formes différentes -> 0
    expect(described_class.raw_score(poem)).to be_within(0.001).of(3.0)
  end

  it 'pondère la césure (0.7) sous la fin de vers et le groupe (0.5) sous la césure' do
    # vers de 3 syllabes (impair -> pas de césure), accent de mot ˌ en position 1
    v = -> { fake_analysis(%w[la bɛl ʁo], %w[pa bel ro], word_accents: [1]) }
    poem = [v.call, v.call]
    # fin de vers 'ʁo' : 2 phones × min(1.0, 1.0) = 2.0 ; groupe 'bɛl' : 3 × min(0.5, 0.5) = 1.5
    expect(described_class.raw_score(poem)).to be_within(0.001).of(3.5)
  end

  it 'exige au moins 2 phones en position (pas de phone seul en fin de vers)' do
    # fin de vers = syllabe 'a' (1 phone) -> repli sur les 2 derniers phones du vers
    poem = [fake_analysis(%w[la a], %w[pa bel]), fake_analysis(%w[ʁa a], %w[ʁo bel])]
    occ = described_class.positional_occurrences(poem, described_class::DEFAULTS)
    fin = occ.select { |o| o.verse == 0 && o.start == 2 } # dernière syllabe du vers 0
    expect(fin.map(&:form)).to eq(['aa'])
    expect(fin.first.weight).to eq(1.0)
  end

  it 'ignore une rime portée par un mot fonctionnel (ex. fin de vers « le »)' do
    fw = [fake_analysis(%w[la lø], %w[pa le]), fake_analysis(%w[ʁo lø], %w[ʁo le])]
    # césures 'la'/'ʁo' différentes -> seule la rime finale 'lø' pourrait compter
    expect(described_class.raw_score(fw)).to eq(0.0) # 'lø' porté par « le » : ignoré
    sans = described_class.raw_score(fw, drop_function_word_syllables: false)
    expect(sans).to be_within(0.001).of(2.0) # rime lø : 2 phones × poids min 1.0
  end

  it 'ignore un vers sans syllabes (ex. ligne mal phonétisée)' do
    empty = fake_analysis([], [], groups: [])
    expect(described_class.position_classes(empty)).to eq({})
    poem = [empty, fake_analysis(%w[la bɛl], %w[pa bel])]
    expect { described_class.raw_score(poem) }.not_to raise_error
    expect(Claudel.score(poem).score).to be >= 0.0
  end

  it 'attribue une césure au milieu d’un vers de longueur paire' do
    analysis = fake_analysis(%w[la bɛl ʁo zi], %w[pa bel ro zi])
    expect(described_class.position_classes(analysis)[1]).to eq(:cesure)
    odd = fake_analysis(%w[la bɛl ʁo], %w[pa bel ro])
    expect(described_class.position_classes(odd)).not_to have_key(1)
  end
end

RSpec.describe Claudel::Criteria::PatternsRythmiques do
  it 'cumul score de régularité par vers + récurrence de la signature dominante' do
    # 2 groupes de 2 syllabes -> signature [2,2], score Rythme = 2 par vers
    verse = fake_analysis(%w[la bɛ ʁo zi], %w[pa bel ro zi], groups: [[0, 1, 1], [2, 3, 3]])
    poem = [verse, verse]
    # 2 vers × score 2 + (2 vers sur la même signature -> +1)
    expect(described_class.raw_score(poem)).to be_within(0.001).of(5.0)
  end
end

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

SAMPLES_DIR = File.expand_path('../../../samples', __dir__) # poems/ruby/samples

RSpec.describe 'échantillons poems/ruby/samples', if: File.directory?(SAMPLES_DIR) do
  def sample_score(name)
    lines = File.readlines(File.join(SAMPLES_DIR, name), chomp: true).map(&:strip).reject(&:empty?)
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

RSpec.describe 'CLI' do
  it '--version affiche la version' do
    expect { Claudel.main(['--version']) }.to output(/claudel \d+\.\d+\.\d+/).to_stdout
  end

  it 'sans fichier, affiche usage et échoue' do
    expect { Claudel.main(['--mode', 'auto']) }.to output(/usage:/).to_stderr
  end

  it 'produit un rapport de densité phonétique pour un fichier' do
    Tempfile.create(['poeme', '.txt']) do |f|
      f.puts 'la substance de mort'
      f.puts 's additionne au vecu'
      f.flush
      expect { Claudel.main(['--mode', 'contemporain', f.path]) }
        .to output(/score de densité phonétique : [\d.]+/).to_stdout
    end
  end

  it '--repetitions détaille les répétitions identifiées' do
    Tempfile.create(['poeme', '.txt']) do |f|
      f.puts 'la substance de mort'
      f.puts 'la mort du substance' # rime approximative en fin de vers
      f.flush
      expect { Claudel.main(['--repetitions', f.path]) }
        .to output(/répétitions générales.*répétitions positionnelles.*signatures rythmiques/m).to_stdout
    end
  end
end
