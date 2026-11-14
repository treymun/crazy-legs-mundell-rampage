## Checks of the four boss arenas (features/boss_arena.gd and src/bosses/
## sheriff.gd, jerry.gd, rudy.gd, foreman.gd; tools/check_fixes.gd runs them,
## this also runs on its own):
##
##   Godot --headless --path <project> --script res://tools/arena_check.gd
##
## Each boss stands in its arena's box; its weak spot counts where the art
## says (the sheriff's pack and the foreman's rig from behind, Jerry's knees
## and helmet, Rudy's drum and his horns while he blows) and nowhere else,
## and once plum desperate the rest of it is guarded; its phase-three attack
## comes and its arena changes (the floodlights cut, back on when it falls);
## its HOG WILD attack comes on HOG WILD only. The hazards go both ways: fire
## burns the boss and the player, the carriage runs the foreman down, a horn
## lane knocks Rudy about, tyres roll off a stack, a boss's shot breaks the
## cover it meets. Hickston's stock gate opens onto Jerry's field when the
## sheriff falls.
extends SceneTree

const STEP := 1.0 / 60.0
const KINDS := ["boss", "jerry", "rudy", "foreman"]

var failures: Array = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Control = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	run(
		main,
		func(ok: bool, text: String) -> void:
			print("  ok   " if ok else "  FAIL ", text)
			if not ok:
				failures.append(text)
	)
	print("")
	print("ARENA CHECK OK" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


static func run(main, check: Callable) -> void:
	print("BOSS ARENAS (weak spots, phase three, HOG WILD, hazards both ways)")
	for kind: String in KINDS:
		_weak(main, check, kind)
		_third(main, check, kind)
		_hog(main, check, kind)
	_both_ways(main, check)
	_gate(main, check)


## The rematch's game for a boss, god mode on, the player `gap` from it on open
## floor it can see.
static func _game(main, kind: String, difficulty := 1, gap := 5.0) -> Game:
	var g: Game = BossRematch.build(Callable(main, "make_game"), kind)
	g.configure({"difficulty": difficulty})
	g.cheats.god = true
	g.spawn_grace = 0.0
	var e := BossFight.of_kind(g, kind)
	var w := g.world
	for k in 32:
		var a := k * TAU / 32.0
		var at := Vector2(e.x + cos(a) * gap, e.y + sin(a) * gap)
		if (
			not w.blocked(at.x, at.y, .4)
			and w.visible(e.x, e.y, at.x, at.y, 1.2, 1.2)
			and absf(w.elevation(at.x, at.y) - w.elevation(e.x, e.y)) < .2
		):
			var p := g.player
			p.x = at.x
			p.y = at.y
			p.eye = w.elevation(at.x, at.y) + .95
			p.angle = atan2(e.y - at.y, e.x - at.x)
			break
	return g


static func _ticks(g: Game, n: int) -> void:
	for i in n:
		g.tick(STEP, Game.Controls.new())


static func _weak(main, check: Callable, kind: String) -> void:
	var g := _game(main, kind)
	var e := BossFight.of_kind(g, kind)
	var f = g.features["boss_arena"]
	check.call(f.in_box(kind, e.x, e.y), "%s: stands in its arena (%.1f, %.1f)" % [kind, e.x, e.y])
	var m := BossKit.moves(kind)
	var feet := g.world.stand(e)
	var tall := e.height * e.variant
	e.angle = 0.0
	var front := Vector2(e.x + 4.0, e.y)
	var back := Vector2(e.x - 4.0, e.y)
	var mid := Vector3(e.x, e.y, feet + tall * .58)
	var plain := m.weak_spot(e, g, mid, front, "shotgun")
	check.call(
		is_equal_approx(plain, 1.0), "%s: a plain hit in front counts 1 (%.2f)" % [kind, plain]
	)
	var weak := 0.0
	match kind:
		"boss", "foreman":
			weak = m.weak_spot(e, g, mid, back, "shotgun")
		"jerry":
			weak = m.weak_spot(e, g, Vector3(e.x, e.y, feet + tall * .15), front, "shotgun")
			var helmet := m.weak_spot(e, g, Vector3(e.x, e.y, feet + tall * .92), front, "shotgun")
			check.call(helmet < 1.0, "jerry: the helmet takes a hit (%.2f)" % helmet)
		"rudy":
			weak = m.weak_spot(e, g, Vector3(e.x, e.y, feet + tall * .35), front, "shotgun")
			e.windup = .5
			var horns := m.weak_spot(e, g, Vector3(e.x, e.y, feet + tall * .85), front, "shotgun")
			e.windup = 0.0
			var still := m.weak_spot(e, g, Vector3(e.x, e.y, feet + tall * .85), front, "shotgun")
			check.call(
				horns > 2.0 and is_equal_approx(still, 1.0),
				"rudy: the horns while he blows (%.2f), not otherwise (%.2f)" % [horns, still]
			)
	check.call(
		weak >= 1.5 and weak <= 2.5, "%s: its weak spot counts %.2f (1.5 to 2.5)" % [kind, weak]
	)
	e.hp = e.max_hp * .15
	BossKit.phase_check(e, g)
	var guarded := m.weak_spot(e, g, mid, front, "shotgun")
	check.call(
		guarded < 1.0 and is_equal_approx(m.weak_spot(e, g, mid, front, "blast"), 1.0),
		"%s: plum desperate, a gun's plain hit is guarded (%.2f), a blast is not" % [kind, guarded]
	)


## Plum desperate: the arena changes and its phase-three attack comes.
static func _third(main, check: Callable, kind: String) -> void:
	var g := _game(main, kind)
	var e := BossFight.of_kind(g, kind)
	var f = g.features["boss_arena"]
	_ticks(g, 30)
	e.hp = e.max_hp * .15
	BossKit.phase_check(e, g)
	var seen := false
	for i in 600:
		g.tick(STEP, Game.Controls.new())
		e.hp = maxf(e.hp, e.max_hp * .1)
		match kind:
			"boss":
				seen = seen or not f.strikes.is_empty()
			"jerry":
				seen = seen or e.has_meta("blitz")
			"rudy":
				var horns := 0
				for s in g.shots:
					horns += 1 if s.kind == "rudy_horn" else 0
				seen = seen or horns >= 10
			"foreman":
				for s in g.shots:
					seen = seen or (s.kind == "foreman_cut" and s.bounces > 0)
		if seen:
			break
	check.call(seen, "%s: plum desperate, its phase-three attack comes" % kind)
	var floods: Array = f.spec(kind).get("floods", [])
	if not floods.is_empty():
		check.call(
			f.dark.has(kind) and not _flood_lit(g, floods[0]),
			"%s: its floodlights cut in phase three" % kind
		)
		e.hurt(e.hp + 999.0, g)
		_ticks(g, 120)
		check.call(
			not f.dark.has(kind) and _flood_lit(g, floods[0]),
			"%s: and come back on when it falls" % kind
		)


static func _flood_lit(g: Game, at: Array) -> bool:
	for board: LevelData.Billboard in g.world.billboards:
		if board.image == "town_floodlight_tower":
			if absf(board.x - float(at[0])) < .3 and absf(board.y - float(at[1])) < .3:
				return board.glow
	return false


## Its HOG WILD attack: on HOG WILD, never on NORMAL.
static func _hog(main, check: Callable, kind: String) -> void:
	var counts := []
	for difficulty: int in [1, 3]:
		var g := _game(main, kind, difficulty)
		var e := BossFight.of_kind(g, kind)
		var f = g.features["boss_arena"]
		_ticks(g, 30)
		e.hp = e.max_hp * .45
		BossKit.phase_check(e, g)
		var seen := 0
		for i in 900:
			g.tick(STEP, Game.Controls.new())
			e.hp = maxf(e.hp, e.max_hp * .4)
			match kind:
				"boss":
					var plasma := 0
					for s in g.shots:
						plasma += 1 if s.kind == "plasma" else 0
					seen += 1 if plasma >= 10 else 0
				"jerry":
					for l in f.lobs:
						seen += 1 if l.kind == "pigskin_bomb" else 0
				"rudy":
					for l in f.lobs:
						seen += 1 if l.drift else 0
				"foreman":
					for r in f.rollers:
						seen += 1 if r.blast != "" else 0
		counts.append(seen)
	check.call(
		counts[0] == 0 and counts[1] > 0,
		(
			"%s: its HOG WILD attack comes on HOG WILD (%d) and not on NORMAL (%d)"
			% [kind, counts[1], counts[0]]
		)
	)


## Hazards fight both ways.
static func _both_ways(main, check: Callable) -> void:
	var g := _game(main, "boss")
	var e := BossFight.of_kind(g, "boss")
	var f = g.features["boss_arena"]
	var before := e.hp
	e.cooldown = 99.0
	f.fire(e.x, e.y, 1.0, 3.0)
	_ticks(g, 70)
	check.call(e.hp < before, "fire burns the boss (%.0f -> %.0f)" % [before, e.hp])
	g.cheats.god = false
	var p := g.player
	var health := p.health
	f.fire(p.x, p.y, 1.0, 3.0)
	_ticks(g, 70)
	check.call(p.health < health, "and the player (%d -> %d)" % [health, p.health])
	# A boss's shot breaks the cover it meets.
	var pieces = g.features["breakables"]
	var cover = null
	for piece in pieces.pieces:
		if not piece.broken and f.in_box("boss", piece.x, piece.y):
			cover = piece
			break
	if cover != null:
		var z: float = g.world.elevation(cover.x, cover.y) + cover.height * .5
		g.launch(cover.x - 1.0, cover.y, z, 0.0, 6.0, "plasma", 0.0, true, 13, -1.0, 1)
		_ticks(g, 40)
	check.call(cover != null and cover.broken, "a boss's shot breaks the cover it meets")
	# The carriage runs the foreman down.
	var mill := _game(main, "foreman")
	var foreman := BossFight.of_kind(mill, "foreman")
	var arena = mill.features["boss_arena"]
	var track: Array = arena.spec("foreman")["track"]
	foreman.x = (float(track[0]) + float(track[1])) * .5
	foreman.y = float(track[2])
	foreman.cooldown = 99.0
	foreman.stun = 99.0
	var hp := foreman.hp
	arena.carriage_run = mill.clock
	for i in 600:
		mill.tick(STEP, Game.Controls.new())
		foreman.x = (float(track[0]) + float(track[1])) * .5
		foreman.y = float(track[2])
		if foreman.hp < hp:
			break
	check.call(
		foreman.hp <= hp - 50.0,
		"the carriage runs the foreman down (%.0f -> %.0f)" % [hp, foreman.hp]
	)
	# A horn lane knocks Rudy about.
	var fair := _game(main, "rudy")
	var rudy := BossFight.of_kind(fair, "rudy")
	var big_top = fair.features["boss_arena"]
	rudy.cooldown = 99.0
	var rudy_hp := rudy.hp
	big_top.lane(rudy.x - 3.0, rudy.y, 0.0, 6.0, .2)
	_ticks(fair, 30)
	check.call(rudy.hp < rudy_hp, "a horn stack's lane knocks Rudy about")
	# Tyres roll off a drill stack.
	var field := _game(main, "jerry")
	var tires = field.features["boss_arena"]
	var stacks: Array = tires.spec("jerry").get("tires", [])
	var rolled: bool = (
		not stacks.is_empty()
		and tires.knock_tyres(float(stacks[0][0]) + .5, float(stacks[0][1]), 2.0)
	)
	check.call(rolled and tires.rollers.size() == 3, "tyres roll off a drill stack")


## Hickston: the stock gate onto Jerry's field opens when the sheriff falls,
## and the field is Jerry's arena.
static func _gate(main, check: Callable) -> void:
	var g: Game = main.make_game("hickston")
	g.configure({})
	g.cheats.god = true
	var gate: LevelData.Door = null
	for door: LevelData.Door in g.world.doors:
		if door.x == 122 and door.y == 10:
			gate = door
	check.call(gate != null and not gate.opened, "hickston: the stock gate stands shut")
	g.boss.hurt(g.boss.hp + 999.0, g)
	_ticks(g, 60)
	check.call(gate != null and gate.opened, "and opens when the sheriff falls")
	check.call(
		(
			BossFight.in_arena_at(g, g.jerry, 108.5, 9.5)
			and not BossFight.in_arena_at(g, g.jerry, 133.0, 14.0)
		),
		"Jerry's arena is his field, the sheriff's the rodeo"
	)
