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

## 7. Points ouverts / à trancher plus tard

- **Révélation Dudo/Calza : 3D ou écran 2D ?** — remarque : faire la révélation dans un **écran 2D dédié** pourrait être plus lisible (tous les dés alignés, comptage affiché) et plus simple que d'animer la révélation de tous les gobelets en 3D — qui souffre déjà de défauts visuels (dés qui dépassent du gobelet). À trancher lors de la spec technique. Le rendu 3D des dés au centre de la table resterait nécessaire de toute façon pour le lancer.
- **Toon shading** (ramp + rim light) : optionnel, à évaluer visuellement — non nécessaire pour l'instant.
- Expressions par **textures swapables** plutôt que meshes 3D : si le nombre de visages/expressions explose (émotions fines), une texture de visage sur la tête devient plus souple que des groupes de meshes.
- Fenêtre : ajouter silhouettes de gratte-ciels éclairés pour vendre l'ambiance nocturne (léger, gros impact).
