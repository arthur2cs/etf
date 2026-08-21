# ETF Reminder — Spécifications fonctionnelles

Application Android (Flutter) personnelle dont le but est de m'aider à investir
chaque mois sur mon PEA, sur plusieurs ETF, en respectant une répartition
cible réglable, tout en tenant compte des contraintes d'achat de BoursoBank
(montant minimum par ordre, achat en actions entières).

> Statut : implémentation faite et **testée en direct sur émulateur Android**
> avec tes 2 ETF réels (ajout ETF, calcul du plan mensuel avec prix Yahoo
> Finance en direct, confirmation de transaction, camembert, écran Stats).
> `flutter analyze` et `flutter test` passent, `flutter build apk --debug`
> compile. Google Sheets n'a pas pu être testé (nécessite le setup Google
> Cloud ci-dessous, à faire par toi). Reste aussi à me donner le détail de
> tes 2 transactions déjà faites pour que je seed le Sheet au premier
> lancement.

## 1. Objectif

Tous les mois, l'appli me dit **exactement combien virer sur mon PEA** et
**sur quel(s) ETF investir combien**, pour :

- me rapprocher de ma répartition cible entre mes ETF (ex. 1/3 Europe,
  1/3 US, 1/3 Asie — pourcentages réglables dans l'appli) ;
- tout en investissant un montant total mensuel à peu près fixe (ex. ~200 €) ;
- en respectant les contraintes réelles de BoursoBank : montant minimum par
  ordre et achat en nombre entier d'actions (donc le montant réel viré peut
  légèrement dépasser la cible, ex. 203,10 € au lieu de 200 €).

Je me sers de l'appli pour connaître le montant exact à virer *avant* de
faire le virement vers mon PEA, puis je confirme dans l'appli une fois
l'ordre passé chez BoursoBank.

## 2. Concepts clés

- **ETF suivi** : nom, ticker/identifiant pour aller chercher le prix,
  catégorie (EU / US / Asie / ... — libre), pourcentage cible de répartition.
- **Répartition cible** : somme des pourcentages cibles de tous les ETF
  suivis = 100 %. Réglable dans l'appli.
