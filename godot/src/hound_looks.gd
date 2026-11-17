## How BLUE looks (features/hound.gd): his body in the view (his model,
## scenes/actors/hound.tscn, posed by a stand-in only the view reads, as
## ModeBodies does for the players) with whatever he carries in his mouth,
## and his badge in the view's bottom left corner: his head (hound_face_*,
## scripts/blender/actors_hound.py) and five health ticks in the status
## bar's own reds and ambers, his name, and what he is up to. Looks only.
class_name HoundLooks
extends RefCounted

## The badge's plate: its top left on the 320x200 canvas, its size.
const BADGE_X := 3
const BADGE_W := 62
const BADGE_H := 33
## The head's box in it.
const FACE := 27
## The plate's wood and trim, as the status bar's (hud.gd meter()).
const PLATE := Color(57 / 255.0, 46 / 255.0, 38 / 255.0)
const TRIM := Color(172 / 255.0, 159 / 255.0, 132 / 255.0)
const TRIM_LOW := Color(125 / 255.0, 111 / 255.0, 92 / 255.0)
const WELL := Color(29 / 255.0, 23 / 255.0, 19 / 255.0)
const TICKS := 5
## The ticks' colours by how many are lit: red, amber, then a field green.
const TICK_INK := [
	Color(238 / 255.0, 89 / 255.0, 52 / 255.0),
	Color(251 / 255.0, 183 / 255.0, 98 / 255.0),
	Color(160 / 255.0, 210 / 255.0, 92 / 255.0)
]
## Holding a hand (PIN) his body is drawn this far back along his heading
## from where play has him (features/hound.gd sprites): the hold's gap is
## the two bodies' radii, but reared up his head and paws reach .8 ahead of
## his middle, and stood in the hand's chest.
const PIN_BACK := .3
## Head picture -> its scaled pixels.
static var _faces: Dictionary = {}


## His body in the view: `frame` his model's frame (hound_<frame>), at (x,
## y) on floor `z`, facing `angle`, his walk at `gait`; `slot` names his
## stand-in; `flash` how freshly hurt.
static func body(
	g: Game,
	slot: int,
	x: float,
	y: float,
	z: float,
	angle: float,
	gait: float,
	frame: String,
	flash: float
) -> View.Sprite:
	var e := ModeBodies.stand_in(g, "hound%d" % slot, "hound")
	e.x = x
	e.y = y
	e.angle = angle
	e.gait = gait
	e.height = 1.0
	e.variant = 1.0
	e.died_at = -1.0
	var s := g.pooled(x, y, "hound_" + frame, 1.0, z)
	s.who = e
	s.body = true
	s.hurt = flash
	return s


## What he carries, in his jaws: the pickup's own picture, small.
static func carried(
	g: Game, item: String, x: float, y: float, z: float, angle: float
) -> View.Sprite:
	var reach := .86
	return g.pooled(x + cos(angle) * reach, y + sin(angle) * reach, "item_" + item, .2, z + .72)


## The badge: `share` his health (0..1), `face` the head to show (0 panting,
## 1 on the scent, 2 hurt, "down"), `word` under his name ("" none), `hot`
## to blink the word.
static func badge(g: Game, c: Canvas, share: float, face: String, word: String, hot: bool) -> void:
	var x := BADGE_X
	var y := View.VIEW - BADGE_H - 3
	c.round_rect(x, y, BADGE_W, BADGE_H, 2, PLATE)
	c.line(x + 2, y, x + BADGE_W - 3, y, TRIM)
	c.line(x + 1, y + 1, x + 1, y + BADGE_H - 3, Color(100 / 255.0, 92 / 255.0, 76 / 255.0))
	c.line(x + 2, y + BADGE_H - 2, x + BADGE_W - 3, y + BADGE_H - 2, TRIM_LOW)
	# the head in its dark well
	c.fill_rect(x + 3, y + 3, FACE, FACE, WELL)
	_face(g, c, "hound_face_" + face, x + 3, y + 3)
	# his name, what he is up to, the ticks
	var right := x + 3 + FACE + 3
	if word != "" and (not hot or fmod(g.clock, .8) < .5):
		HUD.text(c, word, right, y + 3, "mini", HUD.LOW if hot else HUD.AMBER, false, true)
	else:
		HUD.text(c, "BLUE", right, y + 3, "mini", HUD.INK, false, true)
	var lit := clampi(ceili(share * TICKS - .001), 0, TICKS)
	var ink: Color = TICK_INK[0 if lit <= 1 else 1 if lit <= 3 else 2]
	c.fill_rect(right - 1, y + 12, TICKS * 4 + 1, 9, WELL)
	for i in TICKS:
		var on := i < lit
		var shade := ink if on else Color(ink.r * .25, ink.g * .25, ink.b * .25)
		c.fill_rect(right + i * 4, y + 13, 3, 7, shade)
		if on:
			c.line(right + i * 4, y + 13, right + i * 4 + 2, y + 13, ink.lightened(.25))


## Whether `at` (the 320x200 picture) is on the badge, shown in game `g`
## (a tap there whistles: main_input.gd).
static func on_badge(g: Game, at: Vector2i) -> bool:
	var hound: Game.HoundScript = g.features.get("hound")
	if hound == null or not hound.on:
		return false
	var top := View.VIEW - BADGE_H - 3
	return Rect2i(BADGE_X, top, BADGE_W, BADGE_H).grow(3).has_point(at)


## A head picture scaled into the FACE box (kept), at (x, y).
static func _face(g: Game, c: Canvas, name: String, x: int, y: int) -> void:
	var scaled: Dictionary = _faces.get(name, {})
	if scaled.is_empty():
		var art := g.art.art(name)
		var w: int = art["w"]
		var h: int = art["h"]
		var data: PackedByteArray = art["data"]
		var x0 := w
		var y0 := h
		var x1 := -1
		var y1 := -1
		for py in h:
			for px in w:
				if data[(py * w + px) * 4 + 3] >= 128:
					x0 = mini(x0, px)
					x1 = maxi(x1, px)
					y0 = mini(y0, py)
					y1 = maxi(y1, py)
		scaled = {"w": 0, "h": 0, "data": PackedByteArray()}
		if x1 >= x0 and y1 >= y0:
			var cw := x1 - x0 + 1
			var ch := y1 - y0 + 1
			var k := minf(float(FACE) / cw, float(FACE) / ch)
			var tw := maxi(1, roundi(cw * k))
			var th := maxi(1, roundi(ch * k))
			var sub := PackedByteArray()
			sub.resize(cw * ch * 4)
			for py in ch:
				for px in cw:
					var from := ((y0 + py) * w + x0 + px) * 4
					var to := (py * cw + px) * 4
					for b in 4:
						sub[to + b] = data[from + b]
			scaled = {"w": tw, "h": th, "data": SmoothScale.rgba(sub, cw, ch, tw, th)}
		_faces[name] = scaled
	var sw: int = scaled["w"]
	if sw == 0:
		return
	var sh: int = scaled["h"]
	var pix: PackedByteArray = scaled["data"]
	c.blit_rgba(pix, sw, sh, x + (FACE - sw) / 2, y + FACE - sh, "hound|" + name)
