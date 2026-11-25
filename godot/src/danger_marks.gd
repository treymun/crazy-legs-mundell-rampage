## Reading danger (pass 15): where a blow came from, who is about to swing or
## fire off the view, and a hazard a boot would put a man into. Looks only:
## nothing here changes play. It reads what play carries (an enemy's wind-up,
## the blows the local player took: game.danger_blows, kept by blow() from
## damage()) and draws on the canvas over the view, where the hurt arc went
## (game_view.gd), under every banner.
##
## - **Damage arrows** (DANGER ARROWS on): a red chevron at the view's edge
##   toward each blow's source, white the moment it lands, fading over
##   `arrow_for`, at most `arrows_most` at once; a blow of `heavy` or more is a
##   double chevron. The hurt banner then names only what hit; the side is the
##   arrow's. Off: the hurt arc and "<CAUSE> LEFT" as before.
## - **Wind-ups off the view** (DANGER ARROWS on): an amber chevron toward each
##   hand winding up whose middle is off the view, within `windup_reach` (the
##   nearest `windups_most`), blinking hot over the last `tell_share` of the
##   wind-up, when his model flashes amber in the view (EnemyLooks.tell). Off:
##   the WINDUP LEFT panel as before.
## - **Hazards** (always): brackets breathing round each hazard prop within
##   [hazard] `show_reach` of the awake hand nearest the sights (within
##   `sights_reach`), and a little skull under the crosshair when a boot now
##   would slide the man USE would kick into a hazard (skull()).
##
## Crisp at 320x200: a chevron is a pixel pattern pointing out of the edge it
## sits on (up, right, down or left), never a turned line: its place along
## the edge gives the bearing (a quarter turn round is a corner). ASPECT
## WIDE puts them on the picture's own edges; they keep clear of the HUD's
## pieces and the touch buttons (HudLayout.taken, where each is drawn), slid
## in toward the middle. Numbers: hits.cfg [danger] and [hazard].
class_name DangerMarks
extends RefCounted

const Brawl := preload("res://src/features/brawl.gd")

static var ARROW_FOR: float = HitData.value("danger", "arrow_for", .8)
static var ARROWS_MOST: int = HitData.value("danger", "arrows_most", 4)
static var HEAVY: float = HitData.value("danger", "heavy", 20.0)
static var WINDUP_REACH: float = HitData.value("danger", "windup_reach", 14.0)
static var WINDUPS_MOST: int = HitData.value("danger", "windups_most", 2)
static var SHOW_REACH: float = HitData.value("hazard", "show_reach", 3.5)
static var SIGHTS_REACH: float = HitData.value("hazard", "sights_reach", 12.0)

## How far in from the view's edges a chevron's middle sits.
const INSET := 9.0
## A hand within this box of the player may be booted (the boot's reach and
## the widest hand's edge): draw() asks skull() only then.
const NEAR_BOX := 2.6
## The player's own blasts: no arrow.
const OWN := ["BACKBLAST", "LIT DYNAMITE"]
## A source this near the player is on top of him: no way to point.
const ON_TOP := .05
## _place's answer when every spot it tried is under a HUD piece.
const NOWHERE := Vector2i(-100000, -100000)
## A blow is white this long after it lands, then red.
const FRESH := .06
const RED := Color(.93, .21, .13)
const RED_DIM := Color(.42, .07, .04)
const WHITE := Color(1.0, .93, .80)
const AMBER := Color(.98, .66, .27)
const AMBER_HOT := Color(1.0, .93, .62)
const INK := Color(.15, .05, .03)
const BONE := Color(.94, .89, .76)
const HAZARD := Color(.90, .30, .14)
## The way each of the four points (0 up the view, then clockwise).
const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
## The skull under the crosshair, 7 by 6.
const SKULL: Array[String] = [
	".#####.",
	"#######",
	"#..#..#",
	"###.###",
	".#####.",
	".#.#.#.",
]

