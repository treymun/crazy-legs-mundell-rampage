## Mundell's Proving Grounds (data/range.json, src/range_layout.gd): the
## firing range off the title screen. On any other level it does nothing.
##
## Every gun is the player's and the ammo tops itself up; the range medic
## patches the player up before they can buy the farm. The levers and racks
## are the level's stations ("range-<what>"): this hears each one go, undoes
## it so it can be pulled again, and does what it says (hands a gun over,
## turns critters out, racks the pins, starts the gallery, resets the pit).
## The targets (range_targets.gd) keep score; the county's hands it turned
## out are watched for the damage each gun does them, how long they took to
## drop, and what they get up to (cover, running for help, brawls), and the
## card (range_card.gd) shows it all for the station the player stands at.
## The games row south of the armory (range_games.gd: horseshoes, the dunk
## tank, skee-ball, knock 'em down) is played from here too. Nothing here is
## saved (the range is never saved); each game's best goes to the range's
## records and, online, its board (range_board.gd), whose top five the
## station's card shows.
extends GameFeature

const L := preload("res://src/range_layout.gd")
const Targets := preload("res://src/range_targets.gd")
const Card := preload("res://src/range_card.gd")
const Games := preload("res://src/range_games.gd")
## The station each board's game is played at.
const BOARD_OF := {
	"bowling": "bowling",
	"gallery": "gallery",
	"horseshoes": "horseshoes",
	"dunk": "dunk",
	"skeeball": "skeeball",
	"bottles": "bottles",
}
## The most critters one pen holds at once.
const PEN_LIMIT := 10
## What each gun is, said when it is taken off the wall.
const GUN_NOTES := [
	"A SWING: {dmg} A HIT, MORE SQUARE ON WHEN SPRINTING. NO AMMO. TRY THE WHUPPIN' YARD.",
	"{dmg} A SHOT, SIX IN THE WHEEL, TRUE OUT TO {range} YDS. TRY TIN CAN ALLEY.",
	"TEN PELLETS OF {pellet}. RIGHT CLICK: BOTH BARRELS. NONE PAST {range} YDS. THE PELLET PATCH.",
	"A BOLT WITH A STICK ON IT: IT DROPS AND BLOWS ON WHAT IT HITS. TRY THE POWDER PIT.",
	"{dmg} A ROUND, QUICK. HELD DOWN IT HEATS, CLIMBS, STRAYS. {range} YDS. THE RIFLE RANGE.",
	"BLADES BOUNCE OFF WALLS AND TAKE FOLKS APART. RIGHT CLICK GRINDS. TRY SPECIAL ORDERS.",
	"ENERGY BOLTS, {dmg} A HIT, THEY BURST GREEN WHERE THEY LAND. TRY SPECIAL ORDERS.",
	"HOLD FIRE TO LIGHT, LET GO TO THROW. HOLD TOO LONG AND IT GOES OFF. THE POWDER PIT.",
	"A LONG REACH AND {dmg} A HIT, MORE SQUARE ON. TRY THE WHUPPIN' YARD.",
	"{dmg} ON A DIRECT HIT AND A BLAST ALL ROUND. MIND THE BACKBLAST. TRY THE POWDER PIT.",
	"{dmg} A RIVET, RIGHT CLICK FIRES A PAIR. REACHES {range} YDS. TRY THE RIFLE RANGE.",
	"A SHORT SHOT OF STEAM, {dmg}, OUT TO {range} YDS. IT BREAKS A WIND-UP. TRY SPECIAL ORDERS.",
	"ROLLS ALONG THE FLOOR, {dmg}, AND IT BOWLS FOLKS OVER. TRY THE BOWL-O-RAMA.",
	"LOBBED, AND IT GOES UP BIG. TRY THE POWDER PIT.",
	"{dmg} OF BEEF AND A BLAST. DON'T ASK WHERE THE COWS COME FROM. TRY THE POWDER PIT.",
	"A HOSE OF MILK, {dmg} A SQUIRT. SOAKED FOLKS SLOW DOWN AND SLIP. TRY THE SOAK TANK.",
	"THE OUTLAWS' BOLT-ACTION: {dmg} A ROUND. RIGHT CLICK SCOPES IN. THE RIFLE RANGE.",
	"BELT-FED, {dmg} A ROUND. HOLD IT DOWN AND MOW. TRY THE BULLPEN.",
	"THE DEPUTIES' SIDEARM: {dmg} A SHOT, TRUE OUT TO {range} YDS. TIN CAN ALLEY.",
	"A HEAVY .357: {dmg} A SHOT, SLOW AND SURE. TIN CAN ALLEY.",
	"THE OUTLAWS' .44: {dmg} A SHOT AND A KICK LIKE A MULE. TIN CAN ALLEY.",
	"A PUMP GUN, PELLETS OF {pellet}. NONE PAST {range} YDS. THE PELLET PATCH.",
	"A DRUM OF .45, {dmg} A ROUND. HOSE THE BULLPEN.",
	"A TIN SUBGUN, {dmg} A ROUND, CHEAP AND QUICK. TRY THE BULLPEN.",
	"AN AUTOMATIC RIFLE: {dmg} A ROUND OUT TO {range} YDS. THE RIFLE RANGE.",
	"SEMI-AUTO WITH A SCOPE: {dmg} A ROUND. RIGHT CLICK SCOPES IN. THE RIFLE RANGE.",
	"A JAR OF LIGHTNING: IT BLINDS WHOEVER'S LOOKING AT IT. TRY THE BULLPEN.",
	"SMOKE: NOBODY SEES THROUGH IT, THE HANDS NEITHER. TRY THE BULLPEN.",
	"BURSTS ON WHAT IT HITS AND THE GROUND BURNS. TRY THE POWDER PIT.",
	"IT SOUNDS LIKE GUNFIRE: THE HANDS GO LOOK. TRY THE BULLPEN.",
]
## What the hands it watches are up to, worst first: [field test, words].
const DOINGS := {
	"brawl": "BRAWLING",
	"fetch": "RUNNING FOR HELP",
	"cover": "DUCKED IN COVER",
	"retreat": "FALLING BACK",
	"mad": "FIGHTIN' MAD",
	"windup": "WINDING UP",
	"stun": "KNOCKED SILLY",
	"soaked": "SOAKED",
	"idle": "NOT SEEN YOU YET",
	"hunt": "COMING FOR YOU",
}

