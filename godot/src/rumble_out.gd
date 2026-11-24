## The front end's motors: each frame of play it mixes the game's rumble
## (features/rumble.gd) and drives the pad being played with
## (Input.start_joy_vibration on the first pad, the one read_pad reads) and,
## played by touch, the phone (Input.vibrate_handheld on Android; in a phone's
## browser navigator.vibrate where there is one: an iPhone's has none, so it
## stays still and says nothing). RUMBLE (INPUT page) is the pad's level,
## PHONE RUMBLE (TOUCH page) the phone's: OFF, LOW or FULL.
##
## Outside live play (a menu, pause, the down screen, a held game, the window
## put away, a replay, the attract demo) the motors are stopped and the
## game's pulses dropped; main_state.gd stops them as the program goes and
## main_input.gd as the window or the app loses the focus. A pad is told again
## only when a motor moves enough or every `refresh` seconds, and each telling
## runs out by itself soon after, so a stalled frame never leaves it running.
## Numbers in data/tuning/rumble.cfg.
class_name RumbleOut
extends RefCounted

const Rumble := preload("res://src/features/rumble.gd")
## The sticks and triggers that say a pad is in hand.
const AXES: Array[JoyAxis] = [
	JOY_AXIS_LEFT_X,
	JOY_AXIS_LEFT_Y,
	JOY_AXIS_RIGHT_X,
	JOY_AXIS_RIGHT_Y,
	JOY_AXIS_TRIGGER_LEFT,
	JOY_AXIS_TRIGGER_RIGHT,
]


## What drives the motors: the engine's calls. tools/rumble_check.gd puts a
## recorder in its place.
class Sink:
	extends RefCounted

	func pads() -> Array[int]:
		return Input.get_connected_joypads()

	## Whether a stick or trigger of `device` is off its rest now.
	func pad_moved(device: int) -> bool:
		for axis: JoyAxis in AXES:
			if absf(Input.get_joy_axis(device, axis)) > .35:
				return true
		return false

	func pad(device: int, weak: float, strong: float, seconds: float) -> void:
		Input.start_joy_vibration(device, weak, strong, seconds)

	func pad_stop(device: int) -> void:
		Input.stop_joy_vibration(device)

	## Whether this machine can buzz: Android; a browser with navigator.vibrate.
	func phone_can() -> bool:
		if OS.has_feature("android"):
			return true
		if OS.has_feature("web"):
			return str(JavaScriptBridge.eval("typeof navigator.vibrate", true)) == "function"
		return false

	## A buzz of `ms` at `amplitude` (0 to 1; a browser cannot set it).
	func phone(ms: int, amplitude: float) -> void:
		if OS.has_feature("web"):
			JavaScriptBridge.eval("navigator.vibrate(%d)" % ms, true)
		else:
			Input.vibrate_handheld(ms, clampf(amplitude, .01, 1.0))

	func phone_stop() -> void:
		if OS.has_feature("web"):
			JavaScriptBridge.eval("navigator.vibrate(0)", true)


var sink := Sink.new()
## The pad driven (-1: none) and what it was last told.
var device := -1
var sent := Vector2.ZERO
var sent_at := -99.0
## Seconds of live play driven (the clock the pad's and phone's gaps count by).
var clock := 0.0
## When a stick or trigger of the pad last moved.
var pad_used_at := -99.0
## The phone: when it may buzz again and when its buzz ends; whether it can.
var phone_next := 0.0
var phone_until := 0.0
var _phone_can := -1


## Whether the game on screen is played live now: nothing over it, nobody's
## watching a replay, the local player up.
static func live_of(main: MainState) -> bool:
	var g := main.game
	if g == null or main.state != "play" or not main.focused:
		return false
	if main.photo.on or main.opener.playing or main.kill_cam.playing:
		return false
	if main.replay_play != null or main.demo or main.showcase:
		return false
	if main.console != null and main.console.open:
		return false
	return not g.showing_tally and not g.defeated() and g.local_player.health > 0


## Each frame (main.gd): the motors for `dt` seconds of it.
func frame(main: MainState, dt: float) -> void:
	var g := main.game
	var feature: Rumble = g.features.get("rumble") if g != null else null
	if feature == null or not live_of(main):
		if feature != null:
			feature.hush()
		stop()
		return
	var pad_level: int = main.options.get("rumble", 2)
	var phone_level: int = main.options.get("phone_rumble", 1)
	drive(feature, dt, pad_level, phone_level, main.input_device)