## Per way: [the fill's runs, the edge's runs], each run x, y, length from
## the chevron's middle (made once).
static var _ways: Array = []
## The skull's [fill runs, edge runs] from its top left.
static var _skull: Array = []


## A blow landed on the local player (game_world.gd damage(), `source` its
## [x, y] or null): kept for its arrow when it came from somewhere a mark can
## point at: not the player's own blast (OWN), not from where he stands. The
## steam and the chalk or gas clouds get one too (the hurt arc never drew
## them): a boilerback's blast, a jet, the cloud's middle that way.
static func blow(g: Game, source: Variant, cause: String, amount: float) -> void:
	var kept: Array = []
	for b: Array in g.danger_blows:
		var until: float = b[2]
		if until > g.clock:
			kept.append(b)
	if source != null and not OWN.has(cause):
		var sx: float = source[0]
		var sy: float = source[1]
		var p := g.player
		if Vector2(sx - p.x, sy - p.y).length() > ON_TOP:
			kept.append([atan2(sy - p.y, sx - p.x), g.clock, g.clock + ARROW_FOR, amount])
	while kept.size() > ARROWS_MOST:
		kept.pop_front()
	g.danger_blows = kept


## The arrows to draw now: [x, y (the view, picture pixels), way (0..3),
## colour, doubled] each: the blows', then the wind-ups' (of `winders`, the
## hands winding up, when draw() has them: else all the hands).
static func arrows(g: Game, winders: Variant = null) -> Array:
	var out: Array = []
	if not g.danger_arrows or g.view_eye.is_empty() or g.player.health <= 0:
		return out
	var facing: float = g.view_eye["view_angle"]
	var taken := _drawn_rects(g)
	for b: Array in g.danger_blows:
		var heading: float = b[0]
		var landed: float = b[1]
		var until: float = b[2]
		var amount: float = b[3]
		if until <= g.clock:
			continue
		var life := clampf((until - g.clock) / ARROW_FOR, 0.0, 1.0)
		var ink := WHITE if g.clock - landed < FRESH else RED_DIM.lerp(RED, sqrt(life))
		var turn := fposmod(heading - facing + PI, TAU) - PI
		var at := _place(turn, taken)
		if at != NOWHERE:
			out.append([at.x, at.y, _way(turn), ink, amount >= HEAVY])
	var among: Array = g.enemies if winders == null else winders
	for e: Enemy in winding(g, among):
		var turn := fposmod(atan2(e.y - g.player.y, e.x - g.player.x) - facing + PI, TAU) - PI
		var hot := EnemyLooks.tell(e, g.clock) > 0.0 and fposmod(g.clock * 8.0, 1.0) < .5
		var at := _place(turn, taken)
		if at != NOWHERE:
			out.append([at.x, at.y, _way(turn), AMBER_HOT if hot else AMBER, false])
	return out


## The hands of `among` winding up at the player off the view now, nearest
## first (WINDUPS_MOST at most).
static func winding(g: Game, among: Array) -> Array:
	var p := g.player
	var found: Array = []
	for e: Enemy in among:
		if e.windup <= 0.0 or not e.alive or e.dormant or not e.hostile or not e.player_seen:
			continue
		var dx := e.x - p.x
		var dy := e.y - p.y
		var square := dx * dx + dy * dy
		if square > WINDUP_REACH * WINDUP_REACH:
			continue
		var middle := g.world.stand(e) + e.z + e.height * e.variant * .55
		var at := g.to_canvas(e.x, e.y, middle)
		var side := float(View.shift)
		if (
			at.z > 0.0
			and at.x > 4.0 - side
			and at.x < View.WIDTH + side - 4.0
			and at.y > 4.0
			and at.y < View.VIEW - 4.0
		):
			continue
		found.append([square, e])
	found.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var out: Array = []
	for f: Array in found.slice(0, WINDUPS_MOST):
		out.append(f[1])
	return out


