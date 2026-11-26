## Muzzles, owned by features/gun_fx.gd (pass 15; looks only, its own sums,
## never game.rng, nothing kept in a save or carried):
##
## - A hand's shot lights the yard round him a moment (effects.cfg
##   [enemy_muzzle], [light.enemy_muzzle] and _scatter): when a hand whose
##   brain fires a gun starts his recovery (Enemy.recovery jumps: he has just
##   attacked), a light at his gun for its `life`. With the player's own, the
##   nearest Effects.MAX_LIGHTS win (view_lights.gd).
## - Smoke curls up off the player's muzzle after a burst (effects.cfg
##   [gun_smoke]): `burst` shots inside `window`, or one shot of a `big` gun,
##   then `wait` with no more; a wisp rising from the muzzle on the picture,
##   swaying as it climbs, thinning in dithered steps over its last `thin`
##   seconds, for `life` seconds or until he fires again, lowers the gun,
##   reloads or takes another. Drawn from a few small pictures made once.
class_name MuzzleLooks
extends RefCounted

## The wisp's picture: its size, frames of its sway, steps of its rise and
## of its thinning.
const WISP_W := 21
const WISP_H := 46
const WISP_FRAMES := 8
const WISP_FPS := 9.0
const RISE_STEPS := 4
const THIN_STEPS := 4
const RISE := .35
const BAYER: Array[int] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]

## Drawn wisps: key -> PackedByteArray.
static var _made := {}

var game: Game
## The flashes going: [x, y, z, born, light source].
var flashes: Array = []
## Each gunman's recovery last tick (Enemy -> float).
var _was := {}
## The player's last shots' times, the gun and the wisp: when it began
## (below 0: none) and whose.
var _shots: Array[float] = []
var _shot_gun := -1
var wisp_at := -1.0
var wisp_gun := -1


func _init(p_game: Game) -> void:
	game = p_game


static func n(section: String, key: String, fallback: Variant) -> Variant:
	return Effects.num(section, key, fallback)


# ------------------------------------------------------------ the hands' shots


## Each tick: the gunmen within reach who have just fired light up.
func tick_hands() -> void:
	var p := game.local_player if game.local_player != null else game.player
	var reach: float = n("enemy_muzzle", "reach", 24.0)
	var brains: Array = n("enemy_muzzle", "brains", [])
	var scatter: Array = n("enemy_muzzle", "scatter", [])
	var seen := {}
	var px := p.x
	var py := p.y
	for e: Enemy in game.enemies:
		# (The reach first: most of a level's hands are far off.)
		if absf(e.x - px) > reach or absf(e.y - py) > reach:
			continue
		if not e.alive or not e.hostile or e.dormant:
			continue
		if not brains.has(e.brain) and not brains.has(e.kind):
			continue
		var was: float = _was.get(e, e.recovery)
		seen[e] = e.recovery
		if e.recovery > was + .05:
			var source := "enemy_muzzle_scatter" if scatter.has(e.brain) else "enemy_muzzle"
			var out := e.radius + .25
			flashes.append(
				[
					e.x + cos(e.angle) * out,
					e.y + sin(e.angle) * out,
					e.z + e.height * .62,
					game.clock,
					source
				]
			)
	_was = seen
	while not flashes.is_empty():
		var first: Array = flashes[0]
		var born: float = first[3]
		var spec: Dictionary = Effects.LIGHTS.get(str(first[4]), {})
		var life: float = spec.get("life", .1)
		if game.clock - born <= life and game.clock >= born:
			break
		flashes.pop_front()


## The flashes' lights now (Effects.light rows), dying away over their life.
func lights(out: Array) -> void:
	for f: Array in flashes:
		var source := str(f[4])
		var spec: Dictionary = Effects.LIGHTS.get(source, {})
		var spec_life: float = spec.get("life", .1)
		var life := maxf(.01, spec_life)
		var born: float = f[3]
		var left := 1.0 - (game.clock - born) / life
		if left <= 0.0:
			continue
		var fx: float = f[0]
		var fy: float = f[1]
		var fz: float = f[2]
		var lit: Variant = Effects.light(source, fx, fy, fz, left * left, game.clock)
		if lit != null:
			out.append(lit)


# ------------------------------------------------------------- the muzzle wisp


## Whether gun `gun` smokes at all (weapons.cfg muzzle_style: fire, smoke).
static func smokes(gun: int) -> bool:
	if not Weapons.MUZZLE_STYLE.has(gun):
		return false
	var style: Array = Weapons.MUZZLE_STYLE[gun]
	var scale: float = style[2]
	return str(style[0]) == "fire" and scale > 0.0


