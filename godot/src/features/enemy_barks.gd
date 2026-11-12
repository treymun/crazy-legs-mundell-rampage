## The county's hands talk (scripts/audio_spec.py BARKS): the squads announce
## moments (game_state.gd enemy_bark: spot, lost, search, help, flank, cover,
## brawl, idle, surprised, hurt_bad, regroup) and the hand says a line for it
## in its kind's voice, from where it stands, captioned when nothing else is.
## Throttled so a crowd never talks over itself. Sound and captions only: its
## own dice, nothing saved.
extends GameFeature

## Kind (or brain) -> voice. Kinds not here (skeeters, saucers, gators, the
## probes, lanterns, crawlers, the chalk spitters) have nothing to say.
const VOICES := {
	"billy": "hick",
	"big_billy": "hick",
	"clone": "hick",
	"millhand": "hick",
	"chain_hand": "hick",
	"boilerback": "hick",
	"valve_rat": "hick",
	"bottle_tosser": "hick",
	"barker": "hick",
	"noodler": "hick",
	"chum_tosser": "hick",
	"pit_mechanic": "hick",
	"tire_roller": "hick",
	"nitro_huffer": "hick",
	"flagman": "hick",
	"yard_deputy": "deputy",
	"shield_deputy": "deputy",
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
		"spot": ["There he is!", "Git him, boys!"],
		"lost": ["Where'd he go?"],
		"search": ["Come on out, city boy."],
		"help": ["Bubba! Get out here!"],
		"flank": ["I'll cut round back!"],
		"cover": ["Keep yer head down!"],
		"brawl": ["You shot me, Earl!", "That's it, you're dead!"],
		"idle": ["Pass me another one.", "Ain't nothin' on TV."],
		"surprised": ["What in tarnation?"],
		"hurt_bad": ["Ow! I'm hit, Mama!"],
		"regroup": ["Fall back! Fall back!"],
	},
	"deputy":
	{
		"spot": ["Freeze, boy!", "Suspect spotted!"],
		"lost": ["Lost visual."],
		"search": ["Spread out and find him."],
		"help": ["Officer needs assistance!"],
		"flank": ["Flankin' left!"],
		"cover": ["Takin' cover!"],
		"brawl": ["You're under arrest, Cletus!", "Assaultin' an officer!"],
		"idle": ["Quiet night.", "Donut run after this."],
		"surprised": ["Well, I'll be!"],
		"hurt_bad": ["Man down! Man down!"],
		"regroup": ["Pull back to the cruiser!"],
	},
	"coot":
	{
		"spot": ["Git off my land!", "I see you, varmint!"],
		"lost": ["Dang eyes."],
		"search": ["I know you're out there."],
		"help": ["Junior! Fetch the shotgun!"],
		"flank": ["Comin' round the barn!"],
		"cover": ["My back ain't what it was."],
		"brawl": ["Watch where yer shootin'!", "I'll tan yer hide!"],
		"idle": ["Back in my day...", "Where'd I put my teeth?"],
		"surprised": ["Lord have mercy!"],
		"hurt_bad": ["I'm too old for this!"],
		"regroup": ["Retreat! Move, ol' knees!"],
	},
	"grey":
	{
		"spot": ["Earthling detected.", "Hooman sighted!"],
		"lost": ["The hooman has vanished."],
		"search": ["Scan the sector."],
		"help": ["Requesting reinforcements!"],
		"flank": ["Encircle the hooman."],
		"cover": ["Raise the shields!"],
		"brawl": ["Friendly fire, Zorp!", "You will be probed for that!"],
		"idle": ["This cow is defective.", "Report: still no Bessie."],
		"surprised": ["Eep! Intruder!"],
		"hurt_bad": ["Hull breach!"],
		"regroup": ["Return to the saucer!"],
	},
}
## Seconds at least between any two lines, and between two from one hand.
const GAP := 1.3
const OWN_GAP := 7.0
## How far off a line is heard at all, and captioned.
const HEARD := 18.0
const CAPTIONED := 11.0

var dice := RandomNumberGenerator.new()
var _next := 0.0
## Enemy instance id -> when it may speak again.
var _own := {}


func id() -> String:
	return "enemy_barks"


func attach() -> void:
	dice.seed = 6263
	if game.has_signal("enemy_bark"):
		game.connect("enemy_bark", _bark)


## The voice `e` talks in, or "".
static func voice_of(e: Enemy) -> String:
	return String(VOICES.get(e.kind, VOICES.get(e.brain, "")))


func _bark(e, moment: String) -> void:
	if e == null or not e.alive or game.clock < _next or game.sound == null:
		return
	var who := voice_of(e)
	if who == "":
		return
	var lines: Array = LINES[who].get(moment, [])
	if lines.is_empty():
		return
	var key: int = e.get_instance_id()
	if game.clock < float(_own.get(key, 0.0)):
		return
	var p = game.player
	var gap := Vector2(e.x - p.x, e.y - p.y).length()
	if gap > HEARD:
		return
	var n := dice.randi_range(0, lines.size() - 1)
	var cue := "bark_%s_%s_%d" % [who, moment, n]
	if not game.sound.has(cue):
		return
	game.sound_at(cue, e.x, e.y, .95)
	_next = game.clock + GAP
	_own[key] = game.clock + OWN_GAP
	if gap <= CAPTIONED and game.clock >= game.caption_until:
		game.caption = String(lines[n])
		game.caption_until = game.clock + 1.5
