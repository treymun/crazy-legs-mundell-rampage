## The feed barn's hay loft in Hickston (level format 2, layout 4): a plank
## floor up under the rafters on the barn's posts, stairs up its south side,
## railed along its open edges, with the feed stored under it in the shade.
## It took the place of a platform two steps up; hickston_cast.gd puts the
## loft's alien, shells and rinds up on it.
extends RefCounted

const Geo := preload("res://tools/levels/geo_kit.gd")
## Its top.
const LOFT := 1.55


static func build(b, barn: int) -> void:
	# The hay loft at the back: a plank floor up under the rafters on the
	# barn's posts, stairs up its south side, railed along its open edges; the
	# feed and tack stored under it in the shade.
	(
		Geo
		. balcony(
			b,
			"hay_loft",
			[41, 2, 49, 9.6],
			LOFT,
			"es",
			{
				"tile": "porch",
				"under": "joists",
				"edge": "barn",
				"light": .62,
				"area": barn,
				"gaps": [["s", 6.0, 7.7]],
				"rail": {"tile": "stockyard"},
			}
		)
	)
	Geo.stairs(
		b,
		"loft_stairs",
		[47.0, 9.6, 48.7, 14.0],
		0.0,
		LOFT,
		"n",
		{"tile": "porch", "edge": "barn", "area": barn}
	)
	for at: Vector2 in [Vector2(44.95, 9.45), Vector2(48.85, 5.0), Vector2(48.85, 2.2)]:
		# Posts under its open edges.
		Geo.wall(
			b,
			"loft_post_%d_%d" % [int(at.x * 10), int(at.y * 10)],
			at,
			at + Vector2(.01, 0),
			0.0,
			LOFT - .15,
			{"thick": .18, "tile": "barn"}
		)
	b.lighten(41, 2, 48, 9, .5)
	for p in [Vector2(42.0, 2.8), Vector2(43.2, 2.7), Vector2(44.4, 2.9), Vector2(46.8, 3.0)]:
		b.board("prop_hay", p.x, p.y, .92, {"z": LOFT})
	for c in [Vector2(45.5, 5.5), Vector2(42.5, 6.5)]:
		# Bales up on the loft.
		b.fixture(c.x - .42, c.y - .3, c.x + .42, c.y + .3, LOFT + .62, "feed", "counter_top", LOFT)
	# Under it: sacked feed against the back wall.
	b.fixture(41.18, 2.3, 42.02, 2.9, .62, "feed", "counter_top")
	b.town("pallet_stack", 46.6, 2.9, {"solid": .35})
