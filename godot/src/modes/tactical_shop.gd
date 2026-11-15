## The 5v5 round modes' money and guns (tactical_mode.gd): what everything
## costs, what a round pays, what a kill is worth and how hard each gun hits
## another player.
##
## The economy, by the numbers:
##   - everyone starts a half with START_MONEY and can hold MAX_MONEY;
##   - the team that takes a round gets WIN_REWARD (OBJECTIVE_REWARD when it
##     was the bomb going up, the fuse cut or a hostage got out);
##   - the team that loses gets LOSS_BASE, LOSS_STEP more for every loss in a
##     row before it, at most LOSS_MAX (a win takes one off the run);
##   - attackers who lose after planting get PLANT_TEAM_BONUS each on top;
##   - the planter, the one who cuts the fuse and the one who carries a
##     hostage out get their own bonus;
##   - each kill pays by the gun that did it (a crowbar kill pays most).
## A gun bought takes the place of the long gun you had (one long gun at a
## time, as in the county's own sporting goods aisle); the .38 and the
## crowbar are always yours.
class_name TacticalShop
extends RefCounted

const ModeFeature := preload("res://src/features/mode_feature.gd")

## Everything below the code's own lists comes from data/tuning/store.cfg
## (_load), so the store and the money are balanced there, not here.
const DATA := "res://data/tuning/store.cfg"
static var START_MONEY := 800
static var MAX_MONEY := 16000
static var WIN_REWARD := 3250
static var OBJECTIVE_REWARD := 3500
static var LOSS_BASE := 1400
static var LOSS_STEP := 500
static var LOSS_MAX := 3400
static var PLANT_TEAM_BONUS := 800
static var PLANT_REWARD := 300
static var DEFUSE_REWARD := 300
static var HOSTAGE_TAKE_REWARD := 150
static var RESCUE_REWARD := 1000
static var VEST := 100
## [id, label, price, gun (-1: gear), loaded, reserve, group, who may buy it]:
## who "" anyone, "outlaws" or "deputies" only the side that plays them this
## half, "defense" only the deputies in search and destroy (store.cfg
## [item.*], in menu order).
static var ITEMS: Array = []
## The store's rules by id ({kinds, most, cash, least}; store.cfg [rules.*]).
static var RULES: Dictionary = {}
static var RULE_IDS: Array = []
static var RULE_NAMES: Array = []
## Each side's pistol at the start of a round: the outlaws' .38, the
## deputies' issue .45 ([gun, rounds loaded, rounds spare]).
const SIDE_PISTOL := [[Weapons.REVOLVER, 6, 36], [Weapons.COUNTY45, 8, 40]]
## The sidearms (the 2 key goes round the ones held).
const SIDEARMS := [
	Weapons.REVOLVER, Weapons.COUNTY45, Weapons.HOGLEG, Weapons.STAR357, Weapons.PRESSURE
]
## The long guns: one at a time.
const LONG_GUNS := [
	Weapons.SHOTGUN,
	Weapons.RIOT_PUMP,
	Weapons.GREASE_GUN,
	Weapons.TOMMY,
	Weapons.MARKSMAN,
	Weapons.PATROL_BAR,
	Weapons.TEAT,
	Weapons.RIVETER,
	Weapons.RIPSAW,
	Weapons.RIFLE,
	Weapons.ARMGUN,
	Weapons.ROCKET,
	Weapons.HUNTER,
	Weapons.MOWER,
	Weapons.CROSSBOW,
	Weapons.BOWLING,
	Weapons.KEG,
	Weapons.COW,
	Weapons.SLING,
]
const MAX_STICKS := 1
## Throwables a player may carry at once, all kinds together.
const MAX_THROWN := 4
## The ones that are thrown, the 4 key going round those held.
const THROWABLES := [
	Weapons.DYNAMITE,
	Weapons.FLASH_JAR,
	Weapons.SMUDGE_POT,
	Weapons.SHINE_COCKTAIL,
	Weapons.FIRECRACKER_CAN,
]
## The store's pages: the guns, then gear and throwables.
const GEAR_GROUPS := ["GEAR", "THROWN"]
## What a kill pays, by the gun in the killer's hands (store.cfg [hit.*] kill).
static var KILL_REWARD: Dictionary = {}
static var KILL_DEFAULT := 300
## A gun's hit on another player: [times what it does to a hand, the part a
## vest lets through to health, times on the head] (store.cfg [hit.*] damage).
static var DAMAGE: Dictionary = {}
static var DAMAGE_DEFAULT: Array = [1.0, .7, 1.0]
## A blast on another player, by the shot's kind, and the part a vest lets
## through (store.cfg [blast]).
static var BLAST_SCALE: Dictionary = {}
static var BLAST_DEFAULT := 2.0
static var BLAST_THROUGH := .6
## Where a hit counts as the head (0 the feet, 1 the top of the head).
static var HEAD_FROM := .8
## Accuracy on the move, by kind of gun (store.cfg [spread]).
static var MOVE_SPREAD: Dictionary = {}
static var STILL_BELOW := .9
static var RUN_SPEED := 3.85
static var AIR_SPREAD := .08
static var SCOPED_MOVE := 1.6
static var CROUCH_SCALE := .7
## How far a gun reaches in these maps, and its falloff [full damage out to,
## the share left at reach] (store.cfg [hit.*] reach, falloff).
static var REACH: Dictionary = {}
static var FALLOFF: Dictionary = {}
static var _loaded := _load()


