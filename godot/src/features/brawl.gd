## Dirty fighting (content pass 8): the boot, the finishers and the county's
## own hazards. Numbers in hits.cfg [kick], [finish], [finish.<move>],
## [hazard] and [hazard.<kind>].
##
## - **The boot.** USE with one of the county's hands in front of you (Game
##   interact(), before anything else USE does) puts a boot in him: a moment
##   later he takes a little damage, is stunned and dazed, and slides back
##   along your aim, slowing. Into a wall hard he slams (more damage), into
##   another man that one goes too, off a drop he falls and takes the fall,
##   into a hazard (below) he dies by it. Running at a plain shut door, USE
##   kicks it in: it slams open at once and whoever stands behind it is thrown
##   back. A boss takes a little and slides a little.
## - **Finishers.** USE (or a swing of a blade or the crowbar) on a hand in
##   reach who is low, reeling or dazed starts a short move picked by the gun
##   in hand (pistol whip or a round in the mouth; a butt stroke or a belly
##   full of lead; the crowbar to the skull or gutting; else a boot to the
##   face or a punt): the blow lands `wind` later, alone in slow motion, with gore, a
##   call on screen and Mundell's word on it (barks "finisher"). Bosses are
##   never finished. features/brawl_looks.gd shows the boot and the blows.
## - **Hazards** (src/brawl_hazards.gd): a man driven into a saw, a chipper,
##   a bug zapper, a hot fence, a burn barrel, a well, a cattle guard, a
##   crusher, deep or running water or among the hogs dies the way it kills.
##   A man walking about never is (they step round them). A boss takes
##   [hazard] `boss_share` of his health instead (once in `boss_rest`).
##   A hazard kill pays a bonus (pass 15, _bonus): COUNTY JUSTICE! across the
##   screen, scrap with the bench live, a drop at the body and the
##   hazard_killed event. src/danger_marks.gd shows them coming (looks).
##
## Play, the same on every machine: everything here is game.clock, game.rng
## (the move picked, the specks game.burst() throws) and arithmetic on the
## enemies, every variable carried in snapshots by uid (plain values only).
## Not saved: it is all seconds long.
extends GameFeature

const Finishers := preload("res://src/features/finishers.gd")
const Water := preload("res://src/features/water.gd")
const Callouts := preload("res://src/features/callouts.gd")

static var KICK: Dictionary = HitData.section("kick")
static var FINISH: Dictionary = HitData.section("finish", ["pistol", "long", "blade"])
static var BOSS_SHARE: float = HitData.value("hazard", "boss_share", .18)
static var BOSS_REST: float = HitData.value("hazard", "boss_rest", 4.0)
static var BONUS_SCRAP: int = HitData.value("hazard", "bonus_scrap", 3)
static var BONUS_DROPS: Array = HitData.value("hazard", "bonus_drops", ["shells"])
## Gun name -> its finisher class; class -> its moves (hits.cfg order).
static var CLASS_OF := {}
static var MOVES := {}
static var MOVE := {}
const CLASSES := ["pistol", "long", "blade"]
## Brains a boot or a finisher never reaches (in the air, or not a body).
const FLYING := ["skeeter", "saucer", "drone", "lantern", "bessie"]

## Boots on their way: [slot, lands at (clock), the man's uid, -1 a door's index].
var boots: Array = []
## Men sliding from a boot: [uid, vx, vy, kicker's slot, started dry].
var slides: Array = []
## When each player kicked last and may again (slot -> game.clock).
var kicked_at := {}
var kick_ready := {}
## A door each player last kicked in (slot -> its index), for the looks.
var door_kicked := {}
## Dazed men (uid -> game.clock until): open to a finisher.
var dazed := {}
## Finishers under way: [slot, uid, move, started, lands].
var moves: Array = []
## The last finisher each player started (slot -> [move, started]), looks.
var last_moves := {}
## Hogs at their slop: [uid, until, next squeal, the kicker's slot].
var feasts: Array = []
## Sparks or smoke after a kill: [x, y, z, kind, until, next].
var fx: Array = []
## A boss's last hazard hit (uid -> clock).
var boss_hit := {}
## Counts (tools, the tally): boots landed, finishers by move, hazard kills
## by kind, doors kicked in.
var kicks := 0
var finished := {}
var hazard_kills := {}
var doors := 0
## The hazard props of this level (worked out once: the level's own).
var _spots: Array = []
var _spots_of: LevelData = null


