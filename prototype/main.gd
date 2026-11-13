# main.gd — scène de jeu 3D, pilotée par les snapshots serveur (Net.view).
# Le client ne simule rien : il affiche l'état et envoie des actions.
extends Node3D

const TABLE_TOP_Y := 0.78
const TABLE_RADIUS := 1.15
const SEAT_RADIUS := 1.6
const CUP_RADIUS := 0.98
const MY_SEAT_ANGLE := 90.0  # mon siège : face caméra
const ARC_LEFT := 215.0      # arc des adversaires : extrémité gauche
const ARC_RIGHT := 325.0     #                  extrémité droite
const ARC_CENTER := 270.0

var view := {}
var seats := {}          # seat_idx -> {mii, cup, badge, badge_sp}
var splat_tex: ImageTexture
var cam: Camera3D
var sway_t := 0.0
var splat_by_mii := {}   # mii -> splat node

# HUD (charte Wii — ui.gd)
var title_lbl: Label
var turn_lbl: Label          # pill orange « À TOI DE JOUER ! »
var bid_pill: PanelContainer # pill blanche de l'enchère en cours
var bid_row: HBoxContainer   # enchère en cours : quantité × icône + chip enchérisseur
var palifico_lbl: Label
var status_lbl: Label        # pill de toast (chat, élimination…)
var my_dice_box: HBoxContainer # ma main : icônes de dés 2D
var qty_val := 1               # quantité choisie (stepper −/+)
var qty_lbl: Label
var face_icons: Array = []   # sélecteur de face : DieIcons cliquables
var val_face := 1
var bid_btn: Button
var dudo_btn: Button
var calza_btn: Button
var action_bar: PanelContainer
var status_gen := 0
var _turn_tween: Tween
# Révélation (même layout que la maquette : contenu direct sur scrim, sans panneau)
var reveal_panel: Control
var reveal_title: Label
var reveal_sub: Label          # « X conteste l'enchère de Y »
var reveal_bid_line: HBoxContainer
var reveal_dice_box: VBoxContainer
var reveal_count: Label
var reveal_verdict: Label
var reveal_verdict_sub: Label  # « X perd un dé »
var reveal_fill: PanelContainer # remplissage du bouton « Continuer »
var reveal_glow: TextureRect   # halo coloré sous le titre (rouge/vert)
var reveal_tween: Tween
var _wobble_tween: Tween
var _glow_pulse: Tween
var reveal_gen := 0           # invalide les timers d'un reveal précédent
var over_root: Control        # overlay de fin de partie « night club »
var over_box: VBoxContainer
var rematch_btn: Button
var _last_bid_sig := ""       # signature de l'enchère (punch à chaque changement)
var _last_dice: Array = []    # ma main au dernier rafraîchissement
var _turn_was_mine := false   # détecte le début de mon tour (pop du badge)
var _turn_hl_seat := -1       # siège mis en valeur (tour en cours)

static func mat(color: Color, roughness := 0.8, emission := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	if emission:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = 1.5
	return m

func _mesh(mesh: PrimitiveMesh, color: Color, pos: Vector3, roughness := 0.8, emission := false) -> MeshInstance3D:
	mesh.material = mat(color, roughness, emission)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	return mi

func _ready() -> void:
	UI.load_theme()
	randomize()
	splat_tex = _make_splat_texture()
	view = Net.view
	_build_scene()
	_hud()
	_build_seats()
	_refresh()
	Net.room_state.connect(_on_view)
	Net.game_events.connect(_on_events)
	Net.net_error.connect(func(_c: String, m: String) -> void: _set_status(m))
	Net.notice_msg.connect(_on_notice)
	Net.connection_closed.connect(func() -> void: _set_status("connexion perdue — reconnexion…"))
	Net.connection_opened.connect(func() -> void: Net.hello()) # re-join après reconnexion

func _on_view(v: Dictionary) -> void:
	view = v
	var st: String = v.get("state", "")
	if st == "lobby" or st == "cancelled": # revanche ou annulation → retour menu
		get_tree().call_deferred("change_scene_to_file", "res://menu.tscn")
		return
	_refresh()

# ---- Construction des sièges depuis le snapshot ----

# Angle sur l'arc adverse : idx 0 → gauche (215°), total-1 → droite (325°).
func _arc_angle(idx: int, total: int) -> float:
	if total <= 1:
		return ARC_CENTER
	return ARC_LEFT + idx * (ARC_RIGHT - ARC_LEFT) / float(total - 1)

func _build_seats() -> void:
	var n: int = UI.arr(view.get("players")).size()
	var my_seat: int = view.get("your_seat", -1)
	var is_spectator := my_seat < 0
	# Factory de personnage de la scène (défaut : Miis aux palettes salon).
	var char_fn: Callable = _scene.get("char", _char_mii)

	# En spectateur, tous les joueurs sont sur l'arc (triés par siège).
	var plist: Array = UI.arr(view.get("players")).duplicate()
	if is_spectator:
		plist.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("seat", 0)) < int(b.get("seat", 0)))

	for i in n:
		var p: Dictionary = plist[i]
		var p_seat: int = p.get("seat", i)
		var offset := -1 if is_spectator else (p_seat - my_seat + n) % n
		var arc_idx: int
		var arc_total := n - 1
		if is_spectator:
			arc_idx = i
			arc_total = n
		elif offset == 0:
			arc_idx = -1 # moi : pas d'arc
		else:
			arc_idx = offset - 1
		var a := deg_to_rad(MY_SEAT_ANGLE if offset == 0 else _arc_angle(arc_idx, arc_total))
		var pos := Vector3(cos(a) * SEAT_RADIUS, 0, sin(a) * SEAT_RADIUS)
		var seat := {}
		seats[p_seat] = seat

		# Gobelet de chaque joueur sur la table.
		var cup := _cup_mesh()
		cup.position = Vector3(cos(a) * CUP_RADIUS, TABLE_TOP_Y + 0.085, sin(a) * CUP_RADIUS)
		add_child(cup)
		seat["cup"] = cup

		if offset == 0:
			# Moi : dés visibles en 2D (vue subjective, pas de Mii).
			continue

		# Adversaire : personnage de la scène (variantes dérivées du nom).
		var h: int = abs(p.get("name", "?").hash())
		var mii: Node3D = char_fn.call(h)
		mii.position = pos
		mii.rotation.y = atan2(-pos.x, -pos.z)
		mii.set_meta("seat", p_seat)
		add_child(mii)
		seat["mii"] = mii

		# Pseudo + compteur : chip colorée + badge circulaire (comme la maquette),
		# rendus dans un SubViewport affiché en billboard au-dessus du Mii.
		var bdg := _seat_badge(p.get("name", "?"), p_seat)
		bdg.sprite.position = pos + Vector3(0, 1.86, 0)
		seat["badge"] = bdg.badge
		seat["badge_sp"] = bdg.sprite
		seat["chip"] = bdg.chip

