# menu.gd — écran d'accueil + salle d'attente.
# Connexion (pseudo+jeton), création/join par code, lobby joueurs, lancement.
extends Control

var _name_edit: LineEdit
var _code_edit: LineEdit
var _status: Label
var _home: VBoxContainer
var _lobby: VBoxContainer
var _room_lbl: Label
var _players_lbl: Label
var _launch_btn: Button
var _pending := ""
var _pending_code := ""

func _ready() -> void:
	_build_ui()
	# Mode test e2e : --e2e crée une salle + bot et lance la partie automatiquement.
	if OS.get_cmdline_user_args().has("--e2e"):
		_name_edit.text = "e2e-tester"
		_connect("create")
		await get_tree().create_timer(1.5).timeout
		Net.add_bot()
		await get_tree().create_timer(1.0).timeout
		Net.launch()
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

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.1, 0.14)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	_home = VBoxContainer.new()
	_home.custom_minimum_size.x = 480
	_home.add_theme_constant_override("separation", 18)
	center.add_child(_home)

	var title := Label.new()
	title.text = "D O O D O"
	title.add_theme_font_size_override("font_size", 72)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_home.add_child(title)

	var sub := Label.new()
	sub.text = "Perudo en ligne"
	sub.add_theme_font_size_override("font_size", 24)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.modulate = Color(1, 1, 1, 0.6)
	_home.add_child(sub)

	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Ton pseudo"
	_name_edit.custom_minimum_size.y = 64
	_name_edit.add_theme_font_size_override("font_size", 28)
	_home.add_child(_name_edit)

	var create_btn := Button.new()
	create_btn.text = "Créer une table"
	create_btn.custom_minimum_size.y = 72
	create_btn.add_theme_font_size_override("font_size", 28)
	create_btn.pressed.connect(func() -> void: _connect("create"))
	_home.add_child(create_btn)

	var quick_btn := Button.new()
	quick_btn.text = "Partie rapide"
	quick_btn.custom_minimum_size.y = 72
	quick_btn.add_theme_font_size_override("font_size", 28)
	quick_btn.pressed.connect(func() -> void: _connect("quick"))
	_home.add_child(quick_btn)

	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 12)
	_home.add_child(join_row)

	_code_edit = LineEdit.new()
	_code_edit.placeholder_text = "CODE"
	_code_edit.max_length = 6
	_code_edit.custom_minimum_size = Vector2(180, 64)
	_code_edit.add_theme_font_size_override("font_size", 28)
	join_row.add_child(_code_edit)

	var join_btn := Button.new()
	join_btn.text = "Rejoindre"
	join_btn.custom_minimum_size.y = 64
	join_btn.add_theme_font_size_override("font_size", 28)
	join_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_btn.pressed.connect(func() -> void:
		_pending_code = _code_edit.text.strip_edges().to_upper()
		_connect("join"))
	join_row.add_child(join_btn)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 20)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.modulate = Color(1, 0.5, 0.5)
	_home.add_child(_status)

	# --- Panneau salle d'attente ---
	_lobby = VBoxContainer.new()
	_lobby.visible = false
	_lobby.custom_minimum_size.x = 480
	_lobby.add_theme_constant_override("separation", 16)
	center.add_child(_lobby)

	_room_lbl = Label.new()
	_room_lbl.add_theme_font_size_override("font_size", 32)
	_room_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lobby.add_child(_room_lbl)

	_players_lbl = Label.new()
	_players_lbl.add_theme_font_size_override("font_size", 24)
	_players_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lobby.add_child(_players_lbl)

	var bot_btn := Button.new()
	bot_btn.text = "Ajouter un bot"
	bot_btn.custom_minimum_size.y = 60
	bot_btn.add_theme_font_size_override("font_size", 24)
	bot_btn.pressed.connect(func() -> void: Net.add_bot())
	_lobby.add_child(bot_btn)

	_launch_btn = Button.new()
	_launch_btn.text = "Lancer la partie"
	_launch_btn.custom_minimum_size.y = 72
	_launch_btn.add_theme_font_size_override("font_size", 28)
	_launch_btn.pressed.connect(func() -> void: Net.launch())
	_lobby.add_child(_launch_btn)

	var leave_btn := Button.new()
	leave_btn.text = "Quitter la salle"
	leave_btn.custom_minimum_size.y = 56
	leave_btn.pressed.connect(func() -> void:
		Net.leave()
		_lobby.visible = false
		_home.visible = true)
	_lobby.add_child(leave_btn)

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
	var lines := PackedStringArray()
	for p in v.get("players", []):
		var line: String = p.get("name", "?")
		if p.get("bot", false):
			line += "  (bot)"
		if not p.get("connected", true):
			line += "  (déco)"
		lines.append(line)
	_players_lbl.text = "\n".join(lines)
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
			_status.modulate = Color(0.6, 0.9, 1)
			_status.text = "%s : %s" % [d.get("from", "?"), d.get("text", "")]