var on := false
var targets: Targets
var games: Games
## The records on this machine (range_board.gd), read once and kept up; the
## bowling games and gallery rounds counted so far (a new one is finished).
var records := {}
var bowled := 0
var gallery_was := false
## The station the player stands at ("" for none) and since when.
var station := ""
var station_since := 0.0
## A message to show next tick (a station's own empty message would wipe it).
var pending := ""
var pending_for := 3.0
## Critters turned out: enemy -> {station, kind, hp, first, damage, by_gun,
## shots, doing}.
var watched := {}
var shots_fired := 0
var last_shot := -10.0
var damage_by_gun := {}
var hits_by_gun := {}
## The last things worth saying on a card: kills, interrupts, slips.
var kills: Array = []
var interrupts := 0
var slips := 0
var blasts := 0
var gibs := 0
var chain := 0
var best_chain := 0
var chain_until := 0.0
## The pellets of the last blast, by board; the rifle's last shot.
var pellet_blast := {}
var pellet_clock := -1.0
var reach_note := ""
var reach_until := 0.0
var cans_down := {}
var say_next := 0.0
## The PA's "range is hot" has been said this visit.
var range_hot := false
## The next tough guy and oddball their levers turn out.
var tough_next := 0
var variant_next := 0


func id() -> String:
	return "range"


func attach() -> void:
	on = game.level != null and game.level.id == L.ID
	if not on:
		return
	targets = Targets.new()
	games = Games.new()
	records = RangeBoard.read()
	_kit()
	tick_with(_tick)
	game.events.traced.connect(_traced)
	game.events.shot_fired.connect(_fired)
	game.events.exploded.connect(_exploded)
	game.events.station_done.connect(_station)
	game.events.player_hurt.connect(_hurt)
	game.events.enemy_killed.connect(_killed)


