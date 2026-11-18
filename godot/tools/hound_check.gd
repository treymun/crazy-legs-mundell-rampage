## BLUE, the hound (content pass 8: src/features/hound.gd, src/hound_nose.gd,
## src/hound_looks.gd; tools/check_all.gd runs it):
##
##   godot --headless --path godot --script res://tools/hound_check.gd
##
## HEEL: a hound comes with player one on a chapter with HOUND DOG on, and
## none with it off, in County Run, a versus map, the range or the
## Crossroads; left behind he catches up and heels behind his player, out of
## their sights. NOSE: he bays at a secret door not found yet, at a gun his
## player ain't got, and points at a pickup out of their sight. FIGHT: on his
## own he goes for a badly hurt hand, holds it (it cannot fight), never kills
## it, the hands kick at him, and a player finishes it; told (the whistle
## with the sights on one) he goes for a whole one and bites it down; never a
## boss. FETCH: told, he brings a pickup to his player's feet and they take
## it. DOWN: hurt to nothing he lies whining; held USE gets him up, a rind
## at once, and he gets up himself in time. WHISTLE: STAY, COME, the replay
## op and Controls.item. SAVE: a save puts him back. COOP: two players, two
## hounds, each with their own. NET: two games fed the same controls stay
## identical with the hounds about, a snapshot carries them onto a fresh game
## that runs on the same. LOOKS: his frames, the badge, his art and settings.
## POSES (pass 10): every state and moment shows its own pose of his model
## (src/hound_looks.gd: the walk, trot and gallop by pace, the limp, the
## tracking walk, idle, scratch and sniff, sit and lying at STAY, the point,
## the howl, the lunge and bite, the hold's shake, the yelp, going down,
## whining on his side, got up, getting up and the shake), each a frame his
## model has, none of it drawing on game.rng. FEEDBACK: the badge's job and
## mood words, the marker over him behind a wall and at the view's edge, the
## brackets on what he points at, GETTIN' BLUE UP and its bar, and USE's
## prompt naming the key.
extends SceneTree

