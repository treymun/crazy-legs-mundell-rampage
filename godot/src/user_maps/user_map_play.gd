## The front end's side of player maps: the CUSTOM MAPS list (state "maps")
## and the MAP SHED (state "mapedit"), playing a map in a mode, the shed's
## test run, hosting one online, and a map's own save. Its state is kept here
## (static: one front end) so the front end's layers hold only small hooks:
## main_state entries/MENU_STATES, main_flow play/continue_campaign/
## return_to_title/save_game/load_game/net_match_game/net_open_lobby.
class_name UserMapPlay
extends RefCounted

## What a list row can do, in the order the buttons show.
const ACTIONS := ["solo", "bomb", "hostage", "county", "host", "edit", "remove"]
const ACTION_NAMES := {
	"solo": "PLAY ALONE",
	"bomb": "5V5 VS BOTS",
	"hostage": "HOSTAGE VS BOTS",
	"county": "COUNTY RUN",
	"host": "HOST ONLINE",
	"edit": "EDIT IN THE SHED",
	"remove": "THROW IT OUT",
}
## A map save's own format (the game part is SessionStore's, at its VERSION,
## brought up by SaveUpgrade like any save).
const SAVE_VERSION := 1
const SAVES := "saves"

static var entries: Array = []
static var row := 0
static var action := 0
static var editor: MapEditor = null
## The list entry being played (its map, file and where it came from).
static var playing: Dictionary = {}
## The shed's test run is the game in play.
static var testing := false
## A line under the list ("SAVED.", why a map would not start).
static var note := ""
## THROW IT OUT pressed once: the next press throws it out.
static var armed := false


static func refresh() -> void:
	entries = UserMaps.list()
	row = clampi(row, 0, maxi(0, entries.size() - 1))


static func picked() -> Dictionary:
	if entries.is_empty():
		return {}
	var entry: Dictionary = entries[clampi(row, 0, entries.size() - 1)]
	return entry


## Why `entry` cannot do `what` ("" when it can).
static func why_not(entry: Dictionary, what: String) -> String:
	if entry.is_empty():
		return "NO MAP PICKED."
	if entry.has("error"):
		return str(entry["error"])
	var map: Dictionary = entry["map"]
	match what:
		"solo", "bomb", "hostage", "county":
			return str(UserMap.modes(map)[what])
		"host":
			var hosts := UserMap.hosts(map)
			for mode: String in ["bomb", "hostage", "county"]:
				if hosts.has(mode):
					return ""
			return "ONLINE NEEDS 5V5 MARKS OR ROOM FOR A COUNTY RUN."
		"remove":
			return "THE EXAMPLES STAY." if str(entry["source"]) == "example" else ""
	return ""


static func open_list(m: MainFlow, message := "") -> void:
	refresh()
	armed = false
	note = message
	m.state = "maps"
	m.menu_music()
	m.grab(false)


## Leave whatever mode the title had set (a 5v5, a county run).
static func _clear_mode(m: MainFlow) -> void:
	m.showdown_on = false
	m.mode_name = ""
	m.mode_players = 1
	m.mode_options = {}


## Play the picked map: "" or why not.
static func play(m: MainFlow, entry: Dictionary, what: String) -> String:
	var why := why_not(entry, what)
	if why != "":
		return why
	var map: Dictionary = entry["map"]
	playing = entry
	testing = false
	_clear_mode(m)
	match what:
		"solo":
			m.start(UserMaps.register(map))
		"bomb", "hostage":
			var id := UserMaps.register(map, true)
			m.mode_name = Modes.BOMB if what == "bomb" else Modes.HOSTAGE
			m.mode_players = Modes.MAX_PLAYERS
			m.mode_options = {"arena": id, "store_rules": "any", "bot_skill": 1}
			m.showdown_on = true
			m.start_match()
		"county":
			m.start_county(UserMaps.register(map, true))
	return ""


## The shed's TEST: the map as it stands, from your start (or from the cell
## the cursor is on when there is none, or `here`).
static func test(m: MainFlow, here := false) -> String:
	if editor == null:
		return "NOTHING IN THE SHED."
	var map := editor.map.duplicate(true)
	var checked := UserMap.parse_text(UserMap.to_text(map))
	if checked.has("error"):
		return str(checked["error"])
	map = checked["map"]
	var start: Variant = UserMap.mark(map, "start")
	var c := editor.cursor
	if here or start == null:
		if not UserMap.is_open(UserMap.at(map, c.x, c.y)) or not editor.thing_at(c).is_empty():
			return "PUT YOUR START DOWN, OR THE CURSOR ON OPEN GROUND."
	_clear_mode(m)
	testing = true
	playing = {"map": map, "source": "test", "stem": ""}
	m.start(UserMaps.register(map))
	if m.game != null and (here or start == null):
		var p := m.game.player
		p.x = c.x + 1.5
		p.y = c.y + 1.5
		p.angle = editor.facing * PI / 4.0
		p.eye = .95 + m.game.world.stand(p)
	return ""


## ESC out of the shed's test run goes back to the shed (true: it did).
static func back_from_test(m: MainFlow) -> bool:
	if not testing:
		return false
	testing = false
	m.game = null
	m.state = "mapedit"
	m.menu_music()
	m.grab(false)
	return true


## ENTER on a custom map's tally: back to the shed after a test, else to the
## list. False for any other game.
static func finished(m: MainFlow) -> bool:
	if m.game == null or not UserMap.is_custom(m.game.level.id):
		return false
	if back_from_test(m):
		return true
	m.game = null
	open_list(m, "MAP DONE. THE COUNTY THANKS YA.")
	return true


