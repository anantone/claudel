# frozen_string_literal: true

require 'json'

#
# calibration.rb — standardisation des densités sur un corpus (notes §5).
#
# Les densités brutes des critères n'ont pas la même échelle (sur les
# échantillons : générale ≈ 0.22, positionnelle ≈ 0.03, rythme ≈ 0.06) :
# à poids égaux, la répétition générale pèse ~70 % du score. Une calibration
# retient, par critère, la moyenne et l'écart-type de la densité sur un
# corpus ; chaque densité est alors centrée-réduite avant pondération
#     z = (densité − moyenne) / écart-type
# si bien qu'un poids de 1.0 a le même sens pour tous les critères, et que le
# score se lit en écarts-types : 0 = poème moyen du corpus, > 0 = plus dense.
#
# Les densités dépendent des réglages des critères (proximity_lambda, etc.) :
# la calibration enregistre ceux utilisés (+settings+) pour pouvoir signaler
# une calibration appliquée avec d'autres réglages.
#

module Claudel
  # Statistiques de calibration (voir en-tête).
  # - +stats+    : { critère => { mean:, sd: } }
  # - +n+        : nombre de poèmes du corpus
  # - +settings+ : réglages des critères au moment de la calibration
  Calibration = Struct.new(:stats, :n, :settings, keyword_init: true)

  class Calibration
    # Clés de config qui ne changent pas les densités (exclues de +settings+).
    NEUTRAL_KEYS = %i[weights calibration].freeze

    # Calibration de référence livrée avec le gem : 104 poèmes de vers libre
    # contemporain. Les z se lisent par rapport à cette norme (un poème rimé
    # classique ressort nettement positif) — voir README.
    REFERENCE_PATH = File.expand_path('../../data/calibration.json', __dir__)

    class << self
      # @return [Calibration] la calibration de référence (REFERENCE_PATH)
      def reference = load(REFERENCE_PATH)

      # Calibre sur un corpus déjà scoré (scores non calibrés). Les poèmes
      # sans phones (fichier vide…) sont ignorés : leurs densités nulles
      # fausseraient moyenne et écart-type.
      # @param results [Array<ScoreResult>]
      # @param config [Hash] réglages utilisés pour scorer +results+
      # @return [Calibration]
      # @raise [ArgumentError] si aucun poème non vide
      def fit(results, config: {})
        results = results.select { |r| r.total_phones.positive? }
        raise ArgumentError, 'calibration : corpus vide' if results.empty?

        new(stats: density_stats(results), n: results.size, settings: settings_of(config))
      end

      # @return [Hash{Symbol => Hash}] { critère => { mean:, sd: } }
      def density_stats(results)
        results.first.criteria.keys.to_h do |key|
          values = results.map { |r| r.criteria[key][:density] }
          [key, { mean: mean(values), sd: sd(values) }]
        end
      end

      # @param path [String] fichier JSON écrit par #save
      # @return [Calibration]
      def load(path)
        data = JSON.parse(File.read(path), symbolize_names: true)
        new(stats: data.fetch(:stats), n: data.fetch(:n), settings: data.fetch(:settings, {}))
      rescue KeyError, JSON::ParserError => e
        raise ArgumentError, "calibration invalide (#{path}) : #{e.message}"
      end

      # Réglages EFFECTIFS des critères (DEFAULTS de chaque critère + +config+),
      # ceux qui influent sur les densités : un défaut modifié dans le code
      # (ex. rhyme_lambda) rend donc une ancienne calibration incompatible.
      # Sous forme JSON (symboles -> chaînes) : comparables avant et après
      # #save/#load.
      # @return [Hash]
      def settings_of(config)
        defaults = Criteria.all.reduce({}) { |acc, c| Criteria.merge_config(acc, c::DEFAULTS) }
        effective = Criteria.merge_config(defaults, config.except(*NEUTRAL_KEYS))
        JSON.parse(JSON.generate(effective), symbolize_names: true)
      end

      def mean(values) = values.sum / values.size.to_f

      # Écart-type de population (le corpus est la référence, pas un échantillon).
      def sd(values)
        avg = mean(values)
        Math.sqrt(values.sum { |v| (v - avg)**2 } / values.size)
      end
    end

    # Densité centrée-réduite ; 0.0 si le critère est constant sur le corpus.
    # @param key [Symbol] critère
    # @param density [Float]
    # @return [Float]
    # @raise [ArgumentError] si le critère est absent de la calibration
    def standardize(key, density)
      stat = stats[key] or raise ArgumentError, "calibration : critère #{key} absent"
      stat[:sd].positive? ? (density - stat[:mean]) / stat[:sd] : 0.0
    end

    # @return [Boolean] +config+ a les mêmes réglages de critères que la calibration
    def matches?(config)
      Calibration.settings_of(config) == settings
    end

    # @param path [String]
    def save(path)
      File.write(path, "#{JSON.pretty_generate(to_h)}\n")
    end
  end
end
