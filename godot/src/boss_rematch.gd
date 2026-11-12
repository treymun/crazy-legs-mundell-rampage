## BOSS REMATCH (the title's entry): any boss whose chapter has been beaten,
## fought again on its own. build() loads the chapter with only that boss
## (harmless critters stay), every station done and door open as by the fight
## in the campaign, the guns the campaign has by then full, and the player at
## the arena's entrance: DOOR_STEPS walking steps from the boss on the way in
## from the level's start (entrance()). The fight is timed from its start to
## the boss's fall (features/boss_rematch.gd) and pinned with a ribbon by PAR;
## the best time for each boss is kept in boss-rematch.json beside the unlocks,
## never in a campaign save. Nothing in a rematch is saved.
##
## A boss is on the board once its chapter has been beaten: the next chapter
## unlocked, or the chapter marked beaten in boss-rematch.json (a won chapter
## marks itself), or for the last chapter a campaign entry save that won it.
## `--rematch-all` on the command line or the console's `rematch` puts every
## boss on the board for testing.
class_name BossRematch
extends RefCounted

const FILE := "boss-rematch.json"
## The board's order: the campaign's.
const BOSSES := ["boss", "jerry", "rudy", "foreman", "baron", "swamp_king", "derby_champ", "maw"]
const LEVEL_OF := {
	"boss": "hickston",
	"jerry": "hickston",
	"rudy": "fair",
	"foreman": "sawmill",
	"baron": "quarry",
	"swamp_king": "bayou",
	"derby_champ": "speedway",
	"maw": "mothership",
}
## Seconds for a BLUE ribbon: tools/boss_rematch_check.gd -- bot's time to
## kill at NORMAL with the rematch's guns (the sawed-off in hand), rounded up
## (Maw: its god-mode time; the bot goes down with a third of her left). RED within
## RED_SHARE of it; any win takes WHITE. Run the bot again after a change to
## a boss's fight and set these from it.
const PAR := {
	"boss": 12.0,
	"jerry": 12.0,
	"rudy": 10.0,
	"foreman": 12.0,
	"baron": 14.0,
	"swamp_king": 10.0,
	"derby_champ": 12.0,
	"maw": 32.0,
}
const RED_SHARE := 1.6
## The guns lying about in each chapter and those before it (the levels'
## weapon pickups; boss_rematch_check.gd holds this to the level files).
const GUNS := {
	"hickston": [0, 1, 2, 3, 4, 5, 6, 7, 8, 15],
	"fair": [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 13, 15],
	"sawmill": [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 12, 13, 15],
	"quarry": [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 12, 13, 14, 15],
	"bayou": [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 12, 13, 14, 15],
	"speedway": [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 12, 13, 14, 15],
	"mothership": [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 12, 13, 14, 15],
}
## How far from the boss the player starts, in steps of the flow field.
const DOOR_STEPS := 10
## Doors a rematch leaves shut so the player comes in by the arena's front:
## the Mothership's escape hatch, which opens only when Maw falls (the way in
## is the iris), and the derby bowl's back gate (the way in is by the flag).
const SHUT := {"derby_champ": [Vector2i(89, 56)], "maw": [Vector2i(64, 62)]}
## What the framework's boss reinforcements (game.boss_backup) are set to in a
## rematch; null leaves the framework's own default.
const BACKUP = null
## The board on screen: its first row and each row's height.
const TOP := 34
const ROW := 16

static var unlock_all := false


static func folder() -> String:
	var loop := Engine.get_main_loop()
	if loop != null and loop.get_script() != null:
		return OS.get_cache_dir().path_join("clmr-boss-door")
	return SessionStore.data_directory()


static func profile_path() -> String:
	return folder().path_join(FILE)


