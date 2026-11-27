# frozen_string_literal: true

require_relative 'phonemes'
require_relative 'criteria'

module Claudel
  # Résultat du scoring d'un poème (voir Claudel.score).
  # - +score+        : score global de densité phonétique (combinaison pondérée)
  # - +total_phones+ : longueur du poème en phones (normalisation, notes §5)
  # - +verses+       : nombre de vers
  # - +criteria+     : { nom => { raw:, density:, weight:, repetitions:, standardized: } }
  #   (+repetitions+ = détail explain du critère, nil s'il n'en a pas — évite
  #   de le recalculer côté CLI ; +standardized+ = densité centrée-réduite,
  #   nil sans calibration)
  # - +calibrated+   : true si +score+ combine des densités standardisées
  ScoreResult = Struct.new(:score, :total_phones, :verses, :criteria, :calibrated, keyword_init: true)

  class << self
    # Score global de « densité phonétique » d'un poème (notes §5).
    #
    # Chaque critère enregistré produit un score brut, normalisé en densité
    # (brut / nombre total de phones du poème — lignes très variables du
    # contemporain), puis combiné : score = Σ poids·densité / Σ poids.
    # Les poids se règlent via config[:weights][nom_critère] (notes §5) ;
    # chaque critère reçoit aussi +config+ entier pour ses propres réglages.
    #
    # Avec config[:calibration] (une Claudel::Calibration), chaque densité est
    # d'abord centrée-réduite sur le corpus de calibration : le score se lit
    # alors en écarts-types (0 = poème moyen du corpus), et les poids ont le
    # même sens pour tous les critères (voir calibration.rb).
    #
    # @param input [Array<String>, Array<Scansion::Accents::Analysis>] vers ou analyses
    # @param mode [Symbol] :auto (défaut), :classique ou :contemporain (si vers donnés)
    # @param config [Hash] ex. { weights: { repetition_generale: 2.0 }, proximity_lambda: 60 }
    # @return [ScoreResult]
    def score(input, mode: :auto, config: {})
      poem = input.first.is_a?(String) ? analyze(input, mode: mode) : input
      total_phones = poem.sum { |analysis| Phonemes.of_syllables(analysis.syllables).size }
      details = criteria_details(poem, total_phones, config)
      build_result(poem, total_phones, details, config[:calibration])
    end

    # @param calibration [Calibration, nil]
    # @return [ScoreResult]
    def build_result(poem, total_phones, details, calibration)
      standardize(details, calibration) if calibration
      calibrated = !calibration.nil?
      ScoreResult.new(score: combine(details, calibrated: calibrated), total_phones: total_phones,
                      verses: poem.size, criteria: details, calibrated: calibrated)
    end

    # Détail par critère : score brut, densité (brut / phones du poème), poids,
    # et répétitions détaillées si le critère expose .explain (calcul unique).
    # @return [Hash{Symbol => Hash}]
    def criteria_details(poem, total_phones, config)
      weights = config[:weights] || {}
      Criteria.all.to_h do |criterion|
        reps = criterion.respond_to?(:explain) ? criterion.explain(poem, config) : nil
        raw = reps ? reps.sum(&:total) : criterion.raw_score(poem, config)
        weight = weights.fetch(criterion.key, criterion.default_weight)
        density = total_phones.positive? ? raw / total_phones : 0.0
        [criterion.key, { raw: raw, density: density, weight: weight, repetitions: reps, standardized: nil }]
      end
    end

    # Ajoute à chaque critère sa densité centrée-réduite (+standardized+).
    # @param calibration [Calibration]
    def standardize(details, calibration)
      details.each { |key, detail| detail[:standardized] = calibration.standardize(key, detail[:density]) }
    end

    # Combinaison pondérée : Σ poids·valeur / Σ poids, où valeur = densité,
    # ou densité standardisée si +calibrated+.
    def combine(details, calibrated: false)
      total_weight = details.values.sum { |d| d[:weight] }
      return 0.0 unless total_weight.positive?

      value = calibrated ? :standardized : :density
      details.values.sum { |d| d[:weight] * d[value] } / total_weight
    end
  end
end
