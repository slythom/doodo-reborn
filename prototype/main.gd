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
var seats := {}          # seat_idx -> {mii, cup, name_lbl, count_lbl}
var my_dice: Array[Die] = []
var splat_tex: ImageTexture
var cam: Camera3D
var sway_t := 0.0
var splat_by_mii := {}   # mii -> splat node

# HUD
var title_lbl: Label
var bid_lbl: Label
var turn_lbl: Label
var status_lbl: Label
var qty_spin: SpinBox
var val_opt: OptionButton
var bid_btn: Button
var dudo_btn: Button
var calza_btn: Button
var reveal_panel: PanelContainer
var reveal_lbl: Label
var over_panel: PanelContainer
var over_lbl: Label
var rematch_btn: Button
var action_bar: VBoxContainer

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
	randomize()
	splat_tex = _make_splat_texture()
	_environment()
	_lights()
	_room()
	_table()
	_camera()
	_hud()
	view = Net.view
	_build_seats()
	_refresh()
	Net.room_state.connect(_on_view)
	Net.game_events.connect(_on_events)
	Net.net_error.connect(func(_c: String, m: String) -> void: status_lbl.text = m)
	Net.notice_msg.connect(_on_notice)
	Net.connection_closed.connect(func() -> void: status_lbl.text = "connexion perdue — reconnexion…")
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
	var n: int = view.players.size()
	var my_seat: int = view.get("your_seat", -1)
	var is_spectator := my_seat < 0
	var skins := [Color(0.95, 0.78, 0.6), Color(0.85, 0.62, 0.42), Color(0.98, 0.85, 0.7), Color(0.7, 0.5, 0.35), Color(0.92, 0.72, 0.55), Color(0.8, 0.6, 0.45)]
	var shirts := [Color(0.2, 0.5, 0.85), Color(0.85, 0.3, 0.25), Color(0.2, 0.65, 0.3), Color(0.9, 0.75, 0.2), Color(0.55, 0.3, 0.7), Color(0.3, 0.7, 0.75)]
	var hairs := [Color(0.2, 0.12, 0.06), Color(0.5, 0.32, 0.15), Color(0.1, 0.1, 0.1), Color(0.75, 0.55, 0.2), Color(0.35, 0.2, 0.1), Color(0.6, 0.6, 0.65)]

	# En spectateur, tous les joueurs sont sur l'arc (triés par siège).
	var plist: Array = view.players.duplicate()
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
			# Moi : mains + dés visibles (vue subjective, pas de Mii).
			_build_my_hands()
			continue

		# Adversaire : Mii aux variantes déterministes (dérivées du nom).
		var h: int = abs(p.get("name", "?").hash())
		var mii := Mii.build(skins[h % 6], shirts[(h / 6) % 6], hairs[(h / 36) % 6], h % 3 == 0, h % 6, h % 4)
		mii.position = pos
		mii.rotation.y = atan2(-pos.x, -pos.z)
		mii.set_meta("seat", p_seat)
		add_child(mii)
		seat["mii"] = mii

		var nl := Label3D.new()
		nl.text = p.get("name", "?")
		nl.font_size = 48
		nl.position = pos + Vector3(0, 1.75, 0)
		nl.modulate = Color(1, 1, 1, 0.85)
		add_child(nl)
		seat["name_lbl"] = nl

		var cl := Label3D.new()
		cl.font_size = 40
		cl.position = Vector3(cos(a) * (CUP_RADIUS + 0.02), TABLE_TOP_Y + 0.32, sin(a) * (CUP_RADIUS + 0.02))
		cl.modulate = Color(1, 0.9, 0.5)
		add_child(cl)
		seat["count_lbl"] = cl

func _build_my_hands() -> void:
	var skin := Color(0.95, 0.78, 0.6)
	for side in [-1.0, 1.0]:
		var hand := MeshInstance3D.new()
		var hs := SphereMesh.new()
		hs.radius = 0.045
		hs.height = 0.09
		hs.material = mat(skin, 0.55)
		hand.mesh = hs
		hand.position = Vector3(side * 0.45, TABLE_TOP_Y + 0.03, 1.3)
		add_child(hand)

