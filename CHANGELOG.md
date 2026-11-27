# Changelog

## 0.1.0 (2026-11-26)

- **Proximité en vers** pour la répétition positionnelle : poids plein
  jusqu'à 3 vers d'écart (`rhyme_plateau`, règle classique des deux
  couleurs : plates, croisées, embrassées, sonnet, ballade, terza rima
  intactes), puis décroissance `e^(−(Δv−3)/(λ·phones/2))`, `rhyme_lambda: 4.0`
  (une rime épaisse porte plus loin). Corrige le biais de longueur :
  corrélation densité positionnelle / nombre de vers +0.45 -> +0.09.
  `--repetitions` affiche `Δv` et `prox` par paire. `Claudel::Positions`
  extrait de la répétition positionnelle.
- La calibration enregistre les réglages effectifs, défauts compris : une
  calibration faite avant un changement de défaut est signalée.
- Calibrations d'exemple livrées dans `data/` : `calibration.json` (104
  poèmes contemporains ; `Claudel::Calibration.reference`,
  `--calibration reference`), `calibration_chatiments.json` (Hugo, 106
  poèmes), `calibration_racine.json` (Racine, 989 blocs de 20 vers).
  Provenance et découpage : `data/README.md` ; régénération :
  `bundle exec rake calibrations`.
- `script/split_corpus.rb` : prépare un corpus pour `--calibrate` (recueil
  d'un seul tenant coupé aux lignes vides, longs textes en blocs de N vers).
- README : section « Calibrer sur son propre corpus — en bref ».
- **Calibration** (`Claudel::Calibration`, optionnelle) : moyenne et
  écart-type de la densité de chaque critère sur un corpus ; avec
  `config: { calibration: }`, `Claudel.score` combine les densités
  centrées-réduites (`criteria[k][:standardized]`, `ScoreResult#calibrated`)
  et le score se lit en écarts-types. Sur les échantillons, chaque critère
  explique alors 1/3 de la variance du score (contre 55/23/22 %). CLI :
  `--calibrate cal.json` (corpus -> JSON) et `--calibration cal.json`
  (rapport avec z par critère ; avertit si les réglages diffèrent).
- Correctifs config : `proximite` calcule en flottants (un réglage entier
  comme `proximity_lambda: 60` ou `proximity_a: 2` ne bascule plus en
  division entière) ; `Criteria.merge_config` fusionne aussi les sous-hashes
  (`unit_weights`, `position_weights`) — surcharger une seule clé conserve les
  autres défauts au lieu de les mettre à 0 ou de planter.
- CLI réécrit avec `OptionParser` : `--help` ; option inconnue -> usage +
  exit 1 (n'est plus prise pour un fichier) ; sans argument -> usage (et non
  plus la version) ; `--mode=v --mode w` ne laisse plus `w` passer pour un
  fichier ; un fichier en échec (introuvable, illisible, dossier) est signalé
  sans interrompre les suivants, exit 1.
- Positionnel : une position dont la forme reste sous `min_phones` (syllabe
  d'un phone en début de vers) est ignorée ; `VerseContext` remplace les
  8 paramètres de `occurrence_at` (exception rubocop `ParameterLists` retirée).
- **API** : la clé d'un critère est `.key` (et non plus `.name`, qui masquait
  `Module#name`).
- Rapports `explain` : ex aequo départagés par type puis forme (ordre stable).
- Outillage : rubocop dans le Gemfile, `rake` lance specs + rubocop ; specs
  réparties en `criteria_spec`, `score_spec`, `cli_spec`.

- Repli `phone:` à 0 par défaut dans `unit_weights` de `repetition_generale` :
  un phone n'est valorisé que via sa classe (`voyelle:` 0.8, `consonne:` 0.5).
- CLI : nouvelles options `--weights k=w,k=w` et `--set clé=valeur`
  (notation pointée pour les réglages imbriqués, ex. `unit_weights.consonne=0.3`)
  pour régler la pondération sans code ; `--mean` affiche la moyenne des scores
  sur tous les fichiers (comparaison de corpus).
- `docs/references.md` : sources réunies pour la pondération (aesthetics
  empirique Menninghaus/Obermeier, vers libre et assonance, entropie du rythme).
- CLI : `--mode` validé via la liste de candidats d'OptionParser (message
  « invalid argument: --mode zzz » propre, les deux formes `--mode v` et
  `--mode=v`) ; `report_file` rescatte `StandardError` (plus seulement
  `SystemCallError`) avec `e.message` — un fichier qui plante ne stoppe plus
  les suivants.
- Revue de code : `--mode` validé (`Claudel::MODES`, usage + exit 1 si valeur
  invalide ou manquante — le nom de fichier n'est plus mangé comme mode) ;
  `ScoreResult#criteria` transporte désormais les répétitions détaillées
  (`repetitions:`), calculées une seule fois par `Claudel.score` — le CLI
  `--repetitions` ne recalcule plus ; spec affriquée multi-codepoints (U+0361),
  spec épinglant la récurrence sur la seule signature dominante ; README : table
  des réglages ; notes : limitation connue de l'heuristique mot dérivé
  (homophones « mer »/« mère » plein crédit, « comment »/« commencer » pénalisés).
- Distinction **assonance / allitération** au niveau phone : `Phonemes.vowel?`
  classe chaque phone (voyelle, nasales incluses ; glides = consonnes) ;
  `unit_weights` accepte `voyelle:` (0.8) et `consonne:` (0.5), avec `:phone`
  comme repli. Le rapport `--repetitions` étiquette `[voyelle …]`/`[consonne …]`.

- Échafaudage du gem (gemspec, Gemfile, Rakefile, `.rspec`, `bin/claudel`).
- `Claudel::Phonemes` : découpage des syllabes IPA en phones (1 phone = 1
  phone même sur plusieurs codepoints : voyelles nasales, affriquées).
- `Claudel::Units` : extraction des unités de répétition (phone, syllabe,
  syllabe inversée >= 2 phones) avec position absolue en phones et mot
  d'origine.
- `docs/notes_claudel.txt` : feuille de route et décisions sur les questions
  ouvertes (seuils, proximité, pondérations, normalisation).
- Registre `Claudel::Criteria` (poids configurables sans changer le code) et
  trois critères : `RepetitionGenerale` (k−1 répétitions, distance absolue en
  phones, pénalité même mot/dérivé), `RepetitionPositionnelle` (fin de vers /
  césure / fins de groupe, poids 1.0/0.7/0.5), `PatternsRythmiques`
  (signature + régularité par vers, récurrence des signatures).
- `Claudel.score` : score global de densité phonétique par poème (densités
  normalisées par le nombre total de phones, combinaison pondérée).
- CLI `claudel [--mode ...] [--repetitions] <fichier...>` : rapport par
  critère, et avec `--repetitions` le détail de chaque répétition identifiée.
- `explain` sur les deux critères de répétition (détail des paires :
  distance, proximité, pénalité de mot, contribution) ; `raw_score` s'appuie
  dessus.
- Correction : un vers sans syllabes (ex. « _13/11/2008_ » mal phonétisé) ne
  fait plus planter le critère positionnel.
- Mots fonctionnels (listes scansion, `Units.function_word?`) : les
  syllabes/inversées de mots fonctionnels sont ignorées (critère 1), les
  phones de mots fonctionnels ne comptent qu'en paire intra-vers (critère 1),
  et une rime/position portée par un mot fonctionnel est ignorée (critère 2).
  Flags : `drop_function_word_syllables`, `function_word_phones_intra_verse_only`.
