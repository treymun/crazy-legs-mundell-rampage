## The weather that changes play, a simulation feature (carried, its dice
## shared by every machine): how hard it rains and how wet the ground is (the
## rain's spells, as weather.gd kept them before), how much water the puddles
## have gathered over a long storm, how muddy that leaves dirt and grass
## (effects.cfg [mud]), and the wind with its gusts. Play reads game.mud and
## game.wind, set here each tick and scaled by the WEATHER setting
## (game.weather_feel: FULL 1, LIGHT .5, OFF 0): Mud.pace slows a body on a
## muddy floor, a thrown thing drifts on the wind (game_combat.gd move_shot).
## The looks (weather.gd, the 3D view's puddles and swaying props, the dust)
## read the values here unscaled, so they stay whatever the setting.
##
## County Run's storm front (src/modes/county_storm.gd) sets `storm` (0 to 1):
## the rain and the wind build with it on a map that is otherwise dry.
extends GameFeature

## How fast a shower comes on and lets up (rain a second), and how fast the
## ground soaks and dries (wetness a second), as weather.gd had them.
const RAMP := .2
const SOAK := .05
const DRY := .01

var dice := RandomNumberGenerator.new()
## How hard it rains this moment and how wet the ground is (0 to 1); the
## puddles' water (0 to 1: more of them and bigger the longer it rains).
var rain := 0.0
var wet := 0.0
var pool := 0.0
## Showers: whether a spell of rain is on and when it changes.
var spell_on := false
var spell_until := 0.0
## The wind: its bearing on the map (radians), the level's own (cells a
## second), the gust blowing now (0 to 1 of gust_most), how it rises and
## falls, and when the next comes.
var wind_angle := 0.0
var wind_base := 0.0
var gust := 0.0
var gust_peak := 0.0
var gust_from := 0.0
var gust_until := -1.0
var next_gust := 0.0
## County Run's storm front (0 to 1, county_storm.gd) and the way it blows.
var storm := 0.0
var storm_angle := 0.0


func id() -> String:
	return "climate"


func attach() -> void:
	dice.seed = hash(game.level.id) + 51
	game.events.ticked.connect(_tick)
	var hard := rain_strength()
	if hard > 0.0 and showers() <= 0.0:
		# A storm chapter starts in its storm, the ground soaked, puddles out.
		rain = hard
		wet = hard
		pool = number("pool_start", .25) * hard
	spell_until = 20.0 + dice.randf_range(0.0, 40.0)
	var base: Vector2 = Effects.DEBRIS.get(
		"wind_" + game.level.id, number("calm_wind", Vector2(.28, .1))
	)
	wind_angle = base.angle()
	wind_base = base.length()
	next_gust = dice.randf_range(2.0, 6.0)


## A [climate] number (effects.cfg).
static func number(key: String, fallback: Variant) -> Variant:
	return Effects.CLIMATE.get(key, fallback)


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


## How muddy the ground is (0 to 1) before the setting scales it.
func muddy() -> float:
	return clampf(wet * .7 + pool * .4, 0.0, 1.0)


## The wind as the looks see it (cells a second, the way it blows): the
## level's own, stronger in the rain and in a gust, the storm's on top.
func look_wind() -> Vector2:
	var most: float = number("gust_most", 1.8)
	var lift: float = number("rain_wind", .8)
	var strength := wind_base * (1.0 + rain * lift + gust * most)
	var blow := Vector2.from_angle(wind_angle) * strength
	if storm > 0.0:
		blow += Vector2.from_angle(storm_angle) * storm * (1.0 + gust) * 1.2
	return blow


## How hard the wind blows now against the level's calm (1 calm, more in a
## gust): the 3D view sways the props by it.
func gusting() -> float:
	var most: float = number("gust_most", 1.8)
	return 1.0 + gust * most + storm


func _tick(dt: float) -> void:
	_rain(dt)
	_gusts(dt)
	var feel := game.weather_feel
	game.mud = muddy() * feel
	var push: float = number("wind_push", .9)
	game.wind = look_wind() * push * feel


## The rain coming and going, the ground soaking it up and drying, the
## puddles filling while it rains on and drying slowly after.
func _rain(dt: float) -> void:
	var hard := rain_strength()
	var want := hard
	if hard > 0.0:
		var share := showers()
		if share > 0.0:
			if game.clock >= spell_until:
				spell_on = not spell_on
				# Spells of about a minute; dry ones as long as the share leaves.
				var length := dice.randf_range(40.0, 80.0)
				spell_until = (
					game.clock + (length if spell_on else length * (1.0 - share) / share)
				)
			want = hard if spell_on else 0.0
	want = maxf(want, storm * .95)
	if want <= 0.0 and rain <= 0.0 and wet <= 0.0 and pool <= 0.0:
		return
	rain = move_toward(rain, want, RAMP * dt)
	wet = move_toward(wet, rain, (SOAK if rain > wet else DRY) * dt)
	if rain > .2:
		var grow: float = number("pool_grow", .0045)
		pool = minf(1.0, pool + grow * rain * dt)
	else:
		var dry: float = number("pool_dry", .0025)
		pool = maxf(0.0, pool - dry * dt)


## A gust now and then: it rises, holds and falls away (a smooth hump over
## its seconds); the wind's bearing wanders a little with each.
func _gusts(_dt: float) -> void:
	if game.clock >= next_gust and gust_until < game.clock:
		var wait: Vector2 = number("gust_wait", Vector2(3, 9))
		var long: Vector2 = number("gust_long", Vector2(1.2, 3.2))
		gust_from = game.clock
		gust_until = game.clock + dice.randf_range(long.x, long.y)
		gust_peak = dice.randf_range(.45, 1.0)
		wind_angle += dice.randf_range(-.25, .25)
		next_gust = gust_until + dice.randf_range(wait.x, wait.y)
	if game.clock < gust_until:
		var t := (game.clock - gust_from) / maxf(.01, gust_until - gust_from)
		gust = gust_peak * sin(t * PI)
	else:
		gust = 0.0