## Every gun, loaded, and as much for it as it carries.
func _kit() -> void:
	var a := game.armory
	for i in Weapons.COUNT:
		a.owned[i] = true
		a.loaded[i] = Weapons.CAPACITY[i]
		a.reserve[i] = Weapons.MAX_RESERVE[i]
	a.active = Weapons.REVOLVER
	for name: String in HUD.ITEMS:
		game.inventory[name] = 3


func _tick(dt: float) -> void:
	if Modes.is_versus(game):
		return  # a versus match on the range: no refills, no medic (src/modes/)
	game.lessons = false
	var a := game.armory
	for i in Weapons.COUNT:
		a.owned[i] = true
		if a.reserve[i] < Weapons.MAX_RESERVE[i]:
			a.reserve[i] = Weapons.MAX_RESERVE[i]
	var p := game.player
	if p.health <= 0:
		p.health = 100
	var here := L.station_at(p.x, p.y)
	if here != station:
		station = here
		station_since = game.clock
		for board: String in BOARD_OF:
			if BOARD_OF[board] == here:
				RangeBoard.want(board)
	if pending != "":
		game.message(pending, pending_for)
		pending = ""
	if not range_hot and game.clock > 1.5 and game.sound != null:
		range_hot = true
		game.sound.play_voice("range_pa_hot", .7, 0.0)
	targets.tick(game, dt)
	games.tick(game, dt)
	_finished()
	_cans()
	_watch()
	if game.finale != null and not game.finale.alive and game.clock - game.finale.died_at > 4.0:
		game.finale = null
	if chain > 0 and game.clock > chain_until:
		best_chain = maxi(best_chain, chain)
		chain = 0


## Games finished this tick: kept as the range's records and posted.
func _finished() -> void:
	var done: Array = games.finished.duplicate()
	games.finished.clear()
	var bowl := targets.bowling
	if bowl.games != bowled:
		bowled = bowl.games
		done.append(["bowling", bowl.score()])
	if gallery_was and not targets.gallery_on:
		done.append(["gallery", targets.gallery_score])
	gallery_was = targets.gallery_on
	for row: Array in done:
		var board := str(row[0])
		var score: int = row[1]
		if RangeBoard.finished(board, score):
			records[board] = score
			say("A NEW BEST AT THE %s: %d." % [str(RangeBoard.GAMES[board]), score], 2.6)


func say(text: String, length := 3.0) -> void:
	pending = text
	pending_for = length


# ------------------------------------------------------------------- events


func _fired(gun: int) -> void:
	shots_fired += 1
	last_shot = game.clock
	if station == "gallery" and targets.gallery_on:
		targets.gallery_shots += 1
	if gun == Weapons.SHOTGUN:
		pellet_blast = {}
		pellet_clock = game.clock


func _gun_damage(gun: int) -> float:
	var how: Dictionary = Weapons.FIRING[gun]
	var mode := str(how.get("fire", ""))
	if mode == "melee":
		var table: Array = Weapons.MELEE[gun]
		var swing: float = table[1 if game.sprint else 0]
		return swing
	if mode == "pellets":
		var pellet: float = how.get("pellet_damage", Weapons.SHOTGUN_DAMAGE)
		return pellet
	if gun == Weapons.RIPSAW:
		return float(Weapons.GRIND_DAMAGE)
	var damage: float = Weapons.DAMAGE.get(gun, 0)
	return damage


func _traced(end: Vector3, struck: String) -> void:
	var p := game.player
	var gun: int = game.armory.active
	var start := Vector3(p.x, p.y, p.eye)
	var damage := _gun_damage(gun)
	var hit: Dictionary = targets.trace(game, start, end, gun, damage)
	if hit.is_empty() and games.trace(game, start, end):
		return
	if hit.has("id"):
		_tally(gun, damage)
		if str(hit["station"]) == "pellets" and game.clock - pellet_clock < .05:
			var so_far: int = pellet_blast.get(hit["id"], 0)
			pellet_blast[hit["id"]] = so_far + 1
	elif struck == "thing":
		# A can off its post: the nearest can to where the shot ended.
		for c: Array in L.CANS:
			var cx: float = c[1]
			var cy: float = c[2]
			if Vector2(cx - end.x, cy - end.y).length() < .5:
				var yards := roundi(Vector2(cx - p.x, cy - p.y).length())
				cans_down[str(c[0])] = game.clock
				_note_reach("CAN AT %d YDS, %s" % [yards, _gun_name(gun)])
	elif struck == "air" and station in ["cans", "rifle", "pellets", "special"]:
		var how: Dictionary = Weapons.FIRING[gun]
		if how.has("range"):
			var reach: float = how["range"]
			_note_reach("FELL SHORT: %s REACHES %d YDS" % [_gun_name(gun), roundi(reach)])