const STEP := 1.0 / 60.0
const Pilot := preload("res://tools/bot_pilot.gd")
const Hound := preload("res://src/features/hound.gd")

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
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("play="):
			_play(arg.substr(5))
			main.queue_free()
			await process_frame
			quit()
			return
	for part: String in [
		"heel",
		"off",
		"nose",
		"fight",
		"fetch",
		"down",
		"whistle",
		"save",
		"coop",
		"net",
		"looks",
		"poses",
		"feedback"
	]:
		print("\n" + part.to_upper())
		call("_" + part)
	print("")
	print(
		(
			"%d checks in %.1f s"
			% [passes + failures.size(), (Time.get_ticks_msec() - started) / 1000.0]
		)
	)
	print("HOUND CHECK OK" if failures.is_empty() else "%d HOUND CHECK(S) FAILED" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


# ------------------------------------------------------------------ helpers


func _game(id: String, hound := true, keep_enemies := false) -> Game:
	var g: Game = main.make_game(id)
	g.configure({"difficulty": 1, "hound": 1 if hound else 0})
	g.cheats.god = true
	g.lessons = false
	if not keep_enemies:
		g.enemies.clear()
		g.enemy_ids.clear()
	return g


func _tick(g: Game, n: int, c: Game.Controls = null) -> void:
	for t in n:
		g.tick(STEP, c if c != null else Game.Controls.new())


func _hound(g: Game) -> Hound:
	return g.features["hound"]


func _dog(g: Game, slot := 0) -> Hound.Dog:
	var h := _hound(g)
	for d: Hound.Dog in h.dogs:
		if d.slot == slot:
			return d
	return null


## An open spot about `far` from (x, y) on its floor and in its sight, or INF.
func _spot(g: Game, x: float, y: float, far: float) -> Vector2:
	var reach := far
	while reach >= 1.0:
		for k in 24:
			var a := k * TAU / 24.0
			var at := Vector2(x, y) + Vector2(cos(a), sin(a)) * reach
			if at.x < 1 or at.y < 1 or at.x > g.world.width - 1 or at.y > g.world.height - 1:
				continue
			if g.world.blocked(at.x, at.y, .35) or g.world.deep_at(at.x, at.y):
				continue
			if absf(g.world.elevation(at.x, at.y) - g.world.elevation(x, y)) > .3:
				continue
			if not g.world.visible(
				at.x, at.y, x, y, g.world.elevation(x, y) + .9, g.world.elevation(x, y) + .9
			):
				continue
			return at
		reach -= .5
	return Vector2.INF


func _put_player(g: Game, at: Vector2, look: Vector2) -> void:
	var p := g.player
	p.x = at.x
	p.y = at.y
	p.floor_z = g.world.elevation(at.x, at.y)
	p.eye = p.floor_z + .95
	p.air = 0.0
	p.pitch = 0.0
	p.angle = atan2(look.y - at.y, look.x - at.x)
	p.flow.update(p.x, p.y, g.clock)


func _put_dog(g: Game, d: Hound.Dog, at: Vector2) -> void:
	d.x = at.x
	d.y = at.y
	d.floor_z = g.world.elevation(at.x, at.y)


## A hand of a kind he takes, kept from the level, woken and put at `at`.
func _foe(g: Game, at: Vector2) -> Enemy:
	for e: Enemy in g.enemies:
		if e.hostile and HoundNose.takes(e) and e.tactical():
			for other: Enemy in g.enemies:
				if other != e:
					other.dormant = true
			e.dormant = false
			e.x = at.x
			e.y = at.y
			e.floor_z = g.world.elevation(at.x, at.y)
			e.alerted = true
			e.mind = null
			return e
	return null


# ------------------------------------------------------------------ the parts


func _heel() -> void:
	var g := _game("hickston")
	_tick(g, 2)
	var d := _dog(g)
	_check(d != null and _hound(g).on, "hickston: BLUE comes along")
	if d == null:
		return
	var p := g.player
	_check(Vector2(d.x - p.x, d.y - p.y).length() < 2.0, "he starts at the player's heel")
	var away := _spot(g, p.x, p.y, 7.0)
	_put_player(g, away, Vector2(away.x + 3.0, away.y))
	_tick(g, 60 * 4)
	var gap := Vector2(d.x - p.x, d.y - p.y).length()
	_check(gap < 2.3, "left behind he catches up and heels (%.1f off)" % gap)
	var look := Vector2(cos(p.angle), sin(p.angle))
	var to := Vector2(d.x - p.x, d.y - p.y).normalized()
	_check(to.dot(look) < .5, "he heels out of the player's sights (%.2f)" % to.dot(look))
	# Lost: far off and out of sight, he turns up behind them.
	var far := Vector2.INF
	for k in 400:
		var at := Vector2(
			2.5 + (k * 37) % maxi(1, g.world.width - 5),
			2.5 + (k * 53) % maxi(1, g.world.height - 5)
		)
		if at.distance_to(Vector2(p.x, p.y)) > 26.0 and not g.world.blocked(at.x, at.y, .3):
			far = at
			break
	_put_dog(g, d, far)
	_tick(g, 60 * 7)
	gap = Vector2(d.x - p.x, d.y - p.y).length()
	_check(gap < 3.0, "lost far off he turns up behind the player (%.1f)" % gap)


func _off() -> void:
	var g := _game("hickston", false)
	_tick(g, 2)
	_check(_hound(g).dogs.is_empty(), "HOUND DOG off: no hound")
	for id: String in ["county_hickston", "grainyard", "range", "hub"]:
		var h := _game(id)
		_tick(h, 2)
		_check(_hound(h).dogs.is_empty() and not HoundNose.on(h), "%s: no hound" % id)
	var dm := _game("hickston")
	Modes.setup(dm, Modes.DEATHMATCH, 2)
	_tick(dm, 2)
	_check(_hound(dm).dogs.is_empty(), "a deathmatch: no hound")


func _nose() -> void:
	# A secret door: he bays at it from its open side.
	var bayed := false
	for id: String in ["hickston", "fair", "sawmill", "quarry"]:
		var doors := _game(id).world.doors
		for k in doors.size():
			var shut: LevelData.Door = doors[k]
			if not shut.secret or shut.discovered:
				continue
			var g := _game(id)
			_tick(g, 2)
			var d := _dog(g)
			var door: LevelData.Door = g.world.doors[k]
			var front := HoundNose.door_front(g, door, door.x + .5, door.y + .5)
			if front == Vector2.INF:
				continue
			var stand := _spot(g, front.x, front.y, 3.0)
			if stand == Vector2.INF:
				continue
			_put_player(g, stand, front)
			_put_dog(g, d, stand.lerp(front, .5))
			var before := _hound(g).bays
			for t in 60 * 3:
				g.tick(STEP, Game.Controls.new())
				if _hound(g).bays > before:
					break
			if _hound(g).bays > before:
				var near := Vector2(d.x - front.x, d.y - front.y).length()
				_check(
					near < 1.2 and d.state == Hound.BAY,
					(
						"%s: he bays at the secret door at %d,%d (%.1f off its front)"
						% [id, door.x, door.y, near]
					)
				)
				bayed = true
				break
		if bayed:
			break
	_check(bayed, "he bays at a secret door not found yet")
	# New iron: a gun the player ain't got, lying out.
	var g2 := _game("hickston")
	_tick(g2, 2)
	var d2 := _dog(g2)
	var found := false
	for entry: Array in g2.pickups:
		var item := str(entry[0])
		var x: float = entry[1]
		var y: float = entry[2]
		if GunFinder.guns_of(item).is_empty() or not GunFinder.unclaimed(item, g2.player.armory):
			continue
		if GunFinder.in_secret(g2, x, y):
			continue
		var stand := _spot(g2, x, y, 4.0)
		if stand == Vector2.INF:
			continue
		_put_player(g2, stand, Vector2(x + 5, y))
		_put_dog(g2, d2, stand)
		var before := _hound(g2).bays
		_tick(g2, 60 * 2)
		if _hound(g2).bays > before:
			_check(
				_hound(g2).bayed.has(HoundNose.key(Vector2(x, y))), "he bays at new iron: %s" % item
			)
			found = true
			break
	_check(found, "he finds a gun the player ain't got")
	# A pickup out of the player's sight: he points at it.
	var g3 := _game("hickston")
	_tick(g3, 2)
	var d3 := _dog(g3)
	var p := g3.player
	var pointed := false
	var pair := _hidden_pair(g3, p)
	if not pair.is_empty():
		var dog_at: Vector2 = pair[0]
		var at: Vector2 = pair[1]
		_put_dog(g3, d3, dog_at)
		for door: LevelData.Door in g3.world.doors:
			_hound(g3).bayed[HoundNose.key(Vector2(door.x + .5, door.y + .5))] = 0.0
		g3.add_pickup("shells", at.x, at.y)
		var before := _hound(g3).points
		for t in 60 * 3:
			g3.tick(STEP, Game.Controls.new())
			if _hound(g3).points > before:
				break
		pointed = _hound(g3).points > before and d3.state == Hound.POINT
		_check(
			pointed and _hound(g3).bayed.has(HoundNose.key(at)),
			"he points at buckshot out of the player's sight"
		)
	_check(pointed, "he points at a pickup the player cannot see")


## A place near player p for the hound and one for a pickup he can see from
## it that p cannot: [hound, pickup], or [].
func _hidden_pair(g: Game, p: Player) -> Array:
	var z := g.world.elevation(p.x, p.y)
	for ring in range(2, 8):
		for k in 16:
			var a := k * TAU / 16.0
			var dog_at := Vector2(p.x, p.y) + Vector2(cos(a), sin(a)) * ring
			if (
				g.world.blocked(dog_at.x, dog_at.y, .35)
				or absf(g.world.elevation(dog_at.x, dog_at.y) - z) > .1
			):
				continue
			if not g.world.visible(p.x, p.y, dog_at.x, dog_at.y, p.eye, z + .4):
				continue
			for r2 in range(2, 6):
				for k2 in 16:
					var b := k2 * TAU / 16.0
					var at := dog_at + Vector2(cos(b), sin(b)) * r2
					if (
						at.x < 1
						or at.y < 1
						or at.x > g.world.width - 1
						or at.y > g.world.height - 1
					):
						continue
					if (
						g.world.blocked(at.x, at.y, .3)
						or absf(g.world.elevation(at.x, at.y) - z) > .1
					):
						continue
					if not g.world.visible(dog_at.x, dog_at.y, at.x, at.y, z + .4, z + .2):
						continue
					if g.world.visible(p.x, p.y, at.x, at.y, p.eye, z + .2):
						continue
					return [dog_at, at]
	return []


func _fight() -> void:
	var g := _game("hickston", true, true)
	_tick(g, 2)
	var d := _dog(g)
	var p := g.player
	var at := _spot(g, p.x, p.y, 4.0)
	var e := _foe(g, at)
	_check(e != null, "a hand to fight")
	if e == null:
		return
	_put_player(g, Vector2(p.x, p.y), Vector2(e.x, e.y + 3.0))
	e.hp = e.max_hp * .4
	var held := false
	var stunned := true
	var dragged := false
	var faced := true
	for t in 60 * 6:
		g.tick(STEP, Game.Controls.new())
		if d.state == Hound.PIN:
			held = true
			stunned = stunned and e.stun > 0.0
			dragged = dragged or e.held_cel.ends_with("_die_1")
			var to_p := atan2(g.player.y - e.y, g.player.x - e.x)
			faced = faced and absf(wrapf(e.angle - to_p, -PI, PI)) < .05
		elif held:
			break
	_check(held, "on his own he goes for a badly hurt hand and holds it")
	_check(stunned, "held, it cannot fight (stunned the whole time)")
	_check(dragged and faced, "held, it is dragged half down, leaning back from the player")
	_check(e.held_cel == "" or d.state == Hound.PIN, "let go, it stands again")
	_check(e.alive and e.hp >= 1.0, "he never kills it himself (%.0f health left)" % e.hp)
	_check(_hound(g).kicks > 0, "the hands kick at him (%d kicks)" % _hound(g).kicks)
	# The player finishes it.
	var pins := _hound(g).finished
	d.state = Hound.PIN
	d.foe = e.uid
	d.until = g.clock + 3.0
	e.hurt(e.hp + 50.0, g)
	_tick(g, 2)
	_check(
		not e.alive and _hound(g).finished == pins + 1 and d.state == Hound.FOLLOW,
		"a player finishes the hand he holds; he lets go"
	)
	# Told: the whistle with the sights on a whole hand.
	var g2 := _game("hickston", true, true)
	_tick(g2, 2)
	var d2 := _dog(g2)
	var p2 := g2.player
	var at2 := _spot(g2, p2.x, p2.y, 5.0)
	var e2 := _foe(g2, at2)
	_put_player(g2, Vector2(p2.x, p2.y), Vector2(e2.x, e2.y))
	e2.hp = e2.max_hp
	g2.hound_call()
	_check(d2.state == Hound.SIC and d2.foe == e2.uid, "the whistle on a whole hand: SIC 'EM")
	var pinned := false
	for t in 60 * 10:
		g2.tick(STEP, Game.Controls.new())
		pinned = pinned or d2.state == Hound.PIN
		e2.cooldown = 1.0  # it fights back only by kicking
	_check(
		_hound(g2).bites > 0 and pinned,
		"he bites it down to half and holds it (%d bites)" % _hound(g2).bites
	)
	_check(e2.alive, "and never kills it")
	# Never a boss.
	var g3 := _game("quarry", true, true)
	var boss: Enemy = null
	for b: Enemy in g3.enemies:
		if Enemy.BOSS_TITLES.has(b.kind):
			boss = b
	_check(
		boss != null and not HoundNose.takes(boss),
		"never a boss (%s)" % ("none" if boss == null else boss.kind)
	)


func _fetch() -> void:
	var g := _game("hickston")
	_tick(g, 2)
	var d := _dog(g)
	var p := g.player
	var at := _spot(g, p.x, p.y, 5.0)
	_put_player(g, Vector2(p.x, p.y), at)
	_put_dog(g, d, Vector2(p.x, p.y).lerp(at, .2))
	g.add_pickup("shells", at.x, at.y)
	var before: int = g.armory.reserve[Weapons.NAMES.find("shotgun")]
	g.hound_call()
	_check(d.state == Hound.FETCH, "the whistle on a pickup: FETCH")
	var carried := false
	for t in 60 * 8:
		g.tick(STEP, Game.Controls.new())
		carried = carried or d.item == "shells"
	var after: int = g.armory.reserve[Weapons.NAMES.find("shotgun")]
	_check(carried, "he takes it up and carries it")
	_check(
		_hound(g).fetches == 1 and after > before,
		"he drops it at the player's feet and they have it (%d -> %d)" % [before, after]
	)


func _down() -> void:
	var g := _game("hickston")
	_tick(g, 2)
	var h := _hound(g)
	var d := _dog(g)
	var p := g.player
	h.call("_hurt", d, 500.0, d.x + 1.0, d.y)
	_check(d.state == Hound.DOWN and d.health == 0.0, "hurt to nothing he goes down")
	_check(h.frame(d) == "f0", "going down onto his side (%s)" % h.frame(d))
	_tick(g, roundi(60 * (HoundLooks.FALL_TIME + .1)))
	_check(h.frame(d) == "o0", "lying on his side, whining (%s)" % h.frame(d))
	p.x = d.x + .5
	p.y = d.y
	p.inventory["rinds"] = 0
	g.use_key = "E"
	_check(
		h.prompt(p) == "BLUE'S DOWN - HOLD E",
		"USE's prompt beside him names the key: '%s'" % h.prompt(p)
	)
	g.use_key = "Y"
	_check(h.prompt(p).ends_with("HOLD Y"), "and the pad's button: '%s'" % h.prompt(p))
	g.use_key = "E"
	var hold := Game.Controls.new()
	hold.hold = true
	_tick(g, roundi(60 * h.n("revive_time") * .5), hold)
	_check(
		d.state == Hound.DOWN and h.frame(d) == "v0" and HoundLooks._reviving(h) == d,
		"a hand on him: he comes up onto his chest (%s), GETTIN' BLUE UP" % h.frame(d)
	)
	var lay := HudLayout.new()
	lay.reset()
	h.hud_flow(lay)
	_check(lay.find("hound_revive").size.x > 0, "the revive bar takes its place on the HUD")
	_tick(g, roundi(60 * (h.n("revive_time") * .5 + .1)), hold)
	_check(d.state == Hound.FOLLOW and d.health > 0.0, "held USE beside him gets him up")
	_check(h.frame(d) == "u0", "getting up (%s)" % h.frame(d))
	_tick(g, roundi(60 * (HoundLooks.UP_TIME + .1)))
	_check(h.frame(d) == "k0", "and shaking it off (%s)" % h.frame(d))
	_tick(g, roundi(60 * HoundLooks.SHAKE_TIME))
	_check(h.frame(d) != "k0" and h.frame(d) != "u0", "then himself again (%s)" % h.frame(d))
	h.call("_hurt", d, 500.0, d.x + 1.0, d.y)
	_tick(g, 2)
	p.x = d.x + .5
	p.y = d.y
	p.inventory["rinds"] = 1
	_check(h.prompt(p).contains("RIND"), "with a rind: '%s'" % h.prompt(p))
	GameUse.interact(g)
	_check(
		d.state == Hound.FOLLOW and p.inventory["rinds"] == 0 and d.health == h.n("rind_health"),
		"a pork rind gets him up at once"
	)
	h.call("_hurt", d, 500.0, d.x + 1.0, d.y)
	p.x += 15.0
	_tick(g, roundi(60 * (h.n("get_up") + .5)))
	_check(d.state != Hound.DOWN and d.health > 0.0, "left down, he gets himself up: he never dies")
	_check(h.downs == 3 and h.revives == 3, "downs %d, ups %d" % [h.downs, h.revives])


func _whistle() -> void:
	var g := _game("hickston")
	_tick(g, 2)
	var d := _dog(g)
	var p := g.player
	p.angle = atan2(-1, 0) if g.world.blocked(p.x, p.y + 3, .2) else PI * .5
	p.pitch = 80.0
	g.hound_call()
	_check(d.state == Hound.STAY, "the whistle on nothing: STAY")
	var at := Vector2(d.x, d.y)
	var away := _spot(g, p.x, p.y, 6.0)
	_put_player(g, away, Vector2(away.x, away.y + 1.0))
	_tick(g, 60 * 2)
	_check(Vector2(d.x, d.y) == at and h_frame(g, d) == "sit", "staying he sits where he was")
	Replay.apply_op(g, ["hound"])
	_check(d.state == Hound.FOLLOW, "again (the replay's op): COME")
	var c := Game.Controls.new()
	c.item = Game.HOUND_CALL
	_tick(g, 1, c)
	_check(d.state == Hound.STAY, "the whistle as controls (online, a bot): STAY")
	_check(SessionStore.defaults().get("hound", -1) == 1, "HOUND DOG is a setting, on by default")
	var keyed := false
	for entry: Array in KeyBindings.ACTIONS:
		keyed = keyed or (entry[0] == "whistle" and entry[2] == KEY_G)
	_check(keyed, "WHISTLE FOR BLUE is a key (G)")


func h_frame(g: Game, d: Hound.Dog) -> String:
	return _hound(g).frame(d)


func _save() -> void:
	var g := _game("hickston")
	_tick(g, 2)
	var d := _dog(g)
	d.x += .25
	d.health = 40.0
	var kept := _hound(g).save()
	var g2 := _game("hickston")
	_hound(g2).restore(kept)
	var d2 := _dog(g2)
	_check(
		d2 != null and absf(d2.x - d.x) < .001 and d2.health == 40.0,
		"a save puts him back where he was, as hurt"
	)
	var g3 := _game("hickston")
	_hound(g3).restore({})
	_tick(g3, 2)
	_check(_dog(g3) != null, "a save from before him: a fresh hound")
	var store := SessionStore.snapshot(g)
	var feats: Dictionary = store.get("features", {})
	_check(feats.has("hound"), "the save's features block holds him")


func _coop() -> void:
	var g := _game("hickston")
	Modes.setup(g, Modes.COOP, 2)
	_tick(g, 2)
	var h := _hound(g)
	_check(
		h.dogs.size() == g.players.size() and g.players.size() == 2,
		"co-op: a hound each (%d)" % h.dogs.size()
	)
	var q: Player = g.players[1]
	var away := _spot(g, q.x, q.y, 6.0)
	q.x = away.x
	q.y = away.y
	q.flow.update(q.x, q.y, g.clock)
	_tick(g, 60 * 4)
	var d1 := _dog(g, 1)
	_check(
		Vector2(d1.x - q.x, d1.y - q.y).length() < 2.5, "player two's hound heels with player two"
	)
	var c := Game.Controls.new()
	c.item = Game.HOUND_CALL
	g.tick(STEP, {1: c})
	_check(
		d1.state != Hound.FOLLOW and _dog(g, 0).state == Hound.FOLLOW,
		"player two's whistle is for their own hound (%d, %d)" % [d1.state, _dog(g, 0).state]
	)


func _net() -> void:
	var a := _game("hickston", true, true)
	var b := _game("hickston", true, true)
	var pilot := Pilot.new()
	pilot.as_controls = true
	var split := -1
	for t in 60 * 30:
		var c := pilot.steer(a)
		if t % 400 == 200:
			c.item = Game.HOUND_CALL
		a.tick(STEP, c)
		b.tick(STEP, c)
		pilot.moved(a)
		if split < 0 and (t + 1) % 300 == 0:
			if not GameSnapshot.same(GameSnapshot.capture(a), GameSnapshot.capture(b)):
				split = t + 1
	_check(
		split < 0,
		(
			"two games fed the same controls stay identical with BLUE about%s"
			% ("" if split < 0 else " (part by %d)" % split)
		)
	)
	var snap := GameSnapshot.capture(a)
	var unknown: Array = snap["unknown"]
	_check(unknown.is_empty(), "the snapshot knows his classes %s" % [unknown])
	var feats: Dictionary = snap["features"]
	_check(feats.has("hound"), "the snapshot carries him")
	var c2 := _game("hickston", true, true)
	var applied := GameSnapshot.apply(c2, snap)
	var where := GameSnapshot.first_difference(snap, GameSnapshot.capture(c2))
	_check(applied and where == "", "a snapshot put on a fresh game comes back the same %s" % where)
	var parted := -1
	for t in 60 * 10:
		var c := pilot.steer(a)
		if t == 100:
			c.item = Game.HOUND_CALL
		a.tick(STEP, c)
		c2.tick(STEP, c)
		pilot.moved(a)
	if not GameSnapshot.same(GameSnapshot.capture(a), GameSnapshot.capture(c2)):
		parted = 1
	_check(parted < 0, "the copy runs on the same as the game it came from")


func _looks() -> void:
	var g := _game("hickston")
	_tick(g, 2)
	var h := _hound(g)
	var d := _dog(g)
	var art: Assets = main.art
	for frame: String in [
		"0",
		"wag",
		"w0",
		"r0",
		"sit",
		"bark",
		"bay",
		"bite",
		"pin",
		"pin2",
		"fetch",
		"point",
		"sniff",
		"pain",
		"down",
		"whine"
	]:
		_check(art.has_art("hound_" + frame), "hound_%s is drawn" % frame)
	for face: String in ["0", "1", "2", "down"]:
		_check(art.has_art("hound_face_" + face), "his badge's head hound_face_%s" % face)
	_check(art.has_art("actor3d_hound"), "his model's look is packed")
	g.player.angle = atan2(d.y - g.player.y, d.x - g.player.x)
	var shown := false
	for s: View.Sprite in h.sprites():
		shown = shown or (s.who is Enemy and (s.who as Enemy).kind == "hound")
	_check(shown, "he is in the view as his model's stand-in")
	var c := Canvas.new()
	h.draw_view(c)
	var lit := 0
	for yy in range(View.VIEW - 30, View.VIEW - 2):
		for xx in range(3, 50):
			var o := (yy * Canvas.WIDTH + xx) * 3
			if c.pixels[o] + c.pixels[o + 1] + c.pixels[o + 2] > 30:
				lit += 1
	_check(lit > 600, "his badge is drawn in the view's corner (%d pixels)" % lit)
	var wide := 0
	for yy in range(View.VIEW - 30, View.VIEW - 2):
		for xx in range(60, HoundLooks.BADGE_X + HoundLooks.BADGE_W - 2):
			var o := (yy * Canvas.WIDTH + xx) * 3
			if c.pixels[o] + c.pixels[o + 1] + c.pixels[o + 2] > 200:
				wide += 1
	_check(wide > 12, "his mood and health reach across the badge (%d pixels)" % wide)
	var rows := h.tally_rows()
	_check(rows.is_empty(), "no tally row before he has done anything")


## Every state and moment shows its own pose, each a frame of his model.
func _poses() -> void:
	var g := _game("hickston")
	_tick(g, 2)
	var h := _hound(g)
	var d := _dog(g)
	var rng_before: int = g.rng.state
	var models: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://assets3d/actors/actors.json")
	)
	var frames: Dictionary = models["hound"]["frames"]
	# A moment out of his tracking and idle rounds (HoundLooks: TRACK_ROUND,
	# IDLE_ROUND): plain heel.
	g.clock = 13.0
	var want := func(text: String, frame: String) -> void:
		var now := h.frame(d)
		_check(now == frame, "%s: %s (%s)" % [text, frame, now])
		_check(frames.has(now), "%s: his model has frame %s" % [text, now])
	d.hurt_at = -10.0
	d.state = Hound.FOLLOW
	d.item = ""
	d.health = h.n("health")
	for pace: Array in [[1.0, "w0"], [2.6, "t0"], [7.4, "r0"]]:
		d.pace = pace[0]
		want.call("pace %.1f" % pace[0], pace[1])
	d.health = h.n("health") * .2
	d.pace = 2.6
	want.call("sore at a trot", "l0")
	d.pace = 0.0
	want.call("sore, standing", "l0")
	d.health = h.n("health")
	d.state = Hound.BAY
	d.since = g.clock
	d.bark_at = g.clock - 1.0
	d.pace = 1.0
	want.call("tracking to a secret", "n0")
	d.pace = 0.0
	d.bark_at = g.clock
	want.call("baying (the howl)", "bay")
	d.state = Hound.POINT
	want.call("on point", "point")
	d.state = Hound.PIN
	want.call("holding a hand", "p0")
	d.state = Hound.SIC
	d.bite_at = g.clock + .1
	want.call("about to bite", "j0")
	d.bite_at = g.clock + h.n("bite_every") - .1
	want.call("just bitten", "j0")
	d.bite_at = g.clock + .3
	want.call("between bites", "bark")
	d.state = Hound.STAY
	d.since = g.clock
	want.call("told to STAY", "sit")
	d.since = g.clock - HoundLooks.LIE_AFTER - 1.0
	want.call("staying long", "rest")
	d.state = Hound.CARRY
	want.call("carrying", "fetch")
	d.state = Hound.FOLLOW
	d.hurt_at = g.clock
	want.call("kicked", "pain")
	d.hurt_at = -10.0
	d.bark_at = -10.0
	# Now and then at heel he tracks, nose down.
	g.clock = HoundLooks.TRACK_ROUND * 3.0 + 1.0
	d.pace = 1.0
	want.call("tracking at heel", "n0")
	d.pace = 0.0
	g.clock = 13.0
	# Idle: the wag, and in his round a scratch and a sniff.
	var idle := {}
	var clock := g.clock
	for t in 300:
		g.clock = clock + t * .1
		idle[h.frame(d)] = true
	g.clock = clock
	for frame: String in ["i0", "c0", "sniff"]:
		_check(idle.has(frame), "idle at heel he shows %s now and then (%s)" % [frame, idle.keys()])
	for frame: String in idle:
		_check(frames.has(frame), "idle: his model has frame %s" % frame)
	_check(g.rng.state == rng_before, "his poses never draw on game.rng")


