## The campaign played online in co-op (CAMPAIGN CO-OP in a hosted lobby),
## the front end's part: NetPlay carries the lobby and the wire, the co-op
## rules are CoopMode's; this is what the host does between games and what
## every machine does to the game a START names (docs/dev/modes.md "Online
## co-op").
##
## The host plays the one real game; whenever the party goes somewhere else
## the host makes the next game and moves the match onto it
## (NetPlay.switch_match: a START to everyone, on their own slots):
##   - the chapter won: the host's ENTER on the tally makes the next chapter
##     (each player's own kit carried, Modes.carry) and takes the party to
##     the COUNTY CROSSROADS, its gate open (with CLASSIC on, straight in);
##   - a gate (any player's USE): the hub's into a chapter (the one under way
##     is picked up where it was left, `main.net_run`; any other starts
##     fresh with everyone's kit), a chapter's back to the hub;
##   - everyone down: ENTER retries a boss fight from the party's own boss
##     checkpoint (BossDoor.path_of: a -party file, never the host's own),
##     with the partners at player one's side (Modes.gather); R, or no
##     checkpoint, the chapter from its start.
## The host's F5 writes THE PARTY SAVE (only the host saves online); MAP
## THE PARTY SAVE in the lobby picks it up again, any slot without its person
## lying out of play until someone joins late. The host's own campaign, its
## quicksave and its boss checkpoints are never touched; the chapters the
## party reaches open on the host's profile as a local co-op's do.
class_name NetCoop
extends RefCounted

const SAVE_FILE := "party-save.json"


## Where THE PARTY SAVE is kept (a tool's under the cache folder).
static func save_path() -> String:
	return BossDoor.folder().path_join(SAVE_FILE)


## What MAP THE PARTY SAVE would load: "" when it can, else why not.
static func save_note() -> String:
	if not FileAccess.file_exists(save_path()):
		return "NO PARTY SAVE YET. THE HOST'S F5 MAKES ONE."
	return ""


# ------------------------------------------------------------ every machine


## A co-op game a START names, made ready on every machine alike (the host's
## snapshots then put on all the rest): the hub's locked gates and labels,
## a chapter's starting kit (past Hickston the replay kit, as a gate picked
## on the hub gives) for everyone.
static func dress(made: Game, options: Dictionary, fresh: bool) -> void:
	if made.level.id == "hub":
		made.in_hub = true
		var locked: Array = options.get("locked", [])
		made.world.locked_gates = []
		for gate: LevelData.Gate in made.world.hub_gates:
			if locked.has(gate.destination):
				made.world.locked_gates.append(gate)
		var labels: Dictionary = options.get("gate_modes", {})
		made.gate_modes = labels.duplicate()
		made.district = int(made.world.area[made.world.cell(made.player.x, made.player.y)])
		return
	if fresh:
		chapter_kit(made, made.level.id)
		for p: Player in made.players:
			if p != made.players[0]:
				Modes.carry(made.players[0], p)
	made.entry = made.loadout()


## A chapter's kit when it is started from its gate rather than played into
## (main_flow.gd start's replay kit): the shotgun and rifle, the chapter's
## own new gun, the teat gun, kegs and two rinds. Hickston keeps the start's.
static func chapter_kit(fresh: Game, level_id: String) -> void:
	if level_id == "hickston":
		return
	fresh.armory.owned[Weapons.SHOTGUN] = true
	fresh.armory.owned[Weapons.RIFLE] = true
	fresh.armory.loaded[Weapons.SHOTGUN] = Weapons.CAPACITY[Weapons.SHOTGUN]
	fresh.armory.loaded[Weapons.RIFLE] = Weapons.CAPACITY[Weapons.RIFLE]
	fresh.armory.reserve[Weapons.SHOTGUN] = 16
	fresh.armory.reserve[Weapons.RIFLE] = 48
	fresh.armory.active = Weapons.SHOTGUN
	fresh.inventory["rinds"] = 2
	var bonus: Array = (
		{
			"fair": [Weapons.ROCKET, 3],
			"sawmill": [Weapons.BOWLING, 3],
			"quarry": [Weapons.COW, 3],
			"bayou": [Weapons.CROSSBOW, 6],
			"speedway": [Weapons.CROSSBOW, 6],
			"mothership": [Weapons.ARMGUN, 18],
		}
		. get(level_id, [Weapons.ROCKET, 3])
	)
	var new_weapon: int = bonus[0]
	fresh.armory.owned[new_weapon] = true
	fresh.armory.loaded[new_weapon] = Weapons.CAPACITY[new_weapon]
	var bonus_rounds: int = bonus[1]
	fresh.armory.reserve[new_weapon] = bonus_rounds
	for extra: Array in [[Weapons.TEAT, 60], [Weapons.KEG, 2]]:
		var slot: int = extra[0]
		fresh.armory.owned[slot] = true
		fresh.armory.loaded[slot] = Weapons.CAPACITY[slot]
		var extra_rounds: int = extra[1]
		fresh.armory.reserve[slot] = extra_rounds


