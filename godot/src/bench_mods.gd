## Mundell's junk bench: the scrap a player carries and the duct-tape mods it
## buys (data/tuning/bench.cfg). The mods are numbers on the guns' own
## weapons.cfg keys (and a few of their own: bayonet, burns, blast_scale,
## fuse), read through each player's Armory (Weapons.Armory.firing, .num):
## a gun with mods on is its section with the mods' `set` and `times` put on
## it. Where the bench is, what drops scrap and the use key are the bench
## feature's (features/bench.gd); the screen is BenchScreen.
##
## Live only where BenchMods.on: WORKBENCH on, the campaign's chapters and the
## Crossroads, alone or in co-op; never the range, County Run (its runs and
## daily board are set for its own guns and offers), a player map, a boss
## rematch or a versus mode. Elsewhere a player's mods stay on them but count
## for nothing (Armory.mods_on false).
class_name BenchMods
extends RefCounted

const PATH := "res://data/tuning/bench.cfg"

## The mods' ids in the bench's order (a buy is the place in it), and each
## mod: {gun, slot, short, label, line, price, set, times}.
static var IDS: Array[String] = []
static var MODS := {}
static var _read: ConfigFile = null
## (gun slot, its mods) -> the gun's weapons.cfg section with them on; and
## -> the name of its pictures (gun_<that>_<pose>).
static var _firing := {}
static var _art := {}


## The mods' ids in the bench's order.
static func ids() -> Array[String]:
	_fresh()
	return IDS


## Read bench.cfg again when the file Tuning holds is a new one (the dev
## console's reload) or never read.
static func _fresh() -> void:
	var cfg := Tuning.file(PATH)
	if cfg == _read:
		return
	if Weapons.NAMES.is_empty():
		Weapons.load_tuning()
	_read = cfg
	IDS = []
	MODS = {}
	_firing = {}
	_art = {}
	for section: String in cfg.get_sections():
		if not section.begins_with("mod."):
			continue
		var id := section.substr(4)
		var gun := str(cfg.get_value(section, "gun", ""))
		var slot := Weapons.NAMES.find(gun)
		if slot < 0:
			push_error("bench.cfg [%s]: no gun %s" % [section, gun])
			continue
		IDS.append(id)
		var price: int = cfg.get_value(section, "price", 5)
		MODS[id] = {
			"gun": gun,
			"slot": slot,
			"short": str(cfg.get_value(section, "short", id)),
			"label": str(cfg.get_value(section, "label", id.to_upper())),
			"line": str(cfg.get_value(section, "line", "")),
			"price": price,
			"set": cfg.get_value(section, "set", {}),
			"times": cfg.get_value(section, "times", {}),
		}


static func value(section: String, key: String, fallback: Variant = null) -> Variant:
	_fresh()
	return _read.get_value(section, key, fallback)


static func mod(id: String) -> Dictionary:
	_fresh()
	var found: Dictionary = MODS.get(id, {})
	return found


## Whether the bench, its scrap and its mods are live in this game.
static func on(g: Game) -> bool:
	if not g.bench_on or g.level == null:
		return false
	if not (g.in_hub or Campaign.ORDER.has(g.level.id)):
		return false
	if BossRematch.active(g) or CountyMode.active(g) or UserMap.is_custom(g.level.id):
		return false
	var mode := Modes.mode_of(g)
	return mode == Modes.CAMPAIGN or mode == Modes.COOP


## The mods in `mods` that go on gun `slot`, by their short names in name
## order.
static func shorts(slot: int, mods: Array[String]) -> Array:
	_fresh()
	var out: Array = []
	for id: String in mods:
		var m: Dictionary = MODS.get(id, {})
		var for_slot: int = m.get("slot", -1)
		if for_slot == slot:
			out.append(str(m["short"]))
	out.sort()
	return out


