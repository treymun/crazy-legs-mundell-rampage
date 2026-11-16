## A client's own shots, reloads and pickups shown the moment the button goes
## down, not a round trip later when the copy of the game plays them.
##
## Each frame (main.gd `_net_aim`, after the walk is led) `frame()` leads our
## gun through the inputs the host has not played into the copy yet
## (net_gun_lead.gd: flash, kick, pose and the HUD's rounds lead with it) and
## shows once each thing that happened on the way: the bang (and its ring in
## a room), the cycle's and the reload's beats, a dry click, a gun taken up;
## for a shot the gun's kick and shake, the looks-only features' muzzle puff,
## shell and smoke (GameFeature.own_shot), and for a bullet or pellet gun its
## line drawn where our screen shows the world: the tracer and what it chips
## off a wall (own_trace), and on someone the crosshair's mark, the tick and a
## spray of blood. A pickup our drawn player reaches and would take goes from
## the picture with its sound.
##
## The host's game stays the only truth, and the copy plays exactly what it
## played: this is looks only. When the copy plays our hands (game.gd calls
## this as `game.hands_watch` round `_step_hands`), what was shown already is
## not shown again: its looks-only calls are held (`game.own_quiet`, defer())
## and its sounds written down (NetEchoSound), then a shot the copy fired is
## matched with the oldest shown one (its looks dropped, its kick and shake
## taken back; a mark the host did not give withdrawn, its blood taken away),
## and a sound already heard is dropped while anything else (a kill's tick, a
## yelp, a shot nobody foresaw) plays then. Something shown that the copy
## never played within WINDOW of its input (a shot refused, a pickup someone
## else took) is withdrawn quietly; the gun and the HUD were only ever led,
## so they simply follow the copy.
##
## Nothing here runs on a single-player game or a host (`hands_watch` null).
## Any online mode gets it: it follows Game.Controls and the copy alone.
class_name NetShotPredict
extends HandsWatch

## Inputs either side of where the copy is that a shown thing is matched in
## (the host holds or merges an input now and then), and after which one not
## played is withdrawn.
const WINDOW := 8
const EXPIRE := 16
## Shown things of one kind this near (inputs) are the same thing seen again
## (an input held by the host moves the lead by a tick).
const SAME := 3
## How far inside a body's edge (cells) our line must pass for its mark to
## show at the press.
const SURE := .06
## Blood thrown on a player struck (Modes.player_hit's burst).
const BLOOD := 6
## Off: nothing led or shown (net_lag.gd's before).
static var enabled := true

## Shown things the copy has not played yet: {"kind", "seq", "gun", "cues"
## (cue names not heard back yet), "matched", "hit", "marker_at", "specks"}.
var pending: Array = []
## Pickups taken in the picture, by uid: our input when.
var taken := {}
## For a tool: the clock (ms) to time things by (-1: the real one).
var now_ms := -1.0
## What happened (net_lag.gd, tools/predict_check.gd).
var stats := {}
## When each input of ours was first seen sent (ms), for the timings.
var sent_ms := {}
## Button to the shot shown (ms): here, and when the copy played it (as
## before this, when the copy's own looks were the first).
var show_ms := PackedFloat32Array()
var copy_ms := PackedFloat32Array()
var _seen_seq := -1
var _client: WeakRef = null
var _game: WeakRef = null
var dice := RandomNumberGenerator.new()
## The hands step being watched now.
var _quiet := false
var _played := -1
var _real_sound: GameSound = null
var _echo := NetEchoSound.new()
var _held: Array = []
var _before := {}
var _watched: Game = null


func _init() -> void:
	dice.seed = 1997
	clear_stats()


func clear_stats() -> void:
	stats = {
		"shots": 0,
		"confirmed": 0,
		"withdrawn": 0,
		"late": 0,
		"hits": 0,
		"hits_confirmed": 0,
		"hits_withdrawn": 0,
		"pickups": 0,
		"pickups_taken": 0,
		"pickups_back": 0,
		"sounds_dropped": 0,
	}
	show_ms = PackedFloat32Array()
	copy_ms = PackedFloat32Array()


