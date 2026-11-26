## The fight-rhythm director (pass 15, features/director.gd) and the drops
## that lean to what the player is short of (src/drop_need.gd):
##
## - in every chapter it holds hands back, and never one a trigger, a partner
##   pair, the wave, a patrol, a boss, the tough guy or anything else in the
##   level's file names, nor one at the start;
## - played by the balance bot, the beats go build -> peak -> breather: every
##   peak a group, every breather its full length with no hand sent;
## - the same seed plays to the same state (and the director's with it);
## - a snapshot put on another game of the level carries it, and both play on
##   alike; a save through its JSON keeps it; an older save holds nothing and
##   brings a lighter sponge's health down to its kind's;
## - co-op: it runs, comes for the party and leaves the local player acting;
## - off in deathmatch, team deathmatch, County Run, the hub, the range, a
##   rematch and a chapter revisited;
## - a drop gives an empty gun's rounds or food to a hurt player, and its own
##   while that is any use; County Run drops as before.
##
##   godot --headless --path godot --script res://tools/director_check.gd
##
## Prints DIRECTOR CHECK OK (check_all runs it).
extends SceneTree

const Pilot := preload("res://tools/balance_pilot.gd")
const STEP := 1.0 / 60.0

var main
var failures: Array = []


func _init() -> void:
	_run.call_deferred()


func check(condition: bool, text: String) -> void:
	if condition:
		print("  ok   ", text)
	else:
		print("  FAIL ", text)
		failures.append(text)


func _run() -> void:
	main = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	_named()
	_beats()
	_same()
	_carried()
	_saved()
	_coop()
	_off()
	_drops()
	main.queue_free()
	await process_frame
	if failures.is_empty():
		print("DIRECTOR CHECK OK")
	else:
		print("DIRECTOR CHECK FAILED: %d" % failures.size())
		for f: String in failures:
			print("   - ", f)
	quit(0 if failures.is_empty() else 1)


func _made(id: String, diff := 1) -> Game:
	var g: Game = main.make_game(id)
	g.configure({"difficulty": diff, "events": 0})
	g.lessons = false
	for done: String in Campaign.ORDER.slice(0, maxi(0, Campaign.ORDER.find(id))):
		g.history.append([done, 1, 2, 0, 1, 60])
	return g


func _ticks(g: Game, n: int) -> void:
	for i in n:
		g.tick(STEP, Game.Controls.new())


func _dir(g: Game) -> Director:
	return g.features.get("director")


## Every string in the level's file outside its enemies.
func _file_names(id: String) -> Dictionary:
	var text := FileAccess.get_file_as_string("res://data/%s.json" % id)
	var doc: Variant = JSON.parse_string(text)
	var out := {}
	if doc is Dictionary:
		var d: Dictionary = doc
		for key: String in d:
			if key != "enemies":
				_strings(d[key], out)
	return out


func _strings(v: Variant, out: Dictionary) -> void:
	if v is Dictionary:
		var d: Dictionary = v
		for key: Variant in d:
			_strings(d[key], out)
	elif v is Array:
		for x: Variant in v:
			_strings(x, out)
	elif v is String:
		out[v] = true


func _named() -> void:
	print("\nWHAT IT HOLDS (every chapter, NORMAL)")
	for id: String in Campaign.ORDER:
		var g := _made(id)
		var held_before := {}
		for i in g.enemies.size():
			if g.enemies[i].dormant:
				held_before[i] = true
		_ticks(g, 1)
		var d := _dir(g)
		check(d != null and d.on, "%s: the director runs" % id)
		if d == null:
			continue
		var names := _file_names(id)
		var named := DirectorBeats.named(g)
		var start := Vector2(float(g.level.spawn[0]), float(g.level.spawn[1]))
		var bad: Array = []
		var extras := 0
		for index: int in d.held:
			var e: Enemy = g.enemies[index]
			if not e.dormant:
				bad.append("%d awake" % index)
			if index >= g.enemy_ids.size():
				extras += 1
				continue
			var eid := str(g.enemy_ids[index])
			if names.has(eid) or named.has(index) or held_before.has(index):
				bad.append(eid)
			if BossKit.is_boss(e) or Enemy.DEFS[e.kind].has("tough_title") or not e.hostile:
				bad.append(eid + " (" + e.kind + ")")
			if Vector2(e.x, e.y).distance_to(start) < DirectorData.num("start_clear"):
				bad.append(eid + " at the start")
		check(
			d.held.size() >= 5,
			"%s: holds %d hands back (%d of them extra)" % [id, d.held.size(), extras]
		)
		check(bad.is_empty(), "%s: none it holds is named or at the start %s" % [id, str(bad)])
		# What a trigger holds is still the trigger's: dormant, and not the director's.
		var waits := Triggers.held_back(g.level)
		var woke: Array = []
		for i in g.enemy_ids.size():
			if waits.has(str(g.enemy_ids[i])) and not g.enemies[i].dormant:
				woke.append(g.enemy_ids[i])
		check(woke.is_empty(), "%s: the triggers' own hands still wait for them" % id)


