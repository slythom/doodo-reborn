# menu.gd — écran d'accueil + salle d'attente.
# Connexion (pseudo+jeton), création/join par code, lobby joueurs, lancement.
extends Control

var _name_edit: LineEdit
var _code_edit: LineEdit
var _status: Label
var _home: VBoxContainer
var _home_card: PanelContainer
var _lobby: VBoxContainer
var _lobby_card: PanelContainer
var _room_lbl: Label
var _code_lbl: Label
var _players_box: VBoxContainer
var _launch_btn: Button
var _pending := ""
var _pending_code := ""
static var _e2e_started := false

func _ready() -> void:
	UI.load_theme()
	_build_ui()
	Net.connection_opened.connect(func() -> void:
		var pseudo := _name_edit.text.strip_edges()
		if pseudo.length() < 2:
			pseudo = "Joueur"
		Net.hello(pseudo))
	Net.welcome.connect(func(_t: String) -> void:
		match _pending:
			"create": Net.create_room()
			"join": Net.join_room(_pending_code)
			"quick": Net.quick_match()
		_pending = "")
	Net.room_state.connect(_on_view)
	Net.net_error.connect(func(c: String, m: String) -> void: _set_status("[%s] %s" % [c, m]))
	Net.connection_closed.connect(func() -> void: _set_status("connexion perdue — reconnexion…"))
	Net.notice_msg.connect(_on_notice)
	if _name_edit.text == "":
		_name_edit.text = Net.last_name
	# Cible de focus initiale (manette/clavier) — pas de clavier virtuel sur mobile.
	if OS.get_name() != "Android" and OS.get_name() != "iOS":
		_name_edit.call_deferred("grab_focus")
	# Retour au menu avec connexion active (depuis la partie) : resync serveur.
	if Net.is_open():
		Net.hello()
	elif not Net.view.is_empty():
		_on_view(Net.view)
	# Mode test e2e : --e2e crée une salle + bot et lance la partie automatiquement.
	# Garde : le menu peut se recharger (retour lobby) — ne pas relancer.
	if OS.get_cmdline_user_args().has("--e2e") and not _e2e_started:
		_e2e_started = true
		_e2e()

