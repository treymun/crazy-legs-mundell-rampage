## The weather over the fields, all of it looks (the display shader draws it):
## on a level whose mood has `lightning` (effects.cfg), a flash every so often
## lights the sky and the yard (game.lightning, from `flash_dir`), and thunder
## rolls in a few seconds after; on one with `rain`, it rains that hard, all
## the time or, with `showers`, in spells that come and go, and the ground
## gets wet (puddles gather on the floors effects.cfg [puddles] names, and dry
## again slowly). Its own dice, never the game's; lightning is off with SCREEN
## FLASHES off; all of it with LIGHTS AND GLOW off; the hub stays calm.
##
## Since the weather changes play (features/climate.gd, a simulation feature
## carried online) the rain, the wet, the puddles' water and the wind are the
## climate's, mirrored here for the looks (a view tour still holds its own).
## Feet, hooves, claws and tyres on a muddy floor ([mud]) leave prints and
## tracks on the ground (track() for anything with wheels), the newest kept.
extends GameFeature

const Climate := preload("res://src/features/climate.gd")
## Prints: the most kept, how near the player a walker must be to leave
## them, the mud they need, each mark's stride and size.
const PRINT_CAP := 120
const PRINT_NEAR := 22.0
const PRINT_MUD := .12
const STRIDES := {"boot": .55, "hoof": .45, "claw": .22, "tyre": .5}
const SIZES := {"boot": .21, "hoof": .17, "claw": .13, "tyre": .5}
const HOOVES := ["pig", "bessie", "cow", "mule"]
const FLYERS := ["saucer", "skeeter", "drone", "lantern", "probe"]
const TYRES := ["tire_roller", "derby_champ"]

var dice := RandomNumberGenerator.new()
var next_flash := 0.0
var flash_age := -1.0
var thunder_at := -1.0
var thunder_far := 1.0
## Where this flash came from, a direction on the map (the shader lights the
## walls that face it more).
var flash_dir := Vector2(.6, -.8)
## How hard it rains this moment, and how wet the ground is (0 to 1).
var rain := 0.0
var wet := 0.0
## Showers: whether a spell of rain is on and when it changes.
var spell_on := false
var spell_until := 0.0
## A view tour holds the weather where it says (hold()).
var held := false
## The puddles' water (0 to 1) and the wind (cells a second, its way) and how
## hard it gusts (1 calm): the climate's, for the 3D view (puddles, ripples,
## swaying props, the rain's slant).
var pool := 0.0
var wind := Vector2.ZERO
var gusting := 1.0
## Prints in the mud (View.GroundMark) and each walker's last: walker ->
## [x, y, which foot].
var prints: Array = []
var _steps := {}
var _print_next := 0.0


func id() -> String:
	return "weather"


func attach() -> void:
	dice.seed = hash(game.level.id) + 51
	next_flash = 12.0 + dice.randf_range(0.0, 20.0)
	game.events.ticked.connect(_tick)
	# A storm chapter starts in its storm, the ground already soaked; showers
	# start dry, the first spell a little way in.
	var hard := rain_strength()
	if hard > 0.0 and showers() <= 0.0:
		rain = hard
		wet = hard
	spell_until = 20.0 + dice.randf_range(0.0, 40.0)
	wind = Effects.DEBRIS.get("wind_" + game.level.id, Vector2.ZERO)


## How hard it rains at most here (effects.cfg rain), 0 where it never does.
func rain_strength() -> float:
	if game.in_hub:
		return 0.0
	var most: float = Effects.mood(game.level.id, "rain", 0.0)
	return clampf(most, 0.0, 1.0)


## The share of the time it rains, for a level whose rain comes in spells.
func showers() -> float:
	var share: float = Effects.mood(game.level.id, "showers", 0.0)
	return clampf(share, 0.0, 1.0)


## A view tour's weather: rain this hard, the ground this wet, a flash, the
## puddles this full (-1: half the wet), the wind this strong (cells a second).
func hold(hard: float, soaked: float, flash := 0.0, full := -1.0, blow := Vector2.ZERO) -> void:
	held = true
	rain = hard
	wet = soaked
	pool = soaked * .5 if full < 0.0 else full
	if blow != Vector2.ZERO:
		wind = blow
		gusting = 1.0 + blow.length() * 2.0
	game.lightning = flash