## The balance bot plays Hickston (REGULAR, seed 1) a while; the beats.
func _beats() -> void:
	print("\nTHE BEATS (Hickston and the Fair, the REGULAR bot)")
	for id: String in ["hickston", "fair"]:
		var g := _made(id)
		g.rng = GameState.Rng.new(1009 + 31 * Campaign.ORDER.find(id))
		var pilot := Pilot.new(1, 14)
		var d: Director = null
		var phases: Array = []
		var signalled: Array = []
		g.events.pace_changed.connect(
			func(phase: String, _i: float) -> void: signalled.append(phase)
		)
		var peaks := 0
		var sizes: Array = []
		var was := Director.CALM
		var breather_from := -1.0
		var held_at := 0
		var sent_in_breather := 0
		var short_breathers := 0
		var bad_intensity := 0
		var answered := 0
		var t := 0
		while g.clock < 240.0 and not g.won and g.player.health > 0:
			var c := pilot.steer(g)
			g.tick(STEP, c)
			pilot.moved(g)
			t += 1
			if d == null:
				d = _dir(g)
			var phase := d.phase
			if (
				d.intensity < 0.0
				or d.intensity > 1.0
				or (phase == Director.PEAK and d.intensity < .7)
			):
				bad_intensity += 1
			if phase != was:
				phases.append(phase)
				if phase == Director.PEAK:
					peaks += 1
					# (A station's or a key's peak may be one hand.)
					var lone_ok := d.peak_why == "station" or d.peak_why == "key"
					sizes.append(d.peak_size if not lone_ok else maxi(2, d.peak_size))
				if phase == Director.BREATHER:
					breather_from = g.clock
					held_at = d.held.size()
					answered = d.answered.size()
				if was == Director.BREATHER:
					var length := g.clock - breather_from
					if length < DirectorData.at("breather_for", 1) - .3:
						short_breathers += 1
				was = phase
			if phase == Director.BREATHER and d.answered.size() == answered:
				# (A peak's straggler gone back to the held ones adds one.)
				sent_in_breather += maxi(0, held_at - d.held.size())
				held_at = d.held.size()
		# (Pass 15 PUNCH: the stagger changed this seed's fights and Hickston's
		# second peak fell past 240 s; over six campaigns of flow_report
		# Hickston had 1.0 peaks an attempt before it and 1.7 after, the
		# Fair 2.8 and 3.2: Hickston needs one here, the Fair two.)
		var least := 1 if id == "hickston" else 2
		check(peaks >= least, "%s: %d peaks in %.0f s %s" % [id, peaks, g.clock, str(sizes)])
		var groups := true
		for n: int in sizes:
			groups = groups and n >= 2
		check(
			groups, "%s: every peak is a group (two or more; a station's or key's may be one)" % id
		)
		var follows := true
		for i in phases.size():
			if phases[i] == Director.PEAK and i + 1 < phases.size():
				follows = follows and phases[i + 1] == Director.BREATHER
		check(follows, "%s: every peak is followed by a breather %s" % [id, str(phases)])
		check(short_breathers == 0, "%s: every breather runs its length" % id)
		check(sent_in_breather == 0, "%s: no hand sent in a breather" % id)
		check(bad_intensity == 0, "%s: intensity in 0..1, a peak's .7 or more" % id)
		check(signalled == phases, "%s: pace_changed says each move" % id)


## A short run: the bot on Hickston with seed `seed_value`, `secs` seconds.
func _play(id: String, seed_value: int, secs: float) -> Game:
	var g := _made(id)
	g.rng = GameState.Rng.new(seed_value)
	var pilot := Pilot.new(1, seed_value)
	while g.clock < secs and g.player.health > 0:
		var c := pilot.steer(g)
		g.tick(STEP, c)
		pilot.moved(g)
	return g


func _same() -> void:
	print("\nTHE SAME EVERY TIME")
	var a := _play("hickston", 7, 75.0)
	var b := _play("hickston", 7, 75.0)
	var same := GameSnapshot.same(GameSnapshot.capture(a), GameSnapshot.capture(b))
	check(same, "two plays of one seed end alike")
	check(
		_dir(a).held == _dir(b).held and _dir(a).phase == _dir(b).phase,
		"and the director with them (%d held, %s)" % [_dir(a).held.size(), _dir(a).phase]
	)


