## The two example player maps shipped in godot/data/user_maps/, made with the
## MAP SHED's own calls (MapEditor: pick a tab and an item, paint a box or a
## cell, place a thing, turn it) exactly as a player's clicks make them, then
## saved with the shed's own writer (UserMap.to_text):
##
##   godot --headless --path godot --script res://tools/user_map_examples.gd
##
## PUCKETT'S BACK FORTY: a farm at dusk (alone, deathmatch, County Run).
## THE SALE BARN: a livestock auction on a fair night, built for the 5v5 rounds
## (both sites, both starts, hostages in the office) and alone too.
extends SceneTree

var ed: MapEditor


func _init() -> void:
	var out := ProjectSettings.globalize_path(UserMaps.EXAMPLES)
	DirAccess.make_dir_recursive_absolute(out)
	for made: Array in [["pucketts_back_forty", _back_forty()], ["the_sale_barn", _sale_barn()]]:
		var map: Dictionary = made[1]
		var checked := UserMap.parse_text(UserMap.to_text(map))
		if checked.has("error"):
			push_error("%s: %s" % [made[0], checked["error"]])
			quit(1)
			return
		var file := FileAccess.open(out.path_join(str(made[0]) + ".json"), FileAccess.WRITE)
		file.store_string(UserMap.to_text(map))
		file.close()
		print(
			(
				"%s  %dx%d  %d things  hosts %s"
				% [
					made[0],
					UserMap.width(map),
					UserMap.height(map),
					(map["things"] as Array).size(),
					", ".join(UserMap.hosts(map))
				]
			)
		)
		for w: Array in UserMap.warnings(map):
			print("  warning %d,%d %s" % w)
		var modes := UserMap.modes(map)
		for mode: String in modes:
			if str(modes[mode]) != "":
				print("  %s: %s" % [mode, modes[mode]])
	quit()


# ------------------------------------------------------------------ the calls


## Pick the item called `label` on the tab called `tab` (as a click would).
func pick(tab: String, label: String) -> void:
	for t in MapEditor.TABS.size():
		if str(MapEditor.TABS[t][0]) == tab:
			ed.tab = t
			var list := MapEditor.items(t)
			for i in list.size():
				if str(list[i]["label"]) == label:
					ed.pick_item(i)
					return
	push_error("no %s on %s" % [label, tab])


## A box from (x0, y0) to (x1, y1) of the picked item (SHIFT-drag).
func box(x0: int, y0: int, x1: int, y1: int) -> void:
	ed.begin()
	ed.box(Vector2i(x0, y0), Vector2i(x1, y1))
	ed.end_stroke()


## One cell or thing (a click), facing `facing`.
func put(x: int, y: int, facing := 0) -> void:
	ed.facing = facing
	ed.begin()
	if not ed.apply(Vector2i(x, y)):
		push_error("could not put %s at %d,%d: %s" % [ed.item()["label"], x, y, ed.note])
	ed.end_stroke()


func many(tab: String, label: String, spots: Array) -> void:
	pick(tab, label)
	for s: Array in spots:
		put(int(s[0]), int(s[1]), int(s[2]) if s.size() > 2 else 0)


func building(wall: String, floor_name: String, x0: int, y0: int, x1: int, y1: int) -> void:
	pick("INSIDE", floor_name)
	pick("WALLS", wall)
	box(x0, y0, x1, y1)


# ------------------------------------------------------------------ the maps