## The player fired gun `gun` (this machine's: gun_fx's _fired).
func shot(gun: int) -> void:
	wisp_at = -1.0
	if gun != _shot_gun:
		_shots.clear()
		_shot_gun = gun
	_shots.append(game.clock)
	var window: float = n("gun_smoke", "window", 1.2)
	while not _shots.is_empty() and game.clock - _shots[0] > window:
		_shots.pop_front()


## Each tick: a wisp starts once the shooting stops after a burst, and ends.
func tick_wisp() -> void:
	var arms := game.armory
	if wisp_at >= 0.0:
		var life: float = n("gun_smoke", "life", 2.4)
		var ended := game.clock - wisp_at > life or game.clock < wisp_at
		if ended or not _steady(arms, wisp_gun):
			wisp_at = -1.0
		return
	if _shots.is_empty():
		return
	var last := _shots[_shots.size() - 1]
	var wait: float = n("gun_smoke", "wait", .12)
	if game.clock - last < wait:
		return
	var burst: int = n("gun_smoke", "burst", 3)
	var big: Array = n("gun_smoke", "big", [])
	var named := str(Weapons.NAMES[_shot_gun]) if _shot_gun >= 0 else ""
	var enough := _shots.size() >= burst or big.has(named)
	if enough and smokes(_shot_gun) and _steady(arms, _shot_gun):
		wisp_at = game.clock
		wisp_gun = _shot_gun
	_shots.clear()


## The gun in hand is `gun`, up and not being reloaded.
func _steady(arms: Weapons.Armory, gun: int) -> bool:
	return (
		arms.active == gun
		and arms.shown_gun() == gun
		and arms.lower < .2
		and arms.reload == 0.0
		and not arms.holstered
	)


## The wisp over the view at the muzzle (gun_fx's draw_view, under the gun).
func draw(c: Canvas) -> void:
	if wisp_at < 0.0 or game.player.health <= 0 or game.player.scoped:
		return
	var muzzle: Vector2 = Weapons.muzzle_at
	if muzzle.x < 0.0 or not _steady(game.armory, wisp_gun):
		return
	var age := game.clock - wisp_at
	var life: float = n("gun_smoke", "life", 2.4)
	var thin: float = n("gun_smoke", "thin", 1.2)
	var rise := mini(RISE_STEPS - 1, int(age / RISE * RISE_STEPS))
	var gone := clampf((age - (life - thin)) / maxf(thin, .01), 0.0, .999)
	var thinned := int(gone * THIN_STEPS)
	var frame := int(age * WISP_FPS) % WISP_FRAMES
	var key := "wisp|%d|%d|%d" % [frame, rise, thinned]
	var data: PackedByteArray = _made.get(key, PackedByteArray())
	if data.is_empty():
		data = wisp(frame, rise, thinned)
		_made[key] = data
	c.blit_rgba(data, WISP_W, WISP_H, int(muzzle.x) - WISP_W / 2, int(muzzle.y) - WISP_H + 2, key)


## One picture of the wisp: frame `frame` of its sway, risen `rise` steps of
## RISE_STEPS, thinned `thinned` of THIN_STEPS. Grey smoke, lighter on its
## left, a thread at the muzzle widening and curling as it climbs, its pixels
## dropped in a 4x4 ordered dither as it thins (the palette's way).
static func wisp(frame: int, rise: int, thinned: int) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(WISP_W * WISP_H * 4)
	var phase := frame * TAU / WISP_FRAMES
	var top := int(WISP_H * float(rise + 1) / RISE_STEPS)
	var keep := 1.0 - float(thinned) / THIN_STEPS
	for r in top:
		var up := float(r) / WISP_H
		# Two sways, the slow one growing as it climbs: a curl, not a zigzag.
		var mid := (
			(WISP_W - 1) * .5
			+ sin(r * .16 - phase) * (.4 + 3.8 * up)
			+ sin(r * .43 - phase * 2.0) * .9 * up
			+ up * 2.5
		)
		var half := 1.1 + 3.4 * up
		var dense := (1.0 - up * .72) * keep
		var y := WISP_H - 1 - r
		for x in WISP_W:
			var off := (float(x) - mid) / half
			if absf(off) > 1.0:
				continue
			var need := float(BAYER[(x % 4) * 4 + (y % 4)]) / 16.0
			if need >= dense * (1.0 - off * off * .7):
				continue
			var o := (y * WISP_W + x) * 4
			# Lit from the upper left: lighter on its left, a darker skin.
			var grey := lerpf(196.0, 118.0, clampf(absf(off) * .8 + (off * .25), 0.0, 1.0))
			data[o] = roundi(grey)
			data[o + 1] = roundi(grey * .98)
			data[o + 2] = roundi(grey * .93)
			data[o + 3] = 176
	return data
