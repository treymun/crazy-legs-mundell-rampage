## The play HUD's layout: the one place that owns the view's edges and hands
## each piece drawn over the view (the notice, the boss bar, the objective
## pin, the driving plates, the kill feed, BLUE's badge, the flashlight,
## prompts and captions, the modes' lines) a rect clear of the others, so no
## two overlap at 320x200 however crowded the moment.
##
## Each frame game_view.gd resets it and lays out the top stack (the notice,
## the boss bar, the pin, a streak's call); then every feature takes its
## corner piece (GameFeature.hud_claim); then the pieces drawn after (the
## feed, the prompt, the caption, the hurt and windup marks) are fitted into
## what is left. A piece's rect is all it inks, outline and drop shadow too.
##
## tools/hud_layout_check.gd measures what each piece really inks (`measure`)
## in crowded moments and fails on any two that touch.
class_name HudLayout
extends RefCounted

## The view's margins: no piece inks nearer its sides or its top than this.
const EDGE := 4
const TOP := 4
## One past the last row a piece may ink (the view is 156 rows; the status
## bar's rail starts under it).
const BOTTOM := 154
const WIDTH := 320
const MIDDLE := 160
## Pieces keep at least this many clear pixels between them.
const GAP := 1
## A centred banner narrower than this goes up instead of squeezing.
const NARROWEST := 120
## ASPECT WIDE (View.cols over 320): a piece starting within HUG of the
## view's left edge (and ending left of its middle) is drawn that much
## further left, at the picture's own edge; one ending within HUG of the
## right edge, right (side_of, begin()). The rest stays with the canvas,
## centred. The layout itself is worked out at 320 as ever: pieces only move
## outward, so none comes nearer another.
const HUG := 16

## The rects taken this frame, and whose.
var taken: Array[Rect2i] = []
var names: PackedStringArray = []
## How far the objective pin may swing this frame (x of its middle): clear
## of the pinned pieces beside its row.
var pin_swing := Vector2i(44, 276)
## Pieces the front end draws over play after it (the frame counter, the
## ping): [name, rect] each, taken first every frame until changed.
var pinned: Array = []
## The wrap width the last fitted banner used (HUD.banner's `limit`).
var limit := 288

## The checks' measuring: what each named piece inked this frame.
static var measuring := false
static var inked := {}
static var _saved := PackedByteArray()
static var _open := ""
## The layout last reset (the one being drawn): begin() finds its pieces there.
static var drawn: HudLayout = null


func reset() -> void:
	drawn = self
	taken.clear()
	names.clear()
	pin_swing = Vector2i(44, 276)
	if measuring:
		inked.clear()
	for pin: Array in pinned:
		var r: Rect2i = pin[1]
		take(str(pin[0]), r)


## Takes `r` for `name` as it is (a fixed piece) and returns it.
func take(name: String, r: Rect2i) -> Rect2i:
	if r.size.x > 0 and r.size.y > 0:
		taken.append(r)
		names.append(name)
	return r


## The rect taken for `name` this frame (empty when none).
func find(name: String) -> Rect2i:
	var i := names.find(name)
	return taken[i] if i >= 0 else Rect2i()


## Whether `r` keeps GAP clear of every rect taken.
func clear(r: Rect2i) -> bool:
	return _hit(r) < 0


## The first taken rect `r` comes within GAP of (-1 none).
func _hit(r: Rect2i) -> int:
	var near := r.grow(GAP)
	for i in taken.size():
		if near.intersects(taken[i]):
			return i
	return -1


## Down from row `top` at column `x`: the first rect of `size` clear of the
## others and ending by row `bottom`, taken for `name`; an empty Rect2i when
## there is no room.
func down(name: String, size: Vector2i, x: int, top: int, bottom := BOTTOM) -> Rect2i:
	var r := Rect2i(Vector2i(x, maxi(top, TOP)), size)
	for _tries in 24:
		if r.end.y > bottom:
			return Rect2i()
		var i := _hit(r)
		if i < 0:
			return take(name, r)
		r.position.y = taken[i].end.y + GAP
	return Rect2i()


