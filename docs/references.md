# Références — pondération des critères (recherche web, 2026-11-26)

Sources réunies pour fonder les poids actuels des critères de claudel
(voir `docs/notes_claudel.txt` §2/§6). La littérature donne un **ordre de
saillance**, pas des poids exacts — la calibration chiffrée se fait sur nos
corpus (chatiments, racine, oupoco, samples).

## Aesthetics empirique : rime et mètre sont les plus saillants

- Obermeier, Menninghaus et al. 2013, « Aesthetic and Emotional Effects of Meter
  and Rhyme in Poetry », Frontiers in Psychology 4:10.
  https://www.frontiersin.org/journals/psychology/articles/10.3389/fpsyg.2013.00010/full
  → mètre régulier et rime augmentent l'appréciation esthétique/émotionnelle
  (fluidité cognitive) ; strophes originales (mètre+rime intacts) > versions
  sans patterns.
- Menninghaus et al. 2017, « What the eyes reveal about (reading) poetry »
  (eye-tracking). https://pure.mpg.de/rest/items/item_3320097_3/component/file_3320098/content
  → rime et mètre facilitent le traitement prosodique (prédictibilité) ;
  effets sur les temps de lecture et l'évaluation esthétique.
- Bower & Bolton 1969 (mémorisation) : la rime est mnémonique, encodée presque
  automatiquement. Études d'eye-tracking (McConkie & Zola 1980 ; Rayner et al.
  2006, résumées dans une thèse USC) : effet de la rime **plus précoce** que
  celui de l'allitération (chevauchement initial), qui est plus coûteux et
  plus tardif → allitération = canal moins automatique.

## Poésie contemporaine / vers libre

- Thèse Sarrafian (Unistra 2016) : le vers libre symboliste repose sur des
  « groupements de mots phonétiques apparentés grâce à des assonances » —
  l'assonance est le dispositif fondateur du vers libre.
- Revue systématique « Practice of Free Verse in Poetry » (2025) : la perception
  du lecteur est affectée par les patterns rythmiques même sans mètre.
- « The Possibilities of Rhyme in Free Verse » (Univ. Hildesheim) : en vers
  libre, la rime passe par les rimes internes et les échos, pas la fin de vers.

## Mesure quantitative du rythme

- Haider, « Measuring Rhythm Regularity in Verse: Entropy of Inter-Stress
  Intervals », CEUR-WS Vol-3290. https://ceur-ws.org/Vol-3290/short_paper5417.pdf
  → entropie des intervalles inter-accents (piste pour raffiner
  `patterns_rythmiques`).

## « Densité phonétique » : pas de métrique standardisée

Aucune définition/unité standard trouvée (recherches FR « densité phonétique »).
Voisins : phonostylistique (thèse ElSayed, LLL CNRS), détection de schémas
rimiques par corpus (TALN 2015, https://aclanthology.org/2015.jeptalnrecital-court.18.pdf),
Cahiers du CEM n°6 (quantités discrètes en métrique).

## Implications retenues pour les poids

- Classique : rime (positionnelle) et mètre (patterns) très saillants.
- Contemporain : répétitions internes (assonance surtout) portent le sens ;
  la rime de fin de vers y est rare.
- Niveau phone : assonance (voyelle, 0.8) > allitération (consonne, 0.5) —
  l'allitération consonantique est le canal le moins automatique.

## Distance entre rimes (critère 2, proximité en vers)

- Benoît de Cornulier, *Art poëtique. Notions et problèmes de métrique*,
  Presses universitaires de Lyon, 1995, p. 267 — « règle des deux couleurs » :
  « Une terminaison de vers n'est jamais séparée de son plus proche écho par
  plus d'un type de terminaison » → en versification classique, deux vers
  rimant sont au plus à 3 vers d'écart (abba). Cité par :
- Gérald Purnelle, « Cocteau expérimentateur de la rime », Université de Liège.
  https://orbi.uliege.be/bitstream/2268/223778/1/Purnelle%20-%20Cocteau%20exp%c3%a9rimentateur%20de%20la%20rime.pdf
  → définit la « rime distante » (écart > 2 vers, règle des deux couleurs non
  respectée) ; pour l'accepter, « volume et distance doivent se cumuler
  positivement, ou au moins se compenser » : « plus la distance sera grande,
  plus le segment devra être épais » ; deux mots en -a ou -é « ne peuvent
  raisonnablement rimer que s'ils sont très proches » ; distance maximale
  tolérée par l'auteur dans un long poème : 34 vers.
  → fonde `rhyme_plateau: 3` (poids plein) et la décroissance au-delà, dont
  l'échelle croît avec l'épaisseur de la rime (`rhyme_lambda`).
