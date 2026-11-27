# claudel

**claudel** tente de **quantifier certaines des données produites par le gem
[**scansion**](https://rubygems.org/gems/scansion)**, afin de **modéliser
numériquement** des notions comme la **densité phonétique** d'un poème
(pour l'instant — d'autres notions pourront suivre).

scansion produit les **caractéristiques mesurables** du vers : syllabes IPA et
compte, groupes rythmiques, accents de phrase (ˈ) et de mot (ˌ), césure,
signature rythmique (`Scansion::Rythme` : tailles des groupes, score de
régularité) — et applique le **tirage accentuel** en vers contemporain.

À partir de ces caractéristiques, claudel calcule un **score global de
« densité phonétique » par poème**, combinaison pondérée de plusieurs
critères (répétitions phonétiques générales, répétitions positionnelles,
patterns rythmiques). La pondération exacte est un **travail en cours** —
voir `docs/notes_claudel.txt` pour la feuille de route et les décisions
prises.

## Prérequis et installation

- Ruby >= 3.1
- le gem **scansion** (`~> 3.0`), qui phonétise via espeak-ng
  (gem `phonemizer_ffi`) — espeak-ng doit donc être installé sur le système

```sh
gem install claudel
```

Depuis les sources (développement contre la source locale de scansion) :

```sh
git clone <ce dépôt> && cd claudel
bundle install   # Gemfile : gem 'scansion', path: '../scansion'
```

## Calibrer sur son propre corpus — en bref

Sans calibration, le score mélange des critères d'échelles différentes ;
calibré, il se lit en écarts-types par rapport à **un corpus de votre
choix** (0 = poème moyen du corpus). Détails :
[Calibration sur un corpus](#calibration-sur-un-corpus).

1. **Un fichier par poème** (un vers par ligne, lignes vides ignorées) :
   ```sh
   claudel --calibrate ma_cal.json corpus/*.txt
   ```
   Si le corpus n'est pas déjà découpé ainsi, `script/split_corpus.rb`
   (dans les sources, ou `gem contents claudel | grep split_corpus`) le
   prépare : `--poems N` coupe un recueil d'un seul tenant aux suites d'au
   moins N lignes vides, `--blocks N` découpe de longs textes (théâtre…)
   en blocs de N vers ; `--skip-title`, `--exclude REGEX`. Exemple :
   ```sh
   ruby script/split_corpus.rb --blocks 20 --skip-title -o /tmp/unites pieces/*.txt
   claudel --calibrate ma_cal.json /tmp/unites/*.txt
   ```
2. **Scorer avec cette calibration** — mêmes réglages (`--set`, `--mode`)
   qu'au calibrage, sinon le CLI avertit ; les poids (`--weights`) sont
   libres :
   ```sh
   claudel --calibration ma_cal.json poeme.txt
   ```

Conseils : une centaine d'unités au moins, de taille comparable aux poèmes
que vous scorerez (un texte de 1 500 vers d'un bloc écrase l'écart-type) ;
recalibrez après une mise à jour de claudel ou de scansion. Trois
calibrations d'exemple sont livrées dans `data/` ([`data/README.md`](data/README.md)).

## Utilisation comme bibliothèque

```ruby
require 'claudel' # charge scansion + Claudel

lines = File.readlines('poeme.txt', chomp: true).map(&:strip).reject(&:empty?)
result = Claudel.score(lines, mode: :contemporain)
# mode : :auto (défaut, détection du régime), :classique ou :contemporain

result.score         # => 0.03873  score global de densité phonétique
result.total_phones  # => 100      longueur du poème en phones (normalisation)
result.verses        # => 4
result.criteria      # => { repetition_generale: { raw: 1.118, density: 0.01118, weight: 1.0 }, ... }
```

`Claudel.score` accepte aussi un poème déjà analysé
(`Array<Scansion::Accents::Analysis>`, voir `Claudel.analyze(lines, mode:)`).

### Pondération configurable

Chaque critère a un poids par défaut, réglable via `config[:weights]` — aucun
changement de code nécessaire ; chaque critère accepte aussi ses propres
réglages (voir `DEFAULTS` dans `lib/claudel/criteria/*.rb`). Récapitulatif des
réglages et de leur rôle :

| Clé de config | Défaut | Rôle |
|---|---|---|
| `weights: { <critère>: w }` | 1.0 chacun | poids relatif de chaque critère dans le score global |
| `unit_weights: { phone:, voyelle:, consonne:, syllabe:, inversee: }` | `0.0 / 0.8 / 0.5 / 1.5 / :length` | valeur par type d'unité (critère 1) ; `:length` = longueur en phones ; `:phone` = repli |
| `proximity_a`, `proximity_lambda` | 2.0, 40.0 | courbe de proximité `proximité(d) = (d/(d+a))·e^(−d/λ)` en phones |
| `word_penalty`, `root_min_length` | 0.1, 4 | pénalité si même mot / mot dérivé (préfixe commun ≥ 4) |
| `drop_function_word_syllables` | true | ignore syllabes/rimes de mots fonctionnels (critères 1 et 2) |
| `function_word_phones_intra_verse_only` | true | phones de mots fonctionnels comptés seulement en paire intra-vers (critère 1) |
| `position_weights: { fin_de_vers:, cesure:, groupe: }` | 1.0 / 0.7 / 0.5 | poids des classes de position (critère 2) |
| `min_phones` | 2 | unité min en position (rime = ≥ 2 phones ou 1 syllabe) |
| `rhyme_plateau`, `rhyme_lambda` | 3, 4.0 | critère 2 : poids plein jusqu'à 3 vers d'écart (abba, règle classique), puis `e^(−(Δv−3)/(λ·phones/2))` — une rime épaisse porte plus loin ; `rhyme_lambda: nil` = pas de décroissance |
| `verse_bonus`, `recurrence_bonus` | 1.0, 1.0 | poids du score de vers et de la récurrence de signature (critère 3) |

Chaque critère accepte aussi ses propres réglages (voir `DEFAULTS` dans
`lib/claudel/criteria/*.rb`) :

```ruby
Claudel.score(lines, mode: :contemporain, config: {
  weights: { repetition_generale: 2.0, patterns_rythmiques: 0.5 }
}) # => score 0.02353 sur l'exemple ci-dessus

Claudel.score(lines, mode: :contemporain, config: {
  proximity_lambda: 60.0,        # décroissance de la proximité (critère 1)
  word_penalty: 0.05,            # pénalité même mot / mot dérivé (critère 1)
  position_weights: { fin_de_vers: 1.0, cesure: 0.8, groupe: 0.6 } # critère 2
})
```

### Calibration sur un corpus

Les densités brutes des trois critères n'ont pas la même échelle : sur 104
poèmes d'échantillon, la répétition générale tourne autour de 0.22, la
positionnelle de 0.03 et le rythme de 0.06. À poids égaux, la répétition
générale explique ainsi 55 % des écarts de score entre poèmes, et un poids
de 1.0 ne veut pas dire la même chose d'un critère à l'autre.

Une **calibration** retient, par critère, la moyenne et l'écart-type de la
densité sur un corpus ; chaque densité est alors centrée-réduite
(`z = (densité − moyenne) / écart-type`) avant pondération. Chaque critère
explique alors un tiers des écarts, les poids ont le même sens pour tous, et
le score se lit **en écarts-types** : 0 = poème moyen du corpus, +1 = un
écart-type plus dense. Sans calibration, rien ne change.

```sh
claudel --calibrate cal.json samples/*.txt   # enregistre les statistiques
claudel --calibration cal.json poeme.txt     # score calibré
```

```
== dioptre4.txt (17 vers, 332 phones)
score de densité phonétique (calibré, en écarts-types) : +0.391
  repetition_generale      poids  1.0  brut    75.223  densité 0.22658  z +0.18
  repetition_positionnelle poids  1.0  brut     8.317  densité 0.02505  z +0.15
  patterns_rythmiques      poids  1.0  brut    28.000  densité 0.08434  z +0.84
```

```ruby
calibration = Claudel::Calibration.fit(corpus.map { |lines| Claudel.score(lines) })
calibration.save('cal.json') # ... Claudel::Calibration.load('cal.json')
Claudel.score(lines, config: { calibration: calibration }).score # => +0.391
```

#### Calibrations d'exemple livrées

Le gem embarque trois calibrations dans `data/`, sur trois corpus de nature
différente — leur origine et la façon dont elles ont été faites sont
décrites dans [`data/README.md`](data/README.md) :

| Fichier | Corpus |
|---|---|
| `calibration.json` | 104 poèmes contemporains, vers libre en majorité |
| `calibration_chatiments.json` | Hugo, *Les Châtiments*, 106 poèmes |
| `calibration_racine.json` | Racine, 12 pièces en blocs de 20 vers |

Les z se lisent par rapport à la norme du corpus choisi : face au corpus
contemporain, un recueil rimé et mesuré ressort nettement positif sans que
ce soit une anomalie (*Les Châtiments* entiers : +0.69) ; pour comparer des
poèmes classiques entre eux, prenez une calibration classique.

```sh
claudel --calibration reference poeme.txt   # = data/calibration.json (fichier local de ce nom : ./reference)
```
```ruby
Claudel.score(lines, config: { calibration: Claudel::Calibration.reference })
```

Les densités dépendent des réglages des critères (`proximity_lambda`…) : la
calibration enregistre ceux utilisés, et le CLI avertit si on l'applique avec
d'autres réglages (les poids, eux, peuvent changer librement). Une
calibration ne vaut que pour un corpus comparable à celui qui l'a produite.

## Outil de rapport (CLI)

Chaque fichier passé en argument est un poème (un vers par ligne, lignes
vides ignorées) ; le rapport affiche le score global et le détail par critère :

```sh
claudel --version | --help
claudel [--mode auto|classique|contemporain] [--repetitions] [--mean]
        [--weights k=w,k=w] [--set clé=valeur]...
        [--calibration cal.json|reference | --calibrate cal.json] <fichier...>
```

`--weights repetition_generale=2.0,patterns_rythmiques=0.5` règle les poids des
critères ; `--set unit_weights.consonne=0.3` (notation pointée) règle n'importe
quel paramètre imbriqué — voir le tableau des réglages ci-dessous. `--mean`
affiche la moyenne des scores sur tous les fichiers donnés (comparaison de
corpus) :

Un fichier illisible ou introuvable est signalé sur stderr sans interrompre
les fichiers suivants ; le code de sortie est alors 1.

`--repetitions` ajoute le détail de chaque répétition identifiée (unité,
positions `v<vers>@<phone>`, mot, distance, proximité, pénalité de mot,
contribution) — utile pour affiner les heuristiques :

Exemple (`claudel --mode contemporain poeme.txt`) :

```
== poeme.txt (4 vers, 100 phones)
score de densité phonétique : 0.03873
  repetition_generale      poids  1.0  brut     1.118  densité 0.01118
  repetition_positionnelle poids  1.0  brut     1.500  densité 0.01500
  patterns_rythmiques      poids  1.0  brut     9.000  densité 0.09000
```

```
$ claudel --mean samples/*.txt
...
== moyenne : 104 fichiers, score 0.10396 (médiane 0.10288, min 0.04425, max 0.17413)
```

```
== dioptre4.txt (17 vers, 332 phones)
score de densité phonétique : 0.11199
  ...
-- répétitions générales : 63 unités, brut 75.223 (top 40) --
  [voyelle ɛ] valeur 0.8, 23 occ., total 10.245
    v0@5 "étrangères" -> v1@25 "alouettes" : d=20 prox=0.551 mot×1.0 contrib=0.441
    ...
-- répétitions positionnelles : 9 formes, brut 8.317 --
  [rime sɛl] valeur 3, 2 occ., total 1.500
    v4 cesure -> v6 groupe : poids min 0.5, Δv=2 prox=1.000, contrib=1.500
  ...
  [rime ʒɛʁ] valeur 3, 3 occ., total 1.470
    v0 groupe -> v5 fin_de_vers : poids min 0.5, Δv=5 prox=0.717, contrib=1.075
    v5 fin_de_vers -> v16 groupe : poids min 0.5, Δv=11 prox=0.264, contrib=0.395
  [rime lɛst] valeur 4, 2 occ., total 1.213
    v1 groupe -> v8 fin_de_vers : poids min 0.5, Δv=7 prox=0.607, contrib=1.213
    ...
-- signatures rythmiques : [3, 3, 2] [4, 1, 3] ...
```

## Les critères (état actuel)

| Critère | Id | Idée | Poids par défaut |
|---|---|---|---|
| Répétition générale | `:repetition_generale` | syllabes / syllabes inversées (≥ 2 phones) répétés ; au niveau phone, **assonance (voyelle, poids 0.8) distinguée de l'allitération (consonne, poids 0.5)** ; k occurrences = k−1 répétitions, pondérées par la distance absolue en phones `proximité(d) = (d/(d+2))·e^(−d/40)` ; pénalité ×0.1 si même mot ou dérivé ; **mots fonctionnels** : syllabes ignorées, phones comptés seulement en paire intra-vers | 1.0 |
| Répétition positionnelle | `:repetition_positionnelle` | rimes (≥ 2 phones ou 1 syllabe) en fin de vers (poids 1.0), césure (0.7 — vers pair : milieu), fins de groupe ˈ/ˌ (0.5) ; rime portée par un mot fonctionnel ignorée ; poids plein jusqu'à 3 vers d'écart (plates, croisées, embrassées, sonnet, ballade), décroissance au-delà, plus lente pour une rime épaisse | 1.0 |
| Patterns rythmiques | `:patterns_rythmiques` | score de régularité `Rythme.score` par vers + récurrence de la signature dominante entre vers | 1.0 |

Chaque critère produit un score **brut**, normalisé en **densité**
(brut / nombre total de phones du poème), puis combiné :
`score = Σ poids·densité / Σ poids`.

## Architecture

```
lib/claudel.rb                              point d'entrée (require "claudel")
lib/claudel/phonemes.rb                     Claudel::Phonemes  — syllabes IPA -> phones
lib/claudel/unites.rb                       Claudel::Units     — unités de répétition (Unit)
lib/claudel/criteria.rb                     Claudel::Criteria  — registre des critères
lib/claudel/criteria/repetition_generale.rb     critère 1
lib/claudel/criteria/repetition_positionnelle.rb critère 2
lib/claudel/criteria/patterns_rythmiques.rb     critère 3
lib/claudel/calibration.rb                  Claudel::Calibration — densités centrées-réduites
lib/claudel/score.rb                        Claudel.score -> ScoreResult
lib/claudel/cli.rb                          Claudel.main (via bin/claudel)
data/*.json                                 calibrations d'exemple (provenance : data/README.md)
script/split_corpus.rb                      découpe un corpus en unités pour --calibrate
```

Un poème est un `Array<Scansion::Accents::Analysis>` (voir
`Claudel.analyze`). Les unités de répétition portent leur position **absolue
en phones** dans le poème et le mot d'origine. Un phone vaut 1 phone même sur
plusieurs codepoints (voyelles nasales, affriquées : marques combinantes
rattachées au caractère de base).

## Feuille de route

Voir `docs/notes_claudel.txt` : définitions des unités de répétition, fonction
de proximité, pondérations des positions et des poids — **à affiner** sur de
vrais poèmes. La rime « classique » (fin de vers seulement) et d'autres
critères pourront s'ajouter via le registre `Claudel::Criteria`.

## Licence

MIT — voir [LICENSE](LICENSE).
