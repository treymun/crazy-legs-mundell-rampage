## The moment a breakable breaks, besides its real pieces (features/wreckage.gd
## owns this): the fine debris by what it is made of (wreck_debris.gd: wood
## splinters, glass and clay shards and glints, tin slivers, straw, foam and
## stuffing crumbs, plastic chips) thrown from where it was struck, a dust
## puff (features/dust.gd) off what makes dust, and a second sound by what
## it is made of and how hard it went (wood splinters under buckshot, glass
## and clay shards rain down, tin tears, hay bursts: ElevenLabs, pass 11).
## A shot that does not break it knocks a few chips off where it struck.
## Colours: the thing's own (a few texels of its texture, kept a source) and
## the raw stuff's (fresh wood, a glint).
##
## Looks only: wreckage's own dice.
extends RefCounted

const Breakables := preload("res://src/features/breakables.gd")
## Each stuff's bits: [count, more for each 1 of force, long, wide, thin
## (cells, each as a range lo..hi of its long), drag, bounce, life lo, hi]
const BITS := {
	"wood": [8, 12, Vector2(.05, .12), .2, .12, .3, .3, 7.0, 11.0],
	"char": [8, 10, Vector2(.04, .1), .25, .15, .3, .3, 7.0, 11.0],
	"glass": [12, 12, Vector2(.02, .05), .8, .12, .2, .4, 4.0, 7.0],
	"clay": [10, 10, Vector2(.025, .06), .75, .3, .2, .3, 6.0, 9.0],
	"tin": [6, 6, Vector2(.03, .07), .35, .08, .2, .45, 6.0, 9.0],
	"iron": [4, 4, Vector2(.03, .06), .3, .1, .2, .45, 6.0, 9.0],
	"straw": [16, 14, Vector2(.06, .12), .07, .05, 3.5, .1, 8.0, 12.0],
	"stuffing": [10, 8, Vector2(.025, .04), .9, .7, 3.0, .1, 7.0, 10.0],
	"plastic": [6, 6, Vector2(.02, .045), .7, .2, .4, .35, 6.0, 9.0],
	"rubber": [6, 4, Vector2(.03, .05), .8, .1, 1.5, .2, 5.0, 8.0],
	"goo": [6, 6, Vector2(.02, .04), .9, .5, .3, .1, 5.0, 8.0],
}
## The raw stuff's own colours (0..255), mixed with the thing's.
const RAW := {
	"wood": [Color8(206, 160, 102), Color8(180, 132, 80), Color8(150, 104, 62)],
	"char": [Color8(48, 34, 24), Color8(30, 22, 16), Color8(120, 52, 20)],
	"glass": [Color8(172, 216, 198), Color8(226, 238, 230), Color8(120, 170, 150)],
	"clay": [Color8(184, 110, 70), Color8(204, 150, 104)],
	"tin": [Color8(178, 178, 168), Color8(122, 122, 114)],
	"iron": [Color8(70, 64, 58), Color8(122, 66, 38)],
	"straw": [Color8(214, 180, 84), Color8(176, 136, 56), Color8(232, 204, 120)],
	"stuffing": [Color8(232, 228, 214), Color8(210, 204, 190)],
	"plastic": [Color8(222, 218, 204)],
	"rubber": [],
	"goo": [Color8(96, 180, 64), Color8(140, 210, 90)],
}
## What puffs up dust when it breaks.
const DUSTY := ["wood", "char", "straw", "stuffing", "clay", "plastic"]
## A second sound by stuff: [cue, loudness, the least force it sounds at].
const LAYER := {
	"wood": ["break_splinter", .6, .75],
	"char": ["break_splinter", .5, .5],
	"glass": ["shard_rain", .5, 0.0],
	"clay": ["shard_rain", .45, 0.0],
	"tin": ["tin_tear", .55, 0.0],
	"iron": ["tin_tear", .4, 0.0],
	"straw": ["straw_burst", .55, 0.0],
	"stuffing": ["straw_burst", .4, 0.0],
	"plastic": ["can_kick", .3, .8],
}
## Chips a struck (not broken) thing throws at most in a tick.
const CHIPS_TICK := 10

## The thing's own colours, kept by source.
static var _colours := {}

var game: Game
var debris: WreckDebris
var dice: RandomNumberGenerator
var _chip_clock := -1.0
var _chips := 0


func _init(p_game: Game, p_debris: WreckDebris, p_dice: RandomNumberGenerator) -> void:
	game = p_game
	debris = p_debris
	dice = p_dice


