## The first minutes for a new player (pass 12, ONBOARD): the one-time tips
## (src/lessons.gd) and the new player's way to the first boss.
##
##   godot --headless --path godot --script res://tools/onboard_check.gd [-- quick]
##
## - Every tip comes at its moment (set up on Hickston: a hand after you, one
##   reeling, one in boot reach, a locked door, a thing to tote, the mower, the
##   junk bench, the dynamite, BLUE along and hurt, a full gut, the drink...),
##   once: set up again it never shows, nor after the profile is read again
##   from its file; nothing comes before its moment.
## - NEW PLAYER TIPS off: none, ever; nor in a tool's game (lessons off).
## - Each tip names the right key (as bound, a key moved on the KEYS page
##   too), pad button or touch button for the device last used.
## - A fresh profile's first minutes (tools/onboard_walk.gd): the fire tip
##   within FIRE_LAG seconds of the first hand after you, the walk and the
##   arrow first, no tip twice, two tips at least CALM_LEAST apart unless one
##   is urgent; the new player (a ROOKIE that only does what it was shown)
##   reaches the sheriff on NORMAL within BUDGET seconds with at most
##   MOST_DEATHS deaths (quick: skipped).
## ONBOARD CHECK OK when all hold.
extends SceneTree

const Walk := preload("res://tools/onboard_walk.gd")
const STEP := 1.0 / 60.0
## Game seconds a ROOKIE new player may take to the sheriff on NORMAL
## (measured at 227 s, seed 1).
const BUDGET := 300.0
const MOST_DEATHS := 1
## Seconds from the first hand after the player to the fire tip at most.
const FIRE_LAG := 1.5
## The least clear seconds between two tips that can wait.
const CALM_LEAST := 9.0


## What onboard_walk.gd's run() writes down as it goes (no pictures here).
class Notes:
	extends RefCounted
	var log_rows: Array = []

	func note(t: float, kind: String, text: String) -> void:
		log_rows.append([snappedf(t, .1), kind, text])

	func snap(_name: String) -> void:
		pass


var main
## The next games made are a tool's (lessons off).
var as_tool := false
var failures: Array[String] = []
var checks := 0


func _init() -> void:
	_run.call_deferred()


func check(ok: bool, what: String) -> void:
	checks += 1
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		failures.append(what)


func _run() -> void:
	main = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	var lessons_file := Lessons.file
	Lessons.file = OS.get_cache_dir().path_join("clmr-onboard-lessons.json")
	_moments()
	_off()
	_glyphs()
	_controls_page()
	_exact()
	if not OS.get_cmdline_user_args().has("quick"):
		await _first_minutes()
	Lessons.reset()
	Lessons.file = lessons_file
	main.queue_free()
	await process_frame
	print(
		"ONBOARD CHECK OK" if failures.is_empty() else "ONBOARD CHECK FAILED: %d" % failures.size()
	)
	for f: String in failures:
		print("   - ", f)
	quit(0 if failures.is_empty() else 1)


# ------------------------------------------------------------------ setups


## A Hickston game as a player plays it (tips on, BLUE and the bench along),
## every hand asleep, god mode on, the player at the start.
func _game(tips := 1, device := "keys") -> Game:
	var g: Game = main.make_game("hickston")
	var options: Dictionary = SessionStore.defaults().duplicate()
	options["hound"] = 1
	options["bench"] = 1
	options["events"] = 0
	options["tips"] = tips
	g.configure(options)
	g.lessons = not as_tool
	g.cheats.god = true
	g.barks.enabled = false
	g.input_device = device
	g.use_key = "Y" if device == "pad" else ("USE" if device == "touch" else "E")
	for e: Enemy in g.enemies:
		e.dormant = true
	main.game = g
	main.state = "play"
	return g


func _ticks(g: Game, seconds: float) -> void:
	for i in int(seconds / STEP):
		g.tick(STEP, Game.Controls.new())


## Ticks until a tip shows, six seconds at most (a notice up holds back the
## tips that are not urgent: the mower's own notice is up for four).
func _until_tip(g: Game) -> void:
	for i in int(6.0 / STEP):
		if g.tip != "":
			return
		g.tick(STEP, Game.Controls.new())


## Everything taught but `id`, so only it can show.
func _only(id: String) -> void:
	Lessons.forget()
	for other: String in Lessons.ORDER:
		if other != id:
			Lessons.taught[other] = true


