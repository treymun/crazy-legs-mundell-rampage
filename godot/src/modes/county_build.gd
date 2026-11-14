## A COUNTY RUN build (CLAUDE.md "County Run"): the three weapon slots, the
## ranks of every upgrade, perk and milestone (`f`, the county feature), what
## they do to a gun's numbers, the reward cards a level up offers, and taking
## one. A card is {"type": "upgrade" | "weapon" | "perk" | "milestone", "id",
## "gun"}. Every number comes from data/tuning/county.json (CountyData).
class_name CountyBuild
extends RefCounted

## How the spare slots of an ordinary level up are drawn: weights of an
## upgrade for another carried gun, a new weapon and a perk.
const WEIGHTS := {"upgrade": 5.0, "weapon": 2.2, "perk": 2.6}
## A full set of slots still sees a weapon card this often (the swap).
const SWAP_CHANCE := .3

# ------------------------------------------------------------------ ranks


static func key(gun: int, id: String) -> String:
	return "%s/%s" % [Weapons.NAMES[gun], id]


static func rank(f, gun: int, id: String) -> int:
	return int(f.ranks.get(key(gun, id), 0)) if gun >= 0 else 0


static func perk_rank(f, id: String) -> int:
	return int(f.ranks.get("perk/" + id, 0))


static func has(f, milestone: String) -> bool:
	return int(f.ranks.get("m/" + milestone, 0)) > 0


static func milestone_rank(f, milestone: String) -> int:
	return int(f.ranks.get("m/" + milestone, 0))


static func carried(f) -> Array:
	var out: Array = []
	for gun in f.slots:
		if int(gun) >= 0:
			out.append(int(gun))
	return out


static func carries_kind(f, kind: String) -> bool:
	for gun: int in carried(f):
		if CountyData.kind_of(gun) == kind:
			return true
	return false


static func open_slot(f) -> int:
	return f.slots.find(-1)


## The value of upgrade `id` on `gun` at the rank held (0 none).
static func value(f, gun: int, id: String) -> float:
	return float(CountyData.upgrade(id).get("per", 0.0)) * rank(f, gun, id)


static func perk_value(f, id: String) -> float:
	return float(CountyData.perk(id).get("per", 0.0)) * perk_rank(f, id)


# ------------------------------------------------------------- gun numbers


## Damage times this for a hit of `gun` (HOT LOADS; the streaks are
## CountyMoves').
static func damage_scale(f, gun: int) -> float:
	return 1.0 + value(f, gun, "hot_loads")


## A reload takes this share of its time (QUICK HANDS, SLAM LOAD, BREAKAWAY).
static func reload_scale(f, gun: int, burst: bool) -> float:
	var share := 1.0 - value(f, gun, "quick_hands") - value(f, gun, "slam_load")
	if burst:
		share *= 1.0 - float(CountyData.milestone("breakaway").get("reload", .5))
	return maxf(.25, share)


## The time between shots times this (FAST HANDS, LAST STAND's swings).
static func fire_scale(f, gun: int, guarded: bool) -> float:
	var share := 1.0 / (1.0 + value(f, gun, "fast_hands"))
	if guarded and CountyData.kind_of(gun) == CountyData.MELEE:
		share *= 1.0 - float(CountyData.milestone("last_stand").get("swing", .4))
	return share


## A hitscan or pellet shot's spread times this (TIGHT CHOKE, EXTRA BUCK).
static func spread_scale(f, gun: int) -> float:
	var choke := value(f, gun, "tight_choke")
	var buck := (
		float(CountyData.upgrade("extra_buck").get("spread", 0.0)) * rank(f, gun, "extra_buck")
	)
	return maxf(.3, (1.0 - choke) * (1.0 + buck))


static func extra_pellets(f, gun: int) -> int:
	return roundi(value(f, gun, "extra_buck"))


## A melee swing's reach times this (LONG REACH).
static func reach_scale(f, gun: int) -> float:
	return 1.0 + value(f, gun, "long_reach")


## The most rounds `gun` carries (DEEP POCKETS, the rifle's FIELD MAGAZINE).
static func reserve_cap(f, gun: int) -> int:
	var most := float(Weapons.MAX_RESERVE[gun])
	most *= 1.0 + perk_value(f, "deep_pockets") + value(f, gun, "field_magazine")
	return roundi(most)


## Rounds into `gun`'s pool, up to its cap here (the armory's own add_ammo
## caps at weapons.cfg's, which DEEP POCKETS goes past). True when any went in.
static func give_ammo(game, f, gun: int, amount: int) -> bool:
	if gun < 0 or CountyData.kind_of(gun) == CountyData.MELEE:
		return false
	var a: Weapons.Armory = game.armory
	var before: int = a.reserve[gun]
	a.reserve[gun] = mini(reserve_cap(f, gun), before + amount)
	return a.reserve[gun] > before


