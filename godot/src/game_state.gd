## The game's state: constants, the small classes it is built from, and every
## field. game.gd is a chain of layers, each extending the one before:
## GameState -> GameWorld -> GameCombat -> GameView -> Game. A layer only
## calls functions of its own or of the layers below it.
class_name GameState
extends RefCounted

const VIEW := 156
const WIDTH := 320
const HEIGHT := 200
const FOCAL := 230.0
const HUB_WIDTH := 50.0
const PLAYER_RADIUS := .19
const HUB_BOARD := Vector2(30.36, 44.13)
const GALLERY_STAND := Vector2(25.96, 33.42)
const GALLERY_TARGETS := [
	Vector3(29.54, 32.99, .68),
	Vector3(29.54, 33.56, 1.14),
	Vector3(29.54, 33.79, .65),
	Vector3(29.54, 33.15, 1.32)
]

const PROP_HEIGHTS := {
	"barrel": 1.04,
	"hay": .91,
	"pump": 1.43,
	"pump_b": 1.43,
	"sink": .89,
	"crate": .75,
	"jukebox": 1.45,
	"lamp": .24,
	"tree": 3.65,
	"tree_b": 3.65,
	"utilitypole": 3.85,
	"pickup_truck": 1.31,
	"pickup_truck_b": 1.20,
	"roadsign": 1.67,
	"bleacher_sign": 1.58,
	"mailbox": 1.18,
	"tire": .40,
	"windmill": 4.65,
	"silo": 3.78,
	"reeds": .58,
	"water_tower": 5.1,
}

const PICKUP_NAMES := {
	"key_brass": "BRASS BARN KEY",
	"key_steel": "STEEL PASTURE KEY",
	"bullets": ".38 ROUNDS",
	"shells": "BUCKSHOT",
	"dynamite": "DYNAMITE STICKS",
	"rinds": "PORK RINDS",
	"moonshine": "MOONSHINE",
	"beer": "BEER",
	"rifle_ammo": "RIFLE CARTRIDGES",
	"saw_ammo": "SAW BLADES",
	"arm_ammo": "ALIEN CELLS",
	"rocket_ammo": "BOTTLE ROCKETS",
	"rivet_ammo": "MILL RIVETS",
	"pressure_ammo": "SEALED PRESSURE CHARGES",
	"pa_patch": "PA PATCH LEAD",
	"whiskey": "WHISKEY",
	"cowpie": "COW PIE",
	"milk_ammo": "FRESH MILK",
	"bowling_ammo": "BOWLING BALLS",
	"keg_ammo": "POWDER KEGS",
	"cow_ammo": "SPARE COWS",
}

const ALIAS := {"riveter": "bowling_ball", "pressure_gun": "cow_launcher"}
const TASK_ITEMS := ["pa_patch"]

const AMMO := {
	"bullets": [Weapons.REVOLVER, 11],
	"shells": [Weapons.SHOTGUN, 10],
	"dynamite": [Weapons.CROSSBOW, 6],
	"rifle_ammo": [Weapons.RIFLE, 24],
	"saw_ammo": [Weapons.RIPSAW, 5],
	"arm_ammo": [Weapons.ARMGUN, 9],
	"rocket_ammo": [Weapons.ROCKET, 4],
	"rivet_ammo": [Weapons.BOWLING, 2],
	"pressure_ammo": [Weapons.COW, 2],
	"milk_ammo": [Weapons.TEAT, 40],
	"bowling_ammo": [Weapons.BOWLING, 2],
	"keg_ammo": [Weapons.KEG, 1],
	"cow_ammo": [Weapons.COW, 1],
}

const HUB_DISPATCH := [
	[
		"MISSING HOG",
		"COUNTY DISPATCH / MISSING HOG. LAST SEEN NEAR STANKY'S.",
		"RADIO: LOOK FOR THE HOG."
	],
	["HOG HOME", "HOG HOME. THE FAIR STILL HAS BESSIE'S PRIZE TAG.", "RADIO: THE HOG IS HOME."],
	[
		"BLUE TRUNK",
		"FAIR CLOSED. BLUE TRUNK SHIPPED TO BLACKWATER.",
		"RADIO: CHECK THE BLUE TRUNK."
	],
	[
		"LAST LOAD",
		"MILL QUIET. THE LAST LOAD WENT TO STILLWATER CUT.",
		"RADIO: KEEP THE LAST LOAD."
	],
	[
		"GATOR BAYOU",
		"STILLWATER QUIET. THE JUG MONEY WENT DOWN THE BAYOU PAST THE COUNTY LINE.",
		"RADIO: CHECK THE BAYOU."
	],
	[
		"RACE NIGHT",
		"BAYOU QUIET. THE JUG MONEY RIDES ON TONIGHT'S RACE AT BUZZARD BEND.",
		"RADIO: CHECK THE SPEEDWAY."
	],
	[
		"ALL CLEAR",
		"BESSIE'S TAG IS BACK. MUNDELL STILL OWES FOR THE JUGS.",
		"RADIO: THE TAG IS HOME."
	],
	[
		"SKY CLEAR",
		"THE SHIP CAME DOWN IN PIECES OVER THE COUNTY. MAW'S DONE.",
		"RADIO: NOTHING UP THERE BUT STARS."
	],
]

