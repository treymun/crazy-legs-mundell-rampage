## Checks of COUNTY RUN (src/modes/county_*.gd, CLAUDE.md "County Run"):
##
##   godot --headless --path godot --script res://tools/county_check.gd [-- seconds=<play>]
##
## The rules, each set up exactly: a run starts at level 1 with the .38 and
## the crowbar in two of three slots; a weapon card fills the open slot; the
## number keys and the wheel switch between carried guns keeping their rounds
## and upgrades; at three a weapon card asks which to swap out, CANCEL leaves
## the same three cards, a swap drops that gun's upgrades but keeps the perks
## and milestones, and nothing ever carries a fourth; no card offers a gun
## already carried, and every ordinary set has an upgrade for the gun in hand;
## one pickup worth three levels across level 10 queues 9, 10 (a milestone,
## its own big cards) and 11 in order and play goes on once all are taken;
## level 20's milestones leave out what 10 gave; two shotgun builds (TIGHT
## CHOKE vs EXTRA BUCK, both with BUCKSHOT BREAKER) each win their own fight;
## XP is not taken through a wall or from another floor, and is taken in view
## on the same floor; the world and the clock hold while a choice is up;
## SECOND WIND, GRIT ARMOR, MUDSLIDE, CHAIN REACTION, LAST STAND, BREAKAWAY,
## QUICK HANDS and GOOD BOOTS do what their cards say; records go to their own
## file; spawns come in out of sight, far enough off, on ground that walks to
## the player. Then the bot plays each map (seconds=, 45 by default) through
## a death and a retry. tools/check_fixes.gd runs the quick part (run()).
extends SceneTree

const Bot := preload("res://tools/county_bot.gd")
const STEP := 1.0 / 60.0
const QUICK_SECONDS := 25.0

