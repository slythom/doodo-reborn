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
var _scene_opt: OptionButton
var _leave_btn: Button
var _bot_btn: Button
var _bots_box: VBoxContainer
var _chat_log: VBoxContainer
var _chat_scroll: ScrollContainer
var _chat_edit: LineEdit
var _opt_dice: OptionButton
var _opt_maxp: OptionButton
var _opt_timer: OptionButton
var _opt_sw := {} # clé d'option booléenne -> UI.ThemeSwitch
var _rule_sw := {} # id de règle perso -> UI.ThemeSwitch
var _cursor: UI.TriCursor  # marqueur « ▸ » suivant le focus (menu arcade)
var _cur_t: Tween

# Catalogue client des règles perso : [libellé, id, infobulle] (§1.5).
const RULES := [
	["Dé public", "de_public", "Un dé de chaque joueur est révélé à tous en début de manche"],
	["Double Paco", "double_paco", "Les pacos comptent double au décompte (requiert Paco joker)"],
	["Salsa", "salsa", "Enchérir et douter hors de son tour"],
	["Calzone", "calzone", "Calza réussi : vole un dé à l'adversaire de ton choix (requiert Calza)"],
	["Pacobye", "pacobye", "Tirage 100 % pacos avec 4 ou 5 dés : élimination immédiate"],
]
var _pending := ""
var _pending_code := ""
# Lobby public (§3.2) : deux onglets, liste rafraîchie par polling.
var _browse: VBoxContainer
var _browse_card: PanelContainer
var _browse_rows: VBoxContainer
var _browse_status: Label
var _browse_tabs := {}
var _browse_tab := "lobby" # "lobby" (en attente) | "playing" (en cours)
var _rooms: Array = []
static var _e2e_started := false

func _ready() -> void:
	UI.load_theme()
	UI.load_audio()
	UI.load_crt()
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
			"browse": Net.list_rooms()
		_pending = "")
	Net.room_state.connect(_on_view)
	Net.net_error.connect(func(c: String, m: String) -> void:
		_set_status("[%s] %s" % [c, m])
		if _browse.visible:
			_browse_status.text = m
			_browse_status.add_theme_color_override("font_color", UI.RED_DK)
		# Refus serveur (ex. set_options) : pas de room_state — on resync
		# les contrôles sur l'état canonique local pour rétracter le choix.
		if _lobby.visible:
			_on_view(Net.view))
	Net.connection_closed.connect(func() -> void: _set_status("connexion perdue — reconnexion…"))
	Net.notice_msg.connect(_on_notice)
	Net.room_list.connect(_on_room_list)
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
	# --e2e-browse : ouvre le lobby public et rejoint la première table listée.
	# Garde : le menu peut se recharger (retour lobby) — ne pas relancer.
	if OS.get_cmdline_user_args().has("--e2e-browse") and not _e2e_started:
		_e2e_started = true
		_e2e_browse()
	elif OS.get_cmdline_user_args().has("--e2e") and not _e2e_started:
		_e2e_started = true
		_e2e()

func _e2e() -> void:
	_name_edit.text = "e2e-tester"
	_connect("create")
	await get_tree().create_timer(1.5).timeout
	var scene := "cimetiere"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--e2e-scene="):
			scene = a.get_slice("=", 1)
	Net.set_scene(scene)
	# Exerce aussi le chemin options : timer 15 s posé en salle d'attente,
	# + mode dieu quand --e2e-god est passé (exerce la barre de tirage).
	var eo: Dictionary = Net.view.get("options", {}).duplicate(true)
	eo["timer_seconds"] = 15
	if OS.get_cmdline_user_args().has("--e2e-god"):
		eo["god_mode"] = true
	if OS.get_cmdline_user_args().has("--e2e-pub"):
		eo["public"] = true
	Net.set_options(eo)
	Net.add_bot()
	await get_tree().create_timer(1.0).timeout
	Net.launch()