## scenery.REACTIONS: kind -> [cue, particle, count]
const REACTIONS := {
	"bottles": ["glass_break", "glass", 8],
	"cans": ["scenery_cans", "spark", 5],
	"prize": ["scenery_prize", "dust", 7],
	"scrap": ["scenery_scrap", "dust", 9],
	"pipe": ["scenery_pipe", "splash", 8],
	"belt": ["scenery_belt", "spark", 6],
	"tv": ["tv_pop", "spark", 9],
	"toilet": ["toilet_burst", "splash", 14],
	"vending": ["vending_clunk", "dust", 8],
	"window": ["window_smash", "glass", 14],
	"cancan": ["can_kick", "spark", 5],
	"jukebox": ["jukebox_hit", "spark", 7],
}

const WASH := {
	"hickston": [255, 226, 190, .10],
	"hub": [255, 226, 190, .10],
	"fair": [255, 200, 230, .12],
	"sawmill": [255, 214, 160, .13],
	"quarry": [178, 214, 255, .12],
	"bayou": [236, 196, 150, .13],
	"speedway": [255, 206, 168, .12],
	"mothership": [200, 255, 220, .12],
}
const BAYER := [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]

const NO_MARK_SURFACE := ["BACKBLAST", "LIT DYNAMITE", "STEAM", "CHALK"]

# ------------------------------------------------------------------ helpers


## Python's round(): a value exactly halfway goes to the even neighbour, where
## GDScript's round() goes away from zero (22.5 -> 22, not 23).
static func round_even(value: float) -> float:
	var low := floorf(value)
	var rest := value - low
	if rest > 0.5:
		return low + 1.0
	if rest < 0.5:
		return low
	return low if fmod(low, 2.0) == 0.0 else low + 1.0


## Deterministic, serialisable RNG (Python's Mersenne stream cannot be matched
## bit-for-bit; only its determinism is preserved). The state is 63 bits, so the
## top 53 of them (>> 10) give a float in [0, 1).
class Rng:
	var state := 0

	func _init(seed_value := 1997) -> void:
		state = ((seed_value + 1) * 6364136223846793005 + 1442695040888963407) & 0x7FFFFFFFFFFFFFFF

	func next() -> float:
		state = (state * 6364136223846793005 + 1442695040888963407) & 0x7FFFFFFFFFFFFFFF
		return float(state >> 10) / 9007199254740992.0

	func random() -> float:
		return next()

	func uniform(a: float, b: float) -> float:
		return a + (b - a) * next()

	func randf_range(a: float, b: float) -> float:
		return a + (b - a) * next()

	func choice(values: Array):
		return values[clampi(int(next() * values.size()), 0, values.size() - 1)]

	func get_state() -> int:
		return state

	func set_state(value: int) -> void:
		state = value


class Shot:
	var x := 0.0
	var y := 0.0
	var z := 0.0
	var vx := 0.0
	var vy := 0.0
	var vz := 0.0
	var kind := ""
	var life := 0.0
	var enemy := false
	var damage := 0
	var bounces := 0
	var travelled := 0.0
	var resting := false
	## Who threw it (an enemy's instance id; 0: the player or not known).
	var owner := 0
	## Which player threw it (their slot), when a player did.
	var slot := 0
	## Its stable id (game.take_uid(), named as the tick it was thrown ends).
	var uid := 0

	func _init(
		px := 0.0,
		py := 0.0,
		pz := 0.0,
		dx := 0.0,
		dy := 0.0,
		dz := 0.0,
		k := "",
		l := 0.0,
		e := false,
		dmg := 0,
		b := 0
	) -> void:
		x = px
		y = py
		z = pz
		vx = dx
		vy = dy
		vz = dz
		kind = k
		life = l
		enemy = e
		damage = dmg
		bounces = b


class Speck:
	var x := 0.0
	var y := 0.0
	var z := 0.0
	var vx := 0.0
	var vy := 0.0
	var vz := 0.0
	var life := 0.0
	var kind := ""

	func _init(
		px := 0.0, py := 0.0, pz := 0.0, dx := 0.0, dy := 0.0, dz := 0.0, l := 0.0, k := ""
	) -> void:
		x = px
		y = py
		z = pz
		vx = dx
		vy = dy
		vz = dz
		life = l
		kind = k


class Blast:
	var x := 0.0
	var y := 0.0
	var z := 0.0
	var age := 0.0
	var kind := "fire"

	func _init(px := 0.0, py := 0.0, pz := 0.0, k := "fire") -> void:
		x = px
		y = py
		z = pz
		kind = k