## Gun `slot`'s weapons.cfg section with `mods` on (the same dictionary as
## Weapons.FIRING's when none of them is for it).
static func firing(slot: int, mods: Array[String]) -> Dictionary:
	_fresh()
	var key := "%d|%s" % [slot, ",".join(mods)]
	var made: Dictionary = _firing.get(key, {})
	if not made.is_empty():
		return made
	var base: Dictionary = Weapons.FIRING[slot]
	var mine := false
	var out := base.duplicate()
	for id: String in mods:
		var m: Dictionary = MODS.get(id, {})
		var for_slot: int = m.get("slot", -1)
		if for_slot != slot:
			continue
		mine = true
		var times: Dictionary = m["times"]
		for k: String in times:
			var by: float = times[k]
			var was: Variant = out.get(k, null)
			if was is int:
				var whole: int = was
				out[k] = roundi(whole * by)
			elif was is float:
				var part: float = was
				out[k] = part * by
			elif was is Vector2:
				var pair: Vector2 = was
				out[k] = pair * by
		var put: Dictionary = m["set"]
		for k: String in put:
			out[k] = put[k]
	made = out if mine else base
	_firing[key] = made
	return made


## The name gun `slot`'s pictures go by with `mods` on (gun_<name>_<pose>):
## rifle__brake_drum, or the gun's own when none is for it.
static func art_name(slot: int, mods: Array[String]) -> String:
	var key := "%d|%s" % [slot, ",".join(mods)]
	var known: Variant = _art.get(key)
	if known != null:
		return str(known)
	var picked := shorts(slot, mods)
	var name: String = Weapons.NAMES[slot]
	if not picked.is_empty():
		name += "__" + "_".join(picked)
	_art[key] = name
	return name


## What stops player `p` buying mod `index` now ("" nothing).
static func why_not(p: Player, index: int) -> String:
	_fresh()
	if index < 0 or index >= IDS.size():
		return "NO SUCH THING."
	var id := IDS[index]
	var m: Dictionary = MODS[id]
	if p.armory.mods.has(id):
		return "ALREADY TAPED ON."
	var slot: int = m["slot"]
	if not p.armory.owned[slot]:
		return "AIN'T GOT THE %s." % str(Weapons.LABELS[slot]).get_slice(" [", 0)
	var price: int = m["price"]
	if p.armory.scrap < price:
		return "NEED %d SCRAP. YOU GOT %d." % [price, p.armory.scrap]
	return ""


## Player `p` buys mod `index` (Controls.buy at the bench): the scrap
## spent, the mod on. True when it was bought.
static func buy(p: Player, index: int) -> bool:
	if why_not(p, index) != "":
		return false
	var id := IDS[index]
	var m: Dictionary = MODS[id]
	var price: int = m["price"]
	p.armory.scrap -= price
	var owned: Array[String] = p.armory.mods.duplicate()
	owned.append(id)
	owned.sort()
	p.armory.mods = owned
	return true


## A piece of scrap's worth (0: not scrap).
static func worth(pickup: String) -> int:
	if not pickup.begins_with("scrap_"):
		return 0
	var pieces: Dictionary = value("scrap", "pieces", {})
	var each: int = pieces.get(pickup.substr(6), 0)
	return each


## How a player's blast is scaled by the mods on what threw it: [radius,
## strength] (1, 1 when nothing does), and how much of its radius it lights.
static func blast_of(g: Game, shot: GameState.Shot) -> Array:
	if shot.enemy or shot.owner == -1 or not g.bench_live:
		return [1.0, 1.0, 0.0]
	if shot.slot < 0 or shot.slot >= g.players.size():
		return [1.0, 1.0, 0.0]
	var arm: Weapons.Armory = g.players[shot.slot].armory
	if arm.mods.is_empty():
		return [1.0, 1.0, 0.0]
	var slot := Weapons.DYNAMITE if shot.kind == "tnt" else Weapons.NAMES.find(_gun_of(shot.kind))
	if slot < 0:
		return [1.0, 1.0, 0.0]
	var how := firing(slot, arm.mods)
	var scale: Vector2 = how.get("blast_scale", Vector2.ONE)
	var burns: float = how.get("burns", 0.0)
	return [scale.x, scale.y, burns]


## The gun that fires shots of `kind` (weapons.cfg `shot`), "" none.
static func _gun_of(kind: String) -> String:
	for i in Weapons.COUNT:
		var how: Dictionary = Weapons.FIRING[i]
		if str(how.get("shot", "")) == kind:
			return str(Weapons.NAMES[i])
	return ""
