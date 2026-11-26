## Punchier hits (pass 15, PUNCH: ideas 11, 12 and 20), headless:
##
##   Godot --headless --path godot --script res://tools/punch_check.gd [-- print]
##
## The world's hold by closeness and weight (game_world.gd struck, hits.cfg
## [punch]): a kill from afar holds kill_hold, a heavy load's kill within
## close_reach close_hold, the sawed-off at arm's length sawed_hold, a heavy
## hit that does not kill hit_hold, never with two players; the close kill
## kicks the view (feel.gd), a far one does not. Every hit flinches at least
## flinch_floor. Every head hit rings the ding (once a load), a body hit never;
## a head kill leaves the crosshair's splat. The sawed-off at arm's length
## always takes the body apart (one barrel too); from further one barrel
## throws it whole as before; the further past the overkill line, the more and
## bigger chunks (gore.gd, at most gib_most). The slow motion comes only after
## a fight of fight_least kills, longer (peak_length) when the kill ends the
## director's peak. `print` lists the numbers.
extends SceneTree

const DT := 1.0 / 60.0
const Finishers := preload("res://src/features/finishers.gd")

var failures: Array = []
var verbose := false


func _init() -> void:
	_run.call_deferred()


func _check(ok: bool, text: String) -> void:
	print("  ok   " if ok else "  FAIL ", text)
	if not ok:
		failures.append(text)