class Hazard:
	var kind := ""
	var x := 0.0
	var y := 0.0
	var radius := 0.0
	var warning := 0.0
	var life := 0.0
	var damage := 0
	var age := 0.0
	var next_hit := 0.0

	func _init(k := "", px := 0.0, py := 0.0, r := 0.0, w := 0.0, l := 0.0, dmg := 0) -> void:
		kind = k
		x = px
		y = py
		radius = r
		warning = w
		life = l
		damage = dmg


## Port of rampage2.Barks: one-liners with per-category cooldowns.
class Barks:
	const LINES := {
		"kill":
		[
			"THAT'S ONE LESS VARMINT.",
			"YEE-HAW!",
			"BACK TO THE DIRT, SON.",
			"DON'T MESS WITH THE LEGS.",
			"SHOULD'VE STAYED HOME.",
			"THAT'LL LEARN YA.",
			"SOMEBODY CALL THE UNDERTAKER.",
			"FIXIN' TO BE FERTILIZER.",
			"BLESS YOUR HEART.",
			"HOLD MY BEER.",
			"NOT IN MY COUNTY.",
			"THAT'S GONNA LEAVE A MARK."
		],
		"streak": ["WHO'S NEXT?", "I'M JUST GETTIN' WARMED UP.", "RAMPAGE TIME!", "LINE UP, BOYS."],
		"pickup_weapon":
		[
			"NOW WE'RE TALKIN'.",
			"COME TO PAPPY.",
			"THAT'LL DO NICELY.",
			"HOT DIGGITY.",
			"OH, YOU PURTY THING."
		],
		"pickup_food": ["GOOD EATIN'.", "MMM, SALTY.", "THAT HITS THE SPOT.", "WASH IT DOWN."],
		"hurt":
		["OW! THAT STUNG.", "WHY, I OUGHTA...", "YOU'LL PAY FER THAT.", "RIGHT IN THE OVERALLS!"],
		"low":
		["I'M SEEIN' THE LIGHT...", "NEED ME A SNACK.", "TOO MEAN TO DIE.", "SOMEBODY GET MAMA."],
		"reload": ["LOCK AND LOAD.", "ANOTHER ROUND.", "COME ON, COME ON...", "FEED THE BEAST."],
		"empty": ["CLICK. WELL, SHUCKS.", "OUT OF SHELLS!"],
		"drunk": ["HIC! WHO MOVED THE BARN?", "THE GROUND'S MOVIN'.", "I SEE TWO OF YA."],
		"secret": ["WELL, LOOKY HERE.", "NOW THAT'S A SECRET."],
	}
	const COOLDOWN := {
		"kill": 6.0,
		"streak": 8.0,
		"pickup_weapon": 4.0,
		"pickup_food": 7.0,
		"hurt": 7.5,
		"low": 14.0,
		"reload": 12.0,
		"empty": 6.0,
		"drunk": 20.0,
		"secret": 4.0
	}
	const GLOBAL_GAP := 2.6
	const SHOW_FOR := 2.2

	var state := 0
	var last_at := {}
	var last_line := {}
	var next_any := 0.0
	var text := ""
	var until := 0.0
	var recent_kills: Array = []
	var enabled := true

	func _init() -> void:
		state = (2098 * 6364136223846793005 + 1442695040888963407) & 0x7FFFFFFFFFFFFFFF

	func _rand() -> float:
		state = (state * 6364136223846793005 + 1442695040888963407) & 0x7FFFFFFFFFFFFFFF
		return float(state >> 10) / 9007199254740992.0

	func say(game, category: String, force := false) -> bool:
		# The local player's mouth (another player's kill is not ours to crow).
		if not enabled or game.player != game.local_player:
			return false
		var now: float = game.clock
		if (
			not force
			and (
				now < next_any
				or now - float(last_at.get(category, -99.0)) < float(COOLDOWN[category])
			)
		):
			return false
		var pool: Array = LINES[category]
		var choices: Array = []
		for line in pool:
			if line != last_line.get(category):
				choices.append(line)
		if choices.is_empty():
			choices = pool
		var line: String = choices[clampi(int(_rand() * choices.size()), 0, choices.size() - 1)]
		last_line[category] = line
		last_at[category] = now
		next_any = now + GLOBAL_GAP
		text = line
		until = now + SHOW_FOR
		if category == "kill" or category == "streak":
			if _rand() < .35:
				game.sound.play("yee_haw_alt" if _rand() < .5 else "yee_haw", .7)
		return true

	func kill(game) -> void:
		var recent: Array = []
		for t in recent_kills:
			if game.clock - float(t) < 7.0:
				recent.append(t)
		recent.append(game.clock)
		recent_kills = recent
		if recent_kills.size() >= 3:
			if say(game, "streak"):
				recent_kills.clear()
				return
		say(game, "kill")

	func visible(game) -> bool:
		return enabled and until > game.clock