func _now() -> float:
	return now_ms if now_ms >= 0.0 else float(Time.get_ticks_msec())


## The copy's next tick plays our input number this (-1: not known yet).
static func played_seq(client: NetSync.Client) -> int:
	if client == null or client.input_ack < 0:
		return -1
	return client.input_ack + 1 - maxi(0, client.latest_tick - client.game_tick)


## Watches `game` (the client's copy) for slot `my_slot`.
func attach(game: Game, client: NetSync.Client, my_slot: int) -> void:
	_client = weakref(client)
	if game.hands_watch != self:
		forget()
		game.hands_watch = self
		_game = weakref(game)
	slot = my_slot


## Stops watching (out of a match, or this machine is no client).
func forget() -> void:
	var game: Game = _game.get_ref() if _game != null else null
	if game != null and game.hands_watch == self:
		game.hands_watch = null
		game.own_quiet = false
	_game = null
	pending.clear()
	taken.clear()
	sent_ms.clear()
	_seen_seq = -1


func _client_now() -> NetSync.Client:
	return _client.get_ref() if _client != null else null


## This frame's lead: our gun stepped on, new things shown, pickups taken
## out of the picture. Returns what to hand to restore() after the frame.
func frame(game: Game, me: Player, client: NetSync.Client) -> Dictionary:
	attach(game, client, me.slot)
	var played := played_seq(client)
	if played < 0:
		return {}
	var now := _now()
	for n in range(
		maxi(_seen_seq + 1, client.input_seq - NetSync.Client.SENT_KEEP), client.input_seq
	):
		sent_ms[n] = now
	_seen_seq = client.input_seq - 1
	for n: Variant in sent_ms.keys():
		var n_seq: int = n
		if n_seq < played - EXPIRE * 4:
			sent_ms.erase(n)
	_expire(game, played)
	if not enabled:
		return {}
	var inputs := client.unplayed_inputs()
	var led := NetGunLead.lead(game, me, inputs, client.input_seq - inputs.size())
	if not led.is_empty():
		var events: Array = led["events"]
		for ev: Dictionary in events:
			if not _shown(ev):
				_show(game, me, ev)
	var out := {"gun": led.get("kept", {})}
	var hidden := _pickups(game, me, client.input_seq - 1)
	if not hidden.is_empty():
		out["pickups"] = hidden
	return out


## Puts the gun and the pickups back after the frame.
func restore(game: Game, me: Player, kept: Dictionary) -> void:
	if kept.is_empty():
		return
	var gun: Dictionary = kept.get("gun", {})
	NetGunLead.restore(me, gun)
	if kept.has("pickups"):
		var lying: Array = kept["pickups"]
		game.pickups = lying


func _key(ev: Dictionary) -> String:
	var kind: String = ev["kind"]
	if kind == "beat" or kind == "equip":
		var cues: Array = ev["cues"]
		var first: Array = cues[0]
		return kind + ":" + str(first[0])
	return kind


func _shown(ev: Dictionary) -> bool:
	var key := _key(ev)
	var seq: int = ev["seq"]
	for old: Dictionary in pending:
		var old_seq: int = old["seq"]
		if absi(old_seq - seq) <= SAME and old.get("key", "") == key:
			return true
	return false


# ------------------------------------------------------------------ showing


