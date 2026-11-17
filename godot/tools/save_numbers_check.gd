## A save file round trip (JSON: every number comes back a float) in the
## middle of the v3.6.0 things whose state holds whole numbers used as
## indexes or slots (polish pass 9, BUGS). check_fixes step `save_numbers`.
##
## - Saved at the wheel: loaded, the player is still at the wheel (the seats
##   were floats, seat_of never found them, the seat stayed taken for good
##   and the player stood in the bayou's deep channel on foot).
## - Saved mid-raid: the revenue men still know each other (raiders were
##   floats, has() missed, they fought each other).
## - Saved mid-blackout: a hand with a lantern still sees as ever.
extends RefCounted

const STEP := 1.0 / 60.0
const VehicleCheck := preload("res://tools/vehicle_check.gd")


static func run(main: Control, check: Callable) -> void:
	print("\nSAVE FILE NUMBERS (a JSON round trip mid-ride, mid-raid, mid-blackout)")
	_ride(main, check)
	_raid(main, check)
	_blackout(main, check)


static func _game(main: Control, id: String) -> Game:
	var g: Game = main.make_game(id)
	g.configure({"difficulty": 1, "events": 0})
	g.lessons = false
	g.cheats.god = true
	var history: Array = []
	for c: String in Campaign.ORDER:
		if c == id:
			break
		history.append([c, 0, 0, 0, 0, 0])
	g.history = history
	return g


static func _tick(g: Game, n: int) -> void:
	for t in n:
		g.tick(STEP, Game.Controls.new())


## The save file's way: the document to JSON text and back, then restored.
static func _through_file(main: Control, g: Game) -> Game:
	var text := JSON.stringify(SessionStore.snapshot(g))
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return null
	var doc: Dictionary = parsed
	return SessionStore.restore(doc, main.make_game)


static func _ride(main: Control, check: Callable) -> void:
	for id: String in ["bayou", "moonshine"]:
		var g := _game(main, id)
		_tick(g, 2)
		VehicleCheck.walk_up(g)
		g.interact()
		VehicleCheck.drive(g, 60, 1.0)
		var rides: GameFeature = g.features.get("vehicles")
		var was: bool = rides.call("seated", g.player)
		var back := _through_file(main, g)
		check.call(back != null, "%s: a save at the wheel loads" % id)
		if back == null:
			continue
		var rides2: GameFeature = back.features.get("vehicles")
		check.call(
			was and rides2.call("seated", back.player),
			"%s: loaded, the player is still at the wheel" % id
		)
		back.cheats.god = true
		back.interact()
		_tick(back, 2)
		var off: bool = not rides2.call("seated", back.player)
		back.interact()
		_tick(back, 2)
		check.call(
			off and rides2.call("seated", back.player),
			"%s: USE gets them out and back in again" % id
		)


static func _raid(main: Control, check: Callable) -> void:
	var g := _game(main, "hickston")
	g.configure({"difficulty": 1, "events": 2})
	_tick(g, 2)
	var ev: CountyEvents = g.features["events"]
	if not ev.begin("raid"):
		check.call(false, "a raid starts on hickston")
		return
	_tick(g, 30)
	var back := _through_file(main, g)
	check.call(back != null, "a save mid-raid loads")
	if back == null:
		return
	var ev2: CountyEvents = back.features["events"]
	var known := ev2.kind == "raid" and not ev2.raiders.is_empty()
	for i: int in ev2.raiders:
		known = known and EventRaid.raider(ev2, back.enemies[i])
		known = known and not EventRaid.local(ev2, back.enemies[i])
	check.call(known, "loaded, the revenue men still know each other (%d)" % ev2.raiders.size())


static func _blackout(main: Control, check: Callable) -> void:
	var g := _game(main, "hickston")
	g.configure({"difficulty": 1, "events": 2})
	_tick(g, 2)
	var ev: CountyEvents = g.features["events"]
	if not ev.begin("blackout") or ev.lanterns.is_empty():
		check.call(false, "a blackout with lanterns starts on hickston")
		return
	_tick(g, 30)
	var back := _through_file(main, g)
	check.call(back != null, "a save mid-blackout loads")
	if back == null:
		return
	var ev2: CountyEvents = back.features["events"]
	var i: int = ev2.lanterns[0]
	check.call(
		ev2.notice(back.enemies[i], back.player) == 1.0,
		"loaded, a hand with a lantern still sees as ever"
	)