## Port of rampage2.Cheats.
class Cheats:
	const CODES := {
		"hickgod": "HICK MODE: TOO MEAN TO DIE",
		"hickguns": "HICK MODE: ALL THE GUNS",
		"hickhp": "HICK MODE: FULL TANK",
		"hickbooze": "HICK MODE: STOCKED CELLAR",
		"hickbarks": "HICK MODE: BIG MOUTH",
	}
	var buffer := ""
	var god := false
	var used := false

	func feed(char: String, game) -> String:
		if char.length() != 1 or not char.to_lower() in "abcdefghijklmnopqrstuvwxyz":
			return ""
		buffer = (buffer + char.to_lower()).right(10)
		for code in CODES:
			if buffer.ends_with(code):
				buffer = ""
				apply(code, game)
				used = true
				var text: String = CODES[code]
				if code == "hickgod":
					text += " (ON)" if god else " (OFF)"
				return text
		return ""

	func apply(code: String, game) -> void:
		var p = game.player
		if code == "hickgod":
			god = not god
		elif code == "hickhp":
			p.health = 100
		elif code == "hickguns":
			var a = game.armory
			for i in Weapons.COUNT:
				a.owned[i] = true
				a.reserve[i] = Weapons.MAX_RESERVE[i]
		elif code == "hickbooze":
			for key in game.inventory:
				game.inventory[key] = 5
		elif code == "hickbarks":
			game.barks_off_by_code = game.barks.enabled
			game.barks.enabled = not game.barks.enabled


## Port of county_events.Gallery (the tin rooster shooting booth).
class Gallery:
	const GOAL := 4
	const LIMIT := 16.0
	const ROUNDS := 6
	const RADIUS := .135
	const TARGETS := [
		Vector3(29.54, 32.99, .68),
		Vector3(29.54, 33.56, 1.14),
		Vector3(29.54, 33.79, .65),
		Vector3(29.54, 33.15, 1.32)
	]

	## Where this level's booth stands relative to the first fair's
	## (GALLERY_STAND): its targets and its bounds move with it.
	var offset := Vector2.ZERO
	var rewarded := false
	var active := false
	var clock := 0.0
	var next_target := 2.35
	var hits := 0
	var spent := 0
	var index := 0
	var held := true
	var pistol: Weapons.Armory = null
	## The player who opened the booth (their slot): only they play it.
	var slot := 0

	func _init() -> void:
		pistol = Weapons.Armory.new(Weapons.REVOLVER)

	func toggle(game) -> void:
		if active:
			finish(game, "GALLERY CLOSED. E TO TRY AGAIN.")
			return
		if game.armory.fuse > 0.0:
			game.message("THROW THE LIT STICK FIRST.")
			return
		active = true
		slot = game.player.slot
		clock = 0.0
		next_target = 2.35
		hits = 0
		spent = 0
		index = 0
		held = true
		pistol = Weapons.Armory.new(Weapons.REVOLVER)
		game.message("TIN ROOSTER / 4 HITS, 6 BORROWED ROUNDS.", 2.1)
		game.sound.play("menu_accept")

	func prompt() -> String:
		return "E  CLOSE GALLERY" if active else "E  PLAY TIN ROOSTER"

	func hud() -> String:
		return (
			"TIN ROOSTER  %d/4  ROUNDS %d  TIME %02d"
			% [hits, ROUNDS - spent, int(ceil(LIMIT - clock))]
		)

	func sprite(game):
		var t: Vector3 = TARGETS[index] + Vector3(offset.x, offset.y, 0.0)
		var out := Renderer.Sprite.new(
			t.x,
			t.y,
			"county_gallery_target",
			RADIUS * 2.0,
			game.world.elevation(t.x, t.y) + t.z - RADIUS
		)
		out.plane = PI * .5
		return out

	func finish(game, message: String) -> void:
		active = false
		game.message(message, 2.6)

	func advance_target() -> void:
		index = (index + 1) % TARGETS.size()
		next_target = clock + 2.35

	func tick(dt: float, game, fire: bool) -> void:
		var p = game.player
		clock += dt
		pistol.tick(dt, game)
		var at: Vector2 = Vector2(p.x, p.y) - offset
		if not (25.10 <= at.x and at.x <= 28.66 and 32.77 <= at.y and at.y <= 33.94):
			finish(game, "LEFT THE GALLERY. E AT THE TICKET BOOTH TO RETRY.")
			return
		if clock >= LIMIT:
			finish(game, "TIME. E AT THE TICKET BOOTH TO RETRY.")
			return
		if clock >= next_target:
			advance_target()
		var tap := fire and not held
		held = fire
		if not tap or pistol.cooldown > 0.0:
			return
		spent += 1
		pistol.loaded[Weapons.REVOLVER] = ROUNDS - spent
		pistol.recoil = .54
		pistol.flash = .034
		pistol.cooldown = .18
		pistol.shot_age = 0.0
		game.sound.play("revolver", .56)
		var t: Vector3 = TARGETS[index] + Vector3(offset.x, offset.y, 0.0)
		var z: float = t.z + game.world.elevation(t.x, t.y)
		var dx: float = t.x - p.x
		var dy: float = t.y - p.y
		var ax := cos(p.view_angle())
		var ay := sin(p.view_angle())
		var reach: float = dx * ax + dy * ay
		var hit_z: float = p.eye + reach * (p.pitch + p.sway) / Renderer.base_focal
		if (
			reach > 0.0
			and absf(dx * ay - dy * ax) < RADIUS
			and absf(z - hit_z) < RADIUS
			and game.world.visible(p.x, p.y, t.x, t.y, p.eye, z)
		):
			hits += 1
			game.sound_at("ricochet", t.x, t.y, .55)
			advance_target()
		if hits == GOAL:
			if rewarded:
				finish(game, "NICE SHOOTING. PRIZE ALREADY CLAIMED.")
			else:
				rewarded = true
				if not game.collect("rinds"):
					game.add_pickup("rinds", 26.47, 33.64)
				finish(game, "TIN ROOSTER WINNER. ONE BAG OF RINDS.")
			game.sound.play("menu_accept")
		elif spent == ROUNDS:
			finish(game, "OUT OF BORROWED ROUNDS. E TO TRY AGAIN.")