## How full `gun` is, 0..1 (melee: always full).
static func fullness(game, f, gun: int) -> float:
	if CountyData.kind_of(gun) == CountyData.MELEE:
		return 1.0
	var a: Weapons.Armory = game.armory
	return float(a.reserve[gun]) / maxf(1.0, float(reserve_cap(f, gun)))


# ------------------------------------------------------------------ weapons


## The run's opening kit: the starting guns in the first slots, the rest of
## the armory empty and not owned.
static func start_kit(game, f) -> void:
	var start := CountyData.section("start")
	var size := maxi(1, int(start.get("slots", 3)))
	f.slots = []
	for i in size:
		f.slots.append(-1)
	var a: Weapons.Armory = game.armory
	for i in Weapons.COUNT:
		a.owned[i] = false
		a.loaded[i] = 0
		a.reserve[i] = 0
	var k := 0
	for name in start.get("weapons", ["revolver", "crowbar"]):
		var gun := Weapons.NAMES.find(String(name))
		if gun >= 0 and k < size:
			f.slots[k] = gun
			_arm(game, f, gun)
			k += 1
	sort_slots(f)
	var active := Weapons.NAMES.find(String(start.get("active", "revolver")))
	a.active = active if active >= 0 and a.owned[active] else int(carried(f)[0])
	a.reload = 0.0
	a.cooldown = 0.0
	a.fuse = 0.0
	a.switch = 0.0
	a.auto_switch = true


static func _arm(game, f, gun: int) -> void:
	var a: Weapons.Armory = game.armory
	a.owned[gun] = true
	a.loaded[gun] = Weapons.CAPACITY[gun]
	a.reserve[gun] = 0
	give_ammo(game, f, gun, int(CountyData.weapon(gun).get("reserve", Weapons.PICKUP_RESERVE[gun])))


## `gun` into slot `slot`: whatever was there goes with every upgrade on it
## (perks and milestones stay); the new one comes out loaded.
static func put_weapon(game, f, gun: int, slot: int) -> void:
	var a: Weapons.Armory = game.armory
	var old := int(f.slots[slot])
	if old >= 0:
		drop_upgrades(f, old)
		a.owned[old] = false
		a.loaded[old] = 0
		a.reserve[old] = 0
	f.slots[slot] = gun
	_arm(game, f, gun)
	a.fuse = 0.0
	a.tnt_latched = false
	if a.active == old or not a.owned[a.active]:
		a.active = gun
	a.select(gun, game)
	sort_slots(f)


## The slots in the armory's own order (empty ones last), so 1-2-3 on the
## HUD, the number keys and the next-gun key all go the same way round.
static func sort_slots(f) -> void:
	var guns := carried(f)
	guns.sort()
	for i in f.slots.size():
		f.slots[i] = guns[i] if i < guns.size() else -1


## Every upgrade on `gun` goes (a weapon replaced).
static func drop_upgrades(f, gun: int) -> void:
	var prefix := String(Weapons.NAMES[gun]) + "/"
	for k: String in f.ranks.keys():
		if k.begins_with(prefix):
			f.ranks.erase(k)


## [name, rank, most] of every upgrade on `gun` (what replacing it loses).
static func upgrades_on(f, gun: int) -> Array:
	var out: Array = []
	if gun < 0:
		return out
	for id: String in CountyData.upgrades_for(gun):
		var r := rank(f, gun, id)
		if r > 0:
			var spec := CountyData.upgrade(id)
			out.append([String(spec.get("name", id)), r, int(spec.get("ranks", 1))])
	return out


# ------------------------------------------------------------------ offers


static func _room(f, gun: int, id: String) -> bool:
	return rank(f, gun, id) < int(CountyData.upgrade(id).get("ranks", 1))


## The upgrades `gun` can still take.
static func open_upgrades(f, gun: int) -> Array:
	var out: Array = []
	for id: String in CountyData.upgrades_for(gun):
		if _room(f, gun, id):
			out.append(id)
	return out


## The perks worth offering now: ranks left, or a supply that would help.
static func open_perks(game, f) -> Array:
	var out: Array = []
	for id: String in CountyData.section("perks"):
		var spec := CountyData.perk(id)
		if bool(spec.get("supply", false)):
			if id == "patch_up" and game.player.health >= 100:
				continue
			if id == "supply_grab" and supply_target(game, f) < 0:
				continue
			out.append(id)
		elif perk_rank(f, id) < int(spec.get("ranks", 1)):
			out.append(id)
	return out