# e2e : ouvre le lobby public puis rejoint la première table listée —
# exerce list_rooms + join (joueur ou spectateur selon le timing).
func _e2e_browse() -> void:
	_name_edit.text = "e2e-watcher"
	_open_browse()
	await get_tree().create_timer(2.5).timeout
	for r in _rooms:
		_pending_code = String(r.get("code", ""))
		_connect("join")
		return

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

	# Attract mode (#38) : dés qui flottent en fond, derrière la carte.
	var attract := Control.new()
	attract.set_anchors_preset(Control.PRESET_FULL_RECT)
	attract.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(attract)
	for i in 7:
		var d := UI.DieIcon.new(randi_range(1, 6), 46)
		d.modulate = Color(1, 1, 1, 0.4)
		d.pivot_offset = Vector2(23, 23)
		d.position = Vector2(randf_range(0, 640), randf_range(0, 1200))
		d.rotation_degrees = randf_range(0, 360)
		attract.add_child(d)
		var bob := d.create_tween().set_loops()
		bob.tween_property(d, "position:y", d.position.y - 30, randf_range(1.6, 3.0)) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		bob.tween_property(d, "position:y", d.position.y + 30, randf_range(1.6, 3.0)) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		var spin := d.create_tween().set_loops()
		spin.tween_property(d, "rotation_degrees", d.rotation_degrees + 360.0, randf_range(9.0, 16.0))

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	_home = VBoxContainer.new()
	_home.custom_minimum_size.x = _card_w()
	_home.add_theme_constant_override("separation", 20)
	center.add_child(_home)

	# Logo : DOODO en pixel font, ombre dure (borne d'arcade), encadré de
	# deux dés pixel inclinés.
	var logo := HBoxContainer.new()
	logo.alignment = BoxContainer.ALIGNMENT_CENTER
	logo.add_theme_constant_override("separation", 20)
	_home.add_child(logo)
	var d1 := UI.DieIcon.new(3, 48)
	d1.rotation_degrees = -9
	logo.add_child(d1)
	var title := UI.pix_label("DOODO", 64, UI.BLUE)
	title.add_theme_color_override("font_shadow_color", UI.BLUE_DK)
	title.add_theme_constant_override("shadow_offset_x", 4)
	title.add_theme_constant_override("shadow_offset_y", 5)
	title.add_theme_constant_override("shadow_outline_size", 0)
	title.resized.connect(func() -> void: title.pivot_offset = title.size / 2.0)
	logo.add_child(title)
	var d2 := UI.DieIcon.new(5, 48)
	d2.rotation_degrees = 9
	logo.add_child(d2)
	# Le titre flotte doucement (wobble infini, écran d'accueil Wii).
	# Bindé à title : le tween meurt avec le nœud (rebuild du thème).
	var wob := title.create_tween().set_loops()
	wob.tween_property(title, "scale", Vector2(1.04, 1.04), 1.4).set_trans(Tween.TRANS_SINE)
	wob.parallel().tween_property(title, "rotation_degrees", -1.2, 1.4).set_trans(Tween.TRANS_SINE)
	wob.tween_property(title, "scale", Vector2.ONE, 1.4).set_trans(Tween.TRANS_SINE)
	wob.parallel().tween_property(title, "rotation_degrees", 0.0, 1.4).set_trans(Tween.TRANS_SINE)
	# Flicker néon (#38) : micro-coupures d'alpha toutes les ~3 s.
	var fl := title.create_tween().set_loops()
	fl.tween_interval(2.7)
	fl.tween_property(title, "modulate:a", 0.45, 0.05)
	fl.tween_property(title, "modulate:a", 1.0, 0.08)
	fl.tween_property(title, "modulate:a", 0.7, 0.04)
	fl.tween_property(title, "modulate:a", 1.0, 0.07)

	var subc := CenterContainer.new()
	var tag := UI.pill("PERUDO EN LIGNE", Color("#D9F1FB"), UI.BLUE_DK, 13)
	tag.add_theme_font_override("font", UI.font_pix())
	subc.add_child(tag)
	_home.add_child(subc)

	# Carte centrale : formulaire dans un panneau blanc à ombre portée.
	_home_card = UI.panel()
	var csb := _home_card.get_theme_stylebox("panel") as StyleBoxFlat
	csb.content_margin_left = 30
	csb.content_margin_right = 30
	csb.content_margin_top = 28
	csb.content_margin_bottom = 28
	_home.add_child(_home_card)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 14)
	_home_card.add_child(cv)

	_name_edit = _line_edit("Ton pseudo", 16)
	_name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	cv.add_child(_name_edit)

	var create_btn := UI.button("CRÉER UNE TABLE", "primary", true)
	create_btn.pressed.connect(func() -> void: _connect("create"))
	cv.add_child(create_btn)

	var quick_btn := UI.button("PARTIE RAPIDE", "btn", true)
	quick_btn.pressed.connect(func() -> void: _connect("quick"))
	cv.add_child(quick_btn)

	var browse_btn := UI.button("VOIR LE LOBBY", "btn", true)
	browse_btn.pressed.connect(_open_browse)
	cv.add_child(browse_btn)

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
			seprow.add_child(UI.label("ou", 17, UI.DIM, 800))

	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 12)
	cv.add_child(join_row)

	_code_edit = _line_edit("CODE", 6)
	_code_edit.custom_minimum_size.x = 200
	_code_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Le code de salle en pixel font : lettres ASCII, rendu « écran de borne ».
	_code_edit.add_theme_font_override("font", UI.font_pix())
	_code_edit.add_theme_font_size_override("font_size", 24)
	join_row.add_child(_code_edit)

	var join_btn := UI.button("REJOINDRE", "btn", true)
	join_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_btn.pressed.connect(func() -> void:
		_pending_code = _code_edit.text.strip_edges().to_upper()
		_connect("join"))
	join_row.add_child(join_btn)

	# Accroche clignotante façon borne (« INSERT COIN » détourné).
	var insc := CenterContainer.new()
	var ins := UI.pix_label("- INSERT DÉ -", 16, UI.AMBER)
	insc.add_child(ins)
	_home.add_child(insc)
	UI.blink(ins)

	_status = UI.label("", 20, UI.RED_DK)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_home.add_child(_status)

	# Version visible en bas de l'écran d'accueil : permet de distinguer
	# les builds beta installés à la main (sideload) d'un coup d'œil.
	var vc := CenterContainer.new()
	vc.add_child(UI.label("v" + ProjectSettings.get_setting("application/config/version", "?"), 15, UI.DIM))
	_home.add_child(vc)

	# Switch thème clair/sombre en bas de la carte.
	var theme_row := HBoxContainer.new()
	theme_row.add_theme_constant_override("separation", 10)
	cv.add_child(theme_row)
	var tl := UI.label("Mode sombre", 20, UI.INK, 700)
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

	# Effet CRT : scanlines + vignette rétro (#36), persisté comme le thème.
	var crt_row := HBoxContainer.new()
	crt_row.add_theme_constant_override("separation", 10)
	cv.add_child(crt_row)
	var cl := UI.label("Effet CRT", 20, UI.INK, 700)
	cl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	crt_row.add_child(cl)
	var crt_spacer := Control.new()
	crt_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	crt_row.add_child(crt_spacer)
	var crt_sw := UI.ThemeSwitch.new(UI.crt, false, true) # affiche ON/OFF, pas l'icône lune
	crt_sw.toggled.connect(func(on: bool) -> void:
		UI.set_crt(on)
		_rebuild())
	crt_row.add_child(crt_sw)

	# Audio : volume + mute des SFX, persistés (§4.3).
	var audio_row := HBoxContainer.new()
	audio_row.add_theme_constant_override("separation", 10)
	cv.add_child(audio_row)
	var al := UI.label("Son", 20, UI.INK, 700)
	al.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	audio_row.add_child(al)
	var audio_spacer := Control.new()
	audio_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	audio_row.add_child(audio_spacer)
	var vol_slider := HSlider.new()
	vol_slider.min_value = 0
	vol_slider.max_value = 100
	vol_slider.step = 5
	vol_slider.value = UI.sfx_volume * 100
	vol_slider.custom_minimum_size = Vector2(110, 40)
	vol_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	audio_row.add_child(vol_slider)
	var audio_sw := UI.ThemeSwitch.new(not UI.sfx_muted, false, true)
	audio_row.add_child(audio_sw)
	var apply_audio := func() -> void:
		UI.set_audio(not audio_sw.on, vol_slider.value / 100.0)
	audio_sw.toggled.connect(func(_on: bool) -> void: apply_audio.call())
	vol_slider.drag_ended.connect(func(_changed: bool) -> void: apply_audio.call())

	# Serveur : URL du backend (beta — tunnel/prod). Vide = localhost.
	var srv_row := HBoxContainer.new()
	srv_row.add_theme_constant_override("separation", 10)
	cv.add_child(srv_row)
	var srv_lbl := UI.label("Serveur", 17, UI.DIM, 700)
	srv_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	srv_row.add_child(srv_lbl)
	var srv_edit := _line_edit(Net.DEFAULT_URL, 80)
	srv_edit.add_theme_font_size_override("font_size", 20)
	srv_edit.custom_minimum_size.y = 56
	srv_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	srv_edit.text = Net.server
	var apply_srv := func() -> void:
		Net.set_server(srv_edit.text)
		# Réaffiche la valeur canonique (ex. « hote.fr » saisi tel quel).
		srv_edit.text = Net.server
	srv_edit.text_submitted.connect(func(_t: String) -> void: apply_srv.call())
	srv_edit.focus_exited.connect(func() -> void: apply_srv.call())
	srv_row.add_child(srv_edit)

	UI.pop_in(_home_card)

	# --- Salle d'attente : carte blanche avec le code en grand ---
	# Ancrée en haut, PAS centrée : quand la liste des bots grandit, la carte
	# pousse vers le bas — « Ajouter un bot » reste fixe sous le doigt.
	var lobby_wrap := HBoxContainer.new()
	lobby_wrap.set_anchors_preset(Control.PRESET_TOP_WIDE)
	lobby_wrap.alignment = BoxContainer.ALIGNMENT_CENTER
	lobby_wrap.offset_top = 120
	add_child(lobby_wrap)

	_lobby = VBoxContainer.new()
	_lobby.visible = false
	_lobby.custom_minimum_size.x = _card_w()
	_lobby.add_theme_constant_override("separation", 18)
	lobby_wrap.add_child(_lobby)

	_lobby_card = UI.panel()
	var lsb := _lobby_card.get_theme_stylebox("panel") as StyleBoxFlat
	lsb.content_margin_left = 30
	lsb.content_margin_right = 30
	lsb.content_margin_top = 28
	lsb.content_margin_bottom = 28
	_lobby.add_child(_lobby_card)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 12)
	_lobby_card.add_child(lv)

	_room_lbl = UI.label("", 17, UI.DIM, 800)
	_room_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv.add_child(_room_lbl)

	_code_lbl = UI.pix_label("", 34, UI.BLUE)
	_code_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv.add_child(_code_lbl)

	var invite := UI.label("Partage ce code pour inviter des amis", 14, UI.DIM, 700)
	invite.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv.add_child(invite)

	_players_box = VBoxContainer.new()
	_players_box.add_theme_constant_override("separation", 8)
	lv.add_child(_players_box)

	# Décor 3D de la table : choisi par le créateur en salle d'attente,
	# figé au lancement (specs §1.3/§4.1). Id stocké en metadata d'item.
	var scene_row := HBoxContainer.new()
	scene_row.add_theme_constant_override("separation", 10)
	lv.add_child(scene_row)
	var sl := UI.label("Décor", 18, UI.INK, 700)
	sl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	scene_row.add_child(sl)
	_scene_opt = UI.option_button()
	var opt_popup := _scene_opt.get_popup()
	for s in [["salon", "Salon"], ["cimetiere", "Cimetière — squelettes"], ["foret", "Forêt — aventuriers"]]:
		_scene_opt.add_item(s[1])
		var i := _scene_opt.item_count - 1
		_scene_opt.set_item_metadata(i, s[0])
		# Pastille radio : la sélection reste repérable à la réouverture,
		# pas seulement par la couleur du bouton.
		opt_popup.set_item_as_radio_checkable(i, true)
		opt_popup.set_item_icon_modulate(i, UI.INK)
	_scene_opt.item_selected.connect(func(i: int) -> void:
		Net.set_scene(String(_scene_opt.get_item_metadata(i))))
	scene_row.add_child(_scene_opt)

	# Options de la table (§1.3/§4.1) : modifiables par l'hôte jusqu'au
	# lancement, lecture seule pour les invités. Chaque changement renvoie
	# l'intégralité des options — le serveur diffuse l'état canonique.
	var opts_hdr := UI.pix_label("OPTIONS", 10, UI.DIM)
	opts_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv.add_child(opts_hdr)
	_opt_dice = _opt_row(lv, "Dés de départ", [["3", 3], ["4", 4], ["5", 5]])
	_opt_dice.item_selected.connect(func(i: int) -> void:
		_patch_opt("dice_per_player", int(_opt_dice.get_item_metadata(i))))
	_opt_maxp = _opt_row(lv, "Joueurs max", [["2", 2], ["3", 3], ["4", 4], ["5", 5], ["6", 6]])
	_opt_maxp.item_selected.connect(func(i: int) -> void:
		_patch_opt("max_players", int(_opt_maxp.get_item_metadata(i))))
	_opt_timer = _opt_row(lv, "Timer", [["15 s", 15], ["30 s", 30], ["60 s", 60], ["Aucun", 0]])
	_opt_timer.item_selected.connect(func(i: int) -> void:
		_patch_opt("timer_seconds", int(_opt_timer.get_item_metadata(i))))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	lv.add_child(grid)
	for t in [["Paco joker", "paco_joker"], ["Calza", "calza_enabled"],
			["Palifico", "palifico_enabled"], ["Bot si déco", "bot_replacement"],
			["Spectateurs", "spectators"], ["Mode dieu", "god_mode"],
			["Publique", "public"]]:
		var key: String = t[1]
		var tgl := _toggle_cell(grid, t[0])
		tgl.toggled.connect(func(on: bool) -> void: _patch_opt(key, on))
		_opt_sw[key] = tgl

	# Règles perso (§1.5, v0.8) : ids dans options.game.rules. Les
	# dépendances (Double Paco → Paco joker, Calzone → Calza) sont gérées
	# par _patch_opt/_patch_rule en un seul set_options atomique.
	var rules_hdr := UI.pix_label("REGLES PERSO", 10, UI.DIM)
	rules_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv.add_child(rules_hdr)
	var rgrid := GridContainer.new()
	rgrid.columns = 2
	rgrid.add_theme_constant_override("h_separation", 16)
	lv.add_child(rgrid)
	for t in RULES:
		var id: String = t[1]
		var tgl := _toggle_cell(rgrid, t[0], t[2])
		tgl.tooltip_text = t[2]
		tgl.toggled.connect(func(on: bool) -> void: _patch_rule(id, on))
		_rule_sw[id] = tgl

	_bot_btn = UI.button("+ BOT", "btn", true)
	_bot_btn.pressed.connect(func() -> void: Net.add_bot())
	lv.add_child(_bot_btn)

	# Liste des bots ajoutés : sous le bouton qui les crée (ticket #4).
	_bots_box = VBoxContainer.new()
	_bots_box.add_theme_constant_override("separation", 8)
	lv.add_child(_bots_box)

	# Chat de salle d'attente : texte libre tant que la partie n'est pas
	# lancée (§4.3) — en jeu, seuls les messages prédéfinis passent.
	var chat_hdr := UI.pix_label("CHAT", 10, UI.DIM)
	chat_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv.add_child(chat_hdr)
	_chat_scroll = ScrollContainer.new()
	_chat_scroll.custom_minimum_size.y = 100
	_chat_scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	lv.add_child(_chat_scroll)
	_chat_log = VBoxContainer.new()
	_chat_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_log.add_theme_constant_override("separation", 4)
	_chat_scroll.add_child(_chat_log)
	var chat_row := HBoxContainer.new()
	chat_row.add_theme_constant_override("separation", 8)
	lv.add_child(chat_row)
	_chat_edit = _line_edit("Message…", 200)
	_chat_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_row.add_child(_chat_edit)
	var chat_send := UI.button("OK", "btn", true)
	chat_row.add_child(chat_send)
	var send_chat := func() -> void:
		var t := _chat_edit.text.strip_edges()
		if t != "":
			Net.chat(t)
			_chat_edit.clear()
	chat_send.pressed.connect(send_chat)
	_chat_edit.text_submitted.connect(func(_t: String) -> void: send_chat.call())

	_launch_btn = UI.button("LANCER LA PARTIE", "primary", true)
	_launch_btn.pressed.connect(func() -> void: Net.launch())
	lv.add_child(_launch_btn)

	_leave_btn = UI.button("QUITTER", "btn", true)
	_leave_btn.custom_minimum_size.y = 44
	_leave_btn.add_theme_font_size_override("font_size", 18)
	_leave_btn.pressed.connect(func() -> void:
		Net.leave()
		_lobby.visible = false
		_home.visible = true)
	lv.add_child(_leave_btn)

	# --- Lobby public (§3.2) : deux onglets + liste des tables publiques ---
	var browse_wrap := HBoxContainer.new()
	browse_wrap.set_anchors_preset(Control.PRESET_TOP_WIDE)
	browse_wrap.alignment = BoxContainer.ALIGNMENT_CENTER
	browse_wrap.offset_top = 120
	add_child(browse_wrap)

	_browse = VBoxContainer.new()
	_browse.visible = false
	_browse.custom_minimum_size.x = _card_w()
	_browse.add_theme_constant_override("separation", 14)
	browse_wrap.add_child(_browse)

	_browse_card = UI.panel()
	var bsb := _browse_card.get_theme_stylebox("panel") as StyleBoxFlat
	bsb.content_margin_left = 26
	bsb.content_margin_right = 26
	bsb.content_margin_top = 24
	bsb.content_margin_bottom = 24
	_browse.add_child(_browse_card)
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 12)
	_browse_card.add_child(bv)

	var btitle := UI.pix_label("TABLES PUBLIQUES", 16, UI.BLUE)
	btitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bv.add_child(btitle)

	# Onglets « En attente » / « En cours » (§3.2).
	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 8)
	bv.add_child(tabs)
	for t in [["lobby", "En attente"], ["playing", "En cours"]]:
		var tb := UI.button(t[1].to_upper(), "btn", true)
		tb.custom_minimum_size = Vector2(0, 46)
		tb.toggle_mode = true
		var tid: String = t[0]
		tb.pressed.connect(func() -> void: _browse_select(tid))
		_browse_tabs[tid] = tb
		tabs.add_child(tb)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 380)
	bv.add_child(scroll)
	_browse_rows = VBoxContainer.new()
	_browse_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_browse_rows.add_theme_constant_override("separation", 8)
	scroll.add_child(_browse_rows)

	_browse_status = UI.label("", 16, UI.DIM)
	_browse_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bv.add_child(_browse_status)

	var back_btn := UI.button("RETOUR", "btn", true)
	back_btn.pressed.connect(func() -> void:
		_browse.visible = false
		_home.visible = true)
	bv.add_child(back_btn)

	# --- Finitions borne d'arcade : curseur de sélection + scanlines ---
	_cursor = UI.TriCursor.new()
	_cursor.visible = false
	add_child(_cursor)
	if not get_viewport().gui_focus_changed.is_connected(_move_cursor):
		get_viewport().gui_focus_changed.connect(_move_cursor)
	UI.apply_crt(self) # balayage CRT + vignette — au-dessus, désactivable (#36)

