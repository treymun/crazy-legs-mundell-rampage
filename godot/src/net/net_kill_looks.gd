## A hand our shot or a finisher kills falls at once. The copy only kills it
## when it plays our input, a round trip and the playout later (the host's
## health for it decides), so it stood flinching and then fell a third of a
## second after; a fall drawn at the press could not be taken back if the
## host said it lived (a body standing back up). Pass 13, looks only:
##
## - **Sure kills fall at the press.** A hit is sure when the hand cannot be
##   anywhere else by the tick the host plays our input (held by a stun or a
##   wind-up past it, or it never moves), our line passes well inside it with
##   the gun's whole spread, nothing can step or stand in the way, and the
##   least the hit can do (the weakest zone) is more than its health on the
##   copy, which only ever goes down (`sure`). From the press it is drawn
##   dead as the copy will have it (its health 0, its fall's moment, how and
##   from where it was killed, sliding as corpses.gd throws it); when the
##   copy's own kill lands its fall is drawn from our moment, so its fall's
##   dice, its ragdoll and its slide go on unbroken (`kept`, for as long as
##   the body lies there), and where it lies eases onto the copy's once both
##   are still. Never a kill that would take the body apart (an overkill's
##   gibs are the copy's).
## - **Any other killing hit reels** (`reel`): net_hit_looks.gd holds the
##   hand's flinch until the host's word, so it never stands unhurt; the
##   copy's kill then starts its fall from that pose (actor_view.gd starts a
##   ragdoll from the pose drawn), and a hit the host judged a miss lets it
##   go like any flinch.
##
## A kill drawn and not given by the host (`withdrawn`, never seen in the
## checks) puts the hand back on its feet.
class_name NetKillLooks
extends RefCounted

## Off: every kill falls when the copy plays it (net_feel `old`).
static var enabled := true
## On top of the gun's spread, how far inside the body's edge and its top and
## feet (cells) a sure kill's line must pass.
const MARGIN := .06
## Ticks of slack on the host's turn for our input (its input buffer).
const SLACK := 3
## Inputs past our press, once the copy plays it, before a kill it did not
## give is taken back.
const GIVE_UP := 24
## Seconds where the body lies eases onto the copy's once both are still.
const EASE := .3
const Corpses := preload("res://src/features/corpses.gd")
## Brains whose fall is never drawn early (in the air, a boss's own, not a body).
const NEVER := ["skeeter", "saucer", "drone", "lantern", "bessie"]

## Kills drawn: {"who": Enemy, "seq" (our input), "died" (the copy's clock it
## falls from), "how", "with", "from" (Vector2), "angle", "left", "body"
## (Tumble.Body: its slide), "given" (the copy killed it), "eased" (ms the
## ease began, -1), "still" (the copy's body came to rest)}.
var kills: Array = []
## For tools: kills drawn at the press, given by the copy, taken back, and
## killing hits that reeled instead.
## (`reels_missed`: of those, judged a miss by the host.)
var stats := {"sure": 0, "given": 0, "withdrawn": 0, "reels": 0, "reels_missed": 0}
var _feel := Tumble.Feel.new(.24, .12, .2, 2.6)
var _flung := Tumble.Feel.new(.24, .18, .28, 2.2)


func _init() -> void:
	for feel: Tumble.Feel in [_feel, _flung]:
		feel.climb = .1
		feel.pull = 1.0
		feel.hard = 1.6


