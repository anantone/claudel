# frozen_string_literal: true

#
# phonemes.rb — découpage des syllabes IPA en phones.
#
# Un phone peut occuper plusieurs codepoints (voyelle nasale « ɑ̃ » =
# ɑ + tilde combinant U+0303, affriquée « t͡ʃ » avec barre de liaison) :
# DÉCISION (notes §6) — 1 phone = 1 phone même multi-codepoints, les
# marques combinantes (catégorie Unicode Mn) sont rattachées au caractère
# de base qui les précède.
#

module Claudel
  # Découpage de syllabes IPA en phones (voir en-tête).
  module Phonemes
    module_function

    # Découpe une syllabe IPA en phones.
    # @param syl [String] syllabe IPA (ex. "stɑ̃s")
    # @return [Array<String>] ex. ["s", "t", "ɑ̃", "s"]
    def of_syllable(syl)
      phones = []
      syl.each_char do |c|
        if c.match?(/\p{Mn}/) && phones.any?
          phones[-1] += c
        else
          phones << c
        end
      end
      phones
    end

    # Aplatit une liste de syllabes IPA en phones.
    # @param syls [Array<String>] syllabes IPA
    # @return [Array<String>] phones
    def of_syllables(syls)
      syls.flat_map { |s| of_syllable(s) }
    end

    # @param phone [String] un phone (éventuellement multi-codepoints, ex. « ɑ̃ »)
    # @return [Boolean] voyelle (orales + nasales via le caractère de base ;
    #   les glides j ɥ w sont des consonnes) — classe de Scansion::PHONEME_VOYELLE
    def vowel?(phone)
      Scansion::PHONEME_VOYELLE.match?(phone)
    end
  end
end
