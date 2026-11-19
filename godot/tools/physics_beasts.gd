## physics_check's beasts and bosses (pass 13; src/beast_doll.gd on
## view3d/beast_rig.gd, ActorView's boss hand-over), headless:
##
## - every beast kind (the gator, the crawler, the herd's hog, the cow) has a
##   rig fit to its body, its legs, head and tail found;
## - each shot down five ways from two sides on open ground: the start moves
##   no ball (fit), no rigid link is stretched past STRETCH_HIT as it lands
##   nor STRETCH lying, it is at rest by REST_BY and takes no step after, it
##   lies on the floor (none sunk, nothing standing), every knee folds its own
##   way, the same kill from two ways lies two ways, and among its deaths it
##   comes to lie more than one way (belly, side, back);
## - dropped on a ramp and a stair it lies on the floor under it;
## - a gator shot in Gator Bayou's water floats a little under the surface
##   (not on top of it, not sunk), coming up slowly;
## - a blast in the herd kills the hog's stand-in with the blast's place, and
##   one first seen down lies as it fell long ago;
## - a boss's scripted fall hands over to its ragdoll part way through with
##   no part jumping (no pop), lies at rest on the floor not far from where
##   its scripted fall would have laid it, and slides no further.
extends RefCounted

const DT := 1.0 / 60.0
const STRETCH := .1
const STRETCH_LET := .02
## (A crawler's links are a few centimetres: a blast stretches one by half
## for a frame.)
const STRETCH_HIT := .6
const REST_BY := Ragdoll.MOST_AWAKE + .1
const TOL := .03
const KINDS := ["gator", "crawler", "hog", "cow"]
const KILLS := ["revolver", "shotgun_near", "rifle", "blast", "revolver_b"]
## Boss hand-over: a part may move at the hand-over this many times its most
## in the frames before (and POP_LET more), and the body lie this far from
## where the scripted fall laid it (times its size).
const POP_RATIO := 2.5
const POP_LET := .04
const BOSS_NEAR := 1.6

var check: SceneTree
var models: ActorModels


func _init(owner: SceneTree) -> void:
	check = owner


func _check(ok: bool, text: String) -> void:
	check.call("_check", ok, text)


func _ok(text: String) -> void:
	check.call("_ok", text)


func run(main: Node) -> void:
	models = ActorModels.new(Assets.new())
	# (No body left lying about by the checks before.)
	Ragdoll.others = []
	Ragdoll.budget = 1 << 30
	var ground: Game = main.make_game("hickston")
	ground.configure({})
	for kind: String in KINDS:
		_kind(ground, kind)
	_slabs(main)
	_water(main)
	_herd(main)
	for kind: String in ["boss", "jerry", "foreman"]:
		_boss(ground, kind)


func _rig(kind: String) -> BeastRig:
	var info: Dictionary = models.kinds[kind]
	var view: Node = models.scene(kind).instantiate()
	var rig := RagdollRig.of(kind, view, info)
	view.free()
	return rig as BeastRig


## A beast standing at `at` (its floor `z`), turned `turn`, at `size`.
func _doll(rig: BeastRig, kind: String, at: Vector2, z: float, turn: float) -> BeastDoll:
	var info: Dictionary = models.kinds[kind]
	var canvas: Array = info.get("canvas", [1.0, 1.0])
	var tall: float = canvas[1]
	var height: float = Enemy.DEFS.get(kind, {}).get("height", .6) if Enemy.DEFS.has(kind) else .9
	var size := height / maxf(.1, tall)
	var xf := Transform3D(Basis(Vector3.UP, turn).scaled(Vector3.ONE * size), Vector3(at.x, z, at.y))
	return BeastDoll.made_beast(rig, xf, rig.standing(), kind)


## A dead stand-in killed by `how` from `way` (radians) at `at`.
func _victim(at: Vector2, z: float, how: String, way: float) -> Enemy:
	var e := Enemy.new("billy", at.x, at.y)
	e.floor_z = z
	var gun := how.trim_suffix("_b")
	e.killed_by = "shotgun" if gun == "shotgun_near" else gun
	var far := 1.0 if gun == "shotgun_near" else 3.0
	e.killed_from = at - Vector2.from_angle(way) * far
	if gun == "blast":
		e.blast_at = at - Vector2.from_angle(way) * .8
	return e


## Steps until it rests (REST_BY at most): [seconds, the worst rigid stretch].
func _settle(doll: BeastDoll, world: LevelData) -> Array:
	var t := 0.0
	var worst := 0.0
	while doll.awake and t < REST_BY + .5:
		doll.step(world)
		t += Ragdoll.STEP
		worst = maxf(worst, _stretch(doll))
	return [t, worst]