## Shows `ev` now, once, with `me` led (where our screen has us).
func _show(game: Game, me: Player, ev: Dictionary) -> void:
	var kind: String = ev["kind"]
	var gun: int = ev["gun"]
	var seq: int = ev["seq"]
	var shown := {
		"kind": kind,
		"key": _key(ev),
		"seq": seq,
		"gun": gun,
		"cues": [],
		"matched": false,
		"hit": false,
		"marker_at": -1.0,
		"specks": [],
	}
	pending.append(shown)
	var cues: Array = ev["cues"]
	for cue: Array in cues:
		var volume: float = cue[1]
		_say(game, shown, str(cue[0]), volume)
	if ev.get("report", false) and _roofed(game, me):
		var bang: Array = cues[0]
		_say(game, shown, "room_" + str(bang[0]), .78)
	if ev.has("message"):
		var length: float = ev.get("length", 1.0)
		game.message(str(ev["message"]), length)
	if kind == "reload":
		for f: GameFeature in game.features.values():
			f.own_reload(gun)
	if kind != "shot":
		return
	stats["shots"] += 1
	var pressed: float = sent_ms.get(seq, _now())
	show_ms.append(_now() - pressed)
	var shake: float = ev["shake"]
	game.shake = minf(1.0, game.shake + shake)
	var feel: GameFeature = game.features.get("feel")
	if feel != null:
		feel.call("kick_now", ev["recoil"])
	for f: GameFeature in game.features.values():
		f.own_shot(gun)
	var how: Dictionary = Weapons.FIRING[gun]
	var mode := str(how.get("fire", ""))
	if mode == "hitscan" or mode == "pellets":
		_line(game, me, gun, ev, shown)


## Plays `cue` now and notes it, so the copy's own is not heard again.
func _say(game: Game, shown: Dictionary, cue: String, volume: float) -> void:
	game.sound.play(cue, volume)
	var heard: Array = shown["cues"]
	heard.append(cue)


func _roofed(game: Game, me: Player) -> bool:
	var w: LevelData = game.world
	var cell := clampi(int(me.y), 0, w.height - 1) * w.width + clampi(int(me.x), 0, w.width - 1)
	return w.roof[cell] != 0.0


## A bullet or pellet gun's lines as our screen shows the world: the centre
## line (a pellet gun's others off our own dice inside its spread; where they
## really went is the host's dice), their tracers and chips, and on someone
## the mark, the tick and the blood.
func _line(game: Game, me: Player, gun: int, ev: Dictionary, shown: Dictionary) -> void:
	var how: Dictionary = Weapons.FIRING[gun]
	var tuned := Modes.shot_spread(game, me, gun, how, me.armory.rifle_heat)
	var spread: Vector2 = tuned[0]
	var gun_reach: float = tuned[1]
	var reach: float = Modes.hit_reach(game, gun_reach)
	var width: float = how.get("width", 0.0)
	var aim := me.view_angle()
	var slope := (me.pitch + me.sway) / View.base_focal
	var spent: int = ev.get("spent", 1)
	var lines: Array = [Vector2.ZERO]
	if str(how.get("fire", "")) == "pellets":
		var pellets: int = how.get("pellets", Weapons.SHOTGUN_PELLETS)
		for k in pellets * spent - 1:
			lines.append(
				Vector2(
					dice.randf_range(-spread.x, spread.x), dice.randf_range(-spread.y, spread.y)
				)
			)
	elif spent == 2 and how.has("pair_spread"):
		var pair_spread: float = how["pair_spread"]
		lines = [Vector2(-pair_spread, 0.0), Vector2(pair_spread, 0.0)]
	var struck_one: Object = null
	var at := Vector3.ZERO
	var rang := false
	for off: Vector2 in lines:
		var ray := probe(game, me, aim + off.x, slope + off.y, reach, width)
		var end: Vector3 = ray["end"]
		var struck: String = ray["struck"]
		game.impact_kind = str(ray.get("kind", ""))
		for f: GameFeature in game.features.values():
			f.own_trace(end, struck)
		if struck.begins_with("wall:") and struck != "wall:":
			_chips(game, end, str(ray["kind"]))
			if not rang:
				rang = true
				_ring(game, shown, gun, str(ray["kind"]), end)
		var who: Object = ray.get("who")
		# A pellet gun's mark from its centre line only (the rest are our dice,
		# not the host's), and only a line well on the body: one grazing its
		# edge was judged otherwise by the host about half the time, and the
		# mark it gave was taken back (the host's own then shows as it lands).
		if who != null and struck_one == null and (off == Vector2.ZERO or lines.size() <= 2):
			var sure := probe(game, me, aim + off.x, slope + off.y, reach, width - SURE)
			if sure.get("who") == who:
				struck_one = who
				at = end
	if struck_one != null:
		_hit(game, me, gun, shown, struck_one, at)