func id() -> String:
	return "brawl"


func attach() -> void:
	if CLASS_OF.is_empty():
		_read()
	tick_with(_tick)


static func _read() -> void:
	for cls: String in CLASSES:
		var guns: Array = HitData.value("finish", cls, [])
		for gun: Variant in guns:
			CLASS_OF[str(gun)] = cls
	var cfg := Tuning.file(HitData.DATA)
	for section: String in cfg.get_sections():
		if not section.begins_with("finish."):
			continue
		var move := section.substr(7)
		var row := HitData.section(section)
		MOVE[move] = row
		var cls := str(row.get("class", "boot"))
		if not MOVES.has(cls):
			MOVES[cls] = []
		var list: Array = MOVES[cls]
		list.append(move)


static func _f(v: Variant) -> float:
	var x: float = v
	return x


static func _i(v: Variant) -> int:
	var x: int = v
	return x


static func _b(v: Variant) -> bool:
	var x: bool = v
	return x


static func _num(table: Dictionary, key: String) -> float:
	var v: float = table[key]
	return v


## Whether boots and finishers work in this game: anywhere the county's
## hands are (the campaign, co-op, County Run), never in the Crossroads.
func allowed() -> bool:
	if game.in_hub:
		return false
	var mode := Modes.feature(game)
	return mode == null or mode.mode in [Modes.CAMPAIGN, Modes.COOP, Modes.COUNTY]


func spots() -> Array:
	if _spots_of != game.world:
		_spots_of = game.world
		_spots = BrawlHazards.spots(game.world)
	return _spots


func enemy(uid: int) -> Enemy:
	for e: Enemy in game.enemies:
		if e.uid == uid:
			return e
	return null


## The man `p` has in front within `reach` (cells past his edge) and
## `cone` either side of the aim, nearest first; null when none.
func target(p: Player, reach: float, cone: float) -> Enemy:
	var best: Enemy = null
	var best_d := INF
	var aim := p.view_angle()
	var feet: float = game.world.stand(p) + p.air
	for e: Enemy in game.enemies:
		if not e.alive or e.dormant or not e.hostile or FLYING.has(e.brain):
			continue
		var dx := e.x - p.x
		var dy := e.y - p.y
		var most := reach + e.radius
		if absf(dx) > most or absf(dy) > most:
			continue
		var d := sqrt(dx * dx + dy * dy)
		if d > most or d >= best_d:
			continue
		if d > .35 and absf(Enemy.angle_delta(atan2(dy, dx), aim)) > cone:
			continue
		var base: float = game.world.stand(e) + e.z
		if absf(base - feet) > .9:
			continue
		if not game.world.visible(p.x, p.y, e.x, e.y, p.eye, base + e.height * .6):
			continue
		best = e
		best_d = d
	return best


## Whether `e` can be finished: one of the county's hands with arms and legs,
## no boss, down to `low` of his health, reeling or dazed.
func finishable(e: Enemy) -> bool:
	if e == null or not e.alive or not e.hostile or BossKit.is_boss(e):
		return false
	if not HitZones.limbs(e) or FLYING.has(e.brain):
		return false
	if e.hp <= e.max_hp * _num(FINISH, "low") or e.stun >= _num(FINISH, "stagger"):
		return true
	var until: float = dazed.get(e.uid, -1.0)
	return until > game.clock


## `e` left dazed (a thing broken over his head, features/carry.gd).
func daze(e: Enemy) -> void:
	dazed[e.uid] = game.clock + _num(KICK, "daze")
	wake()


## Whether `p`'s hands are busy with a finisher or a boot.
func busy(p: Player) -> bool:
	for m: Array in moves:
		if m[0] == p.slot:
			return true
	var at: float = kicked_at.get(p.slot, -10.0)
	return game.clock - at < _num(KICK, "busy")


# ---------------------------------------------------------------- the hands


