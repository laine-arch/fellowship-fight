class_name LobbyClient
extends Node
## WebSocket connection to the lobby server (server/src/server.js). Emits one signal per
## server message type; reconnects with backoff.

signal connected
signal disconnected
signal message(msg: Dictionary)

var url := ""
var nickname := ""
var lobby := "main"
var client_id := ""
var is_open := false
var _ws := WebSocketPeer.new()
var _want := false
var _retry_at := 0.0
var _backoff := 1.0
## Test hook: hold outgoing messages this long (simulates a slow connection).
var debug_delay_ms := 0
var _outbox: Array = []


func open(server_url: String, name: String, lobby_name: String, id: String) -> void:
	url = server_url; nickname = name; lobby = lobby_name; client_id = id
	_want = true
	_connect()


func close() -> void:
	_want = false
	_ws.close()


func _connect() -> void:
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = 1 << 18
	_ws.outbound_buffer_size = 1 << 18
	_retry_at = Time.get_ticks_msec() / 1000.0 + _backoff  # next attempt if this one fails
	_ws.connect_to_url(url)


func send(msg: Dictionary) -> void:
	if not is_open: return
	var text := JSON.stringify(msg, "", false, true)
	if debug_delay_ms > 0: _outbox.append([Time.get_ticks_msec() + debug_delay_ms + randi() % 20, text])
	else: _ws.send_text(text)


func _process(_dt: float) -> void:
	if not _want: return
	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not is_open:
				is_open = true; _backoff = 1.0
				send({"t": "hello", "name": nickname, "id": client_id, "lobby": lobby})
				connected.emit()
			while _outbox.size() and _outbox[0][0] <= Time.get_ticks_msec():
				_ws.send_text(_outbox.pop_front()[1])
			while _ws.get_available_packet_count() > 0:
				var data = JSON.parse_string(_ws.get_packet().get_string_from_utf8())
				if data is Dictionary and data.has("t"): message.emit(data)
		WebSocketPeer.STATE_CLOSED:
			if is_open:
				is_open = false
				disconnected.emit()
				_retry_at = Time.get_ticks_msec() / 1000.0 + _backoff
			if Time.get_ticks_msec() / 1000.0 >= _retry_at and _retry_at > 0:
				_backoff = minf(_backoff * 2, 15.0)
				_retry_at = Time.get_ticks_msec() / 1000.0 + _backoff
				_connect()