var failures: Array = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Control = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	var seconds := 45.0
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("seconds="):
			seconds = float(arg.substr(8))
	var report := func(ok: bool, text: String) -> void:
		print("  ok   " if ok else "  FAIL ", text)
		if not ok:
			failures.append(text)
	run(main, report, seconds)
	print("")
	print("COUNTY CHECK OK" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


## The checks; `check` is check_fixes' (condition, text).
static func run(main, check: Callable, seconds := QUICK_SECONDS) -> void:
	print("COUNTY RUN")
	CountyRecords.folder_override = OS.get_cache_dir().path_join("clmr-county-check")
	DirAccess.make_dir_recursive_absolute(CountyRecords.folder_override)
	if FileAccess.file_exists(CountyRecords.path()):
		DirAccess.remove_absolute(CountyRecords.path())
	_maps(main, check)
	_start(main, check)
	_slots(main, check)
	_swap(main, check)
	_offers(main, check)
	_levels(main, check)
	_builds(main, check)
	_xp(main, check)
	_hold(main, check)
	_abilities(main, check)
	_spawns(main, check)
	_routes(main, check)
	_campaign_untouched(main, check)
	for map_id: String in CountyData.MAP_IDS:
		_play(main, check, map_id, seconds)
	_records(check)
	CountyRecords.folder_override = ""


## A run on `map_id`, started (its first tick played, the spawner held off).
static func made(main, map_id := "county_hickston") -> Game:
	var g: Game = main.make_game(map_id)
	g.configure({"difficulty": 1})
	Modes.setup(g, Modes.COUNTY, 1)
	g.tick(STEP, Game.Controls.new())
	var f = g.features["county"]
	f.next_spawn = 1e9
	f.next_elite = 1e9
	f.next_lull = 1e9
	Modes.clear_enemies(g)
	return g


static func _maps(_main, check: Callable) -> void:
	for map_id: String in CountyData.MAP_IDS:
		check.call(FileAccess.file_exists("res://data/%s.json" % map_id), "%s is built" % map_id)
		check.call(not CountyData.map(map_id).is_empty(), "%s is on the map picker" % map_id)


static func _start(main, check: Callable) -> void:
	var g := made(main)
	var f = g.features["county"]
	check.call(f.on and Modes.mode_of(g) == Modes.COUNTY, "a run starts under COUNTY RUN")
	check.call(f.level == 1 and f.xp == 0, "it starts at level 1 with no XP")
	check.call(
		f.slots == [Weapons.CROWBAR, Weapons.REVOLVER, -1],
		"the crowbar and the .38 in two of three slots (%s)" % str(f.slots)
	)
	var owned := 0
	for i in Weapons.COUNT:
		owned += 1 if g.armory.owned[i] else 0
	check.call(
		owned == 2 and g.armory.active == Weapons.REVOLVER, "two guns carried, the .38 in hand"
	)
	check.call(
		g.armory.loaded[Weapons.REVOLVER] == 6 and g.armory.reserve[Weapons.REVOLVER] > 0,
		"the .38 comes loaded with spare rounds"
	)
	check.call(g.supply_rule == 2 and g.pickups.is_empty(), "the level's own drops are off")
	var shut := 0
	for door: LevelData.Door in g.world.doors:
		shut += 0 if door.opened else 1
	check.call(shut == 0, "every door stands open (%d shut)" % shut)
	check.call(main.entries().has("COUNTY RUN"), "COUNTY RUN is on the title")


## Fills the third slot; switching keeps rounds and upgrades.
static func _slots(main, check: Callable) -> void:
	var g := made(main)
	var f = g.features["county"]
	f.pending = [[2, false, g.armory.active]]
	f.offer = [
		CountyBuild.card("weapon", "", Weapons.SHOTGUN),
		CountyBuild.card("perk", "good_boots"),
		CountyBuild.card("upgrade", "quick_hands", Weapons.REVOLVER)
	]
	check.call(CountyMode.choose(g, 0), "a weapon card with a slot open is taken")
	check.call(
		f.slots == [Weapons.CROWBAR, Weapons.REVOLVER, Weapons.SHOTGUN],
		"it fills the open slot (%s)" % str(f.slots)
	)
	check.call(
		g.armory.owned[Weapons.SHOTGUN] and g.armory.loaded[Weapons.SHOTGUN] == 2,
		"the sawed-off comes out loaded"
	)
	f.ranks[CountyBuild.key(Weapons.REVOLVER, "deadeye")] = 2
	g.armory.loaded[Weapons.REVOLVER] = 3
	g.armory.reserve[Weapons.REVOLVER] = 17
	# The number keys pick slots (county_input.gd); the wheel cycles carried guns.
	CountyInput.key_play(main, g, KEY_3)
	check.call(g.armory.active == Weapons.SHOTGUN, "3 picks the third slot")
	CountyInput.key_play(main, g, KEY_1)
	check.call(g.armory.active == Weapons.CROWBAR, "1 picks the crowbar")
	g.armory.cycle(1, g)
	check.call(g.armory.active == Weapons.REVOLVER, "the next-gun key goes to the next slot")
	g.armory.cycle(1, g)
	g.armory.cycle(1, g)
	check.call(g.armory.active == Weapons.CROWBAR, "and round to the first")
	g.armory.cycle(1, g)
	check.call(
		g.armory.loaded[Weapons.REVOLVER] == 3 and g.armory.reserve[Weapons.REVOLVER] == 17,
		"switching keeps a gun's rounds"
	)
	check.call(CountyBuild.rank(f, Weapons.REVOLVER, "deadeye") == 2, "and its upgrades")
	var shown := false
	for i in f.slots.size():
		shown = shown or int(f.slots[i]) == g.armory.active
	check.call(shown, "the HUD's slots hold the gun in hand")


## A weapon at capacity: which to swap, the loss shown, CANCEL, perks kept.
static func _swap(main, check: Callable) -> void:
	var g := made(main)
	var f = g.features["county"]
	CountyBuild.put_weapon(g, f, Weapons.SHOTGUN, 2)
	f.ranks[CountyBuild.key(Weapons.SHOTGUN, "tight_choke")] = 2
	f.ranks["perk/good_boots"] = 1
	f.ranks["m/grit_armor"] = 1
	f.pending = [[5, false, g.armory.active]]
	var cards := [
		CountyBuild.card("weapon", "", Weapons.RIFLE),
		CountyBuild.card("perk", "xp_magnet"),
		CountyBuild.card("upgrade", "quick_hands", Weapons.REVOLVER)
	]
	f.offer = cards.duplicate(true)
	check.call(not CountyMode.choose(g, 0), "a weapon card with every slot full needs a slot")
	CountyScreens._shown_at = -100000
	CountyInput.take(main, g, 0)
	check.call(CountyScreens.swapping == 0, "taking it asks which to swap out")
	var lost := CountyBuild.upgrades_on(f, Weapons.SHOTGUN)
	check.call(
		lost.size() == 1 and String(lost[0][0]) == "TIGHT CHOKE",
		"the swap shows the upgrades it would lose"
	)
	CountyInput.pick_slot(main, g, 2)
	CountyInput.cancel_swap(main)
	check.call(
		CountyScreens.swapping < 0 and f.offer == cards and f.pending.size() == 1,
		"CANCEL goes back to the same three cards"
	)
	check.call(f.slots[2] == Weapons.SHOTGUN, "nothing was swapped")
	CountyInput.take(main, g, 0)
	CountyInput.pick_slot(main, g, 2)
	CountyInput.confirm_swap(main, g)
	check.call(
		f.slots == [Weapons.CROWBAR, Weapons.REVOLVER, Weapons.RIFLE],
		"CONFIRM swaps the picked slot (%s)" % str(f.slots)
	)
	check.call(
		CountyBuild.rank(f, Weapons.SHOTGUN, "tight_choke") == 0, "the swapped gun's upgrades go"
	)
	check.call(
		CountyBuild.perk_rank(f, "good_boots") == 1 and CountyBuild.has(f, "grit_armor"),
		"perks and milestones stay"
	)
	check.call(
		not g.armory.owned[Weapons.SHOTGUN] and g.armory.owned[Weapons.RIFLE],
		"the old gun is gone, the new one carried"
	)
	var most := 0
	for k in 40:
		f.level = 3 + k
		var offer := CountyBuild.offers(g, f, [f.level, false, g.armory.active])
		for c: Dictionary in offer:
			if String(c["type"]) == "weapon":
				CountyBuild.take(g, f, c, k % 3)
		var owned := 0
		for i in Weapons.COUNT:
			owned += 1 if g.armory.owned[i] else 0
		most = maxi(most, owned)
	check.call(most == 3, "forty swaps later no more than three guns are ever carried (%d)" % most)


## What ordinary sets offer.
static func _offers(main, check: Callable) -> void:
	var g := made(main)
	var f = g.features["county"]
	var dup := 0
	var carried := 0
	var guaranteed := 0
	var sets := 0
	var weapon_early := false
	for k in 60:
		var entry := [2 + k, false, g.armory.active]
		var offer := CountyBuild.offers(g, f, entry)
		sets += 1
		var seen := {}
		var mine := false
		for c: Dictionary in offer:
			var id := "%s/%s/%d" % [c["type"], c["id"], c["gun"]]
			dup += 1 if seen.has(id) else 0
			seen[id] = true
			if String(c["type"]) == "weapon" and CountyBuild.carried(f).has(int(c["gun"])):
				carried += 1
			if String(c["type"]) == "upgrade" and int(c["gun"]) == int(entry[2]):
				mine = true
			if k < 3 and String(c["type"]) == "weapon" and CountyBuild.open_slot(f) >= 0:
				weapon_early = true
		guaranteed += 1 if mine or CountyBuild.open_upgrades(f, int(entry[2])).is_empty() else 0
		# Take the guaranteed upgrade (the gun's ranks fill up).
		for c: Dictionary in offer:
			if String(c["type"]) == "upgrade":
				CountyBuild.take(g, f, c)
				break
	check.call(dup == 0, "no card twice in a set")
	check.call(carried == 0, "no weapon card for a gun already carried")
	check.call(
		guaranteed == sets,
		(
			"every set has an upgrade for the gun in hand while it has any left (%d of %d)"
			% [guaranteed, sets]
		)
	)
	check.call(weapon_early, "with a slot open a weapon is offered from the first level up")
	# The gun in hand used up: another carried gun's upgrade or a perk instead.
	for id: String in CountyData.upgrades_for(Weapons.REVOLVER):
		f.ranks[CountyBuild.key(Weapons.REVOLVER, id)] = int(CountyData.upgrade(id).get("ranks", 1))
	var offer := CountyBuild.offers(g, f, [70, false, Weapons.REVOLVER])
	var useful := 0
	for c: Dictionary in offer:
		if String(c["type"]) == "upgrade" and int(c["gun"]) != Weapons.REVOLVER:
			useful += 1
		elif String(c["type"]) in ["perk", "weapon"]:
			useful += 1
	check.call(
		offer.size() == 3 and useful == 3,
		"the .38's upgrades used up, the set falls back on other guns and perks"
	)
	g.player.health = 100
	var patch := false
	for k in 30:
		for c: Dictionary in CountyBuild.offers(g, f, [80 + k, false, g.armory.active]):
			patch = patch or String(c["id"]) == "patch_up"
	check.call(not patch, "PATCH UP is never offered at full health")
	var card := CountyBuild.describe(g, f, CountyBuild.card("upgrade", "deadeye", Weapons.REVOLVER))
	check.call(
		(
			String(card["for"]) == ".38 SPECIAL"
			and String(card["rank"]) != ""
			and String(card["lasts"]) != ""
		),
		"a card names its gun, its rank and how long it lasts"
	)
	var gun_card := CountyBuild.describe(g, f, CountyBuild.card("weapon", "", Weapons.ROCKET))
	check.call(
		String(gun_card["lines"][1]).begins_with("COMES WITH"),
		"a weapon card says how it plays and what ammo comes with it"
	)


## One pickup across level 10, then level 20.
static func _levels(main, check: Callable) -> void:
	var g := made(main)
	var f = g.features["county"]
	f.level = 8
	f.xp = 0
	var need := CountyData.xp_to_next(8) + CountyData.xp_to_next(9) + CountyData.xp_to_next(10)
	CountyOrbs._lay(f, g.player.x + .2, g.player.y, g.world.stand(g.player), need + 1, "xp")
	g.tick(STEP, Game.Controls.new())
	var levels: Array = []
	var big: Array = []
	for entry: Array in f.pending:
		levels.append(int(entry[0]))
		big.append(bool(entry[1]))
	check.call(
		levels == [9, 10, 11],
		"one pickup worth three levels queues 9, 10 and 11 in order (%s)" % str(levels)
	)
	check.call(big == [false, true, false], "level 10 is the milestone")
	check.call(Modes.holds(g), "the world holds while they wait")
	var kinds: Array = []
	var taken := 0
	while not f.pending.is_empty() and taken < 5:
		var all_big := true
		for c: Dictionary in f.offer:
			all_big = all_big and String(c["type"]) == "milestone"
		kinds.append(all_big)
		CountyMode.choose(g, 0, 0)
		taken += 1
	check.call(
		kinds == [false, true, false],
		"each choice comes in turn, level 10's all major cards (%s)" % str(kinds)
	)
	check.call(
		f.pending.is_empty() and not Modes.holds(g), "play goes on once every choice is made"
	)
	# Level 20: none of 10's milestone again (except the spares).
	var first: Dictionary = {}
	for k: String in f.ranks:
		if k.begins_with("m/"):
			first[k.substr(2)] = true
	f.level = 19
	f.xp = CountyData.xp_to_next(19) - 1
	CountyMode.gain(g, f, 1)
	g.tick(STEP, Game.Controls.new())
	var again := false
	var types := {}
	for c: Dictionary in f.offer:
		types[String(CountyData.milestone(String(c["id"])).get("kind", ""))] = true
		var spec := CountyData.milestone(String(c["id"]))
		again = again or (first.has(String(c["id"])) and not bool(spec.get("again", false)))
	check.call(f.pending.size() == 1 and bool(f.pending[0][1]), "level 20 is a milestone too")
	check.call(not again and f.offer.size() == 3, "level 20 leaves out the milestone already taken")
	check.call(
		types.has("survive") and types.has("move"),
		"a milestone set mixes a way to live longer and a move (%s)" % str(types.keys())
	)


## Two builds for one gun, each better at its own fight.
static func _builds(main, check: Callable) -> void:
	var line_a := _shotgun_fight(main, "tight_choke", "line")
	var line_b := _shotgun_fight(main, "extra_buck", "line")
	var crowd_a := _shotgun_fight(main, "tight_choke", "crowd")
	var crowd_b := _shotgun_fight(main, "extra_buck", "crowd")
	print(
		(
			"    shotgun damage: choke+breaker line %d crowd %d / buck+breaker line %d crowd %d"
			% [line_a, crowd_a, line_b, crowd_b]
		)
	)
	check.call(
		line_a > line_b,
		"a tight-choke shotgun with BUCKSHOT BREAKER does more to a line at midrange"
	)
	check.call(
		crowd_b > crowd_a,
		"a wide extra-buck shotgun with BUCKSHOT BREAKER does more to a crowd up close"
	)


static func _shotgun_fight(main, upgrade: String, how: String) -> int:
	var g := made(main)
	var f = g.features["county"]
	CountyBuild.put_weapon(g, f, Weapons.SHOTGUN, 2)
	f.ranks[CountyBuild.key(Weapons.SHOTGUN, upgrade)] = 3
	f.ranks["m/buckshot_breaker"] = 1
	var p: Player = g.player
	var spot := _open_line(g, 10.0)
	Modes.place(g, p, spot.x, spot.y, spot.z)
	var targets: Array = []
	var ax := cos(p.angle)
	var ay := sin(p.angle)
	if how == "line":
		for d: float in [6.0, 6.8, 7.6, 8.4]:
			targets.append(Vector2(p.x + ax * d, p.y + ay * d))
	else:
		for k in 6:
			var a := p.angle + (k - 2.5) * .19
			targets.append(Vector2(p.x + cos(a) * 2.0, p.y + sin(a) * 2.0))
	var total := 0
	for shot in 12:
		g.enemies.clear()
		for at: Vector2 in targets:
			var e := Enemy.new("big_billy", at.x, at.y, p.angle + PI)
			e.hp = 5000.0
			e.max_hp = 5000.0
			g.enemies.append(e)
		g.armory.cooldown = 0.0
		g.armory.switch = 0.0
		g.armory.loaded[Weapons.SHOTGUN] = 2
		g.armory.fire(g)
		g.ticked.emit(STEP)
		for e: Enemy in g.enemies:
			total += int(5000.0 - e.hp)
	return total


## An open spot and a heading with `reach` cells of clear floor ahead.
static func _open_line(g: Game, reach: float) -> Vector3:
	var w: LevelData = g.world
	var spots := CountySpawner.spots(g)
	for at: Vector2 in spots:
		for k in 8:
			var a := k * TAU / 8.0
			var end := at + Vector2(cos(a), sin(a)) * reach
			if w.blocked(end.x, end.y, .4) or not w.visible(at.x, at.y, end.x, end.y):
				continue
			var flat := true
			for s in 10:
				var q := at.lerp(end, s / 10.0)
				flat = (
					flat
					and absf(w.elevation(q.x, q.y) - w.elevation(at.x, at.y)) < .05
					and not w.blocked(q.x, q.y, .45)
				)
			if flat:
				return Vector3(at.x, at.y, a)
	return Vector3(spots[0].x, spots[0].y, 0.0)


## XP through a wall, from another floor, in view on the same floor.
static func _xp(main, check: Callable) -> void:
	var g := made(main)
	var f = g.features["county"]
	var p: Player = g.player
	var w: LevelData = g.world
	# A wall: a spot where a cell's middle is open and the next cell is solid.
	var wall_case := Vector4.ZERO
	for at: Vector2 in CountySpawner.spots(g):
		for d: Vector2 in [Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1)]:
			var mid := at + d
			var far := at + d * 2.0
			if (
				w.solid[w.cell(mid.x, mid.y)] >= 0
				and CountySpawner.reached(g, far.x, far.y)
				and not w.blocked(far.x, far.y, .3)
			):
				wall_case = Vector4(at.x, at.y, far.x, far.y)
				break
		if wall_case != Vector4.ZERO:
			break
	f.ranks["perk/xp_magnet"] = 3
	Modes.place(g, p, wall_case.x, wall_case.y, 0.0)
	f.orbs = []
	CountyOrbs._lay(f, wall_case.z, wall_case.w, w.elevation(wall_case.z, wall_case.w), 5, "xp")
	var xp0: int = f.xp_total
	for k in 30:
		g.tick(STEP, Game.Controls.new())
	check.call(
		f.xp_total == xp0 and f.orbs.size() == 1,
		"XP two steps off behind a wall is not taken, magnet or not"
	)
	# Another floor: a deck over open ground.
	var deck := _deck_over(g)
	if deck != Vector3.ZERO:
		Modes.place(g, p, deck.x, deck.y, 0.0)
		f.orbs = []
		CountyOrbs._lay(f, deck.x + .3, deck.y, deck.z, 5, "xp")
		for k in 30:
			g.tick(STEP, Game.Controls.new())
		check.call(
			f.xp_total == xp0 and f.orbs.size() == 1,
			"XP on a deck overhead is not taken from the floor under it"
		)
	else:
		check.call(false, "a deck to check XP from another floor on")
	# In view, same floor.
	var spot := _open_line(g, 4.0)
	Modes.place(g, p, spot.x, spot.y, spot.z)
	f.orbs = []
	CountyOrbs._lay(
		f, p.x + cos(spot.z) * 1.6, p.y + sin(spot.z) * 1.6, w.elevation(p.x, p.y), 5, "xp"
	)
	for k in 90:
		g.tick(STEP, Game.Controls.new())
	check.call(
		f.xp_total == xp0 + 5 and f.orbs.is_empty(),
		"XP in view on the same floor floats in and is taken"
	)
	check.call(not f.pops.is_empty() or f.xp_total == xp0 + 5, "taking it pops its +5")
	# Drops land on ground the player can reach.
	var bad := 0
	for k in 40:
		var at: Vector2 = CountySpawner.spots(g)[(k * 37) % CountySpawner.spots(g).size()]
		var e := Enemy.new("billy", at.x + .45, at.y + .45)
		e.max_hp = 70.0
		CountyOrbs.drop(g, f, e)
	for orb: Array in f.orbs:
		if not CountyOrbs._standable(g, float(orb[0]), float(orb[1]), float(orb[2])):
			bad += 1
	check.call(bad == 0, "every drop lies on reachable floor (%d not)" % bad)
	# Merging keeps the XP.
	f.orbs = []
	for k in 90:
		CountyOrbs._lay(
			f,
			p.x + 3.0 + (k % 9) * .15,
			p.y + 3.0 + (k / 9) * .15,
			w.elevation(p.x + 3, p.y + 3),
			1 + k % 3,
			"xp"
		)
	var before := CountyOrbs.total_xp(f)
	CountyOrbs.merge(f, 1.6)
	check.call(
		CountyOrbs.total_xp(f) == before and f.orbs.size() < 90,
		"piles merge and keep their XP (%d piles of %d XP)" % [f.orbs.size(), before]
	)


