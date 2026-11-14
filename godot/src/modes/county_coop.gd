## COUNTY RUN with two to four players (CLAUDE.md "County Run"): one party
## build. Everyone carries the same three guns with the same upgrades, perks
## and milestones (each their own rounds and health); XP is the party's, and
## the first player up (`leader`) picks the cards while the world holds for
## everyone. A player at 0 is down: a partner holding USE beside them for
## CoopMode.REVIVE_TIME stands them up, or they come back beside a partner
## after RESPAWN_AFTER; the run ends when everyone is down at once. The
## horde grows with the party (`CAP_PER`, `TOUGH_PER`).
##
## Every rule here reads the players by slot, never the local one, so every
## machine of an online run plays it the same (net_play.gd): the cards come
## in the leader's controls (Controls.buy: `encode`), applied in
## hold_controls before the held world returns.
class_name CountyCoop
extends RefCounted

## The spawner's cap and rate, and each hand's health, a player past the first.
const CAP_PER := .5
const TOUGH_PER := .35
## Down this long with nobody helping: back beside a partner.
const RESPAWN_AFTER := 25.0
const RESPAWN_HEALTH := 50
## The most in a party.
const MOST := 4


static func party(game) -> bool:
	return game.players.size() > 1


## The first player up by slot (null: nobody): they pick the cards.
static func leader(game) -> Player:
	for p: Player in game.players:
		if p.health > 0:
			return p
	return null


## The horde's size and toughness for the party.
static func cap_scale(game) -> float:
	return 1.0 + CAP_PER * (game.players.size() - 1)


static func tough_scale(game) -> float:
	return 1.0 + TOUGH_PER * (game.players.size() - 1)


## A tick of a party's run (CountyMode.step's, with more than one player).
static func step(game, f, dt: float) -> void:
	var up: Array = []
	for p: Player in game.players:
		if p.health > 0:
			up.append(p)
	if not up.is_empty():
		# The spawner rings each player in turn, a tick each.
		var anchor: Player = up[int(f.run_time * 8.0) % up.size()]
		game.focus(anchor, anchor != game.local_player)
		CountySpawner.tick(game, f, dt)
	CountyMoves.streaks(f)
	for p: Player in up:
		game.focus(p, p != game.local_player)
		CountyOrbs.tick(game, f, dt)
		CountyMoves.hands(game, f, dt)
	game.focus(game.local_player)
	CountyMoves.world(game, f, dt)
	_downs(game, f, dt)


## Downed players: revived by a partner holding USE beside them, or back
## beside a partner after a while.
static func _downs(game, f, dt: float) -> void:
	for p: Player in game.players:
		if p.health > 0:
			if p.down_at >= 0.0:
				p.down_at = -1.0
				p.revive = 0.0
			continue
		if f.over:
			return
		if p.down_at < 0.0:
			p.down_at = game.clock
		var helper := CoopMode._helper(game, p)
		if helper != null:
			p.revive += dt
			if p.revive >= CoopMode.REVIVE_TIME:
				Modes.stand_up(game, p, CoopMode.REVIVE_HEALTH)
				game.sound_at("key_pickup", p.x, p.y, .8)
				Modes.say(game, "%s IS BACK ON THEIR FEET." % Modes.tag(p))
		else:
			p.revive = maxf(0.0, p.revive - dt * .5)
			if game.clock - p.down_at >= RESPAWN_AFTER:
				var near := Players.nearest(game, p.x, p.y)
				if near != null:
					var at := Modes.open_spot_near(game, near.x, near.y)
					Modes.place(game, p, at.x, at.y, near.angle)
					Modes.stand_up(game, p, RESPAWN_HEALTH)


## Everyone's armory holds the party's slots: a gun the party took comes in
## loaded with its starting rounds, a gun let go leaves, and the card's own
## rounds or health reach every partner (`c`, the card taken; {} at the start).
static func share(game, f, c: Dictionary, taker: Player) -> void:
	var own: bool = game.own_step
	var acting: Player = game.player
	for q: Player in game.players:
		if q == taker:
			continue
		game.focus(q, q != game.local_player)
		var a: Weapons.Armory = q.armory
		for gun in Weapons.COUNT:
			var carried: bool = f.slots.has(gun)
			if carried and not a.owned[gun]:
				CountyBuild._arm(game, f, gun)
			elif not carried and a.owned[gun]:
				a.owned[gun] = false
				a.loaded[gun] = 0
				a.reserve[gun] = 0
		if not a.owned[a.active]:
			var first := (
				int(CountyBuild.carried(f)[0]) if not CountyBuild.carried(f).is_empty() else 0
			)
			a.active = first
			a.select(first, game)
		var id := String(c.get("id", ""))
		match String(c.get("type", "")):
			"upgrade":
				if id == "field_magazine" or id == "big_pouch":
					CountyBuild.give_ammo(
						game, f, int(c["gun"]), CountyBuild.reserve_cap(f, int(c["gun"]))
					)
			"perk":
				var spec := CountyData.perk(id)
				if id == "patch_up":
					q.health = mini(100, q.health + int(spec.get("per", 40)))
				elif id == "supply_grab":
					var target := CountyBuild.supply_target(game, f)
					if target >= 0:
						var share_of := float(spec.get("per", .6))
						CountyBuild.give_ammo(
							game, f, target, roundi(CountyBuild.reserve_cap(f, target) * share_of)
						)
			"milestone":
				if id == "big_haul":
					q.health = 100
					for g: int in CountyBuild.carried(f):
						CountyBuild.give_ammo(game, f, g, CountyBuild.reserve_cap(f, g))
						a.loaded[g] = Weapons.CAPACITY[g]
	game.focus(acting, own)


## A card choice as Controls.buy: card `index` (0..2) for an open slot, or
## 3 + slot * 3 + index to put a weapon in place of slot `slot`'s.
static func encode(index: int, slot := -1) -> int:
	return index if slot < 0 else 3 + slot * 3 + index


## Before a held tick (CountyMode.hold_controls): the leader's card, if
## their controls carry one.
static func picks(game, f, by_slot: Array) -> void:
	if f.pending.is_empty() or f.over:
		return
	var who := leader(game)
	if who == null or who.slot >= by_slot.size():
		return
	var c: Game.Controls = by_slot[who.slot]
	if c.buy < 0:
		return
	var index: int = c.buy if c.buy < 3 else (c.buy - 3) % 3
	var slot: int = -1 if c.buy < 3 else (c.buy - 3) / 3
	c.buy = -1
	var own: bool = game.own_step
	var acting: Player = game.player
	game.focus(who, who != game.local_player)
	CountyMode.choose(game, index, slot)
	game.focus(acting, own)
