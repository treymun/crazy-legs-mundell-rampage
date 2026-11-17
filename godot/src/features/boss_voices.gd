## The bosses talk (scripts/audio_spec.py BOSS_LINES): a line as the fight
## starts (a second one on a retry or a rematch), a taunt now and then when
## they hurt the player (four, dealt in turn), a mad line after their roar at
## half health, a worried line at their last phase and a last word as they
## fall, captioned like the county's other talk. A boss's line cuts in over a
## hand's bark or Mundell's wisecrack (Sound.hush_speech); the mad line and
## Maw's calls to her crew wait for the talking to stop (`queue`). Sound and
## captions only: its own dice, nothing saved.
extends GameFeature

## Boss kind -> the name its lines are made under.
const SPEAKERS := {
	"boss": "sheriff",
	"jerry": "jerry",
	"rudy": "rudy",
	"foreman": "foreman",
	"baron": "baron",
	"swamp_king": "swamp_king",
	"derby_champ": "boggs",
	"revenue_man": "revenue_man",
	"maw": "maw",
}
## The captions, as the lines were made, in MOMENTS order.
const LINES := {
	"sheriff":
	[
		"You're under arrest, Earth boy.",
		"Resistin' arrest, I see.",
		"That's a citation, son.",
		"Backup! I need backup!",
		"Tell my saucer... I loved her.",
		"Pull over, Earth boy. Nice and slow.",
		"That'll go on your permanent record.",
		"You have the right to remain squishy.",
		"Now you done riled the law!",
		"Mayday! Saucer to base, mayday!"
	],
	"jerry":
	[
		"Son, you're on my field now.",
		"Run it again, boy!",
		"That's a penalty!",
		"Somebody get me a towel.",
		"Coach always said... hustle.",
		"Kickoff time, son. Hope you stretched.",
		"Ten yards and a loss of teeth!",
		"My granny tackles harder than you!",
		"Now you got me sweatin', boy!",
		"Call a timeout! Call a timeout!"
	],
	"rudy":
	[
		"Step right up and lose, sucker!",
		"Ain't nobody wins this game!",
		"Three tries for a dime!",
		"Folks, the show's runnin' long...",
		"The show's... over... folks.",
		"Back again? Every sucker gets a second ticket!",
		"Winner gets nothin'! Step right up!",
		"Knock 'em down, win a coffin!",
		"Ladies and gents, he's ruinin' my show!",
		"Somebody cue the band! Anybody!"
	],
	"foreman":
	[
		"You're on the clock, slacker.",
		"Back to work!",
		"That's comin' outta your pay!",
		"Somebody kill that dang saw!",
		"I'm... clockin' out.",
		"Punch in, slacker. Shift's startin'.",
		"No breaks on my floor!",
		"Sweat or bleed, I don't care which!",
		"Who said you could quit workin'?",
		"Call the union! Call somebody!"
	],
	"baron":
	[
		"Nobody drinks my shine for free.",
		"Aged twelve years, like my temper!",
		"You'll be pickled by sundown.",
		"My stills! Not my stills!",
		"Bury me... in a barrel.",
		"Ah. A guest. Do mind the stills.",
		"Have a taste of the barrel, boy!",
		"A hundred proof, and so am I!",
		"You've gone and spoiled my batch!",
		"Not the copper! Anything but the copper!"
	],
	"swamp_king":
	[
		"Who's on my water?",
		"Gator bait, that's all you are!",
		"Ride's free, landin's extra!",
		"She's takin' on water!",
		"Tell the gators... I'm comin' home.",
		"Back on my bayou, boy? Big mistake.",
		"My gators are gettin' hungry!",
		"Swim home, boy! I dare you!",
		"Come get him, my sweet babies!",
		"Bail her out! Somebody bail!"
	],
	"boggs":
	[
		"Buckle up, sunshine!",
		"Trade paint with me, boy!",
		"Forty-seven wins and countin'!",
		"Radiator's blown, dang it!",
		"Checkered flag... for me...",
		"Round two, sunshine! Start your engines!",
		"Eat my dust, boy!",
		"I've wrecked better than you on a Tuesday!",
		"Now you scratched my paint!",
		"She's smokin'! She's smokin' bad!"
	],
	"revenue_man":
	[
		"Federal government, son. That still is evidence.",
		"You have the right to remain thirsty.",
		"Taxes are due, boy!",
		"That's government property you're shootin'!",
		"Tell Washington... I tried.",
		"Back again? Contraband don't get a second chance.",
		"Consider yourself audited!",
		"I've busted bigger stills than you!",
		"Now that's assault on a federal officer!",
		"Somebody radio Washington! Anybody!"
	],
	"maw":
	[
		"Who tracked mud on my clean deck?",
		"Eat your vegetables, hooman!",
		"Wait till your father lands!",
		"My curlers! Not my curlers!",
		"Tell my young'uns... supper's cold.",
		"Back for seconds, hooman?",
		"Sit up straight, hooman!",
		"Don't make me get the wooden spoon!",
		"My housecoat's on fire, you little varmint!",
		"Mercy, I'm comin' apart at the seams!"
	],
}
const MOMENTS := [
	"intro",
	"taunt_0",
	"taunt_1",
	"worried",
	"last",
	"intro_1",
	"taunt_2",
	"taunt_3",
	"mad",
	"worried_1"
]
const INTRO := 0
const WORRIED := 3
const LAST := 4
const INTRO_AGAIN := 5
const MAD := 8
const WORRIED_AGAIN := 9
## The taunts in the order they are dealt.
const TAUNTS := [1, 6, 2, 7]
## Maw Glorb's other lines (features/mothership.gd): cue -> caption.
const MAW_LINES := {
	"boss_maw_wake": "You killed my baby boy!",
	"boss_maw_crew_0": "Git him, young'uns!",
	"boss_maw_crew_1": "Young'uns! Git in here!",
}
## Seconds at least between two taunts, and the share of hits that get one.
const TAUNT_GAP := 9.0
const TAUNT_CHANCE := .45
## The mad line comes after the boss's roar at half health.
const MAD_AFTER := 1.1
## How long a queued line waits for the talking to stop before it is dropped.
const MAD_WAITS := 4.0

