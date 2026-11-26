# frozen_string_literal: true

#
# criteria.rb — registre des critères de densité phonétique (notes §5).
#
# Chaque critère est un module enregistré ici, exposant :
#   .name                    -> Symbol (clé de configuration)
#   .default_weight          -> poids par défaut
#   .raw_score(poem, config) -> score BRUT (non normalisé)
# Le poids effectif se règle via config[:weights][name] : ajouter un critère
# ou modifier les pondérations ne demande AUCUN changement de code (notes §5).
#

module Claudel
  # Registre des critères (voir en-tête).
  module Criteria
    @registry = {}

    class << self
      # Enregistre un critère (module répondant à .name / .default_weight / .raw_score).
      # @param criterion [Module]
      def register(criterion)
        @registry[criterion.name] = criterion
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
    end
  end
end