## {"bests": {kind: seconds}, "beaten": [chapter, ...]}
static func profile() -> Dictionary:
	var out := {"bests": {}, "beaten": []}
	var file := profile_path()
	if not FileAccess.file_exists(file):
		return out
	var raw := FileAccess.get_file_as_bytes(file)
	if raw.size() > 4096:
		return out
	var doc = JSON.parse_string(raw.get_string_from_utf8())
	if not (doc is Dictionary):
		return out
	var bests = doc.get("bests", {})
	if bests is Dictionary:
		for kind in bests:
			var t = bests[kind]
			if BOSSES.has(String(kind)) and (t is float or t is int) and float(t) > 0.0:
				out["bests"][String(kind)] = float(t)
	var beaten = doc.get("beaten", [])
	if beaten is Array:
		for level_id in beaten:
			if Campaign.ORDER.has(String(level_id)):
				out["beaten"].append(String(level_id))
	return out


static func _write(doc: Dictionary) -> bool:
	return SessionStore._write_atomic(profile_path(), JSON.stringify(doc, "", false))


static func best(kind: String) -> float:
	return float(profile()["bests"].get(kind, 0.0))


## Keep a time if it is the boss's best; true when it is.
static func record(kind: String, seconds: float) -> bool:
	var doc := profile()
	var old := float(doc["bests"].get(kind, 0.0))
	if old > 0.0 and old <= seconds:
		return false
	doc["bests"][kind] = snappedf(seconds, .01)
	_write(doc)
	return true


static func mark_beaten(level_id: String) -> void:
	var doc := profile()
	if not Campaign.ORDER.has(level_id) or doc["beaten"].has(level_id):
		return
	doc["beaten"].append(level_id)
	_write(doc)


static func beaten(level_id: String, unlocked: Dictionary, doc: Dictionary) -> bool:
	if doc["beaten"].has(level_id):
		return true
	var following := Campaign.next_level(level_id)
	if following != "":
		return unlocked.has(following)
	# The last chapter has no gate after it: a campaign entry save that won it.
	var entry := SessionStore.data_directory().path_join(SessionStore.ENTRY_FILE)
	if not FileAccess.file_exists(entry):
		return false
	var saved = JSON.parse_string(FileAccess.get_file_as_string(entry))
	return (
		saved is Dictionary
		and String(saved.get("level", "")) == level_id
		and saved.get("game", {}).get("won", false) == true
	)


## Which bosses are on the board: kind -> true.
static func available(unlocked: Dictionary) -> Dictionary:
	var doc := profile()
	var out := {}
	var known := {}
	for kind: String in BOSSES:
		var level_id := String(LEVEL_OF[kind])
		if not known.has(level_id):
			known[level_id] = unlock_all or beaten(level_id, unlocked, doc)
		if known[level_id]:
			out[kind] = true
	return out


static func active(game) -> bool:
	if game == null:
		return false
	var feature = game.features.get("boss_rematch")
	return feature != null and feature.active


static func title(kind: String) -> String:
	return BossBar.title(kind)


static func ribbon(kind: String, seconds: float) -> String:
	var par := float(PAR.get(kind, 60.0))
	if seconds <= par:
		return "BLUE"
	if seconds <= par * RED_SHARE:
		return "RED"
	return "WHITE"


static func clock_text(seconds: float) -> String:
	var tenths := int(floorf(maxf(0.0, seconds) * 10.0))
	return "%d:%02d.%d" % [tenths / 600, (tenths / 10) % 60, tenths % 10]


# ------------------------------------------------------------------ the fight