# ------------------------------------------------------------------- state

var art: Assets
var hud: HUD
## What the game's sounds play through: the speaker (Sound) while the acting
## player is the local one, that player's PlayerVoice otherwise (focus()).
var sound = null
## This machine's Sound itself: sound_at() places a sound for the local
## player's ears through it whoever is acting.
var speaker = null

var level: LevelData
var world: LevelData
var renderer: Renderer

# ----------------------------------------------------------------- players
# src/players.gd says how this works (the multiplayer foundation, CLAUDE.md).

## Everyone playing, by slot (index 0 is player one; a slot is never reused).
var players: Array[Player] = []
## The player this machine shows and plays the sound of: the HUD, the view,
## the camera shake, the objective pin, captions, sound positions.
var local_player: Player
## The ACTING player: whose step the code running now is. Outside the tick it
## is the local player; during the tick each player in turn while their
## controls are played, and an enemy's hunted player while that enemy ticks
## (focus()). The many single-player call sites keep reading game.player.
var player: Player
## The acting player's guns (Player.armory; focus() swaps it in).
var armory: Weapons.Armory
## The acting player's flow field (Player.flow): steps from them over open
## floor, for enemies that have lost sight of them (flow_field.gd).
var flow: FlowField
## The acting player's pockets, keys, carried quest items, selected pocket and
## moonshine sprint (Player; Players.SHARED says which are one shared object).
var inventory: Dictionary:
	get:
		return player.inventory
	set(value):
		Players.store(self, "inventory", value)
var keys: Dictionary:
	get:
		return player.keys
	set(value):
		Players.store(self, "keys", value)
var task_items: Dictionary:
	get:
		return player.task_items
	set(value):
		Players.store(self, "task_items", value)
var inventory_slot: int:
	get:
		return player.inventory_slot
	set(value):
		player.inventory_slot = value
var sprint: float:
	get:
		return player.sprint
	set(value):
		player.sprint = value
## The acting player acts by their own hand this moment (focus()).
var own_step := false
## How many of `enemies` name_new() has looked at.
var _named_enemies := 0
## The controls of a player nobody steers this tick (never changed).
var _idle := Controls.new()
## The next stable entity id (enemies, shots, pickups): handed out in the
## order things come into being, so two machines running the same ticks agree
## (game_snapshot.gd).
var next_uid := 1

var enemy_ids: Array = []
## The places enemies run from this tick (lit dynamite on the ground):
## Vector3(x, y, radius).
var dangers: Array = []
## The same, measured from the objective over the whole level with its doors
## open: the objective pin points along it instead of through walls.
var route: FlowField
## What the route was last measured with: stations done, keys, doors open.
var route_sig := []
var enemies: Array = []
var partners := {}
var wave: Array = []
var boss = null
var jerry = null
var bessie = null
var finale = null