## Stands the player `back` cells from (x, y), facing it, on open floor;
## false when no side is open.
func _face(g: Game, x: float, y: float, back: float) -> bool:
	var p := g.player
	for k in 8:
		var a := k * TAU / 8.0
		var px := x + cos(a) * back
		var py := y + sin(a) * back
		if g.world.blocked(px, py, GameState.PLAYER_RADIUS):
			continue
		p.x = px
		p.y = py
		p.angle = a + PI
		p.pitch = 0.0
		p.floor_z = g.world.floor_under(px, py, 9.0)
		p.eye = p.floor_z + .95
		if g.world.visible(px, py, x, y):
			return true
	return false


## The nearest hand to the player woken, after them, `d` cells in front.
func _hand_in_front(g: Game, d: float) -> Enemy:
	var p := g.player
	var best: Enemy = null
	for e: Enemy in g.enemies:
		if e.hp > 0.0 and e.kind == "billy":
			best = e
			break
	var a := p.view_angle()
	best.x = p.x + cos(a) * d
	best.y = p.y + sin(a) * d
	best.dormant = false
	best.alerted = true
	best.player_seen = true
	return best


## Sets `id`'s moment up on a fresh game; returns the game (null: could not).
func _set_up(id: String, device := "keys", tips := 1) -> Game:
	var g := _game(tips, device)
	var p := g.player
	_ticks(g, .2)
	g.message_until = 0.0  # the chapter's opening notice: tips that can wait wait it out
	match id:
		"fire":
			_hand_in_front(g, 5.0)
		"move":
			_ticks(g, 1.5)
		"map":
			_ticks(g, 7.0)
		"finish":
			var e := _hand_in_front(g, 2.5)
			e.hp = e.max_hp * .1
		"kick":
			_hand_in_front(g, 1.2)
		"locked":
			for door: LevelData.Door in g.world.doors:
				if door.key == "" or door.opened:
					continue
				var c := door.center()
				for back: float in [1.0, 1.2, .9]:
					if _face(g, c.x, c.y, back) and g.use_prompt().ends_with("KEY NEEDED"):
						return g
			return null
		"heal":
			p.health = 40
			g.inventory["rinds"] = 1
		"ride":
			var rides: Game.VehiclesScript = g.features.get("vehicles")
			for v: VehicleDrive.Ride in rides.rides:
				for back: float in [1.1, 1.4, 1.8]:
					if _face(g, v.x, v.y, back) and rides.prompt(p).find("DRIVE THE ") >= 0:
						return g
			return null
		"carry":
			var carry: Game.CarryScript = g.features.get("carry")
			for t: Variant in carry.things:
				var at := carry.place_of(t)
				for back: float in [.9, 1.1]:
					if _face(g, at.x, at.y, back):
						p.pitch = -20.0
						if carry.target() >= 0 and g.use_prompt().find("PICK UP ") >= 0:
							return g
			return null
		"bench":
			var bench: Game.BenchScript = g.features.get("bench")
			_ticks(g, .5)
			for b: Array in bench.benches:
				if _face(g, float(b[0]), float(b[1]), 1.2) and bench.prompt(p) != "":
					return g
			return null
		"tnt":
			g.armory.owned[Weapons.DYNAMITE] = true
			g.armory.reserve[Weapons.CROSSBOW] = 3
			g.armory.select(Weapons.DYNAMITE, g)
		"hound":
			_ticks(g, 15.0)
		"guns":
			for slot: int in [Weapons.SHOTGUN, Weapons.RIFLE]:
				g.armory.owned[slot] = true
		"pockets":
			g.inventory["beer"] = 1
		"scrap":
			g.armory.scrap = 1
		"hound_hurt":
			var hound: Game.HoundScript = g.features.get("hound")
			var dog: Game.HoundScript.Dog = hound.dog_of(p)
			dog.health = 50.0
		"badge":
			_ticks(g, 76.0)
		"gut":
			p.gut = 70.0
		"drunk":
			p.drunk = 40.0
		"lead":
			# BLUE leading the way (pass 15): his job set as HoundLead sets it.
			var hound: Game.HoundScript = g.features.get("hound")
			var dog: Game.HoundScript.Dog = hound.dog_of(p)
			dog.job = Game.HoundScript.LEAD
	return g


