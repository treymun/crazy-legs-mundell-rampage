## The county's hands talk (scripts/audio_spec.py BARKS): the squads announce
## moments (game_state.gd enemy_bark: spot, lost, search, help, flank, cover,
## brawl, idle, surprised, hurt_bad, regroup) and the hand says a line for it
## in its kind's voice, from where it stands, captioned when nothing else is.
## Throttled so a crowd never talks over itself, and quiet while anyone else
## is talking (Sound.talking: a boss, Mundell, the radio). Sound and captions only: its
## own dice, nothing saved. CHATTER (game.chatter, CussLines): OFF says
## nothing; CLEAN and CUSSIN' mix in the cuss pack's lines where they are made
## (CUSS_SHARE of the time), CLEAN's copies quacked over and captioned #@!%.
## In the 5v5 and 2v2 modes the bots talk too (`_tactical`, watched each
## tick): a kill, a bad hit, the plant, the defuse, the round won; outlaws in
## the hick's voice, deputies in the deputy's. A bot is a player this machine
## does not drive and the lobby did not name.
extends GameFeature

const ModeFeature := preload("res://src/features/mode_feature.gd")

## Kind (or brain) -> voice. Kinds not here (skeeters, saucers, gators, the
## probes, lanterns, crawlers, the chalk spitters) have nothing to say. The
## young hicks are Hickston's and the fair's; the working men of the mill, the
## quarry, the fish camp and the pits talk in the local voice (pass 7).
const VOICES := {
	"billy": "hick",
	"big_billy": "hick",
	"clone": "hick",
	"millhand": "local",
	"chain_hand": "local",
	"boilerback": "local",
	"valve_rat": "local",
	"bottle_tosser": "local",
	"barker": "hick",
	"noodler": "local",
	"chum_tosser": "local",
	"pit_mechanic": "local",
	"tire_roller": "local",
	"nitro_huffer": "local",
	"flagman": "local",
	"yard_deputy": "deputy",
	"shield_deputy": "deputy",
	"revenooer": "deputy",
	"still_buster": "deputy",
	"gas_man": "deputy",
	"coot": "coot",
	"drunk_coot": "coot",
	"alien": "grey",
	"drone": "grey",
	"tin_guard": "grey",
}
## Each moment's lines per voice, by count (the cues are bark_<voice>_<moment>_<n>),
## and their captions, as made.
const LINES := {
	"hick":
	{
		"spot": ["There he is!", "Git him, boys!", "Yonder he goes!"],
		"lost": ["Where'd he go?", "Dang it, he's gone!"],
		"search": ["Come on out, city boy.", "Here, city boy, city boy..."],
		"help": ["Bubba! Get out here!", "Cletus! Bring the truck!"],
		"flank": ["I'll cut round back!", "I'll go round the shed!"],
		"cover": ["Keep yer head down!", "Git behind the truck!"],
		"brawl": ["You shot me, Earl!", "That's it, you're dead!"],
		"idle":
		[
			"Pass me another one.",
			"Ain't nothin' on TV.",
			"Who drank my beer?",
			"Reckon it'll rain?"
		],
		"surprised": ["What in tarnation?", "Whoa, Nelly!"],
		"hurt_bad": ["Ow! I'm hit, Mama!", "I'm leakin', Earl!"],
		"regroup": ["Fall back! Fall back!", "Run fer the truck!"],
	},
	"deputy":
	{
		"spot": ["Freeze, boy!", "Suspect spotted!", "Hold it right there!"],
		"lost": ["Lost visual.", "Suspect's gone to ground."],
		"search": ["Spread out and find him.", "Check them bushes, Dwayne."],
		"help": ["Officer needs assistance!", "All units, get over here!"],
		"flank": ["Flankin' left!", "Circle round back!"],
		"cover": ["Takin' cover!", "Get behind the cruiser!"],
		"brawl": ["You're under arrest, Cletus!", "Assaultin' an officer!"],
		"idle":
		[
			"Quiet night.",
			"Donut run after this.",
			"Sure is hot for April.",
			"Who ate my bear claw?"
		],
		"surprised": ["Well, I'll be!", "Sweet mercy!"],
		"hurt_bad": ["Man down! Man down!", "I'm shot! Call my mama!"],
		"regroup": ["Pull back to the cruiser!", "Fall back to the station!"],
	},
	"coot":
	{
		"spot": ["Git off my land!", "I see you, varmint!", "Trespasser! Fetch the salt!"],
		"lost": ["Dang eyes.", "Where'd the varmint git to?"],
		"search": ["I know you're out there.", "Here, varmint, varmint..."],
		"help": ["Junior! Fetch the shotgun!", "Mother! Bring the rock salt!"],
		"flank": ["Comin' round the barn!", "I'll git him from the henhouse!"],
		"cover": ["My back ain't what it was.", "Hold on, lemme sit a spell."],
		"brawl": ["Watch where yer shootin'!", "I'll tan yer hide!"],
		"idle":
		["Back in my day...", "Where'd I put my teeth?", "Kids these days...", "Is it Tuesday?"],
		"surprised": ["Lord have mercy!", "Great jumpin' catfish!"],
		"hurt_bad": ["I'm too old for this!", "Lord, my hip!"],
		"regroup": ["Retreat! Move, ol' knees!", "Back to the porch!"],
	},
	"grey":
	{
		"spot": ["Earthling detected.", "Hooman sighted!", "Specimen located!"],
		"lost": ["The hooman has vanished.", "Target has left the sector."],
		"search": ["Scan the sector.", "Sweep for hooman heat."],
		"help": ["Requesting reinforcements!", "Send more probes!"],
		"flank": ["Encircle the hooman.", "Approach from the rear."],
		"cover": ["Raise the shields!", "Deploy the force field!"],
		"brawl": ["Friendly fire, Zorp!", "You will be probed for that!"],
		"idle":
		[
			"This cow is defective.",
			"Report: still no Bessie.",
			"Why do they tip the cows?",
			"I miss my home planet."
		],
		"surprised": ["Eep! Intruder!", "Alert! A hooman!"],
		"hurt_bad": ["Hull breach!", "My antenna! My antenna!"],
		"regroup": ["Return to the saucer!", "Retreat to the mothership!"],
	},
	"local":
	{
		"spot": ["Hey! We got a live one!", "Boss said shoot on sight!"],
		"lost": ["Now where'd that feller git to?", "Lost him round the side."],
		"search": ["Come on out, we won't bite.", "Check behind the stacks."],
		"help": ["Need a hand over here!", "Somebody fetch the big wrench!"],
		"flank": ["I'll take the long way round!", "Comin' at him from the side!"],
		"cover": ["Git behind somethin' solid!", "Duck, Dwayne!"],
		"brawl": ["That was my good arm, Dwayne!", "Quit shootin' the help!"],
		"idle": ["Lunch whistle ain't blowed yet?", "My back's killin' me."],
		"surprised": ["Well, I'll be dipped!", "Who let you in here?"],
		"hurt_bad": ["I'm hurt bad! Call it in!", "That's a workman's comp claim!"],
		"regroup": ["Back to the trucks!", "Clock out, boys! Clock out!"],
	},
}
## How often a hand reaches for a cuss pack line when one is made.
const CUSS_SHARE := .7
## Seconds at least between any two lines, and between two from one hand.
const GAP := 1.3
const OWN_GAP := 7.0
## How far off a line is heard at all, and captioned.
const HEARD := 18.0
const CAPTIONED := 11.0
## Seconds Mundell's boss line waits for the boss to finish talking.
const MUNDELL_WAITS := 5.0