var props: Array = []
# The sprites that only change with the game's state (props, boards, drums,
# notes, rooms, scenery): game_view.gd lists them again only when the state
# they show changes. Two parts, so the list keeps its order around the
# gallery's moving target.
var fixed_sprites: Array = []
var fixed_sprites_late: Array = []
var fixed_windmills: Array = []
var fixed_sprites_key := []
## The fixed sprites in blocks of the map, so a frame lists only the blocks the
## view can see (game_view.gd _seen): per block its middle, its reach and the
## sprites' places in fixed_sprites (fixed_blocks) or fixed_sprites_late.
var fixed_blocks: Array = []
var late_blocks: Array = []
## This frame's view for in_view(): eye x, y, facing x, y, the half width of
## the view per unit ahead, the mirror's line (NAN: none) and the mirrored eye's x.
var view_cone := PackedFloat64Array()
## fixed_blocks and late_blocks flat for _seen(): per block middle x, y, reach.
var fixed_cull := PackedFloat64Array()
var late_cull := PackedFloat64Array()
## The sprites that last one frame (enemies, pickups, shots, effects) come
## from this pool (pooled()), kept from frame to frame; sprites() starts it
## over. Nothing may keep a pooled sprite past the frame that listed it.
var sprite_pool: Array = []
var sprite_pool_n := 0
## The level's dress marks made once (game_combat.gd ground_marks()): the marks,
## and for each its x, y and the reach it shows within, for the level `dress_of`.
var dress_list: Array = []
var dress_at := PackedFloat64Array()
var dress_of: LevelData = null
## player_sheltered(): whether a hostile enemy was alerted, as of
## (Enemy.alert_changes, enemies.size()) in shelter_key.
var shelter_key := Vector2i(-1, -1)
var shelter_alert := false
## effect_lights(): the props that are lamps and the street lamp boards, found
## once for the level `lamps_of` with that many props.
var lamp_props: Array = []
var lamp_boards: Array = []
var lamps_of := Vector2i(-1, -1)
var pickups: Array = []
var drums := {}
var stations_done := {}
var total_secrets := 0
var history: Array = []
var replay := false
var revisiting := false
var retained := {}
var music_bookmark = null
var in_hub := false
## Loaded from a save of an older build of this level: started over (session_store.gd).
var layout_restarted := false
var gallery: Gallery = null
var supply_rule := 0
var gate_modes := {}
var hub_findings := {}
var hub_milestone := 0
var hub_dispatch_until := 0.0
var portal_request := ""
var entry := {}

var kills := 0
var secrets := 0
var total_kills := 0
var rng: Rng
var barks: Barks
var duck := 0.0
var cheats: Cheats
var barks_off_by_code := false
var last_low_bark := 0.0
var clock := 0.0
var spawn_grace := 3.2
var face_until := 0.0
var message_until := 0.0
var face := ""
var notice := ""
var hurt_flash := 0.0
var blast_flash := 0.0
var damage_feedback = null
var item_feedback = null
## Game feel (HIT FEEDBACK and SCREEN SHAKE): a short freeze when a shot kills
## or hits hard, the crosshair's hit mark (red after a kill) and its tick, and
## a shake of the view (0 to 1, squared when drawn) from blasts, heavy guns and
## blows. None of it is saved; the freeze stops the world but not the aim.
var hitstop := 0.0
var hitstop_next := 0.0
var hit_mark_until := 0.0
var hit_mark_kill := false
var hit_tick_next := 0.0
var shake := 0.0
## The acting player's footstep count and when their full gut may belch next.
var step_number: int:
	get:
		return player.step_number
	set(value):
		player.step_number = value
var next_belch: float:
	get:
		return player.next_belch
	set(value):
		player.next_belch = value

var shots: Array = []
var specks: Array = []
## Gibs, blood pools and wall splats (gore.gd).
## Made in Game._init, which can hand it the whole game.
var gore_fx: Gore
var blasts: Array = []
var hazards: Array = []
var wall_marks: Array = []
var wall_sound := 0.0
var map := false
var won := false
var legacy_completed := false
var legacy_key_route := false
var valve_turns := {}
var next_valve_turn := 0.0
var scenery_spent := {}
var bowled := {}
var exchanges: Array = []
var heard_exchanges := {}
var exchange_next := 0.0
var exchange_pending = null
var caption := ""
var caption_until := 0.0
var visited := {}
var district := 0
var district_until := 3.0
## Where the objective pin hangs this frame: under whatever notice, place name
## or boss bar is at the top of the view (game_view.gd sets it, hud.gd uses it).
var pin_top := 5
var amb_clock := 3.0
var jukebox_on := false
## Where each thing to use can be aimed at (game_world.gd aim_points): the
## thing -> its points with heights, worked out once per level.
var aim_cache := {}
## The name of the button that uses things, for the prompt: the bound key, Y
## on a controller, USE on a touch screen (main.gd sets it each frame).
var use_key := "E"
## The aim point (x, y, height) of the device use_target() last chose, for the
## marker drawn round it; INF when it chose none or a door.
var use_aim := Vector3.INF
var flush_until := 0.0
var map_panel = null
var map_signature = null
var radio_check := 0.0