## A break: its fine debris, its dust and its second sound.
func broke(p: Breakables.Piece, hit: Object, material: String) -> void:
	var force: float = hit.get("force")
	var at: Vector3 = hit.get("at")
	var row: Array = BITS.get(material, BITS["wood"])
	var base: int = row[0]
	var more: int = row[1]
	var count := base + int(more * force)
	var colours := _palette(p, material)
	for k in count:
		_bit(p, hit, row, colours, 1.0)
	if DUSTY.has(material):
		var dust: Object = game.features.get("dust")
		if dust != null:
			var foot: float = game.world.stand(p) + p.z
			for k in 2 + int(force * 2.0):
				var spot := Vector3(
					p.x + dice.randf_range(-.25, .25) * p.radius * 2.0,
					p.y + dice.randf_range(-.25, .25) * p.radius * 2.0,
					foot + p.height * dice.randf_range(.2, .7)
				)
				var drift := Vector3(
					dice.randf_range(-.3, .3), dice.randf_range(-.3, .3), dice.randf_range(.1, .4)
				)
				var size := clampf(p.height * .35, .12, .4) * dice.randf_range(.8, 1.3)
				dust.call("_add", "dust", spot, drift, dice.randf_range(.9, 1.6), size, .25)
	var layer: Array = LAYER.get(material, [])
	var cue2 := str(p.spec.get("cue2", ""))
	if not layer.is_empty():
		var cue := str(layer[0])
		var loud: float = layer[1]
		var least: float = layer[2]
		if force >= least and cue != cue2:
			game.sound_at(cue, at.x, at.y, loud * clampf(force, .6, 1.3))


## A shot that did not break it: a few chips off where it struck, back the
## way the shot came and out to the sides.
func chips(p: Breakables.Piece, hit: Object, material: String) -> void:
	if game.clock != _chip_clock:
		_chip_clock = game.clock
		_chips = 0
	if _chips >= CHIPS_TICK:
		return
	var row: Array = BITS.get(material, BITS["wood"])
	var colours := _palette(p, material)
	var n := mini(3, CHIPS_TICK - _chips)
	_chips += n
	for k in n:
		_bit(p, hit, row, colours, -.6)


## One bit off `p`: from where it was struck, its slab and colour by its
## stuff's row, thrown `along` times the push (below 0: back at the shooter).
func _bit(p: Breakables.Piece, hit: Object, row: Array, colours: Array, along: float) -> void:
	var at: Vector3 = hit.get("at")
	var way: Vector3 = hit.get("way")
	var force: float = hit.get("force")
	var blast: bool = hit.get("blast")
	var b := WreckDebris.Bit.new()
	var long: Vector2 = row[2]
	var wide: float = row[3]
	var thin: float = row[4]
	var life_lo: float = row[7]
	var life_hi: float = row[8]
	var l := dice.randf_range(long.x, long.y) * clampf(p.height, .6, 1.6)
	b.size = Vector3(l, maxf(.004, l * wide * dice.randf_range(.6, 1.2)), maxf(.004, l * thin))
	b.drag = row[5]
	b.bounce = row[6]
	b.life = dice.randf_range(life_lo, life_hi)
	b.colour = colours[dice.randi() % colours.size()]
	var spread := p.radius * .5
	b.p = (
		at
		+ Vector3(
			dice.randf_range(-spread, spread),
			dice.randf_range(-spread, spread),
			dice.randf_range(-.1, .1)
		)
	)
	var floor_z := Tumble.floor_at(game.world, b.p.x, b.p.y, b.p.z + .1)
	b.p.z = maxf(b.p.z, floor_z + .02)
	var rand := Vector3(dice.randf_range(-1, 1), dice.randf_range(-1, 1), dice.randf_range(-.3, 1))
	var push := way * along * force * dice.randf_range(1.0, 4.0)
	if blast:
		var from: Vector3 = hit.get("from")
		push = (b.p - from).normalized() * force * dice.randf_range(2.0, 6.0)
	b.v = push + rand * force * dice.randf_range(1.0, 2.6)
	b.v.z = absf(b.v.z) + force * dice.randf_range(.8, 2.6)
	b.axis = Vector3(dice.randf_range(-1, 1), dice.randf_range(-1, 1), dice.randf_range(-1, 1))
	if b.axis.length() < .1:
		b.axis = Vector3(0, 0, 1)
	b.axis = b.axis.normalized()
	b.spin = dice.randf_range(8.0, 28.0)
	b.angle = dice.randf() * TAU
	debris.add(b)


## A few of the thing's own colours (its texture's, kept by source) and its
## raw stuff's, for its bits.
func _palette(p: Breakables.Piece, material: String) -> Array:
	var raw: Array = RAW.get(material, [])
	var own := _own_colours(p)
	var out: Array = []
	out.append_array(raw)
	out.append_array(own)
	if material == "glass" or material == "straw":
		out.append_array(raw)
	if out.is_empty():
		out.append(Color8(150, 110, 70))
	return out


## Up to six texels of the thing's texture (solid ones), the same each time.
func _own_colours(p: Breakables.Piece) -> Array:
	var source := "p:" + p.image
	var models: Object = game.features.get("wreckage")
	if models != null:
		var src: Dictionary = models.call("_source", p)
		if not src.is_empty():
			source = str(src["key"]).get_slice("|", 0)
	var kept: Variant = _colours.get(source)
	if kept != null:
		var known: Array = kept
		return known
	var out: Array = []
	var image := WreckCuts.texture_image(game.art, source)
	if image != null and image.get_width() > 0:
		var w := image.get_width()
		var h := image.get_height()
		for k in 40:
			if out.size() >= 6:
				break
			var px := int(w * fposmod(k * .618034 + .13, 1.0))
			var py := int(h * fposmod(k * .381966 + .41, 1.0))
			var c := image.get_pixel(clampi(px, 0, w - 1), clampi(py, 0, h - 1))
			if c.a > .5 and c.v > .08:
				out.append(Color(c.r, c.g, c.b, 1.0))
	_colours[source] = out
	return out
