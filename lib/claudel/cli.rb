# frozen_string_literal: true

require_relative '../claudel' unless defined?(Claudel)

#
# cli.rb — ligne de commande de claudel (via bin/claudel).
#
#   claudel --version
#   claudel [--mode auto|classique|contemporain] [--repetitions] <fichier...>
#
# Chaque fichier = un poème (un vers par ligne, lignes vides ignorées) ;
# le rapport affiche le score global de densité phonétique et le détail
# par critère (brut, densité, poids — voir docs/notes_claudel.txt).
# --repetitions ajoute le détail de chaque répétition identifiée
# (position, distance, proximité, pénalité de mot, contribution).
#

module Claudel
  class << self
    # Point d'entrée CLI.
    # @param argv [Array<String>]
    # @return [Integer] code de sortie
    def main(argv = ARGV)
      return version_output if argv.empty? || argv.include?('--version')

      mode, files, verbose = parse_args(argv)
      return usage_error if files.empty?

      files.each { |f| report(f, mode, verbose: verbose) }
      0
    rescue Errno::ENOENT => e
      warn "fichier introuvable : #{e.message}"
      1
    end

    def version_output
      puts "claudel #{VERSION}"
      0
    end

    def usage_error
      warn 'usage: claudel [--mode auto|classique|contemporain] [--repetitions] <fichier...>'
      1
    end

    # @param argv [Array<String>]
    # @return [Array(Symbol, Array<String>, Boolean)] mode, fichiers, verbose
    def parse_args(argv)
      args = argv.dup
      verbose = !args.delete('--repetitions').nil?
      mode = args.include?('--mode') ? shift_mode(args) : :auto
      args.grep(/\A--mode=/) { |a| mode = a.sub('--mode=', '').to_sym }
      [mode, args.reject { |a| a == '--mode' || a.start_with?('--mode=') }, verbose]
    end

    def shift_mode(args)
      i = args.index('--mode')
      mode = (args.delete_at(i + 1) || 'auto').to_sym
      args.delete_at(i)
      mode
    end

    # Rapport de densité phonétique d'un fichier de poème.
    # @param path [String]
    # @param mode [Symbol]
    # @param verbose [Boolean] détail des répétitions (--repetitions)
    def report(path, mode, verbose: false)
      lines = File.readlines(path, chomp: true).map(&:strip).reject(&:empty?)
      poem = Claudel.analyze(lines, mode: mode)
      result = Claudel.score(poem)
      puts header(path, result)
      puts format('score de densité phonétique : %<score>.5f', score: result.score)
      result.criteria.each { |name, detail| puts criterion_line(name, detail) }
      print_repetitions(poem) if verbose
    end

    def header(path, result)
      format('== %<path>s (%<verses>d vers, %<phones>d phones)',
             path: path, verses: result.verses, phones: result.total_phones)
    end

    def criterion_line(name, detail)
      format('  %<name>-24s poids %<weight>4.1f  brut %<raw>9.3f  densité %<density>.5f',
             name: name, weight: detail[:weight], raw: detail[:raw], density: detail[:density])
    end

    # Rapport détaillé des répétitions identifiées (heuristiques, notes §2/§3).
    def print_repetitions(poem, top: 40)
      print_general(poem, top)
      print_positional(poem)
      puts format('-- signatures rythmiques : %s', signatures(poem))
    end

    def signatures(poem)
      poem.map { |analysis| Scansion::Rythme.signature(analysis).inspect }.join(' ')
    end

    def print_general(poem, top)
      reps = Claudel::Criteria::RepetitionGenerale.explain(poem)
      puts format('-- répétitions générales : %<n>d unités, brut %<t>.3f (top %<k>d) --',
                  n: reps.size, t: reps.sum(&:total), k: [top, reps.size].min)
      reps.first(top).each { |rep| puts general_block(rep) }
    end

    def general_block(rep)
      head = format('  [%<type>s %<form>s] valeur %<value>.1f, %<count>d occ., total %<total>.3f',
                    type: rep.type, form: rep.form, value: rep.value,
                    count: rep.occurrences.size, total: rep.total)
      ([head] + rep.pairs.map { |pair| general_pair(pair) }).join("\n")
    end

    def general_pair(pair)
      from = pair[:from]
      to = pair[:to]
      format('    v%<v1>d@%<s1>d "%<w1>s" -> v%<v2>d@%<s2>d "%<w2>s" : ' \
             'd=%<d>d prox=%<p>.3f mot×%<f>.1f contrib=%<c>.3f',
             v1: from.verse, s1: from.start, w1: from.word, v2: to.verse, s2: to.start, w2: to.word,
             d: pair[:distance], p: pair[:proximite], f: pair[:word_factor], c: pair[:contribution])
    end

    def print_positional(poem)
      reps = Claudel::Criteria::RepetitionPositionnelle.explain(poem)
      puts format('-- répétitions positionnelles : %<n>d formes, brut %<t>.3f --',
                  n: reps.size, t: reps.sum(&:total))
      reps.each { |rep| puts positional_block(rep) }
    end

    def positional_block(rep)
      head = format('  [rime %<form>s] valeur %<value>d, %<count>d occ., total %<total>.3f',
                    form: rep.form, value: rep.value, count: rep.occurrences.size, total: rep.total)
      ([head] + rep.pairs.map { |pair| positional_pair(pair) }).join("\n")
    end

    def positional_pair(pair)
      from = pair[:from]
      to = pair[:to]
      format('    v%<v1>d %<k1>s -> v%<v2>d %<k2>s : poids min %<w>.1f, contrib=%<c>.3f',
             v1: from.verse, k1: from.klass, v2: to.verse, k2: to.klass,
             w: pair[:weight], c: pair[:contribution])
    end
  end
end