func _e2e() -> void:
	_name_edit.text = "e2e-tester"
	_connect("create")
	await get_tree().create_timer(1.5).timeout
	Net.add_bot()
	await get_tree().create_timer(1.0).timeout
	Net.launch()

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = UI.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	add_child(UI.Dots.new())
	# Taches pastel douces — écho aux orbes de l'écran de révélation.
	for o in [
		[Vector2(430, -70), Color("#6FC6EA"), 0.15, 380.0],
		[Vector2(-170, 760), Color("#8ED36B"), 0.13, 420.0],
		[Vector2(370, 1100), Color("#FFB45F"), 0.11, 320.0],
	]:
		var orb := UI.orb(Color(o[1], o[2]), o[3])
		orb.position = o[0]
		add_child(orb)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	_home = VBoxContainer.new()
	_home.custom_minimum_size.x = 500
	_home.add_theme_constant_override("separation", 20)
	center.add_child(_home)

	# Logo : DOODO Fredoka encadré de deux dés inclinés.
	var logo := HBoxContainer.new()
	logo.alignment = BoxContainer.ALIGNMENT_CENTER
	logo.add_theme_constant_override("separation", 20)
	_home.add_child(logo)
	var d1 := UI.DieIcon.new(3, 40)
	d1.rotation_degrees = -9
	logo.add_child(d1)
	var title := UI.label("DOODO", 76, UI.BLUE, 700, true)
	title.add_theme_color_override("font_shadow_color", Color(UI.BLUE_DK, 0.35))
	title.add_theme_constant_override("shadow_offset_y", 5)
	title.resized.connect(func() -> void: title.pivot_offset = title.size / 2.0)
	logo.add_child(title)
	var d2 := UI.DieIcon.new(5, 40)
	d2.rotation_degrees = 9
	logo.add_child(d2)
	# Le titre flotte doucement (wobble infini, écran d'accueil Wii).
	# Bindé à title : le tween meurt avec le nœud (rebuild du thème).
	var wob := title.create_tween().set_loops()
	wob.tween_property(title, "scale", Vector2(1.04, 1.04), 1.4).set_trans(Tween.TRANS_SINE)
	wob.parallel().tween_property(title, "rotation_degrees", -1.2, 1.4).set_trans(Tween.TRANS_SINE)
	wob.tween_property(title, "scale", Vector2.ONE, 1.4).set_trans(Tween.TRANS_SINE)
	wob.parallel().tween_property(title, "rotation_degrees", 0.0, 1.4).set_trans(Tween.TRANS_SINE)

	var subc := CenterContainer.new()
	subc.add_child(UI.pill("PERUDO EN LIGNE", Color("#D9F1FB"), UI.BLUE_DK, 15))
	_home.add_child(subc)

	# Carte centrale : formulaire dans un panneau blanc à ombre portée.
	_home_card = UI.panel()
	var csb := _home_card.get_theme_stylebox("panel") as StyleBoxFlat
	csb.content_margin_left = 26
	csb.content_margin_right = 26
	csb.content_margin_top = 24
	csb.content_margin_bottom = 24
	_home.add_child(_home_card)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 14)
	_home_card.add_child(cv)

	_name_edit = _line_edit("Ton pseudo", 0)
	cv.add_child(_name_edit)

	var create_btn := UI.button("Créer une table", "primary")
	create_btn.pressed.connect(func() -> void: _connect("create"))
	cv.add_child(create_btn)

	var quick_btn := UI.button("Partie rapide", "btn")
	quick_btn.pressed.connect(func() -> void: _connect("quick"))
	cv.add_child(quick_btn)

	# Séparateur « — ou — ».
	var seprow := HBoxContainer.new()
	seprow.alignment = BoxContainer.ALIGNMENT_CENTER
	seprow.add_theme_constant_override("separation", 12)
	cv.add_child(seprow)
	for i in 2:
		var ln := HSeparator.new()
		ln.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ln.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ln.add_theme_stylebox_override("separator", UI.sb(UI.EDGE_DK, UI.EDGE_DK, 1, 0))
		seprow.add_child(ln)
		if i == 0:
			seprow.add_child(UI.label("ou", 15, UI.DIM, 800))

	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 12)
	cv.add_child(join_row)

	_code_edit = _line_edit("CODE", 6)
	_code_edit.custom_minimum_size.x = 170
	join_row.add_child(_code_edit)

	var join_btn := UI.button("Rejoindre", "btn")
	join_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_btn.pressed.connect(func() -> void:
		_pending_code = _code_edit.text.strip_edges().to_upper()
		_connect("join"))
	join_row.add_child(join_btn)

	_status = UI.label("", 18, UI.RED_DK)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_home.add_child(_status)

	# Switch thème clair/sombre en bas de la carte.
	var theme_row := HBoxContainer.new()
	theme_row.add_theme_constant_override("separation", 10)
	cv.add_child(theme_row)
	var tl := UI.label("Mode sombre", 18, UI.INK, 700)
	tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	theme_row.add_child(tl)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	theme_row.add_child(spacer)
	var sw := UI.ThemeSwitch.new(UI.dark)
	sw.toggled.connect(func(on: bool) -> void:
		UI.set_dark(on)
		_rebuild())
	theme_row.add_child(sw)

	UI.pop_in(_home_card)

	# --- Salle d'attente : carte blanche avec le code en grand ---
	_lobby = VBoxContainer.new()
	_lobby.visible = false
	_lobby.custom_minimum_size.x = 500
	_lobby.add_theme_constant_override("separation", 18)
	center.add_child(_lobby)

	_lobby_card = UI.panel()
	var lsb := _lobby_card.get_theme_stylebox("panel") as StyleBoxFlat
	lsb.content_margin_left = 26
	lsb.content_margin_right = 26
	lsb.content_margin_top = 24
	lsb.content_margin_bottom = 24
	_lobby.add_child(_lobby_card)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 12)
	_lobby_card.add_child(lv)

	_room_lbl = UI.label("", 17, UI.DIM, 800)
	_room_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv.add_child(_room_lbl)

	_code_lbl = UI.label("", 46, UI.BLUE, 700, true)
	_code_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv.add_child(_code_lbl)

	var invite := UI.label("Partage ce code pour inviter des amis", 14, UI.DIM, 700)
	invite.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv.add_child(invite)

	_players_box = VBoxContainer.new()
	_players_box.add_theme_constant_override("separation", 8)
	lv.add_child(_players_box)

	var bot_btn := UI.button("Ajouter un bot", "btn")
	bot_btn.pressed.connect(func() -> void: Net.add_bot())
	lv.add_child(bot_btn)

	_launch_btn = UI.button("Lancer la partie", "primary")
	_launch_btn.pressed.connect(func() -> void: Net.launch())
	lv.add_child(_launch_btn)

	var leave_btn := UI.button("Quitter la salle", "btn")
	leave_btn.custom_minimum_size.y = 44
	leave_btn.add_theme_font_size_override("font_size", 18)
	leave_btn.pressed.connect(func() -> void:
		Net.leave()
		_lobby.visible = false
		_home.visible = true)
	lv.add_child(leave_btn)