## A cell with a walkable deck over open floor: [x, y, deck top].
static func _deck_over(g: Game) -> Vector3:
	var w: LevelData = g.world
	if w.geo == null:
		return Vector3.ZERO
	for at: Vector2 in CountySpawner.spots(g):
		var top: float = w.floor_under(at.x, at.y, 20.0)
		if top > w.elevation(at.x, at.y) + 1.5:
			return Vector3(at.x, at.y, top)
	return Vector3.ZERO


## The world and the clock hold while a choice or the build screen is up.
static func _hold(main, check: Callable) -> void:
	var g := made(main)
	var f = g.features["county"]
	var e := CountySpawner.spawn(g, f, "billy", g.player.x + 6.0, g.player.y, false)
	f.next_spawn = 0.0
	f.pending = [[2, false, g.armory.active]]
	f.offer = CountyBuild.offers(g, f, f.pending[0])
	var t0: float = f.run_time
	var c0: float = g.clock
	var n0 := g.enemies.size()
	var at := Vector2(e.x, e.y)
	for k in 120:
		g.tick(STEP, Game.Controls.new())
	check.call(f.run_time == t0 and g.clock == c0, "the clock stops while the cards are up")
	check.call(
		g.enemies.size() == n0 and Vector2(e.x, e.y) == at, "nothing moves or spawns meanwhile"
	)
	f.pending = []
	f.offer = []
	CountyInput.open_build(g)
	for k in 30:
		g.tick(STEP, Game.Controls.new())
	check.call(f.run_time == t0, "and while the build screen is up")
	CountyInput.close_build(g)
	g.tick(STEP, Game.Controls.new())
	check.call(f.run_time > t0, "and runs again after")


