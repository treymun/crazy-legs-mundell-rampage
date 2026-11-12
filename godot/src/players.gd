## The players: who is playing, what each keeps of their own and what the party
## shares, and which player an enemy is after. The multiplayer foundation
## (CLAUDE.md "Multiplayer foundation"); there is no networking yet.
##
## game.players lists everyone by slot (index 0 is player one, a slot is never
## reused); game.local_player is the one this machine shows and hears; and
## game.player is the ACTING player, whose step the running code is: the
## local player outside the tick, each player in turn while their controls are
## played (Game.tick), an enemy's hunted player while that enemy ticks. Code
## that acts for "the player" (damage, pickups, use, the guns, an enemy's
## sight and flow field) keeps reading game.player and acts on the right one;
## code that is about the world (blasts, hazards, doors held open, triggers)
## goes over game.players; presentation follows game.local_player.
class_name Players
extends RefCounted

## What the party shares. Each name is a Dictionary every Player has: true
## makes it ONE object all players hold (a key opens its door for everyone,
## the PA patch lead is carried for the party), false gives each player their
## own (pork rinds, beer). The co-op rules flip these here and nowhere else.
## Always each player's own: place, health, gut, drunk, guns and rounds
## (Player.armory), sprint, footsteps, controls. Always the world's, one for
## everybody: stations done, doors, the pickups lying about (whoever touches
## one takes it), kills and secrets, clock, rng, enemies, scenery, triggers.
const SHARED := {
	"keys": true,
	"task_items": true,
	"inventory": false,
}

## How long an enemy stays after one player before it looks round again (with
## more than one player), and how long a player who hurt it comes first.
const RETARGET := .5
const SPITE := 4.0
## How far an enemy sees a player to pick them (its own sight is 14 cells).
const SIGHT := 14.0


## Adds a player standing at (x, y) facing `angle` and returns it: the next
## slot, guns and pockets of its own (or the party's, by SHARED), a flow field
## and, past the first, a voice placed where it stands. The first is player
## one, the local and acting player. game.flow must exist for the second on.
static func join(game, x: float, y: float, angle: float) -> Player:
	var p := Player.new(x, y, angle)
	p.slot = game.players.size()
	p.eye += game.world.elevation(x, y)
	p.armory = Weapons.Armory.new()
	var first: Player = null if game.players.is_empty() else game.players[0]
	for name: String in SHARED:
		if first != null and bool(SHARED[name]):
			p.set(name, first.get(name))
		elif name == "inventory":
			for item in HUD.ITEMS:
				p.inventory[item] = 0
			p.inventory["rinds"] = 1
	game.players.append(p)
	if first == null:
		game.local_player = p
		game.player = p
		game.armory = p.armory
		return p
	p.armory.auto_switch = first.armory.auto_switch
	p.armory.auto_reload = first.armory.auto_reload
	# Its own steps over the same floor (as player one's floor is now: a
	# fence shot down or a barrel broken stays open for it too).
	p.flow = FlowField.new(game.level, first.flow)
	if game.speaker != null:
		p.voice = PlayerVoice.new(game, p)
	return p


## Sets the acting player's Dictionary `name` (a save loading, a loadout):
## every player holding the shared one gets the new one.
static func store(game, name: String, value: Dictionary) -> void:
	if bool(SHARED.get(name, false)):
		for p: Player in game.players:
			p.set(name, value)
	else:
		game.player.set(name, value)


## Makes `p` the one this machine shows and hears.
static func set_local(game, p: Player) -> void:
	game.local_player = p
	game.focus(p)
	for each: Player in game.players:
		if each.voice != null or each == p:
			continue
		if game.speaker != null:
			each.voice = PlayerVoice.new(game, each)


static func anyone_alive(game) -> bool:
	for p: Player in game.players:
		if p.health > 0:
			return true
	return false


## The player enemy `e` is after this tick (only asked with more than one
## player; with one it is always player one). It keeps its pick RETARGET
## seconds; then a player who hurt it within SPITE, else the nearest it can
## see, else the one nearest where it last heard something, else the nearest
## alive. No dice: ties go to the lower slot, so every machine agrees.
static func hunted(game, e: Enemy) -> Player:
	var keep: Player = e.hunted
	if keep != null and keep.health > 0 and game.clock < e.hunted_until:
		return keep
	e.hunted_until = game.clock + RETARGET
	var pick: Player = null
	if e.spite != null and e.spite.health > 0 and game.clock < e.spite_until:
		pick = e.spite
	if pick == null:
		pick = _nearest_seen(game, e)
	if pick == null and e.heard != null:
		pick = nearest(game, float(e.heard[0]), float(e.heard[1]))
	if pick == null:
		pick = nearest(game, e.x, e.y)
	if pick == null:
		pick = keep if keep != null else game.players[0]
	e.hunted = pick
	return pick


## The nearest player alive to (x, y), or null when everyone is down.
static func nearest(game, x: float, y: float) -> Player:
	var best: Player = null
	var gap := INF
	for p: Player in game.players:
		if p.health <= 0:
			continue
		var d := (p.x - x) * (p.x - x) + (p.y - y) * (p.y - y)
		if d < gap:
			gap = d
			best = p
	return best


static func _nearest_seen(game, e: Enemy) -> Player:
	var eye: float = game.world.elevation(e.x, e.y) + e.z + minf(.92, e.height * .72)
	var best: Player = null
	var gap := SIGHT * SIGHT
	for p: Player in game.players:
		if p.health <= 0:
			continue
		var d := (p.x - e.x) * (p.x - e.x) + (p.y - e.y) * (p.y - e.y)
		if d < gap and game.world.visible(e.x, e.y, p.x, p.y, eye, p.eye):
			gap = d
			best = p
	return best


## The controls for each slot this tick from what tick() was handed: one
## Controls is the local player's (everyone else stands idle), a Dictionary
## maps slot -> Controls (a slot left out stands idle).
static func controls_by_slot(game, given, idle) -> Array:
	if game.players.size() == 1 and not (given is Dictionary):
		return [given]
	var out: Array = []
	out.resize(game.players.size())
	for p: Player in game.players:
		var c = null
		if given is Dictionary:
			c = given.get(p.slot)
		elif p == game.local_player:
			c = given
		out[p.slot] = c if c != null else idle
	return out
