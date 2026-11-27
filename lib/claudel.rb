# frozen_string_literal: true

#
# claudel.rb — point d'entrée du gem claudel : quantification de certaines
# caractéristiques mesurables du gem scansion, pour modéliser numériquement
# des notions comme la « densité phonétique » d'un poème.
#
# Organisation sous lib/claudel/ :
#   version.rb    Claudel::VERSION
#   phonemes.rb   Claudel::Phonemes — découpage des syllabes IPA en phones
#   unites.rb     Claudel::Units — unités de répétition (phone, syllabe,
#                 syllabe inversée) extraites d'un poème
#   positions.rb  Claudel::Positions — positions remarquables d'un vers
#   criteria.rb   Claudel::Criteria — registre des critères (notes §5)
#   criteria/*.rb les critères : RepetitionGenerale, RepetitionPositionnelle,
#                 PatternsRythmiques
#   calibration.rb Claudel::Calibration — standardisation des densités sur un corpus
#   score.rb      Claudel.score — score global de densité phonétique par poème
#   cli.rb        Claudel.main — ligne de commande (via bin/claudel)
#
# `require "claudel"` charge scansion + tout ceci sans effet de bord.
# Feuille de route : docs/notes_claudel.txt.
#

require 'scansion'

require_relative 'claudel/version'
require_relative 'claudel/phonemes'
require_relative 'claudel/unites'
require_relative 'claudel/positions'
require_relative 'claudel/criteria'
require_relative 'claudel/criteria/repetition_generale'
require_relative 'claudel/criteria/repetition_positionnelle'
require_relative 'claudel/criteria/patterns_rythmiques'
require_relative 'claudel/calibration'
require_relative 'claudel/score'
require_relative 'claudel/cli'

# Quantification des caractéristiques scansion — voir docs/notes_claudel.txt.
module Claudel
  class << self
    # Analyse un poème (liste de vers) via scansion.
    # @param lines [Array<String>] les vers
    # @param mode [Symbol] :auto (défaut), :classique ou :contemporain
    # @return [Array<Scansion::Accents::Analysis>]
    def analyze(lines, mode: :auto)
      Scansion::Accents.analyze_lines(lines, mode: mode)
    end
  end
end