## USE: a finisher, a boot or a door kicked in. True when it was one of them
## (nothing else answers USE then).
func use(p: Player) -> bool:
	if not allowed() or p.health <= 0 or game.showing_tally:
		return false
	if busy(p):
		return true
	var e := target(p, _num(FINISH, "reach"), _num(FINISH, "cone"))
	if finishable(e):
		start_finish(p, e)
		return true
	if game.clock < _f(kick_ready.get(p.slot, 0.0)):
		return target(p, _num(KICK, "reach"), _num(KICK, "cone")) != null
	e = target(p, _num(KICK, "reach"), _num(KICK, "cone"))
	if e != null:
		kick(p, e.uid)
		return true
	var door := _door_ahead(p)
	if door >= 0:
		kick(p, -1, door)
		return true
	return false


## FIRE this tick (game.gd _step_hands): busy hands fire nothing; a swing of
## a blade at a man who can be finished finishes him. True when the hands
## are taken (the gun is not fired).
func hands(p: Player, fire: bool) -> bool:
	if not allowed():
		return false
	if busy(p):
		return true
	if not fire or p.armory.cooldown > 0.0 or p.armory.holstered:
		return false
	var gun: String = Weapons.NAMES[p.armory.active]
	if CLASS_OF.get(gun, "") != "blade":
		return false
	var e := target(p, _num(FINISH, "reach"), _num(FINISH, "cone"))
	if not finishable(e):
		return false
	start_finish(p, e)
	return true


## A plain shut door square ahead that `p`, running at it, can kick in: its
## index in the level's list, or -1.
func _door_ahead(p: Player) -> int:
	if Vector2(p.vx, p.vy).length() < _num(KICK, "door_speed"):
		return -1
	var found: Variant = GameUse.use_target(game)
	if found == null or not (found[0] is LevelData.Door):
		return -1
	var door: LevelData.Door = found[0]
	if (
		door.opened
		or door.progress > 0.0
		or door.secret
		or door.blast_only
		or (door.key != "" and not game.keys.has(door.key))
		or game.world.controlled_doors.has(Vector2i(door.x, door.y))
		or game.world.crouch_doors.has(Vector2i(door.x, door.y))
	):
		return -1
	return game.world.doors.find(door)


## A boot on its way to the man `uid` (or the door `door`).
func kick(p: Player, uid: int, door := -1) -> void:
	kicked_at[p.slot] = game.clock
	kick_ready[p.slot] = game.clock + _num(KICK, "rest")
	boots.append([p.slot, game.clock + _num(KICK, "land"), uid, door])
	p.armory.cooldown = maxf(p.armory.cooldown, _num(KICK, "busy"))
	game.sound_at("blow_grunt", p.x, p.y, .5)
	wake()


func _player(slot: int) -> Player:
	for q: Player in game.players:
		if q.slot == slot:
			return q
	return null


func _boot_lands(b: Array) -> void:
	var p := _player(_i(b[0]))
	if p == null or p.health <= 0:
		return
	var door: int = b[3]
	if door >= 0:
		_door_in(p, door)
		return
	var e := enemy(_i(b[2]))
	if e == null or not e.alive:
		return
	var d := Vector2(e.x - p.x, e.y - p.y).length()
	if d > _num(KICK, "reach") + e.radius + .45:
		game.sound_at("can_kick", p.x, p.y, .35)  # a boot into the air
		return
	kicks += 1
	var aim := p.view_angle()
	var boss := BossKit.is_boss(e)
	var speed := _num(KICK, "speed") * (_num(KICK, "boss_share") if boss else 1.0)
	_strike(p, e, _num(KICK, "boss_damage") if boss else _num(KICK, "damage"), .45, "kick")
	game.sound_at("brawl_punch", e.x, e.y, .9)
	game.sound_at("body_thud", e.x, e.y, .6)
	game.burst(e.x, e.y, game.world.stand(e) + e.height * .45, "dust", 5, 1.2)
	if not e.alive:
		return
	if not boss:
		e.stun = maxf(e.stun, _num(KICK, "stun"))
		e.windup = 0.0
		e.aim_mark = null
		e.cooldown = maxf(e.cooldown, _num(KICK, "stun"))
		dazed[e.uid] = game.clock + _num(KICK, "daze")
	slide(e, cos(aim) * speed, sin(aim) * speed, p.slot)


