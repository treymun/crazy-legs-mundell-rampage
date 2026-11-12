## The weather over the fields, all of it looks (the display shader draws it):
## on a level whose mood has `lightning` (effects.cfg), a flash every so often
## lights the sky and the yard (game.lightning, from `flash_dir`), and thunder
## rolls in a few seconds after; on one with `rain`, it rains that hard, all
## the time or, with `showers`, in spells that come and go, and the ground
## gets wet (puddles gather on the floors effects.cfg [puddles] names, and dry
## again slowly). Its own dice, never the game's; lightning is off with SCREEN
## FLASHES off; all of it with LIGHTS AND GLOW off; the hub stays calm.
extends GameFeature

## How fast a shower comes on and lets up (rain a second), and how fast the
## ground soaks and dries (wetness a second).
const RAMP := .2
const SOAK := .05
const DRY := .01

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


func id() -> String:
	return "weather"


func attach() -> void:
	dice.seed = hash(game.level.id) + 51
	next_flash = 12.0 + dice.randf_range(0.0, 20.0)
	game.ticked.connect(_tick)
	# A storm chapter starts in its storm, the ground already soaked; showers
	# start dry, the first spell a little way in.
	var hard := rain_strength()
	if hard > 0.0 and showers() <= 0.0:
		rain = hard
		wet = hard
	spell_until = 20.0 + dice.randf_range(0.0, 40.0)


## How hard it rains at most here (effects.cfg rain), 0 where it never does.
func rain_strength() -> float:
	if game.in_hub:
		return 0.0
	return clampf(float(Effects.mood(game.level.id, "rain", 0.0)), 0.0, 1.0)


## The share of the time it rains, for a level whose rain comes in spells.
func showers() -> float:
	return clampf(float(Effects.mood(game.level.id, "showers", 0.0)), 0.0, 1.0)


## A view tour's weather: rain this hard, the ground this wet, a flash.
func hold(hard: float, soaked: float, flash := 0.0) -> void:
	held = true
	rain = hard
	wet = soaked
	game.lightning = flash


func _tick(dt: float) -> void:
	if held:
		return
	_rain(dt)
	var rate := float(Effects.mood(game.level.id, "lightning", 0.0))
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


## The rain coming and going, and the ground soaking it up and drying.
func _rain(dt: float) -> void:
	# It goes on raining with LIGHTS AND GLOW off (scene_layers.gd hands the
	# shader none of it then), so turning it back on finds the same weather.
	var hard := rain_strength()
	if hard <= 0.0:
		rain = 0.0
		wet = 0.0
		return
	var share := showers()
	var want := hard
	if share > 0.0:
		if game.clock >= spell_until:
			spell_on = not spell_on
			# Spells of about a minute; dry ones as long as the share leaves.
			var length := dice.randf_range(40.0, 80.0)
			spell_until = game.clock + (length if spell_on else length * (1.0 - share) / share)
		want = hard if spell_on else 0.0
	rain = move_toward(rain, want, RAMP * dt)
	wet = move_toward(wet, rain, (SOAK if rain > wet else DRY) * dt)
