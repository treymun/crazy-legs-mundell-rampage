## Checks of the county's squads, idle life and tougher variants
## (src/squad.gd, src/idle_life.gd, src/variants.gd and their features;
## tools/check_fixes.gd runs them; this also runs on its own):
##
##   Godot --headless --path <project> --script res://tools/squad_check.gd
##
## Variants swap in by difficulty, the same ones every time, more the harder
## it is, none on EASY, every chapter has its tough guy, and a save loads to
## the same kinds; a shield deputy's door stops a shot from the front, not
## from behind, comes down to a blast, and swings aside while he fires; the
## hands of every chapter find activities by what stands near them; a hand
## hit from behind unaware is stunned, from the front not; a shot heard
## round a corner brings hands to look; a hunt that runs out turns into a
## search, the search into giving up; a squad sends one wide to flank on HOG
## WILD and none on EASY; the barks come, and not in a flood.
extends SceneTree

const CHAPTERS := ["hickston", "fair", "sawmill", "quarry", "bayou", "speedway", "mothership"]
const STEP := 1.0 / 60.0

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
	print("SQUAD CHECK OK" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


static func run(main, check: Callable) -> void:
	print("\nVARIANTS AND TOUGH GUYS")
	_variants(main, check)
	_door(main, check)
	print("\nA LIVING COUNTY")
	_activities(main, check)
	_sneak(main, check)
	print("\nSQUADS")
	_investigate(main, check)
	_search(main, check)
	_flank(main, check)


static func _game(main, level_id: String, difficulty: int) -> Game:
	var g: Game = main.make_game(level_id)
	g.configure({"difficulty": difficulty})
	g.spawn_grace = 0.0
	return g


static func _kinds(g: Game) -> Array:
	var out: Array = []
	for i in g.enemy_ids.size():
		out.append(g.enemies[i].kind)
	return out


static func _variants(main, check: Callable) -> void:
	var counts: Array = []
	var same := true
	var toughs := 0
	for diff in 4:
		var n := 0
		for level_id: String in CHAPTERS:
			var g := _game(main, level_id, diff)
			g.ticked.emit(STEP)
			var again := _game(main, level_id, diff)
			again.ticked.emit(STEP)
			same = same and _kinds(g) == _kinds(again)
			for e: Enemy in g.enemies:
				if Variants.VARIANT_OF.values().has(e.kind):
					n += 1
				if diff == 1 and Enemy.DEFS[e.kind].has("tough_for"):
					toughs += 1
		counts.append(n)
	check.call(same, "the same chapter at the same difficulty swaps the same hands")
	check.call(
		counts[0] == 0 and counts[1] > 0 and counts[1] < counts[2] and counts[2] < counts[3],
		"variants: none on EASY, more the harder it is (%s)" % [counts]
	)
	check.call(toughs == CHAPTERS.size(), "every chapter has its tough guy (%d)" % toughs)
	# A save keeps the kinds, and a load sets each variant up as its kind.
	var g := _game(main, "hickston", 3)
	g.ticked.emit(STEP)
	var big: Enemy = null
	for e: Enemy in g.enemies:
		if e.kind == "big_billy":
			big = e
			break
	var path := OS.get_cache_dir().path_join("clmr-squad-variants.json")
	SessionStore.save(g, path)
	var back: Game = SessionStore.read(path, Callable(main, "make_game"), false)
	var kept := back != null and _kinds(back) == _kinds(g)
	var index := g.enemies.find(big)
	check.call(
		(
			kept
			and big != null
			and back.enemies[index].max_hp == big.max_hp
			and back.enemies[index].brain == "billy"
		),
		"a save loads to the same kinds, each set up as its kind"
	)
	if back != null:
		back.ticked.emit(STEP)
		check.call(_kinds(back) == _kinds(g), "a loaded game is never swapped again")
	# The art: a variant wears its regular's pictures until its own are packed.
	var worn := Variants.stem("big_billy")
	var own := Assets.shared_index.has("big_billy_0")
	check.call(
		worn == ("big_billy" if own else "billy"),
		"a variant without its own pictures wears its regular's (%s)" % worn
	)
	var tough: Enemy = null
	for e: Enemy in g.enemies:
		if e.kind == "tough_earl":
			tough = e
	if tough != null:
		var look = tough.sprite([tough.x + 3.0, tough.y], false, g.clock)
		check.call(
			look != null and String(look.image).contains("~") and look.height > 1.9,
			"the tough guy is drawn bigger and tinted (%s)" % (look.image if look != null else "-")
		)


## A shield deputy on the range, facing the player down the lane.
static func _door(main, check: Callable) -> void:
	var g := _game(main, "range", 1)
	g.ticked.emit(STEP)
	g.enemies.clear()
	var p := g.player
	var at := Vector2(p.x + cos(p.angle) * 5.0, p.y + sin(p.angle) * 5.0)
	var deputy := Enemy.new("shield_deputy", at.x, at.y, p.angle + PI)
	g.enemies.append(deputy)
	p.pitch = 0.0
	p.eye = .95 + g.world.stand(p)
	var keeper = g.features["variants"]
	var full := deputy.hp
	g.hitscan(p.angle, 0.0, 20.0, 20.0, 0.0)
	var front := full - deputy.hp
	check.call(
		front > 0.0 and front < 3.0 and keeper.door_left(deputy) < Variants.DOORS["shield_deputy"],
		"the door stops a shot from the front (%.1f got through)" % front
	)
	deputy.angle = p.angle
	var before := deputy.hp
	g.hitscan(p.angle, 0.0, 20.0, 20.0, 0.0)
	check.call(before - deputy.hp >= 19.0, "a shot from behind the door hits him whole")
	deputy.angle = p.angle + PI
	deputy.windup = .4
	before = deputy.hp
	g.hitscan(p.angle, 0.0, 20.0, 20.0, 0.0)
	check.call(before - deputy.hp >= 19.0, "the door swung aside to fire lets a shot through")
	deputy.windup = 0.0
	# His own pictures carry the door; a door picture is drawn in front only
	# for a kind whose art does not (door_picture in enemies.cfg).
	var drawn: bool = not g.features["variants"].sprites().is_empty()
	var own := String(Enemy.DEFS["shield_deputy"].get("door_picture", "")) == ""
	check.call(drawn != own, "the door is drawn once: in his pictures or in front of him")
	deputy.hurt(160.0, g, true)
	check.call(keeper.door_left(deputy) <= 0.0, "a blast tears the door away")


static func _activities(main, check: Callable) -> void:
	var found := {}
	var per: Array = []
	for level_id: String in CHAPTERS:
		var g := _game(main, level_id, 1)
		g.ticked.emit(STEP)
		var n := 0
		for e: Enemy in g.enemies:
			if e.mind != null and e.mind.activity != "":
				n += 1
				found[e.mind.activity] = true
		per.append(n)
	var every := true
	for n: int in per:
		every = every and n >= 3
	check.call(every, "every chapter's hands find things to do (%s)" % [per])
	check.call(found.size() >= 6, "the activities are many kinds (%s)" % ", ".join(found.keys()))


## A hand at its activity, the player stepping up behind it, then in front.
static func _sneak(main, check: Callable) -> void:
	for from_behind: bool in [true, false]:
		var g := _game(main, "hickston", 1)
		g.ticked.emit(STEP)
		var busy: Enemy = null
		for e: Enemy in g.enemies:
			if e.mind != null and e.mind.activity != "" and e.alive and not e.alerted:
				busy = e
				break
		var p := g.player
		var a := busy.angle + (PI if from_behind else 0.0)
		p.x = busy.x + cos(a) * 1.5
		p.y = busy.y + sin(a) * 1.5
		var moments: Array = []
		g.enemy_bark.connect(func(_e, moment: String): moments.append(moment))
		busy.hurt(5.0, g)
		if from_behind:
			check.call(
				busy.stun >= Squad.SNEAK_STUN[1] - .01 and moments.has("surprised"),
				"hit from behind at its activity, a hand is stunned (%.2f s)" % busy.stun
			)
		else:
			check.call(busy.stun < .5, "hit from the front it is not (%.2f s)" % busy.stun)


## A hand round a corner, out of sight, hears a shot and comes to look.
static func _investigate(main, check: Callable) -> void:
	var g := _game(main, "hickston", 1)
	g.ticked.emit(STEP)
	var p := g.player
	# A hand, and a spot for the player 6 to 9 cells off it, round a corner
	# from it but within the flow field's reach.
	var ear: Enemy = null
	for e: Enemy in g.enemies:
		if e.mind == null or e.alerted or e.dormant or not e.alive or not e.route.is_empty():
			continue
		for k in 24:
			var a := k * TAU / 24.0
			var r := 6.0 + (k % 4)
			var at := Vector2(e.x + cos(a) * r, e.y + sin(a) * r)
			if g.world.blocked(at.x, at.y, .3) or g.world.visible(at.x, at.y, e.x, e.y):
				continue
			g.flow.update(at.x, at.y, g.clock)
			g.flow.next_at = 0.0
			if not is_nan(g.flow.heading(e.x, e.y)):
				p.x = at.x
				p.y = at.y
				ear = e
				break
		if ear != null:
			break
	if ear == null:
		check.call(false, "a hand out of sight near the start to hear a shot")
		return
	var was := Vector2(ear.x - p.x, ear.y - p.y).length()
	g.shot_fired.emit(Weapons.NAMES.find("revolver"))
	check.call(ear.mind.investigate != null, "a shot heard round a corner sends a hand to look")
	var still := Game.Controls.new()
	for i in 240:
		g.tick(STEP, still)
	var now := Vector2(ear.x - p.x, ear.y - p.y).length()
	check.call(now < was - 1.0, "it comes closer (%.1f to %.1f)" % [was, now])


## An alerted hand whose hunt runs out: it searches, then gives up.
static func _search(main, check: Callable) -> void:
	var g := _game(main, "range", 1)
	g.ticked.emit(STEP)
	g.enemies.clear()
	var p := g.player
	var hand := Enemy.new("billy", p.x + 8.0, p.y)
	hand.mind = Squad.Mind.new()
	g.enemies.append(hand)
	hand.alerted = true
	hand.target = [hand.x - 1.0, hand.y]
	hand.hunt_until = 0.0
	# The player is gone: far off, out of sight and out of the field.
	p.x = 2.5
	p.y = 2.5
	var moments: Array = []
	g.enemy_bark.connect(func(_e, moment: String): moments.append(moment))
	var searched := false
	var gave_up := -1.0
	for i in 60 * 20:
		hand.tick(STEP, g)
		g.clock += STEP
		searched = searched or hand.mind.search_until > 0.0
		if not hand.alerted:
			gave_up = g.clock
			break
	check.call(
		searched and moments.has("lost"), "a hand that lost the player searches (%s)" % [moments]
	)
	check.call(
		gave_up > 0.0 and gave_up < Squad.SEARCH[1] + 1.0,
		"and gives up after a while (%.1f s)" % gave_up
	)
	# A crowd spotting the player at once: one "spot", not a flood.
	moments.clear()
	g.clock += 30.0
	for k in 8:
		var e := Enemy.new("billy", p.x + 3.0 + k * .4, p.y)
		e.mind = Squad.Mind.new()
		Squad.bark(e, g, "spot")
		Squad.bark(e, g, "flank")
	check.call(moments == ["spot"], "barks are throttled, not a flood (%s)" % [moments])


## Three hands hunting the player: HOG WILD sends one wide, EASY none.
static func _flank(main, check: Callable) -> void:
	var sent := []
	for diff: int in [0, 3]:
		var g := _game(main, "range", diff)
		g.ticked.emit(STEP)
		g.enemies.clear()
		var p := g.player
		var hands: Array = []
		for k in 3:
			var a := p.angle + (k - 1) * .25
			var e := Enemy.new("billy", p.x + cos(a) * 9.0, p.y + sin(a) * 9.0)
			e.mind = Squad.Mind.new()
			e.alerted = true
			e.target = [p.x, p.y]
			g.enemies.append(e)
			hands.append(e)
		var flanker: Enemy = null
		var from := 0.0
		var still := Game.Controls.new()
		for i in 60 * 8:
			g.tick(STEP, still)
			if flanker == null:
				for e: Enemy in hands:
					if e.mind.flank_until > g.clock:
						flanker = e
						from = atan2(e.y - p.y, e.x - p.x)
		var swung := 0.0
		if flanker != null:
			swung = absf(Enemy.angle_delta(atan2(flanker.y - p.y, flanker.x - p.x), from))
		sent.append([flanker != null, swung])
	check.call(not sent[0][0], "EASY sends nobody wide")
	check.call(
		sent[1][0] and sent[1][1] > .5,
		"HOG WILD sends one wide round the player (%.2f rad)" % sent[1][1]
	)