# ------------------------------------------------------------ the host


static func hosting(main: MainFlow) -> bool:
	return (
		main.net != null
		and main.net.role == NetPlay.Role.HOST
		and main.net.match_game() != null
		and Modes.mode_of(main.net.match_game()) == Modes.COOP
	)


## THE PARTY SAVE picked in the lobby (the host's make_match): the save
## loaded as co-op, the people now in the lobby on its slots in order (a
## slot nobody takes lies out of play; more people than slots join beside
## player one). START's level becomes the save's.
static func load_party(main: MainFlow, info: Dictionary) -> Game:
	var loaded := SessionStore.read(save_path(), main.make_game, false)
	if loaded == null or Modes.mode_of(loaded) != Modes.COOP:
		return null
	info["level"] = loaded.level.id
	var options: Dictionary = info["options"]
	var names: Array = options.get("names", [])
	var count: int = info["count"]
	while loaded.players.size() < mini(count, Modes.MAX_FREE_FOR_ALL):
		Modes.join_beside(loaded, loaded.players[0])
	for p: Player in loaded.players:
		if p.slot < names.size():
			p.name = str(names[p.slot])
			p.away = false
		elif p.slot > 0:
			Modes.went_away(loaded, p)
			p.name = ""
	info["count"] = loaded.players.size()
	main.net_run = loaded
	return loaded


## The host's ENTER on a won chapter's tally: the next chapter made, its
## gate opened (on the host's profile too), and the party to the hub.
static func next(main: MainFlow) -> void:
	var current := main.net.match_game()
	var following := Campaign.next_level(current.level.id)
	if following == "":
		main.net_run = null
		hub(main, current, "THE SKY'S CLEAR. EVERY ROAD LEADS BACK TO A FINISHED CHAPTER.")
		return
	var made := chapter(main, following, current)
	made.history = current.history.duplicate()
	made.history.append(current.result())
	main.net_run = made
	main.unlocked[following] = true
	var merged := SessionStore.unlocks("")
	for key: Variant in merged:
		main.unlocked[key] = true
	var tool := Engine.get_main_loop() != null and Engine.get_main_loop().get_script() != null
	if not tool:
		SessionStore.save_unlocks("", main.unlocked)
	var classic: int = main.options["classic"]
	if classic != 0:
		go(main, made)
		return
	hub(main, current, "GATE OPEN: " + Campaign.title_of(following))


## A chapter made fresh for the party, everyone's kit (health, guns, rounds,
## pockets) and name carried from `from`, the slots kept.
static func chapter(main: MainFlow, level_id: String, from: Game) -> Game:
	var made: Game = main.make_game(level_id)
	made.configure(main.net_options(main.net.match_info))
	made.supply_rule = from.supply_rule
	var options: Dictionary = main.net.match_info["options"]
	Modes.setup(made, Modes.COOP, from.players.size(), {"names": options.get("names", [])})
	_carry_all(from, made)
	made.entry = made.loadout()
	return made


static func _carry_all(from: Game, to: Game) -> void:
	for i in mini(from.players.size(), to.players.size()):
		var was: Player = from.players[i]
		var now: Player = to.players[i]
		Modes.carry(was, now)
		now.name = was.name
		if was.away:
			Modes.went_away(to, now)