var dice := RandomNumberGenerator.new()
var _next := 0.0
## Enemy instance id (or "p<slot>", a bot) -> when it may speak again.
var _own := {}
## The 5v5 as last seen: slot -> health, the bomb's state, the round's phase.
var _health := {}
var _bomb := ""
var _phase := ""
var _started := false
## Mundell's boss line waiting for the boss to finish his: [moment, from, until].
var _mundell_next: Array = []


func id() -> String:
	return "enemy_barks"


func attach() -> void:
	dice.seed = 6263
	if game.has_signal("enemy_bark"):
		game.events.connect("enemy_bark", _bark)
	if game.has_signal("ticked"):
		game.events.connect("ticked", _tactical)
		game.events.connect("ticked", _chapter_start)
		game.events.connect("ticked", _mundell_waits)
	# Mundell has his say at a boss fight's start and its end (Barks), once the
	# boss has had his (features/boss_voices.gd).
	if game.has_signal("boss_intro"):
		game.events.connect("boss_intro", func(_e: Enemy) -> void: _mundell_after("boss"))
	if game.has_signal("boss_down"):
		game.events.connect(
			"boss_down", func(_e: Enemy, _s: float) -> void: _mundell_after("boss_down")
		)


## The voice `e` talks in, or "".
static func voice_of(e: Enemy) -> String:
	return str(VOICES.get(e.kind, VOICES.get(e.brain, "")))


