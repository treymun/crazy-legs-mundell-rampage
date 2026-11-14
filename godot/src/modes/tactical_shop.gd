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

const START_MONEY := 800
const MAX_MONEY := 16000
const WIN_REWARD := 3250
const OBJECTIVE_REWARD := 3500
const LOSS_BASE := 1400
const LOSS_STEP := 500
const LOSS_MAX := 3400
const PLANT_TEAM_BONUS := 800
const PLANT_REWARD := 300
const DEFUSE_REWARD := 300
const HOSTAGE_TAKE_REWARD := 150
const RESCUE_REWARD := 1000
const VEST := 100

## [id, label, price, gun (-1: gear), loaded, reserve, group, who may buy it]:
## who "" anyone, "outlaws" or "deputies" only the side that plays them this
## half (each has its own pistol, shotgun, sprayer, sniper and machine gun),
## "defense" only the deputies in search and destroy. The menu shows a side
## only its own and the shared rows, in this order.
const ITEMS := [
	["hogleg", "HOGLEG .44", 700, Weapons.HOGLEG, 6, 30, "PISTOL", "outlaws"],
	["star357", "STAR .357", 700, Weapons.STAR357, 6, 30, "PISTOL", "deputies"],
	["sawed_off", "SAWED-OFF", 1100, Weapons.SHOTGUN, 2, 24, "SHOTGUN", "outlaws"],
	["riot_pump", "RIOT PUMP", 1300, Weapons.RIOT_PUMP, 6, 24, "SHOTGUN", "deputies"],
	["grease_gun", "GREASE GUN", 1200, Weapons.GREASE_GUN, 30, 120, "SMG", "outlaws"],
	["tommy", "SQUAD TOMMY", 1500, Weapons.TOMMY, 50, 150, "SMG", "deputies"],
	["riveter", "MILL RIVETER", 1350, Weapons.RIVETER, 0, 60, "SPRAYER", "outlaws"],
	["teat_gun", "TEAT GUN", 1050, Weapons.TEAT, 0, 150, "SPRAYER", "outlaws"],
	["rifle", "RANCH RIFLE", 2700, Weapons.RIFLE, 0, 90, "RIFLE", ""],
	["arm_gun", "ALIEN ARM GUN", 2500, Weapons.ARMGUN, 0, 45, "RIFLE", ""],
	["hunter", "HOG HUNTER .30-06", 4750, Weapons.HUNTER, 5, 20, "SNIPER", "outlaws"],
	["marksman", "COUNTY MARKSMAN", 5000, Weapons.MARKSMAN, 10, 30, "SNIPER", "deputies"],
	["mower", "CORN MOWER", 5200, Weapons.MOWER, 100, 200, "MACHINE GUN", "outlaws"],
	["patrol_bar", "PATROL BAR", 5000, Weapons.PATROL_BAR, 60, 180, "MACHINE GUN", "deputies"],
	["rockets", "BOTTLE ROCKETS", 4200, Weapons.ROCKET, 0, 3, "HEAVY", ""],
	["vest", "TIN VEST", 650, -1, 0, 0, "GEAR", ""],
	["vest_hat", "VEST + HARD HAT", 1000, -1, 0, 0, "GEAR", ""],
	["snips", "WIRE SNIPS", 400, -1, 0, 0, "GEAR", "defense"],
	["dynamite", "DYNAMITE (HE)", 300, Weapons.DYNAMITE, 0, 1, "THROWN", ""],
	["flash_jar", "FLASH JAR", 200, Weapons.FLASH_JAR, 0, 1, "THROWN", ""],
	["smudge_pot", "SMUDGE POT (SMOKE)", 300, Weapons.SMUDGE_POT, 0, 1, "THROWN", ""],
	["shine_cocktail", "SHINE COCKTAIL", 400, Weapons.SHINE_COCKTAIL, 0, 1, "THROWN", ""],
	["firecracker_can", "FIRECRACKER CAN", 50, Weapons.FIRECRACKER_CAN, 0, 1, "THROWN", ""],
]
## The store's rules (a lobby's RULES, the picker's): which kinds of item
## are sold ("kinds", ITEMS' seventh column), the dearest item sold ("most"),
## everyone's cash at every round's start ("cash") or the least they start a
## round with ("least": the rules' guns are always within reach).
const RULES := {
	"any": {},
	"shotguns": {"kinds": ["SHOTGUN", "GEAR", "THROWN"], "least": 2000},
	"pistols": {"kinds": ["PISTOL", "GEAR"]},
	"snipers": {"kinds": ["SNIPER", "GEAR", "THROWN"], "least": 6000},
	"eco": {"most": 1500},
	"big_money": {"cash": MAX_MONEY},
}
const RULE_IDS := ["any", "shotguns", "pistols", "snipers", "eco", "big_money"]
const RULE_NAMES := [
	"ANY GUNS", "SHOTGUNS ONLY", "PISTOL PARTY", "SNIPER DUEL", "ECO WAR", "BIG MONEY"
]
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
## What a kill pays, by the gun in the killer's hands.
const KILL_REWARD := {
	Weapons.CROWBAR: 1500,
	Weapons.SLING: 1500,
	Weapons.REVOLVER: 300,
	Weapons.PRESSURE: 300,
	Weapons.SHOTGUN: 900,
	Weapons.TEAT: 600,
	Weapons.RIVETER: 600,
	Weapons.RIPSAW: 600,
	Weapons.RIFLE: 300,
	Weapons.ARMGUN: 300,
	Weapons.ROCKET: 300,
	Weapons.DYNAMITE: 300,
	Weapons.HUNTER: 100,
	Weapons.MOWER: 300,
	Weapons.MARKSMAN: 300,
	Weapons.PATROL_BAR: 300,
	Weapons.RIOT_PUMP: 900,
	Weapons.TOMMY: 600,
	Weapons.GREASE_GUN: 600,
	Weapons.COUNTY45: 300,
	Weapons.STAR357: 300,
	Weapons.HOGLEG: 300,
}
const KILL_DEFAULT := 300
## A gun's hit on another player: [times what it does to a hand, the part a
## vest lets through to health, times on the head]. Tuned so that, against a
## player with 100 health: the .38 takes three to the body or one to an
## unprotected head (the issue .45 four, but holds eight and fires faster); the HOGLEG .44
## one to the head even through a hard hat, the quicker STAR .357 two; the
## ranch rifle four (five through a vest) or a head and a bit through a hard
## hat; a sawed-off barrel up close drops anyone;
## a crowbar takes two; the Hog Hunter drops anyone with one to the body (120,
## 108 through a vest); the Corn Mower four (five through a vest).
const DAMAGE := {
	Weapons.CROWBAR: [1.25, .85, 1.0],
	Weapons.SLING: [1.0, .85, 1.0],
	Weapons.REVOLVER: [1.05, .66, 3.2],
	Weapons.SHOTGUN: [1.17, .7, 1.25],
	Weapons.RIFLE: [1.43, .78, 3.0],
	Weapons.RIPSAW: [1.1, .7, 1.5],
	Weapons.ARMGUN: [.68, .8, 2.5],
	Weapons.RIVETER: [.81, .6, 2.5],
	Weapons.PRESSURE: [1.18, .6, 2.0],
	Weapons.TEAT: [1.0, .5, 2.0],
	Weapons.ROCKET: [.5, .8, 1.0],
	Weapons.HUNTER: [.86, .9, 2.0],
	Weapons.MOWER: [1.15, .8, 2.2],
	Weapons.MARKSMAN: [1.0, .85, 2.5],
	Weapons.PATROL_BAR: [1.1, .8, 2.2],
	Weapons.RIOT_PUMP: [1.1, .7, 1.25],
	Weapons.TOMMY: [1.2, .6, 2.5],
	Weapons.GREASE_GUN: [1.1, .6, 2.5],
	Weapons.COUNTY45: [1.0, .55, 3.0],
	Weapons.STAR357: [1.0, .7, 2.5],
	Weapons.HOGLEG: [1.0, .7, 2.6],
}
const DAMAGE_DEFAULT := [1.0, .7, 1.0]
## A blast on another player, by the shot's kind: times what the level's
## blast does to a player (dynamite 30 -> 96 at its heart), and the part a
## vest lets through. The alien arm gun's little burst stays little.
const BLAST_SCALE := {"tnt": 3.2, "bottle_rocket": 3.0, "bolt": 3.0, "arm_bolt": .6}
const BLAST_DEFAULT := 2.0
const BLAST_THROUGH := .6
## Where a hit counts as the head (0 the feet, 1 the top of the head).
const HEAD_FROM := .8
## Accuracy on the move: the spread (radians, each way) a gun of each kind
## gains at a full run, from nothing at STILL_BELOW cells a second; more in
## the air; less crouched and still. A scoped sniper rifle gains SCOPED_MOVE
## times its kind's (a scope is for standing still).
const MOVE_SPREAD := {
	"PISTOL": .028,
	"SMG": .02,
	"SHOTGUN": .02,
	"SPRAYER": .015,
	"RIFLE": .05,
	"MACHINE GUN": .065,
	"SNIPER": .07,
	"HEAVY": 0.0,
}
const STILL_BELOW := .9
const RUN_SPEED := 3.85
const AIR_SPREAD := .08
const SCOPED_MOVE := 1.6
const CROUCH_SCALE := .7
## How far a gun reaches in the 5v5 modes where its own reach is short for
## these maps, and where its damage starts to fall off and what is left at
## that reach ([full damage out to, the share left at the end]). Past its
## reach a shot does nothing, as everywhere.
const REACH := {
	Weapons.REVOLVER: 34.0,
	Weapons.COUNTY45: 34.0,
	Weapons.STAR357: 38.0,
	Weapons.HOGLEG: 38.0,
	Weapons.GREASE_GUN: 30.0,
	Weapons.TOMMY: 32.0,
	Weapons.RIVETER: 22.0,
	Weapons.RIFLE: 44.0,
	Weapons.MOWER: 44.0,
	Weapons.PATROL_BAR: 44.0,
}
const FALLOFF := {
	Weapons.REVOLVER: [16.0, .55],
	Weapons.COUNTY45: [16.0, .55],
	Weapons.STAR357: [20.0, .6],
	Weapons.HOGLEG: [18.0, .6],
	Weapons.GREASE_GUN: [11.0, .5],
	Weapons.TOMMY: [12.0, .5],
	Weapons.RIVETER: [10.0, .55],
	Weapons.RIFLE: [26.0, .75],
	Weapons.MOWER: [24.0, .7],
	Weapons.PATROL_BAR: [24.0, .7],
	Weapons.SHOTGUN: [5.0, .45],
	Weapons.RIOT_PUMP: [6.0, .45],
}