func _note_reach(text: String) -> void:
	reach_note = text
	reach_until = game.clock + 4.0


func _tally(gun: int, damage: float) -> void:
	var name := _gun_name(gun)
	var damage_so_far: float = damage_by_gun.get(name, 0.0)
	damage_by_gun[name] = damage_so_far + maxf(0.0, damage)
	var hits_so_far: int = hits_by_gun.get(name, 0)
	hits_by_gun[name] = hits_so_far + 1


func _exploded(x: float, y: float, _z: float, _energy: bool) -> void:
	targets.blast(game, x, y)
	if L.station_at(x, y) == "pit" or Rect2(71, 10, 28, 37).has_point(Vector2(x, y)):
		blasts += 1
		chain = chain + 1 if game.clock < chain_until else 1
		chain_until = game.clock + .9
		if chain >= 3 and game.barks.enabled:
			game.callout = "CHAIN OF %d!" % chain
			game.callout_until = game.clock + 1.2


func _hurt(_amount: float, _cause: String) -> void:
	if Modes.is_versus(game):
		return
	var p := game.player
	if p.health < 30:
		p.health = 100
		game.hurt_flash = 0.0
		say("THE RANGE MEDIC PATCHED YA UP. MIND THE BULLPEN.", 2.6)
		if game.sound != null:
			game.sound.play_voice("range_pa_medic", .7, 0.0)


func _killed(enemy: Enemy) -> void:
	var found: Variant = watched.get(enemy)
	if found == null:
		return
	var w: Dictionary = found
	if enemy.explosive:
		gibs += 1
	var first: float = w["first"]
	var took: float = game.clock - first if first >= 0.0 else 0.0
	var best := ""
	var most := 0.0
	var by_gun: Dictionary = w["by_gun"]
	for gun: String in by_gun:
		var dealt: float = by_gun[gun]
		if dealt > most:
			most = dealt
			best = gun
	var shots_then: int = w["shots"]
	var line := (
		"%s DOWN IN %.1f S, %d SHOTS%s"
		% [
			str(L.NAMES.get(w["kind"], str(w["kind"]).to_upper())),
			took,
			shots_fired - shots_then,
			(", " + best) if best != "" else ""
		]
	)
	kills.push_front(line)
	if kills.size() > 3:
		kills.pop_back()
	if station in ["bullpen", "corral", "soak", "special", "pit"]:
		say(line, 2.8)


# ------------------------------------------------------------------ stations


