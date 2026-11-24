## Voice chat on this machine (docs/dev/multiplayer.md "Voice chat"): the
## mic in, the others' voices out, where they stand, and the marks. The front
## end (main.gd) keeps one while it is in an online lobby or match; the wire
## and the jitter buffers are net_voice.gd's, the sound's squeezing
## voice_codec.gd's. Nothing said is ever written down or kept: a frame is
## sent and dropped, a voice heard is played and dropped.
##
## - The mic (MICROPHONE on, off by default) is an AudioStreamMicrophone on a
##   bus of its own, muted, whose AudioEffectCapture is read each frame. It is
##   only opened while the mic is on and a lobby is up: a phone asks for
##   RECORD_AUDIO then, a browser for the mic (getUserMedia) then. A machine
##   that gives nothing says NO MIC and still plays the others.
## - PUSH TO TALK (the default) sends while the TALK key (KEYS page), a pad's
##   share, touchpad or first paddle button, or the phone's TALK button is
##   held, and a few frames after; OPEN MIC sends while the voice is over the
##   gate MIC SENSITIVITY sets, and a little after it drops.
## - Each voice heard plays through an AudioStreamGenerator on a bus of its
##   own (panner and low-pass, like the game's own placed sounds): from where
##   the talker stands as this copy draws them, fainter far off and gone past
##   NetVoice.RADIUS, muffled through walls and floors (Hearing), left and
##   right by STEREO WIDTH. In the lobby, and dead to dead in a 5v5, it is
##   flat. Nothing is ducked for it.
## - VOICE QUALITY: CLEAR 16K (the default) sends the two-band frame when the
##   lobby takes it and our line is not in trouble (NetVoice.sends_clear),
##   CB 8K the old one; every voice plays at VoiceCodec.OUT_RATE, a CB 8K
##   one through the same half-band filter, so a talker may change kinds
##   between frames without a seam.
class_name VoiceChat
extends Node

const VOICE_DATA := NetVoice.VOICE_DATA
const MIC_BUS := "voice_mic"
const OUT_BUS := "voice_out_%d"
## What a voice's generator holds ahead of the mixer (samples at
## VoiceCodec.OUT_RATE, about 110 ms): enough for a frame's wobble, little
## enough to stay quick.
const LEAD := 1800
const OUT_SECONDS := .4
## Pad buttons that talk while held (PUSH TO TALK).
const PAD_TALK := [JOY_BUTTON_MISC1, JOY_BUTTON_TOUCHPAD, JOY_BUTTON_PADDLE1]
## Seconds of a mic giving nothing but silence before it says NO MIC.
const NO_MIC_AFTER := 3.0
## The talking mark, MARK_W by 5: a mouth with sound coming off both sides.
const MARK_W := 7
const MARK := [".x...x.", "x..x..x", "x.xxx.x", "x..x..x", ".x...x."]
## Where the list of who is talking starts (draw, pins).
const ROW_X := 4
const ROW_Y := 22

static var FULL_WITHIN: float = Tuning.file(VOICE_DATA).get_value("voice", "full_within", 3.0)
static var FALLOFF: float = Tuning.file(VOICE_DATA).get_value("voice", "falloff", .11)
static var EDGE: float = Tuning.file(VOICE_DATA).get_value("voice", "edge", .25)
static var LEVEL: float = Tuning.file(VOICE_DATA).get_value("voice", "level", 1.15)
static var HANGOVER: int = Tuning.file(VOICE_DATA).get_value("voice", "hangover_frames", 8)
static var RELEASE: int = Tuning.file(VOICE_DATA).get_value("voice", "release_frames", 3)
static var GATE_LOW: float = Tuning.file(VOICE_DATA).get_value("voice", "gate_db_low", -28.0)
static var GATE_HIGH: float = Tuning.file(VOICE_DATA).get_value("voice", "gate_db_high", -58.0)
## The front end's marks for the 5v5's scoreboard: slot -> 1 talking,
## 2 muted (drawing only; tactical_screens.gd reads it).
static var marks := {}

