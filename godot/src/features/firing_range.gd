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
## Nothing here is saved: the range is never saved.
extends GameFeature

const L := preload("res://src/range_layout.gd")
const Targets := preload("res://src/range_targets.gd")
const Card := preload("res://src/range_card.gd")
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
	_kit()
	game.ticked.connect(_tick)
	game.traced.connect(_traced)
	game.shot_fired.connect(_fired)
	game.exploded.connect(_exploded)
	game.station_done.connect(_station)
	game.player_hurt.connect(_hurt)
	game.enemy_killed.connect(_killed)


## Every gun, loaded, and as much for it as it carries.
func _kit() -> void:
	var a = game.armory
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
	var a = game.armory
	for i in Weapons.COUNT:
		a.owned[i] = true
		if a.reserve[i] < Weapons.MAX_RESERVE[i]:
			a.reserve[i] = Weapons.MAX_RESERVE[i]
	var p = game.player
	if p.health <= 0:
		p.health = 100
	var here := L.station_at(p.x, p.y)
	if here != station:
		station = here
		station_since = game.clock
	if pending != "":
		game.message(pending, pending_for)
		pending = ""
	if not range_hot and game.clock > 1.5 and game.sound != null:
		range_hot = true
		game.sound.play_voice("range_pa_hot", .7, 0.0)
	targets.tick(game, dt)
	_cans()
	_watch()
	if game.finale != null and not game.finale.alive and game.clock - game.finale.died_at > 4.0:
		game.finale = null
	if chain > 0 and game.clock > chain_until:
		best_chain = maxi(best_chain, chain)
		chain = 0


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
	var mode := String(how.get("fire", ""))
	if mode == "melee":
		var table: Array = Weapons.MELEE[gun]
		return float(table[1 if game.sprint else 0])
	if mode == "pellets":
		return float(how.get("pellet_damage", Weapons.SHOTGUN_DAMAGE))
	if gun == Weapons.RIPSAW:
		return float(Weapons.GRIND_DAMAGE)
	return float(Weapons.DAMAGE.get(gun, 0))


func _traced(end: Vector3, struck: String) -> void:
	var p = game.player
	var gun: int = game.armory.active
	var start := Vector3(p.x, p.y, p.eye)
	var damage := _gun_damage(gun)
	var hit: Dictionary = targets.trace(game, start, end, gun, damage)
	if hit.has("id"):
		_tally(gun, damage)
		if String(hit["station"]) == "pellets" and game.clock - pellet_clock < .05:
			pellet_blast[hit["id"]] = int(pellet_blast.get(hit["id"], 0)) + 1
	elif struck == "thing":
		# A can off its post: the nearest can to where the shot ended.
		for c: Array in L.CANS:
			if Vector2(float(c[1]) - end.x, float(c[2]) - end.y).length() < .5:
				var yards := roundi(Vector2(float(c[1]) - p.x, float(c[2]) - p.y).length())
				cans_down[String(c[0])] = game.clock
				_note_reach("CAN AT %d YDS, %s" % [yards, _gun_name(gun)])
	elif struck == "air" and station in ["cans", "rifle", "pellets", "special"]:
		var how: Dictionary = Weapons.FIRING[gun]
		if how.has("range"):
			_note_reach(
				"FELL SHORT: %s REACHES %d YDS" % [_gun_name(gun), roundi(float(how["range"]))]
			)


func _note_reach(text: String) -> void:
	reach_note = text
	reach_until = game.clock + 4.0


func _tally(gun: int, damage: float) -> void:
	var name := _gun_name(gun)
	damage_by_gun[name] = float(damage_by_gun.get(name, 0.0)) + maxf(0.0, damage)
	hits_by_gun[name] = int(hits_by_gun.get(name, 0)) + 1


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
	var p = game.player
	if p.health < 30:
		p.health = 100
		game.hurt_flash = 0.0
		say("THE RANGE MEDIC PATCHED YA UP. MIND THE BULLPEN.", 2.6)
		if game.sound != null:
			game.sound.play_voice("range_pa_medic", .7, 0.0)