func _run() -> void:
	verbose = OS.get_cmdline_user_args().has("print")
	var main: Control = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	print("PUNCHIER HITS: THE HOLD, THE KICK, THE DING, THE GIBS, THE SLOW MOTION")
	_holds(main)
	_flinch(main)
	_dings(main)
	_gibs(main)
	_slowmo(main)
	print("")
	print("PUNCH CHECK OK" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


static func _game(main: Node, options := {}) -> Game:
	var g: Game = main.make_game("hickston")
	g.configure(options)
	g.cheats.god = true
	g.spawn_grace = 99.0
	return g


## A hand of `kind` alone `far` cells east of the player, facing him.
static func _hand(g: Game, far: float, kind := "billy", hp := 70.0) -> Enemy:
	for o: Enemy in g.enemies:
		o.dormant = true
	var p := g.player
	var e := Enemy.new(kind, p.x + far, p.y, PI)
	e.floor_z = g.world.stand(e)
	e.hp = hp
	e.max_hp = maxf(hp, 70.0)
	e.alerted = true
	g.enemies.append(e)
	return e


## A hit on `e` from the player at height `up` of the body: `amount` in
## `pellets` pieces of one instant.
static func _hit(g: Game, e: Enemy, how: String, amount: float, up := .6, pellets := 1) -> void:
	var p := g.player
	g.hit_from = Vector2(p.x, p.y)
	var feet: float = g.world.stand(e) + e.z
	for _k in pellets:
		g.hit_point = Vector3(e.x - e.radius * .8, e.y, feet + e.height * e.variant * up)
		e.hurt(amount / pellets, g, false, false, null, how)


func _hold(
	main: Node, far: float, how: String, amount: float, pellets: int, hp: float, options := {}
) -> Array:
	var g := _game(main, options)
	var e := _hand(g, far, "billy", hp)
	g.hitstop = 0.0
	g.hitstop_next = 0.0
	var feel: Object = g.features.get("feel")
	_hit(g, e, how, amount, .6, pellets)
	var kick := Vector3.ZERO
	if feel != null:
		var v: Vector3 = feel.get("view_v")
		kick = v
	return [g.hitstop, kick.length(), e.alive]


func _holds(main: Node) -> void:
	var far: Array = _hold(main, 8.0, "revolver", 80.0, 1, 70.0)
	var close: Array = _hold(main, 2.2, "revolver", 80.0, 1, 70.0)
	var sawed: Array = _hold(main, .9, "shotgun", 80.0, 8, 70.0)
	var heavy: Array = _hold(main, 5.0, "revolver", 45.0, 1, 300.0)
	var light: Array = _hold(main, 5.0, "revolver", 20.0, 1, 300.0)
	if verbose:
		print(
			(
				(
					"    holds: far kill %.2f, close heavy kill %.2f, sawed-off at arm's length"
					+ " %.2f, heavy hit %.2f, light %.2f"
				)
				% [far[0], close[0], sawed[0], heavy[0], light[0]]
			)
		)
		print("    kick: far %.2f close %.2f sawed %.2f" % [far[1], close[1], sawed[1]])
	_check(
		is_equal_approx(float(far[0]), GameWorld.PUNCH_KILL_HOLD),
		"a kill from afar holds the world %.2f s" % far[0]
	)
	_check(
		is_equal_approx(float(close[0]), GameWorld.PUNCH_CLOSE_HOLD),
		"a heavy kill within reach holds it %.2f s" % close[0]
	)
	_check(
		is_equal_approx(float(sawed[0]), GameWorld.PUNCH_SAWED_HOLD),
		"the sawed-off at arm's length holds it %.2f s" % sawed[0]
	)
	_check(
		is_equal_approx(float(heavy[0]), GameWorld.PUNCH_HIT_HOLD) and light[0] == 0.0,
		"a heavy hit that does not kill %.2f s, a light one none" % heavy[0]
	)
	_check(
		float(close[1]) > 0.0 and float(sawed[1]) > float(close[1]) and far[1] == 0.0,
		(
			"the close kill kicks the view (%.1f, the sawed-off %.1f), a far one does not"
			% [close[1], sawed[1]]
		)
	)
	var g := _game(main)
	Modes.join_beside(g, g.player)
	var e := _hand(g, .9)
	g.hitstop = 0.0
	g.hitstop_next = 0.0
	_hit(g, e, "shotgun", 80.0, .6, 8)
	_check(g.hitstop == 0.0, "never a hold with a second player")


func _flinch(main: Node) -> void:
	var g := _game(main)
	var e := _hand(g, 5.0, "billy", 300.0)
	_hit(g, e, "revolver", 1.0)
	_check(
		e.flinch >= Enemy.FLINCH_FLOOR - 1e-6,
		"every hit flinches at least %.2f s (%.2f)" % [Enemy.FLINCH_FLOOR, e.flinch]
	)


func _dings(main: Node) -> void:
	var g := _game(main)
	var e := _hand(g, 4.0, "billy", 400.0)
	var reads: Object = g.features.get("hit_reads")
	var before: int = reads.call("dings")
	for k in 3:
		g.clock += .5
		_hit(g, e, "revolver", 10.0, .93)
	var heads: int = int(reads.call("dings")) - before
	g.clock += .5
	_hit(g, e, "revolver", 10.0, .6)
	var body: int = int(reads.call("dings")) - before - heads
	g.clock += .5
	_hit(g, e, "shotgun", 40.0, .93, 8)
	var load: int = int(reads.call("dings")) - before - heads - body
	_check(
		heads == 3 and body == 0,
		"a ding for each head hit (%d of 3), none on the body (%d)" % [heads, body]
	)
	_check(load == 1, "a load of buckshot on the head rings once (%d)" % load)
	_check(Assets.MADE_CUES.has("head_ding"), "the ding is a made cue (assets.gd MADE_CUES)")
	g.clock += .5
	e.hp = 5.0
	_hit(g, e, "revolver", 30.0, .93)
	_check(
		g.hit_mark_kill and g.hit_mark_head,
		"a head kill leaves the crosshair's splat (kill and head marks)"
	)


func _gibs(main: Node) -> void:
	var gibbed := [0]
	var count := func(_e: Enemy) -> void: gibbed[0] += 1
	# One barrel at arm's length: apart. One barrel from three cells: whole.
	var g := _game(main)
	g.gore = true
	g.events.enemy_gibbed.connect(count)
	g.armory.last_spent = 1
	var e := _hand(g, .9, "billy", 30.0)
	_hit(g, e, "shotgun", 60.0, .6, 8)
	var near: int = gibbed[0]
	g = _game(main)
	g.gore = true
	g.events.enemy_gibbed.connect(count)
	g.armory.last_spent = 1
	e = _hand(g, 3.0, "billy", 30.0)
	_hit(g, e, "shotgun", 60.0, .6, 8)
	var mid: int = gibbed[0] - near
	_check(
		near == 1 and mid == 0,
		(
			"one barrel at arm's length takes the body apart, from three cells it does not (%d, %d)"
			% [near, mid]
		)
	)
	# More over the line, more and bigger chunks.
	var sizes: Array = []
	for load: float in [50.0, 75.0, 200.0]:
		g = _game(main)
		g.gore = true
		e = _hand(g, 4.0, "billy", 30.0)
		e.struck_sum = load
		e.killed_by = "revolver"
		var gore: Gore = g.gore_fx
		var was := gore.gibs.size()
		gore.burst(e)
		var big := 0.0
		for k in range(was, gore.gibs.size()):
			var chunk: Gore.Gib = gore.gibs[k]
			big = maxf(big, chunk.size)
		sizes.append([gore.gibs.size() - was, big, Gore.excess(e)])
	if verbose:
		print("    overkill chunks [count, biggest, excess]: %s" % str(sizes))
	var a: Array = sizes[0]
	var b: Array = sizes[1]
	var c: Array = sizes[2]
	_check(
		int(b[0]) > int(a[0]) and float(b[1]) > float(a[1]),
		"further over the line, more and bigger chunks (%d to %d)" % [a[0], b[0]]
	)
	_check(
		(
			float(c[2]) <= Gore.GIB_MOST - 1.0 + 1e-6
			and int(c[0]) <= int(a[0]) + ceili((Gore.GIB_MOST - 1.0) * Gore.GIB_MORE)
		),
		"never past gib_most (%d chunks at most)" % c[0]
	)


func _slowmo(main: Node) -> void:
	# A lone hand met alone: no slow motion.
	var g := _game(main)
	var e := _hand(g, 4.0, "billy", 20.0)
	_hit(g, e, "revolver", 40.0)
	_check(g.slowmo == 0.0, "a lone hand's kill is no finisher")
	# The director's peak ends on the third kill: the longer slow motion.
	g = _game(main)
	g.tick(DT, Game.Controls.new())
	var d := Director.of(g)
	if d == null:
		_check(false, "the director runs in hickston")
		return
	var hands: Array = []
	for k in 3:
		var h := _hand(g, 4.0 + k * .4, "billy", 20.0)
		hands.append(h)
	for h: Enemy in hands:
		h.dormant = false
		h.alerted = true
	d.phase = Director.PEAK
	d.peak = []
	for h: Enemy in hands:
		d.peak.append(g.enemies.find(h))
	for h: Enemy in hands:
		g.clock += .2
		_hit(g, h, "revolver", 40.0)
	_check(
		is_equal_approx(g.slowmo, Finishers.PEAK_LENGTH),
		(
			"the kill that ends the director's peak slows %.2f s (%.2f)"
			% [Finishers.PEAK_LENGTH, g.slowmo]
		)
	)
