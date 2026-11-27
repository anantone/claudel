# frozen_string_literal: true

require 'optparse'
require_relative '../claudel' unless defined?(Claudel)

#
# cli.rb — ligne de commande de claudel (via bin/claudel).
#
#   claudel --version | --help
#   claudel [--mode auto|classique|contemporain] [--repetitions] [--mean]
#           [--weights k=w,k=w] [--set clé=valeur]... <fichier...>
#
# Chaque fichier = un poème (un vers par ligne, lignes vides ignorées) ;
# le rapport affiche le score global de densité phonétique et le détail
# par critère (brut, densité, poids — voir docs/notes_claudel.txt).
# --repetitions ajoute le détail de chaque répétition identifiée
# (position, distance, proximité, pénalité de mot, contribution) ;
# --weights / --set règlent la pondération (ex. --weights repetition_generale=2.0
# ou --set unit_weights.consonne=0.3) ; --mean affiche la moyenne des scores
# sur tous les fichiers (comparaison de corpus).
#

module Claudel
  # Modes de scansion acceptés par --mode.
  MODES = %i[auto classique contemporain].freeze

  class << self
    USAGE = 'usage: claudel [--mode auto|classique|contemporain] [--repetitions] [--mean] ' \
            '[--weights k=w,k=w] [--set clé=valeur]... [--calibration cal.json|reference | --calibrate cal.json] ' \
            '<fichier...>'

    # Point d'entrée CLI. Une erreur sur un fichier (introuvable, illisible…)
    # est signalée sans interrompre les fichiers suivants.
    # @param argv [Array<String>]
    # @return [Integer] code de sortie (1 si usage invalide ou un fichier en échec)
    def main(argv = ARGV)
      opts = parse_args(argv)
      return usage_error(opts[:error]) if opts[:error]
      return version_output if opts[:version]
      return help_output if opts[:help]

      report_files(opts)
    end

    # @return [Integer] code de sortie
    def report_files(opts)
      return usage_error if opts[:files].empty?
      return usage_error('--calibrate et --calibration sont exclusifs') if opts[:calibrate] && opts[:calibration]
      return calibrate(opts) if opts[:calibrate]
      return 1 if opts[:calibration] && !apply_calibration(opts)

      report_all(opts)
    end

    # @return [Integer] code de sortie (1 si un fichier a échoué)
    def report_all(opts)
      results = opts[:files].filter_map { |f| report_file(f, opts) }
      print_mean(results) if opts[:mean] && results.any?
      results.size == opts[:files].size ? 0 : 1
    end

    # --calibrate : score le corpus (sans rapport par fichier) et enregistre
    # moyenne / écart-type de la densité de chaque critère.
    # @return [Integer] code de sortie
    def calibrate(opts)
      results = opts[:files].filter_map { |f| score_file_safely(f, opts) }
      return 1 if results.empty?

      calibration = Calibration.fit(results, config: opts[:config])
      calibration.save(opts[:calibrate])
      print_calibration(calibration, opts[:calibrate])
      results.size == opts[:files].size ? 0 : 1
    end

    def print_calibration(calibration, path)
      puts format('== calibration : %<n>d poèmes -> %<path>s', n: calibration.n, path: path)
      calibration.stats.each do |key, stat|
        puts format('  %<key>-24s moyenne %<mean>.5f  écart-type %<sd>.5f', key: key, **stat)
      end
    end

    # --calibration : charge le fichier dans opts[:config][:calibration].
    # @return [Boolean] succès
    def apply_calibration(opts)
      calibration = Calibration.load(calibration_path(opts[:calibration]))
      unless calibration.matches?(opts[:config])
        warn "claudel: attention, #{opts[:calibration]} a été calculée avec d'autres réglages " \
             "(#{calibration.settings.inspect})"
      end
      opts[:config] = opts[:config].merge(calibration: calibration)
      true
    rescue ArgumentError, SystemCallError => e
      warn "claudel: #{e.message}"
      false
    end

    # Le mot « reference » désigne la calibration livrée avec le gem
    # (Calibration::REFERENCE_PATH) ; un fichier local de ce nom : ./reference.
    def calibration_path(arg)
      arg == 'reference' ? Calibration::REFERENCE_PATH : arg
    end

    # Moyenne des scores sur plusieurs fichiers (comparaison de corpus).
    def print_mean(results)
      scores = results.map(&:score)
      puts format('== moyenne : %<n>d fichiers, score %<mean>.5f (médiane %<med>.5f, min %<min>.5f, max %<max>.5f)',
                  n: results.size, mean: scores.sum / results.size, med: scores.sort[scores.size / 2],
                  min: scores.min, max: scores.max)
    end

    def version_output
      puts "claudel #{VERSION}"
      0
    end

    def help_output
      puts USAGE
      0
    end

    def usage_error(message = nil)
      warn "claudel: #{message}" if message
      warn USAGE
      1
    end

    # @param argv [Array<String>]
    # @return [Hash] :mode, :files, :verbose, :version, :help ; :error (message)
    #   si une option est inconnue, ou --mode invalide ou sans valeur
    def parse_args(argv)
      opts = { mode: :auto, verbose: false, version: false, help: false, mean: false, config: {} }
      opts[:files] = option_parser(opts).parse(argv)
      opts
    rescue OptionParser::ParseError => e
      { error: e.message }
    end

    # --version et --help sont définis ici : ceux intégrés à OptionParser
    # appelleraient exit, ce que Claudel.main (testable) ne doit pas faire.
    def option_parser(opts)
      OptionParser.new do |parser|
        # liste de candidats : OptionParser valide --mode et --mode=v
        # ("invalid argument: --mode zzz") sans avaler le fichier suivant
        parser.on('--mode MODE', MODES.map(&:to_s)) { |v| opts[:mode] = v.to_sym }
        parser.on('--repetitions') { opts[:verbose] = true }
        parser.on('--mean') { opts[:mean] = true }
        parser.on('--version') { opts[:version] = true }
        parser.on('-h', '--help') { opts[:help] = true }
        define_config_options(parser, opts)
      end
    end

    def define_config_options(parser, opts)
      parser.on('--weights k=w,...') { |v| v.split(',').each { |pair| add_config(opts, "weights.#{pair}") } }
      parser.on('--set clé=valeur') { |v| add_config(opts, v) }
      parser.on('--calibrate FICHIER') { |v| opts[:calibrate] = v }
      parser.on('--calibration FICHIER') { |v| opts[:calibration] = v }
    end

    # « a.b=1.5 » -> fusion profonde dans opts[:config] ({ a: { b: 1.5 } }).
    # @raise [OptionParser::ParseError] si le « =valeur » manque
    def add_config(opts, arg)
      key, val = arg.split('=', 2)
      raise OptionParser::ParseError, "attendu clé=valeur, reçu « #{arg} »" if val.nil?

      parsed = key.split('.').map(&:to_sym).reverse.reduce(parse_value(val)) { |acc, k| { k => acc } }
      opts[:config] = Criteria.merge_config(opts[:config], parsed)
    end

    # « 2 » -> 2, « 0.5 » -> 0.5, « true » -> true, sinon String.
    def parse_value(val)
      case val
      when /\A-?\d+\z/ then val.to_i
      when /\A-?\d+\.\d+\z/ then val.to_f
      when 'true' then true
      when 'false' then false
      else val
      end
    end

    # Rapport d'un fichier ; toute erreur (lecture, scansion…) est signalée
    # sur stderr sans interrompre les fichiers suivants.
    # @return [ScoreResult, false] le résultat, ou false en cas d'échec
    def report_file(path, opts)
      report(path, opts[:mode], verbose: opts[:verbose], config: opts[:config])
    rescue StandardError => e
      warn "claudel: #{path} : #{e.message}"
      false
    end

    # Comme report_file, sans affichage (corpus de --calibrate).
    # @return [ScoreResult, false]
    def score_file_safely(path, opts)
      Claudel.score(read_poem(path), mode: opts[:mode], config: opts[:config])
    rescue StandardError => e
      warn "claudel: #{path} : #{e.message}"
      false
    end

    # @return [Array<String>] vers non vides du fichier
    def read_poem(path)
      File.readlines(path, chomp: true).map(&:strip).reject(&:empty?)
    end

    # Rapport de densité phonétique d'un fichier de poème.
    # @param path [String]
    # @param mode [Symbol]
    # @param verbose [Boolean] détail des répétitions (--repetitions)
    # @param config [Hash] réglages (--weights / --set)
    # @return [ScoreResult]
    def report(path, mode, verbose: false, config: {})
      poem = Claudel.analyze(read_poem(path), mode: mode)
      result = Claudel.score(poem, config: config)
      puts header(path, result)
      puts score_line(result)
      result.criteria.each { |name, detail| puts criterion_line(name, detail) }
      print_repetitions(result, poem) if verbose
      result
    end

    def header(path, result)
      format('== %<path>s (%<verses>d vers, %<phones>d phones)',
             path: path, verses: result.verses, phones: result.total_phones)
    end

    def score_line(result)
      return format('score de densité phonétique : %<score>.5f', score: result.score) unless result.calibrated

      format('score de densité phonétique (calibré, en écarts-types) : %<score>+.3f', score: result.score)
    end

    def criterion_line(name, detail)
      line = format('  %<name>-24s poids %<weight>4.1f  brut %<raw>9.3f  densité %<density>.5f',
                    name: name, weight: detail[:weight], raw: detail[:raw], density: detail[:density])
      detail[:standardized] ? format('%<line>s  z %<z>+.2f', line: line, z: detail[:standardized]) : line
    end

    # Rapport détaillé des répétitions identifiées (heuristiques, notes §2/§3).
    # Utilise les répétitions déjà calculées par Claudel.score (pas de double calcul).
    def print_repetitions(result, poem, top: 40)
      print_general(result.criteria[:repetition_generale][:repetitions], top)
      print_positional(result.criteria[:repetition_positionnelle][:repetitions])
      puts format('-- signatures rythmiques : %s', signatures(poem))
    end

    def signatures(poem)
      poem.map { |analysis| Scansion::Rythme.signature(analysis).inspect }.join(' ')
    end

    def print_general(reps, top)
      puts format('-- répétitions générales : %<n>d unités, brut %<t>.3f (top %<k>d) --',
                  n: reps.size, t: reps.sum(&:total), k: [top, reps.size].min)
      reps.first(top).each { |rep| puts general_block(rep) }
    end

    def general_block(rep)
      head = format('  [%<label>s %<form>s] valeur %<value>.1f, %<count>d occ., total %<total>.3f',
                    label: unit_label(rep), form: rep.form, value: rep.value,
                    count: rep.occurrences.size, total: rep.total)
      ([head] + rep.pairs.map { |pair| general_pair(pair) }).join("\n")
    end

    # « voyelle »/« consonne » pour un phone, sinon le type d'unité.
    def unit_label(rep)
      return rep.type.to_s unless rep.type == :phone

      Claudel::Phonemes.vowel?(rep.form) ? 'voyelle' : 'consonne'
    end

    def general_pair(pair)
      from = pair[:from]
      to = pair[:to]
      format('    v%<v1>d@%<s1>d "%<w1>s" -> v%<v2>d@%<s2>d "%<w2>s" : ' \
             'd=%<d>d prox=%<p>.3f mot×%<f>.1f contrib=%<c>.3f',
             v1: from.verse, s1: from.start, w1: from.word, v2: to.verse, s2: to.start, w2: to.word,
             d: pair[:distance], p: pair[:proximite], f: pair[:word_factor], c: pair[:contribution])
    end

    def print_positional(reps)
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
      format('    v%<v1>d %<k1>s -> v%<v2>d %<k2>s : poids min %<w>.1f, Δv=%<dv>d prox=%<p>.3f, contrib=%<c>.3f',
             v1: from.verse, k1: from.klass, v2: to.verse, k2: to.klass,
             w: pair[:weight], dv: pair[:verse_distance], p: pair[:proximite], c: pair[:contribution])
    end
  end
end
