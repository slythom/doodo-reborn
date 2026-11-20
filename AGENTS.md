# Doodo — notes agent

## Workflow release (convention utilisateur)

- Commits **locaux uniquement** — ne jamais pousser/tagger sans
  autorisation explicite de l'utilisateur.
- Un commit par issue, référence `(#n)` dans le message.
- **Maintenir `CHANGELOG.md`** à chaque version : une entrée par tag
  (format Keep a Changelog, français), mise à jour avant de tagger.
- Bump de version : `config/version="x.y.z-N"` dans `client/project.godot`
  et `version/code=N` dans `client/export_presets.cfg`. La version
  affichée in-app vient de `project.godot`.
- Schéma de version : `x.y.z` = **prochain tag en préparation**,
  `-N` = compteur de build global. Ex. builds `0.10.4-17` → tag
  `v0.10.4` → builds suivants `0.10.5-18`…

## Build APK

```sh
cd client
godot --headless --export-release "Android" build/doodo.apk
```

- Keystore release = keystore debug (même cert → mises à jour OK),
  configuré dans `export_presets.cfg`.
- L'erreur `cannot connect to daemon at tcp:5037` (adb) est bénigne ;
  vérifier plutôt `unzip -l build/doodo.apk | grep META-INF` (3 fichiers
  = signé) et `unzip -p … assets/project.binary | strings` (version +
  `run/main_scene="res://menu.tscn"`).

## Pièges Godot connus

- **`project.godot` = ConfigFile** : les commentaires sont `;`, pas `#`.
- Après tout harnais de capture (`_shot.tscn` etc.) : **toujours
  vérifier `run/main_scene="res://menu.tscn"`** — une scène de test
  oubliée a déjà crashé un APK au lancement.
- `emulate_mouse_from_touch` : chaque tap Android produit un
  `InputEventMouseButton` émulé (`device = -1`). Tout handler tap doit
  passer par `UI.tap(ev)` qui filtre ces doublons.
- `SubViewport`/`Sprite3D` : les badges sièges sont des sprites 3D ;
  leur zone cliquable passe par un `StaticBody3D` + meta `badge`
  (raycast dans `_unhandled_input`).

## Protocole serveur

- Messages plats `{"type": "…", champs…}` (pas d'enveloppe `data`
  à l'envoi ; les réponses ont `{type, data}`).
- `set_options` remplace TOUT l'objet options — envoyer
  `view.options` complet patché, jamais un patch partiel
  (`Validate` rejette `MaxPlayers=0` etc.).
- Mode dieu (§4.5) : créateur + salle privée uniquement ;
  `view.god` = « tu es le créateur en mode dieu », dés adverses
  dans `players[].dice`.
