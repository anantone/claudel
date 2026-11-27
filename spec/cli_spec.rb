# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'
require 'tmpdir'
require 'stringio'

RSpec.describe 'CLI' do
  it '--version affiche la version' do
    expect { Claudel.main(['--version']) }.to output(/claudel \d+\.\d+\.\d+/).to_stdout
  end

  it 'sans fichier, affiche usage et échoue' do
    expect { Claudel.main(['--mode', 'auto']) }.to output(/usage:/).to_stderr
    expect { expect(Claudel.main([])).to eq(1) }.to output(/usage:/).to_stderr
  end

  it '--help affiche l’usage sur stdout et réussit' do
    expect { expect(Claudel.main(['--help'])).to eq(0) }.to output(/usage:/).to_stdout
  end

  it 'rejette une option inconnue au lieu de la prendre pour un fichier' do
    expect { expect(Claudel.main(['--zzz', 'poeme.txt'])).to eq(1) }
      .to output(/invalid option: --zzz.*usage:/m).to_stderr
  end

  it '--mode=v puis --mode v : la dernière valeur gagne, aucun argument pris pour un fichier' do
    expect(Claudel.parse_args(%w[--mode=classique --mode contemporain f.txt]))
      .to include(mode: :contemporain, files: ['f.txt'])
  end

  it '--weights et --set construisent une config imbriquée' do
    opts = Claudel.parse_args(
      %w[--weights repetition_generale=2.0,patterns_rythmiques=0.5 --set unit_weights.consonne=0.3
         --set proximity_lambda=60 --set word_penalty=false f.txt]
    )
    expect(opts[:config]).to eq(weights: { repetition_generale: 2.0, patterns_rythmiques: 0.5 },
                                unit_weights: { consonne: 0.3 }, proximity_lambda: 60, word_penalty: false)
    expect(opts[:files]).to eq(['f.txt'])
  end

  it '--set sans « =valeur » est une erreur d’usage' do
    expect(Claudel.parse_args(['--set', 'foo'])).to have_key(:error)
  end

  it '--mean affiche la moyenne des scores sur plusieurs fichiers' do
    Tempfile.create(['a', '.txt']) do |fa|
      Tempfile.create(['b', '.txt']) do |fb|
        fa.puts 'la substance de mort'
        fb.puts 'le jour se leve sur les toits'
        fa.flush
        fb.flush
        expect { Claudel.main(['--mean', fa.path, fb.path]) }
          .to output(/== moyenne : 2 fichiers, score [\d.]+ \(médiane [\d.]+/).to_stdout
      end
    end
  end

  it '--weights change le score affiché' do
    Tempfile.create(['poeme', '.txt']) do |f|
      f.puts 'la substance de mort'
      f.flush
      run = lambda do |argv|
        old = $stdout
        $stdout = StringIO.new
        Claudel.main(argv)
        $stdout.string[/score de densité phonétique : ([\d.]+)/, 1]
      ensure
        $stdout = old
      end
      default = run.call([f.path])
      weighted = run.call(['--weights', 'repetition_generale=0', f.path])
      expect(weighted.to_f).not_to eq(default.to_f)
    end
  end

  it 'un fichier introuvable n’interrompt pas les suivants (code de sortie 1)' do
    Tempfile.create(['poeme', '.txt']) do |f|
      f.puts 'la substance de mort'
      f.flush
      code = nil
      expect { code = Claudel.main(['absent.txt', f.path]) }
        .to output(/score de densité/).to_stdout
        .and output(/absent\.txt/).to_stderr
      expect(code).to eq(1)
    end
  end

  it 'rejette un --mode invalide ou sans valeur (ne mange pas le nom de fichier)' do
    expect { Claudel.main(['--mode', 'zzz', 'poeme.txt']) }
      .to output(/invalid argument: --mode zzz.*usage:/m).to_stderr
    expect { Claudel.main(['--mode']) }.to output(/usage:/).to_stderr
    expect { Claudel.main(['--mode=zzz', 'poeme.txt']) }
      .to output(/invalid argument: --mode.*usage:/m).to_stderr
  end

  it 'signale un fichier en échec sans interrompre les suivants (exit 1)' do
    Tempfile.create(['poeme', '.txt']) do |f|
      f.puts 'la substance de mort'
      f.flush
      expect { expect(Claudel.main([f.path, '/nonexistent.txt'])).to eq(1) }
        .to output(%r{claudel: /nonexistent\.txt : No such file or directory}).to_stderr
    end
  end

  it 'produit un rapport de densité phonétique pour un fichier' do
    Tempfile.create(['poeme', '.txt']) do |f|
      f.puts 'la substance de mort'
      f.puts 's additionne au vecu'
      f.flush
      expect { Claudel.main(['--mode', 'contemporain', f.path]) }
        .to output(/score de densité phonétique : [\d.]+/).to_stdout
    end
  end

  it '--repetitions détaille les répétitions identifiées' do
    Tempfile.create(['poeme', '.txt']) do |f|
      f.puts 'la substance de mort'
      f.puts 'la mort du substance' # rime approximative en fin de vers
      f.flush
      expect { Claudel.main(['--repetitions', f.path]) }
        .to output(/répétitions générales.*répétitions positionnelles.*signatures rythmiques/m).to_stdout
    end
  end

  describe '--calibrate / --calibration' do
    around do |example|
      Dir.mktmpdir do |dir|
        @dir = dir
        example.run
      end
    end

    let(:poems) do
      { 'a.txt' => "la substance de mort\nla mort du substance\n",
        'b.txt' => "s additionne au vecu\nle vent se leve\n" }.map do |name, text|
        File.join(@dir, name).tap { |path| File.write(path, text) }
      end
    end
    let(:cal) { File.join(@dir, 'cal.json') }

    it '--calibrate enregistre moyenne et écart-type par critère, sans rapport par fichier' do
      code = nil
      expect { code = Claudel.main(['--calibrate', cal, *poems]) }
        .to output(/calibration : 2 poèmes.*repetition_generale\s+moyenne/m).to_stdout
      expect(code).to eq(0)
      expect(Claudel::Calibration.load(cal).n).to eq(2)
    end

    it '--calibration affiche le score calibré et le z de chaque critère' do
      expect { Claudel.main(['--calibrate', cal, *poems]) }.to output.to_stdout
      expect { expect(Claudel.main(['--calibration', cal, poems.first])).to eq(0) }
        .to output(/calibré, en écarts-types\) : [+-]\d\.\d{3}.*z [+-]\d\.\d{2}/m).to_stdout
    end

    it '--calibration reference utilise la calibration livrée, sans avertissement' do
      expect { expect(Claudel.main(['--calibration', 'reference', poems.first])).to eq(0) }
        .to output(/calibré, en écarts-types/).to_stdout.and output('').to_stderr
    end

    it '--calibration avertit si les réglages diffèrent de ceux de la calibration' do
      expect { Claudel.main(['--calibrate', cal, *poems]) }.to output.to_stdout
      expect { Claudel.main(['--calibration', cal, '--set', 'proximity_lambda=60', poems.first]) }
        .to output(/calibré/).to_stdout.and output(/autres réglages/).to_stderr
    end

    it 'échoue proprement : calibration introuvable, ou les deux options ensemble' do
      expect { expect(Claudel.main(['--calibration', cal, poems.first])).to eq(1) }
        .to output(/No such file/).to_stderr
      expect { expect(Claudel.main(['--calibrate', cal, '--calibration', cal, poems.first])).to eq(1) }
        .to output(/exclusifs/).to_stderr
    end
  end
end
