## Things that break: crates splinter, barrels stave in, jugs and jars
## shatter, a flamingo goes over, a sign gets shot up where it hangs, and
## hazard barrels, propane tanks, gas cans, nitro and crates of dynamite go up,
## each a blast of its own a moment after it breaks, so one sets off the next
## (and the fuel drums, which game_combat.gd already sets off: a chain
## reaction). data/tuning/breakables.cfg says which pictures break into which,
## how much they take and what they throw. A broken one swaps to its broken
## picture and leaves its bits lying where they land (tumble.gd); one that
## stood in the way frees its cell for the paths (flow_field.gd). Quest props,
## doors, anything lit by a signal or glowing, and anything that alone parts
## one stretch of floor from another never break.
##
## game_combat.gd asks it what a shot strikes (ray(), touch()), tells it what
## a shot or a blast did (strike(), blast()) and leaves a burst drum's shell
## with it (wreck()). What is broken, the bits and the shells are saved in the
## feature's block. Its dice only set how the bits fly; what breaks and what
## goes up follows the shots alone.
extends GameFeature

const PATH := "res://data/tuning/breakables.cfg"
## Seconds before a broken explosive goes up: shot, and set off by a blast
## (each one more after the last, so a row goes off one after another).
const FUSE_SHOT := .1
const FUSE_BLAST := .16
const FUSE_STEP := .07
## Each kind of bit: drawn this tall, and whether it is light (straw,
## stuffing, rubber drift and settle; the rest bounce and slide).
const BIT_SIZE := {
	"wood": .09,
	"grey": .09,
	"char": .09,
	"straw": .08,
	"stuffing": .06,
	"rubber": .05,
	"glass": .05,
	"clay": .06,
	"tin": .06,
	"redtin": .06,
	"orange": .06,
	"pink": .05,
	"goo": .05,
	"plastic": .06,
}
const LIGHT := ["straw", "stuffing", "rubber"]
## The specks a breaking thing throws with its bits, by what it is made of.
const SPECKS := {
	"wood": "chips",
	"grey": "chips",
	"char": "dust",
	"straw": "dust",
	"stuffing": "dust",
	"glass": "glass",
	"clay": "glass",
	"goo": "plasma",
}


## Something that can break, where the level stands it.
class Piece:
	var id := ""
	var image := ""
	var spec := {}
	var x := 0.0
	var y := 0.0
	## Its foot over the ground, and how tall it stands.
	var z := 0.0
	var height := 1.0
	var radius := .3
	var hp := 1.0
	var broken := false
	var board: LevelData.Billboard = null
	var sprite: Renderer.Sprite = null
	## The furniture under it that blocks the way (empty: in nobody's way), and
	## the others that stand on the same.
	var base := PackedFloat32Array()
	var shares: Array = []


## A bit of something broken, flying or lying where it landed.
class Bit:
	extends Tumble.Body
	var image := ""
	var size := .08
	var flip := false
	var roll := 0.0
	## Its picture once it lies still (made once, drawn from then on).
	var sprite: Renderer.Sprite = null


## A side of a block of bits lying still, in cells: a frame asks the view about
## each block, not each bit.
const BLOCK := 6.0

var pieces: Array = []
var bits: Array = []
## Burst drums' shells: [x, y, image, height].
var wrecks: Array = []
## Explosives broken and about to go up: [piece index, seconds left].
var cooking: Array = []
var dice := RandomNumberGenerator.new()
## The last ray(): how far along it the piece it found stands, and which.
var ray_d := 0.0
var ray_piece := -1
var bits_max := 180
var shove_reach := 1.6
var shove_most := .45
var _feels := {}
var _cfg: ConfigFile
## The bits lying still, by block: [middle x, middle y, reach, their sprites],
## made again when one settles, is thrown again or goes.
var _resting: Array = []
var _resting_dirty := false
var _chip_next := 0.0
var _crash_next := -1.0
## Counts every change to a piece (hp, broken, moved, its board): a host's
## NetTrack looks through the lists in NET_GUARDED only when it moved, so
## anything that changes a piece bumps it (game_host.gd).
var net_version := 0
const NET_GUARDED := ["pieces"]