static func _abilities(main, check: Callable) -> void:
	var g := made(main)
	var f = g.features["county"]
	var p: Player = g.player
	# SECOND WIND.
	f.ranks["m/second_wind"] = 1
	p.health = 10
	g.damage(60.0, null, "TEST")
	check.call(
		p.health >= 40 and f.second_wind_used and not g.defeated(),
		"SECOND WIND saves a fatal hit (health %d)" % p.health
	)
	p.health = 10
	g.damage(60.0, null, "TEST")
	g.clock += 2.0
	g.damage(60.0, null, "TEST")
	check.call(p.health == 0, "only once a run")
	g = made(main)
	f = g.features["county"]
	p = g.player
	# GRIT ARMOR.
	f.ranks["m/grit_armor"] = 1
	CountyOrbs._lay(f, p.x + .1, p.y, g.world.stand(p), 15, "xp")
	g.tick(STEP, Game.Controls.new())
	check.call(int(f.armor) == 15, "GRIT ARMOR turns 15 XP into 15 armor (%d)" % int(f.armor))
	g.damage(10.0, null, "TEST")
	check.call(
		p.health == 100 and f.armor < 15.0 and f.armor > 0.0,
		"armor takes a hit first (%.0f left)" % f.armor
	)
	f.pending = []
	f.offer = []
	# MUDSLIDE.
	var spot := _open_line(g, 8.0)
	Modes.place(g, p, spot.x, spot.y, spot.z)
	f.ranks["m/mudslide"] = 1
	var c := Game.Controls.new()
	c.use = true
	var from := Vector2(p.x, p.y)
	g.tick(STEP, c)
	for k in 30:
		g.tick(STEP, Game.Controls.new())
	check.call(
		Vector2(p.x, p.y).distance_to(from) > 3.0,
		"MUDSLIDE on USE slides (%.1f steps)" % Vector2(p.x, p.y).distance_to(from)
	)
	check.call(f.dash_ready > g.clock, "then waits on its cooldown")
	# GOOD BOOTS.
	var walk := func(boots: int) -> float:
		var h := made(main)
		var hf = h.features["county"]
		hf.ranks["perk/good_boots"] = boots
		var s := _open_line(h, 9.0)
		Modes.place(h, h.player, s.x, s.y, s.z)
		var start := Vector2(h.player.x, h.player.y)
		var go := Game.Controls.new()
		go.forward = 1.0
		for k in 60:
			h.tick(STEP, go)
		return Vector2(h.player.x, h.player.y).distance_to(start)
	var plain: float = walk.call(0)
	var booted: float = walk.call(3)
	check.call(booted > plain * 1.15, "GOOD BOOTS 3 walks faster (%.2f vs %.2f)" % [booted, plain])
	# QUICK HANDS.
	var reload := func(rank: int) -> int:
		var h := made(main)
		var hf = h.features["county"]
		hf.ranks[CountyBuild.key(Weapons.REVOLVER, "quick_hands")] = rank
		h.armory.loaded[Weapons.REVOLVER] = 0
		h.armory.start_reload(h)
		var ticks := 0
		while h.armory.reload > 0.0 and ticks < 600:
			h.tick(STEP, Game.Controls.new())
			ticks += 1
		return ticks
	var slow: int = reload.call(0)
	var quick: int = reload.call(3)
	check.call(quick < slow * .7, "QUICK HANDS 3 reloads faster (%d ticks vs %d)" % [quick, slow])
	# LAST STAND.
	g = made(main)
	f = g.features["county"]
	f.ranks["m/last_stand"] = 1
	var e := CountySpawner.spawn(g, f, "billy", g.player.x + 1.0, g.player.y, false)
	g.armory.select(Weapons.CROWBAR, g)
	e.hurt(9999.0, g, false, false, null, "crowbar")
	check.call(g.clock < f.guard_until, "a melee kill starts LAST STAND")
	g.player.health = 100
	g.damage(20.0, null, "TEST")
	check.call(g.player.health >= 89, "LAST STAND halves what lands (health %d)" % g.player.health)
	# CHAIN REACTION.
	g = made(main)
	f = g.features["county"]
	f.ranks["m/chain_reaction"] = 1
	CountyBuild.put_weapon(g, f, Weapons.ROCKET, 2)
	var q := _open_line(g, 10.0)
	Modes.place(g, g.player, q.x, q.y, q.z)
	var ring: Array = []
	for k in 8:
		var a := k * TAU / 8.0
		var at := Vector2(
			g.player.x + cos(q.z) * 7.0 + cos(a) * .9, g.player.y + sin(q.z) * 7.0 + sin(a) * .9
		)
		var b := CountySpawner.spawn(g, f, "coot", at.x, at.y, false)
		b.hp = 20.0
		ring.append(b)
	var spread := 0
	for k in 4:
		var x := g.player.x + cos(q.z) * (9.0 + k * 1.3)
		var y := g.player.y + sin(q.z) * (9.0 + k * 1.3)
		var far := CountySpawner.spawn(g, f, "coot", x, y, false)
		far.hp = 20.0
	var center := Vector2(g.player.x + cos(q.z) * 7.0, g.player.y + sin(q.z) * 7.0)
	var shot := GameState.Shot.new(
		center.x,
		center.y,
		g.world.elevation(center.x, center.y) + .5,
		0.0,
		0.0,
		0.0,
		"bottle_rocket",
		0.0,
		false,
		120
	)
	g.explode(shot)
	var queued: int = f.chains.size()
	for k in 60:
		g.tick(STEP, Game.Controls.new())
	check.call(
		queued > 0 and queued <= int(CountyData.milestone("chain_reaction").get("most", 3)),
		"explosive kills set off follow-up blasts, at most 3 a shot (%d)" % queued
	)
	# BREAKAWAY.
	g = made(main)
	f = g.features["county"]
	f.ranks["m/breakaway"] = 1
	var crowd: Array = []
	for k in 5:
		var a := k * TAU / 5.0
		crowd.append(
			CountySpawner.spawn(
				g, f, "billy", g.player.x + cos(a) * 1.5, g.player.y + sin(a) * 1.5, false
			)
		)
	CountyMoves._breakaway(g, f)
	for b2: Enemy in crowd:
		b2.hp = 0.0
	CountyMoves._breakaway(g, f)
	check.call(g.clock < f.burst_until, "breaking out of a crowd of five starts BREAKAWAY")
	check.call(
		(
			CountyBuild.reload_scale(f, Weapons.REVOLVER, true) < .6
			and CountyMode.new().move_scale(g, g.player) > 1.2
		),
		"BREAKAWAY speeds the feet and the reload"
	)