## A game run until a peak is under way (or `most` seconds).
func _to_peak(id: String, most := 150.0) -> Game:
	var g := _made(id)
	g.rng = GameState.Rng.new(31)
	g.cheats.god = true
	var pilot := Pilot.new(1, 3)
	while g.clock < most:
		var c := pilot.steer(g)
		g.tick(STEP, c)
		pilot.moved(g)
		var d := _dir(g)
		if d != null and d.phase == Director.PEAK and g.clock - d.peak_began > 1.0:
			break
	return g


func _carried() -> void:
	print("\nCARRIED ONLINE (a snapshot mid-peak)")
	var a := _to_peak("hickston")
	check(_dir(a).phase == Director.PEAK, "a peak is under way at %.0f s" % a.clock)
	var b: Game = main.make_game("hickston")
	b.configure({"difficulty": 1, "events": 0})
	b.lessons = false
	b.cheats.god = true
	var snap := GameSnapshot.capture(a)
	check(GameSnapshot.apply(b, snap), "the snapshot goes on another game")
	check(GameSnapshot.same(snap, GameSnapshot.capture(b)), "and they are the same")
	var da := _dir(a)
	var db := _dir(b)
	check(
		db.on and db.held == da.held and db.peak == da.peak and db.phase == da.phase,
		"the director's beats came with it"
	)
	for i in 240:
		a.tick(STEP, Game.Controls.new())
		b.tick(STEP, Game.Controls.new())
	check(
		GameSnapshot.same(GameSnapshot.capture(a), GameSnapshot.capture(b)),
		"both play on alike for 4 s"
	)


func _through_file(g: Game) -> Game:
	var text := JSON.stringify(SessionStore.snapshot(g))
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return null
	var doc: Dictionary = parsed
	return SessionStore.restore(doc, main.make_game)


func _saved() -> void:
	print("\nSAVED (through the file)")
	var g := _to_peak("fair")
	var d := _dir(g)
	var back := _through_file(g)
	check(back != null, "a save mid-peak loads")
	if back != null:
		var e := _dir(back)
		check(
			e.on and e.held == d.held and e.peak == d.peak and e.phase == d.phase,
			"the beats come back (%d held, %s)" % [e.held.size(), e.phase]
		)
		var dormant_same := true
		for i in mini(g.enemies.size(), back.enemies.size()):
			dormant_same = dormant_same and g.enemies[i].dormant == back.enemies[i].dormant
		check(
			dormant_same and back.enemies.size() == g.enemies.size(),
			"every hand as it was (the extras too: %d)" % g.enemies.size()
		)
	# A save from before the director: nothing held, and a lighter sponge's
	# health brought to its kind's.
	DirectorData.ON = false
	var old := _made("mothership")
	_ticks(old, 30)
	var guard: Enemy = null
	for x: Enemy in old.enemies:
		if x.kind == "tin_guard" and x.alive:
			guard = x
			break
	if guard != null:
		guard.hp = 185.0
	DirectorData.ON = true
	var text := JSON.stringify(SessionStore.snapshot(old))
	var parsed: Variant = JSON.parse_string(text)
	var doc: Dictionary = parsed
	var features: Dictionary = doc.get("features", {})
	features.erase("director")
	var loaded: Game = SessionStore.restore(doc, main.make_game)
	check(loaded != null, "an older save (no director in it) loads")
	if loaded != null:
		_ticks(loaded, 30)
		var od := _dir(loaded)
		check(not od.on and od.held.is_empty(), "and the director holds nothing in it")
		var over := 0
		for x: Enemy in loaded.enemies:
			if x.hp > x.max_hp and not BossKit.is_boss(x):
				over += 1
		check(guard != null and over == 0, "a tin guard saved at 185 comes back at its 130")
	# Saved before the chapter's first tick: it starts as a new chapter.
	var fresh := _made("quarry")
	var back2 := _through_file(fresh)
	if back2 != null:
		_ticks(back2, 2)
		check(
			_dir(back2).on and not _dir(back2).held.is_empty(),
			"a save from a chapter's start plays with it"
		)