# ---- Rafraîchissement depuis le snapshot ----

func _refresh() -> void:
	_update_players()
	_update_my_dice()
	_update_turn()
	_update_bid()
	_update_actions()

func _update_players() -> void:
	for i in view.players.size():
		var p: Dictionary = view.players[i]
		var p_seat: int = p.get("seat", i)
		if not seats.has(p_seat):
			continue
		var seat: Dictionary = seats[p_seat]
		var eliminated: bool = p.get("dice_count", 0) == 0
		if seat.has("count_lbl"):
			seat["count_lbl"].text = "éliminé" if eliminated else "%d dé(s)" % p.get("dice_count", 0)
		if seat.has("mii") and eliminated:
			seat["mii"].modulate = Color(1, 1, 1, 0.3)

func _update_my_dice() -> void:
	for d in my_dice:
		d.queue_free()
	my_dice.clear()
	var me := _player_by_seat(view.get("your_seat", -1))
	if me.is_empty():
		return
	var dice_vals: Array = me.get("dice", [])
	var a := deg_to_rad(MY_SEAT_ANGLE)
	var center := Vector3(cos(a) * (CUP_RADIUS + 0.25), TABLE_TOP_Y + Die.SIZE / 2.0 + 0.001, sin(a) * (CUP_RADIUS + 0.25))
	for i in dice_vals.size():
		var d := Die.build()
		d.freeze = true
		var spread := dice_vals.size() - 1
		d.position = center + Vector3((i - spread / 2.0) * 0.1, 0, 0.12)
		d.rotation_degrees = _face_up_rotation(dice_vals[i])
		add_child(d)
		my_dice.append(d)

# Fait pointer la face `value` du dé vers le haut.
# Faces de Die.build : 5:+Y 2:-Y 3:+X 4:-X 1:-Z (FORWARD) 6:+Z (BACK).
func _face_up_rotation(v: int) -> Vector3:
	match v:
		5: return Vector3.ZERO
		2: return Vector3(180, 0, 0)
		3: return Vector3(0, 0, 90)
		4: return Vector3(0, 0, -90)
		1: return Vector3(90, 0, 0)   # -Z -> +Y
		6: return Vector3(-90, 0, 0)  # +Z -> +Y
	return Vector3.ZERO

func _player_by_seat(seat: int) -> Dictionary:
	for p in view.get("players", []):
		if int(p.get("seat", -1)) == seat:
			return p
	return {}

func _update_turn() -> void:
	var turn: int = view.get("turn", -1)
	var mine: int = view.get("your_seat", -1)
	if turn == mine:
		turn_lbl.text = "À toi de jouer !"
		turn_lbl.modulate = Color(0.4, 1, 0.4)
	elif turn >= 0:
		turn_lbl.text = "Tour de %s" % _player_name(turn)
		turn_lbl.modulate = Color(1, 1, 1, 0.7)
	else:
		turn_lbl.text = ""

func _update_bid() -> void:
	if view.get("has_bid", false):
		var b: Dictionary = view.bid
		var bidder := _player_name(view.get("bidder", -1))
		var vstr := "paco" if b.get("value", 0) == 1 else str(b.get("value", 0))
		bid_lbl.text = "Enchère : %d x %s — %s" % [b.get("quantity", 0), vstr, bidder]
	else:
		bid_lbl.text = "Manche %d — pas encore d'enchère" % view.get("round", 1)
	if view.get("palifico", false):
		bid_lbl.text += "   [PALIFICO]"

# Reproduction client-side de la légalité (miroir de game.LegalBid) pour
# activer/désactiver le bouton — le serveur reste l'arbitre.
func _legal(q: int, v: int) -> bool:
	if q < 1 or v < 1 or v > 6:
		return false
	if not view.get("has_bid", false):
		return view.get("palifico", false) or v != 1  # ouverture : paco interdit
	var c: Dictionary = view.bid
	var cq: int = c.get("quantity", 0)
	var cv: int = c.get("value", 1)
	if view.get("palifico", false):
		return q > cq  # valeur figée côté serveur
	if cv == 1 and v != 1:
		return q >= 2 * cq + 1
	if cv != 1 and v == 1:
		return q >= int(ceil(cq / 2.0))
	return q > cq or (q == cq and v > cv)