var dice := RandomNumberGenerator.new()
## The boss whose fight is on (the last one that started).
var _boss: Enemy = null
var _taunt_next := 0.0
var _taunts := 0
## Fights begun since this game started (a retry from the checkpoint is one more).
var _fights := 0
## Lines waiting their turn: [enemy, cue, caption, from, until].
var _queue: Array = []


func id() -> String:
	return "boss_voices"


func attach() -> void:
	dice.seed = 4471
	for wired: Array in [["boss_intro", _intro], ["boss_phase", _phase], ["boss_down", _down]]:
		var signal_name := str(wired[0])
		var handler: Callable = wired[1]
		if game.has_signal(signal_name):
			game.connect(signal_name, handler)
	game.events.player_hurt.connect(_hurt)
	game.events.boss_enraged.connect(_enraged)
	tick_with(_tick)


## The name `e`'s lines are made under, or "".
static func speaker_of(e: Enemy) -> String:
	return str(SPEAKERS.get(e.kind, ""))


## Says one of `e`'s lines (a MOMENTS index) from where it stands.
func say(e: Enemy, moment: int) -> void:
	var who := speaker_of(e)
	if who == "":
		return
	line(e, "boss_%s_%s" % [who, MOMENTS[moment]], str(LINES[who][moment]))


## Says `cue` in `e`'s voice from where it stands, over any hand or Mundell
## talking, and captions it with `caption` ("" leaves the caption alone).
func line(e: Enemy, cue: String, caption: String) -> void:
	if game.sound == null or not game.sound.has(cue):
		return
	game.sound.hush_speech()
	var place: Vector2 = game.sound_position(e.x, e.y, 1.3, false)
	var length: float = game.sound.play_voice(cue, maxf(.45, place.x), place.y)
	if caption != "":
		game.caption = caption
		game.caption_until = game.clock + maxf(1.4, length + .2)
	_taunt_next = maxf(_taunt_next, game.clock + 3.0)


## Says `cue` once nobody is talking, `after` seconds from now at the
## earliest; dropped if the talking has not stopped `waits` seconds later.
func queue(e: Enemy, cue: String, caption: String, after: float, waits := MAD_WAITS) -> void:
	_queue.append([e, cue, caption, game.clock + after, game.clock + after + waits])
	wake()


func _tick(_dt: float) -> void:
	if _queue.is_empty():
		sleep()
		return
	var next: Array = _queue[0]
	var e: Enemy = next[0]
	var until: float = next[4]
	if e == null or not e.alive or game.clock > until:
		_queue.pop_front()
		return
	var from: float = next[3]
	if game.clock < from or (game.sound != null and game.sound.talking()):
		return
	_queue.pop_front()
	line(e, str(next[1]), str(next[2]))


func _intro(e: Enemy) -> void:
	_boss = e
	_fights += 1
	_queue.clear()
	say(e, INTRO if _fights == 1 or dice.randf() < .5 else INTRO_AGAIN)


func _phase(e: Enemy, phase: int) -> void:
	_boss = e
	if phase >= 3:
		say(e, WORRIED if _fights <= 1 or dice.randf() < .5 else WORRIED_AGAIN)


func _enraged(e: Enemy) -> void:
	var who := speaker_of(e)
	if who != "" and e.alive:
		queue(e, "boss_%s_mad" % who, str(LINES[who][MAD]), MAD_AFTER)


func _down(e: Enemy, _seconds: float = 0.0) -> void:
	_queue.clear()
	say(e, LAST)
	if e == _boss:
		_boss = null


func _hurt(_amount: float, _cause: String) -> void:
	if not game.acting_local():
		return
	var e := _boss
	if e == null or not e.alive or game.clock < _taunt_next:
		return
	if Vector2(e.x - game.player.x, e.y - game.player.y).length() > 16.0:
		return
	if dice.randf() > TAUNT_CHANCE or game.sound == null or game.sound.talking():
		return
	_taunt_next = game.clock + TAUNT_GAP
	var taunt: int = TAUNTS[_taunts % TAUNTS.size()]
	say(e, taunt)
	_taunts += 1