## Whether `e` struck along (ax, ay, slope) from `me` at `d` cells by `gun`
## (`spent` rounds or loads) is sure to die when the host plays our input
## `ahead` ticks past the tick it is drawn at: see the file's top.
static func sure(
	game: Game, me: Player, e: Enemy, gun: int, spent: int, angle: float, slope: float, ahead: int
) -> bool:
	if not enabled or e == null or not e.alive or not e.hostile or e.dormant:
		return false
	if Enemy.BOSS_TITLES.has(e.kind) or NEVER.has(e.brain) or HitZones.metal(e):
		return false
	if e.kind == "tin_guard" or Variants.DOORS.has(e.kind):
		return false  # a shield soaks what faces it (ship_aliens.gd soak)
	if e.hop > 0.0 or e.climb_z > 0.0 or e.ladder >= 0 or e.toss > 0.0:
		return false
	var lead := float(ahead + SLACK) * NetSync.STEP
	if not _held_still(game, e, lead):
		return false
	var how: Dictionary = Weapons.FIRING[gun]
	var mode := str(how.get("fire", ""))
	var lines := 1
	var each := me.armory.num(gun, "damage")
	if mode == "pellets":
		var pellets: int = how.get("pellets", Weapons.SHOTGUN_PELLETS)
		var pellet: float = how.get("pellet_damage", Weapons.SHOTGUN_DAMAGE)
		lines = pellets * spent
		each = pellet
	elif mode == "hitscan":
		lines = 2 if spent == 2 and how.has("pair_spread") else 1
	else:
		return false
	if Modes.feature(game) != null and String(Modes.feature(game).mode) == Modes.COUNTY:
		return false  # its cards change a hit's damage (Modes.hit_amount)
	var tuned := Modes.shot_spread(game, me, gun, how, me.armory.rifle_heat)
	var spread: Vector2 = tuned[0]
	var gun_reach: float = tuned[1]
	var reach: float = Modes.hit_reach(game, gun_reach)
	var width: float = how.get("width", 0.0)
	var ax := cos(angle)
	var ay := sin(angle)
	var dx := e.x - me.x
	var dy := e.y - me.y
	var d := dx * ax + dy * ay
	if d <= .2 or d >= reach:
		return false
	var pair: float = how.get("pair_spread", 0.0) if lines == 2 else 0.0
	var off := absf(dx * ay - dy * ax) + d * (spread.x + pair) + MARGIN
	if off >= e.radius + width:
		return false
	var feet: float = e.z + game.world.stand(e)
	var z := me.eye + d * slope
	var up := d * spread.y + MARGIN
	if z - up < feet - .10 or z + up > feet + e.height + .10:
		return false
	if not game.world.visible(me.x, me.y, e.x, e.y, me.eye, z):
		return false
	# The least it can do (every line on its weakest zone) against the most
	# it can do, which must not take the body apart (an overkill's gibs).
	var least := each * lines * minf(1.0, minf(HitZones.ARMS, HitZones.LEGS))
	if least <= e.hp + .01:
		return false
	var most := each * lines
	var gibs := most >= maxf(48.0, e.max_hp * .7) and not (gun == Weapons.SHOTGUN and spent < 2)
	if game.gore and gibs:
		return false
	return not _in_way(game, me, e, ax, ay, slope, d, width + d * spread.x + MARGIN, lead)


## Whether `e` stands where it is for `lead` seconds whatever happens: a stun
## or a wind-up (no lunge) past it, or a body that never walks; not sliding
## from a boot.
static func _held_still(game: Game, e: Enemy, lead: float) -> bool:
	var brawl: Object = game.features.get("brawl")
	if brawl != null:
		var slides: Array = brawl.get("slides")
		for s: Array in slides:
			if s[0] == e.uid:
				return false
	if e.speed <= 0.0:
		return true
	if e.stun >= lead:
		return true
	var lunge: Array = Enemy.LUNGES.get(e.kind, [])
	return lunge.is_empty() and e.windup >= lead