# Ligne « libellé + liste déroulante » des options de table — valeurs en
# metadata d'item, comme le sélecteur de décor.
func _opt_row(parent: Control, label_text: String, items: Array) -> OptionButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var l := UI.label(label_text, 18, UI.INK, 700)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var o := UI.option_button()
	o.custom_minimum_size.x = 160
	var pop := o.get_popup()
	for it in items:
		o.add_item(it[0])
		var i := o.item_count - 1
		o.set_item_metadata(i, it[1])
		pop.set_item_as_radio_checkable(i, true)
		pop.set_item_icon_modulate(i, UI.INK)
	row.add_child(o)
	return o

# Cellule « libellé [+ badge i] + interrupteur » des options booléennes.
# info non vide → badge « i » ouvrant la modale de description (issue #7).
func _toggle_cell(parent: Control, label_text: String, info := "") -> UI.ThemeSwitch:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var l := UI.label(label_text, 18, UI.INK, 700)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(l)
	if info != "":
		var ib := UI.info_btn()
		ib.custom_minimum_size.y = 36
		ib.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var title := label_text
		var desc := info
		ib.pressed.connect(func() -> void: _info_modal(title, desc))
		row.add_child(ib)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var sw := UI.ThemeSwitch.new(false, false)
	row.add_child(sw)
	return sw

