## The Moonshine Run's people and things: the roadblocks, who stands where,
## what lies about, the set pieces that fire and the map's labels
## (moonshine_plan.gd lays the ground first).
extends RefCounted

var b
var plan


func dress(p_plan) -> void:
	plan = p_plan
	b = plan.b
	labels()
	roadblocks()
	cast()
	pickups()
	set_pieces()


func labels() -> void:
	for l in [
		["GRANNY'S", 3, 76],
		["BARN", 20, 78],
		["CREEK", 39, 64],
		["BRIDGE", 37, 81],
		["CHURCH", 48, 59],
		["GRAVES", 59, 59],
		["BLACKTOP", 40, 57],
		["BUZZARD KNOB", 14, 4],
		["RADIO", 26, 18],
		["DEER CAMP", 64, 49],
		["SNAKE HOLLER", 98, 63],
		["CHECKPOINT", 80, 30],
		["SWITCHBACKS", 98, 20],
		["REVENUE CAMP", 64, 1],
		["STILL CAVE", 114, 1],
	]:
		b.label(String(l[0]), int(l[1]), int(l[2]))


## The two roadblocks the run rams: a cruiser across half the road with its
## lights going, the striped barricades across the rest. A man on foot gets
## by at the ditch; the car gets by through the barricades.
func roadblocks() -> void:
	# The low water bridge's east end.
	plan.parked("cruiser", 45.0, 75.95, true)
	for y in [77.5, 78.5]:
		b.town("sawhorse", 44.5, y, {"solid": .45})
	b.town("road_flare", 47.5, 79.6)
	b.glow(47.5, 79.5, 2.6, .3)
	b.town("road_flare", 42.5, 74.4)
	b.glow(42.5, 74.4, 2.4, .26)
	plan.parked("cruiser", 45.5, 69.0, false)
	# The county line checkpoint, across the ridge road.
	plan.parked("cruiser", 92.75, 31.7, false)
	for x in [94.5, 95.5]:
		b.town("sawhorse", x, 31.5, {"solid": .45})
	b.town("road_flare", 94.0, 34.6)
	b.glow(94.0, 34.6, 2.4, .26)
	b.board("moonshine_road_closed", 95.0, 31.06, .5, {"z": .55, "plane": 0.0})


