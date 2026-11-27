# frozen_string_literal: true

#
# positions.rb — positions remarquables d'un vers (notes §3), utilisées par
# le critère de répétition positionnelle : fin de vers, césure, fins de
# groupes rythmiques (accent de phrase ˈ, accent de mot ˌ).
#

module Claudel
  # Positions remarquables d'un vers (voir en-tête).
  module Positions
    module_function

    # Classe de chaque position remarquable d'un vers :
    # fin de vers (toujours), césure (vers de longueur paire -> milieu,
    # comme caesura_index en 8/12), fins de groupes ˈ et ˌ.
    # Priorité : fin de vers > césure > groupe.
    # @param analysis [Scansion::Accents::Analysis]
    # @return [Hash{Integer => Symbol}] indice de syllabe -> classe
    def classes(analysis)
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
  end
end