func _back_forty() -> Dictionary:
	ed = MapEditor.new(UserMap.blank(40, 30, "PUCKETT'S BACK FORTY"))
	ed.set_text("author", "THE MAP SHED")
	ed.set_text("note", "THE PUCKETTS OWE THE WRONG PEOPLE. THROW THEIR BARN LEVER AND GIT.")
	# The ground: pasture, the yard's dirt, the drive and the county road.
	pick("GROUND", "PLAIN DIRT")
	box(14, 3, 23, 13)
	box(2, 12, 15, 14)
	pick("GROUND", "GRAVEL LOT")
	box(18, 14, 19, 25)
	box(16, 22, 21, 24)
	pick("GROUND", "COUNTY ROAD")
	box(1, 26, 38, 27)
	pick("GROUND", "BLACKTOP")
	box(1, 25, 38, 25)
	box(1, 28, 38, 28)
	# The creek, its mud banks, a ford where the drive crosses.
	pick("GROUND", "MUD")
	for k in 9:
		box(22 + k * 2, 15 + k / 2, 24 + k * 2, 18 + k / 2)
	pick("GROUND", "CREEK")
	for k in 9:
		box(22 + k * 2, 16 + k / 2, 24 + k * 2, 17 + k / 2)
	# The farmhouse: brick, windows, a kitchen, a porch out front.
	building("BRICK", "PLANK FLOOR", 3, 3, 12, 10)
	pick("INSIDE", "KITCHEN TILE")
	box(4, 4, 7, 6)
	pick("WALLS", "BRICK")
	box(8, 4, 8, 6)
	pick("WALLS", "BRICK WINDOW")
	for s: Array in [[5, 3], [10, 3], [3, 7], [5, 10], [10, 10]]:
		put(s[0], s[1])
	pick("WALLS", "SWING DOOR")
	put(12, 7)
	put(8, 5)
	pick("STEPS", "PORCH STEP")
	box(13, 5, 14, 9)
	# The red barn, its hayloft deck, two doors.
	building("BARN BOARDS", "PLANK FLOOR", 25, 2, 36, 12)
	pick("WALLS", "BARN WINDOW")
	for s: Array in [[28, 2], [33, 2], [36, 5], [36, 9]]:
		put(s[0], s[1])
	pick("WALLS", "SWING DOOR")
	put(30, 12)
	put(25, 7)
	pick("STEPS", "DECK")
	box(32, 3, 35, 6)
	pick("STEPS", "PORCH STEP")
	box(31, 3, 31, 6)
	# The pasture fence and the hog lot.
	pick("WALLS", "STOCK FENCE")
	box(15, 1, 15, 2)
	box(24, 1, 24, 2)
	box(1, 16, 9, 16)
	box(9, 17, 9, 21)
	# A stand of trees and the still in its clearing.
	many("PROPS", "OAK TREE", [[2, 18], [5, 22], [11, 18], [13, 23], [3, 24], [8, 24], [12, 20]])
	many("PROPS", "PINE TREE", [[2, 21], [7, 19], [14, 17], [10, 23], [16, 19]])
	many("PROPS", "DEAD TREE", [[37, 23]])
	many("PROPS", "MOONSHINE STILL", [[5, 19]])
	many("PROPS", "PROPANE TANK", [[4, 18]])
	many("PROPS", "BURN BARREL", [[7, 21], [20, 9], [22, 27]])
	many("PROPS", "LANTERN POST", [[15, 11], [24, 13], [17, 21]])
	# The yard: the work and the junk.
	many("PROPS", "TRACTOR", [[21, 5]])
	many("PROPS", "HAY WAGON", [[22, 11]])
	many("PROPS", "OUTHOUSE", [[2, 12]])
	many("PROPS", "CHICKEN COOP", [[17, 4]])
	many("PROPS", "DOGHOUSE", [[16, 12]])
	many("PROPS", "PICNIC TABLE", [[9, 13]])
	many("PROPS", "BARBECUE GRILL", [[11, 13]])
	many("PROPS", "PORCH COUCH", [[14, 6]])
	many("PROPS", "WRECKED PICKUP", [[20, 22]])
	many("PROPS", "LOG PILE", [[23, 7]])
	many("PROPS", "SCARECROW", [[19, 2]])
	many("PROPS", "PICKUP TRUCK", [[16, 23]])
	many("PROPS", "POWER POLE", [[4, 25], [12, 25], [20, 25], [28, 25], [36, 25]])
	many("PROPS", "MAILBOX", [[17, 25]])
	many("PROPS", "ROAD SIGN", [[38, 25]])
	many("PROPS", "TIRE PILE", [[34, 14]])
	many("PROPS", "HANGING LAMP", [[6, 8], [10, 5], [28, 5], [33, 9]])
	many("PROPS", "TOMBSTONE", [[37, 20], [38, 21]])
	many("PROPS", "LAWN FLAMINGO", [[13, 11]])
	# The hands: Puckett's boys about the yard, the old men at the still, Big
	# Billy minding the lever up in the loft.
	many(
		"HANDS",
		"BILLY",
		[[16, 8, 4], [22, 3, 2], [27, 14, 4], [18, 17, 6], [33, 15, 4], [30, 8, 2]]
	)
	many("HANDS", "OLD COOT", [[6, 5, 0], [10, 8, 4], [21, 13, 6]])
	many("HANDS", "DRUNK COOT", [[6, 20, 0], [8, 18, 4]])
	many("HANDS", "BIG BILLY", [[33, 8, 6]])
	many("HANDS", "YARD DEPUTY", [[30, 26, 4], [35, 23, 4]])
	many("HANDS", "SKEETER", [[12, 21, 0]])
	many("HANDS", "COW", [[19, 7, 0], [22, 8, 2]])
	# Something to fight with on the way.
	many("LOOT", "SHOTGUN", [[11, 4]])
	many("LOOT", "BUCKSHOT", [[4, 9], [26, 3], [17, 19]])
	many("LOOT", ".38 ROUNDS", [[9, 12], [20, 18]])
	many("LOOT", "PORK RINDS", [[7, 4], [35, 11]])
	many("LOOT", "BEER", [[12, 14], [26, 11]])
	many("LOOT", "MOONSHINE", [[6, 18]])
	many("LOOT", "DYNAMITE", [[32, 11]])
	many("LOOT", "HUNTING RIFLE", [[34, 3]])
	# Your start on the road west, the lever in the loft, the truck east.
	many("MARKS", "YOUR START", [[2, 27, 0]])
	many("MARKS", "THE BIG LEVER", [[35, 4]])
	many("MARKS", "THE GETAWAY TRUCK", [[37, 27]])
	return ed.map