## Spawns: out of sight, far enough off, on ground that walks to the player.
static func _spawns(main, check: Callable) -> void:
	for map_id: String in CountyData.MAP_IDS:
		var g := made(main, map_id)
		var f = g.features["county"]
		var p: Player = g.player
		var near := CountyData.number("spawn", "near", 11.0)
		var close := 0
		var seen := 0
		var stranded := 0
		var got := 0
		for k in 40:
			var at = CountySpawner.spot(g, f)
			if at == null:
				continue
			got += 1
			if at.distance_to(Vector2(p.x, p.y)) < near - .01:
				close += 1
			if g.world.visible(p.x, p.y, at.x, at.y, p.eye, g.world.elevation(at.x, at.y) + .9):
				seen += 1
			if not CountySpawner.reached(g, at.x, at.y):
				stranded += 1
		check.call(got >= 30, "%s: spawn points found (%d of 40)" % [map_id, got])
		check.call(
			close == 0 and seen == 0,
			(
				"%s: none nearer than %d or in sight (%d near, %d seen)"
				% [map_id, int(near), close, seen]
			)
		)
		check.call(stranded == 0, "%s: every one on ground that walks to the start" % map_id)
		check.call(
			CountySpawner.spots(g).size() > 1500,
			"%s: a big map (%d open cells to spawn on)" % [map_id, CountySpawner.spots(g).size()]
		)