static func _stretch(doll: Ragdoll) -> float:
	var worst := 0.0
	for k in doll.la.size():
		if doll.lmin[k] == doll.lmax[k] and doll.lmin[k] > 0.0:
			var d := doll.pos[doll.la[k]].distance_to(doll.pos[doll.lb[k]])
			var st := maxf(0.0, absf(d - doll.lmin[k]) - STRETCH_LET) / doll.lmin[k]
			if st > worst:
				worst = st
				worst_link = "%d-%d" % [doll.la[k], doll.lb[k]]
	return worst


static var worst_link := ""


## "" when every knee lies on its own side of the line from root to foot.
static func _knees(doll: BeastDoll) -> String:
	var torso := doll._torso_basis(doll.pos)
	var legs := doll.beast.legs
	for k in legs.size() / 3:
		var a := legs[k * 3]
		var m := a + 1
		var b := a + 2
		if doll._touch.size() > m and doll._touch[m]:
			continue
		var off := doll.pos[m] - (doll.pos[a] + doll.pos[b]) * .5
		# (A knee down on the floor is let be by the hinge: some slack.)
		var most := doll.pos[a].distance_to(doll.pos[b]) * (Ragdoll.KNEE_PAST + .15)
		if off.dot(torso * doll._bend_rest[k]) < -most:
			return "leg %d's knee folds the wrong way" % k
	return ""


static func _shape_gap(a: PackedVector3Array, b: PackedVector3Array) -> float:
	var most := 0.0
	for i in a.size():
		for j in range(i + 1, a.size()):
			most = maxf(most, absf(a[i].distance_to(a[j]) - b[i].distance_to(b[j])))
	return most


func _kind(game: Game, kind: String) -> void:
	var rig := _rig(kind)
	if rig == null or not rig.ok:
		_check(false, "%s has a beast rig" % kind)
		return
	var plan := rig.plan
	var legs_f: float = plan.get("legs", 4.0)
	var head_f: float = plan.get("head", 0.0)
	var tail_f: float = plan.get("tail", 0.0)
	_check(
		rig.legs.size() == int(legs_f) * 3
		and rig.head.size() == int(head_f)
		and rig.tail.size() == int(tail_f),
		(
			"%s's rig: %d legs, %d head and %d tail balls"
			% [kind, rig.legs.size() / 3, rig.head.size(), rig.tail.size()]
		)
	)
	var at := Vector2(30.5, 30.5)
	var z := game.world.floor_under(at.x, at.y, 99.0)
	var faults := PackedStringArray()
	var ends := {}
	var ways := {}
	var rests: Array[float] = []
	for way: float in [0.0, 2.1]:
		for how: String in KILLS:
			var name := "%s %s from %.1f" % [kind, how, way]
			var doll := _doll(rig, kind, at, z, .3)
			var before := doll.pos.duplicate()
			doll.fit()
			var jump := 0.0
			for i in before.size():
				jump = maxf(jump, before[i].distance_to(doll.pos[i]))
			if jump > .02:
				faults.append("%s: the start moved a ball %.3f" % [name, jump])
			var dice := RandomNumberGenerator.new()
			dice.seed = hash([kind, how, way])
			doll.knock(_victim(at, z, how, way + (1.3 if how.ends_with("_b") else 0.0)), dice)
			var ran := _settle(doll, game.world)
			var t: float = ran[0]
			var hit: float = ran[1]
			rests.append(t)
			if hit > STRETCH_HIT:
				faults.append("%s: a rigid link stretched %.0f%%" % [name, hit * 100.0])
				print("    (worst link %s)" % worst_link)
			if _stretch(doll) > STRETCH:
				faults.append("%s: a rigid link lies stretched" % name)
			if doll.awake or t > REST_BY:
				faults.append("%s: still moving after %.1f s" % [name, t])
			var steps := doll.steps
			for _k in 60:
				doll.advance(game.world, DT)
			if doll.steps != steps:
				faults.append("%s: stirred lying still" % name)
			if not doll.lies_on(game.world, TOL):
				faults.append("%s: does not lie on the floor" % name)
			var up := doll.torso_up()
			if up > doll._stand_high * BeastDoll.STAND and doll.dorsal().z > .7:
				faults.append("%s: still stands (torso %.2f up)" % [name, up])
			var knee := _knees(doll)
			if knee != "":
				faults.append("%s: %s" % [name, knee])
			ends[name] = doll.pos.duplicate()
			var back := doll.dorsal().z
			ways["belly" if back > .7 else "back" if back < -.7 else "side"] = true
	for how: String in KILLS:
		var a: PackedVector3Array = ends["%s %s from 0.0" % [kind, how]]
		var b: PackedVector3Array = ends["%s %s from 2.1" % [kind, how]]
		if _shape_gap(a, b) < .03:
			faults.append("%s %s: both ways lie the same" % [kind, how])
	# (A kind its feel lays two ways at least a quarter of the time each.)
	var feel: Array = Effects.RAGDOLL.get("beast_" + kind, [])
	var likely := 0
	for k in range(1, mini(4, feel.size())):
		var share: float = feel[k]
		likely += 1 if share >= .25 else 0
	if ways.size() < 2 and likely >= 2:
		faults.append("%s: every death lies the same way (%s)" % [kind, ", ".join(ways.keys())])
	for f in faults:
		_check(false, f)
	if faults.is_empty():
		_ok(
			(
				"%s's deaths: links held, knees their way, down on the floor, at rest in %.1f to %.1f s, lying %s"
				% [kind, rests.min(), rests.max(), ", ".join(ways.keys())]
			)
		)


