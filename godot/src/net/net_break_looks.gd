## Something our bullets break comes apart at the press (pass 13). A break
## changes the level (the piece's picture, the floor it frees: play), so the
## copy breaks it only when it plays our input, a round trip and the playout
## later, and a break drawn early and then not given would have to come back
## whole. Looks only, and only when it is sure (`sure`): the piece stands
## still, our line passes well inside it with the gun's whole spread, every
## round of the shot strikes it, together they are more than its health on
## the copy (which only ever goes down), nothing stands or could step in
## front by the host's turn for our input, it is no sign that cracks first
## and it stands in nobody's way (a piece with furniture under it: its real
## pieces would start inside that, which the copy still has). Then from the
## press it is drawn broken (breakables.gd drawn_broken: its broken picture,
## its sound and bits), its real pieces fly (wreckage.gd break_early), and a
## hazard barrel, a tank or a crate of dynamite goes up its fuse later
## (net_own_shots.gd's blast looks). When the copy breaks it, breakables.gd
## asks break_shown() and leaves out its sounds, bits and specks, wreckage.gd
## throws nothing more, and the copy's blast is kept quiet (blast_shown);
## the piece's floor, its volume and everything the break sets off stay the
## copy's, a round trip later.
class_name NetBreakLooks
extends RefCounted

## Off: everything breaks when the copy plays it (net_feel `old`).
static var enabled := true
const Breakables := preload("res://src/features/breakables.gd")
## Inputs past our press, once the copy plays it, before a break it did not
## give is let go (the piece whole again).
const GIVE_UP := 24
## Seconds after the copy's break a record is kept (for its blast).
const KEEP := 2.0

## Shown: {"i", "seq", "at" (ms), "first", "from", "to", "damage", "ax",
## "ay", "blast" (its kind, "" none), "boomed", "given"}.
var shown: Array = []
var stats := {"shown": 0, "given": 0, "withdrawn": 0, "booms": 0}


## The piece our shot along (angle, slope) by `gun` (`spent` rounds) is sure
## to break when the host plays it `ahead` ticks past the drawn copy:
## {"i", "d", "end"}, or {} none.
static func sure(
	game: Game, me: Player, gun: int, spent: int, angle: float, slope: float, ahead: int
) -> Dictionary:
	var pieces: Breakables = game.features.get("breakables")
	var wreck: Object = game.features.get("wreckage")
	if not enabled or pieces == null or wreck == null or not wreck.get("on"):
		return {}
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
		return {}
	var tuned := Modes.shot_spread(game, me, gun, how, me.armory.rifle_heat)
	var spread: Vector2 = tuned[0]
	var gun_reach: float = tuned[1]
	var reach: float = Modes.hit_reach(game, gun_reach)
	var width: float = how.get("width", 0.0)
	var pair: float = how.get("pair_spread", 0.0) if lines == 2 else 0.0
	var ax := cos(angle)
	var ay := sin(angle)
	var best := -1
	var near := reach
	for i in pieces.pieces.size():
		var p: Breakables.Piece = pieces.pieces[i]
		if p.broken:
			continue
		var dx := p.x - me.x
		var dy := p.y - me.y
		var d := dx * ax + dy * ay
		if d <= 0.0 or d >= near or absf(dx * ay - dy * ax) >= p.radius + width + d * spread.x:
			continue
		best = i
		near = d
	if best < 0:
		return {}
	var p: Breakables.Piece = pieces.pieces[best]
	var sign: bool = p.spec.get("sign", false)
	if not p.base.is_empty() or (sign and not p.cracked):
		return {}
	var off := absf((p.x - me.x) * ay - (p.y - me.y) * ax)
	if off + near * (spread.x + pair) + NetKillLooks.MARGIN >= p.radius + width:
		return {}
	var foot: float = game.world.stand(p) + p.z
	var z := me.eye + near * slope
	var up := near * spread.y + NetKillLooks.MARGIN
	if z - up < foot - .05 or z + up > foot + p.height + .05:
		return {}
	if not game.world.visible(me.x, me.y, p.x, p.y, me.eye, z):
		return {}
	if each * lines <= p.hp + .01:
		return {}
	var lead := float(ahead + NetKillLooks.SLACK) * NetSync.STEP
	var room := width + near * spread.x + NetKillLooks.MARGIN
	if NetKillLooks._in_way(game, me, null, ax, ay, slope, near, room, lead, p):
		return {}
	return {"i": best, "d": near, "end": Vector3(me.x + ax * near, me.y + ay * near, z)}