# Champ de saisie Wii : blanc, bord clair, focus bleu + halo.
func _line_edit(placeholder: String, maxlen: int) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.max_length = maxlen
	e.custom_minimum_size.y = 56
	e.add_theme_font_override("font", UI.font_w(700))
	e.add_theme_font_size_override("font_size", 26)
	e.add_theme_color_override("font_color", UI.INK)
	e.add_theme_color_override("font_placeholder_color", UI.DIM)
	e.add_theme_stylebox_override("normal", UI.sb(UI.PANEL, UI.EDGE, 18, 2))
	e.add_theme_stylebox_override("focus", UI.sb(UI.PANEL, UI.BLUE, 18, 2))
	return e

# Reconstruit l'écran après bascule de thème (les styles sont cuits à la
# construction — on recrée tout en préservant les saisies et le lobby).
func _rebuild() -> void:
	var typed := _name_edit.text
	var code := _code_edit.text
	for c in get_children():
		c.queue_free()
	_build_ui()
	_name_edit.text = typed
	_code_edit.text = code
	if Net.view.get("state") == "lobby":
		_on_view(Net.view)

func _set_status(t: String, col := UI.RED_DK) -> void:
	_status.text = t
	_status.add_theme_color_override("font_color", col)

func _connect(pending: String) -> void:
	_pending = pending
	_set_status("connexion…", UI.DIM)
	Net.connect_server()
	if Net.is_open():
		Net.hello(_name_edit.text.strip_edges())

func _on_view(v: Dictionary) -> void:
	if v.get("state") == "playing":
		_home.visible = false
		_lobby.visible = false
		get_tree().call_deferred("change_scene_to_file", "res://main.tscn")
		return
	if v.get("state") != "lobby":
		return
	_home.visible = false
	_lobby.visible = true
	UI.pop_in(_lobby_card)
	_room_lbl.text = v.get("name", "Table")
	_code_lbl.text = v.get("code", "?")
	for c in _players_box.get_children():
		c.queue_free()
	var idx := 0
	for p in UI.arr(v.get("players")):
		var txt: String = p.get("name", "?")
		if p.get("bot", false):
			txt += "  (bot)"
		if not p.get("connected", true):
			txt += "  (déco)"
		var cc := CenterContainer.new()
		var chip := UI.player_chip(txt, int(p.get("seat", _players_box.get_child_count())), 20)
		cc.add_child(chip)
		_players_box.add_child(cc)
		UI.pop_in(chip, idx * 0.08)
		idx += 1
	_launch_btn.visible = v.get("host", "") == Net.token

func _on_notice(d: Dictionary) -> void:
	match d.get("kind", ""):
		"kicked":
			_set_status("Tu as été expulsé de la table")
			_lobby.visible = false
			_home.visible = true
		"room_closed":
			_set_status("La salle a été fermée")
			_lobby.visible = false
			_home.visible = true
		"chat":
			_set_status("%s : %s" % [d.get("from", "?"), d.get("text", "")], UI.BLUE_DK)
