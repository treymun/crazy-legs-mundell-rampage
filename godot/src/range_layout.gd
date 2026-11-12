## Where everything on the firing range is (Mundell's Proving Grounds,
## data/range.json): the stations, their targets, levers and pens. The level's
## plan (tools/levels/range_plan.gd) builds the place from these numbers and
## the range feature (features/firing_range.gd) runs it from the same ones, so
## a target is never drawn in one spot and shot at in another.
##
## The map is 100 by 78: eight lanes north of the covered firing line (y 52 to
## 55), the midway along it, and south of that the boss corral, the whuppin'
## yard, the armory (where the player starts) and the bullpen.
extends RefCounted

const ID := "range"
const SPAWN := [48.0, 70.0, -PI / 2.0]
## The firing line: the porch the lanes open off (x0, y0, x1, y1, cells).
const LINE := Rect2i(1, 52, 98, 4)
const MIDWAY := Rect2i(1, 56, 98, 3)

## Each station: id, the cells it holds (x0, y0, x1, y1 inclusive), where its
## card shows (the same), its title and what it teaches (one or two lines).
const STATIONS := {
	"cans":
	{
		"lane": [1, 18, 9, 51],
		"zone": [1, 44, 9, 55],
		"title": "TIN CAN ALLEY",
		"teach":
		[
			"STRAIGHT GUNS HIT WHERE YOU POINT, PLUS A LITTLE SPREAD.",
			"EACH ONE REACHES SO FAR AND NO FURTHER."
		],
	},
	"pellets":
	{
		"lane": [11, 34, 19, 51],
		"zone": [11, 44, 19, 55],
		"title": "PELLET PATCH",
		"teach":
		[
			"A SAWED-OFF THROWS 10 PELLETS OF 12. CLOSE, THEY ALL LAND.",
			"RIGHT CLICK: BOTH BARRELS. PAST 11 YDS NOTHING ARRIVES."
		],
	},
	"rifle":
	{
		"lane": [21, 1, 29, 51],
		"zone": [21, 44, 29, 55],
		"title": "RIFLE RANGE",
		"teach":
		[
			"THE RIFLE REACHES 27 YDS, THE .38 23, THE RIVETER 16.",
			"HOLD FIRE AND THE BARREL HEATS: IT CLIMBS AND STRAYS."
		],
	},
	"gallery":
	{
		"lane": [31, 40, 41, 51],
		"zone": [31, 46, 41, 55],
		"title": "DUCK GALLERY",
		"teach":
		[
			"USE THE LEVER: 30 SECONDS, ANY GUN. ROOSTERS 1, DUCKS 2.",
			"LEAD THE MOVERS. A MISS COSTS YOU NOTHING BUT PRIDE."
		],
	},
	"bowling":
	{
		"lane": [43, 33, 49, 51],
		"zone": [43, 44, 49, 55],
		"title": "BOWL-O-RAMA",
		"teach":
		[
			"THE BOWLING BALL ROLLS ALONG THE FLOOR, IT DOES NOT FLY.",
			"TEN PINS IN ONE ROLL IS A STRIKE. IT BOWLS FOLKS OVER TOO."
		],
	},
	"soak":
	{
		"lane": [51, 32, 59, 51],
		"zone": [51, 44, 59, 55],
		"title": "SOAK TANK",
		"teach":
		[
			"THE TEAT GUN HURTS A LITTLE AND SOAKS A LOT.",
			"SOAKED HANDS SLOW DOWN AND GO OVER IN THE MILK."
		],
	},
	"special":
	{
		"lane": [61, 22, 69, 51],
		"zone": [61, 44, 69, 55],
		"title": "SPECIAL ORDERS",
		"teach":
		[
			"COPPERHEAD SHOTS BREAK A WIND-UP. WAKE THE GREY AND TRY.",
			"RIP SAW BLADES BOUNCE OFF WALLS. THE ARM GUN BURSTS."
		],
	},
	"pit":
	{
		"lane": [71, 10, 98, 51],
		"zone": [71, 46, 98, 55],
		"title": "POWDER PIT",
		"teach":
		[
			"HOLD FIRE TO LIGHT A STICK, LET GO TO THROW. KEGS AND COWS",
			"BLOW UP TOO. DRUMS GO UP IN CHAINS. SEND FODDER, THEN BLAST."
		],
	},
	"yard":
	{
		"lane": [26, 59, 33, 76],
		"zone": [26, 57, 33, 76],
		"title": "WHUPPIN' YARD",
		"teach":
		[
			"SWING AT THE DUMMIES. HIT WHILE SPRINTING ON MOONSHINE",
			"FOR A SQUARE HIT. RIP SAW RIGHT CLICK GRINDS UP CLOSE."
		],
	},
	"bullpen":
	{
		"lane": [67, 60, 98, 76],
		"zone": [62, 57, 98, 76],
		"title": "THE BULLPEN",
		"teach":
		[
			"PULL A LEVER, MEET THE LOCALS. THEY DUCK BEHIND COVER,",
			"RUN FOR HELP WHEN HURT AND BRAWL IF THEY SHOOT EACH OTHER."
		],
	},
	"corral":
	{
		"lane": [1, 60, 24, 76],
		"zone": [1, 57, 24, 76],
		"title": "BOSS CORRAL",
		"teach":
		[
			"ONE BOSS AT A TIME. WATCH THE TELL ON THE HEALTH BAR.",
			"AT HALF HEALTH THEY GO FIGHTIN' MAD AND HIT HARDER."
		],
	},
	"armory":
	{
		"lane": [35, 60, 60, 75],
		"zone": [35, 60, 60, 75],
		"title": "THE ARMORY",
		"teach":
		[
			"EVERY GUN IS YOURS AND THE AMMO REFILLS ITSELF.",
			"WALK UP TO A GUN ON THE WALL AND PRESS USE TO HEAR ABOUT IT."
		],
	},
}