# Modale de description d'une règle (issue #7) : scrim assombri + panneau
# arcade centré, titre pixel + texte — tap sur le fond ou OK pour fermer.
func _info_modal(title: String, desc: String) -> void:
	var scrim := ColorRect.new()
	scrim.color = Color(0, 0, 0, 0.45)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(scrim)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE # laisse passer le tap-fond
	scrim.add_child(cc)
	var p := UI.panel()
	p.custom_minimum_size.x = 420
	cc.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	p.add_child(v)
	var t := UI.pix_label(title.to_upper(), 13, UI.BLUE)
	v.add_child(t)
	var d := UI.label(desc, 19, UI.INK, 600)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(d)
	var ok := UI.button("OK", "primary", true)
	ok.pressed.connect(func() -> void: scrim.queue_free())
	v.add_child(ok)
	scrim.gui_input.connect(func(ev: InputEvent) -> void:
		if UI.tap(ev):
			scrim.queue_free())
	UI.pop_in(p)

# Envoie les options complètes avec un champ modifié — les clés du moteur
# (§1.3) vivent sous options.game.
func _patch_opt(key: String, value: Variant) -> void:
	var o: Dictionary = UI.obj(Net.view.get("options")).duplicate(true)
	var g: Dictionary = UI.obj(o.get("game"))
	if ["dice_per_player", "paco_joker", "calza_enabled", "palifico_enabled"].has(key):
		g[key] = value
		o["game"] = g
	else:
		o[key] = value
	# Publique ⇒ mode dieu désactivé (§4.5) : bascule atomique en un seul
	# set_options — le switch passe off et se verrouille tant que publique.
	if key == "public" and value == true:
		o["god_mode"] = false
	# Dépendances règles perso (§1.5) : couper l'option mère retire les
	# règles qui l'exigent — le serveur refuserait le patch sinon.
	if key == "paco_joker" and value == false:
		UI.arr(g.get("rules")).erase("double_paco")
		o["game"] = g
	if key == "calza_enabled" and value == false:
		UI.arr(g.get("rules")).erase("calzone")
		o["game"] = g
	Net.set_options(o)

