# menu.gd — écran d'accueil + salle d'attente.
# Connexion (pseudo+jeton), création/join par code, lobby joueurs, lancement.
extends Control

var _name_edit: LineEdit
var _code_edit: LineEdit
var _status: Label
var _home: VBoxContainer
var _lobby: VBoxContainer
var _room_lbl: Label
var _players_box: VBoxContainer
var _launch_btn: Button
var _pending := ""
var _pending_code := ""
static var _e2e_started := false

func _ready() -> void:
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
	Net.net_error.connect(func(c: String, m: String) -> void: _status.text = "[%s] %s" % [c, m])
	Net.connection_closed.connect(func() -> void: _status.text = "connexion perdue — reconnexion…")
	Net.notice_msg.connect(_on_notice)
	if _name_edit.text == "":
		_name_edit.text = Net.last_name
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

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	_home = VBoxContainer.new()
	_home.custom_minimum_size.x = 480
	_home.add_theme_constant_override("separation", 18)
	center.add_child(_home)

	var title := UI.label("DOODO", 64, UI.BLUE, 700, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_home.add_child(title)

	var sub := UI.label("PERUDO EN LIGNE", 16, UI.DIM, 800)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_home.add_child(sub)

	_name_edit = _line_edit("Ton pseudo", 0)
	_home.add_child(_name_edit)

	var create_btn := UI.button("Créer une table", "primary")
	create_btn.pressed.connect(func() -> void: _connect("create"))
	_home.add_child(create_btn)

	var quick_btn := UI.button("Partie rapide", "btn")
	quick_btn.pressed.connect(func() -> void: _connect("quick"))
	_home.add_child(quick_btn)

	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 12)
	_home.add_child(join_row)

	_code_edit = _line_edit("CODE", 6)
	_code_edit.custom_minimum_size.x = 180
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

	# --- Panneau salle d'attente ---
	_lobby = VBoxContainer.new()
	_lobby.visible = false
	_lobby.custom_minimum_size.x = 480
	_lobby.add_theme_constant_override("separation", 16)
	center.add_child(_lobby)

	_room_lbl = UI.label("", 30, UI.INK, 700)
	_room_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lobby.add_child(_room_lbl)

	_players_box = VBoxContainer.new()
	_players_box.add_theme_constant_override("separation", 8)
	_lobby.add_child(_players_box)

	var bot_btn := UI.button("Ajouter un bot", "btn")
	bot_btn.pressed.connect(func() -> void: Net.add_bot())
	_lobby.add_child(bot_btn)

	_launch_btn = UI.button("Lancer la partie", "primary")
	_launch_btn.pressed.connect(func() -> void: Net.launch())
	_lobby.add_child(_launch_btn)

	var leave_btn := UI.button("Quitter la salle", "btn")
	leave_btn.pressed.connect(func() -> void:
		Net.leave()
		_lobby.visible = false
		_home.visible = true)
	_lobby.add_child(leave_btn)

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

func _connect(pending: String) -> void:
	_pending = pending
	_status.text = "connexion…"
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
	_room_lbl.text = "%s — code : %s" % [v.get("name", "Table"), v.get("code", "?")]
	for c in _players_box.get_children():
		c.queue_free()
	for p in UI.arr(v.get("players")):
		var txt: String = p.get("name", "?")
		if p.get("bot", false):
			txt += "  (bot)"
		if not p.get("connected", true):
			txt += "  (déco)"
		_players_box.add_child(UI.player_chip(txt, int(p.get("seat", _players_box.get_child_count())), 20))
	_launch_btn.visible = v.get("host", "") == Net.token

func _on_notice(d: Dictionary) -> void:
	match d.get("kind", ""):
		"kicked":
			_status.text = "Tu as été expulsé de la table"
			_lobby.visible = false
			_home.visible = true
		"room_closed":
			_status.text = "La salle a été fermée"
			_lobby.visible = false
			_home.visible = true
		"chat":
			_status.add_theme_color_override("font_color", UI.BLUE_DK)
			_status.text = "%s : %s" % [d.get("from", "?"), d.get("text", "")]