## Draws this frame's arrows, the hazards' brackets and the skull (game_view.gd,
## before the banners).
##
## One pass over the hands first (a chapter has a hundred and more; pass 15
## measured each of the old separate passes at 17 to 50 us a frame): who is
## winding up, and whether any is near enough to boot.
static func draw(g: Game, c: Canvas) -> void:
	var winders: Array = []
	var near := false
	var px := g.player.x
	var py := g.player.y
	for e: Enemy in g.enemies:
		if e.windup > 0.0:
			winders.append(e)
		if not near and absf(e.x - px) < NEAR_BOX and absf(e.y - py) < NEAR_BOX:
			near = true
	for spot: Array in glowing(g):
		_brackets(g, c, spot)
	for a: Array in arrows(g, winders):
		var x: int = a[0]
		var y: int = a[1]
		var way: int = a[2]
		var ink: Color = a[3]
		var doubled: bool = a[4]
		if doubled:
			var back := -DIRS[way] * 4
			_chevron(c, x + back.x, y + back.y, way, ink.darkened(.25))
		_chevron(c, x, y, way, ink)
	if near and skull(g):
		_draw_skull(c, View.WIDTH / 2 - 3, View.VIEW / 2 + 6)


# ------------------------------------------------------------------ hazards


## The awake hand nearest the sights (in sight, within SIGHTS_REACH, the
## aim on his body), or null.
static func sighted(g: Game) -> Enemy:
	if g.view_eye.is_empty():
		return null
	var p := g.player
	var px := p.x
	var py := p.y
	var facing: float = g.view_eye["view_angle"]
	var best: Enemy = null
	var best_d := SIGHTS_REACH
	for e: Enemy in g.enemies:
		var dx := e.x - px
		var dy := e.y - py
		if absf(dx) > best_d or absf(dy) > best_d:
			continue
		if not e.alive or e.dormant or not e.hostile or not e.alerted:
			continue
		var d := sqrt(dx * dx + dy * dy)
		if d >= best_d or d < .2:
			continue
		var off := absf(Enemy.angle_delta(atan2(dy, dx), facing))
		if off > atan((e.radius + .25) / d):
			continue
		var top := g.world.stand(e) + e.z + e.height * e.variant * .6
		if not g.world.visible(p.x, p.y, e.x, e.y, p.eye, top):
			continue
		best = e
		best_d = d
	return best


## The hazard props within SHOW_REACH of the hand in the sights:
## [kind, x, y] each.
static func glowing(g: Game) -> Array:
	var brawl: Brawl = g.features.get("brawl")
	if brawl == null or not brawl.allowed() or g.player.health <= 0:
		return []
	var spots := brawl.spots()
	var px := g.player.x
	var py := g.player.y
	var reach := SIGHTS_REACH + SHOW_REACH
	var any := false
	for spot: Array in spots:
		var sx: float = spot[1]
		var sy: float = spot[2]
		if absf(sx - px) < reach and absf(sy - py) < reach:
			any = true
			break
	if not any:
		return []
	var e := sighted(g)
	if e == null or BossKit.is_boss(e):
		return []
	var out: Array = []
	for spot: Array in spots:
		var sx: float = spot[1]
		var sy: float = spot[2]
		if Vector2(sx - e.x, sy - e.y).length() <= SHOW_REACH:
			out.append(spot)
	return out


## Whether a boot now would send the man USE kicks into a hazard: his slide
## along the aim (the boot's speed run down by its drag, stopped by a wall)
## meets a hazard prop's reach, deep or running water, or ends among the hogs.
static func skull(g: Game) -> bool:
	var brawl: Brawl = g.features.get("brawl")
	var p := g.player
	if brawl == null or not brawl.allowed() or p.health <= 0 or brawl.busy(p):
		return false
	var kick := Brawl.KICK
	var reach: float = kick["reach"]
	var cone: float = kick["cone"]
	var e := brawl.target(p, reach, cone)
	if e == null or BossKit.is_boss(e) or brawl.finishable(e):
		return false
	return slide_meets(g, brawl, e, p.view_angle())