func id() -> String:
	return "breakables"


func attach() -> void:
	dice.seed = 2024
	_cfg = Tuning.file(PATH)
	bits_max = int(_cfg.get_value("all", "bits_max", 150))
	shove_reach = float(_cfg.get_value("all", "shove_reach", 1.6))
	shove_most = float(_cfg.get_value("all", "shove_most", .45))
	_find()
	# The pictures a break shows, read now rather than in the middle of a fight.
	for p: Piece in pieces:
		game.renderer.sprite_art(String(p.spec["broken"]))
	for stuff: String in BIT_SIZE:
		for n in 2:
			game.renderer.sprite_art("fx_brk_%s_%d" % [stuff, n])
	game.ticked.connect(_tick)


func _spec(image: String) -> Dictionary:
	if image == "all" or not _cfg.has_section(image):
		return {}
	var out := {}
	for key in _cfg.get_section_keys(image):
		out[key] = _cfg.get_value(image, key)
	if not game.art.has_art(String(out.get("broken", ""))):
		return {}
	return out


# ------------------------------------------------------------------ finding


## Every board and prop the tuning names, but those that must stay whole.
func _find() -> void:
	var world: LevelData = game.world
	var standing: Array = []
	for board: LevelData.Billboard in world.billboards:
		standing.append([board.image, board.x, board.y, board.z, board, null])
	for sprite: Renderer.Sprite in game.props:
		standing.append([sprite.image, sprite.x, sprite.y, 0.0, null, sprite])
	var by_base := {}
	for row: Array in standing:
		var image := String(row[0])
		var spec := _spec(image)
		var board: LevelData.Billboard = row[4]
		var base := _base_under(float(row[1]), float(row[2]), float(row[3]))
		if not base.is_empty():
			var key := str(base)
			if not by_base.has(key):
				by_base[key] = []
			by_base[key].append(not spec.is_empty())
		if spec.is_empty() or (board != null and (board.signal_name != "" or board.glow)):
			continue
		var p := Piece.new()
		p.image = image
		p.spec = spec
		p.x = float(row[1])
		p.y = float(row[2])
		p.z = float(row[3])
		p.board = board
		p.sprite = row[5]
		p.height = board.height if board != null else p.sprite.height
		var art: Dictionary = game.renderer.sprite_art(image)
		var wide := p.height * float(art["w"]) / maxf(1.0, float(art["h"]))
		p.radius = clampf(wide * (.5 if bool(spec.get("sign", false)) else .4), .12, 1.2)
		p.hp = float(spec.get("hp", 1.0))
		p.base = base
		p.id = "%s@%.2f,%.2f" % [image, p.x, p.y]
		pieces.append(p)
	var kept: Array = []
	for p: Piece in pieces:
		if not p.base.is_empty():
			# Sharing its base with something that never breaks, or the only
			# thing between two stretches of floor: it stays whole.
			if (by_base[str(p.base)] as Array).has(false) or _parts_floor(p.base):
				continue
		kept.append(p)
	pieces = kept
	for p: Piece in pieces:
		if p.base.is_empty():
			continue
		for q: Piece in pieces:
			if q != p and q.base == p.base:
				p.shares.append(q)


## The low base of furniture a thing standing at (x, y) has, if it blocks the
## way: a box no wider than a cell and a hand high (level_builder.gd town()'s
## solid base, a plan's stand()). Anything on a counter or a shelf has none.
func _base_under(x: float, y: float, z: float) -> PackedFloat32Array:
	if z > .05:
		return PackedFloat32Array()
	for fixture in game.world.near_fixtures.get(Vector2i(int(x), int(y)), []):
		var f: PackedFloat32Array = fixture
		if (
			f[0] <= x
			and x <= f[2]
			and f[1] <= y
			and y <= f[3]
			and f[4] - f[7] <= .12
			and maxf(f[2] - f[0], f[3] - f[1]) <= 1.2
		):
			return f
	return PackedFloat32Array()


