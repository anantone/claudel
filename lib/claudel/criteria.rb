# frozen_string_literal: true

#
# criteria.rb — registre des critères de densité phonétique (notes §5).
#
# Chaque critère est un module enregistré ici, exposant :
#   .key                     -> Symbol (clé de configuration ; pas .name,
#                               qui doit rester le nom du module Ruby)
#   .default_weight          -> poids par défaut
#   .raw_score(poem, config) -> score BRUT (non normalisé)
# Le poids effectif se règle via config[:weights][key] : ajouter un critère
# ou modifier les pondérations ne demande AUCUN changement de code (notes §5).
#

module Claudel
  # Registre des critères (voir en-tête).
  module Criteria
    @registry = {}

    class << self
      # Enregistre un critère (module répondant à .key / .default_weight / .raw_score).
      # @param criterion [Module]
      def register(criterion)
        @registry[criterion.key] = criterion
      end

      # @return [Array<Module>] tous les critères enregistrés
      def all
        @registry.values
      end

      # @param name [Symbol]
      # @return [Module, nil] le critère nommé +name+
      def [](name)
        @registry[name]
      end

      # Fusionne +config+ sur les +defaults+ d'un critère, en fusionnant aussi
      # les sous-hashes (ex. unit_weights, position_weights) : surcharger une
      # seule clé imbriquée conserve les autres valeurs par défaut.
      # @param defaults [Hash]
      # @param config [Hash]
      # @return [Hash]
      def merge_config(defaults, config)
        defaults.merge(config) do |_key, default, value|
          default.is_a?(Hash) && value.is_a?(Hash) ? default.merge(value) : value
        end
      end
    end
  end
end