func _update_actions() -> void:
	var spectator: bool = view.get("your_seat", -1) < 0
	action_bar.visible = not spectator and not view.get("over", false)
	if spectator:
		return
	var my_turn: bool = view.get("turn", -1) == view.get("your_seat", -2) and not view.get("over", false)
	bid_btn.disabled = not my_turn or not _legal(int(qty_spin.value), val_opt.selected + 1)
	dudo_btn.disabled = not my_turn or not view.get("has_bid", false)
	calza_btn.disabled = not my_turn or not view.get("has_bid", false) or not view.get("options", {}).get("game", {}).get("calza_enabled", true)

# ---- Événements serveur (révélation, pertes, fin) ----

func _on_events(events: Array) -> void:
	for e in events:
		match e.get("type", ""):
			"reveal":
				_show_reveal(e)
			"eliminated":
				var name := _player_name(e.get("player", -1))
				status_lbl.text = "%s est éliminé" % name
			"game_over":
				_show_game_over(e)

func _player_name(seat: int) -> String:
	return _player_by_seat(seat).get("name", "?")

func _show_reveal(e: Dictionary) -> void:
	var lines := PackedStringArray()
	lines.append("Enchère %d x %s — réalité : %d" % [
		e.get("bid", {}).get("quantity", 0),
		"paco" if e.get("bid", {}).get("value", 0) == 1 else str(e.get("bid", {}).get("value", 0)),
		e.get("count", 0)])
	var dice: Array = e.get("dice", [])
	for i in dice.size():
		if dice[i] is Array and not dice[i].is_empty():
			lines.append("%s : %s" % [_player_name(i), str(dice[i])])
	reveal_lbl.text = "\n".join(lines)
	reveal_panel.visible = true
	get_tree().create_timer(4.0).timeout.connect(func() -> void: reveal_panel.visible = false)

func _show_game_over(e: Dictionary) -> void:
	var lines := PackedStringArray(["Classement"])
	for r in e.get("ranking", []).size():
		var seat: int = e["ranking"][r]
		lines.append("%d. %s" % [r + 1, _player_name(seat)])
	over_lbl.text = "\n".join(lines)
	rematch_btn.visible = view.get("your_seat", -1) >= 0 # joueurs seulement
	over_panel.visible = true

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
	var mii: Mii = hit.collider.get_meta("mii")
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
			status_lbl.text = "%s : %s" % [d.get("from", "?"), d.get("text", "")]

# ---- HUD ----

