## COUNTY RUN's keys, clicks and taps (CLAUDE.md "County Run"): the map
## picker, the slots by number in a fight (1-3; the wheel and the game's own
## next-gun keys and button cycle through what is carried), the reward cards
## (1-3, arrows and ENTER, a click or a tap), the swap (a slot, CONFIRM or
## CANCEL back to the same cards), the build screen (B) and the end of the
## run (ENTER retry, M the maps, ESC the title). county_screens.gd draws them
## and notes where each tap lands; a tap does what its key does.
class_name CountyInput
extends RefCounted

const NUMBERS := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9]

# ------------------------------------------------------------------ picker


static func key_maps(main, code: int) -> void:
	var n := CountyData.maps().size()
	if code == KEY_ESCAPE:
		main.back_to_title()
	elif code in [KEY_UP, KEY_W, KEY_LEFT, KEY_A, KEY_DOWN, KEY_S, KEY_RIGHT, KEY_D]:
		var step := -1 if code in [KEY_UP, KEY_W, KEY_LEFT, KEY_A] else 1
		CountyScreens.map_row = posmod(CountyScreens.map_row + step, n)
		main.sound.play("menu_move")
	elif code in NUMBERS and NUMBERS.find(code) < n:
		CountyScreens.map_row = NUMBERS.find(code)
		_go(main)
	elif code in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		_go(main)


static func _go(main) -> void:
	var maps := CountyData.maps()
	if maps.is_empty():
		return
	main.sound.play("menu_accept")
	main.start_county(String(maps[posmod(CountyScreens.map_row, maps.size())]["id"]))


# ------------------------------------------------------------------ play


## A key in play during a run: true when it was the run's (the game's own
## handler goes on otherwise).
static func key_play(main, game, code: int) -> bool:
	var f = CountyMode.run(game)
	if f == null:
		return false
	if f.over:
		return _key_end(main, game, code)
	if CountyScreens.build_open:
		if code in [KEY_ESCAPE, KEY_B, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_TAB]:
			close_build(game)
			return true
		return code != KEY_F11
	if not f.pending.is_empty():
		return _key_cards(main, game, f, code)
	if code in NUMBERS:
		var i := NUMBERS.find(code)
		if i < f.slots.size() and int(f.slots[i]) >= 0:
			game.armory.select(int(f.slots[i]), game)
		return true
	if code in [KEY_0, KEY_MINUS, KEY_EQUAL, KEY_BACKSLASH]:
		return true  # the campaign's gun keys: nothing to carry there
	if code == KEY_B:
		open_build(game)
		return true
	if code in [KEY_C, KEY_M, KEY_V, KEY_X, KEY_F, KEY_Q]:
		return true  # no pockets in a run
	return false


static func open_build(game) -> void:
	CountyScreens.build_open = true
	var f = CountyMode.run(game)
	if f != null:
		f.paused = true


static func close_build(game) -> void:
	CountyScreens.build_open = false
	var f = CountyMode.run(game)
	if f != null:
		f.paused = false


static func _key_cards(main, game, f, code: int) -> bool:
	if code == KEY_ESCAPE:
		if CountyScreens.swapping >= 0:
			cancel_swap(main)
			return true
		return false  # the title (the world stays held)
	if code == KEY_B:
		open_build(game)
		return true
	if not CountyScreens.armed():
		return true
	var n: int = f.offer.size()
	if CountyScreens.swapping >= 0:
		if code in NUMBERS and NUMBERS.find(code) < f.slots.size():
			pick_slot(main, game, NUMBERS.find(code))
		elif code in [KEY_UP, KEY_W, KEY_DOWN, KEY_S]:
			var step := -1 if code in [KEY_UP, KEY_W] else 1
			CountyScreens.swap_slot = posmod(
				maxi(0, CountyScreens.swap_slot) + step, f.slots.size()
			)
			main.sound.play("menu_move")
		elif code in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE] and CountyScreens.swap_slot >= 0:
			confirm_swap(main, game)
		return true
	if code in NUMBERS and NUMBERS.find(code) < n:
		take(main, game, NUMBERS.find(code))
	elif code in [KEY_LEFT, KEY_A, KEY_RIGHT, KEY_D]:
		var step := -1 if code in [KEY_LEFT, KEY_A] else 1
		CountyScreens.card_row = posmod(CountyScreens.card_row + step, n)
		main.sound.play("menu_move")
	elif code in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		take(main, game, CountyScreens.card_row)
	return true