## The first thing a line from `me` along (angle, slope) meets within `reach`
## as this copy stands now, read only: {"end", "struck" (as `traced` says it),
## "kind" (materials.gd, a wall's), "who" (the Enemy or Player)}. The level's
## loose things, drums and scenery are not looked at (the host's word).
static func probe(
	game: Game, me: Player, angle: float, slope: float, reach: float, width: float
) -> Dictionary:
	var ax := cos(angle)
	var ay := sin(angle)
	var w: LevelData = game.world
	var best: Enemy = null
	var near := reach
	for enemy: Enemy in game.enemies:
		if not enemy.alive or enemy.brain == "bessie":
			continue
		var dx := enemy.x - me.x
		var dy := enemy.y - me.y
		var d := dx * ax + dy * ay
		var z := me.eye + d * slope
		var feet: float = enemy.z + w.stand(enemy)
		if (
			0.0 < d
			and d < near
			and absf(dx * ay - dy * ax) < enemy.radius + width
			and feet - .10 < z
			and z < feet + enemy.height + .10
			and w.visible(me.x, me.y, enemy.x, enemy.y, me.eye, z)
		):
			best = enemy
			near = d
	var mate: Array = []
	if game.players.size() > 1 and Modes.rules(game).bullets_hit_players():
		var was: Player = game.player
		game.player = me
		mate = Modes.player_in_line(game, ax, ay, slope, width, near)
		game.player = was
		if not mate.is_empty():
			near = mate[1]
			best = null
	var point := func(d: float) -> Vector3:
		return Vector3(me.x + ax * d, me.y + ay * d, me.eye + d * slope)
	if not mate.is_empty():
		return {"end": point.call(near), "struck": "enemy", "who": mate[0]}
	if best != null:
		return {"end": point.call(near), "struck": "enemy", "who": best}
	var steps := int(ceilf(reach / .105))
	for i in range(1, steps + 1):
		var d: float = i * reach / steps
		var x := me.x + ax * d
		var y := me.y + ay * d
		var z := me.eye + d * slope
		var cell := clampi(int(y), 0, w.height - 1) * w.width + clampi(int(x), 0, w.width - 1)
		var surface_tile: Variant = null
		if z < w.ground[cell]:
			surface_tile = int(w.floor_tile[cell])
		elif 0.0 < w.roof[cell] and w.roof[cell] < z:
			surface_tile = int(w.ceiling_tile[cell])
		if surface_tile != null or w.blocked(x, y, .024, z):
			if w.pane_at(x, y, z, .025) != null:
				return {"end": point.call(d), "struck": "glass", "kind": "glass"}
			var kind := Materials.struck(w, x, y, z, surface_tile)
			var hit_d: float = (i - .70) * reach / steps
			return {
				"end": point.call(hit_d), "struck": "wall:" + Materials.coarse(kind), "kind": kind
			}
	return {"end": point.call(reach), "struck": "air"}


## What a wall gives off where our line met it (as hitscan's burst, off our
## own dice; the copy's own are held back when it plays the shot).
func _chips(game: Game, end: Vector3, kind: String) -> void:
	var particle := str(Materials.SPECKS.get(kind, "chips"))
	var surface := Materials.coarse(kind)
	var speed: float = {"wood": .64, "metal": 1.21, "plaster": .53, "dirt": .48}.get(surface, .64)
	_specks(game, end.x, end.y, maxf(.04, minf(1.8, end.z)), particle, 3, speed)
	if game.gore_fx != null:
		game.gore_fx.impact(end.x, end.y, maxf(.04, minf(1.8, end.z)), surface)