static func item(id: String) -> Array:
	for row: Array in ITEMS:
		if String(row[0]) == id:
			return row
	return []


static func kill_reward(weapon: int) -> int:
	return int(KILL_REWARD.get(weapon, KILL_DEFAULT))


## Whether the match's rules sell item `row` at all.
static func by_rules(st, row: Array) -> bool:
	var rule: Dictionary = RULES.get(String(st.store_rules), {})
	if rule.has("kinds") and not (rule["kinds"] as Array).has(String(row[6])):
		return false
	return int(row[2]) <= int(rule.get("most", MAX_MONEY))


## `cash` at a round's start under the match's rules.
static func rule_cash(st, cash: int) -> int:
	var rule: Dictionary = RULES.get(String(st.store_rules), {})
	if rule.has("cash"):
		return int(rule["cash"])
	return maxi(cash, int(rule.get("least", 0)))


## The dearest gun the rules sell `p` that `cash` buys and `p` lacks ("" none):
## a bot's buy when its usual one is not for sale.
static func rule_pick(game, st, p: Player, cash: int) -> String:
	var best := ""
	var price := -1
	for row: Array in ITEMS:
		var kind := String(row[6])
		if int(row[3]) < 0 or kind == "THROWN" or kind == "GEAR":
			continue
		if not allowed(game, st, p, row) or owned_fully(st, p, row):
			continue
		var cost := price_for(st, p, row)
		if cost <= cash and cost > price:
			best = String(row[0])
			price = cost
	return best


