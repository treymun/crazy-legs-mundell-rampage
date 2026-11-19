## The big breaks' effects (looks only, src/set_piece_wreck.gd's): billows of
## barn dust rolling out along the ground (fx_barndust), gushes of water
## (fx_gush) and flares (fx_boom), drawn as hard-edged pooled sprites; the
## splinters, hay and splashes as looks specks; the view shaken by how near;
## the sounds, each kept from playing over itself. Its own dice, never
## game.rng.
class_name SetPieceFx
extends RefCounted

const Shape := preload("res://src/set_piece_shape.gd")
## Puff kinds.
const DUST := 0
const GUSH := 1
const BOOM := 2


## A billow of dust, a gush of water or a flare.
class Puff:
	var p := Vector3.ZERO
	var v := Vector3.ZERO
	var born := 0.0
	var life := 3.0
	var s0 := .6
	var s1 := 2.0
	var kind := DUST
	var look := 0
	var drag := 1.5
	var fall := 0.0


var game: Game
var puffs: Array[Puff] = []
var dice := RandomNumberGenerator.new()
## At most (fewer on a phone or the LOW tier).
var most_puffs := 44
var most_specks := 60
var _sound_next := {}


func _init(g: Game, few: bool) -> void:
	game = g
	dice.seed = 1912
	most_puffs = int(Shape.num("looks", "puffs_low" if few else "puffs", 44.0))
	most_specks = int(Shape.num("looks", "specks_low" if few else "specks", 60.0))


func puff(
	kind: int, p: Vector3, v: Vector3, life: float, s0: float, s1: float, drag := 1.4, fall := 0.0
) -> void:
	if puffs.size() >= most_puffs:
		return
	var f := Puff.new()
	f.kind = kind
	f.p = p
	f.v = v
	f.born = game.clock
	f.life = life
	f.s0 = s0
	f.s1 = s1
	f.drag = drag
	f.fall = fall
	f.look = dice.randi_range(0, 3)
	puffs.append(f)


func tick(dt: float) -> void:
	if puffs.is_empty():
		return
	var kept: Array[Puff] = []
	for f: Puff in puffs:
		if game.clock - f.born > f.life:
			continue
		f.p += f.v * dt
		var slow := exp(-f.drag * dt)
		f.v.x *= slow
		f.v.y *= slow
		if f.fall > 0.0:
			f.v.z -= f.fall * dt
			var w := game.world
			var floor_z := w.elevation(
				clampf(f.p.x, 0.0, w.width - .01), clampf(f.p.y, 0.0, w.height - .01)
			)
			if f.p.z < floor_z:
				f.p.z = floor_z
				f.v.z = 0.0
		elif f.kind == DUST:
			# A billow rolls along the ground and rises slowly.
			f.v.z = lerpf(f.v.z, .06, minf(1.0, dt * 2.0))
		kept.append(f)
	puffs = kept


## Looks-only specks (game.specks; this feature's dice).
func specks(x: float, y: float, z: float, kind: String, n: int, speed: float, up: float) -> void:
	for m in n:
		if game.specks.size() >= 100 or m >= most_specks:
			return
		var a := dice.randf() * TAU
		var s := dice.randf_range(.3, speed)
		game.specks.append(
			GameState.Speck.new(
				x,
				y,
				z,
				cos(a) * s,
				sin(a) * s,
				dice.randf_range(.3, up),
				dice.randf_range(.5, 1.1),
				kind
			)
		)


## The view shaken by how near (x, y) is to this machine's player.
func shake(x: float, y: float, amount: float) -> void:
	var p := game.local_player if game.local_player != null else game.player
	if p == null:
		return
	var reach := Shape.num("looks", "shake_reach", 26.0)
	var k := clampf(1.0 - Vector2(x - p.x, y - p.y).length() / reach, 0.0, 1.0)
	game.shake = minf(1.0, game.shake + amount * k * sqrt(k))


func sound(cue: String, x: float, y: float, strength: float, gap: float) -> void:
	if game.clock < Shape.f(_sound_next.get(cue, -1.0)):
		return
	_sound_next[cue] = game.clock + gap
	if game.art != null and not game.art.sfx_index.has(cue):
		return
	game.sound_at(cue, x, y, strength, dice.randf_range(.92, 1.08))


## The puffs as this frame's sprites.
func draw(out: Array) -> void:
	var t := game.clock
	var me := game.local_player if game.local_player != null else game.player
	for f: Puff in puffs:
		if not game.in_view(f.p.x, f.p.y, f.s1):
			continue
		var age := clampf((t - f.born) / f.life, 0.0, 1.0)
		var near_k := 1.0
		if me != null:
			# One right in front stays small: full size it would fill the view.
			near_k = clampf(Vector2(f.p.x - me.x, f.p.y - me.y).length() / 3.5, .25, 1.0)
		var size := lerpf(f.s0, f.s1, sqrt(age)) * near_k
		var image := ""
		var glow := false
		match f.kind:
			DUST:
				# Hard-edged: it shrinks away at the end, never fades.
				size *= clampf((1.0 - age) / .25, 0.0, 1.0)
				image = "fx_barndust_%d" % (3 if age > .7 else f.look)
			GUSH:
				size *= clampf((1.0 - age) / .3, 0.0, 1.0)
				image = "fx_gush_%d" % ((f.look + int(age * 9.0)) % 4)
			BOOM:
				image = "fx_boom_%d" % mini(7, int(age * 8.0))
				glow = true
		if size < .05:
			continue
		var s := game.pooled(f.p.x, f.p.y, image, size, f.p.z)
		s.glow = glow
		# Dust and spray blended as a blast's smoke is (hard edged still).
		s.translucent = f.kind != BOOM
		out.append(s)
