## COUNTY RUN's QUARRY (CLAUDE.md "County Run", COUNTY_RUN.md): Stillwater
## Cut from chapter 4 (quarry_plan.gd) with its story stripped and every door
## open (county_kit.gd), reworked for an endless fight. The haul road climbs
## from the weigh station to the cut yard as before; now the weigh station
## also opens east into the floor of the lower cut, a new ramp comes down from
## the cut yard's southwest corner into the weigh station, and the cut yard
## runs straight on into the condenser yard: three loops round the haul road
## and the terraces. A catwalk crosses the lower cut over the flooded pit
## (stairs up from its west floor, down onto its east bench): the elevated
## route, with the pit's open floor under it to circle a horde in. The
## chalk terraces, the still house, the crusher and the bottling works stand
## as the chapter built them, every door open.
##
## Built by tools/levels/build_level.gd -- county_quarry.
extends RefCounted

const Base := preload("res://tools/levels/quarry_plan.gd")
const Kit := preload("res://tools/levels/county_kit.gd")
const Geo := preload("res://tools/levels/geo_kit.gd")
## The catwalk's deck height, and the cut yard's bench height (the west ramp).
const CATWALK := 1.2
const BENCH := .4

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
		"county_quarry",
		"THE QUARRY",
		"SURVIVE. THE PIT, THE RAMP AND THE CATWALK ALL GO THROUGH NOW."
	)
	shortcuts()
	catwalk()
	landmarks()
	return [62.5, 46.5, -PI / 2]


func shortcuts() -> void:
	# The weigh station's east wall into the floor of the lower cut.
	Kit.open_cells(b, 93, 66, 95, 68, Vector2i(92, 67))
	Kit.clear_fixtures(b, 93, 66, 95, 68)
	Kit.clear_things(b, 92, 65, 96, 69)
	# The cut yard's southwest corner down a ramp into the weigh station: a
	# landing at the yard's height, then the slope to the station's floor.
	Kit.open_cells(b, 36, 60, 40, 62, Vector2i(35, 61))
	Kit.open_cells(b, 36, 63, 40, 67, Vector2i(40, 68))
	Kit.clear_fixtures(b, 36, 60, 40, 67)
	Kit.clear_things(b, 35, 59, 41, 68)
	Geo.ramp(
		b,
		"west_ramp",
		[36, 63, 41, 68],
		0.0,
		BENCH,
		"n",
		{"tile": "quarry_dust", "edge": "quarry_face"}
	)
	# The cut yard straight into the condenser yard.
	Kit.open_cells(b, 93, 31, 93, 32, Vector2i(94, 31))
	Kit.clear_fixtures(b, 93, 31, 93, 32)
	Kit.clear_things(b, 92, 30, 94, 33)


## The catwalk over the lower cut: up from its west floor, across over the
## flooded pit, down onto its east bench.
func catwalk() -> void:
	Kit.clear_fixtures(b, 96, 43, 124, 46)
	Kit.clear_things(b, 96, 43, 124, 46)
	Geo.stairs(b, "catwalk_west", [96, 44, 99, 46], 0.0, CATWALK, "e", {"tile": "steel_mesh"})
	Geo.bridge(
		b, "catwalk", [99, 44, 121, 46], CATWALK, {"tile": "steel_mesh", "edge": "steel_mesh"}
	)
	Geo.stairs(b, "catwalk_east", [121, 44, 124, 46], 0.0, CATWALK, "w", {"tile": "steel_mesh"})
	b.town("lantern_post", 110.5, 44.3, {"z": CATWALK})


func landmarks() -> void:
	b.label("CATWALK", 110, 43)
	b.label("WEST RAMP", 38, 64)
	b.label("PIT GATE", 94, 67)
