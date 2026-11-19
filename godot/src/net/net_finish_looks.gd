## A finisher from our USE shown at the press (pass 13). Its move was the
## host's dice on the host's tick, so a client drew nothing until the copy
## played it a round trip later: the gun's swing, the blow, the man falling.
## With more than one player the move now comes from the man and the player
## (brawl.gd party_move: both known at the press, alone it stays the dice),
## so when our screen has a man in reach that the host will surely finish
## (`sure`: down to `low` of his health, which only ever goes down, or
## reeling or dazed past our input's turn; in reach and in the cone with
## room for where he can get to by then; no other man who could be nearer)
## the move is drawn from the press, looks only:
##
## - the gun's path and frames (brawl_looks.gd's, at our press's age, in
##   place of the copy's), the boot's cels for the stomp and the punt, the
##   man reeling;
## - at the blow (`wind` on): the jolt, the blow's sound, the call across the
##   screen, the blood, and the man falling (net_kill_looks.gd; a move that
##   takes him apart leaves his gibs to the copy);
## - when the copy's blow lands, brawl.gd asks finish_shown() and leaves out
##   its sounds, blood and call (its play goes as ever), and brawl_looks.gd's
##   jolt is not given again.
##
## A finisher the host never started (the copy plays our USE without one)
## lets the gun go back to the copy's and takes the fall back.
class_name NetFinishLooks
extends RefCounted

## Off: a finisher shows when the copy plays it (net_feel `old`).
static var enabled := true
const BrawlLooks := preload("res://src/features/brawl_looks.gd")
## Room (cells, radians) kept inside the reach and the cone.
const MARGIN := .12
const CONE_MARGIN := .08
## Inputs past ours, once the copy plays it, before a finisher it did not
## start is let go.
const GIVE_UP := 16

## Shown: {"seq", "uid", "who" (Enemy), "move", "at" (ms), "blown", "copy"
## (the copy's start moment once it plays it, -1), "done"}.
var shown: Array = []
var stats := {"shown": 0, "matched": 0, "withdrawn": 0}


## A fresh USE press (our input `seq`, `ahead` ticks from the drawn copy to
## the host's turn for it) with `me` as our screen has them: true when the
## host will surely finish a man, and the move is drawn from now.
func press(game: Game, me: Player, seq: int, ahead: int, now_ms: float) -> bool:
	if not enabled or game.players.size() < 2:
		return false
	for f: Dictionary in shown:
		if f["seq"] == seq:
			return true
	var brawl: Game.BrawlScript = game.features.get("brawl")
	if brawl == null or not brawl.allowed() or brawl.busy(me):
		return false
	if me.health <= 0 or game.showing_tally or game.boss_hold > 0.0:
		return false
	var e := sure(game, brawl, me, float(ahead + NetKillLooks.SLACK) * NetSync.STEP)
	if e == null:
		return false
	var move := Game.BrawlScript.party_move(brawl.picks_for(me), e, me)
	(
		shown
		. append(
			{
				"seq": seq,
				"uid": e.uid,
				"who": e,
				"move": move,
				"at": now_ms,
				"blown": false,
				"copy": -1.0,
				"c0": game.clock,
				"done": false,
			}
		)
	)
	stats["shown"] += 1
	return true


## The man brawl.gd use() will surely finish when the host plays our USE
## `lead` seconds on, as our screen stands (null: none for sure).
static func sure(game: Game, brawl: Game.BrawlScript, me: Player, lead: float) -> Enemy:
	var finish: Dictionary = Game.BrawlScript.FINISH
	var reach: float = finish["reach"]
	var cone: float = finish["cone"]
	var e := brawl.target(me, reach, cone)
	if e == null or not brawl.finishable(e):
		return null
	var low: float = finish["low"]
	var stagger: float = finish["stagger"]
	var dazed: float = brawl.dazed.get(e.uid, -1.0)
	if not (e.hp <= e.max_hp * low or e.stun >= stagger + lead or dazed > game.clock + lead):
		return null
	var drift := 0.0 if NetKillLooks._held_still(game, e, lead) else e.speed * lead
	var dx := e.x - me.x
	var dy := e.y - me.y
	var d := sqrt(dx * dx + dy * dy)
	if d + drift > reach + e.radius - MARGIN:
		return null
	if d > .35:
		var off := absf(Enemy.angle_delta(atan2(dy, dx), me.view_angle()))
		if off + drift / maxf(.35, d) > cone - CONE_MARGIN:
			return null
	for o: Enemy in game.enemies:
		if o == e or not o.alive or o.dormant or not o.hostile:
			continue
		var od := Vector2(o.x - me.x, o.y - me.y).length()
		if od - o.speed * lead < d + drift + .3:
			return null  # another who could be the nearer by then
	return e


## Whether our input `seq` started a finisher drawn here.
func has(seq: int) -> bool:
	for f: Dictionary in shown:
		if f["seq"] == seq:
			return true
	return false


## Whether `uid`'s blow by `slot` with `move` was drawn here (brawl.gd asks
## as the copy's own lands).
func finish_shown(game: Game, slot: int, uid: int, move: String, my_slot: int) -> bool:
	if slot != my_slot:
		return false
	for f: Dictionary in shown:
		if f["uid"] == uid and f["move"] == move and not f["done"]:
			f["done"] = true
			stats["matched"] += 1
			_hush_jolt(game, slot)
			return true
	return false


## brawl_looks.gd gives the copy's own blow no jolt (ours was given).
static func _hush_jolt(game: Game, slot: int) -> void:
	var brawl: Game.BrawlScript = game.features.get("brawl")
	var looks: Object = game.features.get("brawl_looks")
	if brawl == null or looks == null:
		return
	var last: Array = brawl.last_moves.get(slot, [])
	if not last.is_empty():
		looks.set("_blow_punched", last[1])


