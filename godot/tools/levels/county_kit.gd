## What every COUNTY RUN map does to the chapter plan it is built on
## (county_<chapter>_plan.gd; CLAUDE.md "County Run", COUNTY_RUN.md): the
## story goes (its hands, pickups, stations, triggers, waves, the exit, the
## road back to the Crossroads, the boss arenas), every door is unlocked and
## stands open (keys, station-worked and secret doors alike, so interiors
## connect), and the plan's own helpers here cut new ways through walls and
## fences, lay raised walkways and mark landmarks on the automap.
##
## The chapter plans stay as they are: a survival map is the chapter's
## ground reworked, built to its own level file (data/county_<chapter>.json)
## by `build_level.gd -- county_<chapter>`.
extends RefCounted

const Geo := preload("res://tools/levels/geo_kit.gd")

## Meta keys that belong to a chapter's story, never to a survival map.
const STORY_META := [
	"extraction",
	"return_gate",
	"wave",
	"boss_arena",
	"rescue",
	"recovery_room",
	"pressure_ports",
	"control_name",
	"objective_side_tasks",
	"devices",
	"boss_decoys",
	"lap_cars",
	"tactical",
	"gallery",
	"hub_gates",
	"hub_clues",
	"hub_board",
	"map_window",
]


## The chapter's story off plan `b`, renamed `id`, titled `title`.
static func strip(b, id: String, title: String, intro: String) -> void:
	b.id = id
	b.enemies = []
	b.patrols = {}
	b.pickups = []
	b.stations = []
	b.notes = []
	b.triggers = []
	b.exchanges = []
	b.partners = []
	b.controlled_doors = []
	b.access_doors = {}
	b.hidden_rooms = []
	for d: Dictionary in b.doors:
		d["key"] = ""
		d["secret"] = false
		d["blast_only"] = false
		d["opened"] = true
		d["progress"] = 1
		d["id"] = ""
	for key: String in STORY_META:
		b.meta.erase(key)
	b.meta["title"] = title
	b.meta["heading"] = ["COUNTY RUN", title]
	b.meta["intro"] = intro
	b.meta["ending"] = ""
	b.meta["layout"] = 1


## Cells x0..x1, y0..y1 (both inside) opened up like the cell `like`: its
## floor, ceiling, ground, roof, light and district (a way cut through a wall,
## a fence or a hedge).
static func open_cells(b, x0: int, y0: int, x1: int, y1: int, like: Vector2i) -> void:
	var j: int = b.at(like.x, like.y)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var i: int = b.at(x, y)
			b.solid[i] = -1
			b.floor_tile[i] = b.floor_tile[j]
			b.ceiling[i] = b.ceiling[j]
			b.ground[i] = b.ground[j]
			b.roof[i] = b.roof[j]
			b.light[i] = b.light[j]
			b.area[i] = b.area[j]
			b.skin[i] = -1
			b.banded[i] = false


## Drops every fixture whose box overlaps cells x0..x1, y0..y1 (a gap cut
## where a post or a crate stood).
static func clear_fixtures(b, x0: float, y0: float, x1: float, y1: float) -> void:
	var kept: Array = []
	for f: Array in b.fixtures:
		if (
			float(f[2]) > x0
			and float(f[0]) < x1 + 1.0
			and float(f[3]) > y0
			and float(f[1]) < y1 + 1.0
		):
			continue
		kept.append(f)
	b.fixtures = kept


## Drops props, boards and scenery standing in cells x0..x1, y0..y1.
static func clear_things(b, x0: float, y0: float, x1: float, y1: float) -> void:
	var box := Rect2(x0, y0, x1 - x0 + 1.0, y1 - y0 + 1.0)
	for list_name: String in ["props", "billboards", "scenery"]:
		var kept: Array = []
		for thing in b.get(list_name):
			var at := _where(thing)
			if at != Vector2.INF and box.has_point(at):
				continue
			kept.append(thing)
		b.set(list_name, kept)


static func _where(thing) -> Vector2:
	if thing is Dictionary:
		if thing.has("x") and thing.has("y"):
			return Vector2(float(thing["x"]), float(thing["y"]))
		return Vector2.INF
	if thing is Array and thing.size() >= 3:
		return Vector2(float(thing[1]), float(thing[2]))
	return Vector2.INF


## A raised walkway: a deck `rect` at `top`, railed on the `open` sides, with
## stairs up from the ground at each end in `ups` ([rect, toward]).
static func walkway(
	b, id: String, rect: Array, top: float, open: String, ups: Array, o := {}
) -> void:
	Geo.balcony(b, id, rect, top, open, o)
	for k in ups.size():
		var up: Array = ups[k]
		Geo.stairs(
			b, "%s_up%d" % [id, k], up[0], 0.0, top, String(up[1]), {"tile": o.get("tile", "porch")}
		)
