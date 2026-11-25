## The view's edge burning on a RAMPAGE (features/rampage.gd; looks only):
## tongues of fire licking in from the four edges of the view, white-hot at
## the edge through yellow and orange to a dithered red, the 1997 palette's
## fire. A few frames are drawn once (their own seeded dice, never game.rng)
## for each picture width and kept as textures; they flicker at FPS, flare
## up as the RAMPAGE begins and gutter out as it ends.
class_name RampageLooks
extends RefCounted

## Frames of fire, and how many a second.
const FRAMES := 6
const FPS := 12.0
## How deep the tongues reach from each edge, at full (the bottom's are the
## tallest: fire rises), and the three sizes drawn (flare, burning, low).
const DEEP_BOTTOM := 18
const DEEP_SIDE := 11
const DEEP_TOP := 7
const SIZES: Array[float] = [1.25, 1.0, .6]
## Seconds of the flare as it begins; the share of the time left at which
## it starts guttering.
const FLARE := .45
const GUTTER := .18

## The fire's inks from the edge in: yellow, orange, red-orange, red, and the
## dark red dithered at the tips; each up to its share of a tongue's reach.
const INKS: Array[Color] = [
	Color(1.0, 218 / 255.0, 98 / 255.0),
	Color(246 / 255.0, 146 / 255.0, 42 / 255.0),
	Color(218 / 255.0, 80 / 255.0, 24 / 255.0),
	Color(164 / 255.0, 30 / 255.0, 12 / 255.0),
	Color(98 / 255.0, 12 / 255.0, 6 / 255.0),
]
const BANDS: Array[float] = [.14, .38, .62, .84, 1.0]

## Drawn strips: key -> [data, w, h].
static var _made := {}


## The edge burning: `left` the share of the RAMPAGE still to run (0..1),
## `age` the seconds since it began.
static func burn(c: Canvas, game: Game, left: float, age: float) -> void:
	var size := 1
	if age < FLARE:
		size = 0
	elif left < GUTTER:
		# Guttering: on and off, the low fire.
		if int(game.clock * 10.0) % 3 == 0:
			return
		size = 2
	var frame := int(game.clock * FPS) % FRAMES
	var cols := View.cols if c.gpu else c.w
	var x0 := -View.shift if c.gpu else 0
	var view := View.VIEW
	for edge: String in ["top", "left", "right", "bottom"]:
		var strip := _strip(edge, size, frame, cols, view)
		var data: PackedByteArray = strip[0]
		var w: int = strip[1]
		var h: int = strip[2]
		var x := x0
		var y := 0
		match edge:
			"bottom":
				y = view - h
			"right":
				x = x0 + cols - w
		c.blit_rgba(data, w, h, x, y, "rampage|%s|%d|%d|%d" % [edge, size, frame, cols])


static func _strip(edge: String, size: int, frame: int, cols: int, view: int) -> Array:
	var key := "%s|%d|%d|%d|%d" % [edge, size, frame, cols, view]
	var kept: Variant = _made.get(key)
	if kept != null:
		return kept
	if _made.size() > 200:
		_made.clear()
	var scale: float = SIZES[size]
	var deep := DEEP_BOTTOM if edge == "bottom" else DEEP_TOP if edge == "top" else DEEP_SIDE
	deep = maxi(2, roundi(deep * scale))
	var along := cols if edge == "top" or edge == "bottom" else view
	var w := along if edge == "top" or edge == "bottom" else deep
	var h := deep if edge == "top" or edge == "bottom" else along
	var data := PackedByteArray()
	data.resize(w * h * 4)
	var dice := RandomNumberGenerator.new()
	dice.seed = hash([edge, frame, 1997])
	# Each edge's tongues: a few waves at their own pace, roughened per frame.
	var phase: Array[float] = [dice.randf() * TAU, dice.randf() * TAU, dice.randf() * TAU]
	var turn := frame * TAU / FRAMES
	for i in along:
		var t := float(i)
		var wave := (
			.45 * sin(t * .21 + phase[0] + turn)
			+ .35 * sin(t * .53 + phase[1] - turn * 2.0)
			+ .2 * sin(t * 1.37 + phase[2] + turn * 3.0)
		)
		var reach := (.55 + .45 * wave) * deep + dice.randf_range(-1.5, 1.5)
		# The corners burn deepest; the middle of a long edge a little less.
		var from_end := minf(t, float(along - 1) - t) / maxf(1.0, along * .5)
		reach *= 1.15 - .35 * from_end
		reach = clampf(reach, 1.0, float(deep))
		for d in deep:
			var share := float(d) / reach
			if share >= 1.0:
				break
			var band := 0
			while share >= BANDS[band]:
				band += 1
			# The tips dithered, so the fire's edge is ragged pixels, not a line.
			if band == INKS.size() - 1 and (i + d) % 2 == 1:
				continue
			var ink: Color = INKS[band]
			var x := i if w == along else d
			var y := i if h == along else d
			if edge == "bottom":
				y = h - 1 - d
			elif edge == "right":
				x = w - 1 - d
			var o := (y * w + x) * 4
			data[o] = roundi(ink.r * 255.0)
			data[o + 1] = roundi(ink.g * 255.0)
			data[o + 2] = roundi(ink.b * 255.0)
			data[o + 3] = 255 if band < 3 else 200
	var made := [data, w, h]
	_made[key] = made
	return made