## The chapter set for a rematch with `kind`, the player at the entrance; null
## when the chapter has no such boss.
static func build(make_game: Callable, kind: String) -> Game:
	var level_id := String(LEVEL_OF.get(kind, ""))
	if level_id == "":
		return null
	var g: Game = make_game.call(level_id)
	var boss := BossFight.of_kind(g, kind)
	if boss == null:
		return null
	var feature = g.features["boss_rematch"]
	feature.active = true
	feature.kind = kind
	_prune(g, boss)
	_finish_stations(g)
	g.keys["key_brass"] = true
	g.keys["key_steel"] = true
	var shut: Array = SHUT.get(kind, [])
	for door: LevelData.Door in g.world.doors:
		if not door.secret and not shut.has(Vector2i(door.x, door.y)):
			door.opened = true
			door.progress = 1.0
	_arm(g, level_id)
	var spot = entrance(g, boss)
	var p := g.player
	if spot != null:
		p.x = spot.x
		p.y = spot.y
	p.angle = atan2(boss.y - p.y, boss.x - p.x)
	p.pitch = 0.0
	p.eye = g.world.elevation(p.x, p.y) + .95
	g.district = int(g.world.area[g.world.cell(p.x, p.y)])
	boss.dormant = false
	boss.hp = boss.max_hp
	boss.alerted = true
	boss.target = [p.x, p.y]
	boss.cooldown = maxf(boss.cooldown, 1.5)
	if BACKUP != null and "boss_backup" in g:
		g.set("boss_backup", BACKUP)
	g.shots.clear()
	g.hazards.clear()
	g.message("REMATCH: %s. THE CLOCK STARTS IN THE ARENA." % title(kind), 4.0)
	return g


## Only the boss stays of everything hostile (harmless critters too); a
## posse is never brought.
static func _prune(g: Game, boss: Enemy) -> void:
	var gone := {}
	for i in range(g.enemies.size() - 1, -1, -1):
		var e: Enemy = g.enemies[i]
		if e == boss or not e.hostile:
			continue
		gone[e] = true
		e.hp = 0.0
		g.enemies.remove_at(i)
		if i < g.enemy_ids.size():
			g.enemy_ids.remove_at(i)
	g.wave = g.wave.filter(func(e: Enemy) -> bool: return not gone.has(e))
	for key in g.partners.keys():
		var pair: Array = g.partners[key]
		if gone.has(pair[0]) or not g.enemies.any(func(e): return e.get_instance_id() == key):
			g.partners.erase(key)
	for name: String in ["boss", "jerry", "finale"]:
		if gone.has(g.get(name)):
			g.set(name, null)
	var posse = g.features.get("posse")
	if posse != null and "spawned" in posse:
		posse.spawned = true
	g.total_kills = 0
	for e: Enemy in g.enemies:
		if e.hostile:
			g.total_kills += 1


## Every station done, in the order they need, as by the campaign's boss fight.
static func _finish_stations(g: Game) -> void:
	var left: Array = g.world.stations.duplicate()
	var moved := true
	while moved and not left.is_empty():
		moved = false
		for station: LevelData.Station in left.duplicate():
			var ready := true
			for key in station.requires:
				ready = ready and g.stations_done.has(String(key))
			if ready:
				g.activate_station(station)
				left.erase(station)
				moved = true


static func _arm(g: Game, level_id: String) -> void:
	var guns: Array = GUNS.get(level_id, [0, 1])
	for i in Weapons.COUNT:
		var owned := guns.has(i)
		g.armory.owned[i] = owned
		g.armory.loaded[i] = Weapons.CAPACITY[i] if owned else 0
		g.armory.reserve[i] = Weapons.MAX_RESERVE[i] if owned else 0
	g.armory.active = Weapons.SHOTGUN
	g.player.health = 100
	g.inventory["rinds"] = 2
	g.inventory["beer"] = 1


## The arena's entrance: the cell DOOR_STEPS walking steps from the boss on the
## way from the level's start (the nearest such cell to the start when the
## start cannot walk there); null when nothing near the boss can be walked to.
static func entrance(g: Game, boss: Enemy) -> Variant:
	var field := field_from(g, boss)
	if field == null:
		return null
	var start := Vector2(float(g.level.spawn[0]), float(g.level.spawn[1]))
	var path: Array = []
	field.waypoint(start.x, start.y, 100000, path)
	if field.distance(start.x, start.y) < FlowField.FAR:
		if field.distance(start.x, start.y) <= DOOR_STEPS:
			return start
		for cell: Vector2i in path:
			if field.distance(cell.x + .5, cell.y + .5) <= DOOR_STEPS and fits(g, cell):
				return Vector2(cell.x + .5, cell.y + .5)
	var best = null
	var near := INF
	for cy in g.world.height:
		for cx in g.world.width:
			var cell := Vector2i(cx, cy)
			if field.steps[cy * g.world.width + cx] != DOOR_STEPS or not fits(g, cell):
				continue
			var d := start.distance_to(Vector2(cx + .5, cy + .5))
			if d < near:
				near = d
				best = Vector2(cx + .5, cy + .5)
	return best


