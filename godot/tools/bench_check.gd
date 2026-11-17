## Mundell's junk bench (content pass 8: src/bench_mods.gd, src/features/bench.gd,
## src/bench_screen.gd; tools/check_all.gd runs it):
##
##   godot --headless --path godot --script res://tools/bench_check.gd [-- audit]
##
## OFF: no bench, scrap or mods with WORKBENCH off, in County Run, a versus
## map, the range or a deathmatch (mods kept there count for nothing).
## WHERE: the Crossroads' bench on its counter, a chapter's by its start with
## its back to a wall, a player walked into it put back out. SCRAP: pieces
## laid out as a chapter starts, taken as pickups for their worth, dropped by
## a hand killed, a boss, a breakable broken, a vehicle wrecked and a set
## piece come down. BUY: USE opens the board, Controls.buy at a bench tapes
## a mod on for its price; never away from a bench, twice, without the gun
## or the scrap; the board's keys queue the buy. MODS: each mod's change, felt
## (scope, loader, bayonet, choke, drum, brake, flame, spring, fuse,
## bundle). LOOKS: every gun's every pose with every choice of its mods has
## its picture, the board's pictures, the HUD's marks, the bench model, the
## scrap pickups. SAVE: a save and a chapter's kit carry scrap and mods, a
## version 9 save loads with none. NET: co-op's buys are each player's own,
## two games fed the same controls (buys and all) stay identical, a snapshot
## carries the mods onto a fresh game. `audit` prints the scrap each chapter
## gives the campaign bot (CAMPAIGN_SECONDS each).
extends SceneTree

const STEP := 1.0 / 60.0
const Pilot := preload("res://tools/bot_pilot.gd")
const Bench := preload("res://src/features/bench.gd")
const Fire := preload("res://src/features/fire.gd")
const AUDIT_SECONDS := 150

var failures: Array = []
var passes := 0
var main


func _init() -> void:
	_run.call_deferred()


func _check(ok: bool, text: String) -> void:
	print("  ok   " if ok else "  FAIL ", text)
	if ok:
		passes += 1
	else:
		failures.append(text)