## Whether taking this base away would join two stretches of floor that are
## not joined now (it stands alone across a way the level means to be shut):
## the open cells round what it closes must already reach one another nearby.
func _parts_floor(base: PackedFloat32Array) -> bool:
	var flow: FlowField = game.flow
	var w := flow.width
	var h := flow.height
	var closed := {}
	for cy in range(
		maxi(0, int(base[1] - FlowField.BODY)), mini(h - 1, int(base[3] + FlowField.BODY)) + 1
	):
		for cx in range(
			maxi(0, int(base[0] - FlowField.BODY)), mini(w - 1, int(base[2] + FlowField.BODY)) + 1
		):
			if flow.open[cy * w + cx] == 0 and game.world.solid[cy * w + cx] < 0:
				closed[Vector2i(cx, cy)] = true
	var ends: Array = []
	for c: Vector2i in closed:
		for n: Vector2i in FlowField.NEIGHBOURS.slice(0, 4):
			var q := c + n
			if (
				q.x >= 0
				and q.y >= 0
				and q.x < w
				and q.y < h
				and not closed.has(q)
				and flow.open[q.y * w + q.x] == 1
				and not ends.has(q)
			):
				ends.append(q)
	if ends.size() <= 1:
		return false
	var lo := Vector2i(int(base[0]) - 10, int(base[1]) - 10)
	var hi := Vector2i(int(base[2]) + 10, int(base[3]) + 10)
	var seen := {ends[0]: true}
	var todo: Array = [ends[0]]
	while not todo.is_empty():
		var c: Vector2i = todo.pop_back()
		for n: Vector2i in FlowField.NEIGHBOURS.slice(0, 4):
			var q: Vector2i = c + n
			if (
				q.x < maxi(0, lo.x)
				or q.y < maxi(0, lo.y)
				or q.x > mini(w - 1, hi.x)
				or q.y > mini(h - 1, hi.y)
				or seen.has(q)
				or closed.has(q)
				or flow.open[q.y * w + q.x] != 1
			):
				continue
			seen[q] = true
			todo.append(q)
	for q: Vector2i in ends:
		if not seen.has(q):
			return true
	return false


# ------------------------------------------------------------------- shots


## The nearest whole piece along a hitscan shot from (px, py) at eye height,
## nearer than `near`: its index (ray_piece) and how far (ray_d), or -1.
func ray(
	px: float, py: float, eye: float, ax: float, ay: float, slope: float, near: float, spread: float
) -> int:
	ray_piece = -1
	ray_d = near
	for i in pieces.size():
		var p: Piece = pieces[i]
		if p.broken:
			continue
		var dx := p.x - px
		var dy := p.y - py
		var d := dx * ax + dy * ay
		if d <= 0.0 or d >= ray_d or absf(dx * ay - dy * ax) >= p.radius + spread:
			continue
		var z := eye + d * slope
		var foot: float = game.world.stand(p) + p.z
		if z < foot - .05 or z > foot + p.height + .05:
			continue
		if game.world.visible(px, py, p.x, p.y, eye, z):
			ray_piece = i
			ray_d = d
	return ray_piece


## The whole piece a shot flying at (x, y, z) is in, or -1.
func touch(x: float, y: float, z: float, reach: float) -> int:
	for i in pieces.size():
		var p: Piece = pieces[i]
		if p.broken or absf(p.x - x) > reach + p.radius or absf(p.y - y) > reach + p.radius:
			continue
		var foot: float = game.world.stand(p) + p.z
		if (
			Vector2(p.x - x, p.y - y).length() < reach + p.radius * .7
			and z > foot - .05
			and z < foot + p.height + .05
		):
			return i
	return -1


