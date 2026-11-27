#!/usr/bin/env ruby
# frozen_string_literal: true

#
# split_corpus.rb — prépare un corpus pour `claudel --calibrate`.
#
# La calibration traite chaque fichier comme un poème. Un corpus se présente
# rarement ainsi : recueil d'un seul tenant, pièces de théâtre de 1 500 vers…
# Ce script écrit dans DOSSIER un fichier par unité de calibration :
#
#   (défaut)     un fichier source = une unité (copie, lignes vides retirées)
#   --poems N    un fichier source = un recueil, dont les poèmes sont séparés
#                par au moins N lignes vides consécutives
#   --blocks N   chaque source est découpée en blocs de N vers ; le dernier
#                bloc, incomplet, est ignoré (N pair : distiques préservés)
#
# Options communes :
#   --skip-title     ignore la première ligne non vide de chaque source
#   --exclude REGEX  ignore les sources dont le nom correspond
#
# Exemple :
#   ruby script/split_corpus.rb --blocks 20 --skip-title -o /tmp/racine racine/*.txt
#   claudel --calibrate ma_calibration.json /tmp/racine/*.txt
#

require 'fileutils'
require 'optparse'

module SplitCorpus
  module_function

  USAGE = 'usage: split_corpus.rb [--poems N | --blocks N] [--skip-title] [--exclude REGEX] -o DOSSIER SOURCE...'

  def parse(argv)
    opts = { mode: :file }
    parser(opts).parse!(argv)
    abort "split_corpus: -o DOSSIER et au moins une source requis\n#{USAGE}" if opts[:out].nil? || argv.empty?
    opts.merge(sources: argv.sort.reject { |f| opts[:exclude]&.match?(File.basename(f)) })
  end

  def parser(opts)
    OptionParser.new(USAGE) do |p|
      p.on('--poems N', Integer) { |n| opts.merge!(mode: :poems, n: n) }
      p.on('--blocks N', Integer) { |n| opts.merge!(mode: :blocks, n: n) }
      p.on('--skip-title') { opts[:skip_title] = true }
      p.on('--exclude REGEX', Regexp) { |r| opts[:exclude] = r }
      p.on('-o', '--output DOSSIER') { |d| opts[:out] = d }
    end
  end

  # @return [Array<Array<String>>] unités (listes de vers) d'une source
  def units(text, opts)
    chunks = verse_chunks(text, opts)
    chunks[0] = chunks[0].drop(1) if opts[:skip_title] && chunks.any?
    return chunks unless opts[:mode] == :blocks

    chunks.flatten.each_slice(opts[:n]).select { |b| b.size == opts[:n] }
  end

  # Texte coupé en poèmes (--poems) ou d'un seul tenant ; vers sans lignes vides.
  def verse_chunks(text, opts)
    chunks = opts[:mode] == :poems ? text.split(/\n(?:[ \t]*\n){#{opts[:n]},}/) : [text]
    chunks.map { |c| c.lines.map(&:strip).reject(&:empty?) }.reject(&:empty?)
  end

  # @return [Integer] nombre d'unités écrites pour +src+
  def write_units(src, opts)
    list = units(File.read(src), opts)
    base = File.basename(src, '.*')
    list.each.with_index(1) do |verses, i|
      File.write(File.join(opts[:out], format('%<base>s-%<i>03d.txt', base: base, i: i)), "#{verses.join("\n")}\n")
    end
    list.size
  end

  def run(argv)
    opts = parse(argv)
    FileUtils.mkdir_p(opts[:out])
    total = opts[:sources].sum { |src| write_units(src, opts) }
    puts "split_corpus: #{opts[:sources].size} sources -> #{total} unités dans #{opts[:out]}"
  end
end

SplitCorpus.run(ARGV) if $PROGRAM_NAME == __FILE__
