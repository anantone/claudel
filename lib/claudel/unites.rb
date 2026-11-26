# frozen_string_literal: true

require_relative 'phonemes'

#
# unites.rb — unités de répétition phonétique (notes §1) extraites d'un poème.
#
# Un poème = Array<Scansion::Accents::Analysis> (voir Claudel.analyze).
# Chaque occurrence d'unité porte sa position ABSOLUE en phones dans le
# poème — indépendamment des frontières de vers (notes §2) — et le mot
# (surface du token scansion) dont elle provient, pour la pénalité de
# répétition de mot/dérivé (notes §2).
#
# Types d'unité :
#   :phone    — un phone (allitération / assonance) ;
#   :syllabe  — une syllabe entière ;
#   :inversee — une syllabe renversée (>= 2 phones ; la valeur croît avec
#               la longueur, pondération côté critère — notes §1c).
#

module Claudel
  # Occurrence d'une unité de répétition dans un poème.
  # - +type+  : :phone | :syllabe | :inversee
  # - +form+  : forme comparée (le phone, la syllabe, ou la syllabe renversée)
  # - +verse+ : index du vers dans le poème
  # - +start+, +stop+ : indices ABSOLUS (en phones) du premier/dernier phone
  # - +word+  : surface du token (mot) contenant l'occurrence (nil si ponctuation)
  Unit = Struct.new(:type, :form, :verse, :start, :stop, :word, keyword_init: true)

  # Extraction des unités de répétition d'un poème (voir en-tête).
  module Units
    module_function

    # Extrait toutes les occurrences d'unités d'un poème.
    # @param poem [Array<Scansion::Accents::Analysis>]
    # @return [Array<Unit>]
    def extract(poem)
      units = []
      offset = 0 # index absolu (en phones) du début du vers courant
      poem.each_with_index do |analysis, verse_idx|
        units.concat(extract_verse(analysis, verse_idx, offset))
        offset += Phonemes.of_syllables(analysis.syllables).size
      end
      units
    end

    # Index des occurrences par unité : { [type, forme] => [Unit, ...] }.
    # C'est la matière du critère 1 (répétitions) et du critère 2 (positions).
    # @param poem [Array<Scansion::Accents::Analysis>]
    # @return [Hash{Array => Array<Unit>}]
    def occurrences(poem)
      extract(poem).group_by { |u| [u.type, u.form] }
    end

    # Extrait les unités d'un seul vers.
    # @param analysis [Scansion::Accents::Analysis]
    # @param verse_idx [Integer] index du vers dans le poème
    # @param offset [Integer] index absolu (en phones) du début du vers
    # @return [Array<Unit>]
    def extract_verse(analysis, verse_idx, offset)
      word_of = word_map(analysis)
      units = []
      pos = offset
      analysis.syllables.each_with_index do |syl, syl_idx|
        phones = Phonemes.of_syllable(syl)
        units.concat(syllable_units(syl, phones, verse_idx, pos, word_of[syl_idx]))
        pos += phones.size
      end
      units
    end

    # Unités portées par une syllabe : chacun de ses phones, la syllabe
    # elle-même, et son inversée (seulement si >= 2 phones — notes §1c).
    # @return [Array<Unit>]
    def syllable_units(syl, phones, verse_idx, start, word)
      stop = start + phones.size - 1
      units = phones.each_with_index.map do |phone, k|
        Unit.new(type: :phone, form: phone, verse: verse_idx, start: start + k, stop: start + k, word: word)
      end
      units << Unit.new(type: :syllabe, form: syl, verse: verse_idx, start: start, stop: stop, word: word)
      if phones.size >= 2
        units << Unit.new(type: :inversee, form: phones.reverse.join, verse: verse_idx, start: start, stop: stop,
                          word: word)
      end
      units
    end

    # Correspondance indice de syllabe -> surface du mot (token scansion).
    # @param analysis [Scansion::Accents::Analysis]
    # @return [Hash{Integer => String}]
    def word_map(analysis)
      map = {}
      analysis.tokens.each do |t|
        next unless t.debut && t.fin

        (t.debut..t.fin).each { |syl_idx| map[syl_idx] = t.surface }
      end
      map
    end

    # Fragments clitiques (miroir de la liste privée de scansion) : en français,
    # une partie d'une lettre ne peut être qu'un clitique (l', n', d'…).
    FRAGMENTS_CLITIQUES = %w[c d j l m n s t].freeze

    # @return [Boolean] mot fonctionnel : toutes ses parties sont dans
    # Scansion::Accents::MOTS_FONCTIONNELS ou un fragment clitique
    # (« n'est » oui, « l'ombre » non, « qu'amer » non).
    def function_word?(word)
      return false if word.nil?

      parts = word.downcase.split(/['’-]/).reject(&:empty?)
      !parts.empty? && parts.all? do |part|
        FRAGMENTS_CLITIQUES.include?(part) || Scansion::Accents::MOTS_FONCTIONNELS.key?(part)
      end
    end
  end
end