## Up from row `bottom` (one past its last row) at column `x`: the first rect
## of `size` clear of the others, no higher than `top`; empty when none.
func up(name: String, size: Vector2i, x: int, bottom := BOTTOM, top := TOP) -> Rect2i:
	var r := Rect2i(Vector2i(x, mini(bottom, BOTTOM) - size.y), size)
	for _tries in 24:
		if r.position.y < top:
			return Rect2i()
		var i := _hit(r)
		if i < 0:
			return take(name, r)
		r.position.y = taken[i].position.y - GAP - size.y
	return Rect2i()


## The pin's row at `top` (`r`, the whole width) and how far it may swing:
## its arrow and plate keep clear of what is already beside it (the touch
## buttons), its middle 14 pixels in from them.
func pin_row(r: Rect2i) -> void:
	var left := 30
	var right := WIDTH - 30
	for t: Rect2i in taken:
		if t.position.y >= r.end.y + GAP or t.end.y + GAP <= r.position.y:
			continue
		if t.end.x <= MIDDLE:
			left = maxi(left, t.end.x + GAP)
		elif t.position.x >= MIDDLE:
			right = mini(right, t.position.x - GAP)
	pin_swing = Vector2i(maxi(44, left + 14), mini(276, right - 14))
	take("pin", Rect2i(left, r.position.y, maxi(1, right - left), r.size.y))


## The widest span centred on the view's middle that is clear over rows
## [y, y + h): x from .x to .y (equal when something sits across the middle).
func span(y: int, h: int) -> Vector2i:
	var left := EDGE
	var right := WIDTH - EDGE
	for t: Rect2i in taken:
		if t.position.y > y + h + GAP - 1 or t.end.y + GAP <= y:
			continue
		if t.end.x <= MIDDLE:
			left = maxi(left, t.end.x + GAP)
		elif t.position.x >= MIDDLE:
			right = mini(right, t.position.x - GAP)
		else:
			return Vector2i(MIDDLE, MIDDLE)
	var half := maxi(0, mini(MIDDLE - left, right - MIDDLE))
	return Vector2i(MIDDLE - half, MIDDLE + half)


## A centred piece of `size` from row `top` down (or from `bottom` up when
## `rising`), clear of the others; empty when there is no room.
func centred(name: String, size: Vector2i, top: int, rising := false) -> Rect2i:
	var y := top - size.y if rising else top
	for _tries in 24:
		if y < TOP or y + size.y > BOTTOM:
			return Rect2i()
		var r := Rect2i(MIDDLE - size.x / 2, y, size.x, size.y)
		var i := _hit(r)
		if i < 0:
			return take(name, r)
		y = taken[i].position.y - GAP - size.y if rising else taken[i].end.y + GAP
	return Rect2i()


## A word-wrapped banner (HUD.banner) of `value`, as wide as `widest` at most,
## from row `edge` down (or up from it when `rising`), narrowed to keep clear
## of the pieces beside it or else moved on past them. `limit` is then the
## wrap width to draw it with; empty when there is no room.
func banner(name: String, value: String, edge: int, widest := 288, rising := false) -> Rect2i:
	var y := edge
	# Going down there is always more room below: narrowed past one more line
	# it moves on down instead.
	var tallest := HUD.banner_size(value, widest).y + (9999 if rising else line_height())
	for _tries in 12:
		var wrap := widest
		for _narrow in 4:
			var size := HUD.banner_size(value, wrap)
			var top := y - size.y if rising else y
			if top < TOP or top + size.y > BOTTOM:
				return Rect2i()
			if size.y > tallest:
				break
			var room := span(top, size.y)
			var r := Rect2i(MIDDLE - (size.x - 1) / 2, top, size.x, size.y)
			if size.x <= room.y - room.x and clear(r):
				limit = wrap
				return take(name, r)
			var narrower := mini(room.y - room.x, wrap - 2)
			if narrower < NARROWEST or narrower >= wrap:
				break
			wrap = narrower
		# No room on these rows: on past the pieces in the way.
		var full := HUD.banner_size(value, widest)
		var top2 := y - full.y if rising else y
		var probe := Rect2i(EDGE, top2, WIDTH - EDGE * 2, full.y).grow(GAP)
		var next := -1
		for t: Rect2i in taken:
			if probe.intersects(t):
				var above := t.position.y - GAP
				if rising:
					next = above if next < 0 else mini(next, above)
				else:
					next = maxi(next, t.end.y + GAP)
		if next < 0 or next == y:
			return Rect2i()
		y = next
	return Rect2i()


