# frozen_string_literal: true

require_relative '../phonemes'
require_relative '../unites'
require_relative '../criteria'

module Claudel
  module Criteria
    # Critère 2 — répétition phonétique POSITIONNELLE (notes §3).
    #
    # On ne regarde que les positions remarquables : fin de vers (rime),
    # césure, fins de groupes (accent de phrase ˈ et accent de mot ˌ).
    # Unité min en position : syllabe de >= 2 phones, ou les 2 derniers
    # phones (une « rime » = au moins 2 phones ou 1 syllabe — notes §3).
    # Poids par classe de position (point de départ) : fin de vers 1.0,
    # césure 0.7, groupe 0.5. Une paire de positions de même forme contribue
    # valeur(forme) × min(poids des deux positions).
    module RepetitionPositionnelle
      NAME = :repetition_positionnelle

      # Points de départ (notes §3/§6) — surchargeables via config.
      DEFAULTS = {
        position_weights: { fin_de_vers: 1.0, cesure: 0.7, groupe: 0.5 },
        min_phones: 2,
        drop_function_word_syllables: true # rime portée par un mot fonctionnel ignorée
      }.freeze

      # Occurrence positionnelle : forme (rime) + classe de position + poids + mot.
      PositionOccurrence = Struct.new(:form, :klass, :weight, :verse, :start, :word, keyword_init: true)

      # Une forme répétée en position : occurrences + paires avec le poids retenu.
      PositionalRepetition = Struct.new(:form, :value, :occurrences, :pairs, :total, keyword_init: true)

      class << self
        def name = NAME

        def default_weight = 1.0

        # Score brut = somme des contributions de toutes les répétitions.
        # @param poem [Array<Scansion::Accents::Analysis>]
        # @param config [Hash] surcharges de DEFAULTS
        # @return [Float]
        def raw_score(poem, config = {})
          explain(poem, config).sum(&:total)
        end

        # Toutes les formes répétées en position, triées par contribution
        # décroissante — pour le rapport détaillé.
        # @return [Array<PositionalRepetition>]
        def explain(poem, config = {})
          cfg = DEFAULTS.merge(config)
          reps = positional_occurrences(poem, cfg).group_by(&:form).filter_map do |form, list|
            build_repetition(form, list)
          end
          reps.sort_by { |rep| -rep.total }
        end

        # @return [PositionalRepetition, nil] nil si la forme n'apparaît qu'une fois
        def build_repetition(form, list)
          sorted = list.sort_by { |o| [o.verse, o.start] }
          return nil if sorted.size < 2

          value = Phonemes.of_syllable(form).size.to_f
          pairs = sorted.each_cons(2).map { |a, b| pair_detail(a, b, value) }
          PositionalRepetition.new(form: form, value: value, occurrences: sorted,
                                   pairs: pairs, total: pairs.sum { |p| p[:contribution] })
        end

        # Paire de positions consécutives : pondérée par le PLUS FAIBLE des deux poids.
        def pair_detail(occ_a, occ_b, value)
          weight = [occ_a.weight, occ_b.weight].min
          { from: occ_a, to: occ_b, weight: weight, contribution: value * weight }
        end

        # Toutes les occurrences positionnelles du poème.
        # @return [Array<PositionOccurrence>]
        def positional_occurrences(poem, cfg)
          offset = 0
          poem.each_with_index.flat_map do |analysis, verse_idx|
            occ = verse_positions(analysis, verse_idx, offset, cfg)
            offset += Phonemes.of_syllables(analysis.syllables).size
            occ
          end
        end

        # Occurrences positionnelles d'un vers.
        # @return [Array<PositionOccurrence>]
        def verse_positions(analysis, verse_idx, offset, cfg)
          syl_phones = analysis.syllables.map { |s| Phonemes.of_syllable(s) }
          starts = syllable_starts(syl_phones)
          word_of = Units.word_map(analysis)
          position_classes(analysis).filter_map do |syl_idx, klass|
            word = word_of[syl_idx]
            next if cfg[:drop_function_word_syllables] && Units.function_word?(word)

            occurrence_at(analysis, syl_idx, klass, syl_phones, starts, verse_idx, offset, cfg).tap do |occ|
              occ.word = word
            end
          end
        end

        # Indices locaux (en phones) de début de chaque syllabe d'un vers.
        def syllable_starts(syl_phones)
          starts = []
          pos = 0
          syl_phones.each do |ps|
            starts << pos
            pos += ps.size
          end
          starts
        end

        # Occurrence positionnelle à la syllabe +syl_idx+.
        def occurrence_at(analysis, syl_idx, klass, syl_phones, starts, verse_idx, offset, cfg)
          verse_phones = syl_phones.flatten
          stop = starts[syl_idx] + syl_phones[syl_idx].size - 1
          form = trailing_form(analysis.syllables[syl_idx], syl_phones[syl_idx], verse_phones, stop, cfg)
          PositionOccurrence.new(form: form, klass: klass, weight: cfg[:position_weights][klass],
                                 verse: verse_idx, start: offset + starts[syl_idx], word: nil)
        end

        # Classe de chaque position remarquable d'un vers :
        # fin de vers (toujours), césure (vers de longueur paire -> milieu,
        # comme caesura_index en 8/12), fins de groupes ˈ et ˌ.
        # Priorité : fin de vers > césure > groupe.
        # @return [Hash{Integer => Symbol}] indice de syllabe -> classe
        def position_classes(analysis)
          n = analysis.syllables.size
          return {} if n.zero? # vers sans syllabes (ex. « _13/11/2008_ » mal phonétisé)

          classes = { n - 1 => :fin_de_vers }
          add_caesura(classes, n)
          add_group_ends(classes, analysis)
          classes
        end

        def add_caesura(classes, size)
          return unless size.even? && size >= 2

          caesura = (size / 2) - 1
          classes[caesura] = :cesure if caesura != size - 1
        end

        def add_group_ends(classes, analysis)
          (analysis.accents + analysis.word_accents).uniq.each { |i| classes[i] ||= :groupe }
        end

        # Forme (rime) terminant à une position : la syllabe si elle fait
        # >= min_phones phones, sinon les min_phones derniers phones du vers.
        # @return [String]
        def trailing_form(syl, syl_phones, verse_phones, stop, cfg)
          min = cfg[:min_phones]
          return syl if syl_phones.size >= min

          verse_phones[[stop - min + 1, 0].max..stop].join
        end
      end
    end

    register(RepetitionPositionnelle)
  end
end