## Whether `e` kicked along `aim` slides into a hazard (see skull()).
static func slide_meets(g: Game, brawl: Brawl, e: Enemy, aim: float) -> bool:
	var kick := Brawl.KICK
	var speed: float = kick["speed"]
	var drag: float = kick["drag"]
	var stop: float = kick["stop"]
	var step := .1
	var dir := Vector2(cos(aim), sin(aim))
	var x := e.x
	var y := e.y
	var dry := not BayouBrains.wet_at(g.world, x, y)
	var spots := brawl.spots()
	while speed >= stop:
		var nx := x + dir.x * step
		var ny := y + dir.y * step
		if g.world.blocked(nx, ny, e.radius):
			break
		x = nx
		y = ny
		for spot: Array in spots:
			var kind: String = spot[0]
			var sx: float = spot[1]
			var sy: float = spot[2]
			var near: float = BrawlHazards.value(kind, "reach", .8)
			near += e.radius
			if (x - sx) * (x - sx) + (y - sy) * (y - sy) < near * near:
				return true
		if dry and speed >= BrawlHazards.WATER_LEAST:
			var ax := x + dir.x * (e.radius + BrawlHazards.WATER_AHEAD)
			var ay := y + dir.y * (e.radius + BrawlHazards.WATER_AHEAD)
			if BayouBrains.wet_at(g.world, ax, ay) and BayouBrains.wet_at(g.world, x, y):
				return true
		speed = sqrt(maxf(0.0, speed * speed - 2.0 * drag * step))
	for hog: Enemy in BrawlHazards.hogs_near(g.enemies, x, y):
		if hog != e:
			return true
	return false


## Corner brackets breathing round a hazard prop (as USE's mark, faint red),
## the prop's own height (its board in the level) tall.
static func _brackets(g: Game, c: Canvas, spot: Array) -> void:
	var sx: float = spot[1]
	var sy: float = spot[2]
	var tall := 1.0
	var lift := 0.0
	for board: LevelData.Billboard in g.world.billboards:
		if absf(board.x - sx) < .01 and absf(board.y - sy) < .01:
			tall = board.height
			lift = board.z
			break
	var foot := g.world.elevation(sx, sy) + lift
	var at := g.to_canvas(sx, sy, foot + tall * .5)
	if at.z <= 0.0:
		return
	var half_h := int(clampf(tall * .55 / at.z * View.base_focal, 5, 60))
	var half := int(clampf(minf(tall * .45, 1.0) / at.z * View.base_focal, 5, 40))
	var cx := int(at.x)
	var cy := int(at.y)
	var side := View.shift
	if cx < half - side or cx > View.WIDTH + side - half or cy < 2 or cy > View.VIEW - 2:
		return
	var glow := .55 + .3 * sin(g.clock * 5.0)
	var colour := Color(HAZARD.r * glow, HAZARD.g * glow, HAZARD.b * glow)
	var arm := maxi(2, mini(half, half_h) / 3)
	for kx: int in [-1, 1]:
		for ky: int in [-1, 1]:
			var x := cx + kx * half
			var y := clampi(cy + ky * half_h, 1, View.VIEW - 2)
			c.fill_rect(mini(x, x - kx * arm), y, arm + 1, 1, colour)
			c.fill_rect(x, mini(y, y - ky * arm), 1, arm + 1, colour)


# ------------------------------------------------------------------ drawing


## Where an arrow for something `turn` off the view's middle goes: on the
## view's edge that way (a turn of a quarter round the corner between), slid
## toward the middle off any HUD piece in `taken`; NOWHERE when it finds no
## clear spot (a mark never strikes a banner through: the layout check).
static func _place(turn: float, taken: Array[Rect2i]) -> Vector2i:
	var side := float(View.shift)
	var middle := Vector2(View.WIDTH / 2.0, View.VIEW / 2.0)
	var hw := middle.x + side - INSET
	var hh := middle.y - INSET
	var e := Vector2(sin(turn), -cos(turn))
	var s := 1.0 / maxf(absf(e.x), absf(e.y))
	var at := middle + Vector2(e.x * s * hw, e.y * s * hh)
	for _try in 9:
		var box := Rect2i(roundi(at.x) - 7, roundi(at.y) - 7, 15, 15)
		var clear := true
		for r: Rect2i in taken:
			if r.intersects(box):
				clear = false
				break
		if clear:
			return Vector2i(roundi(at.x), roundi(at.y))
		at = at.move_toward(middle, 6.0)
	return NOWHERE


