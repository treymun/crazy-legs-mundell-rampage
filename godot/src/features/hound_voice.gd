## BLUE's own little noises and the moments that are this machine's alone
## (pass 10; the hound himself is features/hound.gd): he pants after a run,
## sniffs when he noses about or stands idle, shakes himself off out of the
## water or back on his feet, cowers and whimpers at the thunder (the
## weather is this machine's), and now and then howls along to the radio's
## song by a set (the radio is this machine's too). Looks and sound only,
## with its own dice: it never touches play, and a host leaves it off.
##
## What the looks may read (features/hound_voice.gd, by his player's slot):
## cowering(), howling(), shaking(), panting().
extends GameFeature

const Hound := preload("res://src/features/hound.gd")
const Weather := preload("res://src/features/weather.gd")
const Radio := preload("res://src/features/radio.gd")
## Running this long (seconds, faster than a lope) and then stopping, he
## pants, at most PANT_MOST seconds; a pant every PANT_EVERY.
const RUN_PANT := 3.0
const PANT_MOST := 7.0
const PANT_EVERY := 2.1
## How long each moment shows.
const COWER_FOR := 2.2
const HOWL_FOR := 2.6
const SHAKE_FOR := 1.1
## An idle sniff at heel every so often (seconds, and the chance).
const SNIFF_EVERY := 9.0
const SNIFF_CHANCE := .35
## The radio: near a set this much (RadioStation.near), a howl along at
## most every RADIO_REST seconds (to RADIO_MORE more), now and then.
const RADIO_NEAR := .35
const RADIO_REST := 45.0
const RADIO_MORE := 40.0
const RADIO_CHANCE := .35


## One hound's moments, by his player's slot.
class Ears:
	var ran := 0.0
	var pant_left := 0.0
	var next_pant := 0.0
	var next_sniff := 0.0
	var wet_for := 0.0
	var dry_for := 0.0
	var was_down := false
	var was_riding := false
	var was_job := -1
	var cower_until := -1.0
	var howl_until := -1.0
	var shake_until := -1.0
	var next_radio := 0.0


var _ears := {}
var _dice := Sound.ShuffleRng.new(2112)
var _thunder := -1.0


func id() -> String:
	return "hound_voice"


func attach() -> void:
	tick_with(_tick)


## Whether player `slot`'s hound cowers (the thunder) just now.
func cowering(slot: int) -> bool:
	return _until(slot, "cower_until")


## Whether he howls along to the radio just now.
func howling(slot: int) -> bool:
	return _until(slot, "howl_until")


## Whether he shakes himself off just now.
func shaking(slot: int) -> bool:
	return _until(slot, "shake_until")


## Whether he pants just now.
func panting(slot: int) -> bool:
	var ears: Ears = _ears.get(slot)
	return ears != null and ears.pant_left > 0.0


func _until(slot: int, field: String) -> bool:
	var ears: Ears = _ears.get(slot)
	if ears == null:
		return false
	var until: float = ears.get(field)
	return game.clock < until


func _tick(dt: float) -> void:
	var hound: Hound = game.features.get("hound")
	if hound == null or not hound.on or hound.dogs.is_empty():
		return
	var thunder := _thundered()
	for d: Hound.Dog in hound.dogs:
		if not _ears.has(d.slot):
			_ears[d.slot] = Ears.new()
		var ears: Ears = _ears[d.slot]
		_moments(d, ears, dt, thunder)


## Whether the weather's thunder rolled this tick.
func _thundered() -> bool:
	var sky: Weather = game.features.get("weather")
	if sky == null:
		return false
	var rolled := _thunder > 0.0 and sky.thunder_at <= 0.0
	_thunder = sky.thunder_at
	return rolled


func _moments(d: Hound.Dog, ears: Ears, dt: float, thunder: bool) -> void:
	var now := game.clock
	var down := d.state == Hound.DOWN
	var riding := d.state == Hound.RIDE
	var idle := d.state == Hound.FOLLOW and d.pace < .3 and d.job == Hound.HEEL
	# Back on his feet, or down off the airboat's seat: a shake.
	if (ears.was_down and not down) or (ears.was_riding and not riding and d.hop == Vector2.INF):
		_shake(d, ears)
	ears.was_down = down
	if not riding or d.hop == Vector2.INF:
		ears.was_riding = riding
	if down or riding:
		ears.ran = 0.0
		ears.pant_left = 0.0
		return
	# Out of the water: a shake once he is out of it a moment.
	if BayouBrains.wet_at(game.world, d.x, d.y):
		ears.wet_for += dt
		ears.dry_for = 0.0
	else:
		ears.dry_for += dt
		if ears.wet_for > .8 and ears.dry_for > .4:
			ears.wet_for = 0.0
			_shake(d, ears)
		elif ears.dry_for > 2.0:
			ears.wet_for = 0.0
	# A run, then a stop: panting.
	if d.pace > 4.0:
		ears.ran += dt
		ears.pant_left = 0.0
	elif d.pace < 1.0 and ears.ran > RUN_PANT:
		ears.pant_left = minf(PANT_MOST, ears.ran)
		ears.ran = 0.0
	else:
		ears.ran = maxf(0.0, ears.ran - dt * .5)
	if ears.pant_left > 0.0:
		ears.pant_left -= dt
		if now >= ears.next_pant and d.pace < 1.0:
			ears.next_pant = now + PANT_EVERY
			game.sound_at("hound_pant", d.x, d.y, .55)
	# Nosing about where he ranged, or a sniff now and then at heel.
	if d.job != ears.was_job and d.job == Hound.NOSING:
		game.sound_at("hound_sniff", d.x, d.y, .6)
	ears.was_job = d.job
	if idle and now >= ears.next_sniff:
		ears.next_sniff = now + SNIFF_EVERY * (.6 + _dice.next() * .8)
		if _dice.next() < SNIFF_CHANCE and ears.pant_left <= 0.0:
			game.sound_at("hound_sniff", d.x, d.y, .45)
	if thunder:
		if idle or d.state == Hound.STAY:
			ears.cower_until = now + COWER_FOR
			game.sound_at("hound_whimper", d.x, d.y, .75)
		elif _dice.next() < .5:
			game.sound_at("hound_whimper", d.x, d.y, .55)
	if idle and now >= ears.next_radio and now >= ears.cower_until:
		_radio(d, ears)


## A shake-off: the sound and the moment.
func _shake(d: Hound.Dog, ears: Ears) -> void:
	ears.shake_until = game.clock + SHAKE_FOR
	game.sound_at("hound_shake", d.x, d.y, .7)


## By a set playing a song (not the jock talking, not with the radio off):
## now and then he lifts his nose and howls along.
func _radio(d: Hound.Dog, ears: Ears) -> void:
	var radio: Radio = game.features.get("radio")
	var st := radio.the_station() if radio != null else null
	if st == null or not st.enabled or st.mode == RadioStation.OFF or st.in_break:
		return
	if st.near < RADIO_NEAR or game.sound.score == "":
		return
	ears.next_radio = game.clock + RADIO_REST + _dice.next() * RADIO_MORE
	if _dice.next() >= RADIO_CHANCE:
		return
	ears.howl_until = game.clock + HOWL_FOR
	game.sound_at("hound_howl", d.x, d.y, .8)
	if game.local_player != null and d.slot == game.local_player.slot:
		game.barks.say(game, "hound_hush")
