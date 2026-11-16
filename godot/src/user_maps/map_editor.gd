## The MAP SHED's working copy of a map and everything done to it: the
## palette's tabs, painting cells (a box, or a whole building with walls round
## a floor, at once), placing and taking away things, facing, undo and redo,
## the view's place and zoom. MapEditorScreen draws it and turns keys, the
## mouse and taps into these calls; tools/user_map_examples.gd makes the
## shipped examples with the same calls.
class_name MapEditor
extends RefCounted

## The palette's tabs: [title, kind, group].
const TABS := [
	["GROUND", "cell", "ground"],
	["INSIDE", "cell", "inside"],
	["STEPS", "cell", "rise"],
	["WALLS", "cell", "wall"],
	["HANDS", "thing", "hand"],
	["LOOT", "thing", "loot"],
	["PROPS", "thing", "prop"],
	["MARKS", "thing", "mark"],
]
const ZOOMS := [4, 6, 8, 12]
const UNDO_MOST := 80
## The sizes NEW MAP and SIZE step through.
const SIZES := [[24, 18], [32, 24], [40, 30], [48, 36], [64, 48]]
## What a wall, a door or a thing torn out leaves behind.
const BARE := ","

var map: Dictionary
## The file it came from and goes back to ("" until saved).
var stem := ""
## "mine" or "example" (an example is saved as a copy of your own).
var source := "mine"
var cursor := Vector2i(1, 1)
var tab := 0
## The item picked on each tab.
var picks: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0]
var facing := 0
var zoom := 1
## The cell at the view's top left.
var view := Vector2i.ZERO
var changed := false
## A line for the help bar ("SAVED.", what went wrong).
var note := ""
var _undo: Array = []
var _redo: Array = []
## Bumped on every change (the screen redraws its picture of the map).
var version := 0
var _begun := -1


func _init(start: Dictionary = {}) -> void:
	map = start.duplicate(true) if not start.is_empty() else UserMap.blank(32, 24)
	cursor = Vector2i(UserMap.width(map) / 2, UserMap.height(map) / 2)


## The items of a tab: palette entries.
static func items(t: int) -> Array:
	var spec: Array = TABS[t]
	var out: Array = []
	var source_list: Array = UserMap.cells() if spec[1] == "cell" else UserMap.things()
	for v: Variant in source_list:
		var entry: Dictionary = v
		var group := str(entry.get("group", entry.get("kind", "")))
		if group == str(spec[2]) or (spec[2] == "wall" and group == "door"):
			out.append(entry)
	return out


func item() -> Dictionary:
	var list := items(tab)
	var picked: Dictionary = list[clampi(picks[tab], 0, list.size() - 1)]
	return picked


func is_cell_tab() -> bool:
	return str(TABS[tab][1]) == "cell"


func next_tab(step: int) -> void:
	tab = posmod(tab + step, TABS.size())


func next_item(step: int) -> void:
	picks[tab] = posmod(picks[tab] + step, items(tab).size())


func pick_item(index: int) -> void:
	picks[tab] = clampi(index, 0, items(tab).size() - 1)


func turn(step := 1) -> void:
	facing = posmod(facing + step, 8)


func cells_px() -> int:
	var z: int = ZOOMS[zoom]
	return z


func zoom_by(step: int) -> void:
	zoom = clampi(zoom + step, 0, ZOOMS.size() - 1)


## Keep the cursor inside the view `size` (in pixels), moving the view.
func follow(size: Vector2i) -> void:
	var z := cells_px()
	var across := maxi(1, size.x / z)
	var down := maxi(1, size.y / z)
	view.x = clampi(view.x, cursor.x - across + 2, cursor.x - 1)
	view.y = clampi(view.y, cursor.y - down + 2, cursor.y - 1)
	clamp_view(size)


func clamp_view(size: Vector2i) -> void:
	var z := cells_px()
	view.x = clampi(view.x, 0, maxi(0, UserMap.width(map) - size.x / z))
	view.y = clampi(view.y, 0, maxi(0, UserMap.height(map) - size.y / z))


func move_cursor(step: Vector2i) -> void:
	cursor.x = clampi(cursor.x + step.x, 0, UserMap.width(map) - 1)
	cursor.y = clampi(cursor.y + step.y, 0, UserMap.height(map) - 1)