## Hurt `e` as `p`'s blow, landing `up` of his height up (where on him),
## counting as `how`.
func _strike(p: Player, e: Enemy, amount: float, up: float, how: String) -> void:
	game.focus(p)
	var base: float = game.world.stand(e) + e.z
	game.hit_point = Vector3(e.x, e.y, base + e.height * e.variant * up)
	game.hit_from = Vector2(p.x, p.y)
	e.hurt(amount, game, false, false, null, how)
	game.focus(game.local_player)


## `e` slides at (vx, vy), slowing (another slide of his is replaced).
func slide(e: Enemy, vx: float, vy: float, slot: int) -> void:
	for s: Array in slides:
		if s[0] == e.uid:
			slides.erase(s)
			break
	var dry := not BayouBrains.wet_at(game.world, e.x, e.y)
	slides.append([e.uid, vx, vy, slot, dry])
	wake()


## The door at `index` kicked in by `p`: open at once, splinters, and whoever
## stands behind it thrown back.
func _door_in(p: Player, index: int) -> void:
	var door: LevelData.Door = game.world.doors[index]
	if door.opened:
		return
	doors += 1
	door_kicked[p.slot] = index
	game.toggle_door(door, true)
	door.progress = 1.0
	var c := door.center()
	game.sound_at("break_crate", c.x, c.y, .9)
	game.sound_at("cover_slam", c.x, c.y, .8)
	game.burst(c.x, c.y, game.world.elevation(c.x, c.y) + .9, "chips", 12, 2.2)
	game.disturb(c.x, c.y, 6.0)
	var aim := p.view_angle()
	var reach := _num(KICK, "door_reach")
	for e: Enemy in game.enemies:
		if not e.alive or e.dormant or not e.hostile or FLYING.has(e.brain):
			continue
		var dx := e.x - c.x
		var dy := e.y - c.y
		if dx * dx + dy * dy > reach * reach or dx * cos(aim) + dy * sin(aim) < -.2:
			continue
		var boss := BossKit.is_boss(e)
		_strike(p, e, _num(KICK, "boss_damage") if boss else _num(KICK, "damage") * 1.5, .5, "kick")
		if not e.alive:
			continue
		var speed := _num(KICK, "speed") * (_num(KICK, "boss_share") if boss else 1.1)
		if not boss:
			e.stun = maxf(e.stun, _num(KICK, "stun") * 1.4)
			dazed[e.uid] = game.clock + _num(KICK, "daze")
		slide(e, cos(aim) * speed, sin(aim) * speed, p.slot)


# --------------------------------------------------------------- finishers


func gun_class(p: Player) -> String:
	if p.armory.holstered:
		return "boot"
	var gun: String = Weapons.NAMES[p.armory.active]
	return str(CLASS_OF.get(gun, "boot"))


## Start a finisher on `e`: the move by the gun in hand (game.rng among them).
func start_finish(p: Player, e: Enemy) -> void:
	var cls := gun_class(p)
	var picks := picks_for(p)
	# Alone, off the dice; with more than one player off the man and the
	# player (pass 13), which every copy knows at the press, so a client
	# draws the move then (net_finish_looks.gd).
	var move: String = (
		game.rng.choice(picks) if game.players.size() < 2 else party_move(picks, e, p)
	)
	moves.append([p.slot, e.uid, move, game.clock, game.clock + _num(FINISH, "wind")])
	last_moves[p.slot] = [move, game.clock]
	dazed.erase(e.uid)
	e.stun = maxf(e.stun, _num(FINISH, "wind") + .6)
	e.windup = 0.0
	e.aim_mark = null
	e.cooldown = maxf(e.cooldown, 1.0)
	for s: Array in slides:
		if s[0] == e.uid:
			slides.erase(s)
			break
	p.armory.cooldown = maxf(p.armory.cooldown, _num(FINISH, "hold"))
	if cls == "blade":
		# The blade's own swing shows (weapons.gd pose()); it strikes nothing.
		p.armory.shot_age = 0.0
		p.armory.swing_hit = false
	var f: Object = game.features.get("finishers")
	if f != null and Finishers.allowed(game):
		# Its own slow motion comes with the blow (_blow), not the shot's.
		f.set("again_at", game.clock + Finishers.REST)
	wake()