# Options (configure()).
var incoming := 1.0
var bob_scale := 1.0
## 0 = automatic (one band per core, capped at 16). Set by the options screen.
var look_bands := 0
## With gpu_look the grain, vignette, wash and brightness table are applied by
## palette.gdshader instead of in draw(); main.gd turns it on when there is a
## window. look_live / tone_live say which of them this frame wants.
var gpu_look := false
## With `layered` (and gpu_look) the display shader also draws the sky, floors
## and ceilings and composes the view; the canvas is then only a layer over it.
## scene_live says whether this frame was drawn that way. drunk_k is the
## moonshine warp's strength for the shader (0 none).
var layered := false
var scene_live := false
var drunk_k := 0.0
## The red hurt wash (0-255) the display shader lays over the view this frame.
var hurt_alpha := 0
var look_live := false
var tone_live := false
var flash_scale := 1.0
var gore := true
var aim_assist := 0
var hit_feedback := true
var shake_scale := 1.0
## ADAPTIVE DIFFICULTY: incoming damage eases after each death and stiffens
## after a chapter finished in good health, between .78 and 1.15 of what the
## DIFFICULTY setting gives. Kept for the session (every Game shares it).
static var adapt := 1.0
var adaptive := true
## The touch overlay is in use (main.gd sets it): aim help reaches further.
var touch_aim := false
## TOUCH AUTO FIRE (game_combat.gd sights_on_enemy): its last answer. The
## guns it fires have auto_fire in weapons.cfg (never one that could blow up
## in the player's face).
var sights_next := 0.0
var sights_last := false
## Real play (main_flow.gd play()) teaches the controls as they come up
## (lessons.gd); tools that build a Game leave it off.
var lessons := false
## Lights level triggers have put up (triggers.gd): [x, y, z, radius, Color,
## strength, until].
var trigger_lights: Array = []
## What happens in play, announced for the features (src/features/) to listen
## to, instead of each feature being written into the code that does it.
signal enemy_killed(enemy: Enemy)
signal player_hurt(amount: float, cause: String)
signal pickup_taken(name: String)
signal station_done(station_id: String)
signal shot_fired(gun: int)
signal hit_landed(amount: float, killed: bool)
signal level_won
signal ticked(dt: float)
signal exploded(x: float, y: float, z: float, energy: bool)
signal gun_reloading(gun: int)
## One of the county's hands has something to say (src/squad.gd, throttled):
## "spot", "lost", "search", "help", "flank", "cover", "brawl", "idle",
## "surprised", "hurt_bad", "regroup". When each may next be heard ("" any).
signal enemy_bark(e: Enemy, moment: String)
var bark_next := {}
## DIFFICULTY (0 EASY .. 3 HOG WILD), how sharp the county's hands are (their
## attack recovery, how far they notice, how true they shoot), and how much of
## an ammo pickup the player gets.
var difficulty := 1
var sharpness := 1.0
var ammo_scale := 1.0
## A boss went fightin' mad at half health (enemies.gd _enrage).
signal boss_enraged(enemy: Enemy)
## The boss fights (boss_kit.gd, features/boss_fight.gd, src/bosses/): a
## boss's fight began (its entrance), it reached a new phase (2 under half
## health, 3 under a fifth; Maw Glorb by her own), one instant's hits
## staggered it, a hit found its weak spot, and it fell `seconds` after its
## fight began (0 when it never began).
signal boss_intro(enemy: Enemy)
signal boss_phase(enemy: Enemy, phase: int)
signal boss_staggered(enemy: Enemy)
signal boss_weak_hit(enemy: Enemy)
signal boss_down(enemy: Enemy, seconds: float)
## Where the player's hit about to hurt someone struck (a bullet or pellet on
## the body, a shot where it touched, a blast's middle) and where the player
## stood, set just before hurt(); hurt() asks a boss's weak spot with it and
## forgets it (INF: not known).
var hit_point := Vector3.INF
var hit_from := Vector2.ZERO
## The shot kind whose blast is hurting things this moment (explode(): "cow",
## "tnt"...), "" otherwise: how a body it kills is thrown (hit_zones.gd).
var blast_kind := ""
## The crosshair's mark (game_view.gd): when this one started, and whether a
## hit in it was on the head (hit_zones.gd).
var hit_mark_at := -1.0
var hit_mark_head := false
## Bosses call in backup at their phase changes (a rematch may turn it off).
var boss_backup := true
## A boss's entrance (BossKit.hold): seconds of it left, its whole length,
## whose it is, and whether fire has been let go since (a fresh press skips).
var boss_hold := 0.0
var boss_hold_for := 0.0
var boss_hold_of: Enemy = null
var boss_hold_armed := false
## Slow motion as a boss falls: real seconds of it left; the world goes at
## SLOWMO_PACE meanwhile, the player and the gun at full speed.
var slowmo := 0.0
const SLOWMO_PACE := .35
## A hitscan shot (a bullet, a pellet, a swing, the milk) ended at `end`:
## struck is "enemy", "thing" (a drum or scenery), "glass", "wall:<surface>"
## (wood, metal, plaster, dirt) or "air" (nothing within its range).
signal traced(end: Vector3, struck: String)
## What the last shot to strike a wall, floor or roof met (materials.gd kinds:
## wood, tin, steel, brick, glass...), set just before `traced` says so.
var impact_kind := ""
## A strong round went through a thin wall (penetration.gd): where it went in
## and came out; struck is "enemy" when it hurt someone behind, else "air".
signal pierced(entry: Vector3, exit: Vector3, struck: String)
## The view's kick this frame, from features/feel.gd: yaw (radians), pitch
## (screen pixels) and how far the eye drops (cells). Never moves the aim.
var view_kick := Vector3.ZERO
## This tick's turn of the view and whether the player just landed (game.gd),
## for features/feel.gd's springs.
var feel_turn := 0.0
var feel_landed := false
## The eye the view was drawn from this frame, shake and all (game_view.gd
## to_canvas() projects the world onto the canvas with it).
var view_eye := {}
## A lightning flash this moment, 0 to 1 (features/weather.gd; the shader).
var lightning := 0.0
## A kill streak's call across the screen (features/callouts.gd).
var callout := ""
var callout_until := 0.0
## The features, by id (features.gd).
var features := {}
## Level triggers that have fired (saved), and which repeating ones the player
## is inside of now.
var triggers_fired := {}
var triggers_inside := {}
var district_labels := true
var hints := true
var hud_style := 0
var weapon_view := 0
var voice_captions := true
var bullet_marks := true
var retro_look := true
var flicker := true
## CROSSHAIR COLOR: what the aiming mark is painted (bone by default).
var crosshair_tint := Color8(188, 168, 132)