## Read data/tuning/store.cfg into the tables above.
static func _load() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(DATA) != OK:
		push_error("cannot read " + DATA)
		return false
	var guns := Tuning.sections(Tuning.WEAPONS)
	var e := "economy"
	START_MONEY = cfg.get_value(e, "start_money", START_MONEY)
	MAX_MONEY = cfg.get_value(e, "max_money", MAX_MONEY)
	WIN_REWARD = cfg.get_value(e, "win_reward", WIN_REWARD)
	OBJECTIVE_REWARD = cfg.get_value(e, "objective_reward", OBJECTIVE_REWARD)
	LOSS_BASE = cfg.get_value(e, "loss_base", LOSS_BASE)
	LOSS_STEP = cfg.get_value(e, "loss_step", LOSS_STEP)
	LOSS_MAX = cfg.get_value(e, "loss_max", LOSS_MAX)
	PLANT_TEAM_BONUS = cfg.get_value(e, "plant_team_bonus", PLANT_TEAM_BONUS)
	PLANT_REWARD = cfg.get_value(e, "plant_reward", PLANT_REWARD)
	DEFUSE_REWARD = cfg.get_value(e, "defuse_reward", DEFUSE_REWARD)
	HOSTAGE_TAKE_REWARD = cfg.get_value(e, "hostage_take_reward", HOSTAGE_TAKE_REWARD)
	RESCUE_REWARD = cfg.get_value(e, "rescue_reward", RESCUE_REWARD)
	VEST = cfg.get_value(e, "vest", VEST)
	KILL_DEFAULT = cfg.get_value(e, "kill_default", KILL_DEFAULT)
	ITEMS = []
	RULES = {}
	RULE_IDS = []
	RULE_NAMES = []
	KILL_REWARD = {}
	DAMAGE = {}
	REACH = {}
	FALLOFF = {}
	for section: String in cfg.get_sections():
		if section.begins_with("item."):
			var gun_name := str(cfg.get_value(section, "gun", ""))
			var label := str(cfg.get_value(section, "label", ""))
			var price: int = cfg.get_value(section, "price", 0)
			var loaded: int = cfg.get_value(section, "loaded", 0)
			var reserve: int = cfg.get_value(section, "reserve", 0)
			(
				ITEMS
				. append(
					[
						section.substr(5),
						label,
						price,
						guns.find(gun_name) if gun_name != "" else -1,
						loaded,
						reserve,
						str(cfg.get_value(section, "group", "")),
						str(cfg.get_value(section, "who", "")),
					]
				)
			)
		elif section.begins_with("rules."):
			var id := section.substr(6)
			var rule := {}
			for key: String in ["kinds", "most", "cash", "least"]:
				if cfg.has_section_key(section, key):
					rule[key] = cfg.get_value(section, key)
			RULES[id] = rule
			RULE_IDS.append(id)
			RULE_NAMES.append(str(cfg.get_value(section, "name", id.to_upper())))
		elif section.begins_with("hit."):
			var gun := guns.find(section.substr(4))
			if gun < 0:
				push_error("%s: no gun called %s" % [DATA, section.substr(4)])
				continue
			if cfg.has_section_key(section, "kill"):
				var kill: int = cfg.get_value(section, "kill")
				KILL_REWARD[gun] = kill
			if cfg.has_section_key(section, "damage"):
				DAMAGE[gun] = cfg.get_value(section, "damage")
			if cfg.has_section_key(section, "reach"):
				var gun_reach: float = cfg.get_value(section, "reach")
				REACH[gun] = gun_reach
			if cfg.has_section_key(section, "falloff"):
				FALLOFF[gun] = cfg.get_value(section, "falloff")
	DAMAGE_DEFAULT = cfg.get_value("hit", "damage_default", DAMAGE_DEFAULT)
	HEAD_FROM = cfg.get_value("hit", "head_from", HEAD_FROM)
	BLAST_SCALE = {}
	for key: String in cfg.get_section_keys("blast"):
		var scale: float = cfg.get_value("blast", key)
		if key == "default":
			BLAST_DEFAULT = scale
		elif key == "through":
			BLAST_THROUGH = scale
		else:
			BLAST_SCALE[key] = scale
	MOVE_SPREAD = {}
	for key: String in cfg.get_section_keys("spread"):
		var value: float = cfg.get_value("spread", key)
		match key:
			"still_below":
				STILL_BELOW = value
			"run_speed":
				RUN_SPEED = value
			"air":
				AIR_SPREAD = value
			"scoped":
				SCOPED_MOVE = value
			"crouch":
				CROUCH_SCALE = value
			_:
				MOVE_SPREAD[key.replace("_", " ")] = value
	return true


