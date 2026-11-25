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
## Pass 10: LEGS: he ranges out and circles back, steps out of the sights,
## goes round a hazard, lets go of a fight badly hurt, keeps clear of a boss
## winding up, rides in a free seat and hops out for a partner. MOODS: he
## sulks shot near, howls at the twister's siren and cowers from it, growls
## at a hand round a corner, wags round a still. VOICE: he pants after a run
## and shakes off back on his feet; his barks dealt at random, never twice
## running. tools/hound_walk_check.gd walks every chapter with him.
## Pass 15: LEAD: a player held still away from the objective 30 s and he
## goes onto the way ahead within 3 s, out of the line of fire, points and
## barks, Mundell says it once, the tip; he goes on as they come, a fight
## or getting back on the way ends it, never in a fight; a snapshot carries
## the job; with HOUND DOG off the pin pulses and Mundell says his line.
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
	# The hound's own moves on hands the check stands where it wants them: the
	# fight-rhythm director (pass 15) would hold some back, send others in
	# and keep far ones still; its own check is director_check.gd.
	DirectorData.ON = false
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
		"feedback",
		"legs",
		"moods",
		"voice",
		"lead"
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
	_check(
		d.state == Hound.GREET and d.health > 0.0 and d.goal_uid == p.slot,
		"held USE beside him gets him up, and he greets his helper"
	)
	_check(h.frame(d) == "u0", "getting up (%s)" % h.frame(d))
	_tick(g, roundi(60 * (HoundLooks.UP_TIME + .1)))
	_check(h.frame(d) == "k0", "and shaking it off (%s)" % h.frame(d))
	_tick(g, roundi(60 * HoundLooks.SHAKE_TIME))
	_check(h.frame(d) != "k0" and h.frame(d) != "u0", "then himself again (%s)" % h.frame(d))
	_tick(g, roundi(60 * h.n("greet_for")))
	_check(d.state == Hound.FOLLOW, "the greeting done, he goes with his player again")
	h.call("_hurt", d, 500.0, d.x + 1.0, d.y)
	_tick(g, 2)
	p.x = d.x + .5
	p.y = d.y
	p.inventory["rinds"] = 1
	_check(h.prompt(p).contains("RIND"), "with a rind: '%s'" % h.prompt(p))
	GameUse.interact(g)
	_check(
		d.state == Hound.GREET and p.inventory["rinds"] == 0 and d.health == h.n("rind_health"),
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
		Vector2(d1.x - q.x, d1.y - q.y).length() < h.n("range_far") + 1.0,
		"player two's hound goes with player two"
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
	# (pass 12: by how fast his legs go, Dog.stride_v, in the gait it holds)
	var legs := func(v: float) -> void:
		d.stride_v = v
		d.gait_kind = HoundLooks.gait_of(-1, v)
		d.still_at = g.clock
	for pace: Array in [[1.0, "w0"], [2.0, "t0"], [4.0, "r0"]]:
		legs.call(pace[0])
		want.call("pace %.1f" % pace[0], pace[1])
	d.health = h.n("health") * .2
	legs.call(2.0)
	want.call("sore at a trot", "l0")
	legs.call(0.0)
	want.call("sore, standing", "l0")
	d.health = h.n("health")
	d.state = Hound.BAY
	d.since = g.clock
	d.bark_at = g.clock - 1.0
	legs.call(1.0)
	want.call("tracking to a secret", "n0")
	legs.call(0.0)
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
	legs.call(1.0)
	want.call("tracking at heel", "n0")
	legs.call(0.0)
	g.clock = 13.0
	# Idle: the wag, and in his round a scratch and a sniff.
	var idle := {}
	var clock := g.clock
	for t in 300:
		g.clock = clock + t * .1
		d.still_at = g.clock - 2.0  # stood a moment, not yet settled
		idle[h.frame(d)] = true
	g.clock = clock
	# Pass 12: by his player standing he settles: sits, then lies down; just
	# stopped, no idle round's scratch flashes up.
	d.p_v = Vector2.ZERO
	d.still_at = g.clock - HoundLooks.SIT_AFTER - .5
	want.call("settled by his player", "sit")
	d.still_at = g.clock - HoundLooks.LIE_DOWN_AFTER - .5
	want.call("settled a good while", "rest")
	d.p_v = Vector2(2.0, 0.0)
	want.call("his player walking, he does not sit", "i0")
	d.p_v = Vector2.ZERO
	d.still_at = g.clock
	var round_at := fmod(g.clock + d.slot * 5.1, HoundLooks.IDLE_ROUND)
	g.clock += HoundLooks.IDLE_ROUND - round_at + .2  # in his round's scratch
	d.still_at = g.clock - .3
	want.call("just stopped, no scratch yet", "i0")
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
	_check(str(HoundLooks.mood(h, d)[0]) == "EASY", "mood at heel: %s" % HoundLooks.mood(h, d)[0])
	d.mood = Hound.SULK
	d.job = Hound.TRAIL
	_check(
		str(HoundLooks.mood(h, d)[0]) == "SULKIN'" and HoundLooks.job(h, d) == "TRAILIN'",
		"his mood and job from play: %s, %s" % [HoundLooks.mood(h, d)[0], HoundLooks.job(h, d)]
	)
	d.mood = Hound.CALM
	d.job = Hound.HEEL
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
	var words: Array = HoundLooks.JOBS + HoundLooks.FOLLOW_JOBS
	for word: String in words + ["SNIFFIN'", "LIMPIN'", "LAYIN' UP", "UP AGIN"]:
		_check(PixelType.text_width(word, "mini") <= room, "%s fits the badge" % word)
	for feel: String in HoundLooks.MOOD_WORDS + ["KEEN", "FRETTIN'", "PATIENT", "WHIPPED"]:
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


# ------------------------------------------------------- pass 10: his legs


## Calm, his player standing: he ranges out to one side and comes back; in
## a player's sights he steps out of them; he never stands in harm; badly
## hurt he lets go of a fight; a boss winding up is harm; a free seat beside
## his player at the wheel and he rides, and hops out when a partner takes it.
func _legs() -> void:
	var g := _game("hickston")
	_tick(g, 2)
	var h := _hound(g)
	var d := _dog(g)
	var p := g.player
	var open := _spot(g, p.x, p.y, 6.0)
	_put_player(g, open, open + Vector2(4.0, 0.0))
	_put_dog(g, d, open - Vector2(1.2, 0.0))
	# Pass 12: by his player standing he settles first, a good while.
	var settled := true
	for t in 60 * 6:
		g.tick(STEP, Game.Controls.new())
		settled = settled and d.job == Hound.HEEL
	_check(settled, "by his player standing he settles, no ranging straight off")
	h._n["range_rest_still"] = 0.0  # (then he ranges round them)
	var ranged := 0.0
	var jobs := {}
	var faced_out := true
	for t in 60 * 14:
		g.tick(STEP, Game.Controls.new())
		jobs[d.job] = true
		ranged = maxf(ranged, Vector2(d.x - p.x, d.y - p.y).length())
		if d.job == Hound.RANGE and HoundLegs.before_sights(g, d.roam.x, d.roam.y, 10.0, .93):
			faced_out = false
	_check(
		jobs.has(Hound.RANGE) and jobs.has(Hound.CIRCLE) and ranged > 2.0,
		"calm, he ranges out (%.1f cells) and circles back (jobs %s)" % [ranged, jobs.keys()]
	)
	_check(faced_out, "he never ranges to a spot in his player's sights")
	_check(
		Vector2(d.x - p.x, d.y - p.y).length() < h.n("range_far") + 1.0, "and stays with his player"
	)
	# In the sights: out of them within a second.
	var aim := Vector2(d.x - p.x, d.y - p.y).angle()
	p.angle = aim
	var out_at := -1.0
	for t in 60 * 2:
		g.tick(STEP, Game.Controls.new())
		p.angle = aim
		if (
			out_at < 0.0
			and HoundLegs.in_sights(g, d, h.n("clear_reach"), h.n("clear_cone")) == null
		):
			out_at = t * STEP
	_check(
		out_at >= 0.0 and out_at < 1.0 and h.asides > 0,
		"aimed at, he steps out of the sights (%.2f s)" % out_at
	)
	# Harm: a hazard prop between him and his heel never has him.
	var g2 := _game("moonshine")
	_tick(g2, 2)
	var h2 := _hound(g2)
	var d2 := _dog(g2)
	var harms := HoundLegs.harms_of(g2, 0.0)
	var tested := false
	for c: Vector3 in harms:
		var side_a := _spot(g2, c.x + c.z + 2.0, c.y, 1.5)
		if side_a == Vector2.INF:
			continue
		var side_b := Vector2(c.x - (side_a.x - c.x), c.y - (side_a.y - c.y))
		if g2.world.blocked(side_b.x, side_b.y, .35):
			continue
		_put_player(g2, side_b, Vector2(c.x, c.y))
		_put_dog(g2, d2, side_a)
		var hit := false
		for t in 60 * 5:
			g2.tick(STEP, Game.Controls.new())
			hit = hit or Vector2(d2.x - c.x, d2.y - c.y).length() < c.z
		_check(
			not hit,
			"a hazard between him and his player: he goes round it (%.1f,%.1f)" % [c.x, c.y]
		)
		tested = true
		break
	_check(tested, "moonshine has a hazard to go round")
	_check(not HoundLegs.harm(g2, [], d2.x, d2.y), "he stands clear of harm")
	# Badly hurt in a fight: he lets go and keeps behind his player.
	var g3 := _game("hickston", true, true)
	_tick(g3, 2)
	var d3 := _dog(g3)
	var e := _foe(g3, _spot(g3, g3.player.x, g3.player.y, 3.0))
	if e != null:
		_hound(g3).call("_sic", d3, e, true)
		d3.health = _hound(g3).n("health") * _hound(g3).n("back_off") * .5
		_tick(g3, 3)
		_check(
			d3.state == Hound.FOLLOW and d3.mood == Hound.HURT and _hound(g3).backed_off == 1,
			"badly hurt, he lets go of the fight and keeps back (mood %s)" % Hound.MOODS[d3.mood]
		)
	# A boss winding up: where it aims is harm, and so is the way to it.
	var g4 := _game("quarry", true, true)
	var boss: Enemy = null
	for b: Enemy in g4.enemies:
		if Enemy.BOSS_TITLES.has(b.kind):
			boss = b
	if boss != null:
		boss.dormant = false
		boss.windup = .6
		boss.aim_mark = [boss.x + 5.0, boss.y, 0.0]
		var danger := HoundLegs.dangers(g4, [], 2.2, [boss])
		_check(
			(
				HoundLegs.harm(g4, danger, boss.x + 5.0, boss.y)
				and HoundLegs.harm(g4, danger, boss.x + 2.5, boss.y)
			),
			"a boss winding up: where it aims and the way there are harm"
		)
	_ride_seat()


## A free seat beside his player at the wheel: he gets in and rides; a
## partner taking the seat has him hop out.
func _ride_seat() -> void:
	var g := _game("speedway")
	Modes.setup(g, Modes.COOP, 2)
	_tick(g, 2)
	var rides: Game.VehiclesScript = g.features.get("vehicles")
	var d := _dog(g)
	var p := g.player
	if not rides.seat_in(p, 0):
		_check(false, "speedway: the player takes the car's wheel")
		return
	var v: VehicleDrive.Ride = rides.rides[0]
	_put_dog(g, d, Vector2(v.x - cos(v.h) * 2.2, v.y - sin(v.h) * 2.2))
	_tick(g, 60)
	_check(d.state == Hound.RIDE and d.ride == 0, "he gets in the seat beside his player")
	var seat := HoundLegs.seat_at(v)
	_check(Vector2(d.x - seat.x, d.y - seat.y).length() < .05, "and sits in it")
	var q: Player = g.players[1]
	v.seats[1] = q.slot
	_tick(g, 30)
	_check(d.state != Hound.RIDE and d.ride < 0, "a partner takes the seat: he hops out")
	v.seats[1] = -1


# ------------------------------------------------------- pass 10: his moods


## Shot near: he sulks behind. A siren: he howls. A twister: he cowers. A
## hand awake round a corner: he growls. A still: he wags round it.
func _moods() -> void:
	var g := _game("hickston")
	_tick(g, 2)
	var h := _hound(g)
	var d := _dog(g)
	var p := g.player
	var open := _spot(g, p.x, p.y, 5.0)
	_put_player(g, Vector2(p.x, p.y), open)
	_put_dog(g, d, Vector2(p.x, p.y).lerp(open, .5))
	p.angle = atan2(d.y - p.y, d.x - p.x)
	g.events.shot_fired.emit(Weapons.NAMES.find("shotgun"))
	_check(
		d.mood == Hound.SULK and d.job == Hound.TRAIL and h.sulks == 1,
		"a shot close by him: he sulks, trailing behind"
	)
	_tick(g, roundi(60 * (h.n("sulk_for") + .5)))
	_check(d.mood == Hound.CALM, "and gets over it")
	# A siren: the twister's warning.
	var g2 := _game("hickston")
	_tick(g2, 2)
	var h2 := _hound(g2)
	h2._n["howl_chance"] = 1.0
	var ev: CountyEvents = g2.features.get("events")
	var began := ev != null and ev.begin("twister")
	var howled := false
	var cowered := false
	for t in 60 * 30:
		g2.tick(STEP, Game.Controls.new())
		howled = howled or _dog(g2).state == Hound.HOWL
		cowered = cowered or _dog(g2).state == Hound.COWER
		if cowered and howled:
			break
	_check(began and howled and h2.howls > 0, "the twister's siren: he howls")
	_check(cowered and h2.cowers > 0, "the twister near: he cowers at his player's side")
	# A hand awake his player cannot see.
	var g3 := _game("hickston", true, true)
	_tick(g3, 2)
	var d3 := _dog(g3)
	var p3 := g3.player
	var hid := _hidden_pair(g3, p3)
	var growled := false
	if not hid.is_empty():
		var e := _foe(g3, hid[1])
		if e != null:
			e.alerted = false
			e.stun = 9.0
			_put_dog(g3, d3, hid[0])
			for t in 60 * 3:
				g3.tick(STEP, Game.Controls.new())
				e.x = hid[1].x
				e.y = hid[1].y
				growled = growled or d3.state == Hound.GROWL
	_check(growled and _hound(g3).warned.size() == 1, "a hand round the corner: he growls at it")
	# A still: he wags round it.
	var g4 := _game("hickston")
	_tick(g4, 2)
	var d4 := _dog(g4)
	var still := Vector2.INF
	for board: LevelData.Billboard in g4.world.billboards:
		if HoundNose.TREATS.has(board.image):
			still = Vector2(board.x, board.y)
	var wagged := false
	var stand := _spot(g4, still.x, still.y, 3.0) if still != Vector2.INF else Vector2.INF
	if stand != Vector2.INF:
		_put_player(g4, stand, still + (still - stand))
		_put_dog(g4, d4, stand.lerp(still, .3))
		for door: LevelData.Door in g4.world.doors:
			_hound(g4).bayed[HoundNose.key(Vector2(door.x + .5, door.y + .5))] = 0.0
		for t in 60 * 5:
			g4.tick(STEP, Game.Controls.new())
			wagged = wagged or _hound(g4).treats > 0
	_check(wagged, "a moonshine still: he wags round it")


## His own noises (features/hound_voice.gd): a pant after a run, a shake
## back on his feet; the takes of a set dealt at random, never the same
## twice running.
func _voice() -> void:
	var g := _game("hickston")
	_tick(g, 2)
	var voice: GameFeature = g.features.get("hound_voice")
	_check(voice != null, "his voice is a looks feature of the game")
	_check(GameSnapshot.LOOKS_FEATURES.has("hound_voice"), "and never carried")
	var d := _dog(g)
	d.pace = 7.0
	for t in 60 * 4:
		d.pace = 7.0
		voice.call("_tick", STEP)
	d.pace = 0.0
	voice.call("_tick", STEP)
	_check(voice.call("panting", d.slot), "after a run he pants")
	var h := _hound(g)
	h.call("_hurt", d, 500.0, d.x + 1.0, d.y)
	voice.call("_tick", STEP)
	h.call("_up", d, 50.0, null)
	voice.call("_tick", STEP)
	_check(voice.call("shaking", d.slot), "back on his feet he shakes himself off")
	var s: Sound = main.sound
	var gain := s.effects_gain
	s.effects_gain = 1.0
	var takes := {}
	var twice := 0
	var last := -1
	for k in 60:
		s.play("hound_bark", .01)
		var took: int = s.variations["hound_bark"] - 1
		twice += 1 if took == last else 0
		last = took
		takes[took] = true
	s.effects_gain = gain
	_check(
		twice == 0 and takes.size() >= 4,
		"his barks dealt at random (%d takes), never the same twice running" % takes.size()
	)


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


# ------------------------------------------------------------------ pass 15


## A game with its hands kept but every one asleep but the bosses and
## Bessie (calm, the objective as the level has it, and a hand to wake).
func _calm_game(hound := true) -> Game:
	var g := _game("hickston", hound, true)
	for e: Enemy in g.enemies:
		if not Enemy.BOSS_TITLES.has(e.kind) and e != g.bessie and e.hostile:
			e.dormant = true
	return g


## One of the sleeping hands woken at `at`, after the player.
func _wake_one(g: Game, at: Vector2) -> Enemy:
	for e: Enemy in g.enemies:
		if e.dormant and e.hostile and not e.swims and e.tactical():
			e.dormant = false
			e.x = at.x
			e.y = at.y
			e.floor_z = g.world.elevation(at.x, at.y)
			e.alerted = true
			e.mind = null
			return e
	return null


func _lead() -> void:
	var g := _calm_game()
	_tick(g, 2)
	var h := _hound(g)
	var d := _dog(g)
	var p := g.player
	var lead := HoundLead.of(h)
	var start := lead.steps_at(g, p)
	_check(
		start > 20 and start < FlowField.FAR,
		"the way to the objective is walked (%d steps)" % start
	)
	var led_at := -1.0
	while g.clock < 31.5:
		_tick(g, 1)
		if led_at < 0.0 and d.job == Hound.LEAD:
			led_at = g.clock
	_check(
		led_at >= HoundLead.n("lead_after") and led_at <= 31.5,
		"held still and no nearer for 30 s, BLUE takes the lead (at %.1f s)" % led_at
	)
	while g.clock < led_at + 3.0:
		_tick(g, 1)
	var ahead := lead.field.distance(d.x, d.y, d.floor_z)
	_check(
		d.job == Hound.LEAD and ahead < start - 3,
		"within 3 s he is on the way ahead (%d steps from it to his %d)" % [start, ahead]
	)
	var arrived := -1.0
	while g.clock < led_at + 6.0:
		_tick(g, 1)
		if arrived < 0.0 and d.job == Hound.LEAD and d.until > 0.0:
			arrived = g.clock
	var his := lead.field.distance(d.x, d.y, d.floor_z)
	_check(
		arrived > 0.0 and his < start and his >= start - 12,
		"he stops down it (%d steps, %.1f s after he set off)" % [his, arrived - led_at]
	)
	_check(
		HoundLegs.in_sights(g, d, h.n("clear_reach"), h.n("clear_cone")) == null,
		"his stop is out of the line of fire"
	)
	var frame: String = HoundLooks.pose(h, d)[0]
	_check(frame == "point" or frame == "bark", "he points the way (%s)" % frame)
	_check(HoundLooks.job(h, d) == "LEADIN'", "the badge says LEADIN' (%s)" % HoundLooks.job(h, d))
	_check(g.barks.last_at.has("lost"), "Mundell says his word once")
	_check(Lessons.words(g, "lead") == "BLUE'LL SHOW YA. FOLLOW HIM.", "the tip's words")
	# Snapshot mid-lead onto a fresh game: both go on alike.
	var snap := GameSnapshot.capture(g)
	var copy := _calm_game()
	GameSnapshot.apply(copy, snap)
	var cd := _dog(copy)
	_check(cd != null and cd.job == Hound.LEAD, "a snapshot carries the job")
	var near := Vector2(d.x, d.y) + (Vector2(p.x, p.y) - Vector2(d.x, d.y)).normalized() * 1.2
	var was_goal := d.goal
	for game: Game in [g, copy]:
		Modes.place(game, game.player, near.x, near.y, game.player.angle)
	var parted := false
	for t in 60 * 3:
		_tick(g, 1)
		_tick(copy, 1)
		var a := _dog(g)
		var b := _dog(copy)
		if absf(a.x - b.x) + absf(a.y - b.y) > .0001 or a.job != b.job:
			parted = true
	_check(not parted, "the copy and the game lead alike")
	var further := (
		lead.field.distance(d.goal.x, d.goal.y, d.floor_z) if d.goal != Vector2.INF else 0
	)
	_check(
		d.job == Hound.LEAD and d.goal != was_goal and further < his,
		"his player come near, he goes on another stretch (%d steps left at it)" % further
	)
	# A hand awake near ends it, within a look.
	var foe := _wake_one(g, Vector2(p.x + 3.0, p.y))
	foe.stun = 10.0
	_tick(g, 40)
	_check(d.job != Hound.LEAD, "a hand awake near ends it")
	# Never in a fight: a hand on the player the whole time, no lead.
	var f2 := _calm_game()
	_tick(f2, 2)
	var awake := _wake_one(f2, Vector2(f2.player.x + 4.0, f2.player.y))
	var ever := false
	while f2.clock < 34.0:
		awake.stun = 1.0
		awake.hp = awake.max_hp
		_tick(f2, 1)
		if _dog(f2).job == Hound.LEAD:
			ever = true
	_check(not ever, "never with a hand awake near (a fight)")
	# Back on the way: the player taken well down it ends it.
	var g3 := _calm_game()
	_tick(g3, 2)
	var l3 := HoundLead.of(_hound(g3))
	while g3.clock < 32.0:
		_tick(g3, 1)
	var d3 := _dog(g3)
	var on := l3.field.waypoint(g3.player.x, g3.player.y, int(HoundLead.n("lead_gain")) + 3)
	Modes.place(g3, g3.player, on.x, on.y, g3.player.angle)
	_tick(g3, 40)
	_check(
		d3.job != Hound.LEAD and d3.lead_best >= 0,
		"getting back on the way ends it (%d steps now)" % d3.lead_best
	)
	# Co-op: each hound leads his own player, down his own player's way.
	var g5 := _calm_game()
	Modes.setup(g5, Modes.COOP, 2)
	_tick(g5, 2)
	var q5: Player = g5.players[1]
	var away := _spot(g5, q5.x, q5.y, 6.0)
	# (each looking away from the other: a partner's sights send a hound aside)
	var p5: Player = g5.players[0]
	var apart := atan2(away.y - p5.y, away.x - p5.x)
	Modes.place(g5, q5, away.x, away.y, apart)
	Modes.place(g5, p5, p5.x, p5.y, apart + PI)
	var l5 := HoundLead.of(_hound(g5))
	while g5.clock < 36.0:
		_tick(g5, 1)
	var both := true
	for slot in 2:
		var dg := _dog(g5, slot)
		var pl: Player = g5.players[slot]
		var mine := l5.field.distance(dg.x, dg.y, dg.floor_z)
		var theirs := l5.field.distance(pl.x, pl.y, g5.world.stand(pl))
		if dg.job != Hound.LEAD or mine >= theirs:
			both = false
		elif Vector2(dg.x - pl.x, dg.y - pl.y).length() > HoundLead.n("lead_reach") + 3.0:
			both = false
	_check(both, "co-op: each hound leads his own player")
	# HOUND DOG off: the pin pulses and Mundell says his line.
	var g4 := _calm_game(false)
	_tick(g4, 2)
	var pulsed := false
	while g4.clock < 33.0:
		_tick(g4, 1)
		if HoundLead.pulse(g4) > 0.0:
			pulsed = true
	_check(pulsed, "with HOUND DOG off the pin pulses once stuck")
	_check(g4.barks.last_at.has("lost_pin"), "and Mundell says the pin's line")