## Whether anything could take the shot before `e` at `d` along the line:
## another hand or player that could step into it by then, a breakable, a
## drum, a prop or a set piece standing nearer.
static func _in_way(
	game: Game,
	me: Player,
	e: Enemy,
	ax: float,
	ay: float,
	slope: float,
	d: float,
	width: float,
	lead: float,
	skip: Object = null
) -> bool:
	for o: Enemy in game.enemies:
		if o == e or not o.alive or o.brain == "bessie":
			continue
		var ox := o.x - me.x
		var oy := o.y - me.y
		var od := ox * ax + oy * ay
		var drift := o.speed * lead + .3
		if od <= -drift or od >= d + drift:
			continue
		if absf(ox * ay - oy * ax) < o.radius + width + drift:
			return true
	if game.players.size() > 1 and Modes.rules(game).bullets_hit_players():
		for q: Player in game.players:
			if q == me or q.health <= 0:
				continue
			var qx := q.x - me.x
			var qy := q.y - me.y
			var qd := qx * ax + qy * ay
			if qd > -1.0 and qd < d + 1.0 and absf(qx * ay - qy * ax) < 1.2 + width:
				return true
	var pieces: Object = game.features.get("breakables")
	if pieces != null:
		var list: Array = pieces.get("pieces")
		for p: Object in list:
			if p == skip or p.get("broken"):
				continue
			var px: float = p.get("x")
			var py: float = p.get("y")
			var radius: float = p.get("radius")
			var pd := (px - me.x) * ax + (py - me.y) * ay
			if pd > 0.0 and pd < d and absf((px - me.x) * ay - (py - me.y) * ax) < radius + width:
				return true
	for point: Vector2 in game.drums.keys():
		var dd := (point.x - me.x) * ax + (point.y - me.y) * ay
		if (
			dd > 0.0
			and dd < d
			and absf((point.x - me.x) * ay - (point.y - me.y) * ax) < .24 + width
		):
			return true
	for prop: LevelData.Scenery in game.world.scenery:
		if game.scenery_used(prop):
			continue
		var sd := (prop.x - me.x) * ax + (prop.y - me.y) * ay
		if (
			sd > 0.0
			and sd < d
			and absf((prop.x - me.x) * ay - (prop.y - me.y) * ax) < prop.radius + width
		):
			return true
	var sets: SetPiecesFeature = game.features.get("set_pieces")
	if sets != null:
		var was_d: float = sets.ray_d
		var was_hit: int = sets.ray_hit
		var struck := sets.ray(me.x, me.y, me.eye, ax, ay, slope, d)
		sets.ray_d = was_d
		sets.ray_hit = was_hit
		if struck:
			return true
	return false


## Our sure kill of `e` (killed by `how`, from `from`), drawn from now:
## `seq` our input it comes from.
func shown(game: Game, e: Enemy, how: String, from: Vector2, seq: int, damage: float) -> void:
	for k: Dictionary in kills:
		if k["who"] == e:
			return
	var body := Tumble.Body.new()
	body.x = e.x
	body.y = e.y
	body.z = game.world.stand(e)
	var away := Vector2(e.x, e.y) - from
	var flung := false
	if away.length() > .01:
		var knock: float = Corpses.KNOCK.get(how, .8)
		var per: float = Corpses.PER_POINT.get(how, 0.0)
		var speed := minf(4.5, knock + per * damage)
		var lift := minf(1.6, speed * .3)
		if how in ["rifle", "mower", "tommy", "grease_gun", "patrol_bar", "crowbar", "slingblade"]:
			lift = 0.0
		elif how == "kick" or how == "kick_finish":
			lift = 1.0 if how == "kick" else 1.6
			flung = true
		away = away.normalized()
		body.vx = away.x * speed
		body.vy = away.y * speed
		body.vz = lift
	(
		kills
		. append(
			{
				"who": e,
				"seq": seq,
				"died": game.clock,
				"how": how,
				"from": from,
				"angle": e.angle,
				"left": e.face_left,
				"body": body,
				"flung": flung,
				"given": false,
				"eased": -1.0,
				"still": false,
				"x": e.x,
				"y": e.y,
			}
		)
	)
	stats["sure"] += 1


## The host judged our hit on `e` a miss: a kill drawn of it goes (it is
## alive on the copy after our shot), its body back on its feet.
func withdraw(e: Enemy) -> void:
	if not e.alive:
		return
	for k: Dictionary in kills.duplicate():
		if k["who"] == e and not k["given"]:
			kills.erase(k)
			stats["withdrawn"] += 1


## Whether a kill of `e` is drawn already (its own flinch is not wanted then).
func has(e: Enemy) -> bool:
	for k: Dictionary in kills:
		if k["who"] == e:
			return true
	return false


