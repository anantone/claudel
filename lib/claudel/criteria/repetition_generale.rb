# frozen_string_literal: true

require_relative '../unites'
require_relative '../criteria'

module Claudel
  module Criteria
    # Critère 1 — répétition phonétique GÉNÉRALE, hors position (notes §2).
    #
    # Pour chaque unité (phone / syllabe / inversée) présente k fois dans le
    # poème : k−1 répétitions ; chaque répétition (paire d'occurrences
    # consécutives, triées par position) contribue
    #     valeur(unité) × proximité(d) × pénalité_mot
    # avec d = distance ABSOLUE en phones (indépendamment des vers).
    module RepetitionGenerale
      NAME = :repetition_generale

      # Points de départ (notes §2/§6) — surchargeables via config.
      DEFAULTS = {
        # Distinction assonance/allitération (littérature : l'assonance est plus
        # proche de la rime, l'allitération consonantique moins automatique) :
        # voyelle > consonne ; :phone sert de repli si une classe manque.
        # Inversée = longueur en phones.
        unit_weights: { phone: 0.0, voyelle: 0.8, consonne: 0.5, syllabe: 1.5, inversee: :length },
        proximity_a: 2.0, # proximité(d) = (d/(d+a)) · e^(−d/lambda)
        proximity_lambda: 40.0,
        word_penalty: 0.1, # même mot ou dérivé -> ×0.1
        root_min_length: 4, # préfixe commun >= 4 -> mots dérivés
        drop_function_word_syllables: true, # syllabes/inversées de mots fonctionnels ignorées
        function_word_phones_intra_verse_only: true # phones de mots fonctionnels : seulement en paire intra-vers
      }.freeze

      # Une unité répétée : ses occurrences + le détail de chaque paire
      # (distance, proximité, pénalité de mot, contribution).
      Repetition = Struct.new(:type, :form, :value, :occurrences, :pairs, :total, keyword_init: true)

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

        # Toutes les répétitions du poème (unités présentes >= 2 fois),
        # triées par contribution décroissante — pour le rapport détaillé.
        # @param poem [Array<Scansion::Accents::Analysis>]
        # @param config [Hash]
        # @return [Array<Repetition>]
        def explain(poem, config = {})
          cfg = DEFAULTS.merge(config)
          reps = Units.occurrences(poem).filter_map do |(type, form), units|
            build_repetition(type, form, units.sort_by(&:start), cfg)
          end
          reps.sort_by { |rep| -rep.total }
        end

        # @param sorted [Array<Unit>] occurrences triées par position
        # @return [Repetition, nil] nil si l'unité n'apparaît qu'une fois
        def build_repetition(type, form, sorted, cfg)
          units = filter_occurrences(type, sorted, cfg)
          return nil if units.size < 2

          value = unit_value(type, form, cfg[:unit_weights])
          pairs = units.each_cons(2).map { |a, b| pair_detail(type, a, b, value, cfg) }
          Repetition.new(type: type, form: form, value: value, occurrences: units,
                         pairs: pairs, total: pairs.sum { |p| p[:contribution] })
        end

        # Retire les occurrences de mots fonctionnels pour les unités
        # syllabiques (syllabe / inversée) — notes §2.
        # @return [Array<Unit>]
        def filter_occurrences(type, sorted, cfg)
          return sorted unless type != :phone && cfg[:drop_function_word_syllables]

          sorted.reject { |u| function_word?(u.word) }
        end

        # Détail d'une paire d'occurrences consécutives (k−1 paires pour k occ.).
        # Un phone de mot fonctionnel en paire INTER-vers est ignoré (notes §2) ;
        # en paire intra-vers, il compte.
        def pair_detail(type, unit_a, unit_b, value, cfg)
          distance = unit_b.start - unit_a.start
          prox = proximite(distance, cfg)
          wfactor = word_factor(unit_a.word, unit_b.word, cfg)
          contribution = value * prox * wfactor
          contribution = 0.0 if phone_pair_skipped?(type, unit_a, unit_b, cfg)
          { from: unit_a, to: unit_b, distance: distance, proximite: prox,
            word_factor: wfactor, contribution: contribution }
        end

        # Paire de phones hors d'un même vers et impliquant un mot fonctionnel.
        def phone_pair_skipped?(type, unit_a, unit_b, cfg)
          return false unless type == :phone && cfg[:function_word_phones_intra_verse_only]
          return false if unit_a.verse == unit_b.verse

          function_word?(unit_a.word) || function_word?(unit_b.word)
        end

        # @return [Boolean] mot fonctionnel — voir Units.function_word?
        def function_word?(word)
          Units.function_word?(word)
        end

        # Point de départ (notes §2) : pénalise les répétitions TROP PROCHES
        # (d = 1, gémination), culmine vers d ≈ 9 phones, puis décroît —
        # 3 fois dans un vers pèse plus que 3 fois dans un poème de 50 vers.
        # @param distance [Integer] distance absolue en phones
        # @return [Float]
        def proximite(distance, cfg)
          a = cfg[:proximity_a]
          (distance / (distance + a)) * Math.exp(-distance / cfg[:proximity_lambda])
        end

        # Valeur d'un type d'unité ; :length -> longueur en phones (inversée).
        # Un phone est valorisé selon sa classe : :voyelle (assonance) ou
        # :consonne (allitération), avec :phone comme repli.
        def unit_value(type, form, weights)
          key = type == :phone ? phone_class(form) : type
          weight = weights.key?(key) ? weights[key] : weights[:phone]
          weight == :length ? Phonemes.of_syllable(form).size.to_f : weight.to_f
        end

        # Classe d'un phone : :voyelle ou :consonne.
        def phone_class(phone)
          Phonemes.vowel?(phone) ? :voyelle : :consonne
        end

        # 1.0, ou word_penalty si les deux occurrences viennent du même mot
        # ou de mots dérivés (préfixe commun >= root_min_length — heuristique).
        def word_factor(word1, word2, cfg)
          return 1.0 unless same_or_derived?(word1, word2, cfg[:root_min_length])

          cfg[:word_penalty]
        end

        # @return [Boolean] même mot, ou préfixe commun >= +root_min+ (après
        # normalisation : casse et diacritiques ignorées, « aimer »/« aimés »)
        def same_or_derived?(word1, word2, root_min)
          return false if word1.nil? || word2.nil?

          norm1 = normalize_word(word1)
          norm2 = normalize_word(word2)
          norm1 == norm2 || common_prefix_length(norm1, norm2) >= root_min
        end

        # Normalise une surface de mot pour la comparaison (minuscules, sans accents).
        def normalize_word(word)
          word.unicode_normalize(:nfd).gsub(/\p{Mn}/, '').downcase
        end

        # Longueur du préfixe commun de deux chaînes.
        def common_prefix_length(first, second)
          n = [first.size, second.size].min
          i = 0
          i += 1 while i < n && first[i] == second[i]
          i
        end
      end
    end

    register(RepetitionGenerale)
  end
end
