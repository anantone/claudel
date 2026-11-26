# frozen_string_literal: true

# Charge la source locale de scansion (3.0.0, ahead of rubygems) si elle est
# présente (dépôt voisin gems/scansion), sinon le gem installé.
scansion_local = File.expand_path('../../scansion/lib', __dir__)
$LOAD_PATH.unshift(scansion_local) if File.directory?(scansion_local)
$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'claudel'

# Construit une Scansion::Accents::Analysis factice (sans dépendre d'espeak-ng).
# @param syllables [Array<String>] syllabes IPA (1 token par syllabe)
# @param words [Array<String>] surfaces des mots
# @param groups [Array<Array(Integer, Integer, Integer)>, nil] plages de tokens
#   [first, last, accent] par groupe ; nil = un seul groupe sur tout le vers
# @param word_accents [Array<Integer>] indices de syllabes en ˌ
def fake_analysis(syllables, words, groups: nil, word_accents: [])
  tokens = words.each_with_index.map do |w, i|
    Scansion::Accents::Token.new(surface: w, kind: :word, debut: i, fin: i)
  end
  groups ||= [[0, tokens.size - 1, tokens.last.fin]]
  built = groups.map do |(first, last, accent)|
    Scansion::Accents::Group.new(tokens: tokens[first..last], accent: accent)
  end
  Scansion::Accents::Analysis.new(text: words.join(' '), syllables: syllables,
                                  tokens: tokens, groups: built,
                                  word_accents: word_accents, warnings: [])
end

RSpec.configure do |config|
  config.expect_with(:rspec) { |expectations| expectations.syntax = :expect }
end
