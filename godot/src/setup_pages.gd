## The setup screen's pages: every setting's label, key, default, range and
## hint (SessionStore.setup_pages() builds them once and keeps the defaults).
class_name SetupPages
extends RefCounted


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
					"CROSSHAIR", "crosshair", 1, ["OFF", "DOT", "RING"], "CHOOSE AN AIMING MARK"
				),
				SessionStore.choices(
					"STATUS PANEL",
					"hud_style",
					0,
					["METERS", "DIALS"],
					"GAUGE STYLE FOR THE GUT AND DRUNK METERS"
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
				SessionStore.choices(
					"SCREEN FLASH",
					"flashes",
					0,
					["FULL", "REDUCED", "OFF"],
					"REDUCE DAMAGE, MUZZLE AND BLAST FLASHES"
				),
			]
		],
		[
			"AUDIO",
			[
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
			]
		],
		[
			"PLAY",
			[
				SessionStore.choices(
					"DIFFICULTY",
					"difficulty",
					1,
					["EASY", "NORMAL", "HARD"],
					"ADJUSTS INCOMING DAMAGE IN THE CURRENT RUN"
				),
				SessionStore.choices(
					"AIM ASSIST",
					"aim_assist",
					0,
					["OFF", "VERTICAL", "CLASSIC"],
					"HELPS LINE UP VISIBLE TARGETS"
				),
				SessionStore.toggle(
					"ADAPTIVE DIFFICULTY",
					"adaptive",
					1,
					"EASES OFF A LITTLE AFTER EACH DEATH, PUSHES BACK WHEN YOU FINISH IN GOOD SHAPE"
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
				SessionStore.toggle(
					"CLASSIC LEVEL FLOW",
					"classic",
					0,
					"SKIP THE CROSSROADS. GO STRAIGHT TO THE NEXT CHAPTER."
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
				SessionStore.choices(
					"NEXT RUN SUPPLIES",
					"supply_rule",
					0,
					["STANDARD", "SCARCE", "NO DROPS"],
					"NEW RUNS ONLY. SCARCE CUTS BOXES. NO DROPS REMOVES BASIC FOE AMMO."
				),
			]
		],
		[
			"VIEW",
			[
				SessionStore.choices(
					"SCENERY MOTION",
					"world_motion",
					0,
					["FULL", "REDUCED", "STATIC"],
					"ADJUST MOTION IN CROSSROADS SCENERY"
				),
				SessionStore.choices(
					"WEAPON POSITION",
					"weapon_view",
					0,
					["STANDARD", "LOWER", "HIDDEN"],
					"LOWER OR HIDE WEAPON ART. LIT TNT STAYS VISIBLE."
				),
				SessionStore.toggle(
					"LIGHTS AND GLOW",
					"lights",
					1,
					"GUNFIRE, BLASTS, SHOTS AND LAMPS CAST COLOURED LIGHT. LIT WINDOWS GLOW."
				),
				SessionStore.choices(
					"FIELD OF VIEW",
					"fov",
					0,
					["70", "80", "90", "100"],
					"HOW WIDE THE VIEW IS, IN DEGREES. 70 IS THE ORIGINAL."
				),
				SessionStore.choices(
					"TEXT SIZE",
					"text_size",
					0,
					["NORMAL", "TALL", "LARGE"],
					"SIZE OF NOTICES, PROMPTS, CAPTIONS AND ONE-LINERS"
				),
				SessionStore.choices(
					"SCREEN SHAKE",
					"shake",
					2,
					["OFF", "LOW", "FULL"],
					"BLASTS, BIG GUNS AND HITS JOLT THE VIEW"
				),
				SessionStore.toggle(
					"BULLET MARKS", "bullet_marks", 1, "DRAW IMPACT MARKS ON WALLS"
				),
				SessionStore.toggle(
					"FILM GRAIN + COLOR WASH",
					"film_look",
					0,
					"OFF IS THE PLAIN 256-COLOR PICTURE. ON ADDS GRAIN, DITHER AND A TINT."
				),
				(
					SessionStore
					. choices(
						"VIEW DETAIL",
						"detail",
						2,
						["HIGH", "LOW", "AUTO", "HD"],
						"LOW HALVES THE VIEW. AUTO GOES LOW ONLY WHEN FRAMES RUN LATE. HD DRAWS IT TWICE AS SHARP."
					)
				),
				SessionStore.toggle(
					"TILED WALLS",
					"wall_tiling",
					1,
					"REPEAT WALL TEXTURES AT ONE SIZE INSTEAD OF STRETCHING THEM"
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