# Bascule une règle perso : maj de options.game.rules + activation des
# options mères requises, le tout en un seul set_options atomique (§1.5).
func _patch_rule(id: String, on: bool) -> void:
	var o: Dictionary = UI.obj(Net.view.get("options")).duplicate(true)
	var g: Dictionary = UI.obj(o.get("game"))
	var rl: Array = UI.arr(g.get("rules"))
	if on and not rl.has(id):
		rl.append(id)
	elif not on:
		rl.erase(id)
	match id:
		"double_paco":
			if on:
				g["paco_joker"] = true
		"calzone":
			if on:
				g["calza_enabled"] = true
	g["rules"] = rl
	o["game"] = g
	Net.set_options(o)

# Aligne une liste sur la valeur serveur sans émettre de signal.
func _sync_opt(o: OptionButton, meta_val: Variant) -> void:
	var pop := o.get_popup()
	for i in o.item_count:
		var cur: bool = o.get_item_metadata(i) == meta_val
		pop.set_item_checked(i, cur)
		if cur:
			o.select(i)

# Largeur des cartes de menu : quasi plein écran sur mobile (canvas
# étroit) mais plafonnée pour rester une « carte » sur desktop (#11).
func _card_w() -> float:
	return clampf(get_viewport_rect().size.x - 40.0, 500.0, 660.0)