# Chip pseudo + badge compteur affichés en 2D au-dessus du Mii :
# un SubViewport rend un HBox [chip][badge] texturé sur un Sprite3D billboard.
func _seat_badge(p_name: String, p_seat: int) -> Dictionary:
	var vp := SubViewport.new()
	vp.transparent_bg = true
	vp.size = Vector2i(320, 124)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# Badge compteur AU-DESSUS de la pill pseudo, centré.
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 6)
	var badge := UI.CircleBadge.new("5", UI.PLAYER[p_seat % UI.PLAYER.size()], 48)
	badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(badge)
	var chip := UI.player_chip(p_name, p_seat, 26)
	chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(chip)
	vp.add_child(v)
	add_child(vp)

	var sp := Sprite3D.new()
	sp.texture = vp.get_texture()
	sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sp.pixel_size = 0.004
	sp.shaded = false
	add_child(sp)
	return {"sprite": sp, "badge": badge, "chip": chip}

# ---- Rafraîchissement depuis le snapshot ----

func _refresh() -> void:
	_update_players()
	_update_my_dice()
	_update_turn()
	_update_bid()
	_update_actions()

func _update_players() -> void:
	var players := UI.arr(view.get("players"))
	for i in players.size():
		var p: Dictionary = players[i]
		var p_seat: int = p.get("seat", i)
		if not seats.has(p_seat):
			continue
		var seat: Dictionary = seats[p_seat]
		var eliminated: bool = int(p.get("dice_count", 0)) == 0
		if seat.has("badge"):
			seat["badge"].set_text(str(int(p.get("dice_count", 0))))
		if seat.has("badge_sp"):
			seat["badge_sp"].visible = not eliminated
		if seat.has("mii"):
			seat["mii"].visible = not eliminated # éliminé : le Mii quitte la table

# Ma main : rangée d'icônes 2D dans le HUD (plus de dés 3D sur la table).
# Les dés pop en cascade quand la main change (lancer, perte, gain).
func _update_my_dice() -> void:
	var me := _player_by_seat(view.get("your_seat", -1))
	var vals: Array = UI.arr(me.get("dice"))
	var changed: bool = vals != _last_dice
	_last_dice = vals
	for c in my_dice_box.get_children():
		c.queue_free()
	for i in vals.size():
		var di := UI.DieIcon.new(int(vals[i]), 46)
		di.pivot_offset = Vector2(23, 23)
		my_dice_box.add_child(di)
		if changed:
			di.scale = Vector2.ZERO
			var t := di.create_tween()
			t.tween_property(di, "scale", Vector2.ONE, 0.3).set_delay(i * 0.05) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _player_by_seat(seat: int) -> Dictionary:
	for p in UI.arr(view.get("players")):
		if int(p.get("seat", -1)) == seat:
			return p
	return {}

func _update_turn() -> void:
	var turn: int = view.get("turn", -1)
	var mine: int = view.get("your_seat", -1)
	var mine_turn: bool = turn == mine and not view.get("over", false)
	if _turn_tween:
		_turn_tween.kill()
		_turn_tween = null
	turn_lbl.modulate.a = 1.0
	if mine_turn:
		turn_lbl.text = "À TOI DE JOUER !"
		turn_lbl.add_theme_color_override("font_color", Color.WHITE)
		turn_lbl.add_theme_stylebox_override("normal", UI.sb(UI.ORANGE, UI.ORANGE_DK, 20, 0, 3))
		turn_lbl.visible = true
		if not _turn_was_mine:
			UI.punch(turn_lbl, 0.3)
		_turn_tween = turn_lbl.create_tween().set_loops()
		_turn_tween.tween_property(turn_lbl, "modulate:a", 0.55, 0.45)
		_turn_tween.tween_property(turn_lbl, "modulate:a", 1.0, 0.45)
	elif turn >= 0:
		turn_lbl.text = "Tour de %s" % _player_name(turn)
		turn_lbl.add_theme_color_override("font_color", UI.DIM)
		var tsb := UI.sb(UI.PANEL, UI.EDGE, 20, 1)
		tsb.shadow_color = Color(0, 0, 0, 0.3)
		tsb.shadow_size = 6
		tsb.shadow_offset = Vector2(0, 3)
		turn_lbl.add_theme_stylebox_override("normal", tsb)
		turn_lbl.visible = true
	else:
		turn_lbl.visible = false
	_turn_was_mine = mine_turn
	# Pastille du joueur de tour : anneau blanc lumineux + pulse douce.
	if turn != _turn_hl_seat:
		_hl_seat(_turn_hl_seat, false)
		_turn_hl_seat = turn
		_hl_seat(turn, true)

# Active/désactive la mise en valeur du pseudo d'un siège (tour en cours).
func _hl_seat(s: int, on: bool) -> void:
	if s < 0 or not seats.has(s) or not seats[s].has("chip"):
		return
	var seat: Dictionary = seats[s]
	var chip: Label = seat["chip"]
	var sp: Sprite3D = seat["badge_sp"]
	if seat.has("hl_tween") and seat["hl_tween"]:
		seat["hl_tween"].kill()
		seat.erase("hl_tween")
		sp.scale = Vector3.ONE
	var col := UI.PLAYER[s % UI.PLAYER.size()]
	if on:
		var hsb := UI.sb(col, Color.WHITE, 20, 3)
		hsb.shadow_color = Color(1, 1, 1, 0.45)
		hsb.shadow_size = 10
		chip.add_theme_stylebox_override("normal", hsb)
		var tw := sp.create_tween().set_loops()
		tw.tween_property(sp, "scale", Vector3.ONE * 1.09, 0.55).set_trans(Tween.TRANS_SINE)
		tw.tween_property(sp, "scale", Vector3.ONE, 0.55).set_trans(Tween.TRANS_SINE)
		seat["hl_tween"] = tw
	else:
		chip.add_theme_stylebox_override("normal", UI.sb(col, col, 20, 0))

# Enchère en cours : « 5 × ⚄ par <chip> » dans la pill blanche du haut.
# La pill fait un punch à chaque nouvelle enchère (feedback du changement).
func _update_bid() -> void:
	var b := UI.obj(view.get("bid"))
	var sig := "%s.%d.%d.%d" % [view.get("has_bid", false), int(b.get("quantity", 0)),
		int(b.get("value", 0)), int(view.get("round", 1))]
	if sig != _last_bid_sig:
		_last_bid_sig = sig
		UI.punch(bid_pill, 0.1)
	for c in bid_row.get_children():
		c.queue_free()
	if view.get("has_bid", false):
		bid_row.add_child(UI.label(str(int(b.get("quantity", 0))), 34, UI.INK, 700, true))
		bid_row.add_child(UI.label("×", 24, UI.DIM, 800))
		bid_row.add_child(UI.DieIcon.new(int(b.get("value", 1)), 34))
		bid_row.add_child(UI.label("par", 20, UI.DIM, 600))
		bid_row.add_child(UI.player_chip(_player_name(view.get("bidder", -1)), int(view.get("bidder", -1))))
	else:
		bid_row.add_child(UI.label("Manche %d — pas encore d'enchère" % int(view.get("round", 1)), 20, UI.DIM, 600))
	palifico_lbl.visible = view.get("palifico", false)

# Reproduction client-side de la légalité (miroir de game.LegalBid) pour
# activer/désactiver le bouton — le serveur reste l'arbitre.
func _legal(q: int, v: int) -> bool:
	if q < 1 or v < 1 or v > 6:
		return false
	if not view.get("has_bid", false):
		return view.get("palifico", false) or v != 1  # ouverture : paco interdit
	var c := UI.obj(view.get("bid"))
	var cq: int = c.get("quantity", 0)
	var cv: int = c.get("value", 1)
	if view.get("palifico", false):
		return q > cq  # valeur figée côté serveur
	if cv == 1 and v != 1:
		return q >= 2 * cq + 1
	if cv != 1 and v == 1:
		return q >= int(ceil(cq / 2.0))
	return q > cq or (q == cq and v > cv)