## The carried gun SUPPLY GRAB would fill: the equipped one if it is short,
## else the emptiest (-1: every one is full or melee).
static func supply_target(game, f) -> int:
	var a: Weapons.Armory = game.armory
	if carried(f).has(a.active) and fullness(game, f, a.active) < .95:
		return a.active
	var best := -1
	var low := .95
	for gun: int in carried(f):
		var full := fullness(game, f, gun)
		if full < low:
			low = full
			best = gun
	return best


static func unowned_weapons(f) -> Array:
	var out: Array = []
	for gun: int in CountyData.roster():
		if not carried(f).has(gun):
			out.append(gun)
	return out


static func _same(a: Dictionary, b: Dictionary) -> bool:
	return (
		String(a["type"]) == String(b["type"])
		and String(a["id"]) == String(b["id"])
		and int(a["gun"]) == int(b["gun"])
	)


static func _add(cards: Array, card: Dictionary) -> bool:
	for c: Dictionary in cards:
		if (
			_same(c, card)
			or (
				String(card["type"]) == "weapon"
				and String(c["type"]) == "weapon"
				and int(c["gun"]) == int(card["gun"])
			)
		):
			return false
	cards.append(card)
	return true


static func card(type: String, id: String, gun := -1) -> Dictionary:
	return {"type": type, "id": id, "gun": gun}


## The three cards for level up `entry` ([level, milestone, gun equipped]),
## drawn with the game's dice.
static func offers(game, f, entry: Array) -> Array:
	if bool(entry[1]):
		return milestone_offers(game, f)
	var rng = game.rng
	var cards: Array = []
	var equipped := int(entry[2])
	if not carried(f).has(equipped):
		equipped = game.armory.active
	# Always one for the gun in hand when the level came (or, worked out, for
	# another carried gun; or a perk that helps).
	var mine := open_upgrades(f, equipped)
	if not mine.is_empty():
		_add(cards, card("upgrade", String(rng.choice(mine)), equipped))
	else:
		var others: Array = []
		for gun: int in carried(f):
			for id: String in open_upgrades(f, gun):
				others.append(card("upgrade", id, gun))
		if not others.is_empty():
			_add(cards, rng.choice(others))
		else:
			var perks := open_perks(game, f)
			if not perks.is_empty():
				_add(cards, card("perk", String(rng.choice(perks))))
	# A slot open: a weapon to fill it, every time.
	var spare := unowned_weapons(f)
	if open_slot(f) >= 0 and not spare.is_empty():
		_add(cards, card("weapon", "", int(rng.choice(spare))))
	var tries := 0
	while cards.size() < 3 and tries < 40:
		tries += 1
		var pool := _spare_pool(game, f, cards)
		if pool.is_empty():
			break
		var total := 0.0
		for entry_w: Array in pool:
			total += float(entry_w[1])
		var roll: float = rng.random() * total
		for entry_w: Array in pool:
			roll -= float(entry_w[1])
			if roll <= 0.0:
				_add(cards, entry_w[0])
				break
	return cards


## Every card that could fill a spare place, with its weight.
static func _spare_pool(game, f, cards: Array) -> Array:
	var pool: Array = []
	var ups: Array = []
	for gun: int in carried(f):
		for id: String in open_upgrades(f, gun):
			ups.append(card("upgrade", id, gun))
	for c: Dictionary in ups:
		pool.append([c, WEIGHTS["upgrade"] / maxf(1.0, ups.size() / 3.0)])
	var spare := unowned_weapons(f)
	var swap_ok: bool = open_slot(f) >= 0 or game.rng.random() < SWAP_CHANCE
	if swap_ok:
		for gun: int in spare:
			pool.append(
				[card("weapon", "", gun), WEIGHTS["weapon"] / maxf(1.0, spare.size() / 2.0)]
			)
	var perks := open_perks(game, f)
	for id: String in perks:
		pool.append([card("perk", id), WEIGHTS["perk"] / maxf(1.0, perks.size() / 2.0)])
	var out: Array = []
	for entry: Array in pool:
		var taken := false
		for c: Dictionary in cards:
			if _same(c, entry[0]):
				taken = true
		if not taken:
			out.append(entry)
	return out


