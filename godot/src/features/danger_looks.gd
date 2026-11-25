## Wind-ups read in the world (pass 15, looks only; the arrows and the
## hazards' marks are src/danger_marks.gd, the model's amber flash
## EnemyLooks.tell):
##
## - A regular hand's big wind-up (hits.cfg [danger] `big_windup` seconds or
##   more: the chain hand, the boilerback, the bottle tosser, the yard deputy,
##   the millhand...) marks the floor where it is aimed (Enemy.aim_mark, where
##   the blow or the throw goes) as the bosses' do (features/boss_fight.gd):
##   `ring_dots` warning marks closing in round the spot as the wind-up runs
##   down, its middle filling. The bosses keep their own.
## - A ranged hand in the last `tell_share` of his wind-up shows a glint at his
##   raised gun hand, toward his aim.
##
## Reads only what play carries (each enemy's windup and aim_mark), so a
## client draws what the host's hands are doing; nothing here is carried.
extends GameFeature

static var BIG: float = HitData.value("danger", "big_windup", .6)
static var RING_DOTS: int = HitData.value("danger", "ring_dots", 12)
static var RING_WIDE: float = HitData.value("danger", "ring_wide", 3.2)
static var RING_TIGHT: float = HitData.value("danger", "ring_tight", .5)
## The glint's size, how high up the body (a share of his height) and how
## far to his right it shows: where a raised gun or chain is held.
const GLINT := .2
const GUN_UP := .8
const GUN_SIDE := .22


func id() -> String:
	return "danger_looks"


## Whether `e` gets a ring: a regular hand, alive, winding up a big one at
## a player he sees.
static func ringed(e: Enemy) -> bool:
	if e.windup <= 0.0 or not e.alive or e.dormant or not e.hostile or not e.player_seen:
		return false
	if e.aim_mark == null or Enemy.BOSS_TITLES.has(e.kind):
		return false
	var spec: Array = Enemy.WINDUP.get(e.kind, [])
	if spec.is_empty():
		return false
	var whole: float = spec[0]
	return whole >= BIG


func ground_marks() -> Array:
	var out: Array = []
	for e: Enemy in game.enemies:
		if e.windup > 0.0 and ringed(e):
			out.append_array(_ring(e))
	return out


## The ring round `e`'s aim point, closing as his wind-up runs down.
func _ring(e: Enemy) -> Array:
	var out: Array = []
	var spec: Array = Enemy.WINDUP[e.kind]
	var whole: float = spec[0]
	var t := clampf(1.0 - e.windup / maxf(.05, whole), 0.0, 1.0)
	var mx: float = e.aim_mark[0]
	var my: float = e.aim_mark[1]
	var w: LevelData = game.world
	if mx < 0.0 or my < 0.0 or mx >= w.width or my >= w.height:
		return out
	var r := lerpf(RING_WIDE, RING_TIGHT, t)
	var dot := .13 + .05 * t
	for k in RING_DOTS:
		var a := k * TAU / RING_DOTS + t * .9
		var x := mx + cos(a) * r
		var y := my + sin(a) * r
		if w.blocked(x, y, .05):
			continue
		out.append(View.GroundMark.new(x, y, w.elevation(x, y) + .005, a, dot, dot, "mark_warning"))
	var fill := .10 + .34 * t
	out.append(
		View.GroundMark.new(mx, my, w.elevation(mx, my) + .006, 0.0, fill, fill, "mark_slam")
	)
	return out


func sprites() -> Array:
	var out: Array = []
	for e: Enemy in game.enemies:
		if e.windup <= 0.0 or e.aim_mark == null or not Enemy.RANGED.has(e.kind):
			continue
		if EnemyLooks.tell(e, game.clock) <= 0.0 or not game.in_view(e.x, e.y, 2.0):
			continue
		var tx: float = e.aim_mark[0]
		var ty: float = e.aim_mark[1]
		var a := atan2(ty - e.y, tx - e.x)
		var reach := e.radius + .1
		# His right hand: his aim turned a quarter (the view's left as he faces it).
		var right := Vector2(-sin(a), cos(a)) * GUN_SIDE
		var z := game.world.stand(e) + e.z + e.height * e.variant * GUN_UP
		var flash := fposmod(game.clock * 12.0, 1.0) < .5
		var glint := View.Sprite.new(
			e.x + cos(a) * reach + right.x,
			e.y + sin(a) * reach + right.y,
			"fx_glint_1" if flash else "fx_glint_0",
			GLINT * (1.0 if flash else .75),
			z - GLINT * .5
		)
		glint.glow = true
		out.append(glint)
	return out
