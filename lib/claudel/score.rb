# frozen_string_literal: true

require_relative 'phonemes'
require_relative 'criteria'

module Claudel
  # Résultat du scoring d'un poème (voir Claudel.score).
  # - +score+        : score global de densité phonétique (combinaison pondérée)
  # - +total_phones+ : longueur du poème en phones (normalisation, notes §5)
  # - +verses+       : nombre de vers
  # - +criteria+     : { nom => { raw:, density:, weight: } }
  ScoreResult = Struct.new(:score, :total_phones, :verses, :criteria, keyword_init: true)

  class << self
    # Score global de « densité phonétique » d'un poème (notes §5).
    #
    # Chaque critère enregistré produit un score brut, normalisé en densité
    # (brut / nombre total de phones du poème — lignes très variables du
    # contemporain), puis combiné : score = Σ poids·densité / Σ poids.
    # Les poids se règlent via config[:weights][nom_critère] (notes §5) ;
    # chaque critère reçoit aussi +config+ entier pour ses propres réglages.
    #
    # @param input [Array<String>, Array<Scansion::Accents::Analysis>] vers ou analyses
    # @param mode [Symbol] :auto (défaut), :classique ou :contemporain (si vers donnés)
    # @param config [Hash] ex. { weights: { repetition_generale: 2.0 }, proximity_lambda: 60 }
    # @return [ScoreResult]
    def score(input, mode: :auto, config: {})
      poem = input.first.is_a?(String) ? analyze(input, mode: mode) : input
      total_phones = poem.sum { |analysis| Phonemes.of_syllables(analysis.syllables).size }
      details = criteria_details(poem, total_phones, config)
      ScoreResult.new(score: combine(details), total_phones: total_phones,
                      verses: poem.size, criteria: details)
    end

    # Détail par critère : score brut, densité (brut / phones du poème) et poids.
    # @return [Hash{Symbol => Hash}]
    def criteria_details(poem, total_phones, config)
      weights = config[:weights] || {}
      Criteria.all.to_h do |criterion|
        raw = criterion.raw_score(poem, config)
        weight = weights.fetch(criterion.name, criterion.default_weight)
        density = total_phones.positive? ? raw / total_phones : 0.0
        [criterion.name, { raw: raw, density: density, weight: weight }]
      end
    end

    # Combinaison pondérée des densités : Σ poids·densité / Σ poids.
    def combine(details)
      total_weight = details.values.sum { |d| d[:weight] }
      return 0.0 unless total_weight.positive?

      details.values.sum { |d| d[:weight] * d[:density] } / total_weight
    end
  end
end