static func item(id: String) -> Array:
	for row: Array in ITEMS:
		if str(row[0]) == id:
			return row
	return []


static func kill_reward(weapon: int) -> int:
	var reward: int = KILL_REWARD.get(weapon, KILL_DEFAULT)
	return reward


## Whether the match's rules sell item `row` at all.
static func by_rules(st: ModeFeature, row: Array) -> bool:
	var rule: Dictionary = RULES.get(String(st.store_rules), {})
	if rule.has("kinds"):
		var kinds: Array = rule["kinds"]
		if not kinds.has(str(row[6])):
			return false
	var price: int = row[2]
	var most: int = rule.get("most", MAX_MONEY)
	return price <= most


## `cash` at a round's start under the match's rules.
static func rule_cash(st: ModeFeature, cash: int) -> int:
	var rule: Dictionary = RULES.get(String(st.store_rules), {})
	if rule.has("cash"):
		var fixed: int = rule["cash"]
		return fixed
	var least: int = rule.get("least", 0)
	return maxi(cash, least)


## The dearest gun the rules sell `p` that `cash` buys and `p` lacks ("" none):
## a bot's buy when its usual one is not for sale.
static func rule_pick(game: Game, st: ModeFeature, p: Player, cash: int) -> String:
	var best := ""
	var price := -1
	for row: Array in ITEMS:
		var kind := str(row[6])
		var gun: int = row[3]
		if gun < 0 or kind == "THROWN" or kind == "GEAR":
			continue
		if not allowed(game, st, p, row) or owned_fully(st, p, row):
			continue
		var cost := price_for(st, p, row)
		if cost <= cash and cost > price:
			best = str(row[0])
			price = cost
	return best


