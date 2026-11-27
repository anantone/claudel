# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Claudel do
  it 'expose une version' do
    expect(Claudel::VERSION).to match(/\A\d+\.\d+\.\d+\z/)
  end

  it 'analyse un poème via scansion' do
    poem = described_class.analyze(['la substance de mort'], mode: :contemporain)
    expect(poem.size).to eq(1)
    expect(poem.first.syllables).to include('stɑ̃s')
  end
end

RSpec.describe Claudel::Phonemes do
  it 'découpe une syllabe simple' do
    expect(described_class.of_syllable('la')).to eq(%w[l a])
  end

  it 'traite une voyelle nasale multi-codepoints comme 1 phone' do
    syl = "stɑ\u0303s" # « stɑ̃s » : ɑ + tilde combinant U+0303
    expect(described_class.of_syllable(syl)).to eq(%w[s t ɑ̃ s])
  end

  it 'attache une barre de liaison (U+0361) au caractère précédent (affriquée t͡ʃ)' do
    expect(described_class.of_syllable("t\u0361ʃ")).to eq(%w[t͡ ʃ])
  end

  it 'aplatit une liste de syllabes' do
    expect(described_class.of_syllables(%w[la bɛl])).to eq(%w[l a b ɛ l])
  end

  it 'classe les phones : voyelle (orale/nasale) vs consonne (glides inclus)' do
    expect(described_class.vowel?('ɛ')).to be(true)
    expect(described_class.vowel?("ɑ\u0303")).to be(true) # voyelle nasale
    expect(described_class.vowel?('ʁ')).to be(false)
    expect(described_class.vowel?('j')).to be(false) # glide = consonne
  end
end

RSpec.describe Claudel::Units do
  let(:poem) { [fake_analysis(%w[ʁɛʃ ʃɛʁ], %w[a b])] }

  it 'extrait phones, syllabes et inversées avec positions absolues en phones' do
    units = described_class.extract(poem)
    phones = units.select { |u| u.type == :phone }
    expect(phones.map(&:form)).to eq(%w[ʁ ɛ ʃ ʃ ɛ ʁ])
    expect(phones.map(&:start)).to eq((0..5).to_a)
    expect(units.select { |u| u.type == :syllabe }.map(&:form)).to eq(%w[ʁɛʃ ʃɛʁ])
    expect(units.select { |u| u.type == :inversee }.map(&:form)).to eq(%w[ʃɛʁ ʁɛʃ])
  end

  it 'ne crée pas d’inversée pour une syllabe d’un seul phone' do
    units = described_class.extract([fake_analysis(['a'], ['a'])])
    expect(units.map(&:type)).to eq(%i[phone syllabe])
  end

  it 'indexe les occurrences par unité et conserve le mot d’origine' do
    occ = described_class.occurrences(poem)
    expect(occ[[:phone, 'ʁ']].size).to eq(2)
    expect(occ[[:phone, 'ʁ']].map(&:word)).to eq(%w[a b])
    expect(occ[[:inversee, 'ʃɛʁ']].size).to eq(1)
  end

  it 'numérote les phones en absolu à travers les vers' do
    poem2 = poem + [fake_analysis(['la'], ['c'])]
    first_of_verse2 = described_class.extract(poem2).select { |u| u.verse == 1 }.min_by(&:start)
    expect(first_of_verse2.start).to eq(6)
  end

  it 'extrait les unités d’un vrai poème scansionné' do
    units = described_class.extract(Claudel.analyze(['la substance de mort'], mode: :contemporain))
    expect(units.map(&:type)).to include(:phone, :syllabe, :inversee)
    expect(units.map(&:word)).to all(be_a(String))
  end
end
