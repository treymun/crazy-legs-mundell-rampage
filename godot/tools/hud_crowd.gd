## Crowded moments for the HUD's layout (src/ui/hud/hud_layout.gd): each sets
## a game up with as much over the view at once as play can put there (a
## long notice, a caption, a prompt, a streak's call, BLUE's badge, the
## flashlight, the driving plates, the kill feed, the boss bar, a mode's
## lines...). tools/hud_layout_check.gd measures them headless;
## tools/hud_frames.gd pictures them in a window.
extends RefCounted

const STEP := 1.0 / 60.0
const NOTICE := "THE KING'S BOYS SEEN YOU TAKE HIS BOAT! RUN THE CHANNEL. LAGOON OR BUST, BOY!"
const CAPTION := "DUB ON THE RADIO: FOLKS, IF YOU SEE A FELLA IN OVERALLS WITH A SHOTGUN, WAVE."
const NAMES := ["MUNDELL", "BUBBA", "CLETUS", "EARLENE"]

## Every moment: [name, what it must show (piece names)].
const MOMENTS := [
	["campaign", ["notice", "caption", "prompt", "badge", "light", "callout", "item", "hurt"]],
	["campaign_small", ["notice", "caption", "prompt", "badge", "light", "item"]],
	["campaign_minimal", ["notice", "caption", "prompt", "badge"]],
	# The touch buttons take a good share of the view: the caption may wait.
	["campaign_touch", ["notice", "prompt", "badge", "light"]],
	# The feed gives way to the caption when there is no room for both.
	["drive", ["notice", "caption", "prompt", "badge", "drive", "run"]],
	["drive_minimal", ["notice", "drive", "run", "feed", "badge"]],
	["lap", ["notice", "drive", "lap", "caption"]],
	["coop_watch", ["notice", "watching", "feed", "caption"]],
	["coop_revive", ["notice", "revive", "badge", "prompt", "caption"]],
	["boss", ["notice", "boss", "caption", "callout"]],
	["versus", ["notice", "frags", "feed", "caption"]],
	["fair", ["notice", "card", "caption"]],
	["county", ["notice", "county", "caption"]],
	["tactical", ["notice", "strip", "cash", "caption"]],
]


## Sets moment `name` up on `main` (a Main) and returns its game.
static func make(main: Node, name: String) -> Game:
	PixelType.clear_small = name.ends_with("_small")
	main.hud.minimal = name.ends_with("_minimal")
	# The touch buttons over the view (main_state.gd _pin_hud).
	main.touch.showing = name.ends_with("_touch")
	if main.touch.showing:
		main.touch.layout(main.viewport_rect(), true)
	var g: Game
	match name:
		"campaign", "campaign_small", "campaign_minimal", "campaign_touch":
			g = _campaign(main)
		"drive", "drive_minimal":
			g = _drive(main)
		"lap":
			g = _lap(main)
		"coop_watch":
			g = _coop(main, true)
		"coop_revive":
			g = _coop(main, false)
		"boss":
			g = _boss(main)
		"versus":
			g = _versus(main)
		"fair":
			g = _fair(main)
		"county":
			g = _county(main)
		"tactical":
			g = _tactical(main)
	if g == null:
		return null
	g.hud.minimal = main.hud.minimal
	_talk(g)
	return g


## The words over everything: a long notice and a caption.
static func _talk(g: Game) -> void:
	g.hints = true
	g.notice = NOTICE
	g.message_until = g.clock + 30.0
	g.voice_captions = true
	g.caption = CAPTION
	g.caption_until = g.clock + 30.0


static func _ticks(g: Game, n: int) -> void:
	for i in n:
		g.tick(STEP, Game.Controls.new())


static func _start(main: Node, level: String) -> Game:
	var g: Game = main.make_game(level)
	main.game = g
	main.state = "play"
	var options := SessionStore.defaults()
	options["hound"] = 1
	options["events"] = 2
	g.configure(options)
	g.cheats.god = true
	g.lessons = false
	g.barks.enabled = false
	g.spawn_grace = 99.0
	for e: Enemy in g.enemies:
		e.dormant = true
	return g


## Beside ride `i` of the level, looking at it (USE's prompt to get in).
static func _beside(g: Game, i := 0) -> void:
	var rides = g.features["vehicles"]
	var v: VehicleDrive.Ride = rides.rides[i]
	var s := VehicleDrive.spec(v.kind)
	for turn: float in [0.0, PI, PI * .5, -PI * .5]:
		var a := v.h + PI * .5 + turn
		var far := s.width * .5 + .5
		var x := v.x + cos(a) * far
		var y := v.y + sin(a) * far
		if g.world.blocked(x, y, .3):
			continue
		var p := g.player
		p.x = x
		p.y = y
		p.angle = a + PI
		p.floor_z = g.world.floor_under(x, y, v.z + 1.5)
		p.eye = .95 + p.floor_z
		if rides.prompt(p) != "":
			return


static func _campaign(main: Node) -> Game:
	var g := _start(main, "hickston")
	_ticks(g, 20)
	var ev = g.features["events"]
	ev.begin("blackout")
	_ticks(g, 30)
	_beside(g)
	_ticks(g, 2)
	g.callout = "HAT TRICK!"
	g.callout_until = g.clock + 1.0
	g.item_feedback = ["beer", "", g.clock + 1.0]
	g.damage_feedback = [g.player.view_angle() + PI, "BUCKSHOT", g.clock + 1.0]
	return g