## Whether `p` may buy item `row` at all (the rules, its side), ignoring the
## money.
static func allowed(game: Game, st: ModeFeature, p: Player, row: Array) -> bool:
	if not by_rules(st, row):
		return false
	var who := str(row[7])
	if who == "defense":
		return Modes.mode_of(game) == Modes.BOMB and TacticalMode.defends(st, p)
	if who == "outlaws":
		return TacticalMode.side_of(st, p) == 0
	if who == "deputies":
		return TacticalMode.side_of(st, p) == 1
	return true


## The rows `p`'s side sees in the store, in order.
static func menu(game: Game, st: ModeFeature, p: Player) -> Array:
	var rows: Array = []
	for row: Array in ITEMS:
		if allowed(game, st, p, row):
			rows.append(row)
	return rows


## Whether `p` already has all of item `row` there is to have.
static func owned_fully(st: ModeFeature, p: Player, row: Array) -> bool:
	var id := str(row[0])
	var a: Weapons.Armory = p.armory
	match id:
		"vest":
			var armor: float = st.armor[p.slot]
			return armor >= VEST
		"vest_hat":
			var armor: float = st.armor[p.slot]
			var helmet: bool = st.helmet[p.slot]
			return armor >= VEST and helmet
		"snips":
			var snips: bool = st.snips[p.slot]
			return snips
		"dynamite":
			return a.owned[Weapons.DYNAMITE] and a.reserve[Weapons.CROSSBOW] >= MAX_STICKS
	var gun: int = row[3]
	if Weapons.THROWN_GUNS.has(gun):
		var most: int = Weapons.MAX_RESERVE[gun]
		return a.owned[gun] and a.reserve[gun] >= most
	var reserve: int = row[5]
	var loaded: int = row[4]
	return a.owned[gun] and a.reserve[gun] >= reserve and a.loaded[gun] >= loaded


## What the item costs `p` now: a hard hat alone when the vest is whole.
static func price_for(st: ModeFeature, p: Player, row: Array) -> int:
	if str(row[0]) == "vest_hat":
		var armor: float = st.armor[p.slot]
		if armor >= VEST:
			return 350
	var price: int = row[2]
	return price


## Buys item `id` for `p`: "" when it was bought, else why not (for the HUD).
static func buy(game: Game, st: ModeFeature, p: Player, id: String) -> String:
	var said := why_not(game, st, p, id)
	if said != "":
		return said
	var row := item(id)
	var money: int = st.money[p.slot]
	st.money[p.slot] = money - price_for(st, p, row)
	give(st, p, row)
	return ""


## Why `p` may not buy item `id` now ("" when they may): the store's every
## rule, without buying (the menu asks first, then sends the buy).
static func why_not(game: Game, st: ModeFeature, p: Player, id: String) -> String:
	var row := item(id)
	if row.is_empty():
		return "NOT FOR SALE"
	if not TacticalMode.can_buy(game, st, p):
		return "BUY TIME'S OVER" if p.health > 0 else "YOU'RE OUT"
	if not by_rules(st, row):
		return "NOT IN THESE RULES"
	if not allowed(game, st, p, row):
		return "DEPUTIES ONLY"
	if owned_fully(st, p, row):
		return "ALREADY GOT IT"
	if str(row[6]) == "THROWN" and thrown_count(p) >= MAX_THROWN:
		return "HANDS FULL"
	var money: int = st.money[p.slot]
	if money < price_for(st, p, row):
		return "NOT ENOUGH CASH"
	return ""


## Item `id`'s place in ITEMS (Controls.buy), or -1.
static func index_of(id: String) -> int:
	for i in ITEMS.size():
		if str(ITEMS[i][0]) == id:
			return i
	return -1


