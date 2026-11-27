## Lights and glows as data (data/tuning/effects.cfg): which sources light up
## the world around them, in what colour and how far, and which tiles glow.
## Game.effect_lights() lists this frame's lights from them, scene_layers.gd
## hands them to display.gdshader, and bakes the glows into the tile atlas.
## Only the graphics-card view draws them (CLAUDE.md: one renderer).
class_name Effects
extends RefCounted

const PATH := "res://data/tuning/effects.cfg"
## As many lights as the shader takes in one frame; the nearest win.
const MAX_LIGHTS := 16
## Bits of a light's flags (its seventh value): it pools on the ground under
## it, and the air above it shimmers (display.gdshader light_flags, haze).
const POOL := 1
const HOT := 2

## source -> {color, radius, strength, life, flicker, height, pool, hot, props, at}
static var LIGHTS := {}
## tile name -> Vector2(threshold, light)
static var GLOW := {}
## level id -> its mood (fog, grade, clouds, lightning, rain, showers,
## fog_banks, heat, crows, fireflies)
static var LEVELS := {}
## tile name -> {mode, rate, depth}: tiles that move
static var ANIMS := {}
## mood name -> its values ([mood.<name>], pass 16: moods by area; a map opts
## in, features/area_moods.gd blends them), and [moods] (blend, snap).
static var MOODS := {}
static var MOOD_BLEND := {}
## [debris]: how long the leavings of a fight last
static var DEBRIS := {}
## [ragdoll]: how a kill throws a dead body's limbs (src/ragdoll.gd)
static var RAGDOLL := {}
## tile name -> 0..1: [water] (ripples and a broken reflection), [relief]
## (raised where a texel is brighter than its neighbours) and [puddles] (floors
## that gather puddles in the rain).
static var WATER := {}
static var RELIEF := {}
static var PUDDLES := {}
## The weather that changes play (features/climate.gd): [mud] tile -> 0..1
## (how muddy the floor gets in the wet, slowing what walks it), [sway] prop
## picture -> how far the wind sways it in the 3D view (below 0: it hangs from
## its top and swings), [climate] the numbers (mud, puddles, wind, gusts).
static var MUD := {}
static var SWAY := {}
static var CLIMATE := {}
## image name -> light source: the props a light stands on ([light.*] props).
static var PROP_LIGHTS := {}
## Every section's values by its name, for the looks read with num() (pass
## 15: [rim], [pickup_glint], [hurt_looks], [enemy_muzzle], [gun_smoke],
## [casings]).
static var SECTIONS := {}
## The shader takes this many moving tiles at once: those the level draws
## (scene_layers.gd), so [anim.*] may list more across all the chapters.
const MAX_ANIMS := 8
## Goes up on every reload, so the tile atlas knows to bake its glows again.
static var version := 0
## LIGHTS AND GLOW (main_state.gd); the comparison tour turns it off too.
static var enabled := true
## This frame is the shader view drawn with them (game_view.gd sets it): the
## gun and blast effects only the shader view shows (features/gun_fx.gd, the
## muzzle flashes of weapons.cfg flash_art, the tracers' glow) draw now. The
## software view and the shader view without lights never see them.
static var rich := false


static func _static_init() -> void:
	load_tuning()


static func load_tuning() -> void:
	var cfg := Tuning.file(PATH)
	LIGHTS = {}
	GLOW = {}
	LEVELS = {}
	ANIMS = {}
	MOODS = {}
	MOOD_BLEND = {}
	DEBRIS = {}
	RAGDOLL = {}
	WATER = {}
	RELIEF = {}
	PUDDLES = {}
	MUD = {}
	SWAY = {}
	CLIMATE = {}
	PROP_LIGHTS = {}
	SECTIONS = {}
	var tables := {
		"water": WATER,
		"relief": RELIEF,
		"puddles": PUDDLES,
		"glow": GLOW,
		"mud": MUD,
		"sway": SWAY,
		"climate": CLIMATE,
	}
	for section in cfg.get_sections():
		var values := {}
		for key in cfg.get_section_keys(section):
			values[key] = cfg.get_value(section, key)
		SECTIONS[section] = values
		if section.begins_with("level."):
			LEVELS[section.substr(6)] = values
		elif section.begins_with("anim."):
			ANIMS[section.substr(5)] = values
		elif section.begins_with("mood."):
			MOODS[section.substr(5)] = values
		elif section == "moods":
			MOOD_BLEND = values
		elif section == "debris":
			DEBRIS = values
		elif section == "ragdoll":
			RAGDOLL = values
		elif tables.has(section):
			var table: Dictionary = tables[section]
			for key: String in values:
				table[key] = values[key]
		elif section.begins_with("light."):
			var d := {
				"color": Color(1, 1, 1),
				"radius": 3.0,
				"strength": 1.0,
				"life": 0.0,
				"flicker": 0.0,
				"height": 1.0,
				"pool": false,
				"hot": false,
				"props": [],
				"at": .5
			}
			for key: String in values:
				d[key] = values[key]
			var source := section.substr(6)
			LIGHTS[source] = d
			for image: Variant in d["props"]:
				PROP_LIGHTS[str(image)] = source
	version += 1


## A value of effects.cfg's `section`, or `fallback` where it has none.
static func num(section: String, key: String, fallback: Variant) -> Variant:
	var values: Dictionary = SECTIONS.get(section, {})
	return values.get(key, fallback)


## A level's mood value, or `fallback` for a level effects.cfg does not name.
static func mood(level_id: String, key: String, fallback: Variant) -> Variant:
	var values: Dictionary = LEVELS.get(level_id, {})
	return values.get(key, fallback)


## A mood preset's value ([mood.<name>]), or `fallback` where it sets none.
static func preset(mood_name: String, key: String, fallback: Variant) -> Variant:
	var values: Dictionary = MOODS.get(mood_name, {})
	return values.get(key, fallback)


## One light of `source` at x, y, z, its strength scaled by `scale` (fading,
## a flash dying away): [x, y, z, radius, Color, strength, flags, heat], or
## null; heat is how wide the air above it shimmers, in cells (`hot`: true is
## .4). A source of strength 0 only shimmers: it is no light in the shader.
static func light(
	source: String, x: float, y: float, z: float, scale := 1.0, clock := 0.0
) -> Variant:
	var found: Variant = LIGHTS.get(source)
	if found == null or scale <= 0.0:
		return null
	var d: Dictionary = found
	var base: float = d["strength"]
	var strength: float = base * scale
	var waver: float = d["flicker"]
	if waver > 0.0:
		# A steady pattern per light, not a dice roll: replays look the same.
		strength *= 1.0 - waver * (.5 + .5 * sin(clock * 23.0 + x * 7.1 + y * 3.3))
	var heat := 0.0
	if typeof(d["hot"]) == TYPE_BOOL:
		heat = .4 if d["hot"] else 0.0
	else:
		heat = d["hot"]
	var pool: bool = d["pool"]
	var radius: float = d["radius"]
	var flags := (POOL if pool else 0) | (HOT if heat > 0.0 else 0)
	var colour: Color = d["color"]
	if d.has("blink"):
		# A light bar: `blink` times a second it swaps to `blink_color` (each
		# car on its own beat by where it stands; the clock, never dice).
		var rate: float = d["blink"]
		if fposmod(clock * rate + x * .37 + y * .23, 1.0) >= .5:
			colour = d.get("blink_color", colour)
	return [x, y, z, radius, colour, strength, flags, heat]