func cast() -> void:
	for e in [
		# Granny's place: the agents turning it over.
		["revenooer", 13.0, 70.5, "farm-porch"],
		["revenooer", 19.5, 89.5, "farm-yard"],
		["gas_man", 6.0, 87.5, "farm-coop"],
		["still_buster", 6.5, 79.5, "farm-smokehouse"],
		["still_buster", 25.5, 82.5, "barn-axe"],
		["revenooer", 29.0, 70.0, "barn-tack"],
		# The creek and the low water bridge.
		["skeeter", 40.5, 66.5, "creek-skeeter-a"],
		["skeeter", 41.5, 88.5, "creek-skeeter-b"],
		["revenooer", 48.5, 77.5, "bridge-a"],
		["revenooer", 47.0, 74.5, "bridge-b"],
		# Little Bethel and its graveyard.
		["revenooer", 50.5, 66.5, "church-pews"],
		["gas_man", 46.5, 64.5, "church-yard"],
		["still_buster", 61.0, 65.5, "graves-a"],
		["revenooer", 61.5, 61.3, "graves-b"],
		["revenooer", 66.0, 73.0, "curve-a"],
		# The blacktop and the deer camp.
		["revenooer", 34.5, 57.5, "blacktop-a"],
		["coot", 75.5, 47.5, "deer-coot"],
		["billy", 68.5, 49.5, "deer-billy"],
		["clone", 66.5, 45.0, "deer-cabin"],
		["revenooer", 105.5, 42.5, "blacktop-east"],
		# Buzzard Knob and the radio.
		["revenooer", 24.5, 28.0, "knob-trail"],
		["revenooer", 21.5, 20.5, "knob-a"],
		["revenooer", 29.5, 17.5, "knob-b"],
		["gas_man", 18.5, 12.5, "knob-gas"],
		["still_buster", 31.5, 10.5, "knob-axe"],
		["skeeter", 10.5, 15.5, "knob-skeeter"],
		["coot", 40.5, 20.5, "knob-coot"],
		# Snake Holler.
		["billy", 88.5, 69.5, "holler-billy"],
		["coot", 83.5, 74.5, "holler-coot"],
		["revenooer", 108.5, 77.0, "holler-still"],
		["still_buster", 112.5, 70.5, "holler-buster"],
		["gas_man", 118.5, 73.5, "holler-gas"],
		["coot", 99.5, 87.5, "sinkhole-coot"],
		["skeeter", 95.5, 91.5, "holler-skeeter"],
		# The checkpoint and the switchbacks.
		["revenooer", 88.5, 31.5, "cp-booth"],
		["still_buster", 89.5, 34.5, "cp-buster"],
		["revenooer", 93.5, 22.5, "sb-a"],
		["gas_man", 103.5, 16.5, "sb-b"],
		["revenooer", 109.5, 16.5, "sb-c"],
		# The revenue camp.
		["revenooer", 64.5, 7.5, "camp-a"],
		["revenooer", 75.5, 10.5, "camp-b"],
		["still_buster", 69.5, 11.0, "camp-c"],
		["gas_man", 86.5, 8.5, "camp-d"],
		["revenooer", 96.5, 7.5, "camp-e"],
		["revenooer", 84.0, 4.6, "camp-trailer"],
		# The still cave: the Revenue Man and his best, waiting on the door.
		["revenue_man", 118.5, 7.5, "cave-revenue-man"],
		["revenooer", 115.5, 4.5, "cave-agent-a"],
		["revenooer", 115.5, 10.5, "cave-agent-b"],
		["still_buster", 123.5, 9.5, "cave-buster"],
	]:
		b.enemy(String(e[0]), float(e[1]), float(e[2]), String(e[3]))
	b.partners.append(["bridge-a", "bridge-b", 1])
	b.partners.append(["knob-a", "knob-b", -1])
	b.partners.append(["camp-a", "camp-b", 1])


func pickups() -> void:
	for p in [
		# Granny's: the porch, the house, the yard.
		["shotgun", 3.2, 71.6],
		["shells", 4.5, 70.5],
		["rinds", 9.5, 67.0],
		["moonshine", 10.0, 72.0],
		["bullets", 15.5, 86.5],
		["beer", 3.5, 90.5],
		# The smokehouse stash.
		["moonshine", 4.6, 82.6],
		["moonshine", 6.4, 82.6],
		["dynamite", 5.5, 83.6],
		["shells", 4.6, 83.8],
		# The barn and its tack room (the brass key).
		["shells", 18.5, 81.5],
		["rinds", 29.5, 84.0],
		["dynamite", 28.6, 69.6],
		["whiskey", 29.6, 69.6],
		["rocket_ammo", 28.6, 70.6],
		["keg_ammo", 29.6, 70.6],
		["shells", 30.0, 71.4],
		# The bridge and the creek.
		["shells", 46.0, 74.5],
		["rinds", 40.5, 72.0],
		["bullets", 37.0, 76.0],
		# The church, the pulpit's stash and the graves.
		["crossbow", 55.5, 64.0],
		["bullets", 50.0, 68.0],
		["whiskey", 51.6, 58.6],
		["rifle_ammo", 53.4, 58.6],
		["keg_ammo", 52.5, 59.6],
		["shells", 59.5, 72.3],
		["moonshine", 62.5, 64.5],
		# The blacktop and the deer camp.
		["rifle_ammo", 67.0, 45.5],
		["beer", 68.0, 45.5],
		["shells", 74.5, 49.0],
		["bullets", 20.0, 50.0],
		["rinds", 105.5, 50.0],
		# Buzzard Knob.
		["rifle", 21.5, 15.5],
		["rifle_ammo", 27.5, 16.5],
		["shells", 12.5, 24.5],
		["moonshine", 38.5, 12.5],
		["dynamite", 30.5, 22.5],
		# Snake Holler: the key, the busted still, the sinkhole's crack.
		["key_brass", 82.5, 70.3],
		["shells", 84.5, 70.5],
		["beer", 89.0, 74.0],
		["moonshine", 109.5, 75.5],
		["rifle_ammo", 115.5, 74.5],
		["arm_ammo", 104.6, 86.6],
		["rocket_ammo", 105.6, 87.6],
		["moonshine", 106.6, 86.6],
		["cowpie", 105.0, 88.4],
		# The checkpoint.
		["shells", 89.0, 32.5],
		["bullets", 88.5, 30.5],
		# The camp: the evidence table, the trailer.
		["pressure_gun", 70.0, 7.4],
		["cow_ammo", 68.5, 7.4],
		["shells", 74.5, 7.0],
		["rifle_ammo", 81.5, 3.5],
		["whiskey", 85.5, 3.0],
		["dynamite", 96.5, 11.5],
		["rinds", 106.5, 9.5],
		# The cave, for the fight.
		["shells", 114.0, 7.5],
		["dynamite", 114.5, 13.0],
		["rinds", 125.5, 12.0],
	]:
		b.pickup(String(p[0]), float(p[1]), float(p[2]))