## A shot or a swing struck piece i, going along (ax, ay).
func strike(i: int, amount: float, ax: float, ay: float) -> void:
	var p: Piece = pieces[i]
	if p.broken:
		return
	p.hp -= amount
	net_version += 1
	if p.hp <= 0.0:
		_break(p, ax, ay, FUSE_SHOT)
		return
	var stuff := String(p.spec.get("stuff", "wood"))
	var z: float = game.world.stand(p) + p.z + p.height * .5
	game.burst(p.x, p.y, z, String(SPECKS.get(stuff, "spark")), 3, .7)
	# A load of buckshot is one knock, not ten.
	if game.clock >= _chip_next:
		_chip_next = game.clock + .08
		game.sound_at(_chip_cue(p), p.x, p.y, .3)


## A blast at (x, y, z): what it reaches breaks (or takes the blast's damage,
## if it is tough and far), what stands loose a little further is pushed out,
## and the bits lying about are thrown.
func blast(x: float, y: float, z: float, radius: float, strength: float, energy: bool) -> void:
	var order := 0
	for p: Piece in pieces:
		if p.broken:
			continue
		var d := Vector2(p.x - x, p.y - y).length()
		# Seen at its middle: a low base (its own, a neighbour's) does not shield it.
		var mid: float = game.world.stand(p) + p.z + p.height * .5
		if d < radius + p.radius * .5 and game.world.visible(x, y, p.x, p.y, z, mid):
			var hurt := strength * maxf(0.0, 1.0 - d / (radius + .3)) * (.5 if energy else 1.0)
			p.hp -= hurt
			net_version += 1
			if p.hp <= 0.0:
				var away := Vector2(p.x - x, p.y - y).normalized()
				_break(p, away.x, away.y, FUSE_BLAST + FUSE_STEP * order)
				order += 1
				continue
		if d < radius * shove_reach and _loose(p) and game.world.visible(x, y, p.x, p.y, z, mid):
			_push(p, x, y, (1.0 - d / (radius * shove_reach)) * shove_most)
	for b: Bit in bits:
		if absf(b.x - x) > radius * 1.4 or absf(b.y - y) > radius * 1.4:
			continue
		var push := Tumble.shove(x, y, radius * 1.4, 2.5 if energy else 4.5, b.x, b.y)
		if push != Vector3.ZERO and game.world.visible(x, y, b.x, b.y):
			b.vx += push.x * dice.randf_range(.7, 1.2)
			b.vy += push.y * dice.randf_range(.7, 1.2)
			b.vz += push.z
			b.rest = false
			_resting_dirty = true


## Whether a blast can push it: standing on the ground, in nobody's way.
func _loose(p: Piece) -> bool:
	return p.base.is_empty() and p.z <= .05 and not bool(p.spec.get("sign", false))


func _push(p: Piece, x: float, y: float, far: float) -> void:
	var away := Vector2(p.x - x, p.y - y)
	if away.length() < .01 or far < .02:
		return
	var to := Vector2(p.x, p.y) + away.normalized() * far
	if not game.world.blocked(to.x, to.y, .18):
		_place(p, to.x, to.y)


func _place(p: Piece, x: float, y: float) -> void:
	var shown := _shown(p)
	p.x = x
	p.y = y
	net_version += 1
	if p.board != null:
		p.board.x = x
		p.board.y = y
	if p.sprite != null:
		p.sprite.x = x
		p.sprite.y = y
	if shown != null:
		shown.x = x
		shown.y = y
		_widen(shown)


## The sprite the view draws for a piece out of the fixed sprites
## (game_view.gd lists them once and again only when what they show changes:
## a piece changes its own in place, so nothing is listed again).
func _shown(p: Piece) -> Renderer.Sprite:
	if p.sprite != null:
		return p.sprite
	for s: Renderer.Sprite in game.fixed_sprites:
		if (
			s.image == p.board.image
			and absf(s.x - p.board.x) < .001
			and absf(s.y - p.board.y) < .001
		):
			return s
	return null