## Whether `p` may buy item `row` at all (the rules, its side), ignoring the
## money.
static func allowed(game, st, p: Player, row: Array) -> bool:
	if not by_rules(st, row):
		return false
	var who := String(row[7])
	if who == "defense":
		return Modes.mode_of(game) == Modes.BOMB and TacticalMode.defends(st, p)
	if who == "outlaws":
		return TacticalMode.side_of(st, p) == 0
	if who == "deputies":
		return TacticalMode.side_of(st, p) == 1
	return true


## The rows `p`'s side sees in the store, in order.
static func menu(game, st, p: Player) -> Array:
	var rows: Array = []
	for row: Array in ITEMS:
		if allowed(game, st, p, row):
			rows.append(row)
	return rows


## Whether `p` already has all of item `row` there is to have.
static func owned_fully(st, p: Player, row: Array) -> bool:
	var id := String(row[0])
	var a: Weapons.Armory = p.armory
	match id:
		"vest":
			return float(st.armor[p.slot]) >= VEST
		"vest_hat":
			return float(st.armor[p.slot]) >= VEST and bool(st.helmet[p.slot])
		"snips":
			return bool(st.snips[p.slot])
		"dynamite":
			return a.owned[Weapons.DYNAMITE] and a.reserve[Weapons.CROSSBOW] >= MAX_STICKS
	var gun := int(row[3])
	if Weapons.THROWN_GUNS.has(gun):
		return a.owned[gun] and a.reserve[gun] >= int(Weapons.MAX_RESERVE[gun])
	return a.owned[gun] and a.reserve[gun] >= int(row[5]) and a.loaded[gun] >= int(row[4])


## What the item costs `p` now: a hard hat alone when the vest is whole.
static func price_for(st, p: Player, row: Array) -> int:
	if String(row[0]) == "vest_hat" and float(st.armor[p.slot]) >= VEST:
		return 350
	return int(row[2])


