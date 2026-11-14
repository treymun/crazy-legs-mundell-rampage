## COUNTY RUN's HICKSTON (CLAUDE.md "County Run", COUNTY_RUN.md): the town
## of chapter 1 (hickston_plan.gd) with its story stripped and every door
## open (county_kit.gd), reworked for an endless fight. Main Street's
## storefronts and the blocks either side, alleys and backyards between them,
## the saloon, the barn and the feed store all go through; the dry creek's
## south fence is down, so it is a way round rather than a dead end; the
## stockyard opens into the rodeo, the rodeo into the trailer court and the
## court into the motel strip, three loops where the chapter had one road in.
## A footbridge crosses Main Street (stairs up on the west side from the
## south, down on the east side to the north): a perch over the busiest
## street, with two ways off it. The wide lower road and the court are the
## open ground to circle a horde in; the alleys and the creek are the tight
## ways out.
##
## Built by tools/levels/build_level.gd -- county_hickston.
extends RefCounted

const Base := preload("res://tools/levels/hickston_plan.gd")
const Kit := preload("res://tools/levels/county_kit.gd")
const Geo := preload("res://tools/levels/geo_kit.gd")
## The footbridge's deck height.
const BRIDGE := 2.2

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
		"county_hickston",
		"HICKSTON",
		"SURVIVE. THE CREEK, THE RODEO AND THE COURT ALL GO THROUGH NOW."
	)
	shortcuts()
	footbridge()
	landmarks()
	return [60.5, 40.5, -PI / 2]


## The new ways through: each turns a dead end or a one-way district into a
## loop.
func shortcuts() -> void:
	# The dry creek's south fence: the creek bed runs on into the lower road.
	for x in range(1, 13):
		Kit.open_cells(b, x, 62, x, 62, Vector2i(x, 61))
	Kit.clear_fixtures(b, 1, 62, 12, 62)
	# The stockyard's east fence into the rodeo grounds.
	Kit.open_cells(b, 95, 17, 95, 20, Vector2i(96, 18))
	Kit.clear_fixtures(b, 95, 17, 95, 20)
	# The rodeo's south rail into the trailer court.
	Kit.open_cells(b, 107, 22, 110, 22, Vector2i(108, 23))
	Kit.clear_fixtures(b, 107, 22, 110, 22)
	# The court's south fence into the motel strip and down to the lower road.
	Kit.open_cells(b, 106, 47, 109, 47, Vector2i(107, 48))
	Kit.clear_fixtures(b, 106, 47, 109, 47)
	Kit.clear_things(b, 106, 46, 109, 48)
	Kit.clear_things(b, 107, 21, 110, 23)
	Kit.clear_things(b, 94, 17, 96, 20)


## A footbridge over Main Street: the deck across at BRIDGE, railed both
## sides, stairs up on the west side from the south and down on the east
## side to the north. The street runs on under it.
func footbridge() -> void:
	# Railed along both long sides, left open where each flight comes up.
	Geo.balcony(
		b,
		"footbridge",
		[56, 51, 65, 53],
		BRIDGE,
		"ns",
		{"tile": "porch", "edge": "porch", "gaps": [["s", 0.0, 2.0], ["n", 7.0, 9.0]]}
	)
	Geo.stairs(b, "footbridge_west", [56, 53, 58, 58], 0.0, BRIDGE, "n", {"tile": "porch"})
	Geo.stairs(b, "footbridge_east", [63, 46, 65, 51], 0.0, BRIDGE, "s", {"tile": "porch"})
	b.town("lantern_post", 60.5, 51.25, {"z": BRIDGE})


func landmarks() -> void:
	# Lamps at each new way through, and burn barrels on the open ground.
	for at: Vector2 in [
		Vector2(12.5, 63.4),
		Vector2(96.5, 16.5),
		Vector2(106.4, 23.4),
		Vector2(111.6, 23.4),
		Vector2(105.4, 48.4),
		Vector2(110.6, 48.4)
	]:
		b.town("lantern_post", at.x, at.y)
	b.town("burn_barrel", 50.5, 68.5)
	b.town("burn_barrel", 94.5, 30.5)
	b.label("FOOTBRIDGE", 60, 50)
	b.label("CREEK RUN", 6, 60)
	b.label("RODEO GATE", 108, 21)
	b.label("COURT GATE", 107, 46)