func _station(station_id: String) -> void:
	if not station_id.begins_with("range-"):
		return
	game.stations_done.erase(station_id)
	var what := station_id.substr(6)
	if what.begins_with("rack-"):
		_take(int(what.substr(5)))
	elif what.begins_with("pen-"):
		_pen(what.substr(4))
	elif what.begins_with("boss-"):
		_boss(what.substr(5))
	elif what == "cans":
		for c: Array in L.CANS:
			game.scenery_spent.erase(str(c[0]))
		cans_down.clear()
		say("CANS BACK ON THEIR POSTS.", 1.6)
	elif what == "pins":
		targets.rack()
		say("PINS RACKED. ROLL THE BOWLING BALL [-] DOWN THE LANE.", 2.6)
	elif what == "gallery":
		targets.start_gallery(game)
		say("GALLERY OPEN: 30 SECONDS. ROOSTERS 1, DUCKS 2.", 2.2)
	elif what == "soak":
		_clear("soak")
		for spot: Vector2 in L.SOAK_DOORS:
			_spawn("billy", spot, "soak", true)
		say("THREE HANDS IN THE TANK. TEAT GUN [MOUSE WHEEL] AND SOAK 'EM.", 3.0)
	elif what == "alien_one":
		_clear("special")
		_spawn("alien", L.ALIEN_DOOR, "special", true)
		say("THE GREY'S AWAKE. HIT IT WITH THE COPPERHEAD AS IT WINDS UP.", 3.2)
	elif what == "fodder":
		_clear("pit")
		for i in L.FODDER_DOORS.size():
			var door: Vector2 = L.FODDER_DOORS[i]
			_spawn(str(L.FODDER_KINDS[i]), door, "pit", true)
		say("FODDER IN THE PIT. LIGHT A STICK [8].", 2.4)
	elif what == "pitch":
		_told(games.pitch(game, game.player))
	elif what == "dunk":
		games.start_dunk(game)
	elif what == "skee":
		var rolled := games.skee.roll(game.player, game.rng)
		_told(rolled)
		if rolled == "":
			game.sound.play("football_throw", .5)
	elif what == "bottles":
		_told(games.throw_ball(game, game.player))
	elif what == "reset-pit":
		_clear("pit")
		for d: Vector2 in L.DRUMS:
			game.drums[d] = 18
		blasts = 0
		gibs = 0
		best_chain = 0
		targets.reset_targets()
		say("PIT RESET: DRUMS BACK, TARGETS UP, FODDER GONE.", 2.4)


func _told(words: String) -> void:
	if words != "":
		say(words, 1.6)


func _take(i: int) -> void:
	if i < 0 or i >= Weapons.COUNT:
		return
	var a := game.armory
	if a.active != i:
		a.select(i, game)
	a.loaded[i] = Weapons.CAPACITY[i]
	var how: Dictionary = Weapons.FIRING[i]
	var note := str(GUN_NOTES[i]) if i < GUN_NOTES.size() else ""
	note = note.replace("{dmg}", str(roundi(_gun_damage(i))))
	var reach: float = how.get("range", 0.0)
	note = note.replace("{range}", str(roundi(reach)))
	var pellet: int = how.get("pellet_damage", Weapons.SHOTGUN_DAMAGE)
	note = note.replace("{pellet}", str(pellet))
	say(str(Weapons.LABELS[i]).get_slice(" [", 0) + ". " + note, 5.0)


## Can this kind be drawn here? A browser build fetches a chapter's own
## critters after it starts; a variant or tough guy wears its base kind's.
func _ready_kind(kind: String) -> bool:
	var kinds := [kind]
	var def: Dictionary = Enemy.DEFS.get(kind, {})
	for key: String in ["art", "brain"]:
		var base := str(def.get(key, ""))
		if base != "":
			kinds.append(base)
			var base_def: Dictionary = Enemy.DEFS.get(base, {})
			kinds.append(str(base_def.get("brain", "")))
	for level_id: String in Assets.CHAPTER_KINDS:
		for k: String in kinds:
			if k in Assets.CHAPTER_KINDS[level_id] and not game.art.chapter_ready(level_id):
				return false
	return true


func _pen(kind: String) -> void:
	if kind == "clear":
		_clear("bullpen")
		say("PEN CLEARED.", 1.4)
		return
	if _count("bullpen") >= PEN_LIMIT:
		say("THE PEN'S FULL. CLEAR IT FIRST.", 2.0)
		game.sound.play("empty")
		return
	if kind == "squad":
		# Two come straight for you; three loaf at the back for the hurt to fetch.
		var squad := [
			["billy", 0, true],
			["coot", 1, true],
			["billy", 2, false],
			["coot", 3, false],
			["clone", 1, false]
		]
		for row: Array in squad:
			var at: int = row[1]
			var door: Vector2 = L.PEN_DOORS[at]
			var awake: bool = row[2]
			_spawn(str(row[0]), door + Vector2(-.6 * at, .4), "bullpen", awake)
		say("A SQUAD. WATCH THE HURT ONES RUN FOR THE LOAFERS.", 3.0)
		return
	if kind == "tough":
		kind = str(L.TOUGH_KINDS[tough_next % L.TOUGH_KINDS.size()])
		tough_next += 1
	elif kind == "variant":
		kind = str(L.VARIANT_KINDS[variant_next % L.VARIANT_KINDS.size()])
		variant_next += 1
	if not _ready_kind(kind):
		say("THAT CRITTER'S STILL ON THE TRUCK. TRY AGAIN IN A MINUTE.", 2.5)
		return
	var door2: Vector2 = L.PEN_DOORS[_count("bullpen") % L.PEN_DOORS.size()]
	var count := 2 if kind in ["skeeter", "crawler"] else 1
	for k in count:
		_spawn(kind, door2 + Vector2(0, k * .8), "bullpen", true)
	say("HERE COMES A " + str(L.NAMES.get(kind, kind.to_upper())) + ".", 1.8)


