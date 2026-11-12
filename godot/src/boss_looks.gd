## The bosses' looks as a fight wears on (tools/art/build_enemy_actors.gd makes
## the cels): the first beat of a wind-up shows `<kind>_wind` (drawn back,
## gathering; the rest of it is the usual `_aim`), and below half health the
## living cels give way to a battle-damaged set, `<kind>_p2_<cel>`, then below a
## fifth to a worse one, `<kind>_p3_<cel>`. Maw's housecoat catches fire with
## her fight's own phase two (features/mothership.gd); out of it, her bare set's
## beaten cels are `maw_p3_bare_<cel>`. A cel without a variant keeps its name.
## Looks only: nothing here changes play.
class_name BossLooks
extends RefCounted

## Share of health left at or under which each set shows.
const P2_AT := .5
const P3_AT := .2
const P2_AT_KIND := {"maw": 2.0 / 3.0}
## The wind-up cel holds while more than this share of the wind-up is left.
const WIND_SHARE := .5

## The art index's names (Assets sets it when it reads the index).
static var index: Dictionary = {}
## Each winding-up boss's wind-up as it started (by instance id).
static var _wound := {}


## The cel a boss shows instead of `name` (one of its own `<kind>_...` cels).
static func cel(e: Enemy, name: String) -> String:
	if index.is_empty() or not name.begins_with(e.kind + "_"):
		return name
	var rest := name.substr(e.kind.length() + 1)
	if rest == "aim" or rest.ends_with("_aim"):
		var id := e.get_instance_id()
		var full := maxf(float(_wound.get(id, 0.0)), e.windup)
		_wound[id] = full
		var wind := rest.trim_suffix("aim") + "wind"
		if e.windup > full * WIND_SHARE and index.has(e.kind + "_" + wind):
			rest = wind
	elif e.windup <= 0.0:
		_wound.erase(e.get_instance_id())
	var left := e.hp / maxf(1.0, e.max_hp)
	var phase := 3 if left <= P3_AT else 2 if left <= float(P2_AT_KIND.get(e.kind, P2_AT)) else 1
	for p in range(phase, 1, -1):
		var worn := "%s_p%d_%s" % [e.kind, p, rest]
		if index.has(worn):
			return worn
	return e.kind + "_" + rest