## The wall's sound under our line (hitscan's cues).
func _ring(game: Game, shown: Dictionary, gun: int, kind: String, end: Vector3) -> void:
	if not (
		(
			gun
			in [
				Weapons.REVOLVER,
				Weapons.RIFLE,
				Weapons.SHOTGUN,
				Weapons.RIVETER,
				Weapons.PRESSURE,
				Weapons.HUNTER,
				Weapons.MOWER
			]
		)
		or Weapons.FRESH_BULLETS.has(gun)
	):
		return
	var cue := str(Materials.CUES.get(kind, "impact_wood"))
	if gun == Weapons.RIVETER:
		cue = "impact_rivet"
	elif gun == Weapons.PRESSURE:
		cue = "impact_pressure"
	game.sound_at(cue, end.x, end.y, .64)
	var heard: Array = shown["cues"]
	heard.append(cue)
	heard.append("room_" + cue)  # its ring under a roof, if it rang


## Our line on someone: the crosshair's mark and tick (as game.struck), and
## blood where it went in, all of it ours to take back if the host says no.
func _hit(game: Game, me: Player, gun: int, shown: Dictionary, who: Object, at: Vector3) -> void:
	stats["hits"] += 1
	shown["hit"] = true
	if game.hit_feedback:
		if game.clock >= game.hit_mark_until:
			game.hit_mark_kill = false
			game.hit_mark_head = false
			game.hit_mark_at = game.clock
		game.hit_mark_until = maxf(game.hit_mark_until, game.clock + .12)
		shown["marker_at"] = game.hit_mark_at
		if game.clock >= game.hit_tick_next:
			game.hit_tick_next = game.clock + .06
			_say(game, shown, "hit_tick", .34)
	if not game.gore:
		return
	var before := game.specks.size()
	if who is Player:
		var q: Player = who
		_specks(game, q.x, q.y, q.eye - .3, "gore", BLOOD, 1.2)
	elif who is Enemy:
		var e: Enemy = who
		if e.hostile and not HitZones.metal(e) and game.gore_fx != null:
			var from := atan2(e.y - me.y, e.x - me.x)
			var amount: float = Weapons.DAMAGE.get(gun, 10)
			game.gore_fx.spray(
				at.x, at.y, at.z, cos(from), sin(from), amount, Enemy.PLASMA.has(e.kind)
			)
	shown["specks"] = game.specks.slice(before)


func _specks(
	game: Game, x: float, y: float, z: float, kind: String, count: int, speed: float
) -> void:
	for _i in count:
		var angle := dice.randf() * TAU
		var v := dice.randf_range(.24, speed)
		var up := dice.randf_range(.2, speed * 1.3)
		game.specks.append(
			GameState.Speck.new(
				x, y, z, cos(angle) * v, sin(angle) * v, up, dice.randf_range(.18, .68), kind
			)
		)


## A shown hit the host did not give: the mark goes (if it is still ours)
## and its blood with it.
func _withdraw_hit(game: Game, shown: Dictionary) -> void:
	stats["hits_withdrawn"] += 1
	var marker_at: float = shown["marker_at"]
	if marker_at >= 0.0 and game.hit_mark_at == marker_at and game.hit_mark_until > game.clock:
		game.hit_mark_until = game.clock
	var specks: Array = shown["specks"]
	for s: Variant in specks:
		game.specks.erase(s)
	specks.clear()


# ------------------------------------------------------------------ pickups