## The way (0..3) an arrow for `turn` points: out of the edge _place puts it
## on (a corner's: the top or the foot).
static func _way(turn: float) -> int:
	var e := Vector2(sin(turn), -cos(turn))
	if absf(e.x) > absf(e.y) + .01:
		return 1 if e.x > 0.0 else 3
	return 2 if e.y > 0.0 else 0


## The HUD's pieces this frame where they are drawn (ASPECT WIDE moves the
## ones at an edge out to the picture's).
static func _drawn_rects(g: Game) -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	for r: Rect2i in g.hud.layout.taken:
		out.append(Rect2i(r.position + Vector2i(HudLayout.side_of(r) * View.shift, 0), r.size))
	return out


static func _chevron(c: Canvas, x: int, y: int, way: int, ink: Color) -> void:
	if _ways.is_empty():
		_make_ways()
	var shape: Array = _ways[way]
	var fill: PackedInt32Array = shape[0]
	var edge: PackedInt32Array = shape[1]
	_runs_at(c, edge, x, y, INK)
	_runs_at(c, fill, x, y, ink)


static func _draw_skull(c: Canvas, x: int, y: int) -> void:
	if _skull.is_empty():
		var pts: Array[Vector2i] = []
		for row in SKULL.size():
			for col in SKULL[row].length():
				if SKULL[row][col] == "#":
					pts.append(Vector2i(col, row))
		_skull = [_runs(pts), _runs(_edge(pts))]
	var fill: PackedInt32Array = _skull[0]
	var edge: PackedInt32Array = _skull[1]
	_runs_at(c, edge, x, y, INK)
	_runs_at(c, fill, x, y, BONE)


static func _runs_at(c: Canvas, runs: PackedInt32Array, x: int, y: int, ink: Color) -> void:
	for i in range(0, runs.size(), 3):
		c.fill_rect(x + runs[i], y + runs[i + 1], runs[i + 2], 1, ink)


## The four chevrons: up is a caret with arms three pixels thick, thirteen
## wide and seven tall (its tip a solid head); the rest are it turned.
static func _make_ways() -> void:
	var up: Array[Vector2i] = []
	for k in 7:
		for x in range(-k, k + 1):
			if absi(x) >= k - 2 and not up.has(Vector2i(x, k - 3)):
				up.append(Vector2i(x, k - 3))
	_ways = []
	for way in 4:
		var pts: Array[Vector2i] = []
		for at: Vector2i in up:
			var r := at
			for _q in way:
				r = Vector2i(-r.y, r.x)
			pts.append(r)
		_ways.append([_runs(pts), _runs(_edge(pts))])


## The pixels beside `pts` (above, below, left, right) that are not in it.
static func _edge(pts: Array[Vector2i]) -> Array[Vector2i]:
	var inside := {}
	for at: Vector2i in pts:
		inside[at] = true
	var out: Array[Vector2i] = []
	for at: Vector2i in pts:
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n := at + d
			if not inside.has(n) and not out.has(n):
				out.append(n)
	return out


## `pts` as rows of runs: x, y, length each.
static func _runs(pts: Array[Vector2i]) -> PackedInt32Array:
	var sorted := pts.duplicate()
	sorted.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x)
	)
	var out := PackedInt32Array()
	var i := 0
	while i < sorted.size():
		var start: Vector2i = sorted[i]
		var length := 1
		while i + length < sorted.size() and sorted[i + length] == start + Vector2i(length, 0):
			length += 1
		out.append(start.x)
		out.append(start.y)
		out.append(length)
		i += length
	return out