func _killed(enemy: Enemy) -> void:
	var w = watched.get(enemy)
	if w == null:
		return
	if enemy.explosive:
		gibs += 1
	var took: float = game.clock - float(w["first"]) if float(w["first"]) >= 0.0 else 0.0
	var best := ""
	var most := 0.0
	for gun: String in w["by_gun"]:
		if float(w["by_gun"][gun]) > most:
			most = float(w["by_gun"][gun])
			best = gun
	var line := (
		"%s DOWN IN %.1f S, %d SHOTS%s"
		% [
			String(L.NAMES.get(w["kind"], String(w["kind"]).to_upper())),
			took,
			shots_fired - int(w["shots"]),
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
			game.scenery_spent.erase(String(c[0]))
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
			_spawn(String(L.FODDER_KINDS[i]), L.FODDER_DOORS[i], "pit", true)
		say("FODDER IN THE PIT. LIGHT A STICK [8].", 2.4)
	elif what == "reset-pit":
		_clear("pit")
		for d: Vector2 in L.DRUMS:
			game.drums[d] = 18
		blasts = 0
		gibs = 0
		best_chain = 0
		targets.reset_targets()
		say("PIT RESET: DRUMS BACK, TARGETS UP, FODDER GONE.", 2.4)


func _take(i: int) -> void:
	if i < 0 or i >= Weapons.COUNT:
		return
	var a = game.armory
	if a.active != i:
		a.select(i, game)
	a.loaded[i] = Weapons.CAPACITY[i]
	var how: Dictionary = Weapons.FIRING[i]
	var note := String(GUN_NOTES[i]) if i < GUN_NOTES.size() else ""
	note = note.replace("{dmg}", str(roundi(_gun_damage(i))))
	note = note.replace("{range}", str(roundi(float(how.get("range", 0.0)))))
	note = note.replace("{pellet}", str(int(how.get("pellet_damage", Weapons.SHOTGUN_DAMAGE))))
	say(String(Weapons.LABELS[i]).get_slice(" [", 0) + ". " + note, 5.0)


## Can this kind be drawn here? A browser build fetches a chapter's own
## critters after it starts; a variant or tough guy wears its base kind's.
func _ready_kind(kind: String) -> bool:
	var kinds := [kind]
	var def: Dictionary = Enemy.DEFS.get(kind, {})
	for key in ["art", "brain"]:
		var base := String(def.get(key, ""))
		if base != "":
			kinds.append(base)
			kinds.append(String(Enemy.DEFS.get(base, {}).get("brain", "")))
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
			var door: Vector2 = L.PEN_DOORS[int(row[1])]
			_spawn(String(row[0]), door + Vector2(-.6 * int(row[1]), .4), "bullpen", bool(row[2]))
		say("A SQUAD. WATCH THE HURT ONES RUN FOR THE LOAFERS.", 3.0)
		return
	if kind == "tough":
		kind = String(L.TOUGH_KINDS[tough_next % L.TOUGH_KINDS.size()])
		tough_next += 1
	elif kind == "variant":
		kind = String(L.VARIANT_KINDS[variant_next % L.VARIANT_KINDS.size()])
		variant_next += 1
	if not _ready_kind(kind):
		say("THAT CRITTER'S STILL ON THE TRUCK. TRY AGAIN IN A MINUTE.", 2.5)
		return
	var door2: Vector2 = L.PEN_DOORS[_count("bullpen") % L.PEN_DOORS.size()]
	var count := 2 if kind in ["skeeter", "crawler"] else 1
	for k in count:
		_spawn(kind, door2 + Vector2(0, k * .8), "bullpen", true)
	say("HERE COMES A " + String(L.NAMES.get(kind, kind.to_upper())) + ".", 1.8)


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
		say(String(L.NAMES.get(kind, kind)) + where, 2.4)


func _spawn(kind: String, at: Vector2, home: String, awake: bool) -> Enemy:
	if not Enemy.KINDS.has(kind):
		return null
	var p = game.player
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
		if String(watched[foe]["station"]) == home and foe.alive:
			n += 1
	return n


## Take a station's critters away, dead or alive.
func _clear(home: String) -> void:
	var keep_e: Array = []
	var keep_id: Array = []
	var zone: Array = L.STATIONS[home]["lane"] if L.STATIONS.has(home) else []
	for i in game.enemies.size():
		var foe: Enemy = game.enemies[i]
		var w = watched.get(foe)
		# A boss's backup and Maw's younguns are nobody's: the corral's are its.
		var stray := (
			w == null
			and home == "corral"
			and not zone.is_empty()
			and foe.x >= float(zone[0])
			and foe.x < float(zone[2]) + 1.0
			and foe.y >= float(zone[1])
			and foe.y < float(zone[3]) + 1.0
		)
		if (w != null and String(w["station"]) == home) or stray:
			watched.erase(foe)
			if game.finale == foe:
				game.finale = null
			continue
		keep_e.append(foe)
		keep_id.append(game.enemy_ids[i] if i < game.enemy_ids.size() else "range-%d" % i)
	game.enemies = keep_e
	game.enemy_ids = keep_id
	game.shots = game.shots.filter(func(s) -> bool: return not s.enemy)


# ------------------------------------------------------------------ watching


## Stand the cans back up a while after they were shot off.
func _cans() -> void:
	for c: Array in L.CANS:
		var can_id := String(c[0])
		if game.scenery_spent.has(can_id):
			if not cans_down.has(can_id):
				cans_down[can_id] = game.clock
			elif game.clock - float(cans_down[can_id]) > 4.0:
				game.scenery_spent.erase(can_id)
				cans_down.erase(can_id)


func _watch() -> void:
	for foe: Enemy in watched:
		var w: Dictionary = watched[foe]
		var lost := float(w["hp"]) - foe.hp
		if lost > 0.0:
			if float(w["first"]) < 0.0:
				w["first"] = game.clock
			# Hurt by the player when they fired just now; else by one of its own.
			var by := (
				_gun_name(game.armory.active) if game.clock - last_shot < 2.6 else "FRIENDLY FIRE"
			)
			w["by_gun"][by] = float(w["by_gun"].get(by, 0.0)) + lost
			if by != "FRIENDLY FIRE":
				damage_by_gun[by] = float(damage_by_gun.get(by, 0.0)) + lost
			w["hp"] = foe.hp
		if not foe.alive:
			continue
		if foe.pressure_guard > 1.6 and float(w["guard"]) <= 1.6:
			interrupts += 1
			say("WIND-UP BROKEN! THE COPPERHEAD STAGGERED IT.", 2.0)
		w["guard"] = foe.pressure_guard
		if foe.stun >= .55 and float(w["stun"]) < .2 and foe.soak > .0:
			slips += 1
			if station == "soak":
				say("DOWN IN THE MILK!", 1.4)
		w["stun"] = foe.stun
		var doing := doing_of(foe)
		if doing != String(w["doing"]):
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
	return String(DOINGS.get(doing_of(foe), ""))


## Say what a hand has taken to doing, when it is something worth learning.
func _announce(foe: Enemy, doing: String) -> void:
	if game.clock < say_next or not station in ["bullpen", "corral", "soak", "special"]:
		return
	var name := String(L.NAMES.get(foe.kind, foe.kind.to_upper()))
	var line := ""
	if doing == "brawl" and foe.grudge != null:
		line = (
			"FRIENDLY FIRE! THE %s TURNS ON THE %s."
			% [name, String(L.NAMES.get(foe.grudge.kind, foe.grudge.kind.to_upper()))]
		)
	elif doing == "fetch":
		line = "THE %s IS HURT AND RUNS FOR HELP." % name
	elif doing == "cover":
		line = "THE %s DUCKS OUT OF SIGHT. FLANK IT." % name
	if line != "":
		say(line, 2.4)
		say_next = game.clock + 2.0


func _gun_name(gun: int) -> String:
	return String(Weapons.LABELS[gun]).get_slice(" [", 0)


# ------------------------------------------------------------------ the view


func sprites() -> Array:
	return targets.sprites(game) if on else []


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