# Bouton de stepper : texte bleu plat dans la pill bordée (style maquette).
func _step_btn(t: String) -> Button:
	var b := Button.new()
	b.text = t
	b.custom_minimum_size = Vector2(38, 42)
	b.add_theme_font_override("font", UI.font_w(800))
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_color_override("font_color", UI.BLUE)
	b.add_theme_color_override("font_hover_color", UI.BLUE_DK)
	var tr := UI.sb(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 10, 0)
	for st in ["normal", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, tr)
	b.add_theme_stylebox_override("hover", UI.sb(Color(UI.BLUE, 0.16), Color(0, 0, 0, 0), 10, 0))
	return b

func _set_qty(delta: int) -> void:
	qty_val = clampi(qty_val + delta, 1, 60)
	qty_lbl.text = str(qty_val)
	UI.punch(qty_lbl, 0.2)
	_update_actions()

# Sélecteur de face : la face choisie est cerclée bleu, les autres atténuées.
func _set_face(v: int) -> void:
	val_face = v
	for i in face_icons.size():
		var ic: UI.DieIcon = face_icons[i]
		ic.sel = i + 1 == v
		ic.modulate.a = 1.0 if ic.sel else 0.45
		ic.queue_redraw()
	_update_actions()

func _update_actions() -> void:
	var spectator: bool = view.get("your_seat", -1) < 0
	action_bar.visible = not spectator and not view.get("over", false)
	if spectator:
		return
	var my_turn: bool = view.get("turn", -1) == view.get("your_seat", -2) and not view.get("over", false)
	bid_btn.disabled = not my_turn or not _legal(qty_val, val_face)
	dudo_btn.disabled = not my_turn or not view.get("has_bid", false)
	var game_opts := UI.obj(UI.obj(view.get("options")).get("game"))
	calza_btn.disabled = not my_turn or not view.get("has_bid", false) or not game_opts.get("calza_enabled", true)

# ---- Événements serveur (révélation, pertes, fin) ----

func _on_events(events: Array) -> void:
	for e in events:
		match e.get("type", ""):
			"reveal":
				_show_reveal(e)
			"die_lost":
				# Verdict affiché dans l'overlay de révélation encore ouvert.
				if reveal_panel.visible:
					reveal_verdict_sub.text = "%s perd un dé" % _player_name(e.get("player", -1))
			"die_gained":
				if reveal_panel.visible:
					reveal_verdict_sub.text = "%s regagne un dé" % _player_name(e.get("player", -1))
			"eliminated":
				_set_status("%s est éliminé" % _player_name(e.get("player", -1)))
			"game_over":
				_show_game_over(e)

func _player_name(seat: int) -> String:
	return _player_by_seat(seat).get("name", "?")

# Toast éphémère (4 s) — génération pour invalider les timers précédents.
func _set_status(t: String) -> void:
	status_gen += 1
	var gen := status_gen
	status_lbl.text = t
	status_lbl.visible = not t.is_empty()
	if t.is_empty():
		return
	UI.pop_in(status_lbl)
	get_tree().create_timer(4.0).timeout.connect(func() -> void:
		if gen == status_gen:
			status_lbl.visible = false)

# ---- Révélation : scrim laiteux, titre pop, comptage animé (specs §7) ----

