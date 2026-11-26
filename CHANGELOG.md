# Changelog

## 0.1.0 (2026-11-26)

- Poids des phones à 0 par défaut dans `repetition_generale` (expérimental :
  seules les syllabes et inversées comptent ; réglable via `unit_weights`).

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