## This frame's finisher drawn on `me` (`played`: our input the copy plays
## next); `kills` takes the man's fall at the blow. Returns what end() puts
## back.
func begin(game: Game, me: Player, played: int, now_ms: float, kills: NetKillLooks) -> Dictionary:
	if shown.is_empty():
		return {}
	var brawl: Game.BrawlScript = game.features.get("brawl")
	if brawl == null:
		shown.clear()
		return {}
	var wind: float = Game.BrawlScript.FINISH["wind"]
	var last: Array = brawl.last_moves.get(me.slot, [])
	var drawn: Dictionary = {}
	for f: Dictionary in shown.duplicate():
		var at: float = f["at"]
		var age := (now_ms - at) / 1000.0
		var seq: int = f["seq"]
		var e: Enemy = f["who"]
		var copy: float = f["copy"]
		var c0: float = f["c0"]
		if copy < 0.0 and not last.is_empty() and str(last[0]) == str(f["move"]):
			var started: float = last[1]
			if started >= c0 - NetSync.STEP:
				f["copy"] = started
				copy = started
				_hush_jolt(game, me.slot)
		if copy < 0.0 and played >= 0 and played > seq + GIVE_UP:
			shown.erase(f)
			stats["withdrawn"] += 1
			kills.withdraw(e)
			continue
		if age > 1.2 and (copy >= 0.0 or f["done"]):
			shown.erase(f)
			continue
		if not f["blown"] and age >= wind:
			f["blown"] = true
			_blow(game, me, f, kills)
		if age <= 1.0:
			drawn = f
	if drawn.is_empty():
		return {}
	var kept := {
		"lag": me.weapon_lag,
		"turn": me.weapon_turn,
		"pose": me.weapon_pose,
		"had": brawl.last_moves.has(me.slot),
		"last": last,
	}
	var move: String = drawn["move"]
	var drawn_at: float = drawn["at"]
	var age := (now_ms - drawn_at) / 1000.0
	var ours := _path(move, age)
	var theirs := Vector3.ZERO
	if not last.is_empty():
		var started: float = last[1]
		var s := game.clock - started
		if s >= 0.0 and s <= 1.0:
			theirs = _path(str(last[0]), s)
	me.weapon_lag += Vector2(ours.x - theirs.x, ours.y - theirs.y)
	me.weapon_turn = deg_to_rad(ours.z)
	me.weapon_pose = BrawlLooks.frame(move, age, str(Weapons.NAMES[me.armory.active]))
	brawl.last_moves[me.slot] = [move, game.clock - age]
	var e: Enemy = drawn["who"]
	if not drawn["blown"] and e.alive:
		kept["man"] = [e, e.flinch]
		e.flinch = maxf(e.flinch, NetHitLooks.REEL_FLINCH)
	return kept


static func end(game: Game, me: Player, kept: Dictionary) -> void:
	if kept.is_empty():
		return
	if kept.has("man"):
		var man: Array = kept["man"]
		var e: Enemy = man[0]
		e.flinch = man[1]
	me.weapon_lag = kept["lag"]
	me.weapon_turn = kept["turn"]
	me.weapon_pose = kept["pose"]
	var brawl: Game.BrawlScript = game.features.get("brawl")
	if brawl == null:
		return
	if kept["had"]:
		brawl.last_moves[me.slot] = kept["last"]
	else:
		brawl.last_moves.erase(me.slot)


## The blow drawn: its jolt, sound, call and blood, and the man's fall.
func _blow(game: Game, me: Player, f: Dictionary, kills: NetKillLooks) -> void:
	var move: String = f["move"]
	var e: Enemy = f["who"]
	var row: Dictionary = Game.BrawlScript.MOVE[move]
	var feel: Object = game.features.get("feel")
	if feel != null:
		var jolt: Array = BrawlLooks.BLOW_PUNCH.get(move, BrawlLooks.KICK_PUNCH)
		var sx: float = jolt[3]
		var sy: float = jolt[4]
		feel.call("punch", jolt[0], jolt[1], jolt[2], Vector2(sx, sy))
	var cue := str(row.get("cue", "brawl_punch"))
	if row.get("round", false):
		cue = str(Weapons.NAMES[me.armory.active])
	var end := str(row.get("end", "fall"))
	game.sound_at(cue, e.x, e.y, 1.0)
	game.sound_at("gib_splat" if end != "fall" else "body_thud", e.x, e.y, .8)
	var name := str(row.get("name", ""))
	if name != "":
		game.callout = name + "!"
		game.callout_until = game.clock + 1.8
	if end != "gib" and e.alive:
		var how := str(row.get("how", "crowbar"))
		var seq: int = f["seq"]
		kills.shown(game, e, how, Vector2(me.x, me.y), seq, e.hp + 10.0)


static func _path(move: String, s: float) -> Vector3:
	var keys: Array = BrawlLooks.PATHS.get(move, [])
	if keys.is_empty():
		return Vector3.ZERO
	var prev := Vector4.ZERO
	for i in keys.size():
		var row: Array = keys[i]
		var t: float = row[0]
		var x: float = row[1]
		var y: float = row[2]
		var turn: float = row[3]
		if s <= t and i > 0:
			var k := clampf((s - prev.x) / maxf(.001, t - prev.x), 0.0, 1.0)
			k = k * k * (3.0 - 2.0 * k)
			return Vector3(lerpf(prev.y, x, k), lerpf(prev.z, y, k), lerpf(prev.w, turn, k))
		prev = Vector4(t, x, y, turn)
	return Vector3(prev.y, prev.z, prev.w)


func forget() -> void:
	shown.clear()