## The move a finisher on `e` by `p` takes with more than one player: one of
## `picks` by the man's uid and the player's slot.
static func party_move(picks: Array, e: Enemy, p: Player) -> String:
	return str(picks[posmod(e.uid * 7 + p.slot * 3, picks.size())])


## The moves `p` may finish with now (start_finish's list).
func picks_for(p: Player) -> Array:
	var picks: Array = []
	var list: Array = MOVES.get(gun_class(p), MOVES.get("boot", []))
	for move: String in list:
		var row: Dictionary = MOVE[move]
		if _b(row.get("round", false)) and p.armory.loaded[p.armory.active] <= 0:
			continue
		picks.append(move)
	if picks.is_empty():
		picks = MOVES.get("boot", [])
	return picks


func _blow(m: Array) -> void:
	var p := _player(_i(m[0]))
	var e := enemy(_i(m[1]))
	var move: String = m[2]
	if p == null or e == null or not e.alive or p.health <= 0:
		return
	if Vector2(e.x - p.x, e.y - p.y).length() > _num(FINISH, "reach") + e.radius + 1.0:
		return
	var row: Dictionary = MOVE[move]
	var cue := str(row.get("cue", "brawl_punch"))
	if _b(row.get("round", false)):
		var i := p.armory.active
		if p.armory.loaded[i] > 0:
			p.armory.loaded[i] -= 1
		p.armory.shot_age = 0.0
		p.armory.flash = .08
		cue = Weapons.NAMES[i]
		game.disturb(p.x, p.y, 9.0)
	var zone := str(row.get("zone", "body"))
	var up := .92 if zone == "head" else .15 if zone == "legs" else .55
	var end := str(row.get("end", "fall"))
	var how := str(row.get("how", "crowbar"))
	# How hard: enough to drop him; for "head_off" heavy enough that the
	# gore takes the head (gore_extras.gd LIMB_HIT) yet short of an overkill
	# (hit_zones.gd) that would take him all apart.
	var amount := e.hp + 10.0
	if end == "head_off":
		var head: float = HitZones.HEAD.get(how, HitZones.HEAD_DEFAULT)
		amount = maxf(e.hp / head + 2.0, 46.0 / head)
	if Finishers.allowed(game):
		# The world slows as the blow lands, so the body and the bits fly.
		game.slowmo = maxf(game.slowmo, _num(FINISH, "slowmo"))
		game.slowmo_for = game.slowmo
		game.slowmo_pace = _num(FINISH, "pace")
	_hush_kill_bark(p)
	# An online client that drew this blow from its press (net_finish_looks.gd)
	# does not show it again: its sounds, blood and specks and its call are
	# left out, the play goes as ever (the dice too).
	var shown := game.hands_watch != null and game.hands_watch.finish_shown(p.slot, e.uid, move)
	var loud: Array = [game.speaker, game.own_quiet]
	if shown:
		game.speaker = QuietSound.new()
		game.own_quiet = true
	_strike(p, e, amount, up, how)
	if e.alive:
		e.hurt(e.hp + 1.0, game, false, false, null, how)
	if shown:
		game.own_quiet = loud[1]
	if end == "gib" and not e.explosive and game.gore:
		e.explosive = true
		game.events.enemy_gibbed.emit(e)
	var base: float = game.world.stand(e)
	game.sound_at(cue, e.x, e.y, 1.0)
	game.sound_at("gib_splat" if end != "fall" else "body_thud", e.x, e.y, .8)
	game.burst(e.x, e.y, base + e.height * up, "gore", _i(row.get("gore", 10)), 2.2, not shown)
	if shown:
		game.speaker = loud[0]
		game.focus(game.local_player)
	finished[move] = _i(finished.get(move, 0)) + 1
	if not shown:
		_call(p, str(row.get("name", "")))
	game.focus(p)
	game.barks.say(game, "finisher", true)
	game.focus(game.local_player)


## Mundell's word on a finisher or a hazard kill comes instead of his kill
## line (barks.gd: the kill's own is not forced, so it keeps quiet now).
func _hush_kill_bark(p: Player) -> void:
	if p == game.local_player:
		game.barks.next_any = maxf(game.barks.next_any, game.clock + .2)