## "off", "asking" (a phone's prompt up), "on", "none" (nothing comes in),
## "refused" (the phone said no).
var mic_state := "off"
var gate := Gate.new()
var _mic: AudioStreamPlayer = null
var _capture: AudioEffectCapture = null
var _mic_since := 0.0
var _heard_any := false
var _asked := false
var _down := VoiceCodec.Down.new()
var _coder := VoiceCodec.Coder.new()
## CLEAR 16K's: the mic at OUT_RATE, the two bands squeezed; whether the
## frames going now are CLEAR 16K.
var _down16 := VoiceCodec.Down.new(VoiceCodec.OUT_RATE, VoiceCodec.CLEAR_TOP)
var _wide_coder := VoiceCodec.WideCoder.new()
var _wide := false
var _pending := PackedFloat32Array()
var _pre := PackedFloat32Array()
var _pre_bands: Array[PackedFloat32Array] = []
## id -> Out
var _outs := {}
var _free_buses: Array[int] = []


## Whether a frame goes out: PUSH TO TALK while held (and RELEASE frames
## after), OPEN MIC while over the gate (and HANGOVER frames after).
class Gate:
	extends RefCounted
	var left := 0

	## The gate's level (dB) at MIC SENSITIVITY `sensitivity` (0 to 100).
	static func threshold(sensitivity: int) -> float:
		return lerpf(VoiceChat.GATE_LOW, VoiceChat.GATE_HIGH, clampf(sensitivity / 100.0, 0.0, 1.0))

	func step(level_db: float, held: bool, open_mic: bool, sensitivity: int) -> bool:
		if open_mic:
			if level_db >= threshold(sensitivity):
				left = VoiceChat.HANGOVER + 1
		elif held:
			left = VoiceChat.RELEASE + 1
		if left <= 0:
			return false
		left -= 1
		return true


## One voice's way out: a generator on a bus with a panner and a low-pass.
class Out:
	extends RefCounted
	var player: AudioStreamPlayer
	var playback: AudioStreamGeneratorPlayback
	var bus := 0
	var room := 0
	var used_at := 0.0


func _ready() -> void:
	name = "VoiceChat"
	var tree := get_tree()
	if tree != null and OS.has_feature("android"):
		tree.on_request_permissions_result.connect(_permission)


## One frame of the front end (main.gd): settings, the mic, the voices.
func frame(main: MainState) -> void:
	var net := main.net
	if net == null or net.phase not in ["lobby", "match"]:
		stop()
		return
	var now := Time.get_ticks_usec() / 1000.0
	var on: bool = _opt(main, "voice_chat", 1) != 0
	net.voice.hearing = on
	if not on:
		net.voice.talkers.clear()
	net.voice.clear = _opt(main, "voice_quality", 1) == 1
	net.voice.watch(now)
	net.voice.tell(net)
	var want := on and _opt(main, "voice_mic", 0) != 0
	var open_mic := _opt(main, "voice_talk", 0) == 1
	_open_mic(want, now)
	net.voice.mic = mic_state
	if mic_state == "on" or mic_state == "none":
		_read_mic(main, net, now, open_mic)
	if main.touch != null:
		main.touch.offer("talk", want and not open_mic and main.state == "play")
	_play(main, net, now)
	_note_marks(main, net, now)


## Lets go of the mic and every voice (out of the lobby, or the front end
## leaving).
func stop() -> void:
	if _mic != null and _mic.playing:
		_mic.stop()
	mic_state = "off"
	gate.left = 0
	_pending.clear()
	_pre.clear()
	_pre_bands.clear()
	for id: int in _outs.keys():
		_drop_out(id)
	marks.clear()


static func _opt(main: MainState, key: String, fallback: int) -> int:
	var value: int = main.options.get(key, fallback)
	return value


# ------------------------------------------------------------------ the mic


