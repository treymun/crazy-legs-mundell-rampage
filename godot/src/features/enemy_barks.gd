## The county's hands talk (scripts/audio_spec.py BARKS): the squads announce
## moments (game_state.gd enemy_bark: spot, lost, search, help, flank, cover,
## brawl, idle, surprised, hurt_bad, regroup) and the hand says a line for it
## in its kind's voice, from where it stands, captioned when nothing else is.
## Throttled so a crowd never talks over itself. Sound and captions only: its
## own dice, nothing saved. CHATTER (game.chatter, CussLines): OFF says
## nothing; CLEAN and CUSSIN' mix in the cuss pack's lines where they are made
## (CUSS_SHARE of the time), CLEAN's copies quacked over and captioned #@!%.
## In the 5v5 and 2v2 modes the bots talk too (`_tactical`, watched each
## tick): a kill, a bad hit, the plant, the defuse, the round won; outlaws in
## the hick's voice, deputies in the deputy's. A bot is a player this machine
## does not drive and the lobby did not name.
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
## How often a hand reaches for a cuss pack line when one is made.
const CUSS_SHARE := .7
## Seconds at least between any two lines, and between two from one hand.
const GAP := 1.3
const OWN_GAP := 7.0
## How far off a line is heard at all, and captioned.
const HEARD := 18.0
const CAPTIONED := 11.0

var dice := RandomNumberGenerator.new()
var _next := 0.0
## Enemy instance id (or "p<slot>", a bot) -> when it may speak again.
var _own := {}
## The 5v5 as last seen: slot -> health, the bomb's state, the round's phase.
var _health := {}
var _bomb := ""
var _phase := ""


func id() -> String:
	return "enemy_barks"


func attach() -> void:
	dice.seed = 6263
	if game.has_signal("enemy_bark"):
		game.connect("enemy_bark", _bark)
	if game.has_signal("ticked"):
		game.connect("ticked", _tactical)


## The voice `e` talks in, or "".
static func voice_of(e: Enemy) -> String:
	return String(VOICES.get(e.kind, VOICES.get(e.brain, "")))


func _bark(e, moment: String) -> void:
	if e == null or not e.alive or game.clock < _next or game.sound == null:
		return
	if int(game.chatter) == CussLines.OFF:
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
	var said := String(lines[n])
	var cuss := CussLines.lines("enemies", who, moment)
	if not cuss.is_empty() and dice.randf() < CUSS_SHARE:
		var k := dice.randi_range(0, cuss.size() - 1)
		var cuss_cue := CussLines.cue(who, moment, k, int(game.chatter))
		if game.sound.has(cuss_cue):
			cue = cuss_cue
			said = CussLines.caption(String(cuss[k]), int(game.chatter))
	if not game.sound.has(cue):
		return
	game.sound_at(cue, e.x, e.y, .95)
	_next = game.clock + GAP
	_own[key] = game.clock + OWN_GAP
	if gap <= CAPTIONED and game.clock >= game.caption_until:
		game.caption = said
		game.caption_until = game.clock + 1.5


# ------------------------------------------------------------------ 5v5 bots


func _tactical(_dt: float) -> void:
	if int(game.chatter) == CussLines.OFF or not Modes.is_tactical(game):
		return
	var st = Modes.feature(game)
	if st == null:
		return
	for p: Player in game.players:
		var was := float(_health.get(p.slot, p.health))
		if p.health <= 0 and was > 0:
			var said: Array = st.killed_by.get(p.slot, [])
			if not said.is_empty():
				var killer := _player_tagged(String(said[0]))
				if killer != null:
					_bot_says(st, killer, "tactical", "kill")
		elif p.health > 0 and p.health < 30 and was >= 30:
			_bot_says(st, p, "enemies", "hurt_bad")
		_health[p.slot] = p.health
	var state := String(st.bomb.get("state", "")) if st.bomb is Dictionary else ""
	if state != _bomb:
		if state == "planted":
			var slot := int(st.bomb.get("slot", -1))
			if slot >= 0 and slot < game.players.size():
				_bot_says(st, game.players[slot], "tactical", "plant")
		elif state == "defused":
			var near := _nearest(st, float(st.bomb.get("x", 0.0)), float(st.bomb.get("y", 0.0)))
			if near != null:
				_bot_says(st, near, "tactical", "defuse")
		_bomb = state
	var phase := String(st.phase)
	if phase == "post" and _phase != "post":
		for p: Player in game.players:
			if p.health > 0 and p.team == int(st.round_winner) and _bot(st, p):
				_bot_says(st, p, "tactical", "win")
				break
	_phase = phase


## Is `p` a bot here (not this machine's player, not a person the lobby named)?
func _bot(st, p: Player) -> bool:
	if p == game.local_player:
		return false
	return p.slot >= st.names.size() or String(st.names[p.slot]) == ""


func _player_tagged(tag: String) -> Player:
	for q: Player in game.players:
		if Modes.tag(q) == tag:
			return q
	return null


## The deputy up nearest (x, y): who cut the fuse.
func _nearest(st, x: float, y: float) -> Player:
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
func _bot_says(st, p: Player, group: String, moment: String) -> void:
	if not _bot(st, p) or game.clock < _next or game.sound == null:
		return
	var key := "p%d" % p.slot
	if game.clock < float(_own.get(key, 0.0)):
		return
	var me = game.local_player
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
		game.caption = "%s: %s" % [p.name, CussLines.caption(String(lines[n]), int(game.chatter))]
		game.caption_until = game.clock + 1.5