func _bark(e: Enemy, moment: String) -> void:
	if e == null or not e.alive or game.clock < _next or game.sound == null:
		return
	if int(game.chatter) == CussLines.OFF or game.sound.talking():
		return
	var who := voice_of(e)
	if who == "":
		return
	var by_moment: Dictionary = LINES[who]
	var lines: Array = by_moment.get(moment, [])
	if lines.is_empty():
		return
	var key: int = e.get_instance_id()
	var own_at: float = _own.get(key, 0.0)
	if game.clock < own_at:
		return
	var p := game.player
	var gap := Vector2(e.x - p.x, e.y - p.y).length()
	if gap > HEARD:
		return
	var n := dice.randi_range(0, lines.size() - 1)
	var cue := "bark_%s_%s_%d" % [who, moment, n]
	var said := str(lines[n])
	var cuss := CussLines.lines("enemies", who, moment)
	if not cuss.is_empty() and dice.randf() < CUSS_SHARE:
		var k := dice.randi_range(0, cuss.size() - 1)
		var cuss_cue := CussLines.cue(who, moment, k, int(game.chatter))
		if game.sound.has(cuss_cue):
			cue = cuss_cue
			said = CussLines.caption(str(cuss[k]), int(game.chatter))
	if not game.sound.has(cue):
		return
	game.sound_at(cue, e.x, e.y, .95)
	_next = game.clock + GAP
	_own[key] = game.clock + OWN_GAP
	if gap <= CAPTIONED and game.clock >= game.caption_until:
		game.caption = said
		game.caption_until = game.clock + 1.5


# ------------------------------------------------------------------ Mundell


## Mundell says his piece for `moment` (Barks: only while the local player is
## the one acting, so a partner's moment is not his to crow over).
func _mundell(moment: String) -> void:
	if game.barks != null:
		game.barks.say(game, moment, true)


## Mundell answers a boss: as soon as nobody is talking, within MUNDELL_WAITS.
func _mundell_after(moment: String) -> void:
	_mundell_next = [moment, game.clock + .35, game.clock + MUNDELL_WAITS]


func _mundell_waits(_dt: float) -> void:
	if _mundell_next.is_empty():
		return
	var from: float = _mundell_next[1]
	var until: float = _mundell_next[2]
	if game.clock < from or (game.clock < until and game.sound.talking()):
		return
	var moment := str(_mundell_next[0])
	_mundell_next = []
	_mundell(moment)


