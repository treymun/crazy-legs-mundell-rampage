## The setup screen's pages: every setting's label, key, default, range and
## hint (SessionStore.setup_pages() builds them once and keeps the defaults).
## A setting's default is how the game played before it existed (CHATTER is
## the owner's exception: CUSSIN' from the start).
class_name SetupPages
extends RefCounted

## The small headings that split a page into groups: page -> {the key of the
## first setting under a heading: the heading}. Only drawn (menu.gd).
const HEADERS := {
	"INPUT": {"sensitivity": "MOUSE", "pad_look": "GAMEPAD", "autorun": "HABITS"},
	"DISPLAY": {"brightness": "SCREEN", "crosshair": "SIGHTS AND GAUGES"},
	"AUDIO": {"master": "VOLUME", "voice_captions": "SOUND", "menu_music": "MENUS AND WINDOW"},
	"PLAY":
	{
		"difficulty": "THE RUN",
		"aim_assist": "AIM AND GUNS",
		"barks": "ON THE SCREEN",
	},
	"VIEW": {"detail": "PICTURE", "world_motion": "EASY ON THE EYES"},
	"KEYS":
	{
		"key_forward": "MOVING",
		"key_fire_key": "DOING",
		"key_prev_weapon": "GUNS AND GROCERIES",
		"key_map": "LOOKING AROUND",
	},
	"TOUCH": {"auto_fire": "PHONE AND TABLET"},
}