## A milestone can be offered: not taken (the spares can be again), its gun
## carried, and something to do.
static func milestone_open(game, f, id: String) -> bool:
	var spec := CountyData.milestone(id)
	if spec.is_empty():
		return false
	var most := int(spec.get("ranks", 1))
	if not bool(spec.get("again", false)) and milestone_rank(f, id) >= most:
		return false
	var needs := String(spec.get("needs", ""))
	if needs != "":
		var gun := Weapons.NAMES.find(needs)
		if gun >= 0 and not carried(f).has(gun):
			return false
		if gun < 0 and not carries_kind(f, needs):
			return false
	if id == "double_down":
		return _double_down_target(f, game.armory.active) != ""
	if id == "big_haul":
		var short: bool = game.player.health < 100
		for gun: int in carried(f):
			short = short or fullness(game, f, gun) < .95
		return short
	return true


## Three major cards: a weapon's change, a way to live longer and a move,
## when there is one of each; else the others, then the spares.
static func milestone_offers(game, f) -> Array:
	var rng = game.rng
	var by_kind := {"weapon": [], "survive": [], "move": [], "spare": []}
	for id: String in CountyData.section("milestones"):
		if milestone_open(game, f, id):
			var kind := String(CountyData.milestone(id).get("kind", "spare"))
			if by_kind.has(kind):
				by_kind[kind].append(id)
	var cards: Array = []
	for kind: String in ["weapon", "survive", "move"]:
		var ids: Array = by_kind[kind]
		if not ids.is_empty():
			_add(cards, card("milestone", String(rng.choice(ids))))
	var rest: Array = []
	for kind: String in ["weapon", "survive", "move", "spare"]:
		for id: String in by_kind[kind]:
			rest.append(id)
	while cards.size() < 3 and not rest.is_empty():
		var id := String(rest.pop_front())
		_add(cards, card("milestone", id))
	return cards


static func _double_down_target(f, gun: int) -> String:
	var best := ""
	var room := 0
	for id: String in CountyData.upgrades_for(gun):
		var left := int(CountyData.upgrade(id).get("ranks", 1)) - rank(f, gun, id)
		if left > room:
			room = left
			best = id
	return best


# ------------------------------------------------------------------ taking


## Takes `c` (a weapon card into `slot`, -1: the open one). The words for the
## build screen's log go on f.picks.
static func take(game, f, c: Dictionary, slot := -1) -> void:
	var gun := int(c["gun"])
	var id := String(c["id"])
	var words := ""
	match String(c["type"]):
		"upgrade":
			f.ranks[key(gun, id)] = rank(f, gun, id) + 1
			words = (
				"%s %s %d"
				% [
					CountyData.short_name(gun),
					CountyData.upgrade(id).get("name", id),
					rank(f, gun, id)
				]
			)
			if id == "field_magazine":
				give_ammo(game, f, gun, reserve_cap(f, gun))
		"weapon":
			# An open slot is always the one filled; a swap only when all are full.
			var into := open_slot(f) if open_slot(f) >= 0 else slot
			if into < 0:
				return
			var old := int(f.slots[into])
			put_weapon(game, f, gun, into)
			words = (
				"%s%s"
				% [CountyData.gun_name(gun), "" if old < 0 else " FOR " + CountyData.gun_name(old)]
			)
		"perk":
			var spec := CountyData.perk(id)
			words = String(spec.get("name", id))
			if id == "patch_up":
				game.player.health = mini(100, game.player.health + int(spec.get("per", 40)))
			elif id == "supply_grab":
				var target := supply_target(game, f)
				if target >= 0:
					give_ammo(
						game, f, target, roundi(reserve_cap(f, target) * float(spec.get("per", .6)))
					)
					words += " (" + CountyData.short_name(target) + ")"
			else:
				f.ranks["perk/" + id] = perk_rank(f, id) + 1
				words += " %d" % perk_rank(f, id)
		"milestone":
			var spec := CountyData.milestone(id)
			words = String(spec.get("name", id))
			f.ranks["m/" + id] = milestone_rank(f, id) + 1
			if id == "big_haul":
				game.player.health = 100
				for g: int in carried(f):
					give_ammo(game, f, g, reserve_cap(f, g))
					game.armory.loaded[g] = Weapons.CAPACITY[g]
			elif id == "double_down":
				var on_gun: int = game.armory.active
				for _k in 2:
					var up := _double_down_target(f, on_gun)
					if up != "":
						f.ranks[key(on_gun, up)] = rank(f, on_gun, up) + 1
						words += " +" + String(CountyData.upgrade(up).get("name", up))
	f.picks.append([f.level, words])


# ------------------------------------------------------------------ cards