func _boss(kind: String) -> void:
	_clear("corral")
	game.hazards.clear()
	if kind == "clear":
		say("CORRAL CLEARED.", 1.4)
		return
	if not _ready_kind(kind):
		say("THAT ONE'S STILL ON THE TRUCK. TRY AGAIN IN A MINUTE.", 2.5)
		return
	# The Swamp King's airboat comes in on the pond; the rest by the gate.
	var door := L.POND_DOOR if kind == "swamp_king" else L.BOSS_DOOR
	var foe: Enemy = _spawn(kind, door, "corral", true)
	if foe != null:
		game.finale = foe
		var where := " IS ON THE POND." if kind == "swamp_king" else " IS LOOSE IN THE CORRAL."
		say(str(L.NAMES.get(kind, kind)) + where, 2.4)


func _spawn(kind: String, at: Vector2, home: String, awake: bool) -> Enemy:
	if not Enemy.KINDS.has(kind):
		return null
	var p := game.player
	var foe := Enemy.new(kind, at.x, at.y, atan2(p.y - at.y, p.x - at.x))
	foe.flank = .42 if game.enemies.size() % 2 else -.42
	game.enemies.append(foe)
	game.enemy_ids.append("range-%s-%d" % [kind, game.enemies.size()])
	game.total_kills += 1
	watched[foe] = {
		"station": home,
		"kind": kind,
		"hp": foe.hp,
		"first": -1.0,
		"by_gun": {},
		"shots": shots_fired,
		"doing": "",
		"stun": 0.0,
		"guard": 0.0,
	}
	if awake:
		foe.wake(game, p.x, p.y)
	game.burst(at.x, at.y, .3, "dust", 10, 1.4)
	game.sound_at("range_pen_gate", at.x, at.y, .7)
	return foe


func _count(home: String) -> int:
	var n := 0
	for foe: Enemy in watched:
		if str(watched[foe]["station"]) == home and foe.alive:
			n += 1
	return n


## Take a station's critters away, dead or alive.
func _clear(home: String) -> void:
	var keep_e: Array = []
	var keep_id: Array = []
	var zone: Array = L.STATIONS[home]["lane"] if L.STATIONS.has(home) else []
	for i in game.enemies.size():
		var foe: Enemy = game.enemies[i]
		var w: Variant = watched.get(foe)
		# A boss's backup and Maw's younguns are nobody's: the corral's are its.
		var stray := false
		if w == null and home == "corral" and not zone.is_empty():
			var x0: float = zone[0]
			var y0: float = zone[1]
			var x1: float = zone[2]
			var y1: float = zone[3]
			stray = foe.x >= x0 and foe.x < x1 + 1.0 and foe.y >= y0 and foe.y < y1 + 1.0
		if (w != null and str(w["station"]) == home) or stray:
			watched.erase(foe)
			if game.finale == foe:
				game.finale = null
			continue
		keep_e.append(foe)
		keep_id.append(game.enemy_ids[i] if i < game.enemy_ids.size() else "range-%d" % i)
	game.enemies = keep_e
	game.enemy_ids = keep_id
	game.shots = game.shots.filter(func(s: GameState.Shot) -> bool: return not s.enemy)


# ------------------------------------------------------------------ watching


## Stand the cans back up a while after they were shot off.
func _cans() -> void:
	for c: Array in L.CANS:
		var can_id := str(c[0])
		if game.scenery_spent.has(can_id):
			if not cans_down.has(can_id):
				cans_down[can_id] = game.clock
			else:
				var down_at: float = cans_down[can_id]
				if game.clock - down_at > 4.0:
					game.scenery_spent.erase(can_id)
					cans_down.erase(can_id)