## Walking steps measured from the boss (from the nearest open cell to it, for
## a boss out on deep water), through every door that stands open.
static func field_from(g: Game, boss: Enemy) -> FlowField:
	var field := FlowField.new(g.level, g.flow)
	field.reach = 100000
	field.doors_open = true
	field.keys = g.keys
	var w := g.world.width
	var seed := Vector2i(-1, -1)
	var near := INF
	for r in 9:
		for cy in range(int(boss.y) - r, int(boss.y) + r + 1):
			for cx in range(int(boss.x) - r, int(boss.x) + r + 1):
				if cx < 0 or cy < 0 or cx >= w or cy >= g.world.height:
					continue
				if not field.passable(cy * w + cx):
					continue
				var d := Vector2(cx + .5 - boss.x, cy + .5 - boss.y).length()
				if d < near:
					near = d
					seed = Vector2i(cx, cy)
		if seed.x >= 0:
			break
	if seed.x < 0:
		return null
	field.update(seed.x + .5, seed.y + .5, 0.0)
	return field


## A body fits in the middle of the cell, on floor the player can stand on.
static func fits(g: Game, cell: Vector2i) -> bool:
	var x := cell.x + .5
	var y := cell.y + .5
	return (
		not g.world.blocked(x, y, GameState.PLAYER_RADIUS + .05)
		and not g.world.deep_at(x, y)
		and g.world.solid[cell.y * g.world.width + cell.x] < 0
	)


# ------------------------------------------------------------------ screens


## The board: a row a boss, its chapter, its best and ribbon, or LOCKED.
static func draw_board(
	c: Canvas,
	menu: Menu,
	pick: int,
	open: Dictionary,
	bests: Dictionary,
	note: String,
	guide: String,
	hover: String
) -> void:
	menu.draw_sheet(c, "BOSS REMATCH")
	for i in BOSSES.size():
		var kind: String = BOSSES[i]
		var y := TOP + i * ROW
		var here := i == pick
		var ready := open.has(kind)
		if here:
			c.fill_rect(19, y, 282, ROW - 1, Canvas.rgb(82, 49, 31))
			Menu.shell(c, 22, y + 4)
		elif i % 2 == 0:
			c.fill_rect(19, y, 282, ROW - 1, Canvas.rgb(33, 23, 19))
		var ink := HUD.AMBER if here else (HUD.INK if ready else Menu.DIM)
		HUD.text(c, title(kind), 36, y + 1, "body", ink)
		var chapter := Campaign.title_of(String(LEVEL_OF[kind]))
		HUD.text(
			c, chapter if ready else "BEAT " + chapter, 36, y + 9, "mini", Menu.FADED, false, false
		)
		if not ready:
			HUD.text(c, "LOCKED", 296, y + 4, "body", Menu.DIM, false, true, true)
			continue
		var t := float(bests.get(kind, 0.0))
		if t <= 0.0:
			HUD.text(c, "NO TIME YET", 296, y + 4, "mini", Menu.FADED, false, false, true)
			continue
		HUD.text(c, clock_text(t), 296, y + 1, "body", ink, false, true, true)
		var word := ribbon(kind, t)
		HUD.text(c, word + " RIBBON", 296, y + 9, "mini", ribbon_ink(word), false, false, true)
	var line := note
	if line == "":
		var kind: String = BOSSES[posmod(pick, BOSSES.size())]
		var par := float(PAR[kind])
		line = ("BLUE %s  RED %s  WHITE ANY WIN" % [clock_text(par), clock_text(par * RED_SHARE)])
	HUD.text(c, line, 160, TOP + ROW * BOSSES.size() + 3, "body", HUD.AMBER, true)
	HUD.text(c, guide, 124, 181, "mini", HUD.INK, true)
	Menu.plate_button(c, Menu.BACK, "BACK", hover == "back")