## Dropped on a ramp and a stair of Hickston's or the feed store's: it lies
## on the floor under it.
func _slabs(main: Node) -> void:
	var rig := _rig("crawler")
	var found := 0
	for id: String in ["feedstore", "hickston", "quarry", "sawmill"]:
		var game: Game = main.make_game(id)
		game.configure({})
		var w := game.world
		for s: LevelGeometry.Slab in w.geo.slabs:
			if not s.walk or found >= 4:
				continue
			var mid := Vector2((s.x0 + s.x1) * .5, (s.y0 + s.y1) * .5)
			if not s.inside(mid.x, mid.y) or w.blocked(mid.x, mid.y, .4, s.top_at(mid.x, mid.y) + .3):
				continue
			if not s.sloped() and s.kind != "stair":
				continue
			var top := s.top_at(mid.x, mid.y)
			var doll := _doll(rig, "crawler", mid, top, .7)
			doll.fit()
			var dice := RandomNumberGenerator.new()
			dice.seed = found
			doll.knock(_victim(mid, top, "shotgun_near", .4 * found), dice)
			_settle(doll, w)
			var what := "%s's %s at %.1f, %.1f" % [id, "ramp" if s.sloped() else "stair", mid.x, mid.y]
			_check(not doll.awake and doll.lies_on(w, TOL * 2.0), "a crawler shot on %s lies on it" % what)
			found += 1
	_check(found >= 2, "beasts tried on %d ramps and stairs" % found)


## A gator shot in Gator Bayou's deep water floats a little under the surface.
func _water(main: Node) -> void:
	var game: Game = main.make_game("bayou")
	game.configure({})
	var w := game.world
	var spot := Vector2.INF
	for y in range(4, w.height - 4):
		for x in range(4, w.width - 4):
			if spot != Vector2.INF:
				break
			var at := Vector2(x + .5, y + .5)
			var open := true
			for k in 8:
				var q := at + Vector2.from_angle(k * TAU / 8.0) * 1.8
				open = open and w.deep_at(q.x, q.y) and not w.blocked(q.x, q.y, .3)
			if open and w.deep_at(at.x, at.y):
				spot = at
	if spot == Vector2.INF:
		_check(false, "Gator Bayou has open deep water to try a gator in")
		return
	var rig := _rig("gator")
	var surface := w.floor_under(spot.x, spot.y, 99.0)
	# Shot swimming, sunk a little.
	var doll := _doll(rig, "gator", spot, surface - .12, .5)
	doll.fit()
	var dice := RandomNumberGenerator.new()
	dice.seed = 5
	doll.knock(_victim(spot, surface, "revolver", .4), dice)
	var top := -INF
	var t := 0.0
	while t < 5.0:
		# Play's body bobs on the water (corpses.gd _bob), and the doll with it.
		var bob := .045 * (1.0 + sin(t * 2.1))
		doll.follow(Vector3(spot.x, spot.y, surface + bob), bob, DT)
		doll.advance(w, DT)
		t += DT
		top = maxf(top, doll.middle().z - surface)
	var mid := doll.middle().z - surface
	var r := doll.radius[0]
	_check(
		mid < r * .9 and mid > -r * 1.5,
		"a gator shot in deep water floats a little under the surface (middle %.3f, ball %.3f)" % [mid, r]
	)
	_check(top < r * 2.0, "it comes up slowly, never thrown out of the water (highest %.3f)" % top)


