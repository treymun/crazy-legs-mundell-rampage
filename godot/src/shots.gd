## Shots and blasts as data (data/tuning/shots.cfg): how each kind of shot
## falls, how big it is drawn, whether it glows, and the blast it makes when it
## bursts. game_combat.gd moves and bursts them, game_view.gd draws them.
class_name Shots
extends RefCounted

const PATH := "res://data/tuning/shots.cfg"

## kind -> its section's values
static var KINDS := {}
## [blast]: what every blast has unless its kind says otherwise
static var BLAST := {}


static func _static_init() -> void:
	load_tuning()


static func load_tuning() -> void:
	var cfg := Tuning.file(PATH)
	KINDS = {}
	BLAST = {}
	for section in cfg.get_sections():
		var values := {}
		for key in cfg.get_section_keys(section):
			values[key] = cfg.get_value(section, key)
		if section == "blast":
			BLAST = values
		else:
			KINDS[section] = values


static func gravity(kind: String) -> float:
	return _kind(kind).get("gravity", 0.0)


static func size(kind: String, enemy: bool) -> float:
	return _kind(kind).get("size", .14 if enemy else .10)


static func glows(kind: String) -> bool:
	return _kind(kind).get("glow", false)


## It bounces, rolls and rests till its life runs out, as thrown dynamite does.
static func rolls(kind: String) -> bool:
	return _kind(kind).get("rolls", false)


static func explodes(kind: String) -> bool:
	return _kind(kind).get("explodes", false)


## The blast of a kind: [blast] with what the kind's own section sets.
static func blast(kind: String) -> Dictionary:
	var out := BLAST.duplicate()
	out.merge(_kind(kind), true)
	return out


## A kind's own section ({} for a kind without one).
static func _kind(kind: String) -> Dictionary:
	return KINDS.get(kind, {})


## A bowling ball drawn as a solid ball (SolidLayer3D) on the floor, turned
## over by how far it has rolled about the line across its way; each ball
## starts turned its own way (its uid), so the finger holes come round.
static func ball_look(s: View.Sprite, shot: GameState.Shot) -> void:
	const RADIUS := .118
	const LIFT := .22
	s.solid = "ball"
	s.z = shot.z - LIFT + RADIUS
	var start := Basis.from_euler(Vector3(shot.uid * 1.7, shot.uid * 2.3, shot.uid * .9))
	var across := Vector3(-shot.vy, shot.vx, 0.0)
	if across.length_squared() > 1e-6:
		s.turn = Basis(across.normalized(), shot.travelled / RADIUS) * start
	else:
		s.turn = start