## HOST ONLINE: the host form, with the map waiting for the lobby.
static func host(m: MainFlow, entry: Dictionary) -> String:
	var why := why_not(entry, "host")
	if why != "":
		return why
	NetMaps.pending = entry["map"]
	m.open_net_form(true)
	return ""


# ------------------------------------------------------------------ saves


static func _save_path(entry: Dictionary) -> String:
	var key := "%s_%s" % [entry.get("source", "mine"), entry.get("stem", "map")]
	if str(entry.get("source", "")) == "shared":
		key = "shared_" + str(entry.get("hash", "")).substr(0, 16)
	return UserMaps.folder().path_join(SAVES).path_join(key + ".json")


static func has_save(entry: Dictionary) -> bool:
	return FileAccess.file_exists(_save_path(entry))


## F6 on a custom map: its own save (never the campaign's). True when it
## dealt with the key (a custom map is in play).
static func save(m: MainFlow) -> bool:
	var target := m.game
	if target == null or not UserMap.is_custom(target.level.id):
		return false
	if testing:
		m.notice("NO SAVING A TEST RUN. SAVE THE MAP IN THE SHED.")
	elif Modes.is_versus(target) or CountyMode.active(target) or playing.is_empty():
		m.notice("NO SAVING A MATCH ON A COUNTY MAP.")
	elif target.player.health <= 0 or target.showing_tally or target.armory.fuse > 0.0:
		m.notice("START A LIVE RUN TO SAVE.")
	else:
		var map: Dictionary = playing["map"]
		var doc := SessionStore.snapshot(target)
		doc["custom_save"] = SAVE_VERSION
		doc["custom_map"] = {
			"hash": UserMap.hash_of(map),
			"name": str(map["name"]),
			"stem": str(playing.get("stem", "")),
			"source": str(playing.get("source", "mine")),
		}
		var path := _save_path(playing)
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			m.notice("COULD NOT WRITE THE MAP SAVE.")
			return true
		file.store_string(JSON.stringify(doc, "", false))
		file.close()
		m.notice("MAP SAVED. F9 TO LOAD.")
		m.sound.play("menu_accept", .65)
	return true


## F9 on a custom map (true: it dealt with the key).
static func load_key(m: MainFlow) -> bool:
	if m.game == null or not UserMap.is_custom(m.game.level.id):
		return false
	if testing or playing.is_empty():
		m.notice("NO SAVES FOR A TEST RUN.")
		return true
	var why := load_save(m, playing)
	if why != "":
		m.notice(why, 3.0)
	return true


## The save of `entry` loaded and played: "" or why not (the file is kept
## whatever goes wrong).
static func load_save(m: MainFlow, entry: Dictionary) -> String:
	var path := _save_path(entry)
	if not FileAccess.file_exists(path):
		return "NO SAVE FOR THIS MAP YET."
	var restored: Variant = read_save(path, entry, m.make_game)
	if restored is String:
		return str(restored)
	var loaded: Game = restored
	playing = entry
	testing = false
	_clear_mode(m)
	m.play(loaded)
	m.notice("MAP SAVE LOADED.")
	return ""


## A map save read back onto a fresh game of its map (a Game), or why not (a
## String): a newer save, a map gone or changed since, a save that does not
## fit. `make_game` makes a game of a level id.
static func read_save(path: String, entry: Dictionary, make_game: Callable) -> Variant:
	var raw := FileAccess.get_file_as_bytes(path)
	if raw.size() > SessionStore.MAX_BYTES:
		return "THAT SAVE IS TOO BIG TO BE ONE. FILE KEPT."
	var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
	if not parsed is Dictionary:
		return "THAT SAVE IS BROKEN. FILE KEPT."
	var doc: Dictionary = parsed
	var version: Variant = doc.get("custom_save")
	if not (version is float or version is int):
		return "THAT AIN'T A MAP SAVE. FILE KEPT."
	var save_version: int = version
	if save_version > SAVE_VERSION:
		return "THAT SAVE IS FROM A NEWER GAME. FILE KEPT."
	var about: Variant = doc.get("custom_map")
	if not about is Dictionary:
		return "THAT SAVE DOESN'T SAY WHICH MAP. FILE KEPT."
	var said: Dictionary = about
	if entry.is_empty() or entry.has("error") or not entry.has("map"):
		return "THAT MAP'S GONE. THE SAVE STAYS PUT."
	var map: Dictionary = entry["map"]
	if str(said.get("hash", "")) != UserMap.hash_of(map):
		return "THE MAP CHANGED SINCE THAT SAVE. START IT FRESH; THE SAVE STAYS PUT."
	var id := UserMaps.register(map)
	var upgraded: Variant = SaveUpgrade.upgrade(doc)
	if not upgraded is Dictionary:
		return "THAT SAVE IS TOO OLD OR TOO NEW. FILE KEPT."
	var fields: Dictionary = upgraded
	if str(fields.get("level", "")) != id:
		return "THAT SAVE IS FOR ANOTHER MAP. FILE KEPT."
	var made: Game = make_game.call(id)
	if made == null or made.level == null:
		return "THE MAP WOULD NOT LOAD."
	SessionStore.last_error = ""
	var game := SaveRestore.restore_onto(fields, made)
	if game == null:
		push_warning("map save refused: " + SessionStore.last_error)
		return "THAT SAVE DOESN'T FIT THE MAP. FILE KEPT."
	return game