## Shootable targets the feature draws and keeps score on: [id, station,
## kind, x, y]. Kinds (TARGET_KINDS): picture, height, hit radius across, hit
## centre and half height up the picture.
const TARGETS := [
	["cans-7", "cans", "board", 5.5, 44.5],
	["cans-18", "cans", "board", 5.5, 33.5],
	["pellets-3", "pellets", "board", 13.5, 48.0],
	["pellets-6", "pellets", "board", 17.5, 45.0],
	["pellets-9", "pellets", "board", 13.5, 42.0],
	["pellets-12", "pellets", "board", 17.5, 39.0],
	["rifle-10", "rifle", "gong", 23.5, 41.0],
	["rifle-20", "rifle", "gong", 27.5, 31.0],
	["rifle-25", "rifle", "gong", 23.5, 26.0],
	["rifle-35", "rifle", "gong", 25.5, 16.0],
	["special-6", "special", "gong", 63.5, 45.0],
	["special-10", "special", "gong", 67.5, 41.0],
	["special-20", "special", "board", 65.5, 31.0],
	["pit-cow-a", "pit", "cow", 79.5, 36.5],
	["pit-cow-b", "pit", "cow", 92.5, 34.5],
	["yard-crowbar", "yard", "dummy", 28.5, 63.5],
	["yard-sling", "yard", "dummy", 31.5, 63.5],
	["yard-saw", "yard", "dummy", 28.5, 68.5],
	["yard-any", "yard", "dummy", 31.5, 68.5],
]
const TARGET_KINDS := {
	"board": ["town_range_target", 1.34, .36, .83, .36],
	"gong": ["town_range_gong", 1.53, .33, .9, .33],
	"dummy": ["town_range_dummy", 1.72, .3, 1.05, .62],
	"cow": ["town_range_cow_target", 1.3, .62, .8, .36],
}
## Tin cans on posts in the alley: [id, x, y]; the scenery a shot knocks off.
const CANS := [
	["can-5", 3.5, 46.5],
	["can-10", 7.5, 41.5],
	["can-15", 3.5, 36.5],
	["can-20", 7.5, 31.5],
	["can-25", 5.5, 26.5],
]
const CAN_TOP := .85

## The gallery: targets slide across between these x, on two rows [y, z of
## the bottom, picture, height, points, speed].
const GALLERY_X := [32.2, 40.8]
const GALLERY_ROWS := [
	[45.5, 1.0, "county_gallery_target", .55, 1, 1.5],
	[43.0, 1.55, "town_range_duck", .6, 2, 2.4],
]
const GALLERY_TIME := 30.0

## The ten pins, head pin first, standing on the deck.
const PIN_HEAD := Vector2(46.5, 37.6)
const PIN_GAP := .34