func _show_reveal(e: Dictionary) -> void:
	reveal_gen += 1
	var gen := reveal_gen
	var calza: bool = e.get("calza", false)
	reveal_title.text = "CALZA !" if calza else "DUDO !"
	var tcol := Color("#79DC72") if calza else Color("#FF6E66")
	reveal_title.add_theme_color_override("font_color", tcol)
	reveal_title.add_theme_color_override("font_outline_color", tcol.darkened(0.5))
	reveal_title.add_theme_constant_override("outline_size", 8)
	reveal_title.add_theme_color_override("font_shadow_color", Color(tcol, 0.45))
	reveal_glow.modulate = Color(tcol, 0.26)
	# Le halo respire en boucle.
	if _glow_pulse:
		_glow_pulse.kill()
	_glow_pulse = reveal_glow.create_tween().set_loops()
	_glow_pulse.tween_property(reveal_glow, "modulate:a", 0.36, 1.2)
	_glow_pulse.tween_property(reveal_glow, "modulate:a", 0.18, 1.2)

	var b := UI.obj(e.get("bid"))
	var face := int(b.get("value", 1))
	var qty := int(b.get("quantity", 0))
	var challenger := _player_name(e.get("player", -1))
	var bidder := _player_name(e.get("bidder", -1))
	reveal_sub.text = ("%s parie que l'enchère de %s est exacte" % [challenger, bidder]) if calza \
		else ("%s conteste l'enchère de %s" % [challenger, bidder])

	for c in reveal_bid_line.get_children():
		c.queue_free()
	reveal_bid_line.add_child(UI.label(str(qty), 28, Color.WHITE, 700, true))
	reveal_bid_line.add_child(UI.label("×", 17, Color("#9AA7C6"), 800))
	reveal_bid_line.add_child(UI.DieIcon.new(face, 36))

	# Dés par joueur : colonne nom alignée à droite + dés (les concordants
	# s'illumineront un à un).
	for c in reveal_dice_box.get_children():
		c.queue_free()
	var lit: Array = []
	var dice_rows := UI.arr(e.get("dice"))
	for i in dice_rows.size():
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 10)
		var nm := HBoxContainer.new()
		nm.custom_minimum_size.x = 100
		nm.alignment = BoxContainer.ALIGNMENT_END
		nm.add_child(UI.player_chip(_player_name(i), i, 18))
		row.add_child(nm)
		var rvdice := HBoxContainer.new()
		rvdice.add_theme_constant_override("separation", 10)
		row.add_child(rvdice)
		var icons: Array = []
		for dv in UI.arr(dice_rows[i]):
			var di := UI.DieIcon.new(int(dv), 36)
			di.pivot_offset = Vector2(18, 18)
			var matches := int(dv) == face or (face != 1 and int(dv) == 1)
			if matches:
				lit.append(di)
			else:
				di.modulate.a = 0.35
			di.scale = Vector2.ZERO
			rvdice.add_child(di)
			icons.append(di)
		reveal_dice_box.add_child(row)
		# Entrée en cascade : chaque dé pop avec rebond, décalé par position.
		for j in icons.size():
			var pop: Tween = icons[j].create_tween()
			pop.tween_property(icons[j], "scale", Vector2.ONE, 0.35) \
				.set_delay(0.1 + i * 0.07 + j * 0.05) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	var total := int(e.get("count", 0))
	reveal_count.text = "0"
	reveal_verdict.text = ""
	reveal_verdict_sub.text = ""
	reveal_fill.offset_right = 0.0
	reveal_panel.modulate.a = 0.0
	reveal_panel.visible = true
	var fade := create_tween()
	fade.tween_property(reveal_panel, "modulate:a", 1.0, 0.22)

	# Titre : pop avec rebond puis wobble infini (comme la maquette).
	reveal_title.scale = Vector2(0.4, 0.4)
	reveal_title.rotation = 0.0
	reveal_title.modulate.a = 0.0
	var pop := create_tween()
	pop.set_parallel()
	pop.tween_property(reveal_title, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_property(reveal_title, "modulate:a", 1.0, 0.25)
	get_tree().create_timer(0.6).timeout.connect(func() -> void:
		if gen != reveal_gen or _wobble_tween:
			return
		_wobble_tween = reveal_title.create_tween().set_loops()
		_wobble_tween.tween_property(reveal_title, "scale", Vector2(1.04, 1.04), 1.1).set_trans(Tween.TRANS_SINE)
		_wobble_tween.parallel().tween_property(reveal_title, "rotation_degrees", -1.0, 1.1).set_trans(Tween.TRANS_SINE)
		_wobble_tween.tween_property(reveal_title, "scale", Vector2.ONE, 1.1).set_trans(Tween.TRANS_SINE)
		_wobble_tween.parallel().tween_property(reveal_title, "rotation_degrees", 0.0, 1.1).set_trans(Tween.TRANS_SINE))

	# Comptage animé : un dé s'allume toutes les 0,4 s.
	for i in lit.size():
		var ic: UI.DieIcon = lit[i]
		var n := i + 1
		get_tree().create_timer(0.5 + i * 0.4).timeout.connect(func() -> void:
			if gen != reveal_gen or not is_instance_valid(ic):
				return
			ic.glow = true
			ic.modulate.a = 1.0
			ic.queue_redraw()
			# Le dé qui s'allume fait un punch (scale 1.45 → 1 avec rebond).
			ic.scale = Vector2(1.45, 1.45)
			var it := ic.create_tween()
			it.tween_property(ic, "scale", Vector2.ONE, 0.25) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			reveal_count.text = str(mini(n, total))
			# Petit punch sur le compteur à chaque dé concordant.
			reveal_count.scale = Vector2(1.3, 1.3)
			var pt := create_tween()
			pt.tween_property(reveal_count, "scale", Vector2.ONE, 0.18))
	get_tree().create_timer(0.5 + lit.size() * 0.4 + 0.3).timeout.connect(func() -> void:
		if gen != reveal_gen:
			return
		reveal_count.text = str(total)
		# Verdict d'après le résultat (le nom du perdant arrive via die_lost).
		if calza:
			reveal_verdict.text = "L'enchère était exacte !" if total == qty else "L'enchère n'était pas exacte !"
		else:
			reveal_verdict.text = "L'enchère tenait !" if total >= qty else "L'enchère ne tenait pas !"
		reveal_verdict.modulate.a = 0.0
		var vt := create_tween()
		vt.tween_property(reveal_verdict, "modulate:a", 1.0, 0.3))

	# « Continuer » : remplissage bleu de gauche à droite sur 10 s puis fermeture.
	if reveal_tween:
		reveal_tween.kill()
	reveal_tween = create_tween()
	# Largeur fixe de la capsule (340) — le layout n'est pas encore fait
	# à cet instant, on anime vers la valeur connue.
	reveal_tween.tween_property(reveal_fill, "offset_right", 340.0, 10.0)
	reveal_tween.tween_callback(_hide_reveal)

func _hide_reveal() -> void:
	reveal_gen += 1
	if reveal_tween:
		reveal_tween.kill()
		reveal_tween = null
	if _wobble_tween:
		_wobble_tween.kill()
		_wobble_tween = null
	if _glow_pulse:
		_glow_pulse.kill()
		_glow_pulse = null
	reveal_panel.visible = false

func _show_game_over(e: Dictionary) -> void:
	_hide_reveal()
	for c in over_box.get_children():
		c.queue_free()
	var ranking := UI.arr(e.get("ranking"))
	var i_won: bool = not ranking.is_empty() and int(ranking[0]) == int(view.get("your_seat", -2))
	var tcol := Color("#FFC94D") if i_won else Color("#E9EDF7") # or victoire / blanc-bleu
	var t := UI.label("VICTOIRE !" if i_won else "PARTIE TERMINÉE", 50, tcol, 700, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_color_override("font_outline_color", tcol.darkened(0.5))
	t.add_theme_constant_override("outline_size", 8)
	t.add_theme_color_override("font_shadow_color", Color(tcol, 0.4))
	t.add_theme_constant_override("shadow_offset_y", 5)
	over_box.add_child(t)
	UI.pop_in(t)
	for r in ranking.size():
		var seat: int = int(ranking[r])
		var cc := CenterContainer.new()
		var chip := UI.player_chip("%d. %s" % [r + 1, _player_name(seat)], seat, 22)
		cc.add_child(chip)
		over_box.add_child(cc)
		UI.pop_in(chip, 0.35 + r * 0.1)
	var btns := VBoxContainer.new()
	btns.custom_minimum_size.x = 380
	btns.add_theme_constant_override("separation", 12)
	over_box.add_child(btns)
	rematch_btn = UI.button("Revanche", "primary")
	rematch_btn.visible = view.get("your_seat", -1) >= 0 # joueurs seulement
	rematch_btn.pressed.connect(func() -> void: Net.rematch())
	btns.add_child(rematch_btn)
	var back_btn := UI.button("Retour au menu", "btn")
	back_btn.pressed.connect(func() -> void:
		Net.leave()
		get_tree().call_deferred("change_scene_to_file", "res://menu.tscn"))
	btns.add_child(back_btn)
	over_root.modulate.a = 0.0
	over_root.visible = true
	var fade := create_tween()
	fade.tween_property(over_root, "modulate:a", 1.0, 0.25)
	if rematch_btn.visible:
		rematch_btn.call_deferred("grab_focus")
	else:
		back_btn.call_deferred("grab_focus")

# ---- Emotes (tomate) : envoi optimiste + réception ----

func _unhandled_input(event: InputEvent) -> void:
	var pos := Vector2.ZERO
	var pressed := false
	if event is InputEventScreenTouch and event.pressed:
		pos = event.position
		pressed = true
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pos = event.position
		pressed = true
	if not pressed:
		return
	var from := cam.project_ray_origin(pos)
	var to := from + cam.project_ray_normal(pos) * 10.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or not hit.collider.has_meta("mii"):
		return
	var mii: Node3D = hit.collider.get_meta("mii")
	Net.emote(mii.get_meta("seat"), "tomato")  # le serveur diffuse aux autres
	_throw_tomato(mii)                         # anim optimiste locale

func _on_notice(d: Dictionary) -> void:
	match d.get("kind", ""):
		"emote":
			# ne pas rejouer notre propre emote (déjà animée en optimiste)
			if d.get("from", "") != Net.last_name and d.get("text", "") == "tomato":
				var seat := int(d.get("target", "-1"))
				if seats.has(seat) and seats[seat].has("mii"):
					_throw_tomato(seats[seat]["mii"], int(d.get("from_seat", -1)))
		"chat":
			_set_status("%s : %s" % [d.get("from", "?"), d.get("text", "")])

# ---- HUD (charte Wii — portrait uniquement) ----

func _hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	# Bandeau haut : titre, badge de tour, enchère en cours.
	var top := VBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_top = 12
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_theme_constant_override("separation", 8)
	layer.add_child(top)

	title_lbl = UI.label("%s — %s" % [view.get("name", "Doodo"), view.get("code", "")], 15, UI.DIM, 800)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var tsb := UI.sb(Color(UI.PANEL, 0.66), Color(0, 0, 0, 0), 14, 0)
	tsb.content_margin_top = 4
	tsb.content_margin_bottom = 4
	title_lbl.add_theme_stylebox_override("normal", tsb)
	top.add_child(title_lbl)

	var tc := CenterContainer.new()
	top.add_child(tc)
	turn_lbl = UI.label("", 26, Color.WHITE, 700, true)
	turn_lbl.resized.connect(func() -> void: turn_lbl.pivot_offset = turn_lbl.size / 2.0)
	turn_lbl.visible = false
	tc.add_child(turn_lbl)

	var bc := CenterContainer.new()
	top.add_child(bc)
	bid_pill = UI.panel()
	bid_pill.resized.connect(func() -> void: bid_pill.pivot_offset = bid_pill.size / 2.0)
	bc.add_child(bid_pill)
	bid_row = HBoxContainer.new()
	bid_row.alignment = BoxContainer.ALIGNMENT_CENTER
	bid_row.add_theme_constant_override("separation", 8)
	bid_pill.add_child(bid_row)

	var pc := CenterContainer.new()
	top.add_child(pc)
	palifico_lbl = UI.pill("PALIFICO", Color("#FFF3D6"), UI.ORANGE_DK, 15)
	palifico_lbl.visible = false
	pc.add_child(palifico_lbl)

	# Toast éphémère haut-centre (chat, éliminations).
	var sc := CenterContainer.new()
	top.add_child(sc)
	status_lbl = UI.pill("", UI.PANEL, UI.INK, 18)
	status_lbl.visible = false
	sc.add_child(status_lbl)

	# Quitter : petit bouton discret en haut à droite.
	var leave_btn := UI.button("Quitter", "btn")
	leave_btn.custom_minimum_size = Vector2(0, 44)
	leave_btn.add_theme_font_size_override("font_size", 18)
	leave_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	leave_btn.offset_left = -110
	leave_btn.offset_right = -12
	leave_btn.offset_top = 12
	leave_btn.offset_bottom = 56
	leave_btn.pressed.connect(func() -> void:
		Net.leave()
		get_tree().call_deferred("change_scene_to_file", "res://menu.tscn"))
	layer.add_child(leave_btn)

	# Ma main : rangée d'icônes flottant juste au-dessus du panneau.
	var mc := CenterContainer.new()
	mc.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	mc.offset_top = -216
	mc.offset_bottom = -164
	layer.add_child(mc)
	my_dice_box = HBoxContainer.new()
	my_dice_box.add_theme_constant_override("separation", 10)
	mc.add_child(my_dice_box)

	# Panneau d'action en bas : hug content vers le haut, coins arrondis en
	# haut seulement — effet « bottom sheet » mobile.
	action_bar = UI.panel()
	var asb := action_bar.get_theme_stylebox("panel") as StyleBoxFlat
	asb.corner_radius_bottom_left = 0
	asb.corner_radius_bottom_right = 0
	action_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	action_bar.offset_left = 12
	action_bar.offset_right = -12
	action_bar.offset_top = -14
	action_bar.offset_bottom = -14
	action_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	layer.add_child(action_bar)

	var av := VBoxContainer.new()
	av.add_theme_constant_override("separation", 11)
	action_bar.add_child(av)

	# pickrow : stepper quantité [−][N][+] + sélecteur de faces.
	var pickrow := HBoxContainer.new()
	pickrow.alignment = BoxContainer.ALIGNMENT_CENTER
	pickrow.add_theme_constant_override("separation", 10)
	av.add_child(pickrow)

	var step := PanelContainer.new()
	var stsb := UI.sb(UI.PANEL, UI.EDGE, 14, 2)
	stsb.content_margin_top = 4
	stsb.content_margin_bottom = 4
	step.add_theme_stylebox_override("panel", stsb)
	pickrow.add_child(step)
	var sh := HBoxContainer.new()
	sh.add_theme_constant_override("separation", 2)
	step.add_child(sh)
	var minus := _step_btn("−")
	minus.pressed.connect(func() -> void: _set_qty(-1))
	sh.add_child(minus)
	qty_lbl = UI.label("1", 20, UI.INK, 700, true)
	qty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	qty_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	qty_lbl.custom_minimum_size = Vector2(46, 42)
	sh.add_child(qty_lbl)
	var plus := _step_btn("+")
	plus.pressed.connect(func() -> void: _set_qty(1))
	sh.add_child(plus)

	var face_row := HBoxContainer.new()
	face_row.alignment = BoxContainer.ALIGNMENT_CENTER
	face_row.add_theme_constant_override("separation", 6)
	pickrow.add_child(face_row)
	for v in 6:
		var ic := UI.DieIcon.new(v + 1, 48)
		ic.pivot_offset = Vector2(24, 24)
		ic.mouse_filter = Control.MOUSE_FILTER_STOP
		var face := v + 1
		ic.gui_input.connect(func(ev: InputEvent) -> void:
			var tap: bool = (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT) \
				or (ev is InputEventScreenTouch and ev.pressed)
			if tap:
				_set_face(face)
				var ft := ic.create_tween()
				ft.tween_property(ic, "scale", Vector2(1.28, 1.28), 0.07)
				ft.tween_property(ic, "scale", Vector2.ONE, 0.14) \
					.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))
		face_icons.append(ic)
		face_row.add_child(ic)

	# btnrow : trois actions à largeur égale (comme la maquette).
	var btnrow := HBoxContainer.new()
	btnrow.alignment = BoxContainer.ALIGNMENT_CENTER
	btnrow.add_theme_constant_override("separation", 9)
	av.add_child(btnrow)

	bid_btn = UI.button("Enchérir", "primary")
	bid_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bid_btn.pressed.connect(func() -> void: Net.bid(qty_val, val_face))
	btnrow.add_child(bid_btn)
	dudo_btn = UI.button("Dudo !", "dudo")
	dudo_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dudo_btn.pressed.connect(func() -> void: Net.dudo())
	btnrow.add_child(dudo_btn)
	calza_btn = UI.button("Calza !", "calza")
	calza_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	calza_btn.pressed.connect(func() -> void: Net.calza())
	btnrow.add_child(calza_btn)

	_set_face(1)

	# Overlay de révélation « night club » : dégradé bleu nuit opaque, orbes
	# lumineux, trame de pois claire, halo coloré derrière le titre.
	reveal_panel = Control.new()
	reveal_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	reveal_panel.visible = false
	layer.add_child(reveal_panel)

	_night_bg(reveal_panel)

	# Halo derrière le titre — teinté rouge ou vert à l'événement.
	reveal_glow = UI.orb(Color(1, 1, 1, 0.0), 420.0)
	reveal_glow.position = Vector2(-60, -230)
	reveal_panel.add_child(reveal_glow)

	var rmargin := MarginContainer.new()
	rmargin.set_anchors_preset(Control.PRESET_FULL_RECT)
	rmargin.add_theme_constant_override("margin_top", 96)
	rmargin.add_theme_constant_override("margin_left", 22)
	rmargin.add_theme_constant_override("margin_right", 22)
	reveal_panel.add_child(rmargin)

	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 20)
	rmargin.add_child(rv)

	reveal_title = UI.label("DUDO !", 58, Color("#FF6E66"), 700, true)
	reveal_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reveal_title.add_theme_constant_override("shadow_offset_x", 0)
	reveal_title.add_theme_constant_override("shadow_offset_y", 5)
	reveal_title.resized.connect(func() -> void:
		reveal_title.pivot_offset = reveal_title.size / 2.0)
	rv.add_child(reveal_title)

	reveal_sub = UI.label("", 14, Color("#9AA7C6"), 800)
	reveal_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reveal_sub.uppercase = true
	rv.add_child(reveal_sub)

	var bidc := CenterContainer.new()
	rv.add_child(bidc)
	var bid_p := PanelContainer.new()
	var bid_sb := UI.sb(Color(1, 1, 1, 0.08), Color(1, 1, 1, 0.22), 18, 1)
	bid_sb.content_margin_left = 26
	bid_sb.content_margin_right = 26
	bid_sb.content_margin_top = 12
	bid_sb.content_margin_bottom = 12
	bid_p.add_theme_stylebox_override("panel", bid_sb)
	bidc.add_child(bid_p)
	reveal_bid_line = HBoxContainer.new()
	reveal_bid_line.alignment = BoxContainer.ALIGNMENT_CENTER
	reveal_bid_line.add_theme_constant_override("separation", 10)
	bid_p.add_child(reveal_bid_line)

	reveal_dice_box = VBoxContainer.new()
	reveal_dice_box.add_theme_constant_override("separation", 18)
	rv.add_child(reveal_dice_box)

	reveal_count = UI.label("0", 44, Color("#63D97A"), 700, true)
	reveal_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reveal_count.add_theme_color_override("font_shadow_color", Color(0.24, 0.9, 0.42, 0.35))
	reveal_count.add_theme_constant_override("shadow_offset_y", 3)
	reveal_count.resized.connect(func() -> void:
		reveal_count.pivot_offset = reveal_count.size / 2.0)
	rv.add_child(reveal_count)

	reveal_verdict = UI.label("", 17, Color("#E9EDF7"), 800)
	reveal_verdict.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rv.add_child(reveal_verdict)

	reveal_verdict_sub = UI.label("", 14, Color("#9AA7C6"), 700)
	reveal_verdict_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rv.add_child(reveal_verdict_sub)

	# « Continuer » : capsule blanche centrée — remplissage bleu clair
	# avec liseré droit bleu, timer de 10 s déguisé.
	var wrapc := CenterContainer.new()
	rv.add_child(wrapc)
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(340, 58)
	wrapc.add_child(wrap)
	# La capsule reste blanche dans les deux thèmes (overlay toujours nuit).
	var rbg := PanelContainer.new()
	rbg.set_anchors_preset(Control.PRESET_FULL_RECT)
	rbg.add_theme_stylebox_override("panel", UI.sb(Color("#FFFFFF"), Color("#DCE3EE"), 29, 1, 3))
	wrap.add_child(rbg)
	reveal_fill = PanelContainer.new()
	reveal_fill.anchor_bottom = 1.0
	reveal_fill.offset_right = 0.0
	reveal_fill.clip_contents = true
	var fsb := UI.sb(Color(UI.BLUE, 0.3), UI.BLUE, 29, 0)
	fsb.border_width_right = 3
	reveal_fill.add_theme_stylebox_override("panel", fsb)
	wrap.add_child(reveal_fill)
	var rbtn_lbl := UI.label("Continuer", 19, UI.BLUE, 800)
	rbtn_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	rbtn_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rbtn_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	wrap.add_child(rbtn_lbl)
	var rbtn := Button.new()
	rbtn.set_anchors_preset(Control.PRESET_FULL_RECT)
	var transparent := UI.sb(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 29, 0)
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		rbtn.add_theme_stylebox_override(st, transparent)
	rbtn.pressed.connect(_hide_reveal)
	wrap.add_child(rbtn)

	var hint := UI.label("La manche reprend automatiquement", 13, Color("#7E8BAE"), 700)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rv.add_child(hint)

	# Overlay fin de partie : même ambiance « night club » que la révélation.
	over_root = Control.new()
	over_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	over_root.visible = false
	layer.add_child(over_root)
	_night_bg(over_root)
	var oc := CenterContainer.new()
	oc.set_anchors_preset(Control.PRESET_FULL_RECT)
	over_root.add_child(oc)
	over_box = VBoxContainer.new()
	over_box.add_theme_constant_override("separation", 14)
	oc.add_child(over_box)