## Final VGA brightness tone table (set by the front end when brightness != 100).
var tone = null

var showing_tally: bool:
	get:
		return won and not revisiting

# -------------------------------------------------------------- configure

var _render_open := false
## Called (by main_state.gd: scene_layers.gd early()) once the gun and HUD are
## painted and before the draw waits for the renderer's bands.
var scene_hook := Callable()

## rampage2.look_pass tables: wash tint, vignette and ordered dither.
var _grit_r := PackedFloat32Array()
var _grit_g := PackedFloat32Array()
var _grit_b := PackedFloat32Array()
var _dither := PackedFloat32Array()

const GRAIN_STRIDE := 936
const GRAIN_FRAMES := 6

var _look_threads: Array[Thread] = []
var _look_rows_per := 0
var _look_gain := 1.0
var _look_frame := 0
var _look_blast := 0.0
var _look_tone = null

## The automap (game_view.gd): the whole map drawn at the zoom in use, the
## scale it was drawn at, how much of `visited` is painted on it, the cells a
## secret still hides, and this frame's window onto it; the zoom (an index into
## MAP_ZOOMS; 0 fits the level); the texture the window shows on a 2D canvas.
var _map_image: Image = null
var _map_built_scale := -1.0
var _map_painted := 0
var _map_hidden := {}
var _map_origin := Vector2.ZERO
var _map_scale_now := 1.0
var _map_region_now := Rect2i()
var map_zoom := 2
var _map_texture: ImageTexture

## game.Controls: one sim step's input.
## Milliseconds the last draw spent listing sprites, rendering the scene, drawing
## the weapon, grading the view and drawing the HUD; read by tools/bench.gd.
var stage_ms: Array = [0.0, 0.0, 0.0, 0.0, 0.0]


## Makes `p` the acting player (see `player`): its guns, flow field, pockets
## and keys become the game's armory, flow, inventory, keys... `own`: it acts
## by its own hand (its controls, a shot it threw), so its sounds play from
## where it stands (unless it is the local player) and its notices are not
## shown here; an enemy's turn after it is not its own. Nearly free with one
## player.
func focus(p: Player, own := false) -> void:
	own_step = own
	if p != player:
		player = p
		armory = p.armory
		flow = p.flow
	if speaker != null and players.size() > 1:
		sound = p.voice if own and p != local_player and p.voice != null else speaker


## The next stable entity id (an enemy, a shot, a pickup).
func take_uid() -> int:
	next_uid += 1
	return next_uid - 1


## Whether the acting player is the one this machine shows: presentation
## (the HUD's flashes, the view's kick, the face, messages) is for them only.
func acting_local() -> bool:
	return player == local_player


## A sprite for this frame's list from the pool, as Renderer.Sprite.new()
## would make it (every other field at its default).
func pooled(px: float, py: float, image: String, h: float, pz: float) -> Renderer.Sprite:
	if sprite_pool_n < sprite_pool.size():
		var s: Renderer.Sprite = sprite_pool[sprite_pool_n]
		sprite_pool_n += 1
		s.x = px
		s.y = py
		s.image = image
		s.height = h
		s.z = pz
		s.glow = false
		s.flip = false
		s.translucent = false
		s.body = false
		s.plane = NAN
		s.hurt = 0.0
		return s
	var made := Renderer.Sprite.new(px, py, image, h, pz)
	sprite_pool.append(made)
	sprite_pool_n += 1
	return made


class Controls:
	var forward := 0.0
	var strafe := 0.0
	var turn := 0.0
	var look := 0.0
	var running := false
	var fire := false
	var alt_fire := false
	var jump := false
	var crouch := false
	## For a player whose actions arrive as controls (a second player, a bot,
	## later the network): USE on a fresh press, a gun slot to take up and a
	## pocket item to use (-1: none). The local player's front end calls
	## interact(), Armory.select() and use_item() itself between ticks.
	var use := false
	var weapon := -1
	var item := -1
	## The next (1) or last (-1) gun, as the mouse wheel takes it.
	var cycle := 0