## Buys item `id` for `p`: "" when it was bought, else why not (for the HUD).
static func buy(game, st, p: Player, id: String) -> String:
	var said := why_not(game, st, p, id)
	if said != "":
		return said
	var row := item(id)
	st.money[p.slot] = int(st.money[p.slot]) - price_for(st, p, row)
	give(st, p, row)
	return ""


## Why `p` may not buy item `id` now ("" when they may): the store's every
## rule, without buying (the menu asks first, then sends the buy).
static func why_not(game, st, p: Player, id: String) -> String:
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
	if String(row[6]) == "THROWN" and thrown_count(p) >= MAX_THROWN:
		return "HANDS FULL"
	if int(st.money[p.slot]) < price_for(st, p, row):
		return "NOT ENOUGH CASH"
	return ""


## Item `id`'s place in ITEMS (Controls.buy), or -1.
static func index_of(id: String) -> int:
	for i in ITEMS.size():
		if String(ITEMS[i][0]) == id:
			return i
	return -1


## Puts item `row` in `p`'s hands (no money changes hands here).
static func give(st, p: Player, row: Array) -> void:
	var id := String(row[0])
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
	var gun := int(row[3])
	if Weapons.THROWN_GUNS.has(gun):
		a.owned[gun] = true
		a.reserve[gun] = mini(int(Weapons.MAX_RESERVE[gun]), a.reserve[gun] + 1)
		return
	if LONG_GUNS.has(gun):
		for other: int in LONG_GUNS:
			if other != gun and a.owned[other]:
				a.owned[other] = false
				a.loaded[other] = 0
				a.reserve[other] = 0
	a.owned[gun] = true
	a.loaded[gun] = int(row[4])
	a.reserve[gun] = int(row[5])
	a.active = gun
	a.reload = 0.0
	a.switch = .2


## The kit everyone has whatever happens: the crowbar and their side's
## loaded pistol (`side` 0 the outlaws' .38, 1 the deputies' .45).
static func base_kit(p: Player, side := 0) -> void:
	var a: Weapons.Armory = p.armory
	var pistol: Array = SIDE_PISTOL[clampi(side, 0, 1)]
	var gun := int(pistol[0])
	for i in Weapons.COUNT:
		a.owned[i] = i == Weapons.CROWBAR or i == gun
		a.loaded[i] = 0
		a.reserve[i] = 0
	a.loaded[gun] = int(pistol[1])
	a.reserve[gun] = int(pistol[2])
	a.active = gun
	settle(a)


## A survivor's guns at a new round: kept, every one topped up to what a
## fresh one comes with.
static func top_up(p: Player, side := 0) -> void:
	var a: Weapons.Armory = p.armory
	var pistol: Array = SIDE_PISTOL[clampi(side, 0, 1)]
	var own := int(pistol[0])
	a.owned[Weapons.CROWBAR] = true
	a.owned[own] = true
	a.loaded[own] = int(pistol[1])
	a.reserve[own] = maxi(a.reserve[own], int(pistol[2]))
	for row: Array in ITEMS:
		var gun := int(row[3])
		if gun < 0 or gun == Weapons.DYNAMITE or Weapons.THROWN_GUNS.has(gun) or not a.owned[gun]:
			continue
		a.loaded[gun] = maxi(a.loaded[gun], int(row[4]))
		a.reserve[gun] = maxi(a.reserve[gun], int(row[5]))
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
		return float(REACH[gun])
	var how: Dictionary = Weapons.FIRING[gun]
	if how.has("range"):
		return float(how["range"])
	if how.has("melee_range"):
		return float(how["melee_range"])
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
		return lerpf(float(f[0]), reach(gun), .4)
	return reach(gun)


## The share of a hit that lands from `distance` away (FALLOFF).
static func falloff(gun: int, distance: float) -> float:
	if not FALLOFF.has(gun):
		return 1.0
	var f: Array = FALLOFF[gun]
	var full := float(f[0])
	if distance <= full:
		return 1.0
	var end := maxf(full + .01, reach(gun))
	return lerpf(1.0, float(f[1]), clampf((distance - full) / (end - full), 0.0, 1.0))


## A gun's kind in the store ("RIFLE", "PISTOL"...; the kit pistols too).
static func kind_of(gun: int) -> String:
	if _kinds.is_empty():
		for row: Array in ITEMS:
			if int(row[3]) >= 0:
				_kinds[int(row[3])] = String(row[6])
		_kinds[Weapons.REVOLVER] = "PISTOL"
		_kinds[Weapons.COUNTY45] = "PISTOL"
	return String(_kinds.get(gun, ""))


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
static func page_rows(game, st, p: Player, page: int) -> Array:
	var rows: Array = []
	for row: Array in menu(game, st, p):
		if (page == 1) == GEAR_GROUPS.has(String(row[6])):
			rows.append(row)
	return rows