func _coop() -> void:
	print("\nCO-OP")
	var g := _made("hickston")
	Modes.setup(g, Modes.COOP, 2)
	g.cheats.god = true
	_ticks(g, 2)
	var d := _dir(g)
	check(d.on and not d.held.is_empty(), "it runs in co-op and holds hands back")
	_ticks(g, roundi(DirectorData.num("first_peak") / STEP) + 30)
	d.pending = ["station", g.clock]
	d.build_from = g.clock - 60.0
	var before := d.held.size()
	var n := 0
	while d.peaks_done == 0 and n < 30:
		_ticks(g, 1)
		n += 1
	check(d.peaks_done >= 1 and d.held.size() < before, "a station brings a peak for the party")
	# A tick on, each is still where it was put: a held hand owed no time
	# (its level of detail starts afresh; it once crossed half the map in a step).
	_ticks(g, 2)
	var far: Array = DirectorData.value("peak_spot", [8.0, 15.0])
	var most: float = far[1]
	var strays := 0
	for i: int in d.peak:
		var e: Enemy = g.enemies[i]
		var lead := g.players[0]
		if Vector2(e.x - lead.x, e.y - lead.y).length() > most + 1.5:
			strays += 1
	check(strays == 0, "its hands are where they were put a tick later")
	check(g.player == g.local_player, "the local player is left acting")
	var seen := 0
	for i: int in d.peak:
		if DirectorBeats.seen(g, g.enemies[i]) and g.clock - d.peak_began < .3:
			seen += 1
	check(seen == 0, "its hands came in out of both players' sight")


func _off() -> void:
	print("\nOFF WHERE IT DOES NOT BELONG")
	var cases := [
		["hickston", Modes.DEATHMATCH, 2],
		["hickston", Modes.TEAM, 2],
		["county_hickston", Modes.COUNTY, 1],
		["hub", "", 1],
		["range", "", 1],
	]
	for row: Array in cases:
		var g: Game = main.make_game(str(row[0]))
		g.configure({"difficulty": 1, "events": 0})
		if str(row[1]) != "":
			Modes.setup(g, str(row[1]), int(row[2]))
		_ticks(g, 3)
		var d := _dir(g)
		check(d == null or not d.on, "off in %s %s" % [row[0], row[1]])
	var rematch := BossRematch.build(main.make_game, "foreman")
	if rematch != null:
		_ticks(rematch, 3)
		check(not _dir(rematch).on, "off in a boss rematch")
	var again := _made("sawmill")
	again.revisiting = true
	_ticks(again, 3)
	check(not _dir(again).on, "off in a chapter revisited")
	DirectorData.ON = false
	var tool := _made("sawmill")
	_ticks(tool, 3)
	DirectorData.ON = true
	check(not _dir(tool).on, "off when a tool turns it off (DirectorData.ON)")


func _drops() -> void:
	print("\nDROPS BY NEED")
	var g := _made("hickston")
	_ticks(g, 2)
	var a := g.armory
	for slot in Weapons.COUNT:
		a.owned[slot] = (
			slot == Weapons.CROWBAR or slot == Weapons.REVOLVER or slot == Weapons.SHOTGUN
		)
	a.loaded[Weapons.REVOLVER] = 0
	a.reserve[Weapons.REVOLVER] = 0
	a.loaded[Weapons.SHOTGUN] = Weapons.CAPACITY[Weapons.SHOTGUN]
	a.reserve[Weapons.SHOTGUN] = roundi(a.num(Weapons.SHOTGUN, "max_reserve"))
	g.player.health = 100
	check(
		DropNeed.pick(g, "shells", .1) == "bullets",
		"full shells, an empty .38: a shell drop is bullets"
	)
	check(DropNeed.pick(g, "shells", .95) == "shells", "past need_share it is the kind's own")
	check(DropNeed.pick(g, "bullets", .1) == "bullets", "a drop of what is short stays")
	a.reserve[Weapons.REVOLVER] = roundi(a.num(Weapons.REVOLVER, "max_reserve"))
	a.loaded[Weapons.REVOLVER] = Weapons.CAPACITY[Weapons.REVOLVER]
	check(DropNeed.pick(g, "shells", .1) == "shells", "wanting for nothing: the kind's own")
	g.player.health = 30
	check(DropNeed.pick(g, "shells", .1) == "rinds", "hurt under need_health: food")
	g.player.health = 100
	# An always-drop through enemy_down: a boilerback's pressure rounds (no cow
	# launcher) are bullets for an empty .38, by the uid's roll.
	a.loaded[Weapons.REVOLVER] = 0
	a.reserve[Weapons.REVOLVER] = 0
	var e := Enemy.new("boilerback", g.player.x + 3.0, g.player.y)
	e.uid = 1
	while DropNeed.even(e.uid) >= .5:
		e.uid += 1
	g.enemies.append(e)
	e.hp = 0.0
	var count := g.pickups.size()
	g.enemy_down(e)
	var last: Array = g.pickups[g.pickups.size() - 1] if g.pickups.size() > count else []
	check(
		not last.is_empty() and str(last[0]) == "bullets",
		(
			"a boilerback's drop to a player with an empty .38: %s"
			% (str(last[0]) if not last.is_empty() else "none")
		)
	)
	var c: Game = main.make_game("county_hickston")
	Modes.setup(c, Modes.COUNTY, 1)
	_ticks(c, 2)
	check(DropNeed.pick(c, "shells", .1) == "shells", "County Run drops as before")
