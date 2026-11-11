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

## source -> {color, radius, strength, life, flicker, height}
static var LIGHTS := {}
## tile name -> Vector2(threshold, light)
static var GLOW := {}
## level id -> its mood (fog, grade, clouds, lightning, crows, fireflies)
static var LEVELS := {}
## tile name -> {mode, rate, depth}: tiles that move
static var ANIMS := {}
## [debris]: how long the leavings of a fight last
static var DEBRIS := {}
## The shader takes this many moving tiles.
const MAX_ANIMS := 8
## Goes up on every reload, so the tile atlas knows to bake its glows again.
static var version := 0
## LIGHTS AND GLOW (main_state.gd); the comparison tour turns it off too.
static var enabled := true


static func _static_init() -> void:
	load_tuning()


static func load_tuning() -> void:
	var cfg := Tuning.file(PATH)
	LIGHTS = {}
	GLOW = {}
	LEVELS = {}
	ANIMS = {}
	DEBRIS = {}
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
		if section.begins_with("light."):
			var d := {
				"color": Color(1, 1, 1),
				"radius": 3.0,
				"strength": 1.0,
				"life": 0.0,
				"flicker": 0.0,
				"height": 1.0
			}
			for key in cfg.get_section_keys(section):
				d[key] = cfg.get_value(section, key)
			LIGHTS[section.substr(6)] = d
		elif section == "glow":
			for key in cfg.get_section_keys(section):
				GLOW[key] = cfg.get_value(section, key)
	version += 1


## A level's mood value, or `fallback` for a level effects.cfg does not name.
static func mood(level_id: String, key: String, fallback):
	return LEVELS.get(level_id, {}).get(key, fallback)


## One light of `source` at x, y, z, its strength scaled by `scale` (fading,
## a flash dying away): [x, y, z, radius, Color, strength], or null.
static func light(source: String, x: float, y: float, z: float, scale := 1.0, clock := 0.0):
	var d = LIGHTS.get(source)
	if d == null or scale <= 0.0:
		return null
	var strength: float = float(d["strength"]) * scale
	var waver := float(d["flicker"])
	if waver > 0.0:
		# A steady pattern per light, not a dice roll: replays look the same.
		strength *= 1.0 - waver * (.5 + .5 * sin(clock * 23.0 + x * 7.1 + y * 3.3))
	return [x, y, z, float(d["radius"]), d["color"], strength]