## Pickups our drawn player reaches and would take: shown taken (sound and
## word) once, and out of the picture until the copy plays it or WINDOW
## passes. Returns the copy's list to put back (empty: nothing hidden).
func _pickups(game: Game, me: Player, seq: int) -> Array:
	var lying: Array = game.pickups
	var uids := {}
	for entry: Array in lying:
		var uid: int = entry[3] if entry.size() > 3 else -1
		uids[uid] = true
		if uid < 0 or taken.has(uid) or not game.reaches_pickup(entry):
			continue
		if not would_take(me, str(entry[0])) or not NetGunLead.leads(game, me):
			continue
		taken[uid] = seq
		stats["pickups"] += 1
		var name := str(Game.ALIAS.get(str(entry[0]), str(entry[0])))
		var shown := {
			"kind": "pickup",
			"key": "pickup:%d" % uid,
			"seq": seq,
			"gun": -1,
			"cues": [],
			"matched": false,
			"hit": false,
			"marker_at": -1.0,
			"specks": [],
		}
		pending.append(shown)
		var cue := (
			"key_pickup"
			if name.begins_with("key_") or Game.TASK_ITEMS.has(name)
			else "weapon_pickup" if Weapons.NAMES.has(name) else "pickup"
		)
		_say(game, shown, cue, .8)
		if Game.PICKUP_NAMES.has(name):
			game.message(str(Game.PICKUP_NAMES[name]), 1.0)
		elif Weapons.NAMES.has(name):
			game.message(str(Weapons.LABELS[Weapons.NAMES.find(name)]), 1.35)
	for uid: Variant in taken.keys():
		if not uids.has(uid):
			taken.erase(uid)  # the copy took it (or somebody did)
			stats["pickups_taken"] += 1
	if taken.is_empty():
		return []
	var drawn: Array = []
	for entry: Array in lying:
		var uid: int = entry[3] if entry.size() > 3 else -1
		if not taken.has(uid):
			drawn.append(entry)
	game.pickups = drawn
	return lying


## Whether `me` would take a pickup called `name` (game_world.gd collect's
## refusals: a full pocket, a full pouch, something it does not know).
static func would_take(me: Player, name: String) -> bool:
	name = str(Game.ALIAS.get(name, name))
	if Weapons.NAMES.has(name) or Game.TASK_ITEMS.has(name) or name.begins_with("key_"):
		return true
	if HUD.ITEMS.has(name):
		var have: int = me.inventory.get(name, 0)
		return have < 5
	if not Game.AMMO.has(name):
		return false
	var entry: Array = Game.AMMO[name]
	var gun: int = entry[0]
	return me.armory.reserve[gun] < Weapons.MAX_RESERVE[gun]


# ------------------------------------------------------------------ the copy


## Withdraws what the copy has gone WINDOW past without playing.
func _expire(game: Game, played: int) -> void:
	if played < 0:
		return
	var keep: Array = []
	for shown: Dictionary in pending:
		var seq: int = shown["seq"]
		if seq >= played - EXPIRE:
			keep.append(shown)
			continue
		if shown["kind"] == "shot" and not shown["matched"]:
			stats["withdrawn"] += 1
			if shown["hit"]:
				_withdraw_hit(game, shown)
	pending = keep
	var lying := {}
	if not taken.is_empty():
		for entry: Array in game.pickups:
			lying[entry[3] if entry.size() > 3 else -1] = true
	for uid: Variant in taken.keys():
		var seq: int = taken[uid]
		if seq < played - EXPIRE:
			taken.erase(uid)
			if lying.has(uid):
				stats["pickups_back"] += 1  # still lying there: back in the picture
			else:
				stats["pickups_taken"] += 1


func before_hands(g: GameState, p: Player, _controls: GameState.Controls) -> void:
	var game := g as Game
	_played = played_seq(_client_now())
	if _played < 0:
		return
	_expire(game, _played)
	var looks := false
	var any := false
	for shown: Dictionary in pending:
		var seq: int = shown["seq"]
		if seq > _played + WINDOW:
			continue
		any = true
		var kind: String = shown["kind"]
		if kind == "shot" or kind == "reload":
			looks = true
	if not any:
		return
	_quiet = true
	_watched = game
	game.own_quiet = looks
	_held.clear()
	_echo.held.clear()
	_echo.real = game.speaker
	_real_sound = game.sound
	game.sound = _echo
	game.speaker = _echo
	_before = {
		"shake": game.shake,
		"until": game.hit_mark_until,
		"kill": game.hit_mark_kill,
		"at": game.hit_mark_at,
		"head": game.hit_mark_head,
		"reload": p.armory.reload,
	}