func set_pieces() -> void:
	(
		b
		. triggers
		. append(
			{
				"id": "barn-look",
				"when": {"area": [17, 69, 30, 84]},
				"do": [{"message": "GRANNY'S LOAD. THE KEYS ARE IN THE STOCK CAR.", "for": 3.0}],
			}
		)
	)
	(
		b
		. triggers
		. append(
			{
				"id": "blacktop",
				"when": {"area": [64, 56, 67, 59]},
				"do":
				[
					{"message": "THE BLACKTOP. MIND THE CRUISERS, THEY DON'T BRAKE.", "for": 3.0},
					{"sound": "sheriff_siren", "at": [80.0, 57.5]},
				],
			}
		)
	)
	(
		b
		. triggers
		. append(
			{
				"id": "holler-down",
				"when": {"area": [84, 62, 86, 64]},
				"do": [{"message": "SNAKE HOLLER. SKEETER PRUITT LIVES DOWN HERE.", "for": 3.0}],
			}
		)
	)
	(
		b
		. triggers
		. append(
			{
				"id": "key-found",
				"when": {"key": "key_brass"},
				"do":
				[
					{
						"message":
						"GRANNY'S BARN KEY. SKEETER SOLD HER OUT. TACK ROOM'S HERS AGAIN.",
						"for": 3.5
					}
				],
			}
		)
	)
	(
		b
		. triggers
		. append(
			{
				"id": "camp-up",
				"when": {"area": [100, 10, 111, 14]},
				"do":
				[
					{"message": "THE REVENUE CAMP. THE STILL'S IN THE CAVE BEHIND IT.", "for": 3.0},
					{"alert": 14}
				],
			}
		)
	)
	b.exchanges.append(
		{
			"id": "bridge-radio",
			"x": 47.0,
			"y": 76.0,
			"stop_at": "radio",
			"lines": ["RADIO: CAR TWO, ANY SIGN OF THAT LOAD?", "AGENT: NOTHIN' BUT MOSQUITOES."]
		}
	)
	b.exchanges.append(
		{
			"id": "camp-talk",
			"x": 70.0,
			"y": 9.5,
			"stop_at": "",
			"lines": ["AGENT: CHIEF SAYS DON'T TASTE THE EVIDENCE.", "OTHER: CHIEF AIN'T HERE."]
		}
	)
	b.exchanges.append(
		{
			"id": "booth-radio",
			"x": 89.0,
			"y": 31.0,
			"stop_at": "radio",
			"lines": ["RADIO: CHECKPOINT, HOLD EVERY CAR.", "AGENT: EVEN GRANNY'S?"]
		}
	)
	b.distant_cues.append([24.5, 15.5, "distant_dog"])
	b.distant_cues.append([110.0, 73.0, "distant_crow"])