## Two players (the feed is on), the second away off to the side.
static func _pair(main: Node, level: String, mode: String, count := 2) -> Game:
	var g: Game = main.make_game(level)
	main.game = g
	main.state = "play"
	var options := SessionStore.defaults()
	options["hound"] = 1
	g.configure(options)
	Modes.setup(g, mode, count, {})
	g.cheats.god = true
	g.lessons = false
	g.barks.enabled = false
	g.spawn_grace = 99.0
	for e: Enemy in g.enemies:
		e.dormant = true
	for p: Player in g.players:
		p.name = NAMES[p.slot % NAMES.size()]
	return g


static func _feed(g: Game) -> void:
	var feed = g.features.get("kill_feed")
	if feed == null:
		return
	feed.add("BUBBA  SAWED-OFF  BILLY", feed.KILL_INK)
	feed.add("CLETUS WENT DOWN", feed.DOWN_INK)
	feed.add("EARLENE HAULED CLETUS UP", feed.UP_INK)
	feed.add("BUBBA  DYNAMITE CROSSBOW  ALIEN SHERIFF", feed.BOSS_INK)
	feed.add("MUNDELL  .38  SWAMP KING", feed.BOSS_INK)


static func _drive(main: Node) -> Game:
	var g := _pair(main, "bayou", Modes.COOP)
	_ticks(g, 20)
	var rides = g.features["vehicles"]
	rides.seat_in(g.player, 0)
	var runs = g.features["vehicle_runs"]
	runs._start(0, 0, rides.rides[0])
	_ticks(g, 2)
	_feed(g)
	return g


static func _lap(main: Node) -> Game:
	var g := _start(main, "speedway")
	_ticks(g, 10)
	var rides = g.features["vehicles"]
	for i in rides.rides.size():
		var v: VehicleDrive.Ride = rides.rides[i]
		if v.kind == "car":
			rides.seat_in(g.player, i)
			break
	_ticks(g, 4)
	return g


static func _coop(main: Node, watching: bool) -> Game:
	var g := _pair(main, "hickston", Modes.COOP, 3)
	_ticks(g, 20)
	var a: Player = g.players[0]
	var b: Player = g.players[1]
	var c: Player = g.players[2]
	# b down beside a; c far off (its tag at the view's edge).
	Modes.place(g, b, a.x + cos(a.angle) * .8, a.y + sin(a.angle) * .8, 0.0)
	Modes.place(g, c, a.x - cos(a.angle) * 6.0, a.y - sin(a.angle) * 6.0, 0.0)
	g.cheats.god = false
	g.damage(500.0, null, "TEST", b)
	g.cheats.god = true
	_ticks(g, 4)
	_feed(g)
	if watching:
		g.cheats.god = false
		g.damage(500.0, null, "TEST", a)
		g.cheats.god = true
		TacticalScreens.human = 0
		_ticks(g, 4)
		Players.set_local(g, c)
		return g
	TacticalScreens.human = 0
	b.revive = CoopMode.REVIVE_TIME * .4
	var held := Game.Controls.new()
	held.use = true
	for i in 10:
		g.tick(STEP, held)
	return g


static func _boss(main: Node) -> Game:
	var g: Game = BossRematch.build(Callable(main, "make_game"), "boss")
	main.game = g
	main.state = "play"
	g.configure(SessionStore.defaults())
	g.cheats.god = true
	g.barks.enabled = false
	var e := BossFight.of_kind(g, "boss")
	var p := g.player
	# Well into the arena, a few steps short of the boss.
	var door := Vector2(p.x, p.y)
	for k in range(1, 20):
		var at := door.lerp(Vector2(e.x, e.y), k * .04)
		if not g.world.blocked(at.x, at.y, .4) and BossFight.in_arena_at(g, e, at.x, at.y):
			p.x = at.x
			p.y = at.y
			break
	p.angle = atan2(e.y - p.y, e.x - p.x)
	e.alerted = true
	e.cooldown = 99.0
	e.windup = .5
	_ticks(g, 2)
	e.windup = .5
	g.callout = "TWOFER!"
	g.callout_until = g.clock + 1.0
	return g


static func _versus(main: Node) -> Game:
	var g := _pair(main, "hickston", Modes.DEATHMATCH, 4)
	_ticks(g, 20)
	_feed(g)
	return g


static func _fair(main: Node) -> Game:
	var g := _start(main, "fair")
	_ticks(g, 10)
	var gallery = g.features.get("fair_gallery")
	if gallery != null:
		gallery.round_on = true
	return g


static func _county(main: Node) -> Game:
	var g: Game = main.make_game("county_hickston")
	g.configure(SessionStore.defaults())
	Modes.setup(g, Modes.COUNTY, 1)
	g.tick(STEP, Game.Controls.new())
	var f = g.features["county"]
	f.next_spawn = 1e9
	f.streak = 30
	main.game = g
	main.state = "play"
	return g


static func _tactical(main: Node) -> Game:
	var g: Game = main.make_game("grainyard")
	g.configure(SessionStore.defaults())
	Modes.setup(g, Modes.BOMB, 10, {"arena": "grainyard"})
	for i in 60:
		g.tick(1.0 / 120.0, Game.Controls.new())
	TacticalScreens.human = 0
	main.game = g
	main.state = "play"
	return g