## The routes: hands spawned round a player who stands still and never shoots
## walk all the way to them within a minute (in sight eight steps off, or right
## up close; the bayou's wade round the deep water is the slowest).
static func _routes(main, check: Callable) -> void:
	for map_id: String in CountyData.MAP_IDS:
		var g := made(main, map_id)
		var f = g.features["county"]
		var p: Player = g.player
		g.cheats.god = true
		var born := {}
		for k in 14:
			var at = CountySpawner.spot(g, f)
			if at != null:
				var e := CountySpawner.spawn(
					g, f, "billy" if k % 2 == 0 else "coot", at.x, at.y, false
				)
				born[e.get_instance_id()] = e
		var came := {}
		var ticks := 0
		while ticks < 60 * 60 and came.size() < born.size():
			g.tick(STEP, Game.Controls.new())
			ticks += 1
			for key: int in born:
				var e: Enemy = born[key]
				if came.has(key):
					continue
				var d := Vector2(e.x - p.x, e.y - p.y).length()
				var sees: bool = (
					d < 8.0 and g.world.visible(e.x, e.y, p.x, p.y, g.world.stand(e) + .9, p.eye)
				)
				if d < 3.0 or sees:
					came[key] = ticks / 60.0
		for key: int in born:
			if not came.has(key):
				var e: Enemy = born[key]
				print(
					(
						"      not there: %s at %.1f, %.1f, %.1f steps off, %d by the field, swims %s"
						% [
							e.kind,
							e.x,
							e.y,
							Vector2(e.x - p.x, e.y - p.y).length(),
							g.flow.distance(e.x, e.y),
							e.swims
						]
					)
				)
		var times: Array = came.values()
		times.sort()
		var median := float(times[times.size() / 2]) if not times.is_empty() else -1.0
		print(
			(
				"    %s: %d of %d hands reached the player, median %.0fs"
				% [map_id, came.size(), born.size(), median]
			)
		)
		check.call(
			born.size() >= 10 and came.size() >= born.size() * .85,
			(
				"%s: hands spawned out of sight walk to a player who stands still (%d of %d)"
				% [map_id, came.size(), born.size()]
			)
		)