func _run() -> void:
	main = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	var started := Time.get_ticks_msec()
	if OS.get_cmdline_user_args().has("audit"):
		_audit()
		main.queue_free()
		await process_frame
		quit()
		return
	for part: String in ["off", "where", "scrap", "buy", "mods", "looks", "save", "net"]:
		print("\n" + part.to_upper())
		call("_" + part)
	print("")
	print(
		(
			"%d checks in %.1f s"
			% [passes + failures.size(), (Time.get_ticks_msec() - started) / 1000.0]
		)
	)
	print("BENCH CHECK OK" if failures.is_empty() else "%d BENCH CHECK(S) FAILED" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


# ------------------------------------------------------------------ helpers


func _game(id: String, on := true, keep_enemies := false) -> Game:
	var g: Game = main.make_game(id)
	g.configure({"difficulty": 1, "bench": 1 if on else 0})
	g.cheats.god = true
	g.lessons = false
	if not keep_enemies:
		g.enemies.clear()
		g.enemy_ids.clear()
	return g


func _tick(g: Game, n: int, c: Game.Controls = null) -> void:
	for t in n:
		g.tick(STEP, c if c != null else Game.Controls.new())


func _bench(g: Game) -> Bench:
	return g.features["bench"]


func _scrap_count(g: Game) -> int:
	var n := 0
	for entry: Array in g.pickups:
		if str(entry[0]).begins_with("scrap_"):
			n += 1
	return n


func _arm(g: Game, guns: Array, scrap: int) -> void:
	for gun: String in guns:
		var slot := Weapons.NAMES.find(gun)
		g.armory.owned[slot] = true
		g.armory.loaded[slot] = Weapons.CAPACITY[slot]
		g.armory.reserve[slot] = 20
	g.armory.scrap = scrap


func _at_bench(g: Game) -> void:
	var b: Array = _bench(g).benches[0]
	var p := g.player
	var facing: float = b[2]
	p.x = float(b[0]) + sin(facing) * 1.1
	p.y = float(b[1]) + cos(facing) * 1.1
	p.angle = atan2(float(b[1]) - p.y, float(b[0]) - p.x)
	p.pitch = 0.0


func _index(id: String) -> int:
	return BenchMods.ids().find(id)


func _buy_one(g: Game, id: String) -> void:
	var c := Game.Controls.new()
	c.buy = _index(id)
	g.tick(STEP, c)


## A cfg value set for this process only (the tuning file stays as it is).
func _tune(section: String, key: String, value: Variant) -> Variant:
	var cfg := Tuning.file(BenchMods.PATH)
	var was: Variant = cfg.get_value(section, key)
	cfg.set_value(section, key, value)
	return was


# ------------------------------------------------------------------ the parts


func _off() -> void:
	var g := _game("hickston", false)
	_tick(g, 3)
	_check(
		not g.bench_live and _bench(g).benches.is_empty() and _scrap_count(g) == 0,
		"WORKBENCH off: no bench, no scrap"
	)
	var picked: Array[String] = ["scope"]
	g.armory.mods = picked
	_tick(g, 1)
	_check(
		not g.armory.firing(Weapons.REVOLVER).has("scope"),
		"WORKBENCH off: a mod counts for nothing"
	)
	for id: String in ["county_hickston", "range", "grainyard"]:
		var h := _game(id)
		_tick(h, 3)
		_check(not h.bench_live and _scrap_count(h) == 0, "%s: no bench, no scrap" % id)
	var dm := _game("hickston")
	Modes.setup(dm, Modes.DEATHMATCH, 2)
	dm.armory.mods = picked
	_tick(dm, 3)
	_check(
		not dm.bench_live and not dm.armory.firing(Weapons.REVOLVER).has("scope"),
		"a deathmatch: no bench, mods count for nothing"
	)
	var tool_options: int = main.options.get("bench", 0)
	_check(tool_options == 0, "a tool plays without the bench unless it asks (main.gd)")


func _where() -> void:
	var hub := _game("hub")
	hub.in_hub = true
	_tick(hub, 3)
	var at: Vector2 = BenchMods.value("bench", "hub_at", Vector2.ZERO)
	var benches := _bench(hub).benches
	_check(
		benches.size() == 1 and absf(float(benches[0][0]) - at.x) < .01,
		"the Crossroads: one bench, in the Road Department's yard"
	)
	var hub_bench: Array = benches[0]
	_check(
		_bench(hub).call(
			"_fits",
			at.x,
			at.y,
			float(hub_bench[2]),
			1.66,
			.66,
			hub.world.elevation(at.x, at.y),
			true
		),
		"its place in the yard is clear floor with the depot's wall behind it"
	)
	_check(_scrap_count(hub) == 0, "no scrap lies about the Crossroads")
	var found := 0
	for id: String in Campaign.ORDER:
		var g := _game(id)
		_tick(g, 2)
		var b := _bench(g).benches
		if b.is_empty():
			print("       %s: no spot for a bench" % id)
			continue
		found += 1
		var spawn := Vector2(float(g.level.spawn[0]), float(g.level.spawn[1]))
		var d := Vector2(float(b[0][0]), float(b[0][1])).distance_to(spawn)
		_check(d <= 4.6, "%s: its bench stands %.1f from the start" % [id, d])
	_check(
		found >= Campaign.ORDER.size() - 2, "most chapters have a bench by their start (%d)" % found
	)
	var g2 := _game("hickston")
	_tick(g2, 2)
	if not _bench(g2).benches.is_empty():
		var b2: Array = _bench(g2).benches[0]
		g2.player.x = b2[0]
		g2.player.y = b2[1]
		_tick(g2, 1)
		var out := Vector2(g2.player.x - float(b2[0]), g2.player.y - float(b2[1])).length()
		_check(out > .3, "a player walked into a chapter's bench is put back out (%.2f)" % out)


func _scrap() -> void:
	var g := _game("hickston")
	_tick(g, 2)
	var laid := _scrap_count(g)
	var want := roundi(float(BenchMods.value("placed", "count", 3)))
	_check(laid == want, "a chapter lays out its loose scrap (%d of %d)" % [laid, want])
	_tick(g, 2)
	_check(_scrap_count(g) == laid, "laid out once")
	# Taken as a pickup, for its worth.
	var entry: Array = []
	for e: Array in g.pickups:
		if str(e[0]).begins_with("scrap_"):
			entry = e
	var worth := BenchMods.worth(str(entry[0]))
	g.armory.scrap = 0
	g.player.x = entry[1]
	g.player.y = entry[2]
	g.player.floor_z = g.world.elevation(g.player.x, g.player.y)
	_tick(g, 2)
	_check(
		g.armory.scrap == worth and worth > 0,
		"a piece taken: %d scrap (%s)" % [g.armory.scrap, entry[0]]
	)
	# Dropped by a hand killed (every one, for this test), a boss and a breakable.
	var was: Variant = _tune("drops", "enemy_chance", 1.0)
	var kinds: Variant = _tune("drops", "enemy_kinds", {})
	var g2 := _game("hickston", true, true)
	_tick(g2, 2)
	var before := _scrap_count(g2)
	var hand: Enemy = null
	for e: Enemy in g2.enemies:
		if e.hostile and not BossKit.is_boss(e) and hand == null:
			hand = e
	hand.hurt(9999, g2)
	_tick(g2, 1)
	_check(_scrap_count(g2) == before + 1, "a hand killed drops a piece")
	_tune("drops", "enemy_chance", was)
	_tune("drops", "enemy_kinds", kinds)
	var g3 := _game("hickston")
	_tick(g3, 2)
	before = _scrap_count(g3)
	var props: Variant = _tune("drops", "props", {"prop_barrel": [1.0, "bolts"]})
	g3.events.prop_broken.emit("prop_barrel", g3.player.x + 1.0, g3.player.y, 0.0)
	_check(_scrap_count(g3) == before + 1, "a breakable broken drops its piece")
	_tune("drops", "props", props)
	var boss_kit: Array = BenchMods.value("drops", "boss", [])
	_check(boss_kit.size() >= 3, "a boss drops %d pieces" % boss_kit.size())
	# A vehicle wrecked, a set piece come down.
	var wrecked := false
	var downed := false
	for id: String in Campaign.ORDER:
		var g4 := _game(id)
		_tick(g4, 2)
		var rides: Game.VehiclesScript = g4.features.get("vehicles")
		if not wrecked and rides != null and not rides.rides.is_empty():
			before = _scrap_count(g4)
			rides.call("_hurt", rides.rides[0], 99999.0)
			_tick(g4, 20)
			var gave := _scrap_count(g4) - before
			var want_v: Array = BenchMods.value("drops", "vehicle", [])
			_check(gave >= want_v.size(), "%s: a vehicle wrecked drops %d pieces" % [id, gave])
			wrecked = true
		var sets: GameFeature = g4.features.get("set_pieces")
		var pieces: Array = sets.get("pieces")
		if not downed and not pieces.is_empty():
			before = _scrap_count(g4)
			sets.call("_collapse", 0)
			_tick(g4, 20)
			_check(_scrap_count(g4) > before, "%s: a set piece come down drops scrap" % id)
			downed = true
		if wrecked and downed:
			break
	_check(wrecked and downed, "a chapter with a vehicle and one with a set piece were found")


func _buy() -> void:
	var g := _game("hickston")
	_tick(g, 2)
	_arm(g, ["revolver", "shotgun"], 30)
	# Away from the bench: no buy.
	var b: Array = _bench(g).benches[0]
	g.player.x = float(b[0]) + 6.0
	_buy_one(g, "scope")
	_check(not g.armory.mods.has("scope"), "away from a bench a buy is not taken")
	_at_bench(g)
	_check(_bench(g).at_bench(g.player) >= 0, "at the bench, looking at it")
	_check(_bench(g).prompt(g.player).contains("JUNK BENCH"), "USE's prompt names it")
	g.interact()
	_check(g.bench_asked, "USE asks for the board (this machine's player)")
	BenchScreen.settle(g)
	_check(BenchScreen.open and not g.bench_asked, "the board comes up")
	var price: int = BenchMods.mod("scope")["price"]
	_buy_one(g, "scope")
	_check(
		g.armory.mods.has("scope") and g.armory.scrap == 30 - price,
		"a buy at the bench tapes the scope on for %d scrap" % price
	)
	_buy_one(g, "scope")
	_check(g.armory.scrap == 30 - price, "the same mod twice: not taken")
	_buy_one(g, "drum")
	_check(not g.armory.mods.has("drum"), "a mod for a gun not had: not taken")
	g.armory.scrap = 1
	_buy_one(g, "choke")
	_check(not g.armory.mods.has("choke"), "not enough scrap: not taken")
	_check(BenchMods.why_not(g.player, _index("choke")).begins_with("NEED"), "the board says why")
	# The board's keys: a pick queued, sent with the next controls.
	g.armory.scrap = 20
	BenchScreen.row = 1
	BenchScreen.column = 0
	BenchScreen.key(g, KEY_ENTER)
	var c := Game.Controls.new()
	BenchScreen.take_pending(c)
	g.tick(STEP, c)
	_check(g.armory.mods.has(BenchScreen.mod_at(1, 0)), "ENTER on the board buys its tag")
	var c2 := Game.Controls.new()
	c2.buy = 99
	BenchScreen.take_pending(c2)
	_check(c2.buy == -1, "one buy is sent once")
	g.player.x += 8.0
	BenchScreen.settle(g)
	_check(not BenchScreen.open, "walked off, the board shuts")
	BenchScreen.reset()


func _mods() -> void:
	var g := _game("hickston", true, true)
	_tick(g, 2)
	_arm(g, ["revolver", "shotgun", "rifle", "crossbow"], 0)
	g.armory.owned[Weapons.DYNAMITE] = true
	for e: Enemy in g.enemies:
		e.dormant = true
	var all: Array[String] = []
	for id: String in BenchMods.ids():
		all.append(id)
	all.sort()
	var none: Array[String] = []
	var arm := g.armory
	# The scope: ALT FIRE puts it up, it zooms; none without it.
	arm.active = Weapons.REVOLVER
	arm.mods = none
	var alt := Game.Controls.new()
	alt.alt_fire = true
	g.tick(STEP, alt)
	_tick(g, 1)
	_check(not g.player.scoped, ".38 bare: ALT FIRE no scope")
	arm.mods = all
	arm.cooldown = 0.0
	g.tick(STEP, alt)
	_check(
		g.player.scoped and float(arm.firing(Weapons.REVOLVER)["scope"]) > 1.5,
		"scope: ALT FIRE puts it up"
	)
	_tick(g, 1)
	g.tick(STEP, alt)
	g.player.scoped = false
	# The speed loader: the reload's time halved.
	arm.loaded[Weapons.REVOLVER] = 0
	arm.reload = 0.0
	arm.start_reload(g)
	var fast := arm.reload
	arm.reload = 0.0
	arm.mods = none
	arm.start_reload(g)
	var slow := arm.reload
	arm.reload = 0.0
	_check(fast < slow * .6, "speed loader: reloads in %.2f s, not %.2f" % [fast, slow])
	# The choke: the sawed-off's pattern tighter, further.
	var bare := Modes.shot_spread(
		g, g.player, Weapons.SHOTGUN, Weapons.FIRING[Weapons.SHOTGUN], 0.0
	)
	arm.mods = all
	var tight := Modes.shot_spread(g, g.player, Weapons.SHOTGUN, arm.firing(Weapons.SHOTGUN), 0.0)
	var bare_spread: Vector2 = bare[0]
	var tight_spread: Vector2 = tight[0]
	_check(
		tight_spread.x < bare_spread.x * .7 and float(tight[1]) > float(bare[1]),
		"pipe choke: spread %.3f, not %.3f; reach %.1f" % [tight_spread.x, bare_spread.x, tight[1]]
	)
	# The bayonet: FIRE dry jabs the hand in front, finishing one under its share.
	var hand: Enemy = null
	for e: Enemy in g.enemies:
		if e.hostile and not BossKit.is_boss(e) and e.tactical() and hand == null:
			hand = e
	var p := g.player
	hand.x = p.x + cos(p.angle) * 1.0
	hand.y = p.y + sin(p.angle) * 1.0
	hand.floor_z = g.world.elevation(hand.x, hand.y)
	hand.dormant = false
	hand.hp = hand.max_hp * .3
	arm.active = Weapons.SHOTGUN
	arm.loaded[Weapons.SHOTGUN] = 0
	arm.reserve[Weapons.SHOTGUN] = 0
	arm.switch = 0.0
	arm.cooldown = 0.0
	arm.reload = 0.0
	arm.jab_age = 9.0
	var shoot := Game.Controls.new()
	shoot.fire = true
	g.tick(STEP, shoot)
	var brawl: GameFeature = g.features.get("brawl")
	var finishing: Array = brawl.get("moves") if brawl != null else []
	_check(
		not finishing.is_empty() or not hand.alive,
		"corn knife: dry, FIRE on a low hand starts the gun's finisher (features/brawl.gd)"
	)
	_tick(g, 90)
	_check(not hand.alive, "corn knife: the finisher lands, the hand is dead")
	# A whole hand only takes the jab's damage.
	var whole: Enemy = null
	for e: Enemy in g.enemies:
		if e.alive and e.hostile and not BossKit.is_boss(e) and e.tactical() and whole == null:
			whole = e
	if whole != null:
		whole.x = p.x + cos(p.angle) * 1.0
		whole.y = p.y + sin(p.angle) * 1.0
		whole.floor_z = g.world.elevation(whole.x, whole.y)
		whole.dormant = false
		whole.hp = whole.max_hp
		arm.jab_age = 9.0
		arm.cooldown = 0.0
		var before_hp := whole.hp
		g.tick(STEP, shoot)
		_check(
			whole.alive and whole.hp < before_hp and finishing.is_empty(),
			"corn knife: a whole hand takes the jab (%.0f), no finisher" % (before_hp - whole.hp)
		)
	arm.mods = none
	arm.jab_age = 9.0
	var before_jab := arm.jab_age
	g.tick(STEP, shoot)
	_check(arm.jab_age >= before_jab, "no knife: dry FIRE is only a click")
	arm.mods = all
	# The drum: the rifle carries more, heats slower.
	arm.reserve[Weapons.RIFLE] = 200
	arm.add_ammo(Weapons.RIFLE, 100)
	_check(
		arm.reserve[Weapons.RIFLE] == 300,
		"drum mag: the rifle carries 300 (%d)" % arm.reserve[Weapons.RIFLE]
	)
	# The brake: a shot climbs less.
	var climbs := []
	for mods: Array[String] in [none, all]:
		arm.mods = mods
		arm.active = Weapons.RIFLE
		arm.cooldown = 0.0
		arm.switch = 0.0
		arm.reload = 0.0
		arm.rifle_heat = .5
		p.pitch = 0.0
		arm.fire(g)
		climbs.append(p.pitch)
	p.pitch = 0.0
	_check(
		float(climbs[1]) < float(climbs[0]) * .5,
		"coffee can brake: the climb %.2f, not %.2f" % [climbs[1], climbs[0]]
	)
	# The spring: the bolt flies faster, cocks quicker.
	var speeds := []
	for mods: Array[String] in [none, all]:
		arm.mods = mods
		arm.active = Weapons.CROSSBOW
		arm.cooldown = 0.0
		arm.switch = 0.0
		g.shots.clear()
		arm.fire(g)
		var shot: GameState.Shot = g.shots[0] if not g.shots.is_empty() else null
		speeds.append([Vector2(shot.vx, shot.vy).length() if shot != null else 0.0, arm.cooldown])
	_check(
		(
			float(speeds[1][0]) > float(speeds[0][0]) * 1.3
			and float(speeds[1][1]) < float(speeds[0][1])
		),
		(
			"truck spring: the bolt at %.1f, not %.1f; ready in %.2f s"
			% [speeds[1][0], speeds[0][0], speeds[1][1]]
		)
	)
	g.shots.clear()
	# The flame: the bolt's blast sets what it reaches alight.
	var fire: Fire = g.features["fire"]
	var spot := Vector2(p.x + cos(p.angle) * 3.0, p.y + sin(p.angle) * 3.0)
	var burned := []
	for mods: Array[String] in [none, all]:
		arm.mods = mods
		fire.burning.clear()
		fire.call("_index")
		var bolt := GameState.Shot.new(
			spot.x,
			spot.y,
			g.world.elevation(spot.x, spot.y) + .3,
			0.0,
			0.0,
			0.0,
			"bolt",
			0.0,
			false,
			0
		)
		bolt.slot = 0
		g.explode(bolt)
		burned.append(fire.burning.size())
	_check(
		int(burned[0]) == 0 and int(burned[1]) > 0,
		"flaming bolts: the blast lights %d cells (none bare)" % burned[1]
	)
	fire.burning.clear()
	fire.call("_index")
	# The long fuse.
	arm.mods = all
	arm.active = Weapons.DYNAMITE
	arm.reserve[Weapons.CROSSBOW] = 5
	arm.cooldown = 0.0
	arm.switch = 0.0
	arm.fuse = 0.0
	arm.tnt_latched = false
	arm.fire(g)
	_check(absf(arm.fuse - 4.4) < .01, "long fuse: the stick burns %.1f s" % arm.fuse)
	arm.fuse = 0.0
	arm.tnt_latched = false
	# The bundle: a bigger blast reaches a hand the plain stick does not.
	var hurt := []
	for mods: Array[String] in [none, all]:
		g = _game("hickston", true, true)
		_tick(g, 2)
		g.armory.mods = mods
		g.armory.mods_on = true
		g.bench_live = true
		p = g.player
		spot = Vector2(p.x + cos(p.angle) * 3.0, p.y + sin(p.angle) * 3.0)
		hand = null
		for e: Enemy in g.enemies:
			e.dormant = true
			if e.hp > 0 and e.hostile and not BossKit.is_boss(e) and e.tactical() and hand == null:
				hand = e
		var far := 3.2
		# Somewhere open beside the blast, in its sight, 3.2 off.
		for k in 16:
			var a := k * TAU / 16.0
			hand.x = spot.x + cos(a) * far
			hand.y = spot.y + sin(a) * far
			if (
				not g.world.blocked(hand.x, hand.y, .2)
				and g.world.visible(spot.x, spot.y, hand.x, hand.y)
			):
				break
		hand.floor_z = g.world.elevation(hand.x, hand.y)
		hand.dormant = false
		var hp := hand.hp
		var stick := GameState.Shot.new(
			spot.x,
			spot.y,
			g.world.elevation(spot.x, spot.y) + .2,
			0.0,
			0.0,
			0.0,
			"tnt",
			0.0,
			false,
			0
		)
		stick.slot = 0
		g.explode(stick)
		hurt.append(hp - hand.hp)
		hand.hp = hp
	_check(
		float(hurt[0]) <= 0.0 and float(hurt[1]) > 0.0,
		"3-stick bundle: reaches a hand %.1f off (%.0f hurt)" % [3.2, hurt[1]]
	)


func _looks() -> void:
	var art: Assets = main.art
	var missing: Array = []
	for slot in Weapons.COUNT:
		var mine: Array[String] = []
		for id: String in BenchMods.ids():
			if int(BenchMods.mod(id)["slot"]) == slot:
				mine.append(id)
		if mine.is_empty():
			continue
		var poses: Array = []
		for name: String in art.art_index:
			var prefix := "gun_%s_" % Weapons.NAMES[slot]
			if name.begins_with(prefix) and not name.substr(prefix.length()).begins_with("_"):
				poses.append(name.substr(prefix.length()))
		for pick in range(1, 1 << mine.size()):
			var chosen: Array[String] = []
			for k in mine.size():
				if pick >> k & 1:
					chosen.append(mine[k])
			chosen.sort()
			var view := BenchMods.art_name(slot, chosen)
			for pose: String in poses:
				if not art.has_art("gun_%s_%s" % [view, pose]):
					missing.append("gun_%s_%s" % [view, pose])
	_check(
		missing.is_empty(),
		(
			"every gun's every pose with every choice of its mods has its picture %s"
			% [missing.slice(0, 6)]
		)
	)
	var pictures: Array = [
		"bench_board",
		"bench_stamp",
		"bench_scrap_hud",
		"item_scrap_bolts",
		"item_scrap_wire",
		"item_scrap_hubcap"
	]
	for id: String in BenchMods.ids():
		var short := str(BenchMods.mod(id)["short"])
		pictures.append_array(
			["bench_tag_" + short, "bench_tag_%s_dim" % short, "bench_mod_%s_hud" % short]
		)
	for gun: String in BenchScreen.GUNS:
		pictures.append_array(["bench_gun_" + gun, "bench_gun_%s_bare" % gun])
	var lacking: Array = pictures.filter(func(n: String) -> bool: return not art.has_art(n))
	_check(lacking.is_empty(), "the bench's pictures are all there %s" % [lacking])
	_check(
		(
			art.has_art("town_junk_bench")
			and ResourceLoader.exists("res://assets3d/props/junk_bench.glb")
		),
		"the bench's picture and model"
	)
	# The anchors of a gun whose muzzle a mod moves (the brake's can).
	_check(
		Weapons.muzzle_anchors().has("rifle__brake"),
		"the coffee can moves the rifle's muzzle flash out to it"
	)
	# Every mod has its tag text, a fair price and a line of Mundell's to buy it with.
	var fair := true
	for id: String in BenchMods.ids():
		var m := BenchMods.mod(id)
		var price: int = m["price"]
		fair = (
			fair and price >= 2 and price <= 12 and str(m["label"]) != "" and str(m["line"]) != ""
		)
	_check(fair, "every mod has a name, a line and a price of 2 to 12")
	_check(
		BenchMods.ids().size() >= 10, "two mods for each of five guns (%d)" % BenchMods.ids().size()
	)
	var lines: Array = GameState.Barks.LINES.get("bench_buy", [])
	_check(lines.size() >= 2, "Mundell has lines for a mod bought")
	# The board drawn: its tags noted where a tap finds them.
	var g := _game("hub")
	g.in_hub = true
	_tick(g, 2)
	_arm(g, ["revolver", "shotgun"], 12)
	BenchScreen.show(g)
	var canvas := Canvas.new()
	BenchScreen.draw(canvas, g)
	var tag := Rect2i(
		BenchScreen.PANEL.position + Vector2i(BenchScreen.TAG_X[1], BenchScreen.ROW_TOP),
		BenchScreen.TAG
	)
	BenchScreen.hover(tag.get_center())
	_check(BenchScreen.row == 0 and BenchScreen.column == 1, "a tap on a tag picks it")
	BenchScreen.reset()


func _save() -> void:
	var g := _game("hickston")
	_tick(g, 2)
	_arm(g, ["revolver", "rifle"], 11)
	var picked: Array[String] = ["drum", "scope"]
	g.armory.mods = picked
	g.armory.reserve[Weapons.RIFLE] = 300
	var path := OS.get_cache_dir().path_join("bench_check_save.json")
	_check(SessionStore.save(g, path), "a save is written")
	var back := SessionStore.read(path, main.make_game, false)
	_check(
		(
			back != null
			and back.armory.scrap == 11
			and back.armory.mods == picked
			and back.armory.reserve[Weapons.RIFLE] == 300
		),
		"it loads with its scrap, its mods and the drum's rounds"
	)
	DirAccess.remove_absolute(path)
	var doc := SessionStore.snapshot(g)
	doc["version"] = 9
	var arm_doc: Dictionary = doc["armory"]
	arm_doc.erase("scrap")
	arm_doc.erase("mods")
	arm_doc["reserve"][Weapons.RIFLE] = 100
	var up: Variant = SaveUpgrade.upgrade(doc)
	var upgraded: Dictionary = up if up is Dictionary else {}
	var up_arm: Dictionary = upgraded.get("armory", {})
	_check(
		int(up_arm.get("scrap", -1)) == 0 and up_arm.get("mods", null) == [],
		"a version 9 save comes up with no scrap and no mods"
	)
	var kit := g.loadout()
	var next := _game("fair")
	next.apply_loadout(kit)
	_check(
		next.armory.scrap == 11 and next.armory.mods == picked,
		"the next chapter's kit carries them"
	)
	var old_kit := kit.duplicate()
	old_kit.erase("scrap")
	old_kit.erase("mods")
	var older := _game("fair")
	older.apply_loadout(old_kit)
	_check(
		older.armory.scrap == 0 and older.armory.mods.is_empty(),
		"a kit from before the bench: none"
	)
	var hub := _game("hub")
	hub.in_hub = true
	hub.armory.scrap = 3
	var more: Array[String] = ["drum", "loader", "scope"]
	hub.armory.mods = more
	main.bench_carry(hub, g)
	_check(
		g.armory.scrap == 3 and g.armory.mods == more,
		"out of the Crossroads the hub's buys go along"
	)


func _net() -> void:
	var g := _game("hickston")
	Modes.setup(g, Modes.COOP, 2)
	_tick(g, 2)
	var q: Player = g.players[1]
	var b: Array = _bench(g).benches[0]
	var facing: float = b[2]
	for p: Player in g.players:
		p.x = float(b[0]) + sin(facing) * 1.1 + (.3 if p == q else -.3)
		p.y = float(b[1]) + cos(facing) * 1.1
		p.angle = atan2(float(b[1]) - p.y, float(b[0]) - p.x)
		p.armory.owned[Weapons.SHOTGUN] = true
		p.armory.scrap = 20
	var c := Game.Controls.new()
	c.buy = _index("choke")
	g.tick(STEP, {1: c})
	_check(
		q.armory.mods.has("choke") and not g.players[0].armory.mods.has("choke"),
		"co-op: player two's buy is player two's own"
	)
	var to := _game("hickston")
	Modes.setup(to, Modes.COOP, 2)
	Modes.carry(q, to.players[1])
	_check(to.players[1].armory.mods.has("choke"), "Modes.carry takes a player's mods along")
	# Two games fed the same controls, a buy among them.
	var a := _game("hickston", true, true)
	var b2 := _game("hickston", true, true)
	for gg: Game in [a, b2]:
		_arm(gg, ["revolver", "shotgun"], 40)
	var pilot := Pilot.new()
	pilot.as_controls = true
	var split := -1
	for t in 60 * 25:
		var cc := pilot.steer(a)
		if t == 30:
			_at_bench(a)
			_at_bench(b2)
		if t == 31:
			cc = Game.Controls.new()
			cc.buy = _index("loader")
		a.tick(STEP, cc)
		b2.tick(STEP, cc)
		pilot.moved(a)
		if split < 0 and (t + 1) % 300 == 0:
			if not GameSnapshot.same(GameSnapshot.capture(a), GameSnapshot.capture(b2)):
				split = t + 1
	_check(a.armory.mods.has("loader"), "the controls' buy went through")
	_check(
		split < 0,
		(
			"two games fed the same controls stay identical with the bench about%s"
			% ("" if split < 0 else " (part by %d)" % split)
		)
	)
	var snap := GameSnapshot.capture(a)
	var unknown: Array = snap["unknown"]
	_check(unknown.is_empty(), "the snapshot knows the bench's classes %s" % [unknown])
	var c2 := _game("hickston", true, true)
	var applied := GameSnapshot.apply(c2, snap)
	var where := GameSnapshot.first_difference(snap, GameSnapshot.capture(c2))
	_check(
		applied and where == "" and c2.armory.mods.has("loader"),
		"a snapshot carries the mods onto a fresh game %s" % where
	)


## The scrap each chapter gives the campaign bot, and what it would buy.
func _audit() -> void:
	var total := 0
	for id: String in Campaign.ORDER:
		var g := _game(id, true, true)
		g.cheats.god = true
		var pilot := Pilot.new()
		pilot.as_controls = true
		for t in 60 * AUDIT_SECONDS:
			var c := pilot.steer(g)
			g.tick(STEP, c)
			pilot.moved(g)
		total += g.armory.scrap
		print(
			(
				"  %-12s scrap %3d   lying about %2d   kills %d"
				% [id, g.armory.scrap, _scrap_count(g), g.kills]
			)
		)
	var price := 0
	for id: String in BenchMods.ids():
		price += int(BenchMods.mod(id)["price"])
	print("  the campaign: %d scrap picked up; every mod costs %d" % [total, price])