## A call across the screen for whoever did it.
func _call(p: Player, text: String) -> void:
	if text == "" or p != game.local_player:
		return
	game.callout = text + "!"
	game.callout_until = game.clock + 1.8


# ------------------------------------------------------------------ hazards


## `e` driven into the hazard `kind` (at x, y) by `slot`'s boot: he dies the
## way it kills (a boss takes his share). True when it took him.
func caught(e: Enemy, kind: String, x: float, y: float, slot: int) -> bool:
	var p := _player(slot)
	if p == null:
		p = game.local_player
	var how := str(BrawlHazards.value(kind, "how", "blade"))
	var cue := str(BrawlHazards.value(kind, "cue", "body_thud"))
	var kill := str(BrawlHazards.value(kind, "kill", "gib"))
	var base: float = game.world.stand(e)
	if BossKit.is_boss(e):
		var last: float = boss_hit.get(e.uid, -100.0)
		if game.clock - last < BOSS_REST:
			return false
		boss_hit[e.uid] = game.clock
		var harm := minf(e.max_hp * BOSS_SHARE, e.hp - 1.0)
		if harm > 0.0:
			_strike(p, e, harm, .5, how)
		game.sound_at(cue, e.x, e.y, 1.0)
		_effects(kill, e.x, e.y, base + e.height * .5, .8)
		return true
	if kill == "hogs":
		e.stun = 9.0
		e.windup = 0.0
		feasts.append([e.uid, game.clock + 1.3, game.clock, slot])
		game.sound_at("pig", e.x, e.y, 1.0)
		game.sound_at("hick_pain_1", e.x, e.y, .9)
		return true
	var up := .15 if kill == "crumple" else .55
	if kill == "drop" or kill == "drown":
		# Over the well's mouth or face down in the water.
		e.x = lerpf(e.x, x, .8)
		e.y = lerpf(e.y, y, .8)
	_hush_kill_bark(p)
	_strike(p, e, e.hp + 200.0 if kill == "gib" else e.hp + 30.0, up, how)
	if e.alive:
		e.hurt(e.hp + 1.0, game, false, false, null, how)
	if kill == "drop":
		e.explosive = true  # gone down the shaft: no body to show
	elif kill == "burn":
		var fire: Object = game.features.get("fire")
		if fire != null:
			fire.call("ignite", e.x, e.y, base)
	elif kill == "drown":
		Water.splash_if(game, e.x, e.y, base, 2.2)
	game.sound_at(cue, e.x, e.y, 1.0)
	_effects(kill, e.x, e.y, base + e.height * .5, 1.2)
	hazard_kills[kind] = _i(hazard_kills.get(kind, 0)) + 1
	_bonus(p, e, kind)
	game.focus(p)
	game.barks.say(game, "hazard", true)
	game.focus(game.local_player)
	return true


## A hazard kill's bonus (pass 15; hits.cfg [hazard]): for whoever booted him,
## COUNTY JUSTICE! across the screen and the hazard's own name with the pay in
## the notice; `bonus_scrap` scrap in his coffee can with the bench live (up to
## what he may carry); a drop at the body, nudged toward the kicker (_bonus_pick);
## and the hazard_killed event (a RAMPAGE meter adds [hazard] `bonus_rampage`).
## Play: game.rng and the kicker's armory, the same on every machine.
func _bonus(p: Player, e: Enemy, kind: String) -> void:
	var paid := 0
	if game.bench_live:
		var most: int = BenchMods.value("scrap", "most", 99)
		paid = clampi(BONUS_SCRAP, 0, maxi(0, most - p.armory.scrap))
		p.armory.scrap += paid
	var pick := _bonus_pick(e)
	if pick != "":
		var to := Vector2(p.x - e.x, p.y - e.y).limit_length(.6)
		var at := Vector2(e.x, e.y) + to
		if game.world.blocked(at.x, at.y, .1):
			at = Vector2(e.x, e.y)
		game.add_pickup(pick, at.x, at.y, e.floor_z)
	if p == game.local_player:
		game.callout = Callouts.JUSTICE
		game.callout_until = game.clock + 1.8
		var name := str(BrawlHazards.value(kind, "name", ""))
		game.notice = name + ("!  +%d SCRAP" % paid if paid > 0 else "!")
		game.message_until = game.clock + 2.2
	game.events.hazard_killed.emit(e, kind, p.slot)