## Puts the kills on for this frame (`played`: our input the copy plays
## next, `now_ms` the clock, `dt` the frame's seconds); returns what end()
## puts back.
func begin(game: Game, played: int, now_ms: float, dt: float) -> Array:
	var kept: Array = []
	if kills.is_empty():
		return kept
	var here := {}
	for e: Enemy in game.enemies:
		here[e] = true
	for k: Dictionary in kills.duplicate():
		var e: Enemy = k["who"]
		if not here.has(e):
			kills.erase(k)  # cleared from the game (County Run's dead)
			continue
		var given: bool = k["given"]
		if not given:
			if not e.alive and e.died_at >= 0.0:
				k["given"] = true
				given = true
				stats["given"] += 1
			elif played >= 0 and played > _seq(k) + GIVE_UP:
				kills.erase(k)  # the host said it lived
				stats["withdrawn"] += 1
				continue
		if given and (e.alive or e.died_at < 0.0 or e.explosive):
			kills.erase(k)  # brought back (a put back before it), or taken apart
			continue
		_slide(game, k, dt)
		var row := [e, e.hp, e.died_at, e.killed_by, e.killed_with, e.killed_from]
		row.append_array([e.x, e.y, e.toss, e.angle, e.face_left, e.flinch, e.hit_flash])
		kept.append(row)
		e.died_at = k["died"]
		e.angle = k["angle"]
		e.face_left = k["left"]
		var body: Tumble.Body = k["body"]
		if not given:
			e.hp = 0.0
			e.killed_by = k["how"]
			e.killed_with = k["how"]
			e.killed_from = k["from"]
			e.flinch = 0.0
			e.hit_flash = 0.0
			e.x = body.x
			e.y = body.y
			e.toss = maxf(0.0, body.z - game.world.floor_under(body.x, body.y, body.z + .05))
			continue
		_ease(game, k, e, body, now_ms)
	return kept


## Where a kill the copy has given lies: ours while either still slides,
## then eased onto the copy's over EASE; then the copy's.
func _ease(game: Game, k: Dictionary, e: Enemy, body: Tumble.Body, now_ms: float) -> void:
	var eased: float = k["eased"]
	if eased < 0.0:
		var corpses: Object = game.features.get("corpses")
		var moving := false
		if corpses != null:
			var list: Array = corpses.get("moving")
			for b: Object in list:
				if b.get("enemy") == e:
					moving = true
		if moving or not body.rest:
			e.x = body.x
			e.y = body.y
			return
		k["eased"] = now_ms
		eased = now_ms
	var t := clampf((now_ms - eased) / (EASE * 1000.0), 0.0, 1.0)
	if t >= 1.0:
		return
	t = t * t * (3.0 - 2.0 * t)
	e.x = lerpf(body.x, e.x, t)
	e.y = lerpf(body.y, e.y, t)


## The body's slide (corpses.gd's throw, Tumble's steps; no fence it breaks).
func _slide(game: Game, k: Dictionary, dt: float) -> void:
	var body: Tumble.Body = k["body"]
	if body.rest:
		return
	var feel := _flung if k["flung"] else _feel
	var left := minf(dt, .1)
	while left > 0.0:
		var h := minf(left, NetSync.STEP * .5)
		left -= h
		if Tumble.step(game.world, body, feel, h) & Tumble.RESTED:
			body.rest = true
			return


static func _seq(k: Dictionary) -> int:
	var seq: int = k["seq"]
	return seq


static func end(kept: Array) -> void:
	for i in range(kept.size() - 1, -1, -1):
		var row: Array = kept[i]
		var e: Enemy = row[0]
		e.hp = row[1]
		e.died_at = row[2]
		e.killed_by = row[3]
		e.killed_with = row[4]
		e.killed_from = row[5]
		e.x = row[6]
		e.y = row[7]
		e.toss = row[8]
		e.angle = row[9]
		e.face_left = row[10]
		e.flinch = row[11]
		e.hit_flash = row[12]


func forget() -> void:
	kills.clear()