func _open_mic(want: bool, now: float) -> void:
	if not want:
		if _mic != null and _mic.playing:
			_mic.stop()
		mic_state = "off"
		gate.left = 0
		_asked = false  # turned on again: a phone that was told no asks again
		return
	if DisplayServer.get_name() == "headless":
		mic_state = "none"
		return
	if mic_state == "refused":
		return
	if OS.has_feature("android") and not _granted():
		mic_state = "asking"
		if not _asked:
			_asked = true
			OS.request_permission("RECORD_AUDIO")
		return
	if _mic == null:
		_make_mic()
	if not _mic.playing:
		_mic.play()
		_mic_since = now
		_heard_any = false
		mic_state = "on"
	if mic_state == "on" and not _heard_any and now - _mic_since > NO_MIC_AFTER * 1000.0:
		mic_state = "none"


static func _granted() -> bool:
	return OS.get_granted_permissions().has("android.permission.RECORD_AUDIO")


func _permission(permission: String, granted: bool) -> void:
	if permission.ends_with("RECORD_AUDIO") and not granted:
		mic_state = "refused"


func _make_mic() -> void:
	var bus := AudioServer.get_bus_index(MIC_BUS)
	if bus < 0:
		bus = AudioServer.bus_count
		AudioServer.add_bus(bus)
		AudioServer.set_bus_name(bus, MIC_BUS)
		AudioServer.set_bus_send(bus, "Master")
		# Read, never heard: our own voice is not played back to us.
		AudioServer.set_bus_mute(bus, true)
		var capture := AudioEffectCapture.new()
		capture.buffer_length = .5
		AudioServer.add_bus_effect(bus, capture)
	_capture = AudioServer.get_bus_effect(bus, 0) as AudioEffectCapture
	_mic = AudioStreamPlayer.new()
	_mic.name = "Mic"
	_mic.stream = AudioStreamMicrophone.new()
	_mic.bus = MIC_BUS
	add_child(_mic)


static func _peak(buf: PackedVector2Array) -> float:
	var peak := 0.0
	for f: Vector2 in buf:
		peak = maxf(peak, maxf(absf(f.x), absf(f.y)))
	return peak


func _read_mic(main: MainState, net: NetPlay, now: float, open_mic: bool) -> void:
	if _capture == null:
		return
	var n := _capture.get_frames_available()
	if n <= 0:
		return
	var held := talk_held(main)
	if not open_mic and not held and gate.left <= 0:
		# Nothing going out: the mic's sound is thrown away (looked at only
		# until it has once been more than silence, for NO MIC).
		if not _heard_any:
			_heard_any = _peak(_capture.get_buffer(n)) > 0.0
			if _heard_any and mic_state == "none":
				mic_state = "on"
		_capture.clear_buffer()
		_pending.clear()
		_pre.clear()
		_pre_bands.clear()
		return
	var buf := _capture.get_buffer(n)
	var mono := PackedFloat32Array()
	mono.resize(n)
	var peak := 0.0
	for i in n:
		var f := buf[i]
		var v := (f.x + f.y) * .5
		mono[i] = v
		peak = maxf(peak, absf(v))
	if peak > 0.0:
		_heard_any = true
		if mic_state == "none":
			mic_state = "on"
	feed(net, mono, AudioServer.get_mix_rate(), held, open_mic, _opt(main, "voice_gate", 50), now)