## The campaign is untouched: no mode, the hooks hand back what they get.
static func _campaign_untouched(main, check: Callable) -> void:
	var g: Game = main.make_game("hickston")
	g.configure({})
	check.call(
		Modes.mode_of(g) == Modes.CAMPAIGN and not Modes.holds(g), "a campaign game is no run"
	)
	check.call(
		Modes.move_scale(g, g.player) == 1.0 and Modes.incoming(g, g.player, 12.5, "X") == 12.5,
		"the run's hooks leave campaign play as it was"
	)
	check.call(
		(
			Modes.hit_reach(g, 1.65) == 1.65
			and Modes.blast_tuning(g, null, 2.8, 160.0) == [2.8, 160.0, 0.0, 0.0]
		),
		"swings and blasts as they were"
	)
	check.call(g.features["county"].save().is_empty(), "the run saves nothing into a campaign save")


## The bot plays the map through a death, then a retry starts it fresh.
static func _play(main, check: Callable, map_id: String, seconds: float) -> void:
	var g: Game = main.make_game(map_id)
	g.configure({"difficulty": 1})
	Modes.setup(g, Modes.COUNTY, 1)
	var f = g.features["county"]
	var bot = Bot.new()
	var worst := 0.0
	var ticks := 0
	while not g.defeated() and ticks < int(seconds * 60.0):
		if f.on and not f.pending.is_empty():
			CountyMode.choose(g, Bot.pick(g, f), 0)
			continue
		var t0 := Time.get_ticks_usec()
		g.tick(STEP, bot.steer(g))
		worst = maxf(worst, (Time.get_ticks_usec() - t0) / 1000.0)
		bot.moved(g)
		ticks += 1
	var died := g.defeated()
	if not died:
		g.damage(9999.0, null, "TEST")
	print(
		(
			"    %s: %.0fs, level %d, %d kills, %d spawned, worst tick %.1f ms%s"
			% [
				map_id,
				f.run_time,
				f.level,
				g.kills,
				f.spawned,
				worst,
				"" if died else " (ended by the check)"
			]
		)
	)
	check.call(f.spawned > 5 and g.kills > 0, "%s: the horde comes and dies" % map_id)
	check.call(
		g.defeated() and f.over and not f.result.is_empty(),
		"%s: death ends the run with its numbers" % map_id
	)
	check.call(
		f.result.has("best_before") and f.result["build"] is Array,
		"%s: the end has the map's best and the build" % map_id
	)
	# Retry: the end's RETRY (county_input.gd) starts the same map fresh.
	main.game = g
	main.state = "play"
	CountyInput.key_play(main, g, KEY_ENTER)
	var again: Game = main.game
	check.call(
		again != g and again.level.id == map_id and CountyMode.active(again),
		"%s: RETRY starts the map again" % map_id
	)
	again.tick(STEP, Game.Controls.new())
	var f2 = again.features["county"]
	check.call(
		(
			f2.level == 1
			and f2.run_time < .1
			and f2.slots == [Weapons.CROWBAR, Weapons.REVOLVER, -1]
			and f2.ranks.is_empty()
		),
		"%s: the retry starts at level 1 with the starting kit" % map_id
	)
	CountyInput.key_play(main, again, KEY_ESCAPE)
	main.game = null
	main.state = "title"


static func _records(check: Callable) -> void:
	var all := CountyRecords.read()
	var ok := true
	for map_id: String in CountyData.MAP_IDS:
		var r = all.get(map_id, {})
		ok = (
			ok
			and r is Dictionary
			and float(r.get("time", 0.0)) > 0.0
			and int(r.get("runs", 0)) >= 1
		)
	check.call(ok, "each map's record is kept in county-records.json")
	check.call(
		CountyRecords.path().begins_with(OS.get_cache_dir()),
		"a check keeps its records in the cache folder, apart from saves"
	)
	check.call(not CountyRecords.path().contains("hickston-quick"), "never in a campaign save")