func _sale_barn() -> Dictionary:
	ed = MapEditor.new(UserMap.blank(48, 32, "THE SALE BARN"))
	ed.set_text("author", "THE MAP SHED")
	ed.set_text("note", "SATURDAY NIGHT AT THE COUNTY SALE. SOMEBODY BID WITH A SHOTGUN.")
	ed.next_mood(1)
	# Gravel everywhere a truck parks, blacktop out front.
	pick("GROUND", "GRAVEL LOT")
	box(1, 3, 46, 30)
	pick("GROUND", "BLACKTOP")
	box(1, 1, 46, 2)
	pick("GROUND", "PLAIN DIRT")
	box(3, 22, 14, 30)
	# The sale barn: tin, a ring of stock fence, bleacher decks.
	building("SHEET TIN", "SHOP FLOOR", 16, 8, 31, 23)
	pick("WALLS", "STOCK FENCE")
	box(21, 13, 26, 13)
	box(21, 18, 26, 18)
	box(21, 14, 21, 15)
	box(26, 16, 26, 17)
	pick("STEPS", "DECK")
	box(18, 9, 29, 9)
	pick("STEPS", "PORCH STEP")
	box(18, 10, 29, 10)
	pick("WALLS", "SWING DOOR")
	put(16, 15)
	put(31, 16)
	put(23, 8)
	put(24, 23)
	# The office: brick with windows, the hostages kept in it.
	building("BRICK", "KITCHEN TILE", 3, 4, 11, 10)
	pick("WALLS", "BRICK WINDOW")
	for s: Array in [[5, 4], [9, 4], [3, 7], [11, 6]]:
		put(s[0], s[1])
	pick("WALLS", "SWING DOOR")
	put(7, 10)
	put(11, 8)
	# The loading docks east, steps up to them.
	pick("STEPS", "LOADING DOCK")
	box(38, 4, 45, 9)
	pick("STEPS", "DECK")
	box(37, 4, 37, 9)
	pick("STEPS", "PORCH STEP")
	box(36, 4, 36, 9)
	# Trailers parked by the docks, the pens south-west.
	pick("WALLS", "TRAILER SIDING")
	box(34, 12, 35, 18)
	box(39, 12, 40, 17)
	box(43, 24, 44, 29)
	pick("WALLS", "STOCK FENCE")
	box(3, 22, 14, 22)
	box(14, 23, 14, 27)
	box(8, 23, 8, 26)
	pick("WALLS", "TIRE STACK")
	box(36, 22, 37, 23)
	box(29, 27, 31, 27)
	pick("WALLS", "JUNK PILE")
	box(18, 27, 20, 28)
	# Dressing.
	many("PROPS", "PICKUP TRUCK", [[13, 2], [27, 2], [33, 25]])
	many("PROPS", "HAY WAGON", [[14, 14], [33, 20]])
	many("PROPS", "TRACTOR", [[44, 13]])
	many("PROPS", "PALLET STACK", [[41, 10], [37, 11], [24, 25]])
	many("PROPS", "BURN BARREL", [[13, 18], [35, 28], [5, 13]])
	many("PROPS", "LANTERN POST", [[15, 6], [32, 7], [12, 21], [38, 20], [26, 29]])
	many("PROPS", "HANGING LAMP", [[19, 12], [28, 12], [19, 20], [28, 20], [6, 6], [9, 8]])
	many("PROPS", "OIL DRUM", [[42, 11], [30, 4]])
	many("PROPS", "TNT CRATE", [[44, 5]])
	many("PROPS", "GAS PUMP", [[2, 3]])
	many("PROPS", "GAS CANS", [[3, 2]])
	many("PROPS", "POWER POLE", [[8, 1], [24, 1], [40, 1]])
	many("PROPS", "OAK TREE", [[45, 31 - 2], [1, 30]])
	many("PROPS", "COOLER", [[20, 25]])
	many("PROPS", "WHEELBARROW", [[10, 24]])
	many("HANDS", "COW", [[5, 25, 0], [11, 27, 2], [6, 28, 4]])
	# The 5v5: attackers off the road west, defenders by the docks; A in the
	# ring, B up on the dock; the hostages in the office.
	many("MARKS", "ATTACK START", [[2, 15, 0]])
	many("MARKS", "DEFEND START", [[42, 26, 4]])
	many("MARKS", "BOMB SITE A", [[24, 15]])
	many("MARKS", "BOMB SITE B", [[41, 7]])
	many("MARKS", "HOSTAGE", [[5, 6], [9, 9]])
	# Alone: in from the road, the lever on the dock, the truck by the pens.
	many("MARKS", "YOUR START", [[2, 2, 0]])
	many("MARKS", "THE BIG LEVER", [[44, 8]])
	many("MARKS", "THE GETAWAY TRUCK", [[4, 30]])
	many("HANDS", "BILLY", [[20, 15, 0], [27, 19, 4], [33, 10, 2], [38, 25, 4], [17, 3, 2]])
	many("HANDS", "YARD DEPUTY", [[42, 6, 4], [24, 11, 2], [12, 16, 4]])
	many("HANDS", "RIOT DEPUTY", [[38, 7, 4]])
	many("HANDS", "OLD COOT", [[7, 7, 0], [29, 25, 6]])
	many("HANDS", "BIG BILLY", [[24, 16, 4]])
	many("LOOT", "SHOTGUN", [[10, 13]])
	many("LOOT", "BUCKSHOT", [[17, 21], [32, 13], [9, 29]])
	many("LOOT", ".38 ROUNDS", [[15, 3], [30, 22]])
	many("LOOT", "HUNTING RIFLE", [[29, 9]])
	many("LOOT", "RIFLE CARTRIDGES", [[45, 9]])
	many("LOOT", "WHISKEY", [[22, 21], [37, 26]])
	many("LOOT", "PORK RINDS", [[4, 8]])
	return ed.map
