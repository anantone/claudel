# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Claudel::Criteria do
  it 'enregistre les trois critères' do
    expect(described_class.all.map(&:key)).to contain_exactly(
      :repetition_generale, :repetition_positionnelle, :patterns_rythmiques
    )
  end

  it 'laisse Module#name intact (la clé du critère est .key)' do
    expect(described_class.all.map(&:name)).to all(start_with('Claudel::Criteria::'))
  end

  it 'fusionne la config sur les défauts, sous-hashes compris' do
    defaults = { a: 1, nested: { x: 1, y: 2 } }
    merged = described_class.merge_config(defaults, { nested: { y: 3 }, b: 4 })
    expect(merged).to eq(a: 1, nested: { x: 1, y: 3 }, b: 4)
    expect(defaults).to eq(a: 1, nested: { x: 1, y: 2 }) # défauts intacts
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
    expect(weights[:voyelle]).to be > weights[:consonne] # assonance > allitération
    # poème ʁɛʃ/ʃɛʁ : voyelle ɛ [1,4] d=3 ; consonnes ʁ [0,5] d=5 et ʃ [2,3] d=1
    expected = (weights[:voyelle] * prox(3)) + (weights[:consonne] * (prox(5) + prox(1)))
    expect(described_class.raw_score(poem)).to be_within(1e-9).of(expected)
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

  it 'proximité identique avec des réglages entiers ou flottants (pas de division entière)' do
    ints = described_class::DEFAULTS.merge(proximity_a: 2, proximity_lambda: 60)
    floats = described_class::DEFAULTS.merge(proximity_a: 2.0, proximity_lambda: 60.0)
    [1, 9, 30, 61].each do |d|
      expect(described_class.proximite(d, ints)).to be_within(1e-12).of(described_class.proximite(d, floats))
    end
    expect(described_class.proximite(9, ints)).to be > 0.0
  end

  it 'surcharger un seul poids d’unité conserve les autres poids par défaut' do
    poem = [fake_analysis(%w[ʁa ʁa], %w[aa bb])]
    syllabe = described_class::DEFAULTS[:unit_weights][:syllabe]
    # seule la contribution de la syllabe ʁa change : (2.0 − défaut) × prox(2)
    expected = described_class.raw_score(poem) + ((2.0 - syllabe) * prox(2))
    expect(described_class.raw_score(poem, unit_weights: { syllabe: 2.0 })).to be_within(1e-9).of(expected)
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
    expect(described_class.unit_value(:phone, 'ɛ', defaults)).to eq(defaults[:voyelle]) # voyelle
    expect(described_class.unit_value(:phone, 'ʁ', defaults)).to eq(defaults[:consonne]) # consonne
    repli = { phone: 0.5, syllabe: 1.5, inversee: :length } # sans classes -> repli :phone
    expect(described_class.unit_value(:phone, 'ɛ', repli)).to eq(0.5)
    expect(described_class.phone_class("ɑ\u0303")).to eq(:voyelle) # nasale = voyelle
    expect(described_class.phone_class('j')).to eq(:consonne) # glide = consonne
  end
end