# Fond « night club » commun aux overlays plein écran (révélation, fin) :
# dégradé bleu nuit opaque + orbes lumineux + trame de pois blanche.
func _night_bg(parent: Control) -> void:
	var bg_tex := TextureRect.new()
	bg_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg_tex.stretch_mode = TextureRect.STRETCH_SCALE
	var grad := Gradient.new()
	grad.set_color(0, Color("#0E1530"))
	grad.set_color(1, Color("#1E2B52"))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.width = 32
	gt.height = 256
	gt.fill = GradientTexture2D.FILL_LINEAR
	gt.fill_from = Vector2(0.5, 0.0)
	gt.fill_to = Vector2(0.5, 1.0)
	bg_tex.texture = gt
	parent.add_child(bg_tex)
	for o in [
		[Vector2(-120, 120), Color("#3FC8EC"), 0.22, 340.0],
		[Vector2(430, 560), Color("#7BC94E"), 0.18, 400.0],
		[Vector2(-60, 980), Color("#FFB45F"), 0.15, 330.0],
	]:
		var orb := UI.orb(Color(o[1], o[2]), o[3])
		orb.position = o[0]
		parent.add_child(orb)
	var d := UI.Dots.new()
	d.col = Color(1, 1, 1, 0.06)
	parent.add_child(d)