# Champ de saisie « écran de borne » : bordure épaisse + ombre dure,
# focus bleu — même signature que les boutons.
func _line_edit(placeholder: String, maxlen: int) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.max_length = maxlen
	e.custom_minimum_size.y = 64
	e.add_theme_font_override("font", UI.font_w(700))
	e.add_theme_font_size_override("font_size", 30)
	e.add_theme_color_override("font_color", UI.INK)
	e.add_theme_color_override("font_placeholder_color", UI.DIM)
	e.add_theme_color_override("caret_color", UI.BLUE)
	e.add_theme_stylebox_override("normal", UI.px(UI.PANEL, UI.EDGE, 8, 3, 5))
	e.add_theme_stylebox_override("focus", UI.px(UI.PANEL, UI.BLUE, 8, 3, 5))
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

# Curseur de menu arcade : glisse vers le contrôle qui prend le focus
# (clavier/manette) — signal viewport, ça couvre aussi les contrôles
# créés après coup (lignes du lobby public…).
func _move_cursor(c: Control) -> void:
	if not _cursor_target_ok(c):
		_cursor.visible = false
		return
	var gp := c.get_global_rect()
	var tgt := gp.position + Vector2(-34, gp.size.y / 2.0 - 13)
	if not _cursor.visible:
		_cursor.position = tgt # placement instantané au premier focus
	_cursor.visible = true
	if _cur_t:
		_cur_t.kill()
	_cur_t = _cursor.create_tween() # lié au curseur : meurt avec lui (rebuild)
	_cur_t.tween_property(_cursor, "position", tgt, 0.12) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# Le curseur ne suit que les vrais widgets interactifs — pas les popups
