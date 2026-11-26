# frozen_string_literal: true

require_relative 'lib/claudel/version'

Gem::Specification.new do |spec|
  spec.name          = 'claudel'
  spec.version       = Claudel::VERSION
  spec.authors       = ['anantone']
  spec.summary       = 'Score de densité phonétique par poème, au-dessus de scansion'
  spec.description   = 'claudel consomme les caractéristiques mesurables du gem ' \
                       'scansion (syllabes IPA, groupes rythmiques, accents, signature ' \
                       'rythmique) et calcule un score global de densité phonétique ' \
                       'par poème. Voir docs/notes_claudel.txt pour la feuille de route.'
  spec.license       = 'MIT'
  spec.required_ruby_version = '>= 3.1'
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files         = Dir['lib/**/*.rb'] + Dir['docs/**/*.txt'] + %w[LICENSE README.md CHANGELOG.md]
  spec.bindir        = 'bin'
  spec.executables   = ['claudel']
  spec.require_paths = ['lib']

  spec.add_dependency 'scansion', '~> 3.0'
end
