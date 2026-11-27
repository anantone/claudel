# Calibrations d'exemple

Trois calibrations (`claudel --calibrate`, voir la section « Calibration »
du README) faites sur trois corpus de nature différente. Une calibration ne
vaut que pour le corpus qui l'a produite : les z-scores se lisent par
rapport à la norme de ce corpus. Choisissez celle qui ressemble aux poèmes
que vous comparez, ou faites la vôtre.

| Fichier | Corpus | Unités | générale (moy. ± é.-t.) | positionnelle | rythme |
|---|---|---|---|---|---|
| `calibration.json` | poèmes contemporains, vers libre en majorité | 104 poèmes | 0.2198 ± 0.0366 | 0.0222 ± 0.0197 | 0.0646 ± 0.0234 |
| `calibration_chatiments.json` | Hugo, *Les Châtiments* (1853) | 106 poèmes | 0.2507 ± 0.0203 | 0.0467 ± 0.0299 | 0.0691 ± 0.0214 |
| `calibration_racine.json` | Racine, théâtre complet (12 pièces) | 989 blocs de 20 vers | 0.2368 ± 0.0175 | 0.0333 ± 0.0112 | 0.0547 ± 0.0155 |

`calibration.json` est celle qu'utilise `--calibration reference`
(`Claudel::Calibration.reference`).

## Comment elles ont été produites

Les corpus ne sont pas dans le dépôt (ils sont dans `poems/ruby/`, deux
niveaux au-dessus). Une seule commande régénère les trois fichiers :

```sh
bundle exec rake calibrations                 # corpus dans ../..
bundle exec rake calibrations CORPUS_DIR=…    # ou ailleurs
```

Elle exécute, pour chaque corpus :

- **contemporain** — `samples/*.txt`, un fichier par poème, pris tels quels :
  ```sh
  claudel --calibrate data/calibration.json samples/*.txt
  ```
- **Châtiments** — `chatiments.txt` est le recueil d'un seul tenant, sans
  titres. Les poèmes y sont séparés par 3 lignes vides ou plus (les vers
  par 1 ligne vide, les strophes et parties par 2) : la coupe à 3 lignes
  vides donne 106 poèmes, ce qui correspond au recueil, et retombe sur des
  débuts de poèmes (« L'enfant avait reçu deux balles dans la tête »,
  « Ô soldats de l'an deux ! »…). Les 6 849 vers sont tous retenus.
  ```sh
  ruby script/split_corpus.rb --poems 3 -o /tmp/chatiments chatiments.txt
  claudel --calibrate data/calibration_chatiments.json /tmp/chatiments/*.txt
  ```
- **Racine** — `racine_txt/`, une pièce par fichier, titre en première
  ligne. Les versions de première édition (`-64`, `-66`, `-68`, `-69`,
  `-77`) sont exclues : elles doubleraient cinq pièces. Une pièce entière
  fait ~1 500 vers ; sur 12 pièces, la densité ne varierait presque pas et
  l'écart-type serait artificiellement minuscule. Chaque pièce est donc
  découpée en blocs de 20 vers (pair : les rimes plates restent ensemble ;
  taille proche d'un poème), le dernier bloc incomplet est écarté — 989
  blocs, 19 780 vers.
  ```sh
  ruby script/split_corpus.rb --blocks 20 --skip-title --exclude '-\d\d\.txt\z' \
    -o /tmp/racine racine_txt/*.txt
  claudel --calibrate data/calibration_racine.json /tmp/racine/*.txt
  ```

Toutes en mode `auto` (défaut), avec les réglages par défaut des critères,
que chaque fichier enregistre.

## Quand les régénérer

Les densités dépendent des réglages (enregistrés : le CLI avertit s'ils
diffèrent, et un test vérifie que `calibration.json` correspond aux défauts)
mais aussi de l'analyse faite par **scansion** et du **mode**, qui ne sont
pas enregistrés. Après un changement de scansion ou des critères, relancez
`bundle exec rake calibrations`.

## Lecture comparée

Même poème, trois calibrations (score calibré, en écarts-types) :

| | contemporain | Châtiments | Racine |
|---|---|---|---|
| `dioptre4.txt` (contemporain) | +0.39 | −0.40 | +0.20 |
| *Phèdre*, bloc 10 | −0.32 | −1.26 | −0.91 |
| *Châtiments*, poème 1 | +0.79 | +0.13 | +1.09 |

Un texte rimé et mesuré ressort nettement positif face au corpus
contemporain (*Les Châtiments* entiers : +0.69, positionnelle z +1.16,
générale z +1.02) : c'est attendu, rimes et mètre font précisément cela.
Pour comparer des poèmes classiques entre eux, prenez une calibration
classique.