static func build() -> Array:
	return [
		[
			"INPUT",
			[
				SessionStore.Setting.new(
					"MOUSE TURN SPEED",
					"sensitivity",
					100,
					40,
					220,
					10,
					[],
					"HORIZONTAL MOUSE SPEED"
				),
				SessionStore.Setting.new(
					"MOUSE LOOK SPEED",
					"vertical",
					100,
					40,
					220,
					10,
					[],
					"VERTICAL MOUSE SPEED, INDEPENDENT OF TURN SPEED"
				),
				SessionStore.toggle(
					"INVERT MOUSE Y", "invert", 0, "REVERSE UP AND DOWN MOUSE LOOK"
				),
				SessionStore.Setting.new(
					"PAD LOOK SPEED",
					"pad_look",
					100,
					40,
					220,
					10,
					[],
					"HOW FAST THE RIGHT STICK TURNS AND TIPS THE VIEW"
				),
				SessionStore.choices(
					"PAD DEADZONE",
					"pad_deadzone",
					1,
					["SMALL", "NORMAL", "LARGE"],
					"HOW FAR A STICK MOVES BEFORE IT COUNTS. LARGE STOPS A WORN STICK DRIFTING."
				),
				SessionStore.toggle(
					"INVERT PAD Y", "pad_invert", 0, "REVERSE UP AND DOWN ON THE RIGHT STICK"
				),
				SessionStore.toggle("ALWAYS RUN", "autorun", 0, "SHIFT INVERTS RUN WHILE HELD"),
				SessionStore.choices(
					"CROUCH", "crouch", 0, ["HOLD", "TOGGLE"], "HOW THE Z KEY CONTROLS CROUCHING"
				),
				SessionStore.toggle(
					"PAUSE ON FOCUS LOSS", "focus_pause", 1, "PAUSE IF YOU SWITCH TO ANOTHER WINDOW"
				),
			]
		],
		[
			"DISPLAY",
			[
				SessionStore.Setting.new(
					"BRIGHTNESS",
					"brightness",
					100,
					80,
					150,
					10,
					[],
					"BRIGHTEN THE SCENE; HUD AND TEXT STAY FIXED"
				),
				SessionStore.choices(
					"ASPECT / SCALING",
					"aspect",
					0,
					["DOS 4:3", "SQUARE 8:5", "INTEGER 8:5"],
					"ALL MODES KEEP CRISP, UNSMOOTHED PIXELS"
				),
				SessionStore.choices(
					"FRAME LIMIT",
					"frame_limit",
					1,
					["30 FPS", "60 FPS", "120 FPS", "144 FPS", "240 FPS"],
					"LIMIT SCREEN REFRESH AND CPU USE"
				),
				SessionStore.choices(
					"WINDOW MODE",
					"window_mode",
					0,
					["WINDOWED", "FULLSCREEN (FILL)", "FULLSCREEN (ASPECT)"],
					"FILL REMOVES THE TITLE BAR AND ALL BLACK BARS"
				),
				SessionStore.choices(
					"CROSSHAIR",
					"crosshair",
					1,
					["OFF", "DOT", "RING", "CROSS"],
					"CHOOSE AN AIMING MARK"
				),
				SessionStore.choices(
					"CROSSHAIR COLOR",
					"crosshair_color",
					0,
					["BONE", "AMBER", "LIME", "RED", "WHITE"],
					"PAINT THE AIMING MARK SO IT STANDS OUT AGAINST THE DIRT"
				),
				SessionStore.choices(
					"STATUS PANEL",
					"hud_style",
					0,
					["METERS", "DIALS"],
					"GAUGE STYLE FOR THE GUT AND DRUNK METERS"
				),
				SessionStore.choices(
					"WEAPON POSITION",
					"weapon_view",
					0,
					["STANDARD", "LOWER", "HIDDEN"],
					"LOWER OR HIDE WEAPON ART. LIT TNT STAYS VISIBLE."
				),
				SessionStore.choices(
					"TEXT SIZE",
					"text_size",
					0,
					["NORMAL", "TALL", "LARGE"],
					"SIZE OF NOTICES, PROMPTS, CAPTIONS AND ONE-LINERS"
				),
				SessionStore.toggle(
					"FRAME COUNTER",
					"show_fps",
					0,
					"FRAMES PER SECOND IN THE TOP CORNER WHILE YOU PLAY"
				),
			]
		],
		[
			"AUDIO",
			[
				SessionStore.Setting.new(
					"MASTER VOLUME",
					"master",
					100,
					0,
					100,
					10,
					[],
					"SCORE, GUNS, VOICES AND YARD, ALL AT ONCE"
				),
				SessionStore.Setting.new(
					"MUSIC VOLUME",
					"music",
					50,
					0,
					100,
					10,
					[],
					"BACKGROUND SCORE; F4 ALSO MUTES THE SCORE"
				),
				SessionStore.Setting.new(
					"EFFECTS VOLUME",
					"effects",
					100,
					0,
					100,
					10,
					[],
					"WEAPONS, MOVEMENT AND INTERACTIONS"
				),
				SessionStore.Setting.new(
					"AMBIENCE VOLUME",
					"ambience",
					100,
					0,
					100,
					10,
					[],
					"ROOMS, WIND, CREEK AND BACKGROUND ANIMALS"
				),
				SessionStore.Setting.new(
					"FOOTSTEP VOLUME",
					"footsteps",
					100,
					0,
					100,
					10,
					[],
					"PLAYER FOOTSTEPS AND LANDINGS"
				),
				SessionStore.Setting.new(
					"VOICE VOLUME",
					"voice_volume",
					80,
					0,
					100,
					10,
					[],
					"OVERHEARD RADIOS, SPEAKERS AND PA"
				),
				SessionStore.toggle(
					"VOICE CAPTIONS", "voice_captions", 1, "TEXT FOR OVERHEARD LOCAL EXCHANGES"
				),
				SessionStore.choices(
					"CHATTER",
					"chatter",
					2,
					["OFF", "CLEAN", "CUSSIN'"],
					"WHAT THE HANDS, THE BOTS AND MUNDELL SAY. CLEAN QUACKS OVER THE CUSSIN'"
				),
				SessionStore.choices(
					"SFX STEREO WIDTH",
					"stereo",
					2,
					["MONO", "NARROW", "NORMAL", "WIDE"],
					"CONTROL HOW FAR POSITIONAL SOUNDS PAN"
				),
				SessionStore.toggle(
					"ROOM REVERB",
					"reverb",
					1,
					"ECHO THAT FOLLOWS THE ROOM, BARN OR OPEN AIR YOU STAND IN"
				),
				SessionStore.toggle(
					"MENU MUSIC",
					"menu_music",
					1,
					"THE TITLE TUNE ON THE MENUS. OFF KEEPS THE FRONT PORCH QUIET."
				),
				SessionStore.toggle(
					"MUTE IN BACKGROUND",
					"bg_mute",
					0,
					"SILENCE THE GAME WHILE ANOTHER WINDOW OR APP HAS THE FOCUS"
				),
			]
		],
		[
			"PLAY",
			[
				SessionStore.choices(
					"DIFFICULTY",
					"difficulty",
					1,
					["EASY", "NORMAL", "HARD", "HOG WILD"],
					"HARD: SHARPER HANDS, A BIGGER POSSE, LESS AMMO. HOG WILD: ALL THAT AND MORE."
				),
				SessionStore.toggle(
					"ADAPTIVE DIFFICULTY",
					"adaptive",
					1,
					"EASES OFF A LITTLE AFTER EACH DEATH, PUSHES BACK WHEN YOU FINISH IN GOOD SHAPE"
				),
				SessionStore.choices(
					"NEXT RUN SUPPLIES",
					"supply_rule",
					0,
					["STANDARD", "SCARCE", "NO DROPS"],
					"NEW RUNS ONLY. SCARCE CUTS BOXES. NO DROPS REMOVES BASIC FOE AMMO."
				),
				SessionStore.toggle(
					"CLASSIC LEVEL FLOW",
					"classic",
					0,
					"SKIP THE CROSSROADS. GO STRAIGHT TO THE NEXT CHAPTER."
				),
				SessionStore.choices(
					"AIM ASSIST",
					"aim_assist",
					0,
					["OFF", "VERTICAL", "CLASSIC"],
					"HELPS LINE UP VISIBLE TARGETS"
				),
				SessionStore.toggle(
					"HIT FEEDBACK",
					"hit_feedback",
					1,
					"CROSSHAIR MARKS AND A KNOCK ON HITS, A CLANK AND A BEAT OF PAUSE ON KILLS"
				),
				SessionStore.toggle(
					"AUTO SWITCH ON PICKUP",
					"auto_switch",
					1,
					"EQUIP A NEW WEAPON AS SOON AS YOU FIND IT"
				),
				SessionStore.toggle(
					"RELOAD ON EMPTY", "auto_reload", 1, "FIRING AN EMPTY GUN STARTS RELOADING"
				),
				SessionStore.toggle("PLAYER ONE-LINERS", "barks", 1, "SHOW THE HERO'S WISECRACKS"),
				SessionStore.toggle(
					"BLOOD PARTICLES", "gore", 1, "SHOW BLOOD PARTICLES WHEN ENEMIES ARE HIT"
				),
				SessionStore.toggle(
					"DISTRICT LABELS",
					"district_labels",
					1,
					"SHOW LOCATION NAMES WHEN YOU ENTER NEW AREAS"
				),
				SessionStore.toggle(
					"TOOLTIPS / OBJECTIVES", "hints", 1, "SHOW USE PROMPTS AND OBJECTIVES"
				),
			]
		],
		[
			"VIEW",
			[
				(
					SessionStore
					. choices(
						"VIEW DETAIL",
						"detail",
						2,
						["HIGH", "LOW", "AUTO", "HD"],
						"HIGH IS 320 WIDE, LOW HALF. AUTO GOES LOW WHEN FRAMES RUN LATE. HD: 640, TWICE AS SHARP."
					)
				),
				SessionStore.choices(
					"FIELD OF VIEW",
					"fov",
					0,
					["70", "80", "90", "100"],
					"HOW WIDE THE VIEW IS, IN DEGREES. 70 IS THE ORIGINAL."
				),
				SessionStore.toggle(
					"LIGHTS AND GLOW",
					"lights",
					1,
					"GUNFIRE, BLASTS, SHOTS AND LAMPS CAST COLOURED LIGHT. LIT WINDOWS GLOW."
				),
				SessionStore.toggle(
					"FILM GRAIN + COLOR WASH",
					"film_look",
					0,
					"OFF IS THE PLAIN 256-COLOR PICTURE. ON ADDS GRAIN, DITHER AND A TINT."
				),
				SessionStore.toggle(
					"TILED WALLS",
					"wall_tiling",
					1,
					"REPEAT WALL TEXTURES AT ONE SIZE INSTEAD OF STRETCHING THEM"
				),
				SessionStore.toggle(
					"BULLET MARKS", "bullet_marks", 1, "DRAW IMPACT MARKS ON WALLS"
				),
				SessionStore.choices(
					"SCENERY MOTION",
					"world_motion",
					0,
					["FULL", "REDUCED", "STATIC"],
					"ADJUST MOTION IN CROSSROADS SCENERY AND THE MENUS"
				),
				SessionStore.choices(
					"SCREEN SHAKE",
					"shake",
					2,
					["OFF", "LOW", "FULL"],
					"BLASTS, BIG GUNS AND HITS JOLT THE VIEW"
				),
				SessionStore.choices(
					"SCREEN FLASH",
					"flashes",
					0,
					["FULL", "REDUCED", "OFF"],
					"REDUCE DAMAGE, MUZZLE AND BLAST FLASHES, AND THE MENU LIGHTS"
				),
				SessionStore.Setting.new(
					"WEAPON / VIEW BOB",
					"bob",
					100,
					0,
					100,
					25,
					[],
					"REDUCE VIEW AND WEAPON SWAY WHILE WALKING"
				),
				SessionStore.toggle(
					"LAMP FLICKER",
					"flicker",
					1,
					"BUZZING LIGHTS INDOORS. TURN OFF IF SENSITIVE TO FLASHING."
				),
			]
		],
		["KEYS", _key_settings()],
		[
			"TOUCH",
			[
				(
					SessionStore
					. toggle(
						"TOUCH AUTO FIRE",
						"auto_fire",
						1,
						"ON A PHONE OR TABLET, STRAIGHT-SHOOTING GUNS FIRE BY THEMSELVES AT A FOE IN THE SIGHTS"
					)
				),
				SessionStore.choices(
					"TILT AIM",
					"tilt_aim",
					0,
					["OFF", "LOW", "HIGH"],
					"TURN AND TIP THE PHONE TO AIM, AS WELL AS DRAGGING"
				),
				(
					SessionStore
					. choices(
						"TOUCH BUTTONS",
						"touch_layout",
						0,
						["STANDARD", "MY LAYOUT", "MOVE THEM"],
						"MOVE THEM SHOWS THE STICK AND BUTTONS TO DRAG. MY LAYOUT USES WHERE YOU PUT THEM."
					)
				),
			]
		],
	]


static func _key_settings() -> Array:
	var rows: Array = []
	for entry: Array in KeyBindings.ACTIONS:
		rows.append(SessionStore.KeySetting.new(entry[0], entry[1], entry[2]))
	return rows