## A couple of seconds into a chapter, Mundell sizes it up.
func _chapter_start(_dt: float) -> void:
	if _started or game.clock < 2.0:
		return
	_started = true
	if Campaign.ORDER.has(game.level.id) and game.players.size() == 1:
		_mundell("start")


# ------------------------------------------------------------------ 5v5 bots


func _tactical(_dt: float) -> void:
	if int(game.chatter) == CussLines.OFF or not Modes.is_tactical(game):
		return
	var st: ModeFeature = Modes.feature(game)
	if st == null:
		return
	for p: Player in game.players:
		var was: float = _health.get(p.slot, p.health)
		if p.health <= 0 and was > 0:
			var said: Array = st.killed_by.get(p.slot, [])
			if not said.is_empty():
				var killer := _player_tagged(str(said[0]))
				if killer != null:
					_bot_says(st, killer, "tactical", "kill")
		elif p.health > 0 and p.health < 30 and was >= 30:
			_bot_says(st, p, "enemies", "hurt_bad")
		_health[p.slot] = p.health
	var state := str(st.bomb.get("state", "")) if st.bomb is Dictionary else ""
	if state != _bomb:
		if state == "planted":
			var slot: int = st.bomb.get("slot", -1)
			if slot >= 0 and slot < game.players.size():
				_bot_says(st, game.players[slot], "tactical", "plant")
		elif state == "defused":
			var bomb_x: float = st.bomb.get("x", 0.0)
			var bomb_y: float = st.bomb.get("y", 0.0)
			var near := _nearest(st, bomb_x, bomb_y)
			if near != null:
				_bot_says(st, near, "tactical", "defuse")
		_bomb = state
	var phase := st.phase
	if phase == "post" and _phase != "post":
		for p: Player in game.players:
			if p.health > 0 and p.team == st.round_winner and _bot(st, p):
				_bot_says(st, p, "tactical", "win")
				break
	_phase = phase


## Is `p` a bot here (not this machine's player, not a person the lobby named)?
func _bot(st: ModeFeature, p: Player) -> bool:
	if p == game.local_player:
		return false
	return p.slot >= st.names.size() or str(st.names[p.slot]) == ""


func _player_tagged(tag: String) -> Player:
	for q: Player in game.players:
		if Modes.tag(q) == tag:
			return q
	return null


## The deputy up nearest (x, y): who cut the fuse.
func _nearest(st: ModeFeature, x: float, y: float) -> Player:
	var best: Player = null
	var gap := INF
	for q: Player in game.players:
		if q.health <= 0 or TacticalMode.side_of(st, q) != 1:
			continue
		var d := Vector2(q.x - x, q.y - y).length()
		if d < gap:
			gap = d
			best = q
	return best


## A bot says a line of `group` for `moment` in its side's voice, from where it
## stands, when it is in earshot and has not just spoken.
func _bot_says(st: ModeFeature, p: Player, group: String, moment: String) -> void:
	if not _bot(st, p) or game.clock < _next or game.sound == null:
		return
	var key := "p%d" % p.slot
	var own_at: float = _own.get(key, 0.0)
	if game.clock < own_at:
		return
	var me := game.local_player
	var gap := Vector2(p.x - me.x, p.y - me.y).length()
	if gap > HEARD:
		return
	var who := "hick" if TacticalMode.side_of(st, p) == 0 else "deputy"
	var lines := CussLines.lines(group, who, moment)
	if lines.is_empty():
		return
	var n := dice.randi_range(0, lines.size() - 1)
	var cue := CussLines.cue(who, moment, n, int(game.chatter))
	if not game.sound.has(cue):
		return
	game.sound_at(cue, p.x, p.y, .95)
	_next = game.clock + GAP
	_own[key] = game.clock + OWN_GAP
	if gap <= CAPTIONED and game.clock >= game.caption_until:
		game.caption = "%s: %s" % [p.name, CussLines.caption(str(lines[n]), int(game.chatter))]
		game.caption_until = game.clock + 1.5