func inside(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < UserMap.width(map) and c.y < UserMap.height(map)


# ------------------------------------------------------------------ undo


## Call before a change (a mouse stroke calls it once at its start).
func begin() -> void:
	_undo.append(map.duplicate(true))
	if _undo.size() > UNDO_MOST:
		_undo.pop_front()
	_redo.clear()
	_begun = version


## A stroke or key that changed nothing leaves no undo step.
func end_stroke() -> void:
	if version == _begun and not _undo.is_empty():
		_undo.pop_back()


func undo_drop() -> void:
	end_stroke()


func undo() -> bool:
	if _undo.is_empty():
		note = "NOTHING TO UNDO."
		return false
	_redo.append(map.duplicate(true))
	map = _undo.pop_back()
	_touched()
	note = "UNDONE."
	return true


func redo() -> bool:
	if _redo.is_empty():
		note = "NOTHING TO REDO."
		return false
	_undo.append(map.duplicate(true))
	map = _redo.pop_back()
	_touched()
	note = "REDONE."
	return true


func _touched() -> void:
	changed = true
	version += 1
	cursor.x = clampi(cursor.x, 0, UserMap.width(map) - 1)
	cursor.y = clampi(cursor.y, 0, UserMap.height(map) - 1)


# ------------------------------------------------------------------ editing


func _set_cell(c: Vector2i, key: String) -> bool:
	if not inside(c) or UserMap.at(map, c.x, c.y) == key:
		return false
	var rows: Array = map["rows"]
	var row: String = rows[c.y]
	rows[c.y] = row.left(c.x) + key + row.substr(c.x + 1)
	if not UserMap.is_open(key):
		_take_thing(c)
	else:
		# A lamp hangs from a roof: none left under the sky.
		var held := thing_at(c)
		if not held.is_empty():
			var spec := UserMap.thing(str(held[0]), str(held[1]))
			var inside_only: bool = spec.get("inside", false)
			if inside_only and str(UserMap.cell(key).get("group", "")) != "inside":
				_take_thing(c)
	return true


## The thing on a cell ([] for none).
func thing_at(c: Vector2i) -> Array:
	for v: Variant in map["things"]:
		var t: Array = v
		if _i(t[2]) == c.x and _i(t[3]) == c.y:
			return t
	return []


func _take_thing(c: Vector2i) -> bool:
	var list: Array = map["things"]
	for i in list.size():
		var t: Array = list[i]
		if _i(t[2]) == c.x and _i(t[3]) == c.y:
			list.remove_at(i)
			return true
	return false


## Paint (or place) the picked item at `c`. True when something changed.
func apply(c: Vector2i) -> bool:
	if not inside(c):
		return false
	var spec := item()
	var done := false
	if is_cell_tab():
		done = _set_cell(c, str(spec["key"]))
	else:
		done = _place(c, spec)
	if done:
		_touched()
	return done


func _place(c: Vector2i, spec: Dictionary) -> bool:
	var key := UserMap.at(map, c.x, c.y)
	var label := str(spec["label"])
	if not UserMap.is_open(key):
		note = "A %s CAN'T STAND IN A WALL OR A DOOR." % label
		return false
	var inside_only: bool = spec.get("inside", false)
	if inside_only and str(UserMap.cell(key).get("group", "")) != "inside":
		note = "A %s HANGS INSIDE ONLY." % label
		return false
	var kind := str(spec["kind"])
	var name := str(spec["name"])
	var here := thing_at(c)
	if not here.is_empty() and str(here[0]) == kind and str(here[1]) == name:
		if _i(here[4]) == facing:
			return false
		here[4] = facing
		return true
	var list: Array = map["things"]
	var only_one: bool = spec.get("one", false)
	var most: int = 1 if only_one else _i(spec.get("most", 9999))
	var same := UserMap.marks(map, kind, name)
	if only_one and not same.is_empty():
		# The one of a kind moves to the new place.
		_take_thing(Vector2i(_i(same[0][0]), _i(same[0][1])))
	elif same.size() >= most:
		note = "ONLY %d %s ON A MAP." % [most, label]
		return false
	if kind == "hand" and _count("hand") >= UserMap.limit("hands") and here.is_empty():
		note = "THAT'S ENOUGH HANDS: %d IS THE MOST." % UserMap.limit("hands")
		return false
	if list.size() >= UserMap.limit("things") and here.is_empty():
		note = "THE MAP'S FULL UP: %d THINGS IS THE MOST." % UserMap.limit("things")
		return false
	_take_thing(c)
	list.append([kind, name, c.x, c.y, facing])
	return true


func _count(kind: String) -> int:
	var n := 0
	for v: Variant in map["things"]:
		var t: Array = v
		n += 1 if str(t[0]) == kind else 0
	return n


## Take away what is at `c`: the thing on it, else a wall or door goes back
## to pasture. True when something changed.
func erase(c: Vector2i) -> bool:
	if not inside(c):
		return false
	var done := _take_thing(c)
	if not done and not UserMap.is_open(UserMap.at(map, c.x, c.y)):
		done = _set_cell(c, BARE)
	if done:
		_touched()
	return done


## The picked item over a box of cells from `a` to `b`. A wall box is a
## building: the wall round the edge and the INSIDE tab's floor within.
func box(a: Vector2i, b: Vector2i) -> bool:
	var lo := Vector2i(mini(a.x, b.x), mini(a.y, b.y))
	var hi := Vector2i(maxi(a.x, b.x), maxi(a.y, b.y))
	var done := false
	if not is_cell_tab():
		return apply(b)
	var key := str(item()["key"])
	var building := UserMap.is_wall(key) and hi.x - lo.x >= 2 and hi.y - lo.y >= 2
	var floor_key := str(items(1)[picks[1]]["key"])
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			var edge := x == lo.x or x == hi.x or y == lo.y or y == hi.y
			var paint := key if (edge or not building) else floor_key
			done = _set_cell(Vector2i(x, y), paint) or done
	if done:
		_touched()
		if building:
			note = "BUILDING RAISED. PUT A DOOR IN A WALL (WALLS TAB, LAST)."
	return done


## The item under `c` picked (the dropper).
func pick_at(c: Vector2i) -> void:
	var here := thing_at(c)
	var want_kind := ""
	var want_name := ""
	if not here.is_empty():
		want_kind = str(here[0])
		want_name = str(here[1])
		facing = _i(here[4])
	for t in TABS.size():
		var list := items(t)
		for i in list.size():
			var entry: Dictionary = list[i]
			var hit := (
				str(entry.get("kind", "")) == want_kind and str(entry.get("name", "")) == want_name
				if want_kind != ""
				else str(entry.get("key", "")) == UserMap.at(map, c.x, c.y)
			)
			if hit:
				tab = t
				picks[t] = i
				return


## Rename and the like: what the map is called, who made it, its note, its
## mood. Text goes through UserMap's letters.
func set_text(key: String, text: String) -> void:
	var most := UserMap.limit(key)
	var clean := ""
	for ch in text.to_upper():
		if UserMap.LETTERS.contains(ch):
			clean += ch
	clean = clean.left(most).strip_edges()
	if key == "name" and clean == "":
		clean = "NEW MAP"
	if str(map.get(key, "")) == clean:
		return
	begin()
	map[key] = clean
	_touched()


func next_mood(step := 1) -> void:
	var list := UserMap.moods()
	var at := 0
	for i in list.size():
		if str(list[i]["id"]) == str(map.get("mood", "dusk")):
			at = i
	begin()
	map["mood"] = str(list[posmod(at + step, list.size())]["id"])
	_touched()


## Step the map's size through SIZES; what is past the new edge goes, new
## ground is pasture inside a hedgerow edge.
func next_size(step := 1) -> void:
	var w := UserMap.width(map)
	var h := UserMap.height(map)
	var at := 0
	for i in SIZES.size():
		if _i(SIZES[i][0]) <= w:
			at = i
	var size: Array = SIZES[posmod(at + step, SIZES.size())]
	resize(_i(size[0]), _i(size[1]))


func resize(w: int, h: int) -> void:
	begin()
	var old := map.duplicate(true)
	var fresh := UserMap.blank(w, h, str(old["name"]))
	for key: String in ["author", "note", "mood"]:
		fresh[key] = old[key]
	var rows: Array = fresh["rows"]
	for y in mini(h - 1, UserMap.height(old) - 1):
		var row: String = rows[y]
		for x in mini(w - 1, UserMap.width(old) - 1):
			if y == 0 or x == 0:
				continue
			var key := UserMap.at(old, x, y)
			row = row.left(x) + key + row.substr(x + 1)
		rows[y] = row
	var list: Array = fresh["things"]
	for v: Variant in old["things"]:
		var t: Array = v
		if _i(t[2]) < w - 1 and _i(t[3]) < h - 1:
			list.append(t)
	map = fresh
	# Things left stranded in a wall at the new edge go.
	var stranded: Array = map["things"]
	for v: Variant in stranded.duplicate():
		var t: Array = v
		if not UserMap.is_open(UserMap.at(map, _i(t[2]), _i(t[3]))):
			_take_thing(Vector2i(_i(t[2]), _i(t[3])))
	_touched()
	note = "MAP IS %d BY %d NOW." % [w, h]


## Save into the player's folder: "" or why not. An example (or a map not
## saved yet) gets a file named for it.
func save() -> String:
	var name := str(map["name"])
	var target := stem
	if target == "" or source != "mine":
		target = UserMaps.stem_for(name)
		var n := 2
		while FileAccess.file_exists(UserMaps.path_of(target)):
			target = UserMaps.stem_for(name) + "_%d" % n
			n += 1
	var why := UserMaps.write(map, target)
	if why != "":
		note = why
		return why
	stem = target
	source = "mine"
	changed = false
	note = "SAVED AS %s." % target.to_upper()
	return ""


static func _i(v: Variant) -> int:
	var n: int = v
	return n