func _watch() -> void:
	for foe: Enemy in watched:
		var w: Dictionary = watched[foe]
		var hp_then: float = w["hp"]
		var lost := hp_then - foe.hp
		if lost > 0.0:
			var first: float = w["first"]
			if first < 0.0:
				w["first"] = game.clock
			# Hurt by the player when they fired just now; else by one of its own.
			var by := (
				_gun_name(game.armory.active) if game.clock - last_shot < 2.6 else "FRIENDLY FIRE"
			)
			var by_gun: Dictionary = w["by_gun"]
			var dealt: float = by_gun.get(by, 0.0)
			by_gun[by] = dealt + lost
			if by != "FRIENDLY FIRE":
				var dealt_all: float = damage_by_gun.get(by, 0.0)
				damage_by_gun[by] = dealt_all + lost
			w["hp"] = foe.hp
		if not foe.alive:
			continue
		var guard_then: float = w["guard"]
		if foe.pressure_guard > 1.6 and guard_then <= 1.6:
			interrupts += 1
			say("WIND-UP BROKEN! THE COPPERHEAD STAGGERED IT.", 2.0)
		w["guard"] = foe.pressure_guard
		var stun_then: float = w["stun"]
		if foe.stun >= .55 and stun_then < .2 and foe.soak > .0:
			slips += 1
			if station == "soak":
				say("DOWN IN THE MILK!", 1.4)
		w["stun"] = foe.stun
		var doing := doing_of(foe)
		if doing != str(w["doing"]):
			w["doing"] = doing
			_announce(foe, doing)


static func doing_of(foe: Enemy) -> String:
	if foe.grudge != null:
		return "brawl"
	if foe.fetching != null:
		return "fetch"
	if foe.cover != null:
		return "cover"
	if foe.retreat != null:
		return "retreat"
	if foe.enraged:
		return "mad"
	if foe.windup > 0.0:
		return "windup"
	if foe.stun > .3:
		return "stun"
	if foe.soak > .3:
		return "soaked"
	if not foe.alerted:
		return "idle"
	return "hunt"


func doing_words(foe: Enemy) -> String:
	return str(DOINGS.get(doing_of(foe), ""))


## Say what a hand has taken to doing, when it is something worth learning.
func _announce(foe: Enemy, doing: String) -> void:
	if game.clock < say_next or not station in ["bullpen", "corral", "soak", "special"]:
		return
	var name := str(L.NAMES.get(foe.kind, foe.kind.to_upper()))
	var line := ""
	if doing == "brawl" and foe.grudge != null:
		line = (
			"FRIENDLY FIRE! THE %s TURNS ON THE %s."
			% [name, str(L.NAMES.get(foe.grudge.kind, foe.grudge.kind.to_upper()))]
		)
	elif doing == "fetch":
		line = "THE %s IS HURT AND RUNS FOR HELP." % name
	elif doing == "cover":
		line = "THE %s DUCKS OUT OF SIGHT. FLANK IT." % name
	if line != "":
		say(line, 2.4)
		say_next = game.clock + 2.0


func _gun_name(gun: int) -> String:
	return str(Weapons.LABELS[gun]).get_slice(" [", 0)


# ------------------------------------------------------------------ the view


func sprites() -> Array:
	if not on:
		return []
	var out := targets.sprites(game)
	out.append_array(games.sprites(game))
	return out


## The station's card where the HUD's layout has room (range_card.gd).
func hud_flow(layout: HudLayout) -> void:
	if Modes.is_versus(game) or not on or game.map or game.player.health <= 0:
		return
	if station != "" and L.station_at(game.player.x, game.player.y) == station:
		Card.claim(layout, self)


func draw_view(c: Canvas) -> void:
	if Modes.is_versus(game):
		return
	if on:
		var here := L.station_at(game.player.x, game.player.y)
		if here != station:
			station = here
			station_since = game.clock
	if on and station != "" and not game.map and game.player.health > 0:
		Card.draw(c, self)