func _tick(dt: float) -> void:
	_lay_prints()
	if held:
		return
	_rain(dt)
	var rate: float = Effects.mood(game.level.id, "lightning", 0.0)
	if rate <= 0.0 or game.in_hub or game.flash_scale <= 0.0 or not Effects.enabled:
		game.lightning = 0.0
		return
	if game.clock >= next_flash:
		next_flash = game.clock + 60.0 / rate * dice.randf_range(.5, 1.5)
		flash_age = 0.0
		thunder_far = dice.randf_range(.4, 1.0)
		thunder_at = game.clock + 1.0 + thunder_far * 3.5
		flash_dir = Vector2.from_angle(dice.randf_range(0.0, TAU))
	if flash_age >= 0.0:
		flash_age += dt
		# Two quick strokes and a fading glow.
		var flash := 0.0
		if flash_age < .08:
			flash = 1.0
		elif flash_age < .16:
			flash = .25
		elif flash_age < .26:
			flash = .8
		elif flash_age < .9:
			flash = .8 * (1.0 - (flash_age - .26) / .64)
		else:
			flash_age = -1.0
		game.lightning = flash * game.flash_scale
	else:
		game.lightning = 0.0
	if thunder_at > 0.0 and game.clock >= thunder_at:
		thunder_at = -1.0
		game.sound.play("thunder", .55 * (1.2 - thunder_far * .6), dice.randf_range(-.4, .4))


## The rain, the wet, the puddles and the wind: the climate's (play's).
func _rain(_dt: float) -> void:
	# It goes on raining with LIGHTS AND GLOW off (the view hands the shaders
	# none of it then), so turning it back on finds the same weather.
	var c: Climate = game.features.get("climate")
	if c == null:
		rain = 0.0
		wet = 0.0
		return
	rain = c.rain
	wet = c.wet
	pool = c.pool
	spell_on = c.spell_on
	spell_until = c.spell_until
	wind = c.look_wind()
	gusting = c.gusting()


## How muddy the ground looks (0 to 1), whatever the WEATHER setting.
func muddy() -> float:
	var c: Climate = game.features.get("climate")
	if held or c == null:
		return clampf(wet * .7 + pool * .4, 0.0, 1.0)
	return c.muddy()


## Something with wheels at (x, y): it leaves tyre tracks in the mud (a
## vehicle's own code may call this every tick).
func track(walker: Object, x: float, y: float) -> void:
	if muddy() >= PRINT_MUD:
		_step(walker, x, y, "tyre")


## Every walker near the player on a muddy floor leaves a print a stride.
func _lay_prints() -> void:
	if game.clock < _print_next:
		return
	_print_next = game.clock + .08
	if muddy() < PRINT_MUD or game.in_hub:
		if not _steps.is_empty():
			_steps.clear()
		return
	var me := game.local_player
	for p: Player in game.players:
		if p.health > 0 and p.air <= .01:
			_step(p, p.x, p.y, "boot")
	for e: Enemy in game.enemies:
		if not e.alive or e.dormant or FLYERS.has(e.brain) or e.z > .05 or e.hop > 0.0:
			continue
		if absf(e.x - me.x) > PRINT_NEAR or absf(e.y - me.y) > PRINT_NEAR:
			continue
		var mark := "boot"
		if TYRES.has(e.brain):
			mark = "tyre"
		elif HOOVES.has(e.brain):
			mark = "hoof"
		elif e.brain == "chicken":
			mark = "claw"
		_step(e, e.x, e.y, mark)
	if _steps.size() > 64:
		for walker: Object in _steps.keys():
			var e := walker as Enemy
			if e != null and not e.alive:
				_steps.erase(walker)


func _step(walker: Object, x: float, y: float, mark: String) -> void:
	var last: Array = _steps.get(walker, [])
	if last.is_empty():
		_steps[walker] = [x, y, false]
		return
	var lx: float = last[0]
	var ly: float = last[1]
	var stride: float = STRIDES[mark]
	var gone := (x - lx) * (x - lx) + (y - ly) * (y - ly)
	if gone < stride * stride:
		return
	if gone > 6.0:
		# Moved there in one go (a respawn, a teleport): no print between.
		_steps[walker] = [x, y, false]
		return
	var was: bool = last[2]
	var foot := not was
	_steps[walker] = [x, y, foot]
	if Mud.at(game.world, x, y) <= 0.0:
		return
	var heading := atan2(y - ly, x - lx)
	var side := 0.0 if mark == "tyre" else (.08 if foot else -.08)
	var px := x - sin(heading) * side
	var py := y + cos(heading) * side
	var size: float = SIZES[mark]
	var ground := View.GroundMark.new(
		px, py, 0.0, heading + PI / 2.0, size, .26 if mark == "tyre" else size, "mark_%s_mud" % mark
	)
	prints.append(Tumble.lay(game.world, ground, game.world.elevation(px, py) + .1))
	if prints.size() > PRINT_CAP:
		prints.pop_front()


func ground_marks() -> Array:
	var out: Array = []
	if prints.is_empty():
		return out
	var p := game.player
	for m: View.GroundMark in prints:
		if (m.x - p.x) * (m.x - p.x) + (m.y - p.y) * (m.y - p.y) < 196.0:
			out.append(m)
	return out