## The badge's words, the markers, the point's brackets.
func _feedback() -> void:
	var g := _game("hickston")
	_tick(g, 2)
	var h := _hound(g)
	var d := _dog(g)
	var p := g.player
	g.clock = 13.0
	d.state = Hound.FOLLOW
	_check(HoundLooks.job(h, d) == "HEELIN'", "job at heel: %s" % HoundLooks.job(h, d))
	_check(str(HoundLooks.mood(h, d)[0]) == "HAPPY", "mood at heel: %s" % HoundLooks.mood(h, d)[0])
	d.state = Hound.POINT
	_check(HoundLooks.job(h, d) == "POINTIN'", "job on point: %s" % HoundLooks.job(h, d))
	_check(str(HoundLooks.mood(h, d)[0]) == "KEEN", "mood on point: %s" % HoundLooks.mood(h, d)[0])
	d.state = Hound.PIN
	_check(HoundLooks.job(h, d) == "HOLDIN'", "job holding: %s" % HoundLooks.job(h, d))
	_check(str(HoundLooks.mood(h, d)[0]) == "RILED", "mood holding: %s" % HoundLooks.mood(h, d)[0])
	d.state = Hound.DOWN
	_check(HoundLooks.job(h, d) == "DOWN!", "job down: %s" % HoundLooks.job(h, d))
	d.state = Hound.FOLLOW
	d.health = h.n("health") * .2
	_check(HoundLooks.job(h, d) == "LIMPIN'", "job sore: %s" % HoundLooks.job(h, d))
	_check(str(HoundLooks.mood(h, d)[0]) == "SORE", "mood sore: %s" % HoundLooks.mood(h, d)[0])
	d.health = h.n("health")
	var room := HoundLooks.BADGE_W - HoundLooks.FACE - 9
	for word: String in HoundLooks.JOBS + ["SNIFFIN'", "LIMPIN'", "LAYIN' UP", "UP AGIN"]:
		_check(PixelType.text_width(word, "mini") <= room, "%s fits the badge" % word)
	for feel: String in ["HAPPY", "KEEN", "RILED", "SORE", "FRETTIN'", "PATIENT", "WHIPPED"]:
		_check(PixelType.text_width(feel, "mini") <= room, "%s fits the badge's top row" % feel)
	# The marker: none in plain sight, one over him behind a wall, one at
	# the view's edge when he is off it.
	var at := _spot(g, p.x, p.y, 5.0)
	_put_dog(g, d, at)
	var look := atan2(d.y - p.y, d.x - p.x)
	g.view_eye = {
		"x": p.x, "y": p.y, "eye": p.eye, "view_angle": look, "pitch": 0.0, "bob": 0.0, "sway": 0.0
	}
	_check(HoundLooks.in_sight(g, d), "he is in plain sight")
	_check(HoundLooks.marker_at(g, d).is_empty(), "no marker on him in plain sight")
	g.view_eye["view_angle"] = look + PI
	var edge := HoundLooks.marker_at(g, d)
	_check(edge.size() == 3, "behind the eye: a marker at the view's edge")
	var hidden := _hidden_spot(g, p)
	if hidden != Vector2.INF:
		_put_dog(g, d, hidden)
		g.view_eye["view_angle"] = atan2(d.y - p.y, d.x - p.x)
		var over := HoundLooks.marker_at(g, d)
		_check(
			not HoundLooks.in_sight(g, d) and over.size() == 3 and absf(float(over[2])) < .01,
			"behind a wall in the view: a marker over him, pointing down (%s)" % str(over)
		)
	else:
		_check(false, "no spot behind a wall near the start to try the marker")
	# On point: brackets on what he points at.
	_put_dog(g, d, at)
	var target := Vector2(p.x, p.y).lerp(at, .5)
	d.state = Hound.POINT
	d.since = g.clock - 1.0
	d.bark_at = g.clock
	d.look = target
	g.view_eye["view_angle"] = atan2(target.y - p.y, target.x - p.x)
	var c := Canvas.new()
	HoundLooks._point_mark(h, c, d)
	var mark := 0
	for i in range(0, c.pixels.size(), 3):
		if c.pixels[i] > 150 and c.pixels[i + 1] > 110:
			mark += 1
	_check(mark > 10, "on point, brackets on what he points at (%d pixels)" % mark)