## The mic's sound (`mono` at `rate`) through the gate, squeezed and sent:
## what _read_mic does with the capture, and the checks with a made-up voice.
## CLEAR 16K or CB 8K as NetVoice.sends_clear says (a change starts afresh).
func feed(
	net: NetPlay,
	mono: PackedFloat32Array,
	rate: float,
	held: bool,
	open_mic: bool,
	sensitivity: int,
	now: float
) -> void:
	var wide := net.voice.sends_clear(net)
	if wide != _wide:
		_wide = wide
		_pending.clear()
		_pre.clear()
		_pre_bands.clear()
	_pending.append_array(_down16.take(mono, rate) if wide else _down.take(mono, rate))
	var size := VoiceCodec.OUT_FRAME if wide else VoiceCodec.FRAME
	while _pending.size() >= size:
		var pcm := _pending.slice(0, size)
		_pending = _pending.slice(size)
		# The bands split every frame, so the filter runs on through the quiet.
		var bands: Array[PackedFloat32Array] = []
		if wide:
			bands = _wide_coder.split(pcm)
		var was_open := gate.left > 0
		if gate.step(VoiceCodec.level_db(pcm), held, open_mic, sensitivity):
			if not was_open and not _pre.is_empty():
				# The frame before the gate opened too: the word's start.
				net.voice.send_own(net, _squeeze(_pre, _pre_bands), false, now)
			net.voice.send_own(net, _squeeze(pcm, bands), gate.left == 0, now)
		_pre = pcm
		_pre_bands = bands


## A frame as bytes: CLEAR 16K's two bands, or CB 8K's.
func _squeeze(pcm: PackedFloat32Array, bands: Array[PackedFloat32Array]) -> PackedByteArray:
	return _wide_coder.encode(bands) if not bands.is_empty() else _coder.encode(pcm)


## Whether PUSH TO TALK is held: the TALK key, a pad's talk button, the
## phone's TALK button (in a lobby or a match).
static func talk_held(main: MainState) -> bool:
	if main.state != "play" and main.state != "lobby":
		return false
	if KeyBindings.held("talk"):
		return true
	for device: int in Input.get_connected_joypads():
		for button: int in PAD_TALK:
			if Input.is_joy_button_pressed(device, button):
				return true
	return main.touch != null and main.touch.pressing("talk")


# ------------------------------------------------------------------ voices


func _play(main: MainState, net: NetPlay, now: float) -> void:
	var g: Game = main.game if main.state == "play" and net.match_game() == main.game else null
	var level := _opt(main, "voice_chat_volume", 80) / 100.0 * LEVEL
	var width := main.sound.pan_width if main.sound != null else .7
	var silent := DisplayServer.get_name() == "headless"
	for id: int in net.voice.talkers.keys():
		var t: NetVoice.Talker = net.voice.talkers[id]
		if silent:
			# No sound out (the checks): the voice is still taken off the wire.
			t.pull(VoiceCodec.OUT_FRAME, now)
			continue
		var out := _out_for(id, now)
		if out == null:
			continue
		var place := placement(g, _player_of(g, net, id), t.flat, width) * Vector3(level, level, 1)
		_set_place(out, place)
		var buffered := out.room - out.playback.get_frames_available()
		var want := LEAD - buffered
		if want <= 0:
			continue
		var pcm := t.pull(want, now)
		if pcm.is_empty():
			continue
		out.used_at = now
		var frames := PackedVector2Array()
		frames.resize(pcm.size())
		for i in pcm.size():
			frames[i] = Vector2(pcm[i], pcm[i])
		out.playback.push_buffer(frames)
	for id: int in _outs.keys():
		var out: Out = _outs[id]
		if not net.voice.talkers.has(id) or now - out.used_at > 5000.0:
			_drop_out(id)


## The talker `id`'s body in match `g` (null: none, or no match drawn).
static func _player_of(g: Game, net: NetPlay, id: int) -> Player:
	if g == null:
		return null
	var slot: int = net.player_of(id).get("slot", -1)
	return g.players[slot] if slot >= 0 and slot < g.players.size() else null


