## The loops the world makes around the player (Sound.set_bed): the rain,
## louder outdoors and a drumming on the roof when under one; the nearest burn
## barrel, grill, still or generator, or the Mothership's core; the hiss of
## the swamp king's wake while his airboat runs on the water. Sound only:
## nothing is saved and play never changes.
extends GameFeature

## Picture -> the loop it makes.
const SOURCES := {
	"town_burn_barrel": "fire_crackle",
	"town_grill": "ember_crackle",
	"town_still": "still_bubble",
	"town_generator": "generator_hum",
}
## Each loop's level against the others: the crackles were mastered quiet
## with loud pops, the engines loud and steady (audio_src/manifest.json).
const GAIN := {
	"fire_crackle": 1.0,
	"ember_crackle": .9,
	"still_bubble": .75,
	"generator_hum": .4,
	"core_thrum": .55,
	"airboat_wake": .6,
}
## How far a source is heard, and how loud it is (Game.sound_position strength).
const REACH := 9.0
const STRENGTH := .75
## How often the nearest source is looked for again (seconds).
const LOOK := .25

## [x, y, cue]
var _sources: Array = []
var _near: Array = []
var _look_at := 0.0
var _boat := Vector2.INF


func id() -> String:
	return "soundscape"


func attach() -> void:
	for board: LevelData.Billboard in game.world.billboards:
		if SOURCES.has(board.image):
			_sources.append([board.x, board.y, String(SOURCES[board.image])])
	for spot in Effects.mood(game.level.id, "heat", []):
		if game.level.id == "mothership" and spot is Vector4:
			_sources.append([spot.x, spot.y, "core_thrum"])
	game.ticked.connect(_tick)


func _tick(_dt: float) -> void:
	var sound: Sound = game.sound
	if sound == null:
		return
	_rain(sound)
	_nearest(sound)
	_wake(sound)


func _rain(sound: Sound) -> void:
	var weather = game.features.get("weather")
	var hard: float = 0.0 if weather == null else float(weather.rain)
	var p = game.player
	var cell: int = int(p.y) * game.level.width + int(p.x)
	var roofed: bool = game.world.roof[cell] != 0.0
	sound.set_bed(
		Sound.BED_RAIN,
		"rain_loop",
		hard * (.3 if roofed else .9),
		0.0,
		2600.0 if roofed else Sound.OPEN_CUTOFF
	)
	sound.set_bed(Sound.BED_ROOF, "rain_roof", hard * .3 if roofed else 0.0)


func _nearest(sound: Sound) -> void:
	var p = game.player
	if game.clock >= _look_at:
		_look_at = game.clock + LOOK
		_near = []
		var best := REACH * REACH
		for s: Array in _sources:
			var dx: float = float(s[0]) - p.x
			var dy: float = float(s[1]) - p.y
			var d := dx * dx + dy * dy
			if d < best:
				best = d
				_near = s
	if _near.is_empty():
		sound.set_bed(Sound.BED_NEAR, "", 0.0)
		return
	var x: float = _near[0]
	var y: float = _near[1]
	var place: Vector2 = game.sound_position(x, y, STRENGTH)
	var distance := Vector2(x - p.x, y - p.y).length()
	# Faded to nothing at the edge of its reach, so it never pops on or off.
	var edge := clampf((REACH - distance) / 2.0, 0.0, 1.0)
	var cue := String(_near[2])
	sound.set_bed(
		Sound.BED_NEAR,
		cue,
		place.x * edge * float(GAIN.get(cue, 1.0)),
		place.y,
		game.sound_cutoff(x, y)
	)


func _wake(sound: Sound) -> void:
	var water = game.features.get("water")
	for e: Enemy in game.enemies:
		if e.brain != "swamp_king" or not e.alive:
			continue
		var here := Vector2(e.x, e.y)
		var moving := _boat != Vector2.INF and here.distance_to(_boat) > .004
		_boat = here
		if moving and water != null and water.wet_at(e.x, e.y):
			var place: Vector2 = game.sound_position(e.x, e.y, .9)
			sound.set_bed(
				Sound.BED_WAKE,
				"airboat_wake",
				place.x * GAIN["airboat_wake"],
				place.y,
				game.sound_cutoff(e.x, e.y)
			)
			return
	sound.set_bed(Sound.BED_WAKE, "", 0.0)
