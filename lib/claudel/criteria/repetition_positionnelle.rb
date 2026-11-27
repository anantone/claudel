# frozen_string_literal: true

require_relative '../phonemes'
require_relative '../unites'
require_relative '../positions'
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
    # valeur(forme) × min(poids des deux positions) × proximité en vers.
    #
    # Proximité en vers (notes §3) — règle classique « des deux couleurs »
    # (Cornulier, Art poëtique, 1995, p. 267) : une terminaison n'est jamais
    # séparée de son plus proche écho par plus d'un autre type de terminaison,
    # soit au plus 3 vers d'écart (abba). Jusqu'à rhyme_plateau = 3 vers,
    # poids plein : rimes plates (1), croisées (2), embrassées (3), tercets
    # ccd eed (3), ballade ababbcbc (≤ 2) ne perdent rien. Au-delà (« rime
    # distante », Purnelle, « Cocteau expérimentateur de la rime ») : volume
    # et distance se compensent — plus la rime est épaisse, plus elle porte
    # loin — d'où une décroissance exponentielle dont l'échelle croît avec la
    # longueur de la forme : e^(−(Δv − plateau) / (lambda · phones / min_phones)).
    # Sans cette décroissance, une forme répétée à 40 vers d'écart comptait
    # comme une rime plate, et la densité positionnelle croissait avec la
    # longueur du poème.
    module RepetitionPositionnelle
      NAME = :repetition_positionnelle

      # Points de départ (notes §3/§6) — surchargeables via config.
      DEFAULTS = {
        position_weights: { fin_de_vers: 1.0, cesure: 0.7, groupe: 0.5 },
        min_phones: 2,
        drop_function_word_syllables: true, # rime portée par un mot fonctionnel ignorée
        rhyme_plateau: 3, # écart (en vers) à poids plein : abba (règle des deux couleurs)
        rhyme_lambda: 4.0 # décroissance au-delà, en vers, pour une rime de min_phones phones ; nil = aucune
      }.freeze

      # Occurrence positionnelle : forme (rime) + classe de position + poids + mot.
      PositionOccurrence = Struct.new(:form, :klass, :weight, :verse, :start, :word, keyword_init: true)

      # Une forme répétée en position : occurrences + paires avec le poids retenu.
      PositionalRepetition = Struct.new(:form, :value, :occurrences, :pairs, :total, keyword_init: true)

      # Données d'un vers calculées une fois pour toutes ses positions.
      VerseContext = Struct.new(:syllables, :syl_phones, :starts, :phones, :verse_idx, :offset,
                                keyword_init: true)

      class << self
        def key = NAME

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
          cfg = Criteria.merge_config(DEFAULTS, config)
          reps = positional_occurrences(poem, cfg).group_by(&:form).filter_map do |form, list|
            build_repetition(form, list, cfg)
          end
          reps.sort_by { |rep| [-rep.total, rep.form] } # ex aequo : ordre stable
        end

        # @return [PositionalRepetition, nil] nil si la forme n'apparaît qu'une fois
        def build_repetition(form, list, cfg = DEFAULTS)
          sorted = list.sort_by { |o| [o.verse, o.start] }
          return nil if sorted.size < 2

          value = Phonemes.of_syllable(form).size.to_f
          pairs = sorted.each_cons(2).map { |a, b| pair_detail(a, b, value, cfg) }
          PositionalRepetition.new(form: form, value: value, occurrences: sorted,
                                   pairs: pairs, total: pairs.sum { |p| p[:contribution] })
        end

        # Paire de positions consécutives : pondérée par le PLUS FAIBLE des deux
        # poids et par la proximité en vers (voir en-tête).
        def pair_detail(occ_a, occ_b, value, cfg = DEFAULTS)
          weight = [occ_a.weight, occ_b.weight].min
          distance = occ_b.verse - occ_a.verse
          prox = verse_proximity(distance, value, cfg)
          { from: occ_a, to: occ_b, weight: weight, verse_distance: distance, proximite: prox,
            contribution: value * weight * prox }
        end

        # 1.0 jusqu'à rhyme_plateau vers d'écart, puis décroissance d'autant
        # plus lente que la forme est longue (+value+ phones).
        # @param distance [Integer] écart en vers (0 = même vers)
        # @return [Float]
        def verse_proximity(distance, value, cfg)
          excess = distance - cfg[:rhyme_plateau]
          return 1.0 if excess <= 0 || cfg[:rhyme_lambda].nil?

          scale = cfg[:rhyme_lambda].to_f * value / cfg[:min_phones]
          Math.exp(-excess / scale)
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

        # Occurrences positionnelles d'un vers. Une position dont la forme
        # n'atteint pas min_phones (syllabe d'un phone en tout début de vers,
        # sans phone précédent pour compléter) est ignorée.
        # @return [Array<PositionOccurrence>]
        def verse_positions(analysis, verse_idx, offset, cfg)
          verse = verse_context(analysis, verse_idx, offset)
          word_of = Units.word_map(analysis)
          Positions.classes(analysis).filter_map do |syl_idx, klass|
            word = word_of[syl_idx]
            next if cfg[:drop_function_word_syllables] && Units.function_word?(word)

            occ = occurrence_at(verse, syl_idx, klass, word, cfg)
            occ if Phonemes.of_syllable(occ.form).size >= cfg[:min_phones]
          end
        end

        # @return [VerseContext]
        def verse_context(analysis, verse_idx, offset)
          syl_phones = analysis.syllables.map { |s| Phonemes.of_syllable(s) }
          VerseContext.new(syllables: analysis.syllables, syl_phones: syl_phones,
                           starts: syllable_starts(syl_phones), phones: syl_phones.flatten,
                           verse_idx: verse_idx, offset: offset)
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
        # @param verse [VerseContext]
        def occurrence_at(verse, syl_idx, klass, word, cfg)
          PositionOccurrence.new(form: trailing_form(verse, syl_idx, cfg), klass: klass,
                                 weight: cfg[:position_weights][klass], verse: verse.verse_idx,
                                 start: verse.offset + verse.starts[syl_idx], word: word)
        end

        # Forme (rime) terminant à une position : la syllabe si elle fait
        # >= min_phones phones, sinon les min_phones derniers phones du vers
        # jusqu'à cette syllabe incluse.
        # @param verse [VerseContext]
        # @return [String]
        def trailing_form(verse, syl_idx, cfg)
          min = cfg[:min_phones]
          syl_size = verse.syl_phones[syl_idx].size
          return verse.syllables[syl_idx] if syl_size >= min

          stop = verse.starts[syl_idx] + syl_size - 1
          verse.phones[[stop - min + 1, 0].max..stop].join
        end
      end
    end

    register(RepetitionPositionnelle)
  end
end