## Make sure the block a fixed sprite is in reaches over it, wider or moved.
func _widen(s: Renderer.Sprite) -> void:
	var index: int = game.fixed_sprites.find(s)
	if index < 0:
		return
	var art: Dictionary = game.renderer.sprite_art(s.image)
	var half := s.height * float(art["w"]) / maxf(1.0, float(art["h"])) * .5
	for b in game.fixed_blocks.size():
		var block: Array = game.fixed_blocks[b]
		if (block[3] as PackedInt32Array).has(index):
			var far := Vector2(s.x - float(block[0]), s.y - float(block[1])).length() + half + .3
			block[2] = maxf(float(block[2]), far)
			# game_view.gd _seen() reads the reach from fixed_cull.
			if game.fixed_cull.size() > b * 3 + 2:
				game.fixed_cull[b * 3 + 2] = block[2]
			return


## A fuel drum that went up (game_combat.gd drum_hit()): its burst shell stays.
func wreck(x: float, y: float, image: String) -> void:
	if not game.art.has_art(image):
		return
	wrecks.append([x, y, image, _tall(image, 1.0, "")])
	_throw(x, y, game.world.elevation(x, y) + .5, "redtin", 6, 0.0, 0.0)


# ------------------------------------------------------------------ breaking


## Break it: its broken picture, its base out of the way, and (unless quiet,
## as from a save) its noise and bits; an explosive goes up after `fuse`
## seconds unless `cook` is off.
func _break(p: Piece, ax: float, ay: float, fuse: float, quiet := false, cook := true) -> void:
	p.broken = true
	net_version += 1
	var broken := String(p.spec["broken"])
	var tall := _tall(broken, p.height, p.image)
	var shown := _shown(p)
	if p.board != null:
		p.board.image = broken
		p.board.height = tall
	if p.sprite != null:
		p.sprite.image = broken
		p.sprite.height = tall
	if shown != null:
		shown.image = broken
		shown.height = tall
		_widen(shown)
	if not p.base.is_empty():
		var all_down := true
		for q: Piece in p.shares:
			all_down = all_down and q.broken
		if all_down:
			_free(p.base)
	if cook and p.spec.has("blast"):
		cooking.append([pieces.find(p), fuse])
	if quiet:
		return
	if cook and p.spec.has("blast"):
		game.sound_at("fuse_short", p.x, p.y, .7)
	var stuff := String(p.spec.get("stuff", "wood"))
	var z: float = game.world.stand(p) + p.z + p.height * .5
	# A row going at once is one crash, not one each.
	var loud: bool = game.clock >= _crash_next
	if loud:
		_crash_next = game.clock + .05
		var crash := "sign_shot" if bool(p.spec.get("sign", false)) else "impact_wood"
		game.sound_at(String(p.spec.get("cue", crash)), p.x, p.y, .8)
	if loud and p.spec.has("cue2"):
		game.sound_at(String(p.spec["cue2"]), p.x, p.y, .6)
	var sign := bool(p.spec.get("sign", false))
	_throw(p.x, p.y, z, stuff, 2 if sign else int(p.spec.get("bits", 6)), ax, ay)
	game.burst(p.x, p.y, z, String(SPECKS.get(stuff, "spark")), 4 if sign else 9, 1.2)
	# Breaking things is loud: whoever is near and can see it comes to look.
	game.disturb(p.x, p.y, 4.5, z)


## The knock of a shot that does not break it yet.
func _chip_cue(p: Piece) -> String:
	if p.spec.has("chip"):
		return String(p.spec["chip"])
	if bool(p.spec.get("sign", false)):
		return "sign_shot"
	return String(p.spec.get("cue", "impact_wood"))


