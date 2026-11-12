## The bosses talk (scripts/audio_spec.py BOSS_LINES): a line as the fight
## starts, a taunt now and then when they hurt the player, a worried line at
## their last phase and a last word as they fall, captioned like the county's
## other talk. Sound and captions only: its own dice, nothing saved.
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
	"maw": "maw",
}
## The captions, as the lines were made (intro, two taunts, worried, last).
const LINES := {
	"sheriff":
	[
		"You're under arrest, Earth boy.",
		"Resistin' arrest, I see.",
		"That's a citation, son.",
		"Backup! I need backup!",
		"Tell my saucer... I loved her."
	],
	"jerry":
	[
		"Son, you're on my field now.",
		"Run it again, boy!",
		"That's a penalty!",
		"Somebody get me a towel.",
		"Coach always said... hustle."
	],
	"rudy":
	[
		"Step right up and lose, sucker!",
		"Ain't nobody wins this game!",
		"Three tries for a dime!",
		"Folks, the show's runnin' long...",
		"The show's... over... folks."
	],
	"foreman":
	[
		"You're on the clock, slacker.",
		"Back to work!",
		"That's comin' outta your pay!",
		"Somebody kill that dang saw!",
		"I'm... clockin' out."
	],
	"baron":
	[
		"Nobody drinks my shine for free.",
		"Aged twelve years, like my temper!",
		"You'll be pickled by sundown.",
		"My stills! Not my stills!",
		"Bury me... in a barrel."
	],
	"swamp_king":
	[
		"Who's on my water?",
		"Gator bait, that's all you are!",
		"Ride's free, landin's extra!",
		"She's takin' on water!",
		"Tell the gators... I'm comin' home."
	],
	"boggs":
	[
		"Buckle up, sunshine!",
		"Trade paint with me, boy!",
		"Forty-seven wins and countin'!",
		"Radiator's blown, dang it!",
		"Checkered flag... for me..."
	],
	"maw":
	[
		"Who tracked mud on my clean deck?",
		"Eat your vegetables, hooman!",
		"Wait till your father lands!",
		"My curlers! Not my curlers!",
		"Tell my young'uns... supper's cold."
	],
}
const MOMENTS := ["intro", "taunt_0", "taunt_1", "worried", "last"]
## Seconds at least between two taunts, and the share of hits that get one.
const TAUNT_GAP := 9.0
const TAUNT_CHANCE := .45

var dice := RandomNumberGenerator.new()
## The boss whose fight is on (the last one that started).
var _boss: Enemy = null
var _taunt_next := 0.0
var _taunts := 0


func id() -> String:
	return "boss_voices"


func attach() -> void:
	dice.seed = 4471
	for wired: Array in [["boss_intro", _intro], ["boss_phase", _phase], ["boss_down", _down]]:
		if game.has_signal(String(wired[0])):
			game.connect(String(wired[0]), wired[1])
	game.player_hurt.connect(_hurt)


## Says one of `e`'s lines (a MOMENTS index) from where it stands.
func say(e: Enemy, moment: int) -> void:
	var who := String(SPEAKERS.get(e.kind, ""))
	if who == "" or game.sound == null:
		return
	var cue := "boss_%s_%s" % [who, MOMENTS[moment]]
	if not game.sound.has(cue):
		return
	var place: Vector2 = game.sound_position(e.x, e.y, 1.3, false)
	var length: float = game.sound.play_voice(cue, maxf(.45, place.x), place.y)
	game.caption = String(LINES[who][moment])
	game.caption_until = game.clock + maxf(1.4, length + .2)
	_taunt_next = maxf(_taunt_next, game.clock + 3.0)


func _intro(e) -> void:
	_boss = e
	say(e, 0)


func _phase(e, phase: int) -> void:
	_boss = e
	if phase >= 3:
		say(e, 3)


func _down(e, _seconds = 0.0) -> void:
	say(e, 4)
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
	if dice.randf() > TAUNT_CHANCE:
		return
	_taunt_next = game.clock + TAUNT_GAP
	say(e, 1 + _taunts % 2)
	_taunts += 1