## Puts item `row` in `p`'s hands (no money changes hands here).
static func give(st: ModeFeature, p: Player, row: Array) -> void:
	var id := str(row[0])
	var a: Weapons.Armory = p.armory
	match id:
		"vest":
			st.armor[p.slot] = VEST
			return
		"vest_hat":
			st.armor[p.slot] = VEST
			st.helmet[p.slot] = true
			return
		"snips":
			st.snips[p.slot] = true
			return
		"dynamite":
			a.owned[Weapons.DYNAMITE] = true
			a.reserve[Weapons.CROSSBOW] = mini(MAX_STICKS, a.reserve[Weapons.CROSSBOW] + 1)
			return
	var gun: int = row[3]
	if Weapons.THROWN_GUNS.has(gun):
		a.owned[gun] = true
		var most: int = Weapons.MAX_RESERVE[gun]
		a.reserve[gun] = mini(most, a.reserve[gun] + 1)
		return
	if LONG_GUNS.has(gun):
		for other: int in LONG_GUNS:
			if other != gun and a.owned[other]:
				a.owned[other] = false
				a.loaded[other] = 0
				a.reserve[other] = 0
	a.owned[gun] = true
	var loaded: int = row[4]
	var reserve: int = row[5]
	a.loaded[gun] = loaded
	a.reserve[gun] = reserve
	a.active = gun
	a.reload = 0.0
	a.switch = .2


## The kit everyone has whatever happens: the crowbar and their side's
## loaded pistol (`side` 0 the outlaws' .38, 1 the deputies' .45).
static func base_kit(p: Player, side := 0) -> void:
	var a: Weapons.Armory = p.armory
	var pistol: Array = SIDE_PISTOL[clampi(side, 0, 1)]
	var gun: int = pistol[0]
	for i in Weapons.COUNT:
		a.owned[i] = i == Weapons.CROWBAR or i == gun
		a.loaded[i] = 0
		a.reserve[i] = 0
	var loaded: int = pistol[1]
	var reserve: int = pistol[2]
	a.loaded[gun] = loaded
	a.reserve[gun] = reserve
	a.active = gun
	settle(a)


## A survivor's guns at a new round: kept, every one topped up to what a
## fresh one comes with.
static func top_up(p: Player, side := 0) -> void:
	var a: Weapons.Armory = p.armory
	var pistol: Array = SIDE_PISTOL[clampi(side, 0, 1)]
	var own: int = pistol[0]
	a.owned[Weapons.CROWBAR] = true
	a.owned[own] = true
	var own_loaded: int = pistol[1]
	var own_spare: int = pistol[2]
	a.loaded[own] = own_loaded
	a.reserve[own] = maxi(a.reserve[own], own_spare)
	for row: Array in ITEMS:
		var gun: int = row[3]
		if gun < 0 or gun == Weapons.DYNAMITE or Weapons.THROWN_GUNS.has(gun) or not a.owned[gun]:
			continue
		var loaded: int = row[4]
		var reserve: int = row[5]
		a.loaded[gun] = maxi(a.loaded[gun], loaded)
		a.reserve[gun] = maxi(a.reserve[gun], reserve)
	if not a.owned[a.active]:
		a.active = own
	settle(a)


static func settle(a: Weapons.Armory) -> void:
	a.reload = 0.0
	a.cooldown = 0.0
	a.fuse = 0.0
	a.tnt_latched = false
	a.switch = 0.0
	a.holstered = false


## How far a gun's shot reaches (a thrown or flying shot: far).
static func reach(gun: int) -> float:
	if gun < 0 or gun >= Weapons.FIRING.size():
		return 0.0
	if REACH.has(gun):
		var gun_reach: float = REACH[gun]
		return gun_reach
	var how: Dictionary = Weapons.FIRING[gun]
	if how.has("range"):
		var shot_range: float = how["range"]
		return shot_range
	if how.has("melee_range"):
		var melee_range: float = how["melee_range"]
		return melee_range
	return 40.0