## Card `i` taken: a weapon with every slot full asks which to swap out.
static func take(main, game, i: int) -> void:
	var f = CountyMode.run(game)
	if f == null or i < 0 or i >= f.offer.size():
		return
	CountyScreens.card_row = i
	var card: Dictionary = f.offer[i]
	if String(card["type"]) == "weapon" and CountyBuild.open_slot(f) < 0:
		CountyScreens.swapping = i
		CountyScreens.swap_slot = -1
		main.sound.play("menu_accept")
		return
	if CountyMode.choose(game, i):
		CountyScreens.card_row = 0


static func pick_slot(main, game, slot: int) -> void:
	if CountyScreens.swap_slot == slot:
		confirm_swap(main, game)
		return
	CountyScreens.swap_slot = slot
	main.sound.play("menu_move")


static func confirm_swap(main, game) -> void:
	var i := CountyScreens.swapping
	var slot := CountyScreens.swap_slot
	if i < 0 or slot < 0:
		return
	CountyScreens.swapping = -1
	CountyScreens.swap_slot = -1
	if CountyMode.choose(game, i, slot):
		CountyScreens.card_row = 0
	else:
		main.sound.play("empty")


## Back to the same three cards, nothing taken.
static func cancel_swap(main) -> void:
	CountyScreens.swapping = -1
	CountyScreens.swap_slot = -1
	main.sound.play("menu_back")


static func _key_end(main, game, code: int) -> bool:
	match code:
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_R:
			if code == KEY_SPACE or code == KEY_ENTER or code == KEY_KP_ENTER:
				_end_action(main, game, CountyScreens.over_row if code != KEY_R else 0)
			else:
				_end_action(main, game, 0)
			return true
		KEY_M:
			_end_action(main, game, 1)
			return true
		KEY_LEFT, KEY_A, KEY_RIGHT, KEY_D:
			var step := -1 if code in [KEY_LEFT, KEY_A] else 1
			CountyScreens.over_row = posmod(CountyScreens.over_row + step, 3)
			main.sound.play("menu_move")
			return true
		KEY_B:
			return true
	return false


## The end's buttons: 0 retry the map, 1 the map picker, 2 the title.
static func _end_action(main, game, which: int) -> void:
	var map_id := String(game.level.id)
	CountyScreens.reset()
	match which:
		0:
			main.sound.play("menu_accept")
			main.start_county(map_id)
		1:
			main.open_county(true)
		_:
			main.return_to_title(true)


# ------------------------------------------------------------------ taps


## A tap or left click at `at` on the picker or over a run. True when it hit
## one of the run's places.
static func tap(main, at: Vector2i) -> bool:
	var hit := LobbyScreens.zone_at(at)
	if hit.is_empty():
		return false
	var id := String(hit[0])
	var arg := int(hit[1])
	if String(main.state) == "county":
		if id == "back":
			main.key(KEY_ESCAPE)
		elif id == "map":
			CountyScreens.map_row = arg
			_go(main)
		return true
	var game = main.game
	var f = CountyMode.run(game)
	if f == null:
		return false
	match id:
		"card":
			if CountyScreens.armed():
				take(main, game, arg)
		"slot":
			if CountyScreens.armed():
				pick_slot(main, game, arg)
		"confirm":
			confirm_swap(main, game)
		"cancel":
			cancel_swap(main)
		"build":
			open_build(game)
		"close":
			close_build(game)
		"retry":
			_end_action(main, game, 0)
		"maps":
			_end_action(main, game, 1)
		"title":
			_end_action(main, game, 2)
		_:
			return false
	return true


## The pointer over a card, a slot, a map or an end button picks it.
static func hover(main, at: Vector2i) -> void:
	var hit := LobbyScreens.zone_at(at)
	if hit.is_empty():
		return
	var id := String(hit[0])
	var arg := int(hit[1])
	var moved := false
	if id == "map" and CountyScreens.map_row != arg:
		CountyScreens.map_row = arg
		moved = true
	elif id == "card" and CountyScreens.card_row != arg:
		CountyScreens.card_row = arg
		moved = true
	elif id in ["retry", "maps", "title"]:
		var row := ["retry", "maps", "title"].find(id)
		moved = CountyScreens.over_row != row
		CountyScreens.over_row = row
	if moved:
		main.sound.play("menu_move")