static func ribbon_ink(word: String) -> Color:
	match word:
		"BLUE":
			return Canvas.rgb(110, 160, 236)
		"RED":
			return Canvas.rgb(222, 80, 60)
	return Canvas.rgb(236, 230, 214)


## The row of the board under a point of the picture, or -1.
static func row_at(x: int, y: int) -> int:
	if x < 19 or x >= 301 or y < TOP or y >= TOP + ROW * BOSSES.size():
		return -1
	return (y - TOP) / ROW


## After the fall: the time, the ribbon pinned beside it, the best.
## `result`: {kind, seconds, best, fresh}.
static func draw_result(
	c: Canvas, menu: Menu, result: Dictionary, guide: String, hover: String
) -> void:
	menu.draw_sheet(c, "REMATCH")
	var kind := String(result.get("kind", "boss"))
	var seconds := float(result.get("seconds", 0.0))
	var word := ribbon(kind, seconds)
	HUD.panel(c, 24, 38, 180, 118, Canvas.rgb(40, 29, 23))
	HUD.text(c, title(kind), 34, 46, "heading", HUD.AMBER)
	HUD.text(c, "IS DOWN", 34, 62, "body", HUD.INK)
	c.line(34, 74, 194, 74, Canvas.rgb(135, 95, 63))
	c.fill_rect(34, 80, 160, 15, Canvas.rgb(30, 21, 17))
	HUD.text(c, "TIME", 39, 84, "body", HUD.INK)
	HUD.text(c, clock_text(seconds), 188, 84, "body", HUD.AMBER, false, true, true)
	c.fill_rect(34, 98, 160, 15, Canvas.rgb(30, 21, 17))
	HUD.text(c, "BEST", 39, 102, "body", HUD.INK)
	var best_t := float(result.get("best", seconds))
	HUD.text(c, clock_text(best_t), 188, 102, "body", HUD.AMBER, false, true, true)
	var par := float(PAR.get(kind, 60.0))
	HUD.text(
		c,
		"BLUE %s  RED %s" % [clock_text(par), clock_text(par * RED_SHARE)],
		34,
		120,
		"mini",
		Menu.FADED,
		false,
		false
	)
	if bool(result.get("fresh", false)):
		HUD.text(c, "A NEW BEST. THE COUNTY TAKES NOTE.", 34, 134, "body", HUD.AMBER)
	else:
		HUD.text(c, "THE OLD BEST STANDS.", 34, 134, "body", HUD.INK)
	_rosette(c, 256, 70, word)
	HUD.text(c, guide, 124, 181, "mini", HUD.INK, true)
	Menu.plate_button(c, Menu.BACK, "BOARD", hover == "back")


## A county-fair rosette: a round of pleats, the word on its button, two tails.
static func _rosette(c: Canvas, cx: int, cy: int, word: String) -> void:
	var face := ribbon_ink(word)
	var deep := face.darkened(.45)
	var gold := Color(236 / 255.0, 196 / 255.0, 104 / 255.0)
	for x: int in [cx - 14, cx + 6]:
		c.fill_rect(x, cy + 14, 9, 38, deep)
		c.fill_rect(x + 1, cy + 14, 7, 37, face)
		c.fill_rect(x + 2, cy + 51, 5, 4, face)
	c.circle(cx, cy, 25, deep)
	c.circle(cx, cy, 23, face)
	for k in 16:
		var a := k * TAU / 16.0
		c.fill_rect(int(cx + cos(a) * 21.0) - 1, int(cy + sin(a) * 21.0) - 1, 2, 2, deep)
	c.circle(cx, cy, 15, gold)
	c.circle(cx, cy, 13, Canvas.rgb(40, 29, 23))
	HUD.text(c, word, cx, cy - 7, "body", gold, true)
	HUD.text(c, "RIBBON", cx, cy + 2, "mini", gold, true, false)