## How tall a broken picture stands: a modelled prop's at the scale the whole
## one was stood (both are rendered 60 pixels to the unit), a sign's as it was.
func _tall(broken: String, whole_height: float, whole: String) -> float:
	var art: Dictionary = game.renderer.sprite_art(broken)
	var own := float(art["h"]) / 60.0
	if whole.begins_with("town_"):
		var was: Dictionary = game.renderer.sprite_art(whole)
		return whole_height * float(art["h"]) / maxf(1.0, float(was["h"]))
	if whole != "" and not whole.begins_with("prop_"):
		return whole_height
	return own


## Take a broken thing's base out of the way and open its cells to the paths.
func _free(base: PackedFloat32Array) -> void:
	game.world.drop_volume(base)
	game.reopen_paths(base[0], base[1], base[2], base[3])
	game.route_sig = []


## Bits of a wall that broke (features/wall_breaks.gd: glass, splinters),
## thrown, kept and saved with the rest.
func scatter(x: float, y: float, z: float, stuff: String, count: int, ax: float, ay: float) -> void:
	_throw(x, y, z, stuff, count, ax, ay)


func _throw(x: float, y: float, z: float, stuff: String, count: int, ax: float, ay: float) -> void:
	var size := float(BIT_SIZE.get(stuff, .07))
	for k in count:
		var b := Bit.new()
		b.x = x + dice.randf_range(-.12, .12)
		b.y = y + dice.randf_range(-.12, .12)
		if game.world.blocked(b.x, b.y, .05):
			b.x = x
			b.y = y
		b.z = z + dice.randf_range(-.15, .15)
		var a := dice.randf() * TAU
		var speed := dice.randf_range(.6, 2.2)
		b.vx = cos(a) * speed + ax * dice.randf_range(.5, 2.0)
		b.vy = sin(a) * speed + ay * dice.randf_range(.5, 2.0)
		b.vz = dice.randf_range(1.0, 3.0)
		b.image = "fx_brk_%s_%d" % [stuff, k % 2]
		b.size = size * dice.randf_range(.8, 1.25)
		b.flip = dice.randf() < .5
		bits.append(b)
	while bits.size() > bits_max:
		bits.pop_front()
		_resting_dirty = true


func _feel(image: String) -> Tumble.Feel:
	var feel: Tumble.Feel = _feels.get(image)
	if feel == null:
		var light := false
		for stuff: String in LIGHT:
			light = light or image.contains(stuff)
		feel = Tumble.Feel.new(.04, .35, .15 if light else .3, 4.0 if light else 2.6)
		feel.gravity = 5.0 if light else Tumble.GRAVITY
		feel.hard = .9
		_feels[image] = feel
	return feel


func _tick(dt: float) -> void:
	if not cooking.is_empty():
		var going: Array = []
		for c: Array in cooking:
			c[1] = float(c[1]) - dt
			if float(c[1]) <= 0.0:
				going.append(c)
		for c: Array in going:
			cooking.erase(c)
			var p: Piece = pieces[int(c[0])]
			var shot := Game.Shot.new(
				p.x,
				p.y,
				game.world.stand(p) + p.z + p.height * .45,
				0.0,
				0.0,
				0.0,
				String(p.spec["blast"]),
				0.0,
				false,
				0
			)
			shot.owner = -1
			game.explode(shot)
	for b: Bit in bits:
		if b.rest:
			continue
		var ox := b.x
		var oy := b.y
		var hit := Tumble.step(game.world, b, _feel(b.image), dt)
		if hit & Tumble.RESTED:
			b.rest = true
			_resting_dirty = true
		elif b.vz == 0.0:
			var was := int(b.roll / .15)
			b.roll += Vector2(b.x - ox, b.y - oy).length()
			if int(b.roll / .15) != was:
				b.flip = not b.flip


func sprites() -> Array:
	var out: Array = []
	if _resting_dirty:
		_sort_resting()
	for block: Array in _resting:
		if game.in_view(block[0], block[1], block[2]):
			out.append_array(block[3])
	for b: Bit in bits:
		if not b.rest and game.in_view(b.x, b.y, b.size + .2):
			var s: Renderer.Sprite = game.pooled(b.x, b.y, b.image, b.size, b.z)
			s.flip = b.flip
			out.append(s)
	for w: Array in wrecks:
		if game.in_view(float(w[0]), float(w[1]), 1.2):
			out.append(
				game.pooled(w[0], w[1], String(w[2]), w[3], game.world.elevation(w[0], w[1]))
			)
	return out


