## Lights and glows as data (data/tuning/effects.cfg): which sources light up
## the world around them, in what colour and how far, and which tiles glow.
## Game.effect_lights() lists this frame's lights from them, scene_layers.gd
## hands them to palette.gdshader, and bakes the glows into the tile atlas.
## Only the graphics-card view draws them (CLAUDE.md: one renderer).
class_name Effects
extends RefCounted

const PATH := "res://data/tuning/effects.cfg"
## As many lights as the shader takes in one frame; the nearest win.
const MAX_LIGHTS := 16
## Bits of a light's flags (its seventh value): it pools on the ground under
## it, and the air above it shimmers (palette.gdshader light_flags, haze).
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
## [debris]: how long the leavings of a fight last
static var DEBRIS := {}
## tile name -> 0..1: [water] (ripples and a broken reflection), [relief]
## (raised where a texel is brighter than its neighbours) and [puddles] (floors
## that gather puddles in the rain).
static var WATER := {}
static var RELIEF := {}
static var PUDDLES := {}
## image name -> light source: the props a light stands on ([light.*] props).
static var PROP_LIGHTS := {}
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
	DEBRIS = {}
	WATER = {}
	RELIEF = {}
	PUDDLES = {}
	PROP_LIGHTS = {}
	var tables := {"water": WATER, "relief": RELIEF, "puddles": PUDDLES, "glow": GLOW}
	for section in cfg.get_sections():
		var values := {}
		for key in cfg.get_section_keys(section):
			values[key] = cfg.get_value(section, key)
		if section.begins_with("level."):
			LEVELS[section.substr(6)] = values
		elif section.begins_with("anim."):
			ANIMS[section.substr(5)] = values
		elif section == "debris":
			DEBRIS = values
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
			for image in d["props"]:
				PROP_LIGHTS[String(image)] = source
	version += 1


## A level's mood value, or `fallback` for a level effects.cfg does not name.
static func mood(level_id: String, key: String, fallback):
	return LEVELS.get(level_id, {}).get(key, fallback)


## One light of `source` at x, y, z, its strength scaled by `scale` (fading,
## a flash dying away): [x, y, z, radius, Color, strength, flags, heat], or
## null; heat is how wide the air above it shimmers, in cells (`hot`: true is
## .4). A source of strength 0 only shimmers: it is no light in the shader.
static func light(source: String, x: float, y: float, z: float, scale := 1.0, clock := 0.0):
	var d = LIGHTS.get(source)
	if d == null or scale <= 0.0:
		return null
	var strength: float = float(d["strength"]) * scale
	var waver := float(d["flicker"])
	if waver > 0.0:
		# A steady pattern per light, not a dice roll: replays look the same.
		strength *= 1.0 - waver * (.5 + .5 * sin(clock * 23.0 + x * 7.1 + y * 3.3))
	var heat := 0.0
	if typeof(d["hot"]) == TYPE_BOOL:
		heat = .4 if d["hot"] else 0.0
	else:
		heat = float(d["hot"])
	var flags := (POOL if bool(d["pool"]) else 0) | (HOT if heat > 0.0 else 0)
	return [x, y, z, float(d["radius"]), d["color"], strength, flags, heat]