# ------------------------------------------------------------------ checks


## Each tip at its moment, once, and not before it.
func _moments() -> void:
	print("EACH TIP AT ITS MOMENT, ONCE")
	for id: String in Lessons.ORDER:
		# Before its moment: a game left standing shows nothing (the walk, the
		# arrow and BLUE come with time, and the start has a rind in the pocket).
		if not ["move", "map", "hound", "badge", "pockets"].has(id):
			_only(id)
			var calm := _game()
			_ticks(calm, 3.0)
			check(calm.tip == "", "%s: nothing before its moment" % id)
		_only(id)
		var g := _set_up(id)
		if g == null:
			check(false, "%s: its moment could be set up on Hickston" % id)
			continue
		_until_tip(g)
		var shown := g.tip == Lessons.words(g, id) and g.tip_until > g.clock
		check(shown and Lessons.last_id == id, "%s: shown at its moment (%s)" % [id, g.tip])
		# Never again: the same moment set up again, and after the profile is
		# read again from its file.
		var again := _set_up(id)
		_until_tip(again)
		check(again.tip == "", "%s: not shown a second time" % id)
		Lessons._loaded = false
		Lessons.taught = {}
		var reread := _set_up(id)
		_until_tip(reread)
		check(reread.tip == "" and Lessons.taught.has(id), "%s: kept on the profile" % id)


## NEW PLAYER TIPS off, and a tool's game (lessons off): none.
func _off() -> void:
	print("TIPS OFF")
	for id: String in ["fire", "carry", "move"]:
		Lessons.forget()
		var g := _set_up(id, "keys", 0)
		_ticks(g, 3.0)
		check(g.tip == "" and Lessons.taught.is_empty(), "%s: none with NEW PLAYER TIPS off" % id)
		Lessons.forget()
		as_tool = true
		var tool := _set_up(id)
		as_tool = false
		_ticks(tool, 3.0)
		check(tool.tip == "" and Lessons.taught.is_empty(), "%s: none in a tool's game" % id)
	var row: SessionStore.Setting = null
	for page: Array in SessionStore.setup_pages():
		for s: SessionStore.Setting in page[1]:
			if s.key == "tips":
				row = s
	check(row != null and SessionStore.defaults()["tips"] == 1, "NEW PLAYER TIPS is a setting, on")


## Each device's words: keys as bound, the pad's and the touch buttons.
func _glyphs() -> void:
	print("THE RIGHT KEY OR BUTTON")
	var want := {
		"keys":
		"LOOSE JUNK CAN BE TOTED: E PICKS IT UP, LEFT CLICK CHUCKS IT, RIGHT CLICK SETS IT DOWN.",
		"pad": "LOOSE JUNK CAN BE TOTED: Y PICKS IT UP, RT CHUCKS IT, LT SETS IT DOWN.",
		"touch": "LOOSE JUNK CAN BE TOTED: USE PICKS IT UP, FIRE CHUCKS IT, ALT SETS IT DOWN.",
	}
	for device: String in want:
		_only("carry")
		var g := _set_up("carry", device)
		_ticks(g, .5)
		check(g.tip == want[device], "%s: %s" % [device, g.tip])
	var g2 := _game()
	var fire := {
		"keys": "LEFT CLICK SHOOTS, R RELOADS. RIGHT CLICK IS THE GUN'S OTHER FIRE.",
		"pad": "RT SHOOTS, X RELOADS. LT IS THE GUN'S OTHER FIRE.",
	}
	for device: String in fire:
		g2.input_device = device
		check(Lessons.words(g2, "fire") == fire[device], "%s fire: %s" % [device, fire[device]])
	g2.input_device = "pad"
	check(
		Lessons.words(g2, "hound").begins_with("THAT'S BLUE, YER HOUND. HOLD BACK"), "pad whistle"
	)
	g2.input_device = "touch"
	check(Lessons.words(g2, "hound").find("TAP HIS BADGE") >= 0, "touch whistle")
	check(Lessons.words(g2, "move") == "LEFT THUMB WALKS, RIGHT THUMB AIMS.", "touch walk")
	# A key moved on the KEYS page is the key named.
	var opts: Dictionary = main.options
	var was: Variant = opts.get(KeyBindings.option_key("use"), KEY_E)
	KeyBindings.bind(opts, "use", KEY_T)
	KeyBindings.register(opts)
	g2.input_device = "keys"
	check(Lessons.words(g2, "kick").begins_with("UP CLOSE, T PUTS"), "a moved USE key: T")
	KeyBindings.bind(opts, "use", int(was))
	KeyBindings.register(opts)
	check(Lessons.words(g2, "kick").begins_with("UP CLOSE, E PUTS"), "and back to E")


