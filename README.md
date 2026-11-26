# claudel

**claudel** est la couche d'évaluation *subjective* au-dessus du gem
[**scansion**](https://rubygems.org/gems/scansion).

scansion produit les **caractéristiques mesurables** du vers : syllabes IPA et
compte, groupes rythmiques, accents de phrase (ˈ) et de mot (ˌ), césure,
signature rythmique (`Scansion::Rythme` : tailles des groupes, score de
régularité) — et applique le **tirage accentuel 2.6** en vers contemporain.

claudel ajoute le **jugement** : à partir de ces caractéristiques, il calcule
un **score global de « densité phonétique » par poème**, combinaison pondérée
de plusieurs critères (répétitions phonétiques générales, répétitions
positionnelles, patterns rythmiques). La pondération exacte est un **travail
en cours** — voir `docs/notes_claudel.txt` pour la feuille de route et les
décisions prises.

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
réglages (voir `DEFAULTS` dans `lib/claudel/criteria/*.rb`) :

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

## Outil de rapport (CLI)

Chaque fichier passé en argument est un poème (un vers par ligne, lignes
vides ignorées) ; le rapport affiche le score global et le détail par critère :

```sh
claudel --version
claudel [--mode auto|classique|contemporain] [--repetitions] <fichier...>
```

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
== dioptre4.txt (17 vers, 332 phones)
score de densité phonétique : 0.05014
-- répétitions générales : 63 unités, brut 5.936 (top 40) --
  [inversee iv] valeur 2.0, 3 occ., total 1.311
    v15@296 "suivie" -> v15@303 "virevoltantes" : d=7 prox=0.653 mot×1.0 contrib=1.306
    ...
-- répétitions positionnelles : 10 formes, brut 16.000 --
  [rime ʒɛʁ] valeur 3, 3 occ., total 3.000
    v0 groupe -> v5 fin_de_vers : poids min 0.5, contrib=1.500
    ...
-- signatures rythmiques : [3, 3, 2] [4, 1, 3] ...
```

## Les critères (état actuel)

| Critère | Id | Idée | Poids par défaut |
|---|---|---|---|
| Répétition générale | `:repetition_generale` | syllabes / syllabes inversées (≥ 2 phones) répétés — **poids des phones à 0 pour l'instant** ; k occurrences = k−1 répétitions, pondérées par la distance absolue en phones `proximité(d) = (d/(d+2))·e^(−d/40)` ; pénalité ×0.1 si même mot ou dérivé ; **mots fonctionnels** : syllabes ignorées, phones comptés seulement en paire intra-vers | 1.0 |
| Répétition positionnelle | `:repetition_positionnelle` | rimes (≥ 2 phones ou 1 syllabe) en fin de vers (poids 1.0), césure (0.7 — vers pair : milieu), fins de groupe ˈ/ˌ (0.5) ; rime portée par un mot fonctionnel ignorée | 1.0 |
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
lib/claudel/score.rb                        Claudel.score -> ScoreResult
lib/claudel/cli.rb                          Claudel.main (via bin/claudel)
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

## Développement

```sh
bundle exec rspec     # tests
bundle exec rake      # idem (tâche par défaut)
rubocop               # style
```

Documentation et commentaires en français.

## Licence

MIT — voir [LICENSE](LICENSE).