## Our sure break of piece `i` (from `sure`), our input `seq`, drawn from now.
func press(
	game: Game, me: Player, found: Dictionary, seq: int, damage: float, now_ms: float
) -> void:
	var i: int = found["i"]
	for b: Dictionary in shown:
		if b["i"] == i:
			return
	var pieces: Breakables = game.features.get("breakables")
	var p: Breakables.Piece = pieces.pieces[i]
	var end: Vector3 = found["end"]
	var from := Vector3(me.x, me.y, me.eye)
	var way := (end - from).normalized()
	(
		shown
		. append(
			{
				"i": i,
				"seq": seq,
				"at": now_ms,
				"first": true,
				"from": from,
				"to": end,
				"damage": damage,
				"ax": way.x,
				"ay": way.y,
				"blast": str(p.spec.get("blast", "")),
				"boomed": false,
				"given": -1.0,
			}
		)
	)
	stats["shown"] += 1


## This frame's breaks drawn (`played`: our input the copy plays next;
## `own` shows a blast's looks). Returns what end() puts back.
func begin(game: Game, played: int, now_ms: float, own: NetOwnShots) -> Array:
	var kept: Array = []
	if shown.is_empty():
		return kept
	var pieces: Breakables = game.features.get("breakables")
	var wreck: Object = game.features.get("wreckage")
	if pieces == null or wreck == null:
		shown.clear()
		return kept
	for b: Dictionary in shown.duplicate():
		var i: int = b["i"]
		if i >= pieces.pieces.size():
			shown.erase(b)
			continue
		var p: Breakables.Piece = pieces.pieces[i]
		var at: float = b["at"]
		var given: float = b["given"]
		var seq: int = b["seq"]
		if given < 0.0 and p.broken:
			b["given"] = now_ms
			given = now_ms
			stats["given"] += 1
		if given < 0.0 and played >= 0 and played > seq + GIVE_UP:
			shown.erase(b)  # the host never broke it: whole again
			stats["withdrawn"] += 1
			continue
		if given >= 0.0 and now_ms - given > KEEP * 1000.0:
			shown.erase(b)
			continue
		var blast: String = b["blast"]
		if blast != "" and not b["boomed"] and now_ms - at >= Breakables.FUSE_SHOT * 1000.0:
			b["boomed"] = true
			stats["booms"] += 1
			var was := own.shown_blasts.size()
			own.call("_boom", game, blast, p.x, p.y, game.world.stand(p) + p.z + p.height * .45)
			if own.shown_blasts.size() > was:
				var mine: Dictionary = own.shown_blasts[-1]
				mine["used"] = true  # matched by boom_shown, never another's
		if given >= 0.0:
			continue
		var first: bool = b["first"]
		b["first"] = false
		var ax: float = b["ax"]
		var ay: float = b["ay"]
		var from: Vector3 = b["from"]
		var to: Vector3 = b["to"]
		var damage: float = b["damage"]
		wreck.call("break_early", i, from, to, damage, first)
		var drawn := pieces.drawn_broken(i, first, ax, ay)
		if not drawn.is_empty():
			kept.append(drawn)
	return kept


static func end(game: Game, kept: Array) -> void:
	var pieces: Breakables = game.features.get("breakables")
	if pieces == null:
		return
	for i in range(kept.size() - 1, -1, -1):
		var drawn: Array = kept[i]
		pieces.drawn_back(drawn)


## Whether piece `index`'s break was drawn here (breakables.gd asks as the
## copy's own comes).
func break_shown(index: int) -> bool:
	for b: Dictionary in shown:
		if b["i"] == index:
			return true
	return false


## Whether a blast nobody threw (a broken piece going up) is one of ours
## shown already: a piece we broke, of that kind, where it stands.
func boom_shown(shot: GameState.Shot, game: Game) -> bool:
	var pieces: Breakables = game.features.get("breakables")
	if pieces == null:
		return false
	for b: Dictionary in shown:
		var i: int = b["i"]
		if not b["boomed"] or str(b["blast"]) != shot.kind or i >= pieces.pieces.size():
			continue
		var p: Breakables.Piece = pieces.pieces[i]
		if absf(p.x - shot.x) < .05 and absf(p.y - shot.y) < .05:
			b["blast"] = ""
			return true
	return false


func forget() -> void:
	shown.clear()