## The CONTROLS page names the keys as bound and says USE totes and boots.
func _controls_page() -> void:
	print("HOW TO RAISE HELL")
	var rows: Array = ControlsScreen.rows_of(0)
	check(str(rows[0][0]) == "WASD / MOUSE", "the walk keys as bound: %s" % rows[0][0])
	var text := JSON.stringify(rows)
	check(text.find("TOTE") >= 0 and text.find("BOOT") >= 0, "USE totes and boots")
	check(text.find("{") < 0, "every key filled in")
	for page in MainState.CONTROL_PAGES.size():
		for row: Array in ControlsScreen.rows_of(page):
			var left := PixelType.text_width(str(row[0]), "menu")
			var right := PixelType.text_width(str(row[1]), "menu")
			check(
				left <= 108 and right <= 162, "page %d row fits: %s / %s" % [page, row[0], row[1]]
			)


## Tips only look: the same controls with tips on and off (and in a tool's
## game) play the same game.
func _exact() -> void:
	print("PLAY THE SAME WITH TIPS ON AND OFF")
	var hashes: Array = []
	for mode in 3:
		Lessons.forget()
		as_tool = mode == 2
		var g := _game(1 if mode == 0 else 0)
		as_tool = false
		for e: Enemy in g.enemies:
			e.dormant = false
		g.rng = GameState.Rng.new(77)
		var pilot: RefCounted = load("res://tools/bot_pilot.gd").new()
		pilot.set("as_controls", true)
		var shown := 0
		for i in int(60.0 / STEP):
			g.tick(STEP, pilot.call("steer", g))
			pilot.call("moved", g)
			if g.tip_until > g.clock and g.tip != "" and i % 30 == 0:
				shown += 1
		hashes.append(Replay.state_hash(g))
		if mode == 0:
			check(shown > 0, "tips shown in the minute with them on")
	check(hashes[0] == hashes[1] and hashes[1] == hashes[2], "the same game: %s" % str(hashes))


## A fresh profile's first minutes, played by the new player.
func _first_minutes() -> void:
	print("A NEW PLAYER'S FIRST MINUTES")
	var walker := Notes.new()
	var result: Dictionary = await Walk.run(
		main, {"secs": BUDGET + 60.0, "diff": 1, "skill": 0, "seed": 1, "tips": 1}, walker
	)
	var tips: Array = result["tips"]
	var ids: Array = tips.map(func(row: Array) -> String: return str(row[1]))
	print("    ", JSON.stringify(tips))
	print("    sheriff at %.1f s, deaths %d" % [float(result["boss_at"]), int(result["deaths"])])
	var boss_at: float = result["boss_at"]
	check(boss_at > 0.0 and boss_at <= BUDGET, "the sheriff reached within %d s" % BUDGET)
	check(int(result["deaths"]) <= MOST_DEATHS, "at most %d deaths on the way" % MOST_DEATHS)
	var unique := {}
	for id: String in ids:
		unique[id] = true
	check(unique.size() == ids.size(), "no tip twice")
	check(
		ids.slice(0, 3).has("move") and ids.slice(0, 3).has("fire"), "the walk and the fire first"
	)
	var fight: float = -1.0
	for row: Array in walker.log_rows:
		if str(row[1]) == "fight" and fight < 0.0:
			fight = float(row[0])
	var fire_at := -1.0
	for row: Array in tips:
		if str(row[1]) == "fire":
			fire_at = float(row[0])
	check(fire_at >= 0.0 and fire_at - fight <= FIRE_LAG, "the fire tip with the first fight")
	var last_end := -99.0
	var spaced := true
	for row: Array in tips:
		if Lessons.CALM.has(str(row[1])) and float(row[0]) - last_end < CALM_LEAST:
			spaced = false
		last_end = float(row[0]) + Lessons.SHOW
	check(spaced, "tips that can wait keep %d s clear" % CALM_LEAST)
