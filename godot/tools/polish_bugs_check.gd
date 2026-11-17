## Polish pass 9's BUGS fixes that are not save numbers (save_numbers_check.gd).
## check_fixes step `polish_bugs`.
##
## - A twister lifting past the map's edge (it runs on 8 cells past its end)
##   read the ground off the map: a script error each frame on the quarry
##   and Copperhead Ridge, and its rip and fling skipped. check_all fails a
##   row whose output holds a script error, so this plays one out there.
## - A hand sent running from a barn creaking down (or from lit dynamite)
##   holds a retreat without the once-only fall-back; Python's save check
##   refused such a save, and with it every later campaign save keeping that
##   chapter (seen after a twister on Copperhead Ridge).
## - The blackout's word names the FLASHLIGHT key as bound (and none on a pad
##   or a touch screen); the breaker's prompt names the USE button.
extends RefCounted

const STEP := 1.0 / 60.0


static func run(main: Control, check: Callable) -> void:
	print("\nPOLISH PASS 9 BUGS")
	for id: String in ["quarry", "moonshine"]:
		_twister_edge(main, check, id)
	_flee_save(main, check)
	_words(main, check)


static func _game(main: Control, id: String, events := 2) -> Game:
	var g: Game = main.make_game(id)
	g.configure({"difficulty": 1, "events": events})
	g.lessons = false
	g.cheats.god = true
	var history: Array = []
	for c: String in Campaign.ORDER:
		if c == id:
			break
		history.append([c, 0, 0, 0, 0, 0])
	g.history = history
	return g


static func _twister_edge(main: Control, check: Callable, id: String) -> void:
	var g := _game(main, id)
	for t in 30:
		g.tick(STEP, Game.Controls.new())
	var ev: CountyEvents = g.features["events"]
	if not ev.begin("twister"):
		check.call(false, "%s: a twister starts" % id)
		return
	var off := false
	var w := g.world
	for t in 60 * 180:
		g.tick(STEP, Game.Controls.new())
		var at := ev.tw_at
		off = off or at.x < 0.0 or at.y < 0.0 or at.x >= w.width or at.y >= w.height
		if ev.kind == "":
			break
	check.call(ev.kind == "", "%s: a twister plays out" % id)
	check.call(off, "%s: it lifts past the map's edge (no script error reading the ground)" % id)
	check.call(
		is_equal_approx(w.elevation_near(-5.0, w.height + 3.0), w.elevation(0.0, w.height - 1.0)),
		"%s: the ground off the map is its nearest cell's" % id
	)


static func _flee_save(main: Control, check: Callable) -> void:
	var g := _game(main, "hickston", 0)
	g.tick(STEP, Game.Controls.new())
	var sets: SetPiecesFeature = g.features.get("set_pieces")
	var boxes: Array = sets.get("_boxes")
	var hand: Enemy = null
	for e: Enemy in g.enemies:
		if e.alive and e.tactical() and not Enemy.BOSS_TITLES.has(e.kind) and hand == null:
			hand = e
	if boxes.is_empty() or hand == null:
		check.call(false, "hickston has a set piece and a hand")
		return
	var box: Rect2 = boxes[0]
	hand.x = box.get_center().x
	hand.y = box.position.y - .8
	sets.call("_warn", 0)
	check.call(
		hand.retreat != null and not hand.responded,
		"a hand by a barn creaking down runs (no fall-back used)"
	)
	var text := JSON.stringify(SessionStore.snapshot(g))
	var parsed: Variant = JSON.parse_string(text)
	var doc: Dictionary = parsed if parsed is Dictionary else {}
	SessionStore.last_error = ""
	var back := SessionStore.restore(doc, main.make_game)
	check.call(back != null, "a save with him running loads ('%s')" % SessionStore.last_error)


static func _words(main: Control, check: Callable) -> void:
	var g := _game(main, "hickston")
	g.tick(STEP, Game.Controls.new())
	var ev: CountyEvents = g.features["events"]
	g.torch_key = "K"
	g.use_key = "Y"
	ev.begin("blackout")
	check.call(g.notice.ends_with("FLASHLIGHT: K."), "the blackout names the bound key (%s)" % g.notice)
	ev.finish()
	g.torch_key = ""
	ev.begin("blackout")
	check.call(g.notice.ends_with("FLASHLIGHT."), "and no key on a pad (%s)" % g.notice)
	g.player.x = ev.breaker.x
	g.player.y = ev.breaker.y
	check.call(
		ev.prompt(g.player) == "Y: THROW THE MAIN BREAKER",
		"the breaker names the USE button (%s)" % ev.prompt(g.player)
	)
	var options: Dictionary = main.options.duplicate()
	main.options[KeyBindings.option_key("flashlight")] = KEY_K
	main.input_device = "keys"
	var keyed: String = main.torch_button()
	main.input_device = "pad"
	var padded: String = main.torch_button()
	main.options = options
	check.call(keyed == "K" and padded == "", "the front end names the key, none on a pad")