func _process(delta: float) -> void:
	sway_t += delta
	cam.rotation.y += sin(sway_t * 0.6) * 0.00005
	cam.rotation.x += cos(sway_t * 0.45) * 0.00004

# ---- Scène : décor, table, caméra, tomate (identiques au proto) ----

# Palettes Mii du salon (référence — une scène peut fournir les siennes).
const SALON_SKINS: Array[Color] = [Color(0.95, 0.78, 0.6), Color(0.85, 0.62, 0.42), Color(0.98, 0.85, 0.7), Color(0.7, 0.5, 0.35), Color(0.92, 0.72, 0.55), Color(0.8, 0.6, 0.45)]
const SALON_SHIRTS: Array[Color] = [Color(0.2, 0.5, 0.85), Color(0.85, 0.3, 0.25), Color(0.2, 0.65, 0.3), Color(0.9, 0.75, 0.2), Color(0.55, 0.3, 0.7), Color(0.3, 0.7, 0.75)]
const SALON_HAIRS: Array[Color] = [Color(0.2, 0.12, 0.06), Color(0.5, 0.32, 0.15), Color(0.1, 0.1, 0.1), Color(0.75, 0.55, 0.2), Color(0.35, 0.2, 0.1), Color(0.6, 0.6, 0.65)]

var _scene: Dictionary = {} # entrée active du registry de décors