# d'OptionButton, panels ou ScrollContainer qui peuvent prendre le
# focus et plaçaient le triangle entre les lignes (#12).
func _cursor_target_ok(c: Control) -> bool:
	return is_instance_valid(c) and c.is_visible_in_tree() \
		and (c is BaseButton or c is LineEdit or c is Range \
			or c is UI.ThemeSwitch)

func _process(_d: float) -> void:
	# gui_focus_changed ne tire que sur PRISE de focus : quand le
	# contrôle focusé est caché ou libéré (retour accueil, rebuild),
	# le focus est relâché sans signal et le curseur restait figé à
	# sa dernière position (#12). On le masque dès que plus rien de
	# valide n'a le focus.
	if _cursor != null and _cursor.visible and \
			not _cursor_target_ok(get_viewport().gui_get_focus_owner()):
		_cursor.visible = false

func _set_status(t: String, col := UI.RED_DK) -> void:
	_status.text = t
	_status.add_theme_color_override("font_color", col)

func _connect(pending: String) -> void:
	_pending = pending
	_set_status("connexion…", UI.DIM)
	Net.connect_server()
	if Net.is_open():
		Net.hello(_name_edit.text.strip_edges())

# --- Lobby public (§3.2) : les listes ne sont pas poussées par le serveur,
# elles se rafraîchissent par polling tant que l'écran est affiché. ---

func _open_browse() -> void:
	_home.visible = false
	_browse.visible = true
	UI.pop_in(_browse_card)
	_browse_select(_browse_tab)
	_connect("browse")
	_browse_tick()

func _browse_tick() -> void:
	if not _browse.visible:
		return
	if Net.is_open():
		Net.list_rooms()
	get_tree().create_timer(3.0).timeout.connect(_browse_tick)

func _browse_select(tab: String) -> void:
	_browse_tab = tab
	for tid in _browse_tabs:
		_browse_tabs[tid].button_pressed = (tid == tab)
	_browse_render()

func _on_room_list(rooms: Array) -> void:
	if not _browse.visible:
		return
	_rooms = rooms
	_browse_render()

func _browse_render() -> void:
	for c in _browse_rows.get_children():
		c.queue_free()
	var n := 0
	for r in _rooms:
		if r.get("state") != _browse_tab:
			continue
		n += 1
		_browse_rows.add_child(_browse_row(r))
	_browse_status.text = "" if n > 0 else (
		"Aucune table en attente" if _browse_tab == "lobby" else "Aucune partie en cours")
	_browse_status.add_theme_color_override("font_color", UI.DIM)

