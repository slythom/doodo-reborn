# Specs artistiques — Doodo

Document de référence pour les choix graphiques et le pipeline d'assets. Complète `specs_fonctionnelles.md` (règles/UX) et la future spec technique.

*État : validé par prototype (scène Godot jouable, personnages Blender→glb).*

---

## 1. Direction artistique

- **Référence cible : Wii Party / Wii Sports** — vue première personne attablée, personnages ronds type Mii, salon chaleureux la nuit, table en feutrine, gobelets en cuir. Capture de référence : `inspiration/Partie de Perudo autour de la table.png`.
- **Ton** : cartoon, chaleureux, familier. Pas de réalisme : géométrie low-poly lissée, couleurs quasi unies, visages simples et expressifs.
- **Rendu** : 3D temps réel, mobile-first, **portrait verrouillé** (v1). HUD 2D superposé (boutons d'action, chat) — cf. spec fonctionnelle §7.
- Le « polish Wii » vient de trois piliers : **éclairage doux** (ambiance chaude, peu de sources), **animations snappy** (squash-and-stretch, réactions expressives), **cohérence des formes/couleurs** partout.

## 2. Personnages

- Personnages **paramétriques** façon Mii, générés en script Blender (`assets/make_mii.py`) et exportés en `.glb` :
  - **Variantes** activables côté moteur par nommage de nœuds :
    - `Hair0`–`Hair5` : calotte, chauve, frange, pics, carré, chignon
    - `Face0`–`Face3` : neutre/sourire, joyeux (yeux ∩), colère, surpris (bouche O)
    - `Glasses*` : lunettes optionnelles par personnage
  - **Recoloration** par nom de matériau : `Skin`, `Shirt`, `Hair` (peau, t-shirt, cheveux varient par joueur) ; `Dark`, `Mouth`, `Pants`, `SkinDark` fixes.
  - **Rig minimal** : 3 os `Root` → `Body` → `Head`, liaisons rigides par partie (chaque mesh 100 % à un os).
  - **Animations embarquées** dans le `.glb` : `flinch` (sursaut : tête écrasée + recul + rebond). Prévu : rire, hochement de tête « à ton tour », réaction à l'élimination, victoire.
- Les joueurs sont identifiés par leur **pseudo** affiché (pas d'avatars en v1 — spec fonctionnelle).
- Les expressions peuvent changer en cours de partie (ex. face « surpris » à l'impact d'une tomate) par swap de visibilité des nœuds `Face*`.

## 3. Environnement

*Le décor n'est **pas unique** : plusieurs scènes 3D, choisies par le créateur de la table en salle d'attente (spec fonctionnelle §1.3/§4.1), figées au lancement — jamais modifiables en cours de partie. `salon` est la scène **par défaut** et le **fallback** (id inconnu → salon). Les scènes peuvent être radicalement différentes ; seul le contrat ci-dessous est garanti.*

### Contrat commun (toute scène le respecte)

- **Table ronde centrée** : un gobelet posé par joueur sur le tapis.
- **Sièges en arc** face caméra pour les adversaires ; le joueur local en **vue subjective** au bord proche — ni Mii ni mains rendus (retirés pour lisibilité), son gobelet reste posé sur la table.
- **Caméra fixe portrait**, légèrement plongée sur la table — pas de contrôle caméra en v1.
- **Lumière principale au-dessus de la table** (seule source d'ombres portées) ; appoints libres.
- **Budget perf §6 inchangé** quelle que soit la scène ; le HUD 2D et les overlays ne dépendent pas du décor.
- Hors ce contrat : **liberté totale** (murs, ciel, props, ambiance, variantes de Mii…).

### Catalogue de scènes

- **`salon` — salon intérieur la nuit (défaut + fallback)** : murs beige chaud, sol bois, grande fenêtre à ciel nocturne derrière les adversaires (détail : gratte-ciels lumineux envisageables), plantes, cadres, appliques murales. Table : feutrine verte + rebord bois, **piètement en fonte sombre métallique** (distinct du bois des gobelets). Éclairage chaud au-dessus de la table, appoints d'ambiance, lumière froide discrète côté fenêtre.
- **`cimetiere` — cimetière gothique la nuit, personnages squelettes** : toile de fond illustrée (`assets/graveyard_bg.png` — grille, crypte, arbres morts) rendue non éclairée, sol herbeux sombre, pierres tombales et troncs en volume pour la parallaxe, brume légère. Lune froide directionnelle + appoint chaud au-dessus de la table. Personnages : squelettes KayKit (CC0) — 4 variantes (Minion, Mage, Rogue, Warrior) choisies par hash du pseudo, normalisées à ~1,4 unité de haut ; animations du rig partagé (`Idle_A/B`, `Hit_A/B`, `Death_A/B`, `Spawn`, `Throw`…). Le Mage est légèrement incliné « tête levée » pour dégager le visage sous le chapeau. Le splat de tomate est parenté au bone `head` (suit le recul de `Hit_A`).
- **`foret` — clairière enchantée, personnages aventuriers** : toile de fond illustrée (`assets/forest_bg.png` — grands arbres, sentier, champignons) non éclairée, sous-bois moussu, rochers et amanites en volume pour la parallaxe, brume verte légère. Soleil filtré canopée + appoint chaud au-dessus de la table. Personnages KayKit Adventurers 2.0 (CC0) — 6 variantes (Barbarian, Knight, Mage, Ranger, Rogue, Rogue Hooded) par hash du pseudo, rig `Rig_Medium` partagé avec les squelettes (mêmes animations).
- *Scènes futures : à définir — chacune documentée ici en respectant le contrat ci-dessus.*

## 4. Animations & interactions

- **Moments clés animés** : lancer de dés (physique réelle sous le gobelet), gobelet soulevé/posé, révélation, perte de dé, élimination, victoire — cf. SFX associés (spec fonctionnelle §4.3).
- **Interactions sociales animées** (idée validée par proto) : tap sur un personnage → projectile (tomate) en arc → particules + splat sur le visage + sursaut + visage « surpris » temporaire. Peut devenir le support des emotes prédéfinies §4.3.
- **Technique d'anim** : animations squelettiques bakées dans le `.glb` pour le corps ; tweens Godot pour les éléments simples (gobelet, HUD, micro-balancement caméra).

## 5. Pipeline d'assets

- **Tout est généré en code** — zéro asset payant, zéro licence à gérer.
- Pipeline : `assets/make_mii.py` (versionné) → exécuté via Blender MCP dans le Blender local → `assets/mii.glb` → import Godot.
- Conventions à respecter dans les générateurs : **purge des datablocks orphelins** en début de script (matériaux, meshes, courbes, armatures, actions — sinon suffixes `.001`), nommage des nœuds par préfixe (`Hair*`, `Face*`, `Glasses*`), matériaux nommés pour la recoloration, `transform_apply` avant le binding.
- Extensions prévues : générateurs pour les gobelets, la table/salon, accessoires ; possibilité de compléter par des packs **CC0** (Kenney, Quaternius, KayKit) ou retouches Blender scriptées.

## 6. Budget performance (cible : 60 fps smartphone milieu de gamme)

- **Renderer Godot** : Mobile (ou Compatibility) — pas Forward+ en production.
- Polycount très bas (~50 k tris la scène entière), draw calls contenus, textures plates, **une seule lumière à ombres**.
- Post-processing : aucun requis (pas de glow/SSAO — le style est plat).
- Physique : ~6 rigid bodies (dés), négligeable. Particules par dizaines.
- `.glb` personnage ≈ 0,8 Mo (variantes incluses) ; partagé entre toutes les instances.

## 7. Charte UI / HUD (2D)

*But : une UI « Wii Sports » — claire, joyeuse, tactile — qui prolonge naturellement le cartoon/Mii de la scène 3D. Référence : menus Wii (fonds ivoire, boutons « soft plastic », couleurs joueur). **Portrait uniquement** — pas de layout paysage.*

### Palette (fond clair ivoire)

| Rôle | Couleur | Usage |
|---|---|---|
| Fond | `#EEF2F7` (ivoire bleuté) | écrans, scrim laiteux |
| Panneau | `#FFFFFF` | cartes, barre d'actions, pills |
| Bordure | `#DDE3EB` | liserés de panneaux, champs |
| Biseau bouton | `#D3D9E1` | bord inférieur 3 px (effet « soft plastic ») |
| Texte | `#3C4048` | jamais de noir pur |
| Texte secondaire | `#8A919E` | labels discrets, code de salle |
| Accent bleu Wii | `#2FA8D8` (sombre `#1E86B0`, clair `#55C8EC`) | action principale, focus, titre, remplissage Continuer |
| Badge tour | `#FF9D3C` (bord `#DE8A2E`) | « À TOI DE JOUER ! », Palifico |
| Dudo | `#F25C54` (bord `#D94A42`) | action Dudo, titre DUDO! |
| Calza | `#67BB45` (bord `#55A738`) | action Calza, dés concordants, titre CALZA! |
| Ambre doux | `#FFC94D` | accents chauds secondaires |
| Couleurs joueur | bleu `#2E8BE6` · rouge `#E64A3C` · vert `#3FAF49` · jaune `#F5C518` · violet `#8E5BB5` · orange `#F28C28` | chips pseudo + badge compteur de dés (par siège) |
| Pips des dés | `#232B40` | faces de dés (ivoire `#FFFFFF`) |

### Mode sombre

*Switch « Mode sombre » en bas de la carte d'accueil — pill + knob animé avec icône soleil/lune. Préférence persistée (`user://settings.cfg`), appliquée à tous les écrans 2D. Les accents (bleu Wii, Dudo, Calza, orange, couleurs joueur, pips) sont **identiques** dans les deux thèmes ; l'écran de révélation reste « night club » dans les deux cas ; la scène 3D ne suit pas le thème.*

| Rôle | Clair | Sombre |
|---|---|---|
| Fond | `#EEF2F7` | `#131A29` |
| Panneau | `#FFFFFF` | `#202B3E` |
| Bordure | `#DDE3EB` | `#34425C` |
| Biseau bouton | `#D3D9E1` | `#151D2E` |
| Texte | `#3C4048` | `#E9EEF8` |
| Texte secondaire | `#8A919E` | `#8C97AB` |
| Trame de pois | encre 7 % | blanc 5 % |

### Typographie

- **Fredoka** (SIL OFL, variable wght) — display : titres, badges, chiffres d'enchère, « DUDO ! ». Ronde et grasse, c'est l'ADN Wii.
- **Nunito** (SIL OFL, variable wght) — corps, boutons, chips. Ronde, très lisible.
- Échelle (portrait 720×1280) : titre écran 60-64 · titre overlay 54 · enchère 34 · boutons 26 · corps 20-22 · secondaire 15-18.
- Les **dés s'affichent en icônes de faces** (pips), pas en chiffre. Une enchère se lit « 5 × ⚄ », pas « 5 x 4 ».

### Widgets

- **Boutons « soft plastic »** : fond uni, radius 18, **biseau inférieur 3 px** de la teinte sombre de la variante ; pressé = biseau réduit à 1 px + teinte assombrie ; désactivé = opacité 45 %.
- Variantes : `primary` (bleu Wii plein, texte blanc), `btn` (blanc cassé, texte encre — secondaire/neutre), `dudo` (rouge), `calza` (vert).
- **Cibles tactiles ≥ 48 px** partout (≈56 px boutons, 48 px icônes de faces — même hauteur que le stepper de quantité).
- **Panneaux** : blancs, radius 20, bordure `#DDE3EB` + biseau léger.
- **Chips joueur** : pill couleur du siège, pseudo blanc — un joueur = une couleur partout (scène, chip, badge).
- **Champs de saisie** : fond blanc, bord 2 px clair ; focus → bord bleu Wii.
- **Badge compteur de dés** : badge circulaire à la couleur du joueur **au-dessus de sa pill pseudo**, le tout en billboard 2D au-dessus du Mii — lisible de loin, plus de texte « N dé(s) ».
- **Joueur actif** : sa pill pseudo reçoit un **anneau blanc + halo** et pulse doucement (scale 1 → 1.09 en boucle).

### HUD (portrait, zones)

- **Haut, centré** : code de salle discret → **badge « À TOI DE JOUER ! » orange** qui pulse (sinon « Tour de X » en pill blanche) → **enchère en cours** dans une pill blanche : quantité Fredoka + icône de face + chip de l'enchérisseur ; pill ambre PALIFICO quand actif.
- **Bas** : panneau blanc arrondi sur 4 lignes — toasts éphémères · **ma main en icônes de dés 2D** (plus de dés 3D sur la table) · **sélecteur de face = 6 icônes cliquables** (la choisie cerclée bleu, les autres à 45 %) · quantité + `Enchérir` (bleu) · `Dudo` (rouge) / `Calza` (vert) / `Quitter` (blanc).
- **Toasts** : pills blanches éphémères en tête du panneau (chat, éliminations).
- Le joueur éliminé **quitte la table** (son Mii disparaît) plutôt qu'un simple atténuement.

### Écran de révélation (Dudo/Calza) — le moment clé

- **Scrim blanc laiteux** (~74 %) — la scène respire dessous ; panneau blanc centré.
- Titre `DUDO !` (rouge) ou `CALZA !` (vert) Fredoka 54 — **pop avec rebond** (scale 0 → 1, TRANS_BACK).
- L'enchère contestée : « Enchère : N × icône » centrée sous le titre.
- **Dés alignés par joueur** : une ligne par joueur (chip couleur siège + icônes 34 px).
- **Comptage animé** : les dés concordants (face + pacos jokers) s'illuminent un à un — anneau vert + remontée d'opacité — toutes les 0,4 s, compteur `= N` en vert qui grimpe en parallèle.
- **Verdict** : « X perd un dé » (depuis l'événement die_lost).
- **Dismiss** : bouton « Continuer » **qui se remplit de bleu de gauche à droite sur 10 s** — timer déguisé ; tap = passer, expiration = fermeture auto.

---
## 8. Points ouverts / à trancher plus tard

- ~~**Révélation Dudo/Calza : 3D ou écran 2D ?**~~ — **tranché : écran 2D dédié** (implémenté, §7). Reste à décider si le lancer de dés de manche se fait en 3D sur la table ou en animation 2D.
- **Toon shading** (ramp + rim light) : optionnel, à évaluer visuellement — non nécessaire pour l'instant.
- Expressions par **textures swapables** plutôt que meshes 3D : si le nombre de visages/expressions explose (émotions fines), une texture de visage sur la tête devient plus souple que des groupes de meshes.
- Fenêtre : ajouter silhouettes de gratte-ciels éclairés pour vendre l'ambiance nocturne (léger, gros impact).
