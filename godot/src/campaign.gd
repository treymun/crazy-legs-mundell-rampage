## Port of campaign.py: stable map ids plus the metadata the campaign, automap
## and save files share.
##
## The playable data lives in res://data/*.json, the source of every level;
## this class only carries the ordering and the strings the UI needs without
## loading a whole level.
class_name Campaign
extends RefCounted

const ORDER := ["hickston", "fair", "sawmill", "quarry", "mothership"]

const GATE_LABELS := {
	"hickston": "HICKSTON",
	"fair": "FAIR",
	"sawmill": "MILL",
	"quarry": "QUARRY",
	"mothership": "SHIP",
}

const LEVEL_INFO := {
	"hickston":
	{
		"title": "THE HICKSTON INCIDENT",
		"heading": ["BESSIE'S", "COMIN' HOME"],
		"districts":
		[
			"COUNTY ROAD",
			"STANKY'S BAR & GRILL",
			"RESTROOM",
			"SUPPLY ROOM",
			"FEED BARN",
			"HOG PEN",
			"PACKING SHED",
			"DISPATCH OFFICE",
			"TRAILER LOT",
			"DRY CREEK",
			"NORTH PASTURE",
			"COUNTY CROSSROADS",
			"COUNTY SERVICE ROAD",
			"LIVESTOCK LOTS",
			"STOCK REGISTRY"
		],
		"introduction": "BRASS KEY: STANKY'S BACK OFFICE",
		"ending": '"NEXT TIME, TAKE THE TRACTOR."',
		"score": "music",
		"ambience": "",
		"rescue": true,
		"labels":
		[
			["STANKY'S", 4, 18],
			["BARN", 25, 19],
			["TRAILERS", 37, 20],
			["HOG PEN", 26, 3],
			["CREEK", 36, 7],
			["ORCHARD", 4, 3],
			["GARAGE", 54, 17],
			["LOTS", 69, 26],
			["REGISTRY", 70, 9]
		],
	},
	"fair":
	{
		"title": "POSSUM COUNTY FAIR",
		"heading": ["LAST CALL", "ON THE MIDWAY"],
		"districts":
		[
			"TICKET SHACK",
			"THE MIDWAY",
			"CONCESSION ALLEY",
			"GAME COURT",
			"PRIZE PAVILION",
			"SERVICE EXIT",
			"FREIGHT AND RAFFLE LOT",
			"BACKSTAGE SIDESHOWS",
			"PA BOOTH"
		],
		"introduction": "SET CONCESSION POWER AND PATCH THE BACKSTAGE PA.",
		"ending": '"NO REFUNDS AFTER THE ABDUCTION."',
		"score": "fair_score",
		"ambience": "fair",
		"rescue": false,
		"labels":
		[
			["GATE", 18, 35],
			["MIDWAY", 18, 27],
			["FOOD", 5, 27],
			["GAMES", 33, 25],
			["PRIZES", 17, 11],
			["EXIT", 32, 8],
			["FREIGHT", 43, 29],
			["SIDESHOW", 53, 23],
			["PA", 56, 8]
		],
	},
	"sawmill":
	{
		"title": "BLACKWATER TIMBER",
		"heading": ["BLACKWATER", "TIMBER"],
		"districts":
		[
			"DELIVERY YARD",
			"FLOODED LOG POND",
			"WEST BANK",
			"EAST BANK",
			"THE CUTTING SHED",
			"LOADING APRON",
			"GREEN CHAIN SORT",
			"DRY KILNS",
			"RAIN STORAGE"
		],
		"introduction": "ISOLATE THE WEST FEED AND TRIP THE DRY-KILN BELT.",
		"ending": '"CLOCK OUT. LEAVE THE BOOTS OUTSIDE."',
		"score": "mill_score",
		"ambience": "mill",
		"rescue": false,
		"labels":
		[
			["YARD", 18, 33],
			["POND", 18, 23],
			["WEST", 7, 18],
			["EAST", 34, 19],
			["PUMP", 20, 8],
			["APRON", 10, 2],
			["SORT", 44, 20],
			["KILN", 60, 29],
			["DRY STACKS", 49, 40]
		],
	},
	"quarry":
	{
		"title": "STILLWATER CUT",
		"heading": ["STILLWATER CUT", "BOOTLEG WORKS"],
		"districts":
		[
			"COUNTY WEIGH STATION",
			"LIMESTONE CUT YARD",
			"CUTTING SHED",
			"CONDENSER YARD",
			"BOTTLING WORKS",
			"LOADING COURT",
			"LOWER CUT",
			"CHALK TERRACES",
			"COPPER RECOVERY"
		],
		"introduction": "STOP THE CUTTING FEED AND DIVERT THE COPPER CONDENSER.",
		"ending": '"WEIGHT INCLUDES CONTENTS AND DEBTS."',
		"score": "quarry_score",
		"ambience": "quarry",
		"rescue": false,
		"labels":
		[
			["SCALES", 21, 38],
			["CUT YARD", 25, 29],
			["SHED", 9, 17],
			["STILLS", 42, 19],
			["BOTTLING", 25, 13],
			["COURT", 17, 4],
			["LOWER CUT", 51, 26],
			["WASH", 70, 37],
			["COPPER", 67, 12]
		],
	},
	"mothership":
	{
		"title": "THE MOTHERSHIP",
		"heading": ["MAW'S", "MOTHERSHIP"],
		"districts":
		[
			"TRACTOR BEAM BAY",
			"RING DECK",
			"THE CORE",
			"THE BRIDGE",
			"TROPHY ROOM",
			"MAW'S PARLOR",
			"CREW BUNKS",
			"CREW MESS",
			"SPECIMEN HOLD",
			"PROBE LAB",
			"CORN DECK",
			"ENGINE ROOM",
			"SHINE TANKS",
			"CARGO HOLD",
			"SERVICE DUCTS"
		],
		"introduction": "SPIKE THE SHINE DRIVE AND DRAIN THE COW TUBES.",
		"ending": '"TELL YER MAW SHE CAN KEEP THE BUS."',
		"score": "mothership_score",
		"ambience": "mothership",
		"rescue": false,
		"labels":
		[
			["BAY", 60, 86],
			["CORE", 61, 50],
			["BRIDGE", 60, 25],
			["TROPHIES", 34, 24],
			["PARLOR", 12, 22],
			["MESS", 31, 50],
			["SPECIMENS", 8, 76],
			["CORN", 80, 22],
			["ENGINE", 86, 48],
			["CARGO", 92, 84]
		],
	},
}