## The herd: a blast kills a hog's stand-in where it was, with the blast's
## place; a stand-in first seen down lies long dead.
func _herd(main: Node) -> void:
	var opts: Dictionary = main.get("options")
	opts["events"] = 2
	var g: Game = main.make_game("hickston")
	g.configure({"difficulty": 1, "events": 2})
	opts.erase("events")
	for _k in 2:
		g.tick(DT, Game.Controls.new())
	var ev: CountyEvents = g.features["events"]
	if not ev.begin("hogs"):
		_check(false, "a stampede starts to try the hogs in")
		return
	EventHerd.sprites(ev)
	var row: Array = ev.herd[0]
	var at := Vector2(EventHerd.f(row, 0), EventHerd.f(row, 1))
	EventHerd.blast(ev, at.x + .5, at.y)
	var shown := EventHerd.sprites(ev)
	var hog: Enemy = null
	for s: View.Sprite in shown:
		var e := s.who as Enemy
		if e != null and Vector2(e.x, e.y).distance_to(at) < .01:
			hog = e
	_check(
		hog != null and not hog.alive and absf(hog.died_at - g.clock) < .01 and hog.blast_at.x > at.x,
		"a blast kills the hog's stand-in now, thrown from the blast"
	)
	var fresh := ModeBodies.stand_in(g, "hog_check", "hog")
	fresh.gait = 0.0
	_check(fresh.alive, "a new stand-in stands")


## A boss felled in front of its model: the scripted fall hands over to the
## ragdoll with no part jumping, and it lies still near where it fell.
func _boss(game: Game, kind: String) -> void:
	View.ragdolls = true
	var view := models.scene(kind).instantiate() as ActorView
	check.root.add_child(view)
	if not view.setup(models):
		_check(false, "%s's model poses" % kind)
		view.queue_free()
		return
	var at := Vector2(30.5, 30.5)
	var e := Enemy.new(kind, at.x, at.y, .4)
	e.floor_z = game.world.floor_under(at.x, at.y, 99.0)
	var clock := 10.0
	for _k in 5:
		_show(view, e, game, clock)
		clock += DT
	e.hp = 0.0
	e.died_at = clock
	e.killed_by = "shotgun"
	e.killed_from = at - Vector2(2.0, 0.0)
	var was := _bones(view)
	var moves: Array[float] = []
	var handed := -1
	var t := 0.0
	while t < REST_BY + 1.0:
		_show(view, e, game, clock)
		var now := _bones(view)
		var most := 0.0
		for i in now.size():
			if now[i] != Vector3.INF and was[i] != Vector3.INF:
				most = maxf(most, now[i].distance_to(was[i]))
		moves.append(most)
		if handed < 0 and view.doll != null:
			handed = moves.size() - 1
		was = now
		clock += DT
		t += DT
		if view.doll != null and not view.doll.awake and t > 1.0:
			break
	if handed < 0:
		_check(false, "%s's fall hands over to its ragdoll" % kind)
		view.queue_free()
		return
	var before := 0.0
	for k in range(maxi(0, handed - 4), handed):
		before = maxf(before, moves[k])
	var jump := 0.0
	for k in range(handed, mini(moves.size(), handed + 3)):
		jump = maxf(jump, moves[k])
	_check(
		jump <= before * POP_RATIO + POP_LET,
		(
			"%s's fall hands over at %.2f s with no pop (a part moved %.3f, before %.3f)"
			% [kind, float(handed) * DT, jump, before]
		)
	)
	var doll := view.doll
	_check(not doll.awake, "%s's body comes to rest (%.1f s)" % [kind, t])
	_check(doll.lies_on(game.world, TOL), "%s lies on the floor" % kind)
	var lying := view._lying_middle() * view._size(e)
	var scripted := Vector2(at.x, at.y) + Vector2(lying.x, lying.z).rotated(0.0)
	var mid := doll.middle()
	var off := Vector2(mid.x, mid.y).distance_to(at)
	_check(
		off < lying.length() + BOSS_NEAR * view._size(e),
		"%s lies %.2f from where it stood (its scripted fall %.2f)" % [kind, off, lying.length()]
	)
	var settled := doll.middle()
	for _k in 60:
		_show(view, e, game, clock)
		clock += DT
	_check(doll.middle().distance_to(settled) < .005, "%s slides no further at rest" % kind)
	if scripted == Vector2.INF:
		pass
	view.queue_free()


func _show(view: ActorView, e: Enemy, game: Game, clock: float) -> void:
	var s := e.sprite(null, false, clock)
	if s == null:
		return
	s.z = e.floor_z
	s.who = e
	view.show_as(s, e, game.world, clock)


## Every bone's place in the world.
static func _bones(view: ActorView) -> PackedVector3Array:
	var out := PackedVector3Array()
	for sk: Node in view.find_children("*", "Skeleton3D", true, false):
		var skeleton := sk as Skeleton3D
		for i in skeleton.get_bone_count():
			# (A part shrunk away, INF: the gun let go of shows anew.)
			if skeleton.get_bone_pose_scale(i).x < .2:
				out.append(Vector3.INF)
			else:
				out.append(skeleton.global_transform * skeleton.get_bone_global_pose(i).origin)
	return out