## The gun a bot wants for a foe `distance` away: the best it holds that
## reaches, else the one that reaches furthest.
static func gun_for(p: Player, distance: float) -> int:
	var a: Weapons.Armory = p.armory
	var far := -1
	var far_reach := 0.0
	for gun: int in BOT_ORDER:
		if not a.owned[gun] or (a.loaded[gun] <= 0 and a.reserve[gun] <= 0):
			continue
		if distance < SNIPER_CLOSE and gun in [Weapons.HUNTER, Weapons.MARKSMAN]:
			continue  # up close a scope is too slow: the sidearm
		var r := sweet(gun)
		if r >= distance:
			return gun
		if r > far_reach:
			far_reach = r
			far = gun
	return far if far >= 0 else Weapons.CROWBAR


## How far a gun does most of its damage (a bot's choice of gun goes by it).
static func sweet(gun: int) -> float:
	if FALLOFF.has(gun):
		var f: Array = FALLOFF[gun]
		var full: float = f[0]
		return lerpf(full, reach(gun), .4)
	return reach(gun)


## The share of a hit that lands from `distance` away (FALLOFF).
static func falloff(gun: int, distance: float) -> float:
	if not FALLOFF.has(gun):
		return 1.0
	var f: Array = FALLOFF[gun]
	var full: float = f[0]
	if distance <= full:
		return 1.0
	var end := maxf(full + .01, reach(gun))
	var left: float = f[1]
	return lerpf(1.0, left, clampf((distance - full) / (end - full), 0.0, 1.0))


## A gun's kind in the store ("RIFLE", "PISTOL"...; the kit pistols too).
static func kind_of(gun: int) -> String:
	if _kinds.is_empty():
		for row: Array in ITEMS:
			var row_gun: int = row[3]
			if row_gun >= 0:
				_kinds[row_gun] = str(row[6])
		_kinds[Weapons.REVOLVER] = "PISTOL"
		_kinds[Weapons.COUNTY45] = "PISTOL"
	return str(_kinds.get(gun, ""))


static var _kinds := {}

## Nearer than this a bot leaves a sniper rifle for its next gun.
const SNIPER_CLOSE := 5.0

## The bots' order of preference among what they hold.
const BOT_ORDER := [
	Weapons.HUNTER,
	Weapons.MARKSMAN,
	Weapons.MOWER,
	Weapons.PATROL_BAR,
	Weapons.ARMGUN,
	Weapons.RIFLE,
	Weapons.TOMMY,
	Weapons.GREASE_GUN,
	Weapons.RIVETER,
	Weapons.RIPSAW,
	Weapons.SHOTGUN,
	Weapons.TEAT,
	Weapons.RIOT_PUMP,
	Weapons.PRESSURE,
	Weapons.STAR357,
	Weapons.HOGLEG,
	Weapons.COUNTY45,
	Weapons.REVOLVER,
	Weapons.CROWBAR,
]


## What a bot holds walking about: the best gun it has that reaches across a
## room and down a lane.
static func best_gun(p: Player) -> int:
	return gun_for(p, 15.0)


## Throwables `p` carries now, every kind together.
static func thrown_count(p: Player) -> int:
	var a: Weapons.Armory = p.armory
	var n := a.reserve[Weapons.CROSSBOW] if a.owned[Weapons.DYNAMITE] else 0
	for gun: int in Weapons.THROWN_GUNS:
		if a.owned[gun]:
			n += a.reserve[gun]
	return n


## The rows of one page of `p`'s store (0 the guns, 1 gear and throwables).
static func page_rows(game: Game, st: ModeFeature, p: Player, page: int) -> Array:
	var rows: Array = []
	for row: Array in menu(game, st, p):
		if (page == 1) == GEAR_GROUPS.has(str(row[6])):
			rows.append(row)
	return rows