func _sort_resting() -> void:
	_resting_dirty = false
	var by_key := {}
	for b: Bit in bits:
		if not b.rest:
			continue
		if b.sprite == null:
			b.sprite = Renderer.Sprite.new(b.x, b.y, b.image, b.size, b.z)
			b.sprite.flip = b.flip
		b.sprite.x = b.x
		b.sprite.y = b.y
		b.sprite.z = b.z
		var key := Vector2i(floori(b.x / BLOCK), floori(b.y / BLOCK))
		if not by_key.has(key):
			by_key[key] = []
		by_key[key].append(b.sprite)
	_resting.clear()
	for key: Vector2i in by_key:
		var mx := (key.x + .5) * BLOCK
		var my := (key.y + .5) * BLOCK
		var reach := 0.0
		for s: Renderer.Sprite in by_key[key]:
			reach = maxf(reach, Vector2(s.x - mx, s.y - my).length() + s.height + .3)
		_resting.append([mx, my, reach, by_key[key]])


# -------------------------------------------------------------------- saves


func save() -> Dictionary:
	var broken: Array = []
	var moved: Array = []
	for p: Piece in pieces:
		if p.broken:
			broken.append(p.id)
		if p.id != "%s@%.2f,%.2f" % [p.image, p.x, p.y]:
			moved.append([p.id, snappedf(p.x, .01), snappedf(p.y, .01)])
	var cook: Array = []
	for c: Array in cooking:
		cook.append([(pieces[int(c[0])] as Piece).id, snappedf(float(c[1]), .01)])
	var lying: Array = []
	for b: Bit in bits:
		lying.append([snappedf(b.x, .01), snappedf(b.y, .01), snappedf(b.z, .01), b.image])
	if broken.is_empty() and moved.is_empty() and wrecks.is_empty() and lying.is_empty():
		return {}
	return {
		"broken": broken,
		"moved": moved,
		"cooking": cook,
		"bits": lying,
		"wrecks": wrecks.duplicate(true)
	}


func restore(state: Dictionary) -> void:
	var by_id := {}
	for p: Piece in pieces:
		by_id[p.id] = p
	var cook := {}
	for row in state.get("cooking", []):
		if row is Array and row.size() == 2:
			cook[String(row[0])] = float(row[1])
	for key in state.get("broken", []):
		var p: Piece = by_id.get(String(key))
		if p == null or p.broken:
			continue
		# Broken before the save: its picture and its freed cell, but no noise,
		# no bits (those come back below) and no blast unless it was going up.
		_break(p, 0.0, 0.0, float(cook.get(p.id, 0.0)), true, cook.has(p.id))
	for row in state.get("moved", []):
		if row is Array and row.size() == 3 and by_id.has(String(row[0])):
			_place(by_id[String(row[0])], float(row[1]), float(row[2]))
	# Listed again with what was broken and moved before the save.
	game.fixed_sprites_key = []
	bits.clear()
	for row in state.get("bits", []):
		if row is Array and row.size() == 4 and game.art.has_art(String(row[3])):
			var b := Bit.new()
			b.x = float(row[0])
			b.y = float(row[1])
			b.z = float(row[2])
			b.image = String(row[3])
			for stuff: String in BIT_SIZE:
				if b.image.contains("_%s_" % stuff):
					b.size = float(BIT_SIZE[stuff])
			b.rest = true
			bits.append(b)
	_resting_dirty = true
	wrecks.clear()
	for row in state.get("wrecks", []):
		if row is Array and row.size() == 4 and game.art.has_art(String(row[2])):
			wrecks.append([float(row[0]), float(row[1]), String(row[2]), float(row[3])])