static func info(level_id: String) -> Dictionary:
	return LEVEL_INFO.get(level_id, {})


static func title_of(level_id: String) -> String:
	return String(info(level_id).get("title", level_id.to_upper()))


static func heading_of(level_id: String) -> PackedStringArray:
	var out := PackedStringArray()
	for line in info(level_id).get("heading", []):
		out.append(String(line))
	return out


static func districts_of(level_id: String) -> PackedStringArray:
	var out := PackedStringArray()
	for line in info(level_id).get("districts", []):
		out.append(String(line))
	return out


## Label rows as [text, x, y]; the automap draws these on the map chrome.
static func map_labels(level_id: String) -> Array:
	return info(level_id).get("labels", [])


static func ending_of(level_id: String) -> String:
	return String(info(level_id).get("ending", ""))


static func score_of(level_id: String) -> String:
	return String(info(level_id).get("score", "music"))


static func ambience_of(level_id: String) -> String:
	return String(info(level_id).get("ambience", ""))


static func is_rescue(level_id: String) -> bool:
	return bool(info(level_id).get("rescue", false))


## Next map in campaign order, or "" after the last one.
static func next_level(level_id: String) -> String:
	var index := ORDER.find(level_id)
	if index < 0 or index + 1 >= ORDER.size():
		return ""
	return ORDER[index + 1]