## Release levers and buttons: [station id (the level's station), x, y, label,
## what it does]. Its station's id is "range-" + the first field.
const LEVERS := [
	["cans", 2.5, 50.6, "STAND THE CANS UP", "cans"],
	["pins", 48.5, 50.6, "RACK THE PINS", "pins"],
	["gallery", 32.5, 50.5, "START A GALLERY ROUND", "gallery"],
	["soak", 52.5, 50.6, "TURN OUT THREE HANDS", "soak"],
	["alien_one", 62.5, 50.6, "WAKE THE GREY ALIEN", "alien_one"],
	["fodder", 72.5, 50.6, "SEND IN THE FODDER", "fodder"],
	["reset-pit", 97.5, 50.6, "RESET THE PIT", "reset"],
]
## The bullpen's lever bank along its north fence, and the corral's.
const PEN_KINDS := [
	"billy",
	"coot",
	"skeeter",
	"clone",
	"alien",
	"saucer",
	"barker",
	"crawler",
	"bottle_tosser",
	"millhand",
	"lantern",
	"boilerback",
	"chalk_spitter",
	"yard_deputy",
	"chain_hand",
	"valve_rat",
	"squad",
	"clear",
]
const PEN_LEVER_X := 67.5
const PEN_LEVER_STEP := 1.75
const PEN_LEVER_Y := 58.5
const BOSS_KINDS := ["boss", "jerry", "rudy", "foreman", "baron", "clear"]
const BOSS_LEVER_X := [3.5, 6.5, 9.5, 15.5, 18.5, 21.5]
const BOSS_LEVER_Y := 58.5
const NAMES := {
	"billy": "BILLY",
	"coot": "COOT",
	"skeeter": "SKEETER",
	"clone": "CLONE",
	"alien": "GREY ALIEN",
	"saucer": "SAUCER",
	"barker": "BARKER",
	"crawler": "CRAWLER",
	"bottle_tosser": "BOTTLE TOSSER",
	"millhand": "MILLHAND",
	"lantern": "LANTERN",
	"boilerback": "BOILERBACK",
	"chalk_spitter": "CHALK SPITTER",
	"yard_deputy": "YARD DEPUTY",
	"chain_hand": "CHAIN HAND",
	"valve_rat": "VALVE RAT",
	"boss": "ALIEN SHERIFF",
	"jerry": "JERRY JONES",
	"rudy": "RUDY RACKET",
	"foreman": "SPLINTER FOREMAN",
	"baron": "COPPER BARON",
	"squad": "A WHOLE SQUAD",
	"clear": "CLEAR THE PEN",
}
## Where each pen's critters come in.
const PEN_DOORS := [
	Vector2(95.5, 64.5), Vector2(95.5, 71.5), Vector2(91.5, 74.5), Vector2(92.5, 61.5)
]
const BOSS_DOOR := Vector2(12.5, 71.5)
const SOAK_DOORS := [Vector2(53.5, 35.5), Vector2(55.5, 34.5), Vector2(57.5, 36.5)]
const ALIEN_DOOR := Vector2(65.5, 27.5)
const FODDER_DOORS := [
	Vector2(78.5, 18.5),
	Vector2(84.5, 15.5),
	Vector2(90.5, 18.5),
	Vector2(80.5, 23.5),
	Vector2(88.5, 22.5)
]
const FODDER_KINDS := ["crawler", "billy", "crawler", "clone", "crawler"]
## Fuel drums in the pit (back after a reset).
const DRUMS := [
	Vector2(82.5, 30.5),
	Vector2(83.4, 31.2),
	Vector2(84.3, 30.4),
	Vector2(90.5, 24.5),
	Vector2(91.4, 25.3),
	Vector2(76.5, 26.5),
]
## The corral's steam ports (the Copper Baron's pipes) and Rudy's decoys.
const PRESSURE_PORTS := [[6.5, 66.5], [18.5, 66.5], [6.5, 73.5], [18.5, 73.5]]
const BOSS_DECOYS := [[4.5, 75.0], [20.5, 75.0]]


## The guns on the armory walls, in weapons.cfg order: [x, y, facing (the
## plane the picture lies in), where to stand to take it].
static func rack(i: int) -> Array:
	if i < 7:
		var y := 61.5 + i * 2.0
		return [35.03, y, -PI / 2.0, Vector2(35.75, y)]
	if i < 14:
		var y2 := 61.5 + (i - 7) * 2.0
		return [60.97, y2, PI / 2.0, Vector2(60.25, y2)]
	var x := 42.5 if i == 14 else 53.5
	return [x, 75.97, PI, Vector2(x, 75.25)]


## The pins of a fresh rack: rows of 1, 2, 3 and 4 going away (north).
static func pins() -> Array:
	var out: Array = []
	for row in 4:
		for k in row + 1:
			out.append(PIN_HEAD + Vector2((k - row * .5) * PIN_GAP, -row * PIN_GAP * .87))
	return out


static func pen_lever(i: int) -> Vector2:
	return Vector2(PEN_LEVER_X + i * PEN_LEVER_STEP, PEN_LEVER_Y)


static func station_at(x: float, y: float) -> String:
	for id: String in STATIONS:
		var r: Array = STATIONS[id]["zone"]
		if (
			x >= float(r[0])
			and x < float(r[2]) + 1.0
			and y >= float(r[1])
			and y < float(r[3]) + 1.0
		):
			return id
	return ""