## What a card says: [title, top line (the gun it is for, or the kind), lines
## of what it does, the tradeoff, how long it lasts].
static func describe(game, f, c: Dictionary) -> Dictionary:
	var gun := int(c["gun"])
	var id := String(c["id"])
	var out := {"title": "", "for": "", "lines": [], "trade": "", "lasts": "", "rank": ""}
	match String(c["type"]):
		"upgrade":
			var spec := CountyData.upgrade(id)
			var next := rank(f, gun, id) + 1
			var most := int(spec.get("ranks", 1))
			out["title"] = String(spec.get("name", id))
			out["for"] = CountyData.gun_name(gun)
			out["rank"] = "RANK %d OF %d" % [next, most]
			var now := ""
			if next > 1:
				now = "NOW: " + CountyData.fill(String(spec.get("text", "")), spec, next - 1, gun)
			out["lines"] = [CountyData.fill(String(spec.get("text", "")), spec, next, gun)]
			if now != "":
				out["lines"].append(now)
			out["trade"] = CountyData.fill(String(spec.get("trade", "")), spec, next, gun)
			out["lasts"] = "LASTS WHILE YOU CARRY THIS GUN"
		"weapon":
			var spec := CountyData.weapon(gun)
			out["title"] = CountyData.gun_name(gun)
			out["for"] = "NEW WEAPON"
			out["lines"] = [String(spec.get("plays", "")), CountyData.ammo_text(gun)]
			var slot := open_slot(f)
			out["trade"] = (
				"FILLS AN EMPTY SLOT" if slot >= 0 else "SLOTS FULL: PICK ONE TO SWAP OUT"
			)
			out["lasts"] = "FOR THE REST OF THE RUN"
		"perk":
			var spec := CountyData.perk(id)
			var supply := bool(spec.get("supply", false))
			var next := perk_rank(f, id) + 1
			out["title"] = String(spec.get("name", id))
			out["for"] = "SUPPLIES" if supply else "PERK"
			if not supply:
				out["rank"] = "RANK %d OF %d" % [next, int(spec.get("ranks", 1))]
			var target := supply_target(game, f) if id == "supply_grab" else -1
			out["lines"] = [
				CountyData.fill(String(spec.get("text", "")), spec, 1 if supply else next, target)
			]
			out["trade"] = String(spec.get("trade", ""))
			out["lasts"] = "RIGHT NOW" if supply else "THE WHOLE RUN, WHATEVER YOU CARRY"
		"milestone":
			var spec := CountyData.milestone(id)
			var next := milestone_rank(f, id) + 1
			out["title"] = String(spec.get("name", id))
			out["for"] = (
				{
					"weapon": "WEAPON CHANGE",
					"survive": "STAY ALIVE",
					"move": "MOVE",
					"spare": "MAJOR"
				}
				. get(String(spec.get("kind", "")), "MAJOR")
			)
			var needs := String(spec.get("needs", ""))
			if Weapons.NAMES.has(needs):
				out["for"] += ": " + CountyData.gun_name(Weapons.NAMES.find(needs))
			out["lines"] = [
				CountyData.fill(String(spec.get("text", "")), spec, next, game.armory.active)
			]
			out["trade"] = String(spec.get("trade", ""))
			out["lasts"] = (
				"RIGHT NOW"
				if id == "big_haul" or id == "double_down"
				else (
					"LASTS WHILE YOU CARRY IT"
					if String(spec.get("kind", "")) == "weapon"
					else "THE WHOLE RUN"
				)
			)
	return out


## Lines for the build screen: the slots with their upgrades, then the perks
## and milestones.
static func summary(f) -> Array:
	var out: Array = []
	for i in f.slots.size():
		var gun := int(f.slots[i])
		if gun < 0:
			out.append(["SLOT %d" % (i + 1), "EMPTY"])
			continue
		var ups := upgrades_on(f, gun)
		var bits: Array = []
		for u: Array in ups:
			bits.append("%s %d/%d" % [u[0], u[1], u[2]])
		out.append(
			[
				CountyData.gun_name(gun),
				", ".join(bits) if not bits.is_empty() else "NO UPGRADES YET"
			]
		)
	var perks: Array = []
	for id: String in CountyData.section("perks"):
		if perk_rank(f, id) > 0:
			perks.append("%s %d" % [CountyData.perk(id).get("name", id), perk_rank(f, id)])
	out.append(["PERKS", ", ".join(perks) if not perks.is_empty() else "NONE"])
	var big: Array = []
	for id: String in CountyData.section("milestones"):
		var r := milestone_rank(f, id)
		if r > 0 and not bool(CountyData.milestone(id).get("again", false)):
			big.append(
				String(CountyData.milestone(id).get("name", id)) + ("" if r < 2 else " %d" % r)
			)
	out.append(["MILESTONES", ", ".join(big) if not big.is_empty() else "NONE YET"])
	return out
