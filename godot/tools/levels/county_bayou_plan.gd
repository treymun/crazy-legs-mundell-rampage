## COUNTY RUN's GATOR BAYOU (CLAUDE.md "County Run", COUNTY_RUN.md): Gator
## Bayou from chapter 5 (bayou_plan.gd) with its story stripped and every
## door open (county_kit.gd), reworked for an endless fight. The deep channel
## that splits the swamp north from south had three ways over; now plank
## causeways (laid on the water as the chapter's own bridges are, since
## nobody steps off a deck into deep water) also cross it west of the
## lagoon, and run out to the lagoon island from both shores, so the island
## shack is a crossroads instead of a cul-de-sac. Two raised boardwalks
## stand over the open shallows south and east (stairs up at each end, high
## enough to walk under): the elevated routes over the muck. The shacks on
## stilts, the muddy trails and the wide shallow water to circle in stand as
## the chapter built them, every door open.
##
## Built by tools/levels/build_level.gd -- county_bayou.
extends RefCounted

const Base := preload("res://tools/levels/bayou_plan.gd")
const Kit := preload("res://tools/levels/county_kit.gd")
const Geo := preload("res://tools/levels/geo_kit.gd")
## The boardwalks' height: high enough to walk under (a body is 1.12 tall).
const WALK := 1.4

var base
var b


func make():
	base = Base.new()
	b = base.make()
	return b


func build(_b) -> Array:
	base.build(b)
	Kit.strip(
		b,
		"county_bayou",
		"GATOR BAYOU",
		"SURVIVE. NEW PLANKS CROSS THE DEEP WATER AND TWO BOARDWALKS STAND OVER THE MUCK."
	)
	causeways()
	boardwalks()
	landmarks()
	return [24.5, 11.5, 0.0]


## Planks laid over the deep water, at the shallows' height.
func planks(x0: int, y0: int, x1: int, y1: int) -> void:
	b.paint(x0, y0, x1, y1, "bayou_planks")
	b.raise(x0, y0, x1, y1, 0.0)
	Kit.clear_fixtures(b, x0, y0, x1, y1)
	Kit.clear_things(b, x0, y0, x1, y1)


func causeways() -> void:
	# Across the deep channel west of the lagoon.
	planks(29, 37, 31, 42)
	# Out to the lagoon island from the west shore and from the east.
	planks(41, 35, 46, 36)
	planks(79, 35, 84, 36)


## Two raised boardwalks over the open shallows, stairs at each end, and
## four raised crossings over the deep water (a deck over deep water is dry
## ground: level_geometry.gd can_walk).
func boardwalks() -> void:
	_boardwalk("high_walk", 12, 44, 84)
	_boardwalk("east_walk", 100, 121, 69)
	_crossing("west_crossing", 22, 37, 42)
	_crossing("island_north", 66, 27, 30)
	_crossing("island_south", 65, 43, 46)
	_crossing("east_crossing", 108, 37, 42)


## A raised walk two cells wide over the deep rows y0..y1 at column x, stairs
## up from the dry ground at each end.
func _crossing(id: String, x: int, y0: int, y1: int) -> void:
	var top := .8
	Kit.clear_fixtures(b, x, y0 - 3, x + 1, y1 + 3)
	Kit.clear_things(b, x - 1, y0 - 3, x + 2, y1 + 3)
	Geo.bridge(b, id, [x, y0, x + 2, y1 + 1], top, {"tile": "bayou_planks", "edge": "bayou_planks"})
	var north := float(b.ground[b.at(x, y0 - 4)])
	var south := float(b.ground[b.at(x, y1 + 4)])
	Geo.stairs(b, id + "_n", [x, y0 - 3, x + 2, y0], north, top, "s", {"tile": "bayou_planks"})
	Geo.stairs(b, id + "_s", [x, y1 + 1, x + 2, y1 + 4], south, top, "n", {"tile": "bayou_planks"})


## A boardwalk from x0 to x1 two cells wide from row y, stairs up from the
## water at both ends.
func _boardwalk(id: String, x0: int, x1: int, y: int) -> void:
	Kit.clear_fixtures(b, x0 - 3, y, x1 + 2, y + 1)
	Kit.clear_things(b, x0 - 3, y - 1, x1 + 3, y + 2)
	Geo.bridge(b, id, [x0, y, x1, y + 2], WALK, {"tile": "bayou_planks", "edge": "bayou_planks"})
	# Each flight starts from the floor at its foot (shallow water lies lower
	# than mud).
	var west_foot := float(b.ground[b.at(x0 - 4, y)])
	var east_foot := float(b.ground[b.at(x1 + 3, y)])
	Geo.stairs(
		b, id + "_west", [x0 - 3, y, x0, y + 2], west_foot, WALK, "e", {"tile": "bayou_planks"}
	)
	Geo.stairs(
		b, id + "_east", [x1, y, x1 + 3, y + 2], east_foot, WALK, "w", {"tile": "bayou_planks"}
	)
	b.town("lantern_post", (x0 + x1) * .5, y + .25, {"z": WALK})


func landmarks() -> void:
	# Lamps at the causeways' ends; a camp on the mud flat where a run starts.
	for at: Vector2 in [
		Vector2(40.4, 34.6), Vector2(47.4, 34.6), Vector2(78.4, 34.6), Vector2(85.6, 34.6)
	]:
		b.town("lantern_post", at.x, at.y)
	b.town("burn_barrel", 27.5, 9.5)
	b.town("camp_chairs", 26.0, 10.8)
	b.label("MUD FLAT CAMP", 26, 8)
	b.label("WEST PLANKS", 30, 39)
	b.label("ISLAND CAUSEWAY", 43, 34)
	b.label("ISLAND CAUSEWAY", 81, 34)
	b.label("HIGH WALK", 28, 83)
	b.label("EAST WALK", 110, 68)
	b.label("WEST CROSSING", 23, 36)
	b.label("EAST CROSSING", 109, 36)