func _hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	title_lbl = _label(20, HORIZONTAL_ALIGNMENT_CENTER)
	title_lbl.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title_lbl.position.y = 20
	title_lbl.text = "%s — %s" % [view.get("name", "Doodo"), view.get("code", "")]
	layer.add_child(title_lbl)

	bid_lbl = _label(30, HORIZONTAL_ALIGNMENT_CENTER)
	bid_lbl.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bid_lbl.position.y = 90
	layer.add_child(bid_lbl)

	turn_lbl = _label(26, HORIZONTAL_ALIGNMENT_CENTER)
	turn_lbl.set_anchors_preset(Control.PRESET_TOP_WIDE)
	turn_lbl.position.y = 140
	layer.add_child(turn_lbl)

	status_lbl = _label(20, HORIZONTAL_ALIGNMENT_CENTER)
	status_lbl.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	status_lbl.position.y = -180
	layer.add_child(status_lbl)

	# Barre d'actions en bas : deux lignes pour tenir en portrait 720 px.
	action_bar = VBoxContainer.new()
	var bar := action_bar
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.position.y = -170
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 10)
	layer.add_child(bar)

	var row1 := HBoxContainer.new()
	row1.alignment = BoxContainer.ALIGNMENT_CENTER
	row1.add_theme_constant_override("separation", 12)
	bar.add_child(row1)

	qty_spin = SpinBox.new()
	qty_spin.min_value = 1
	qty_spin.max_value = 60
	qty_spin.value = 1
	qty_spin.custom_minimum_size = Vector2(100, 60)
	qty_spin.add_theme_font_size_override("font_size", 26)
	qty_spin.value_changed.connect(func(_v: float) -> void: _update_actions())
	row1.add_child(qty_spin)

	val_opt = OptionButton.new()
	for v in ["Paco", "2", "3", "4", "5", "6"]:
		val_opt.add_item(v)
	val_opt.custom_minimum_size = Vector2(140, 60)
	val_opt.add_theme_font_size_override("font_size", 26)
	val_opt.item_selected.connect(func(_i: int) -> void: _update_actions())
	row1.add_child(val_opt)

	bid_btn = _button("Enchérir", row1)
	bid_btn.pressed.connect(func() -> void: Net.bid(int(qty_spin.value), val_opt.selected + 1))

	var row2 := HBoxContainer.new()
	row2.alignment = BoxContainer.ALIGNMENT_CENTER
	row2.add_theme_constant_override("separation", 12)
	bar.add_child(row2)

	dudo_btn = _button("Dudo !", row2)
	dudo_btn.pressed.connect(func() -> void: Net.dudo())
	calza_btn = _button("Calza !", row2)
	calza_btn.pressed.connect(func() -> void: Net.calza())

	var leave_btn := _button("Quitter", row2)
	leave_btn.pressed.connect(func() -> void:
		Net.leave()
		get_tree().call_deferred("change_scene_to_file", "res://menu.tscn"))

	# Overlay de révélation (2D, décision actée).
	reveal_panel = PanelContainer.new()
	reveal_panel.visible = false
	reveal_panel.set_anchors_preset(Control.PRESET_CENTER)
	reveal_panel.custom_minimum_size = Vector2(560, 0)
	layer.add_child(reveal_panel)
	reveal_lbl = _label(24, HORIZONTAL_ALIGNMENT_CENTER)
	reveal_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	reveal_panel.add_child(reveal_lbl)

	# Overlay fin de partie.
	over_panel = PanelContainer.new()
	over_panel.visible = false
	over_panel.set_anchors_preset(Control.PRESET_CENTER)
	layer.add_child(over_panel)
	var vb := VBoxContainer.new()
	over_panel.add_child(vb)
	over_lbl = _label(30, HORIZONTAL_ALIGNMENT_CENTER)
	vb.add_child(over_lbl)
	rematch_btn = _button("Revanche", vb)
	rematch_btn.pressed.connect(func() -> void: Net.rematch())
	var back_btn := _button("Retour au menu", vb)
	back_btn.pressed.connect(func() -> void:
		Net.leave()
		get_tree().call_deferred("change_scene_to_file", "res://menu.tscn"))

func _label(size: int, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.horizontal_alignment = align
	return l

func _button(text: String, parent: Container) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 64)
	b.add_theme_font_size_override("font_size", 26)
	parent.add_child(b)
	return b

func _process(delta: float) -> void:
	sway_t += delta
	cam.rotation.y += sin(sway_t * 0.6) * 0.00005
	cam.rotation.x += cos(sway_t * 0.45) * 0.00004

# ---- Scène : décor, table, caméra, tomate (identiques au proto) ----

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
	add_child(_mesh(leg, Color(0.3, 0.18, 0.09), Vector3(0, 0.375, 0), 0.6))

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

func _throw_tomato(mii: Mii, from_seat := -1) -> void:
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
		var fm: Mii = seats[from_seat]["mii"]
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

func _tomato_impact(mii: Mii, tomato: MeshInstance3D, at: Vector3) -> void:
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
	splat.position = Vector3(0, 1.32, 0.16)
	mii.add_child(splat)
	get_tree().create_timer(3.0).timeout.connect(splat.queue_free)

	mii.set_face(3)
	mii.play_flinch()
	get_tree().create_timer(3.0).timeout.connect(func() -> void: mii.set_face(mii._face))
