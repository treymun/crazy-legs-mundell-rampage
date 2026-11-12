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
## By kind and cel name, what cel() needs (_row()), for an index of this size.
static var _rows := {}
static var _index_size := -1


## The cel a regular enemy shows instead of `name` (one of its own `<kind>_...` cels).
static func cel(e: Enemy, name: String) -> String:
	if Assets.shared_index.size() != _index_size:
		# The pictures known changed (a chapter's pack came in): look again.
		_index_size = Assets.shared_index.size()
		_rows = {}
	if _index_size == 0:
		return name
	var by_kind = _rows.get(e.kind)
	if by_kind == null:
		by_kind = {}
		_rows[e.kind] = by_kind
	var row = by_kind.get(name)
	if row == null:
		row = _row(e.kind, name)
		by_kind[name] = row
	if row.is_empty():
		return name
	var id := e.get_instance_id()
	var wind := false
	if row[0]:
		var full := maxf(float(_wound.get(id, 0.0)), e.windup)
		_wound[id] = full
		wind = e.windup > full * WIND_SHARE and row[3] != ""
	elif e.windup <= 0.0 and not _wound.is_empty():
		_wound.erase(id)
	var hurt := e.hp <= e.max_hp * HURT_AT
	if wind:
		return row[4] if hurt and row[4] != "" else row[3]
	return row[2] if hurt and row[2] != "" else row[1]


## What cel() needs to know of `name` for `kind`, worked out once: [the cel is
## the aim, its own name, its hurt copy, the wind-up cel, the wind-up's hurt
## copy] ("" where there is no such picture), or [] when it is not the kind's.
static func _row(kind: String, name: String) -> Array:
	if not name.begins_with(kind + "_"):
		return []
	var rest := name.substr(kind.length() + 1)
	var wind := kind + "_wind"
	var hurt := "%s_hurt_%s" % [kind, rest]
	var hurt_wind := "%s_hurt_wind" % kind
	var has: Dictionary = Assets.shared_index
	return [
		rest == "aim",
		kind + "_" + rest,
		hurt if has.has(hurt) else "",
		wind if has.has(wind) else "",
		hurt_wind if has.has(hurt_wind) else "",
	]