## A banner line's height in the banners' type (HUD.text_style).
static func line_height() -> int:
	var h: int = PixelType.style_of(HUD.text_style)[1]
	return h + 3


## The lowest row taken across the view's top, from `x0` to `x1`, under
## which a piece in that column starts (TOP when nothing is there).
func under(x0: int, x1: int, below := 80) -> int:
	var y := TOP
	for t: Rect2i in taken:
		if t.end.x > x0 and t.position.x < x1 and t.position.y < below:
			y = maxi(y, t.end.y + GAP)
	return y


## What a line of text inks: its letters, the outline round them and the
## drop under them (Canvas.label with a shadow), from its top-left corner.
static func text_rect(value: String, x: int, y: int, style: String, shadow := true) -> Rect2i:
	var w := PixelType.text_width(value, style)
	var h: int = PixelType.style_of(style)[1]
	if not shadow:
		return Rect2i(x, y, w, h)
	return Rect2i(x - 1, y - 1, w + 2, h + 3)


## What Canvas.panel inks for a box at (x, y) of w x h: the drop shadow too.
static func panel_rect(x: int, y: int, w: int, h: int) -> Rect2i:
	return Rect2i(x, y, w + 1, h + 2)


# ------------------------------------------------------------- measuring


## Which edge the piece in `r` keeps in ASPECT WIDE: -1 the left, 1 the
## right, 0 none (centred with the canvas).
static func side_of(r: Rect2i) -> int:
	if r.size.x <= 0 or r.size.y <= 0:
		return 0
	if r.position.x <= HUG and r.end.x <= MIDDLE:
		return -1
	if r.end.x >= WIDTH - HUG and r.position.x >= MIDDLE:
		return 1
	return 0


## Begins drawing the piece `name`: in ASPECT WIDE it keeps its edge
## (side_of its rect this frame); while `measuring`, on a software layer, its
## own ink is told apart from what is under it.
static func begin(c: Canvas, name: String) -> void:
	if c.gpu and View.shift > 0 and drawn != null:
		c.anchor(side_of(drawn.find(name)) * View.shift)
	if not measuring or c.gpu or not c.layer:
		return
	if _open != "":
		end(c)
	_open = name
	_saved = c.cover.duplicate()
	c.cover.fill(0)


## Ends the piece begun: its inked rect over the view is added to `inked`.
static func end(c: Canvas) -> void:
	c.anchor(0)
	if _open == "" or not measuring:
		return
	var cover := c.cover
	var x0 := WIDTH
	var y0 := BOTTOM + 2
	var x1 := -1
	var y1 := -1
	for y in View.VIEW:
		var row := y * WIDTH
		var first := -1
		var last := -1
		for x in WIDTH:
			if cover[row + x] != 0:
				if first < 0:
					first = x
				last = x
		if first >= 0:
			x0 = mini(x0, first)
			x1 = maxi(x1, last)
			y0 = mini(y0, y)
			y1 = y
	for i in cover.size():
		if _saved[i] > cover[i]:
			cover[i] = _saved[i]
	c.cover = cover
	if x1 >= 0:
		var r := Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)
		if inked.has(_open):
			var had: Rect2i = inked[_open]
			r = had.merge(r)
		inked[_open] = r
	_open = ""