## The COUNTY CROSSROADS for the party: the gates the host has opened (and
## the chapter under way, CONTINUE), everyone at the hub's spawn with their
## kit; the clients make the same gates from START (`locked`, `gate_modes`).
static func hub(main: MainFlow, from: Game, message: String) -> void:
	var made: Game = main.make_game("hub")
	made.configure(main.net_options(main.net.match_info))
	made.hub_findings = main.hub_findings
	made.visited = main.hub_visited
	Modes.setup(made, Modes.COOP, from.players.size())
	_carry_all(from, made)
	var locked: Array = []
	var labels := {}
	for gate: LevelData.Gate in made.world.hub_gates:
		var dest := gate.destination
		var run := main.net_run
		if run != null and run.level.id == dest and not run.won:
			labels[dest] = "CONTINUE"
		elif not main.unlocked.has(dest):
			locked.append(dest)
		else:
			labels[dest] = "REPLAY"
	var extra := {"locked": locked, "gate_modes": labels}
	dress(made, extra, false)
	made.message(message if message != "" else "COUNTY CROSSROADS. FACE A GATE AND PRESS E.", 4.5)
	go(main, made, extra)


## A gate taken (any player's USE sets the host's game's portal_request).
static func travel(main: MainFlow, destination: String) -> void:
	var current := main.net.match_game()
	current.portal_request = ""
	if destination == "hub":
		if not current.in_hub and not current.won:
			main.net_run = current  # picked up where it was left
		hub(main, current, "")
		return
	var run := main.net_run
	if run != null and run.level.id == destination and not run.won and run != current:
		_carry_all(current, run)
		main.face_into_level(run)
		Modes.gather(run)
		run.message("BACK IN %s." % Campaign.title_of(destination), 3.0)
		go(main, run)
		return
	if not main.unlocked.has(destination):
		return
	var made := chapter(main, destination, current)
	main.net_run = made
	go(main, made)


## Everyone down: the boss fight again from the party's checkpoint, or
## (`fight` false, or none to load) the chapter from its start with player
## one's kit as it was entered and the partners' carried.
static func retry(main: MainFlow, fight: bool) -> void:
	var current := main.net.match_game()
	var loaded: Game = BossDoor.restore(main.make_game, current) if fight else null
	if loaded != null:
		loaded.configure(main.net_options(main.net.match_info))
		for i in mini(current.players.size(), loaded.players.size()):
			loaded.players[i].name = current.players[i].name
			if current.players[i].away:
				Modes.went_away(loaded, loaded.players[i])
		loaded.history = current.history.duplicate()
		main.net_run = loaded
		go(main, loaded)
		return
	var made := chapter(main, current.level.id, current)
	made.apply_loadout(current.entry)
	made.player.health = 100
	made.entry = current.entry
	made.history = current.history.duplicate()
	main.net_run = made
	if fight:
		made.message("THE BOSS CHECKPOINT WOULDN'T LOAD. THE CHAPTER STARTS OVER.", 4.0)
	go(main, made)


## The match moves onto `made` for everyone, and the host plays it.
static func go(main: MainFlow, made: Game, extra := {}) -> void:
	main.net.switch_match(made, extra)
	main.net_begin_match()


## The host's F5: THE PARTY SAVE (the host's only; a client is told so).
static func save(main: MainFlow) -> void:
	var target := main.net.match_game()
	if main.net.role != NetPlay.Role.HOST:
		main.notice("THE HOST KEEPS THE SAVES.")
	elif target.in_hub:
		main.notice("ENTER A CHAPTER TO SAVE THE PARTY.")
	elif target.showing_tally or target.defeated():
		main.notice("NOTHING TO SAVE RIGHT NOW.")
	elif target.armory.fuse > 0.0:
		main.notice("THROW THE LIT STICK BEFORE SAVING.")
	elif not SessionStore.save(target, save_path()):
		main.notice("COULD NOT WRITE THE PARTY SAVE.")
	else:
		main.notice("PARTY SAVED. PICK THE PARTY SAVE IN THE LOBBY TO PLAY ON.")
		main.sound.play("menu_accept", .65)