## The motors from `feature`'s mix after `dt`: the pad at `pad_level`, the
## phone at `phone_level` (0 OFF, 1 LOW, 2 FULL); `by` is what the player is
## playing with ("pad", "keys", "touch").
func drive(feature: Rumble, dt: float, pad_level: int, phone_level: int, by: String) -> void:
	clock += dt
	var mixed := feature.mix(dt)
	var fresh := feature.take_fresh()
	var pads := sink.pads()
	var dev: int = pads[0] if not pads.is_empty() else -1
	if dev != device:
		_pad_off()
		device = dev
	if dev >= 0 and (by == "pad" or sink.pad_moved(dev)):
		pad_used_at = clock
	var idle := RumbleData.num("all", "pad_idle", 20.0)
	if pad_level > 0 and dev >= 0 and by != "touch" and clock - pad_used_at < idle:
		_pad(mixed * RumbleData.level_scale(pad_level))
	else:
		_pad_off()
	if phone_level > 0 and by == "touch" and _can_buzz():
		_phone(fresh, RumbleData.level_scale(phone_level))


## Every motor still (out of play, the focus lost, the program closing).
func stop() -> void:
	_pad_off()
	if phone_until > clock:
		sink.phone_stop()
		phone_until = clock


## The setting just changed in the menu: a pulse at its new level, to feel it.
## Says what is wrong when nothing can (no pad, a phone that cannot buzz), else "".
func taste(key: String, level: int) -> String:
	var k := RumbleData.level_scale(level)
	var p := RumbleData.pulse("all", "taste")
	if key == "phone_rumble":
		if not _can_buzz():
			return "SAVED, BUT THIS ONE CANNOT BUZZ."
		if k > 0.0:
			sink.phone(int(p.z * 1000.0), maxf(p.x, p.y) * k)
		return ""
	var pads := sink.pads()
	if pads.is_empty():
		return "SAVED, BUT NO PAD IS HOOKED UP."
	if k > 0.0:
		sink.pad(pads[0], p.x * k, p.y * k, p.z)
	return ""


func _can_buzz() -> bool:
	if _phone_can < 0:
		_phone_can = 1 if sink.phone_can() else 0
	return _phone_can == 1


func _pad(m: Vector2) -> void:
	var w := clampf(m.x, 0.0, 1.0)
	var s := clampf(m.y, 0.0, 1.0)
	var quiet := RumbleData.num("all", "quiet", .02)
	if w < quiet and s < quiet:
		_pad_off()
		return
	var step := RumbleData.num("all", "send_step", .04)
	var refresh := RumbleData.num("all", "refresh", .2)
	if absf(w - sent.x) > step or absf(s - sent.y) > step or clock - sent_at >= refresh:
		sink.pad(device, w, s, refresh + RumbleData.num("all", "linger", .1))
		sent = Vector2(w, s)
		sent_at = clock


func _pad_off() -> void:
	if sent != Vector2.ZERO and device >= 0:
		sink.pad_stop(device)
	sent = Vector2.ZERO
	sent_at = -99.0


## One buzz for the strongest pulse just begun, if it is strong enough and
## the last has had its gap.
func _phone(fresh: Array[Rumble.Pulse], k: float) -> void:
	var best: Rumble.Pulse = null
	var best_amp := 0.0
	for pulse: Rumble.Pulse in fresh:
		var amp := maxf(pulse.weak, pulse.strong)
		if amp > best_amp:
			best_amp = amp
			best = pulse
	var amp := best_amp * k * RumbleData.num("phone", "scale", 1.0)
	if best == null or amp < RumbleData.num("phone", "floor", .12) or clock < phone_next:
		return
	var length := best.length
	if OS.has_feature("web"):
		length *= lerpf(RumbleData.num("phone", "web_short", .35), 1.0, clampf(amp, 0.0, 1.0))
	var ms := clampi(
		roundi(length * 1000.0),
		int(RumbleData.num("phone", "least_ms", 15.0)),
		int(RumbleData.num("phone", "most_ms", 300.0))
	)
	sink.phone(ms, clampf(amp, 0.0, 1.0))
	phone_next = clock + RumbleData.num("phone", "gap", .06)
	phone_until = clock + ms / 1000.0