- **Capital investi** : somme des montants historiquement investis sur
  chaque ETF (= la source de vérité vient des transactions enregistrées,
  pas d'une valorisation de marché — cf. §3.4).
- **Transaction** : un versement réel effectué sur un ETF donné, à une
  date donnée, pour un montant donné (et le prix unitaire au moment de
  l'achat, pour dérider le nombre d'actions achetées).

## 3. Fonctionnalités

### 3.1 Configuration des ETF (écran de réglages)

- CRUD sur la liste des ETF suivis : ISIN (→ ticker Yahoo dérivé
  automatiquement), catégorie, % cible.
- % cible réglable librement par ETF à tout moment. Quand un nouvel ETF est
  ajouté, son % cible par défaut est **0 %** (pas de redistribution
  automatique des autres % — c'est à moi de tout réajuster manuellement).
- Validation que la somme des % cible = 100 % avant de pouvoir lancer un
  calcul mensuel (avertissement si ce n'est pas le cas, sans bloquer la
  consultation de l'écran).
- Réglage du montant mensuel cible d'investissement (ex. 200 €).
- Réglage du montant minimum par ordre BoursoBank (ex. 200 €), un seul
  réglage global pour tous les ETF.
- Réglage de la date/fréquence du rappel mensuel.

### 3.2 Calcul du montant à investir (le cœur de l'appli)

Chaque mois, l'appli doit déterminer, à partir :
- du capital déjà investi sur chaque ETF (recalculé depuis l'historique
  des transactions),
- de la répartition cible,
- du montant mensuel visé,
- du prix actuel de chaque ETF,
- du montant minimum par ordre BoursoBank,
- du taux de commission BoursoBank (réglable, §7),

...quel(s) ETF acheter ce mois-ci et pour quel montant exact (multiple entier
du prix de l'action, ≥ minimum BoursoBank, commission de courtage incluse
dans le montant à virer).

**Révisé une 2e fois** (deux bugs trouvés en usage réel avec une cible très
déséquilibrée — 80/20 — et un gros budget mensuel — 900€) : l'algorithme
"un seul ETF, tout le budget dessus" surallouait sur un seul ETF ; sa
correction "greedy, un ordre à la fois recalculé" sous-estimait le montant
par ordre et fragmentait en plusieurs achats minimums sur le même ETF. La
version actuelle calcule directement la meilleure répartition d'ensemble :

1. Calcule la répartition **continue** (pas encore en actions) qui, en
   dépensant tout le budget du mois, retomberait exactement sur la cible —
   en tenant compte du capital déjà investi :
   `x_i = %cible_i × (total_actuel + budget) − investi_i`
   (résolu à partir de `investi_i + x_i = %cible_i × (total_actuel + x_i +
   les autres)`, généralisation à N ETF de l'ancienne formule à un seul ETF
   — investir fait grossir le total du portefeuille, donc la cible bouge
   avec).
2. Les ETF déjà à/au-dessus de leur cible reçoivent 0 (jamais utile d'en
   acheter plus) — écartés d'office.
3. Arrondir `x_i` en actions entières peut tomber sous le minimum d'ordre
   pour certains ETF. Il n'y a **pas de règle fixe correcte** ("toujours
   arrondir au minimum" ou "toujours laisser de côté" donnent chacune de
   meilleurs résultats selon les cas, vérifié à la main sur des exemples
   concrets) — donc l'appli essaie **toutes les combinaisons** d'ETF à
   financer ce mois-ci (peu nombreuses vu le peu d'ETF suivis), calcule le
   résultat réel de chacune après arrondi, et choisit celle qui minimise
   l'écart total à la cible : somme des écarts en points de % sur tous les
   ETF (y compris ceux laissés de côté ce mois-ci). Une combinaison n'est
   même considérée que si son budget total (au moins le minimum d'ordre par
   ETF inclus) tient dans le budget du mois.
4. Dans une combinaison à plusieurs ETF, gonfler l'un d'eux au minimum
   d'ordre ne doit pas laisser les autres inchangés à leur propre montant
   idéal — sinon le total dépasse largement le budget (bug observé en usage
   réel : cible 80/20, budget 400€ pile — soit exactement 2× le minimum
   d'ordre, sans marge — a recommandé 472€, 18% au-dessus du budget). Les
   ETF non gonflés de la combinaison sont donc recalculés sur ce qu'il
   reste **après** les montants gonflés, en cascade si besoin (si ce
   recalcul fait à son tour tomber un ETF sous le minimum, il est gonflé
   à son tour, etc.) — jusqu'à stabilisation, ou jusqu'à ce que la
   combinaison se révèle intenable dans le budget (elle est alors écartée
   comme les autres combinaisons infaisables, cf. point 3).
5. Conséquence assumée : même si le portefeuille est déjà exactement à la
   cible, le budget du mois est quand même investi (réparti pour minimiser
   l'écart après coup) — l'appli existe pour investir régulièrement, pas
   pour sauter des mois.

Commission estimée par ordre = `brut × taux commission`, arrondi au centime.

Avec un budget proche du minimum d'ordre (ne permettant qu'un seul achat),
ou pile à la limite pour un achat à deux ETF (sans marge pour l'arrondi),
le comportement retombe sur un seul ETF ciblé — celui le plus sous-pondéré.
Avec un budget qui laisse un peu de marge au-delà de ce seuil, ça peut se
répartir sur 2+ ETF dans le même mois pour se rapprocher plus précisément
de la cible, plutôt que de compter uniquement sur la rotation entre
plusieurs mois.

### 3.3 Récupération des prix des ETF

- Source retenue : **Yahoo Finance** (API non-officielle, gratuite, sans
  clé). L'ISIN saisi par l'utilisateur ne suffit pas à deviner le ticker
  Yahoo (`{ISIN}.PA` ne fonctionne pas de façon fiable — testé en pratique :
  pour FR0011550193 ça renvoie un symbole obsolète à prix figé à 0, pour
  FR0013412020 ça renvoie une 404). L'appli résout donc l'ISIN en ticker via
  l'endpoint de recherche Yahoo (`/v1/finance/search?q={ISIN}`), qui renvoie
  le bon ticker coté (ex. `ETZ.PA` pour FR0011550193, `PAEEM.PA` pour
  FR0013412020), en préférant une cotation Euronext Paris si disponible.
  Toujours pas de saisie manuelle de ticker à faire — juste l'ISIN.
- À chaque calcul mensuel (et idéalement en cache, rafraîchi à la demande),
  l'appli va chercher le prix actuel de chaque ETF suivi.
- En cas d'échec réseau ou de changement d'API côté Yahoo (API non
  officielle, peut casser sans préavis), utiliser le dernier prix connu en
  cache avec un avertissement visuel ("prix du JJ/MM/AAAA").

### 3.4 Écran principal

- Diagramme camembert de la répartition actuelle du capital investi par ETF
  (couleur par ETF/catégorie).
- Comparaison visuelle avec la répartition cible (ex. anneau extérieur =
  cible, camembert intérieur = actuel — ou simple texte "cible 33% / actuel
  41%").
- Rappel du calcul du mois en cours : montant **total** à virer d'abord
  (somme de tous les ordres du mois), puis le détail par ETF — "Vire 464 €"
  suivi de "Achète 12 actions de [ETF EU] pour 253 €", "Achète 6 actions de
  [ETF Emergents] pour 214 €", etc.
- **Un seul bouton** "J'ai fait la transaction(s)" même quand plusieurs
  ordres sont proposés le même mois (l'utilisateur les passe tous à la
  suite chez BoursoBank) → ouvre un formulaire pré-rempli avec une section
  par ETF (montant, actions, prix, commission, tous modifiables) et une
  date commune → enregistre chaque ligne dans Google Sheets et arrête les
  rappels du mois.

### 3.5 Stockage des données (Google Sheets)

- Les transactions sont la source de vérité, stockées dans un Google Sheet
  (pas de base locale persistante autre qu'un cache) :
  colonnes → `date | isin | montant_eur | prix_unitaire | nb_actions | commission_eur`.
  `montant_eur` est le montant **brut** (actions × prix, cohérent avec le
  reste de l'appli qui raisonne en valeur d'actions) ; la commission
  BoursoBank est stockée à part dans `commission_eur` — le montant net
  réellement débité = `montant_eur + commission_eur`.
- Au démarrage, l'appli lit tout l'historique du Sheet pour reconstruire
  l'état (capital par ETF, dernière transaction, etc.).
- Quand je confirme une transaction dans l'appli, une ligne est ajoutée au
  Sheet.
- Objectif : réinstallation sur un nouveau téléphone = tout se resynchronise
  depuis le Sheet, aucune perte de données.
- Authentification : Google Sign-In / OAuth avec le compte Google personnel
  (cf. §4).

### 3.6 Notifications de rappel mensuel

- Le jour J configuré du mois (ex. le 1er), une notification part :
  "Il est temps d'investir — X € sur [ETF]".
- Si je n'ai pas confirmé la transaction dans l'appli, la notification
  revient **tous les jours** jusqu'à confirmation (même appli fermée →
  planification native via `flutter_local_notifications`, pas un simple
  timer en mémoire).
- Dès que je confirme via l'écran principal, les rappels du mois s'arrêtent
  et se reprogrammeront pour le mois suivant.

### 3.7 Écran Stats / Projections

- Historique des versements (courbe dans le temps, par ETF et total).
- Projection de la valeur du portefeuille à horizon N années, à partir d'une
  hypothèse de rendement annuel (réglable, ex. 7%) et de la poursuite des
  versements mensuels.
- Comparaison avec l'inflation (montant investi en euros constants vs
  courants) — taux annuel saisi/réglable par l'utilisateur, un taux par
  année depuis l'année du premier investissement jusqu'à l'année en cours.
  Pour l'année en cours (non terminée), le taux renseigné est appliqué au
  prorata des jours écoulés depuis le 1er janvier. Pas d'appel à une API
  d'inflation officielle en v1.
- Éventuellement : performance réelle si on ajoute la valorisation de marché
  (nécessite de garder les prix historiques, pas juste au moment de l'achat).

## 4. Architecture technique (proposition)

- **Flutter**, Android uniquement (les dossiers `ios/` et `macos/` ont été
  retirés du repo — l'appli ne cible que Android pour l'instant ; ils
  peuvent être régénérés avec `flutter create .` si besoin plus tard).
- `flutter_local_notifications` + `timezone` : déjà en place pour les
  rappels natifs.
- `shared_preferences` : cache local (réglages, dernier prix connu, dernier
  état calculé) — pas de base de données locale complexe, Google Sheets fait
  office de backend.
- `google_sign_in` + `googleapis` (Sheets API v4) : lecture/écriture du
  Google Sheet avec le compte Google personnel, via OAuth (connexion Google
  au premier lancement, pas de compte de service embarqué).
- Un client HTTP vers Yahoo Finance pour les cours (§3.3).
- `fl_chart` (ou équivalent) pour le camembert et les graphiques de stats.
- Pas de backend serveur : tout tourne en local sur le téléphone, avec Google
  Sheets comme unique stockage distant.

## 4bis. Design système

Basé sur l'icône de l'appli (`assets/icon/renard.jpeg`, un renard groovy
orange/noir sur fond blanc) — palette et typographie dans
`lib/theme/app_theme.dart`.

- **Couleurs** : orange `#FC842D` (échantillonné sur le pelage du renard) en
  couleur primaire, noir doux `#1C1B17` (encre/texte, boutons secondaires),
  fond blanc cassé `#FFF8F0`, cartes blanches avec une ombre douce orangée.
  Sur un bouton orange, le texte est en noir (pas blanc) — le blanc sur cet
  orange ne passe pas le contraste (2,5:1 contre 7:1 avec l'encre).
- **Palette des graphiques** : 5 couleurs catégorielles dérivées du orange/
  noir (orange, terracotta, ambre, acajou, corail) — validées avec la
  méthode du skill dataviz (bande de luminosité, seuil de chroma,
  séparation daltonisme ΔE 22+ sur paires adjacentes). Le contraste marque/
  fond est en WARN pour 3 des 5 couleurs, ce qui est légal seulement si un
  texte de secours accompagne toujours la couleur — d'où la légende de
  l'écran principal qui affiche toujours le nom + montant en texte, jamais
  juste une pastille de couleur.
- **Typographie** : Google Fonts "Fredoka" partout (rounded, doux,
  généreux — l'esprit "groovy" demandé), chargée à l'exécution (nécessite
  une connexion réseau au premier lancement, puis mise en cache).
- **Boutons** : grands rayons arrondis (24px), padding généreux, police en
  gras — `FilledButton` orange/encre pour l'action principale, `OutlinedButton`
  encre pour le secondaire.
- **Icône de l'appli** : générée depuis `assets/icon/renard_icon.png` (le
  renard recentré avec une marge de sécurité pour les icônes adaptatives
  Android) via `flutter_launcher_icons` — pour régénérer après un changement
  d'image : `dart run flutter_launcher_icons`.

## 5. Modèle de données

### Google Sheet — onglet `transactions`

| date       | isin         | montant_eur | prix_unitaire | nb_actions | commission_eur |
|------------|--------------|-------------|----------------|------------|-----------------|
| 2026-08-01 | FR0011550193 | 203.10      | 67.70          | 3          | 1.02            |

`montant_eur` = brut (actions × prix). Montant réellement viré = `montant_eur
+ commission_eur`. Taux de commission réglable dans les paramètres (§7),
déduit des transactions réelles de l'utilisateur : **0,5 %** du montant brut,
arrondi au centime (vérifié sur 2 transactions réelles : 0,55€ sur 110,78€ et
1,05€ sur 210,80€, les deux tombent exactement sur ce taux).

### Google Sheet — onglet `config`

| isin         | nom                                                  | categorie  | pct_cible |
|--------------|-------------------------------------------------------|------------|-----------|
| FR0011550193 | BNP Paribas Easy STOXX Europe 600 UCITS ETF           | Europe     | 50        |
| FR0013412020 | Amundi PEA Emergent (MSCI Emerging) ESG Transition ETF | Émergents  | 50        |

Répartition cible de départ 50/50 entre les 2 ETF actuels, réglable à tout
moment dans l'appli. Écran "Ajouter un ETF" = saisie de l'ISIN (le nom vient
de la source de prix, le ticker Yahoo est dérivé automatiquement, §3.3) ;
% cible initialisé à 0 %, à ajuster manuellement ensuite.

### Google Sheet — onglet `inflation`

| annee | taux_pct |
|-------|----------|
| 2024  | 4.9      |
| 2025  | 1.5      |
| 2026  | 6.0      |

Une ligne par année depuis le premier investissement jusqu'à l'année en
cours, saisie/modifiable dans l'appli. Pour l'année en cours, le calcul
"euros constants" applique le taux renseigné au prorata du nombre de jours
écoulés depuis le 1er janvier (cf. §3.7).

## 6. Hors périmètre (v1)

- Multi-devise (tout est en EUR).
- Multi-comptes / multi-utilisateurs.
- Frais de courtage modélisés uniquement comme un taux fixe en % (pas de
  palier, pas de minimum de commission — voir §7 si BoursoBank applique un
  barème plus complexe que 0,5% linéaire).
- Vente d'ETF / rééquilibrage par arbitrage (uniquement rééquilibrage par
  les flux entrants).

## 7. Décisions prises

- **Répartition du budget mensuel** : recherche de la meilleure combinaison
  d'ETF à financer ce mois-ci (parmi toutes les combinaisons possibles),
  potentiellement plusieurs en même temps si le budget le permet (§3.2 —
  révisé après 2 cas réels : cible 80/20 avec gros budget qui surallouait
  tout sur un seul ETF, puis qui fragmentait en plusieurs achats minimums
  sur le même ETF au lieu d'un seul).
- **Authentification Google Sheets** : Google Sign-In / OAuth avec le compte
  Google personnel.
- **Camembert de l'écran principal** : capital investi (coût d'achat), pas
  la valeur de marché actuelle. La valorisation de marché est réservée à
  l'écran Stats (v2 potentielle).
- **Minimum BoursoBank** : un seul réglage global (pas par ETF).
- **Google Sheet** : n'existe pas encore, l'appli le crée de zéro au premier
  lancement (onglets `transactions` et `config`, cf. §5).
- **Config des ETF (nom/ticker/%cible)** : sauvegardée dans l'onglet
  `config` du Google Sheet (pas seulement en local), pour survivre à une
  réinstallation comme les transactions.
- **Relance des rappels** : intervalle fixe, tous les jours, jusqu'à
  confirmation.

- **Liste des ETF (v1)** : FR0011550193 (BNP Paribas Easy Stoxx Europe 600)
  et FR0013412020 (Amundi PEA Emergent ESG Transition), répartition cible
  50/50 provisoire, prix via Yahoo Finance (`{ISIN}.PA`), cf. §3.3 et §5.
  D'autres ETF pourront être ajoutés plus tard juste en saisissant leur
  ISIN.
- **Seed initial du Sheet** : les 2 investissements faits avant la création
  de l'appli (24/10/2025 et 13/07/2026, tous deux sur FR0011550193) ont été
  ajoutés à la main dans l'onglet `transactions` du Sheet.
- **Inflation** : taux annuel réglable, un par année (cf. §3.7 et onglet
  `inflation` en §5), pas d'appel à une source officielle en v1.
- **Commission BoursoBank** : taux fixe réglable en % (0,5% par défaut,
  déduit des 2 transactions réelles ci-dessus — détail en §5), appliqué sur
  le montant brut pour calculer le montant exact à virer.

## 8. Prérequis côté Google Cloud (à faire par toi avant l'auth Google Sheets)

L'authentification OAuth (Google Sign-In) nécessite un projet Google Cloud
avec l'API Google Sheets activée et un identifiant client OAuth Android. Ce
sont des étapes que tu devras faire toi-même dans la console Google Cloud
(je peux te guider pas à pas le moment venu) :

1. Créer un projet Google Cloud (ou réutiliser un projet perso existant).
2. Activer l'API "Google Sheets API" (et "Google Drive API", utilisée
   uniquement pour retrouver le Sheet existant après réinstallation).
3. Configurer l'écran de consentement OAuth (en mode "Test" avec ton propre
   compte Google comme utilisateur autorisé — pas besoin de validation
   Google pour un usage strictement personnel).
4. Créer un identifiant OAuth "Android" avec :
   - nom de package : `com.arthur2cs.etf_reminder`
   - empreinte SHA-1 (build debug, générée localement) :
     `DE:C9:F0:2A:00:2A:F9:06:1B:C4:40:A7:97:8A:F0:D7:FC:BC:9A:15`
   - il faudra refaire cette étape avec l'empreinte SHA-1 de la clé de
     signature *release* le jour où tu distribues un build signé (pas
     nécessaire tant que tu restes en debug/sideload).