# Ligne « Table de X — n/6 joueurs · dés · timer » + Rejoindre/Regarder.
func _browse_row(r: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	info.add_child(UI.label(r.get("name", "Table"), 18, UI.INK, 800))
	var opts := UI.obj(r.get("options"))
	var gopts := UI.obj(opts.get("game"))
	var timer_txt := "sans timer" if int(opts.get("timer_seconds", 0)) == 0 \
		else "%d s" % int(opts.get("timer_seconds"))
	var det := "%d/%d joueurs · %d dés · %s" % [
		int(r.get("players", 0)), int(r.get("max_players", 6)),
		int(gopts.get("dice_per_player", 5)), timer_txt]
	info.add_child(UI.label(det, 14, UI.DIM, 700))
	var playing: bool = r.get("state") == "playing"
	var jb := UI.button("REGARDER" if playing else "REJOINDRE", "btn", true)
	jb.custom_minimum_size = Vector2(130, 52)
	jb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var code := String(r.get("code", ""))
	jb.pressed.connect(func() -> void:
		_pending_code = code
		_connect("join"))
	row.add_child(jb)
	return row

func _on_view(v: Dictionary) -> void:
	if v.get("state") == "playing":
		_home.visible = false
		_lobby.visible = false
		_browse.visible = false
		get_tree().call_deferred("change_scene_to_file", "res://main.tscn")
		return
	if v.get("state") != "lobby":
		return
	_home.visible = false
	_browse.visible = false
	var entering := not _lobby.visible
	_lobby.visible = true
	UI.pop_in(_lobby_card)
	if entering:
		for c in _chat_log.get_children():
			c.queue_free()
	_room_lbl.text = v.get("name", "Table")
	_code_lbl.text = v.get("code", "?")
	for c in _players_box.get_children():
		c.queue_free()
	for c in _bots_box.get_children():
		c.queue_free()
	var is_host: bool = v.get("host", "") == Net.token
	var idx := 0
	for p in UI.arr(v.get("players")):
		var txt: String = p.get("name", "?")
		var is_bot: bool = p.get("bot", false)
		if is_bot:
			txt += "  (bot)"
		if not p.get("connected", true):
			txt += "  (déco)"
		var chip := UI.player_chip(txt, int(p.get("seat", idx)), 20)
		# Les bots listés sous le bouton « Ajouter un bot » : l'hôte peut les
		# retirer via la croix accolée à la chip (issue #5, remove_bot serveur).
		if is_bot:
			var brow := HBoxContainer.new()
			brow.alignment = BoxContainer.ALIGNMENT_CENTER
			brow.add_theme_constant_override("separation", 8)
			brow.add_child(chip)
			# La croix n'a de sens qu'avec l'id membre du bot (absent des vues
			# servies par un serveur antérieur à PlayerView.id).
			var bot_id := String(p.get("id", ""))
			if is_host and bot_id != "":
				var x := UI.button("✕", "dudo")
				x.custom_minimum_size = Vector2(40, 40)
				x.add_theme_font_size_override("font_size", 16)
				x.pressed.connect(func() -> void: Net.remove_bot(bot_id))
				brow.add_child(x)
			_bots_box.add_child(brow)
		else:
			var cc := CenterContainer.new()
			cc.add_child(chip)
			_players_box.add_child(cc)
		UI.pop_in(chip, idx * 0.08)
		idx += 1
	_launch_btn.visible = is_host
	# Ajout de bot réservé à l'hôte côté serveur (ErrNotHost sinon).
	_bot_btn.visible = is_host
	_scene_opt.disabled = not is_host
	var scene_id := String(UI.obj(v.get("options")).get("scene", "salon"))
	var opt_popup := _scene_opt.get_popup()
	for i in _scene_opt.item_count:
		var cur := String(_scene_opt.get_item_metadata(i)) == scene_id
		opt_popup.set_item_checked(i, cur)
		if cur:
			_scene_opt.select(i)
	# Options de la table : sync depuis l'état serveur (canonique) —
	# éditable par l'hôte, lecture seule pour les invités.
	var opts := UI.obj(v.get("options"))
	var gopts := UI.obj(opts.get("game"))
	for o in [_opt_dice, _opt_maxp, _opt_timer]:
		o.disabled = not is_host
	_sync_opt(_opt_dice, int(gopts.get("dice_per_player", 5)))
	_sync_opt(_opt_maxp, int(opts.get("max_players", 6)))
	_sync_opt(_opt_timer, int(opts.get("timer_seconds", 30)))
	var groups := {"paco_joker": gopts, "calza_enabled": gopts,
		"palifico_enabled": gopts, "bot_replacement": opts, "spectators": opts,
		"god_mode": opts, "public": opts}
	var public_on := bool(opts.get("public", false))
	var is_creator := bool(v.get("creator", false))
	for k in _opt_sw:
		var sw: UI.ThemeSwitch = _opt_sw[k]
		# Le statut du mode dieu n'est visible que pour le créateur (§4.5) :
		# la ligne entière (label + switch) est cachée aux autres membres.
		sw.get_parent().visible = k != "god_mode" or is_creator
		var def: bool = not ["god_mode", "public"].has(k) # ces deux options sont off par défaut
		# Le mode dieu est toujours affiché off tant que la table est publique.
		var on: bool = bool(groups[k].get(k, def)) and not (k == "god_mode" and public_on)
		sw.set_on_quiet(on)
		# Mode dieu verrouillé sur une table publique (§4.5).
		var editable: bool = is_host and not (k == "god_mode" and public_on)
		sw.editable = editable
		sw.focus_mode = Control.FOCUS_ALL if editable else Control.FOCUS_NONE
		sw.mouse_filter = Control.MOUSE_FILTER_STOP if editable else Control.MOUSE_FILTER_IGNORE
		sw.modulate.a = 1.0 if editable else 0.55
	# Règles perso : sync depuis options.game.rules (état serveur
	# canonique) — éditables par l'hôte uniquement.
	var active := UI.arr(gopts.get("rules"))
	for k in _rule_sw:
		var sw: UI.ThemeSwitch = _rule_sw[k]
		sw.set_on_quiet(active.has(k))
		sw.editable = is_host
		sw.focus_mode = Control.FOCUS_ALL if is_host else Control.FOCUS_NONE
		sw.mouse_filter = Control.MOUSE_FILTER_STOP if is_host else Control.MOUSE_FILTER_IGNORE
		sw.modulate.a = 1.0 if is_host else 0.55
	# Focus à l'ouverture du lobby seulement : le refaire à chaque room_state
	# volerait le focus pendant la navigation manette.
	if entering:
		var first: Control = _scene_opt if is_host else _leave_btn
		first.call_deferred("grab_focus")

func _on_notice(d: Dictionary) -> void:
	match d.get("kind", ""):
		"kicked":
			_set_status("Tu as été expulsé de la table")
			_lobby.visible = false
			_browse.visible = false
			_home.visible = true
		"room_closed":
			_set_status("La salle a été fermée")
			_lobby.visible = false
			_browse.visible = false
			_home.visible = true
		"chat":
			var msg := "%s : %s" % [d.get("from", "?"), UI.chat_text(d.get("text", ""))]
			_set_status(msg, UI.BLUE_DK)
			_chat_append(msg)

func _chat_append(msg: String) -> void:
	var l := UI.label(msg, 15, UI.INK)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_chat_log.add_child(l)
	while _chat_log.get_child_count() > 30:
		_chat_log.get_child(0).queue_free()
	# Scrolle en bas après que le conteneur a refait sa mise en page.
	_chat_scroll.scroll_vertical = _chat_scroll.get_v_scroll_bar().max_value