# Registry des décors 3D (specs_artistiques §3). Chaque entrée :
#   build: Callable          construit décor + table + caméra
#   char: Callable(h) -> Node3D  personnage d'un siège (défaut _char_mii)
# `salon` est le décor par défaut et le fallback : id inconnu → salon.
func _scenes() -> Dictionary:
	return {
		"salon": {"build": _scene_salon},
		"cimetiere": {"build": _scene_graveyard, "char": _char_skeleton},
	}

# Mii aux palettes salon — référence ; une scène peut varier via `char`.
func _char_mii(h: int) -> Node3D:
	return Mii.build(SALON_SKINS[h % 6], SALON_SHIRTS[(h / 6) % 6],
		SALON_HAIRS[(h / 36) % 6], h % 3 == 0, h % 6, h % 4)

func _char_skeleton(h: int) -> Node3D:
	return Skeleton.build(h % 4, h)

func _build_scene() -> void:
	var id := String(UI.obj(view.get("options")).get("scene", ""))
	var reg := _scenes()
	_scene = reg.get(id, reg["salon"])
	_scene.build.call()

func _scene_salon() -> void:
	_environment()
	_lights()
	_room()
	_table()
	_camera()

# Cimetière nuit : même table/gobelets/caméra que le salon, mais le décor est
# une toile de fond illustrée (assets/graveyard_bg.png) + sol sombre +
# quelques pierres tombales pour la parallaxe.
func _scene_graveyard() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.05, 0.09)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.38, 0.52)
	env.ambient_light_energy = 0.7
	env.fog_enabled = true
	env.fog_light_color = Color(0.08, 0.12, 0.18)
	env.fog_density = 0.04
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# Lune froide + appoint chaud au-dessus de la table pour la lisibilité.
	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-50, -25, 0)
	moon.light_color = Color(0.6, 0.7, 0.95)
	moon.light_energy = 0.8
	moon.shadow_enabled = true
	add_child(moon)

	var key := OmniLight3D.new()
	key.position = Vector3(0, 2.5, 0.3)
	key.light_color = Color(1.0, 0.82, 0.6)
	key.light_energy = 1.1
	key.omni_range = 6.0
	key.shadow_enabled = true
	add_child(key)

	# Sol herbeux sombre.
	var ground := PlaneMesh.new()
	ground.size = Vector2(40, 40)
	add_child(_mesh(ground, Color(0.07, 0.11, 0.08), Vector3(0, -0.01, -4), 1.0))

	# Toile de fond : illustration panoramique, non éclairée, centrée derrière
	# l'arc de sièges et assez large pour encaisser le léger balancement caméra.
	var bg := MeshInstance3D.new()
	var bg_quad := QuadMesh.new()
	bg_quad.size = Vector2(28, 15.75) # 16:9
	var bg_mat := StandardMaterial3D.new()
	bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg_mat.albedo_texture = load("res://assets/graveyard_bg.png")
	bg_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	bg_quad.material = bg_mat
	bg.mesh = bg_quad
	bg.position = Vector3(0, 6.5, -9)
	add_child(bg)

	# Pierres tombales éparses — volumes simples pour casser la planéité
	# du fond et donner de la profondeur aux squelettes.
	var stone := Color(0.28, 0.3, 0.34)
	for t in [
		[Vector3(-3.4, 0.3, -4.6), Vector3(0.5, 0.6, 0.12), 8.0],
		[Vector3(3.6, 0.35, -5.0), Vector3(0.55, 0.7, 0.12), -6.0],
		[Vector3(-2.2, 0.25, -5.8), Vector3(0.42, 0.5, 0.12), -12.0],
		[Vector3(2.4, 0.28, -6.2), Vector3(0.45, 0.56, 0.12), 10.0],
		[Vector3(-4.6, 0.32, -3.0), Vector3(0.5, 0.64, 0.12), 18.0],
		[Vector3(4.7, 0.3, -3.4), Vector3(0.48, 0.6, 0.12), -15.0],
	]:
		var grave := BoxMesh.new()
		grave.size = t[1]
		var gi := _mesh(grave, stone.darkened(randf() * 0.15), t[0], 0.95)
		gi.rotation_degrees.y = t[2]
		add_child(gi)

	# Deux troncs d'arbres morts pour fermer les côtés.
	for side in [-1.0, 1.0]:
		var trunk := CylinderMesh.new()
		trunk.top_radius = 0.1
		trunk.bottom_radius = 0.22
		trunk.height = 4.5
		var ti := _mesh(trunk, Color(0.1, 0.09, 0.1), Vector3(side * 5.2, 2.25, -6.5), 1.0)
		ti.rotation_degrees.z = side * 6.0
		add_child(ti)

	_table()
	_camera()

func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.05, 0.08)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.46, 0.36)
	env.ambient_light_energy = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

func _lights() -> void:
	var key := OmniLight3D.new()
	key.position = Vector3(0, 2.5, 0.2)
	key.light_color = Color(1.0, 0.84, 0.62)
	key.light_energy = 1.8
	key.omni_range = 7.0
	key.shadow_enabled = true
	add_child(key)

	var fill := OmniLight3D.new()
	fill.position = Vector3(0, 1.8, -3.8)
	fill.light_color = Color(0.5, 0.6, 0.9)
	fill.light_energy = 0.4
	fill.omni_range = 6.0
	add_child(fill)

	for side in [-1.0, 1.0]:
		var sconce := OmniLight3D.new()
		sconce.position = Vector3(side * 3.5, 2.0, -4.0)
		sconce.light_color = Color(1.0, 0.8, 0.55)
		sconce.light_energy = 0.5
		sconce.omni_range = 4.0
		add_child(sconce)