## What a hazard kill drops (none with NO DROPS): the hand's own drop when
## his kind has one (enemies.cfg `drop`), else one of [hazard] `bonus_drops`
## by game.rng; either way leaning to what the acting player is short of
## (src/drop_need.gd, every time: roll 0, no dice).
func _bonus_pick(e: Enemy) -> String:
	if game.supply_rule == 2:
		return ""
	var spec: Dictionary = Enemy.DEFS.get(e.kind, {})
	var own := str(spec["drop"]) if spec.has("drop") else str(game.rng.choice(BONUS_DROPS))
	return DropNeed.pick(game, own, 0.0)


## What a hazard kill throws after: sparks for a shock, smoke and embers for
## fire, a spray of blood and chips for the blades (game.burst, so game.rng).
func _effects(kill: String, x: float, y: float, z: float, length: float) -> void:
	var kind := ""
	match kill:
		"shock":
			kind = "spark"
		"burn":
			kind = "dust"
		"gib":
			kind = "gore"
		"drown":
			kind = "splash"
	if kind != "":
		fx.append([x, y, z, kind, game.clock + length, game.clock])


func _hogs(f: Array, dt: float) -> bool:
	var e := enemy(_i(f[0]))
	if e == null or not e.alive:
		return false
	var hogs := BrawlHazards.hogs_near(game.enemies, e.x, e.y)
	for hog: Enemy in hogs:
		var d := Vector2(e.x - hog.x, e.y - hog.y)
		var reach := d.length() - e.radius - hog.radius
		if reach > .05:
			var step := minf(reach, 2.6 * dt) / maxf(.01, d.length())
			game.move_actor(hog, d.x * step, d.y * step, hog.radius)
		hog.angle = atan2(d.y, d.x)
	var next: float = f[2]
	if game.clock >= next:
		f[2] = game.clock + .3
		game.sound_at("pig", e.x, e.y, .9)
		game.burst(e.x, e.y, game.world.stand(e) + .4, "gore", 4, 1.4)
	if game.clock < _f(f[1]):
		return true
	var p := _player(_i(f[3]))
	if p == null:
		p = game.local_player
	_hush_kill_bark(p)
	_strike(p, e, e.hp + 200.0, .5, "blade")
	game.sound_at("gib_burst", e.x, e.y, 1.0)
	hazard_kills["hogs"] = _i(hazard_kills.get("hogs", 0)) + 1
	_bonus(p, e, "hogs")
	game.focus(p)
	game.barks.say(game, "hazard", true)
	game.focus(game.local_player)
	return false


# --------------------------------------------------------------------- tick


func _tick(dt: float) -> void:
	if boots.is_empty() and slides.is_empty() and moves.is_empty() and feasts.is_empty():
		if fx.is_empty():
			_forget()
			if dazed.is_empty():
				sleep()
			return
	var due: Array = []
	for b: Array in boots:
		if game.clock >= _f(b[1]):
			due.append(b)
	for b: Array in due:
		boots.erase(b)
		_boot_lands(b)
	var blows: Array = []
	for m: Array in moves:
		if game.clock >= _f(m[4]):
			blows.append(m)
	for m: Array in blows:
		moves.erase(m)
		_blow(m)
	var keep: Array = []
	for s: Array in slides:
		if _slide_step(s, dt):
			keep.append(s)
	slides = keep
	var eating: Array = []
	for f: Array in feasts:
		if _hogs(f, dt):
			eating.append(f)
	feasts = eating
	var lit: Array = []
	for f: Array in fx:
		if game.clock < _f(f[4]):
			lit.append(f)
			if game.clock >= _f(f[5]):
				f[5] = game.clock + .12
				game.burst(_f(f[0]), _f(f[1]), _f(f[2]), str(f[3]), 3, 1.1)
	fx = lit
	_forget()


func _forget() -> void:
	for uid: int in dazed.keys():
		var until: float = dazed[uid]
		if until < game.clock:
			dazed.erase(uid)


