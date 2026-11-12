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

- **Salon intérieur la nuit** : murs beige chaud, sol bois, grande fenêtre à ciel nocturne derrière les adversaires (détail : gratte-ciels lumineux envisageables), plantes, cadres, appliques murales.
- **Table** : feutrine verte + rebord bois ; un gobelet en cuir par joueur ; les dés du joueur visibles sous son propre gobelet.
- **Éclairage** : une lumière principale chaude au-dessus de la table (seule source d'ombres), appoints d'ambiance, lumière froide discrète côté fenêtre.

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

*But : une UI « casino moderne » — sombre, propre, premium — qui contraste avec le cartoon de la scène 3D sans la trahir. Référence : apps de poker mobiles (HUD sombre bleu nuit, sans-serif géométrique, accents dorés).*

### Palette (fond sombre bleu nuit)

| Rôle | Couleur | Usage |
|---|---|---|
| Fond | `#0E1A2B` (bleu nuit profond) | fond d'écran, scrim atténué |
| Surface | `#182A45` | panneaux, cartes, barre d'actions |
| Bordure | `#2A3E5F` | liserés de panneaux, séparateurs |
| Texte | `#F4EDDC` (crème) | jamais de blanc pur — trop froid |
| Texte secondaire | `#9AA7BD` (bleu-gris) | labels discrets, code de salle |
| Accent vert | `#35A466` (feutrine éclairci pour le sombre) | actions principales, Calza, focus |
| Accent sombre | `#1F5C33` | liseré des boutons verts |
| Vert clair | `#5FD696` | texte/anneaux sur fond sombre |
| Danger / Dudo | `#E2472F` (tomate vif) | action Dudo, élimination, erreurs |
| Ambre | `#F2B33D` | badge « À toi », timer, Palifico, jetons |
| Chips joueur | fond `#1D3B6E` + texte doré `#E8C96A` | pastille pseudo + compte de dés |
| Neutre | `#42536F` | boutons secondaires, états inactifs |

### Typographie

- **Inter** (SIL OFL, accents FR complets) — propre, géométrique, lisible en petit. Poids : SemiBold 600 titres/boutons, Medium 500 corps, Regular 400 secondaire. Alternative si changement : Manrope ou Outfit (même famille d'esprit).
- Échelle (portrait 720×1280) : titre écran 52 · panneau 32 · boutons 28 · labels/corps 22 · secondaire 17.
- Les **dés s'affichent en icônes de faces** (pips), pas en chiffre. Une enchère se lit « 5 × ⚄ », pas « 5 x 4 ».

### Widgets

- **Boutons** : plats, radius 12, fond surface ou accent + bordure 1 px de la variante claire ; pressé = légère assombrissement ; désactivé = opacité 40 %. Pas de « bouton physique » — le style reste plat et moderne.
- **Cibles tactiles ≥ 48 px** partout (doigts, pas souris).
- **Panneaux** : radius 14, fond `#182A45`, bordure `#2A3E5F` 1 px, ombre portée discrète.
- **Chips joueur** : pill bleu `#1D3B6E`, pseudo Inter Medium + compte de dés en doré `#E8C96A`.
- **Champs de saisie** : fond `#0E1A2B`, bord `#2A3E5F`, focus → bord accent vert.

### HUD (portrait, zones)

- **Haut** : code de salle discret (texte secondaire) + badge « À toi ! » ambre qui pulse ; timer de tour en anneau ambre autour du badge quand actif.
- **Bas** : barre d'actions sur 2 lignes (déjà en place) — sélecteurs quantité/valeur + `Enchérir` (accent vert), `Dudo` (rouge) / `Calza` (vert) / `Quitter` (neutre).
- **Toasts** : notices (chat, éliminations, « X regagne un dé ») en pills bleu nuit à bordure fine, éphémères haut-centre.

### Écran de révélation (Dudo/Calza) — le moment clé

- **Scrim** `#0E1A2B` à 80 % + panneau surface centré ; titre `DUDO !` (rouge) ou `CALZA !` (vert) en Inter Bold ~64 **avec léger effet néon/pulse** (halo teinté dont l'alpha oscille, scale 1.0→1.03 — pas de squash cartoon, on reste premium).
- L'enchère contestée affichée grande : quantité + icône de face + chip pseudo de l'enchérisseur.
- **Dés alignés par joueur** : une ligne par joueur (chip bleu + pseudo doré), la sienne en premier ; dés en icônes de faces.
- **Comptage animé** : les dés concordants (valeur + pacos jokers) s'illuminent un à un (anneau vert clair + léger zoom), le compteur monte en parallèle.
- **Verdict** : « Il y en a **6** — l'enchère tient ! » puis « sly1 perd un dé ».
- **Dismiss** : bouton « Continuer » **qui se remplit d'ambre de gauche à droite sur 10 s** — visuellement un timer déguisé ; tap = passer immédiatement, expiration = fermeture auto puis manche suivante.
- Version « toutes les mains » identique pour les spectateurs.

---

## 8. Points ouverts / à trancher plus tard

- **Révélation Dudo/Calza : 3D ou écran 2D ?** — remarque : faire la révélation dans un **écran 2D dédié** pourrait être plus lisible (tous les dés alignés, comptage affiché) et plus simple que d'animer la révélation de tous les gobelets en 3D — qui souffre déjà de défauts visuels (dés qui dépassent du gobelet). À trancher lors de la spec technique. Le rendu 3D des dés au centre de la table resterait nécessaire de toute façon pour le lancer.
- **Toon shading** (ramp + rim light) : optionnel, à évaluer visuellement — non nécessaire pour l'instant.
- Expressions par **textures swapables** plutôt que meshes 3D : si le nombre de visages/expressions explose (émotions fines), une texture de visage sur la tête devient plus souple que des groupes de meshes.
- Fenêtre : ajouter silhouettes de gratte-ciels éclairés pour vendre l'ambiance nocturne (léger, gros impact).
