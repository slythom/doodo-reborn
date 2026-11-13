# net.gd — client WebSocket, autoload "Net".
# Connexion au serveur Go, session par jeton invité (persistée en user://),
# réception des enveloppes {type, data} et dispatch en signaux.
extends Node

signal connection_opened
signal connection_closed
signal welcome(token: String)
signal room_state(view: Dictionary)
signal game_events(events: Array)
signal notice_msg(data: Dictionary)
signal net_error(code: String, message: String)

const URL := "ws://localhost:8080/ws"
# DOODO_PROFILE permet plusieurs instances sur la même machine (jetons
# distincts, sinon la seconde vole la session de la première).
var CFG: String = "user://session%s.cfg" % OS.get_environment("DOODO_PROFILE")

var ws: WebSocketPeer
var token := ""
var last_name := ""
var view := {}
var _was_open := false

func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CFG) == OK:
		token = cfg.get_value("session", "token", "")
	set_process(false)

func connect_server() -> void:
	if is_open() or (ws != null and ws.get_ready_state() == WebSocketPeer.STATE_CONNECTING):
		return
	ws = WebSocketPeer.new()
	if ws.connect_to_url(URL) != OK:
		net_error.emit("connect", "impossible de joindre le serveur")
		return
	_was_open = false
	set_process(true)

func is_open() -> bool:
	return ws != null and ws.get_ready_state() == WebSocketPeer.STATE_OPEN

func _process(_dt: float) -> void:
	if ws == null:
		set_process(false)
		return
	ws.poll()
	match ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not _was_open:
				_was_open = true
				connection_opened.emit()
			while ws.get_available_packet_count() > 0:
				_on_packet(ws.get_packet().get_string_from_utf8())
		WebSocketPeer.STATE_CLOSED:
			_was_open = false
			set_process(false)
			connection_closed.emit()
			_auto_reconnect()

# Reconnexion auto : le serveur garde le siège 60 s (jeton invité).
func _auto_reconnect() -> void:
	await get_tree().create_timer(1.5).timeout
	if not is_open():
		connect_server()

func _on_packet(txt: String) -> void:
	var env = JSON.parse_string(txt)
	if not env is Dictionary:
		return
	var data = env.get("data")
	if data == null:
		data = {}
	match env.get("type", ""):
		"welcome":
			token = data.get("token", token)
			var cfg := ConfigFile.new()
			cfg.set_value("session", "token", token)
			cfg.save(CFG)
			welcome.emit(token)
		"room_state":
			view = data
			room_state.emit(data)
		"events":
			game_events.emit(UI.arr(data.get("events")))
		"notice":
			notice_msg.emit(data)
		"error":
			net_error.emit(data.get("code", "?"), data.get("message", "?"))

func _send(d: Dictionary) -> void:
	if is_open():
		ws.send_text(JSON.stringify(d))

# ---- Commandes (miroir du protocole serveur) ----

func hello(pseudo: String = "") -> void:
	if pseudo != "":
		last_name = pseudo
	_send({"type": "hello", "token": token, "name": last_name})
func create_room() -> void: _send({"type": "create"})
func join_room(code: String) -> void: _send({"type": "join", "code": code.to_upper()})
func quick_match() -> void: _send({"type": "quick"})
func launch() -> void: _send({"type": "launch"})
func set_scene(id: String) -> void: _send({"type": "set_scene", "scene": id})
func add_bot() -> void: _send({"type": "add_bot"})
func leave() -> void: _send({"type": "leave"})
func chat(text: String) -> void: _send({"type": "chat", "text": text})
func emote(target_seat: int, kind: String) -> void: _send({"type": "emote", "target": str(target_seat), "text": kind})
func bid(quantity: int, value: int) -> void: _send({"type": "action", "action": "bid", "quantity": quantity, "value": value})
func dudo() -> void: _send({"type": "action", "action": "dudo"})
func calza() -> void: _send({"type": "action", "action": "calza"})
func rematch() -> void: _send({"type": "rematch"})