## A spot near the player that a wall hides from them, or INF.
func _hidden_spot(g: Game, p: Player) -> Vector2:
	for r: float in [4.0, 6.0, 8.0, 10.0]:
		for k in 24:
			var a := k * TAU / 24.0
			var x := p.x + cos(a) * r
			var y := p.y + sin(a) * r
			if g.world.blocked(x, y, .25) or g.world.deep_at(x, y):
				continue
			var z := g.world.floor_under(x, y, g.world.stand(p) + .4)
			if not g.world.visible(p.x, p.y, x, y, p.eye, z + .5):
				return Vector2(x, y)
	return Vector2.INF


## `-- play=<level>`: the campaign bot plays a chapter for two minutes with
## BLUE along (not mortal: god), and what he did is printed (tuning by eye).
func _play(id: String) -> void:
	var g := _game(id, true, true)
	var pilot := Pilot.new()
	pilot.as_controls = true
	var h := _hound(g)
	var states := {}
	var lag := 0.0
	for t in 60 * 120:
		var c := pilot.steer(g)
		g.tick(STEP, c)
		pilot.moved(g)
		var d := _dog(g)
		if d != null:
			states[d.state] = int(states.get(d.state, 0)) + 1
			lag = maxf(lag, Vector2(d.x - g.player.x, d.y - g.player.y).length())
	print(
		(
			(
				"%s: kills %d, bays %d, points %d, bites %d, pins %d, finished %d,"
				+ " fetches %d, kicks %d, downs %d, ups %d"
			)
			% [
				id,
				g.kills,
				h.bays,
				h.points,
				h.bites,
				h.pins,
				h.finished,
				h.fetches,
				h.kicks,
				h.downs,
				h.revives
			]
		)
	)
	print("  ticks by state %s, the most he fell behind %.1f" % [states, lag])