func defer(call: Callable, kind: String) -> void:
	var impact := _watched.impact_kind if _watched != null else ""
	_held.append([call, kind, impact])


func held_burst(x: float, y: float, z: float, kind: String, count: int, speed: float) -> void:
	_held.append(
		[_burst_later.bind(x, y, z, kind, count, speed), "hit" if kind == "gore" else "trace", ""]
	)


func _burst_later(x: float, y: float, z: float, kind: String, count: int, speed: float) -> void:
	if _watched != null:
		_specks(_watched, x, y, z, kind, count, speed)


func after_hands(g: GameState, p: Player, _controls: GameState.Controls) -> void:
	if not _quiet:
		if _played >= 0 and p.armory.shot_age == 0.0:
			_late()  # nothing shown in reach: a shot nobody foresaw, as ever
		return
	var game := g as Game
	_quiet = false
	game.own_quiet = false
	game.speaker = _echo.real
	game.sound = _real_sound
	var arms: Weapons.Armory = p.armory
	var fired := arms.shot_age == 0.0
	var until: float = _before["until"]
	var hit_now := game.hit_mark_until != until
	var drop := {}
	var shot := _oldest("shot") if fired else {}
	if not shot.is_empty():
		shot["matched"] = true
		stats["confirmed"] += 1
		var seq: int = shot["seq"]
		if sent_ms.has(seq):
			var pressed: float = sent_ms[seq]
			copy_ms.append(_now() - pressed)
		game.shake = _before["shake"]
		var feel: GameFeature = game.features.get("feel")
		if feel != null:
			feel.call("skip_kick")
		drop["shot"] = true
		drop["trace"] = true
		if shot["hit"]:
			drop["hit"] = true
			if hit_now:
				stats["hits_confirmed"] += 1
				if not (game.hit_mark_kill and not _before["kill"]):
					# Ours stands; a kill the host gave shows as the host has it.
					game.hit_mark_until = _before["until"]
					game.hit_mark_kill = _before["kill"]
					game.hit_mark_at = _before["at"]
					game.hit_mark_head = _before["head"]
			else:
				_withdraw_hit(game, shot)
	elif fired:
		_late()
	var was_reload: float = _before["reload"]
	if was_reload <= 0.0 and arms.reload > 0.0:
		var reload := _oldest("reload")
		if not reload.is_empty():
			reload["matched"] = true
			drop["reload"] = true
	var impact := game.impact_kind
	for item: Array in _held:
		if drop.has(str(item[1])):
			continue
		game.impact_kind = str(item[2])
		var call: Callable = item[0]
		call.call()
	game.impact_kind = impact
	_held.clear()
	for entry: Array in _echo.held:
		if _heard(str(entry[0])):
			stats["sounds_dropped"] += 1
		else:
			_echo.let_out(entry)
	_echo.held.clear()
	_watched = null


## The copy fired our gun with nothing shown for it: its own looks played.
func _late() -> void:
	stats["late"] += 1
	if sent_ms.has(_played):
		var pressed: float = sent_ms[_played]
		copy_ms.append(_now() - pressed)


## The oldest shown thing of `kind` not matched yet, in WINDOW of where the
## copy is ({} none).
func _oldest(kind: String) -> Dictionary:
	for shown: Dictionary in pending:
		var seq: int = shown["seq"]
		if shown["kind"] == kind and not shown["matched"] and seq <= _played + WINDOW:
			return shown
	return {}


## Whether `cue` was heard already (shown in WINDOW, not heard back yet).
func _heard(cue: String) -> bool:
	for shown: Dictionary in pending:
		var seq: int = shown["seq"]
		if seq > _played + WINDOW:
			continue
		var cues: Array = shown["cues"]
		var at := cues.find(cue)
		if at >= 0:
			cues.remove_at(at)
			return true
	return false