RSpec.describe Claudel::Criteria::RepetitionPositionnelle do
  describe 'proximité en vers (règle des deux couleurs, puis rime distante)' do
    # Une rime de 3 phones par lettre du schéma ; vers de 3 syllabes (impair :
    # pas de césure), premières syllabes toutes distinctes -> seules les fins
    # de vers peuvent se répéter.
    rhymes = { 'A' => 'bɛl', 'B' => 'ʁoz', 'C' => 'mɔʁ', 'D' => 'nɥi', 'E' => 'ʒuʁ' }
    scheme_poem = lambda do |scheme|
      scheme.delete(' ').chars.each_with_index.map do |letter, i|
        fake_analysis(["k#{i}", "t#{i}", rhymes.fetch(letter)], ["mot#{i}a", "mot#{i}b", "mot#{i}c"])
      end
    end

    {
      'rimes plates' => 'AABB',
      'rimes croisées' => 'ABAB',
      'rimes embrassées' => 'ABBA',
      'sonnet (tercets ccd eed)' => 'ABBA ABBA CCD EED',
      'sonnet (tercets ccd ede)' => 'ABBA ABBA CCD EDE',
      'ballade (huitain ababbcbc)' => 'ABABBCBC',
      'terza rima' => 'ABA BCB CDC'
    }.each do |name, scheme|
      it "ne pénalise aucune paire : #{name} (#{scheme})" do
        reps = described_class.explain(scheme_poem.call(scheme))
        pairs = reps.flat_map(&:pairs)
        expect(pairs.map { |p| p[:verse_distance] }.max).to be <= 3
        expect(pairs.map { |p| p[:proximite] }).to all(eq(1.0))
        expect(reps.sum(&:total)).to be_within(1e-9).of(3.0 * pairs.size) # 3 phones × poids 1.0
      end
    end

    it 'au-delà de 3 vers, décroît d’autant plus lentement que la rime est épaisse' do
      cfg = described_class::DEFAULTS
      # Δv = 10 : e^(−(10 − 3) / (4.0 · phones / 2))
      expect(described_class.verse_proximity(10, 2.0, cfg)).to be_within(1e-12).of(Math.exp(-7 / 4.0))
      expect(described_class.verse_proximity(10, 4.0, cfg)).to be_within(1e-12).of(Math.exp(-7 / 8.0))
      expect(described_class.verse_proximity(4, 2.0, cfg)).to be < 1.0
      expect(described_class.verse_proximity(0, 2.0, cfg)).to eq(1.0) # même vers (rime interne)
    end

    it 'une forme répétée loin compte moins qu’à 3 vers ; rhyme_lambda: nil désactive' do
      near = scheme_poem.call('ABBA') # A : Δv = 3
      far = scheme_poem.call("A#{'BC' * 5}A") # A : Δv = 11
      a_total = ->(poem, cfg) { described_class.explain(poem, cfg).find { |r| r.form == 'bɛl' }.total }
      expect(a_total.call(far, {})).to be < a_total.call(near, {})
      expect(a_total.call(far, rhyme_lambda: nil)).to eq(a_total.call(near, {}))
    end
  end

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

  it 'surcharger un seul poids de position conserve les autres (pas de crash)' do
    poem = [fake_analysis(%w[la bɛl], %w[pa bel]), fake_analysis(%w[ʁɛ bɛl], %w[ʁo bel])]
    # la rime de fin de vers garde son poids par défaut 1.0
    expect(described_class.raw_score(poem, position_weights: { cesure: 0.9 })).to be_within(0.001).of(3.0)
  end

  it 'ignore une position dont la forme reste sous min_phones (syllabe d’un phone en début de vers)' do
    # 2 syllabes -> césure sur 'a' (1 phone, rien avant pour compléter)
    occ = described_class.positional_occurrences([fake_analysis(%w[a bɛl], %w[xa bel])], described_class::DEFAULTS)
    expect(occ.map { |o| [o.form, o.klass] }).to eq([['bɛl', :fin_de_vers]])
  end

  it 'ignore un vers sans syllabes (ex. ligne mal phonétisée)' do
    empty = fake_analysis([], [], groups: [])
    expect(Claudel::Positions.classes(empty)).to eq({})
    poem = [empty, fake_analysis(%w[la bɛl], %w[pa bel])]
    expect { described_class.raw_score(poem) }.not_to raise_error
    expect(Claudel.score(poem).score).to be >= 0.0
  end

  it 'attribue une césure au milieu d’un vers de longueur paire' do
    analysis = fake_analysis(%w[la bɛl ʁo zi], %w[pa bel ro zi])
    expect(Claudel::Positions.classes(analysis)[1]).to eq(:cesure)
    odd = fake_analysis(%w[la bɛl ʁo], %w[pa bel ro])
    expect(Claudel::Positions.classes(odd)).not_to have_key(1)
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

  it 'ne crédite la récurrence qu’à la signature dominante (alternance -> 1, pas 3)' do
    a = fake_analysis(%w[la bɛ ʁo zi], %w[pa bel ro zi], groups: [[0, 1, 1], [2, 3, 3]]) # [2,2]
    b = fake_analysis(%w[la bɛl ʁo], %w[pa bel ro], groups: [[0, 0, 0], [1, 2, 2]]) # [1,2]
    sigs = [a, b, a, b].map { |v| Scansion::Rythme.signature(v) }
    expect(described_class.recurrence(sigs)).to eq(1) # tally max = 2 -> 2-1
  end
end
