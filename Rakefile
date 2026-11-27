# frozen_string_literal: true

require 'rspec/core/rake_task'
require 'rubocop/rake_task'

RSpec::Core::RakeTask.new(:spec)
RuboCop::RakeTask.new

task default: %i[spec rubocop]

# Calibrations d'exemple de data/ (voir data/README.md). Les corpus ne sont
# pas dans le dépôt : CORPUS_DIR pointe sur le dossier qui contient samples/,
# chatiments.txt et racine_txt/ (défaut : poems/ruby, deux niveaux au-dessus).
desc "Régénère les calibrations d'exemple de data/ (CORPUS_DIR=…)"
task :calibrations do
  require 'tmpdir'
  corpus = File.expand_path(ENV.fetch('CORPUS_DIR', '../..'), __dir__)
  split = ['ruby', 'script/split_corpus.rb']
  claudel = ['ruby', '-Ilib', 'bin/claudel']
  Rake::FileUtilsExt.verbose_flag = false
  Dir.mktmpdir do |tmp|
    sh(*claudel, '--calibrate', 'data/calibration.json', *Dir[File.join(corpus, 'samples/*.txt')])

    sh(*split, '--poems', '3', '-o', "#{tmp}/chatiments", File.join(corpus, 'chatiments.txt'))
    sh(*claudel, '--calibrate', 'data/calibration_chatiments.json', *Dir["#{tmp}/chatiments/*.txt"])

    sh(*split, '--blocks', '20', '--skip-title', '--exclude', '-\d\d\.txt\z', '-o', "#{tmp}/racine",
       *Dir[File.join(corpus, 'racine_txt/*.txt')])
    sh(*claudel, '--calibrate', 'data/calibration_racine.json', *Dir["#{tmp}/racine/*.txt"])
  end
end