## How a voice from `speaker` reaches the local player of `g`: (left, right,
## low-pass cutoff), before VOICE CHAT VOLUME. Flat (the lobby, the dead to
## the dead, no body drawn): both sides whole, nothing muffled.
static func placement(g: Game, speaker: Player, flat: bool, width: float) -> Vector3:
	if flat or g == null or speaker == null or speaker == g.local_player:
		return Vector3(1.0, 1.0, Sound.OPEN_CUTOFF)
	var me := g.local_player
	var dx := speaker.x - me.x
	var dy := speaker.y - me.y
	var across := sqrt(dx * dx + dy * dy)
	var up := g.hearing.rise(g, speaker.x, speaker.y)
	var d := sqrt(across * across + up * up)
	var near := 1.0 if d <= FULL_WITHIN else 1.0 / (1.0 + (d - FULL_WITHIN) * FALLOFF)
	var fade_from := NetVoice.RADIUS * (1.0 - EDGE)
	if d > fade_from:
		near *= clampf((NetVoice.RADIUS - d) / maxf(.01, NetVoice.RADIUS - fade_from), 0.0, 1.0)
	var cutoff := Sound.OPEN_CUTOFF
	if d > 1.0:
		near *= g.hearing.gain(g, speaker.x, speaker.y)
		cutoff = g.sound_cutoff(speaker.x, speaker.y)
	var a := me.view_angle()
	var pan := (-sin(a) * dx + cos(a) * dy) / maxf(1.0, across)
	return Vector3(
		near * (1.0 - maxf(0.0, pan) * width), near * (1.0 + minf(0.0, pan) * width), cutoff
	)


func _set_place(out: Out, place: Vector3) -> void:
	var total := place.x + place.y
	out.player.volume_linear = clampf(total * .5, 0.0, 2.0)
	var panner := AudioServer.get_bus_effect(out.bus, 0) as AudioEffectPanner
	if panner != null and total > .0001:
		panner.pan = clampf((place.y - place.x) / total, -1.0, 1.0)
	var muffle := AudioServer.get_bus_effect(out.bus, 1) as AudioEffectLowPassFilter
	if muffle != null:
		muffle.cutoff_hz = place.z


func _out_for(id: int, now: float) -> Out:
	var had: Out = _outs.get(id)
	if had != null:
		return had
	if _outs.size() > NetVoice.HEARD_MOST:
		return null
	var out := Out.new()
	out.bus = _free_buses.pop_back() if not _free_buses.is_empty() else _make_bus()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = VoiceCodec.OUT_RATE
	gen.buffer_length = OUT_SECONDS
	out.player = AudioStreamPlayer.new()
	out.player.stream = gen
	out.player.bus = AudioServer.get_bus_name(out.bus)
	add_child(out.player)
	out.player.play()
	out.playback = out.player.get_stream_playback() as AudioStreamGeneratorPlayback
	out.room = out.playback.get_frames_available()
	out.used_at = now
	_outs[id] = out
	return out


func _make_bus() -> int:
	var k := 0
	while AudioServer.get_bus_index(OUT_BUS % k) >= 0:
		k += 1
	var bus := AudioServer.bus_count
	AudioServer.add_bus(bus)
	AudioServer.set_bus_name(bus, OUT_BUS % k)
	AudioServer.set_bus_send(bus, "Master")
	AudioServer.add_bus_effect(bus, AudioEffectPanner.new())
	var muffle := AudioEffectLowPassFilter.new()
	muffle.cutoff_hz = Sound.OPEN_CUTOFF
	AudioServer.add_bus_effect(bus, muffle)
	return bus


func _drop_out(id: int) -> void:
	var out: Out = _outs[id]
	_outs.erase(id)
	out.player.stop()
	out.player.queue_free()
	_free_buses.append(out.bus)


# ------------------------------------------------------------------ marks


func _note_marks(main: MainState, net: NetPlay, now: float) -> void:
	marks.clear()
	for p: Dictionary in net.players:
		var id: int = p["id"]
		var slot: int = p.get("slot", -1)
		if slot < 0:
			continue
		if net.voice.muted.has(id):
			marks[slot] = 2
		elif net.voice.talking(id, net.my_id, now):
			marks[slot] = 1
	if main.state != "play":
		marks.clear()