func _room() -> void:
	var floor_m := PlaneMesh.new()
	floor_m.size = Vector2(12, 12)
	add_child(_mesh(floor_m, Color(0.42, 0.28, 0.16), Vector3.ZERO, 0.9))

	var ceil_m := PlaneMesh.new()
	ceil_m.size = Vector2(12, 12)
	var ceil_i := _mesh(ceil_m, Color(0.75, 0.7, 0.62), Vector3(0, 3.0, 0))
	ceil_i.rotation_degrees.x = 180
	add_child(ceil_i)

	var wall_color := Color(0.82, 0.74, 0.6)
	var walls := [
		[Vector3(0, 1.5, -4.5), Vector3(10, 3, 0.12)],
		[Vector3(0, 1.5, 4.5), Vector3(10, 3, 0.12)],
		[Vector3(-4.5, 1.5, 0), Vector3(0.12, 3, 10)],
		[Vector3(4.5, 1.5, 0), Vector3(0.12, 3, 10)],
	]
	for w in walls:
		var wm := BoxMesh.new()
		wm.size = w[1]
		add_child(_mesh(wm, wall_color, w[0]))

	var glass := QuadMesh.new()
	glass.size = Vector2(3.2, 1.6)
	add_child(_mesh(glass, Color(0.06, 0.12, 0.4), Vector3(0, 1.7, -4.42), 0.4, true))

	var frame_mat := Color(0.25, 0.15, 0.08)
	var frame_parts := [
		[Vector3(0, 2.55, -4.4), Vector3(3.4, 0.12, 0.1)],
		[Vector3(0, 0.85, -4.4), Vector3(3.4, 0.12, 0.1)],
		[Vector3(-1.65, 1.7, -4.4), Vector3(0.12, 1.8, 0.1)],
		[Vector3(1.65, 1.7, -4.4), Vector3(0.12, 1.8, 0.1)],
		[Vector3(0, 1.7, -4.4), Vector3(0.08, 1.6, 0.1)],
		[Vector3(-0.82, 1.7, -4.4), Vector3(0.08, 1.6, 0.1)],
		[Vector3(0.82, 1.7, -4.4), Vector3(0.08, 1.6, 0.1)],
	]
	for f in frame_parts:
		var fm := BoxMesh.new()
		fm.size = f[1]
		add_child(_mesh(fm, frame_mat, f[0], 0.6))

	for side in [-1.0, 1.0]:
		var sconce_m := QuadMesh.new()
		sconce_m.size = Vector2(0.25, 0.35)
		add_child(_mesh(sconce_m, Color(1.0, 0.85, 0.55), Vector3(side * 3.5, 2.0, -4.42), 0.5, true))

	var pic := BoxMesh.new()
	pic.size = Vector3(0.9, 0.7, 0.06)
	add_child(_mesh(pic, Color(0.3, 0.45, 0.35), Vector3(-4.42, 1.8, -1.0)))

	for side in [-1.0, 1.0]:
		var pot := CylinderMesh.new()
		pot.top_radius = 0.16
		pot.bottom_radius = 0.12
		pot.height = 0.35
		add_child(_mesh(pot, Color(0.55, 0.35, 0.2), Vector3(side * 3.6, 0.175, -3.6), 0.7))
		for i in 3:
			var leaf := SphereMesh.new()
			leaf.radius = 0.22
			leaf.height = 0.44
			var leaf_m := _mesh(leaf, Color(0.15, 0.4, 0.15).darkened(i * 0.06), Vector3(side * 3.6 + (i - 1) * 0.15, 0.6 + i * 0.12, -3.6), 0.9)
			leaf_m.scale = Vector3(1.0, 1.6, 0.6)
			add_child(leaf_m)

func _table() -> void:
	var top := CylinderMesh.new()
	top.top_radius = TABLE_RADIUS
	top.bottom_radius = TABLE_RADIUS
	top.height = 0.06
	top.radial_segments = 48
	add_child(_mesh(top, Color(0.12, 0.36, 0.2), Vector3(0, 0.75, 0), 0.95))

	var rim := TorusMesh.new()
	rim.inner_radius = TABLE_RADIUS - 0.04
	rim.outer_radius = TABLE_RADIUS + 0.02
	rim.rings = 48
	rim.ring_segments = 12
	add_child(_mesh(rim, Color(0.35, 0.2, 0.1), Vector3(0, 0.78, 0), 0.5))

	var leg := CylinderMesh.new()
	leg.top_radius = 0.12
	leg.bottom_radius = 0.18
	leg.height = 0.75
	# Piètement en fonte sombre — tranche avec le bois du gobelet.
	var leg_mi := _mesh(leg, Color(0.13, 0.14, 0.17), Vector3(0, 0.375, 0), 0.35)
	(leg_mi.mesh.material as StandardMaterial3D).metallic = 0.7
	add_child(leg_mi)

func _cup_mesh() -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = 0.08
	cm.bottom_radius = 0.105
	cm.height = 0.17
	cm.radial_segments = 24
	return _mesh(cm, Color(0.4, 0.23, 0.1), Vector3.ZERO, 0.55)

func _camera() -> void:
	cam = Camera3D.new()
	cam.fov = 70.0
	add_child(cam)
	cam.look_at_from_position(Vector3(0, 1.55, 3.0), Vector3(0, 0.82, -0.3))

func _make_splat_texture() -> ImageTexture:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for i in 9:
		var c := Vector2i(32 + randi_range(-14, 14), 32 + randi_range(-14, 14))
		Die._fill_circle(img, c, randi_range(7, 16), Color(0.8, 0.1, 0.05, 0.95))
	return ImageTexture.create_from_image(img)

func _throw_tomato(mii: Node3D, from_seat := -1) -> void:
	var tomato := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.055
	sm.height = 0.11
	sm.material = mat(Color(0.8, 0.1, 0.05), 0.5)
	tomato.mesh = sm
	add_child(tomato)

	# Origine : mes mains si c'est moi (ou un spectateur « dans les tribunes »),
	# sinon la main du lanceur (son Mii, légèrement vers la table).
	var p0 := Vector3(0, 1.15, 2.5)
	if from_seat >= 0 and from_seat != view.get("your_seat", -2) \
			and seats.has(from_seat) and seats[from_seat].has("mii"):
		var fm: Node3D = seats[from_seat]["mii"]
		var inward := -fm.global_position
		inward.y = 0
		p0 = fm.global_position + Vector3(0, 1.25, 0) + inward.normalized() * 0.3
	var p2: Vector3 = mii.global_position + Vector3(0, 1.32, 0.05)
	var mid := (p0 + p2) / 2.0 + Vector3(0, 0.8, 0)
	var twn := create_tween()
	twn.tween_method(_bezier_move.bind(tomato, p0, mid, p2), 0.0, 1.0, 0.55).set_ease(Tween.EASE_IN)
	twn.tween_callback(_tomato_impact.bind(mii, tomato, p2))

func _bezier_move(t: float, tomato: MeshInstance3D, p0: Vector3, mid: Vector3, p2: Vector3) -> void:
	tomato.global_position = p0.lerp(mid, t).lerp(mid.lerp(p2, t), t)

func _tomato_impact(mii: Node3D, tomato: MeshInstance3D, at: Vector3) -> void:
	tomato.queue_free()

	var ppm := ParticleProcessMaterial.new()
	ppm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	ppm.emission_sphere_radius = 0.03
	ppm.direction = Vector3(0, 0.6, 0.6)
	ppm.spread = 70.0
	ppm.initial_velocity_min = 1.0
	ppm.initial_velocity_max = 2.4
	ppm.gravity = Vector3(0, -6, 0)
	ppm.scale_min = 0.5
	ppm.scale_max = 1.4
	var gp := GPUParticles3D.new()
	gp.process_material = ppm
	gp.amount = 28
	gp.lifetime = 0.7
	gp.one_shot = true
	gp.explosiveness = 1.0
	var dm := SphereMesh.new()
	dm.radius = 0.012
	dm.height = 0.024
	dm.material = mat(Color(0.8, 0.1, 0.05), 0.5)
	gp.draw_pass_1 = dm
	gp.position = at
	add_child(gp)
	gp.emitting = true
	get_tree().create_timer(1.5).timeout.connect(gp.queue_free)

	var splat := MeshInstance3D.new()
	var sq := QuadMesh.new()
	sq.size = Vector2(0.2, 0.2)
	var sqm := StandardMaterial3D.new()
	sqm.albedo_texture = splat_tex
	sqm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sq.material = sqm
	splat.mesh = sq
	if mii.has_method("attach_splat"):
		mii.attach_splat(splat)
	else:
		splat.position = Vector3(0, 1.32, 0.16)
		mii.add_child(splat)
	get_tree().create_timer(3.0).timeout.connect(splat.queue_free)

	mii.set_face(3)
	mii.play_flinch()
	get_tree().create_timer(3.0).timeout.connect(func() -> void: mii.set_face(mii._face))