## One step of a slide; false when it is over.
func _slide_step(s: Array, dt: float) -> bool:
	var e := enemy(_i(s[0]))
	if e == null or not e.alive:
		return false
	var vx: float = s[1]
	var vy: float = s[2]
	var speed := sqrt(vx * vx + vy * vy)
	if speed < _num(KICK, "stop"):
		_among_hogs(e, _i(s[3]))
		return false
	e.stun = maxf(e.stun, .2)
	var was_x := e.x
	var was_y := e.y
	var was_floor := e.floor_z
	var dx := vx * dt
	var dy := vy * dt
	game.move_actor(e, dx, dy, e.radius)
	var moved := Vector2(e.x - was_x, e.y - was_y).length()
	var spot := BrawlHazards.prop_at(spots(), e)
	if not spot.is_empty():
		var sx: float = spot[1]
		var sy: float = spot[2]
		if caught(e, str(spot[0]), sx, sy, _i(s[3])):
			return false
	if _b(s[4]) and BrawlHazards.into_water(game.world, e, vx, vy):
		if caught(e, "water", e.x + vx * .08, e.y + vy * .08, _i(s[3])):
			return false
	var p := _player(_i(s[3]))
	if p == null:
		p = game.local_player
	var drop := was_floor - e.floor_z
	if drop > _num(KICK, "drop"):
		_strike(p, e, drop * _num(KICK, "drop_damage"), .1, "fall")
		game.sound_at("body_thud", e.x, e.y, 1.0)
		if not e.alive:
			return false
	_domino(e, vx, vy, s)
	if moved < Vector2(dx, dy).length() * .5:
		if speed > _num(KICK, "slam_least"):
			_strike(p, e, _num(KICK, "slam") * speed, .55, "kick")
			game.sound_at("cover_slam", e.x, e.y, .8)
			game.burst(e.x, e.y, game.world.stand(e) + .9, "dust", 6, 1.4)
			if e.alive:
				e.stun = maxf(e.stun, _num(KICK, "stun"))
		if e.alive:
			_among_hogs(e, _i(s[3]))
		return false
	var slow := maxf(0.0, speed - _num(KICK, "drag") * dt) / speed
	s[1] = vx * slow
	s[2] = vy * slow
	return true


## Where a slide ends: among the hogs, they set on him.
func _among_hogs(e: Enemy, slot: int) -> void:
	if BossKit.is_boss(e) or _feasting(e):
		return
	if not BrawlHazards.hogs_near(game.enemies, e.x, e.y).is_empty():
		caught(e, "hogs", e.x, e.y, slot)


func _feasting(e: Enemy) -> bool:
	for f: Array in feasts:
		if f[0] == e.uid:
			return true
	return false


## A sliding man into another standing in his way: that one goes too.
func _domino(e: Enemy, vx: float, vy: float, s: Array) -> void:
	for o: Enemy in game.enemies:
		if o == e or not o.alive or o.dormant or not o.hostile or FLYING.has(o.brain):
			continue
		var dx := o.x - e.x
		var dy := o.y - e.y
		var reach := e.radius + o.radius + .08
		if absf(dx) > reach or absf(dy) > reach or dx * dx + dy * dy > reach * reach:
			continue
		if dx * vx + dy * vy <= 0.0:
			continue
		var sliding := false
		for t: Array in slides:
			if t[0] == o.uid:
				sliding = true
		if sliding:
			continue
		var share := (
			_num(KICK, "domino") * (_num(KICK, "boss_share") if BossKit.is_boss(o) else 1.0)
		)
		var p := _player(_i(s[3]))
		if p != null:
			_strike(p, o, _num(KICK, "damage") * .5, .5, "kick")
		if not o.alive:
			continue
		if not BossKit.is_boss(o):
			o.stun = maxf(o.stun, _num(KICK, "stun"))
			dazed[o.uid] = game.clock + _num(KICK, "daze")
		slides.append([o.uid, vx * share, vy * share, s[3], true])
		s[1] = vx * .5
		s[2] = vy * .5
		game.sound_at("body_thud", o.x, o.y, .7)
		return


## The chapter's tally: a row when anything was done.
func tally_rows() -> Array:
	var done := 0
	for k: String in finished:
		done += _i(finished[k])
	var env := 0
	for k: String in hazard_kills:
		env += _i(hazard_kills[k])
	if done + env == 0:
		return []
	return [["FINISHERS", str(done)], ["DIRTY KILLS", str(env)]]