## The pieces drawn over play (main_state.gd _pin_hud keeps the HUD clear of
## them): our own mic's line and who is talking, down the left from ROW_Y
## (under the 5v5's cash; the right is the ping's, the frags', the kill
## feed's and the storm ring's).
func pins(main: MainState) -> Array:
	var out: Array = []
	var h: int = PixelType.style_of("mini")[1]
	for row: Array in _rows(main):
		var text: String = row[0]
		var y: int = row[2]
		var w := PixelType.text_width(text, "mini") + MARK_W + 3
		out.append(["voice_%d" % y, Rect2i(ROW_X - 1, y - 1, w + 2, h + 3)])
	return out


## Our mic's state and who is talking, top left, and a mark over each
## talker's head this player can see (main_state.gd, after play is drawn).
func draw(c: Canvas, main: MainState) -> void:
	var net := main.net
	if net == null or main.state != "play" or main.game == null:
		return
	var g := main.game
	var now := Time.get_ticks_usec() / 1000.0
	for row: Array in _rows(main):
		var text: String = row[0]
		var ink: Color = row[1]
		var y: int = row[2]
		var marked: bool = row[3]
		if marked:
			wave_mark(c, ROW_X, y, ink)
		HUD.text(c, text, ROW_X + MARK_W + 3, y, "mini", ink)
	if net.match_game() != g or g.showing_tally or main.kill_cam.playing or main.opener.playing:
		return
	if Modes.is_tactical(g) and (TacticalScreens.open or Input.is_key_pressed(KEY_TAB)):
		return  # the store or the scoreboard is up (it has marks of its own)
	var me := g.local_player
	for p: Dictionary in net.players:
		var id: int = p["id"]
		var q := _player_of(g, net, id)
		if q == null or q == me or q.health <= 0 or not net.voice.talking(id, net.my_id, now):
			continue
		var head: float = g.world.stand(q) + q.air + 1.45
		var at: Vector3 = g.to_canvas(q.x, q.y, head)
		if at.z <= 0.0 or at.x < 6.0 or at.x > View.WIDTH - 6.0 or at.y < 6.0:
			continue
		if at.y > View.VIEW - 6.0:
			continue
		if not g.world.visible(me.x, me.y, q.x, q.y, me.eye, head):
			continue
		wave_mark(c, int(at.x) - MARK_W / 2, int(at.y) - 4, HUD.AMBER)


## The rows of the list down the left: [text, ink, y, marked].
func _rows(main: MainState) -> Array:
	var out: Array = []
	var net := main.net
	if net == null or main.state != "play" or _opt(main, "voice_chat", 1) == 0:
		return out
	var now := Time.get_ticks_usec() / 1000.0
	var y := ROW_Y
	var mine := ""
	var ink := HUD.AMBER
	if mic_state == "on" and net.voice.sending(now):
		mine = "ON THE AIR"
		ink = LobbyScreens.RED
	elif mic_state == "none":
		mine = "NO MIC"
		ink = HUD.DIM
	elif mic_state == "asking":
		mine = "ALLOW THE MIC"
	elif mic_state == "refused":
		mine = "MIC REFUSED"
		ink = HUD.DIM
	if mine != "":
		out.append([mine, ink, y, mine == "ON THE AIR"])
		y += 7
	var shown := 0
	for p: Dictionary in net.players:
		var id: int = p["id"]
		if id == net.my_id or not net.voice.talking(id, net.my_id, now):
			continue
		if shown >= NetVoice.HEARD_MOST:
			break
		out.append([str(p["name"]), HUD.INK, y, true])
		y += 7
		shown += 1
	return out


## The talking mark at x, y (its top left) in `ink`, with a dark edge.
static func wave_mark(c: Canvas, x: int, y: int, ink: Color) -> void:
	var dark := Canvas.rgb(20, 13, 9)
	for pass_no in 2:
		for row in MARK.size():
			var line: String = MARK[row]
			for col in line.length():
				if line[col] != "x":
					continue
				if pass_no == 0:
					c.fill_rect(x + col + 1, y + row + 1, 1, 1, dark)
				else:
					c.fill_rect(x + col, y + row, 1, 1, ink)
