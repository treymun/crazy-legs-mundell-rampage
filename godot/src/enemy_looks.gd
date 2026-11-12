## The regular hands' looks as a fight wears on them (tools/art/build_enemy_actors.gd
## makes the cels): the first beat of a wind-up shows `<kind>_wind` (drawn back,
## racking, revving, rearing; the rest of it is the usual `_aim`), and below half
## health every living cel gives way to its hurt copy, `<kind>_hurt_<cel>`
## (bloodied, torn, limping; tin dented and sparking). A cel without a variant
## keeps its name, so a kind drawn before the hurt pass looks as it did. Bosses
## have their own (BossLooks). Looks only: nothing here changes play.
class_name EnemyLooks
extends RefCounted

## Share of health left at or under which the hurt set shows.
const HURT_AT := .5
## The wind-up cel holds while more than this share of the wind-up is left.
const WIND_SHARE := .5

## Each winding-up hand's wind-up as it started (by instance id).
static var _wound := {}


## The cel a regular enemy shows instead of `name` (one of its own `<kind>_...` cels).
static func cel(e: Enemy, name: String) -> String:
	if Assets.shared_index.is_empty() or not name.begins_with(e.kind + "_"):
		return name
	var rest := name.substr(e.kind.length() + 1)
	var id := e.get_instance_id()
	if rest == "aim":
		var full := maxf(float(_wound.get(id, 0.0)), e.windup)
		_wound[id] = full
		if e.windup > full * WIND_SHARE and Assets.shared_index.has(e.kind + "_wind"):
			rest = "wind"
	elif e.windup <= 0.0 and not _wound.is_empty():
		_wound.erase(id)
	if e.hp <= e.max_hp * HURT_AT:
		var hurt := "%s_hurt_%s" % [e.kind, rest]
		if Assets.shared_index.has(hurt):
			return hurt
	return e.kind + "_" + rest
