# frozen_string_literal: true

require_relative '../criteria'

module Claudel
  module Criteria
    # Critère 3 — patterns rythmiques (notes §4) : la répétition a une valeur
    # en soi. Par vers : Rythme.signature + Rythme.score (régularité interne).
    # Par poème : récurrence des signatures entre vers (la signature dominante
    # répétée rapporte +1 par vers au-delà du premier).
    module PatternsRythmiques
      NAME = :patterns_rythmiques

      # Points de départ — surchargeables via config.
      DEFAULTS = {
        verse_bonus: 1.0, # poids du score de régularité de chaque vers
        recurrence_bonus: 1.0 # poids de chaque répétition de la signature dominante
      }.freeze

      class << self
        def name = NAME

        def default_weight = 1.0

        # @param poem [Array<Scansion::Accents::Analysis>]
        # @param config [Hash] surcharges de DEFAULTS
        # @return [Float] score brut
        def raw_score(poem, config = {})
          cfg = DEFAULTS.merge(config)
          signatures = poem.map { |analysis| Scansion::Rythme.signature(analysis) }
          (cfg[:verse_bonus] * verse_scores(signatures)) + (cfg[:recurrence_bonus] * recurrence(signatures))
        end

        # Somme des scores de régularité (Rythme.score) de chaque vers.
        def verse_scores(signatures)
          signatures.sum { |sig| Scansion::Rythme.score(sig) }
        end

        # Nombre de vers au-delà du premier partageant la signature dominante.
        def recurrence(signatures)
          [signatures.tally.values.max.to_i - 1, 0].max
        end
      end
    end

    register(PatternsRythmiques)
  end
end
