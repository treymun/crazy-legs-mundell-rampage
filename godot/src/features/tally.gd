## The chapter tally's show: when a chapter is won its rows come down one at a
## time with a thud, then a ribbon is stamped on by how it went, then NEW BEST
## when a best fell (hud.gd intermission, src/tally_card.gd draws it). Time
## here is real time: play stops at the tally. A key, button or tap while the
## rows come down puts them all down at once (hurry()); the next goes on.
##
## The front end fills in what the show cannot know from the game (pass 15):
## `choices` (the ways on and their keys, main_flow.gd watch_tally) and
## `card` (par and the bests, BetweenChapters.settle).
extends GameFeature

const ChapterStats := preload("res://src/features/chapter_stats.gd")
## Milliseconds between the rows (380 before pass 15: a seven-row card took
## three seconds to read before it could be left).
const ROW_GAP := 260
## Milliseconds after the win before the card takes a key, button or tap:
## fire or USE still hammered as the chapter ends must not throw it away.
const KEY_WAIT := 600
const RIBBONS := [
	[.9, "BLUE RIBBON"],
	[.7, "GOOD OL' BOY"],
	[.45, "WEEKEND HUNTER"],
	[0.0, "CITY SLICKER"],
]

var won_at := -1
var thuds := 0
## Rows on the card when it was last drawn (0: never drawn).
var rows_total := 0
## [[key word, label, action, slot], ...]: the ways on, the first the one
## tap's (BetweenChapters.choices).
var choices: Array = []
## BETWEEN CHAPTERS is STRAIGHT ON (the online host's line orders its two
## ways by it: lobby_screens.gd).
var straight := true
## {"old": the bests before, "time"/"kills"/"secrets": true for a new best,
## "difficulty": its word, "kept_bests": this run's bests are kept (a
## player's own chapter, alone: BetweenChapters.settle)}.
var card := {}


func id() -> String:
	return "tally"


func attach() -> void:
	game.events.level_won.connect(func() -> void: won_at = Time.get_ticks_msec())


## How many beats of the show are down by now: the rows, then the ribbon,
## then the NEW BEST stamp when a best fell (all of them when there is no
## show running), thudding for each new one.
func rows_shown(total: int) -> int:
	rows_total = total
	var beats := total + (2 if fresh() else 1)
	if won_at < 0 or game.flash_scale <= 0.0:
		return beats
	var shown := mini(beats, int((Time.get_ticks_msec() - won_at) / ROW_GAP) + 1)
	while thuds < shown:
		thuds += 1
		game.sound.play("stamp_thud", .8 if thuds <= total else 1.0)
		if thuds > total + 1:
			game.sound.play("yee_haw", .9)  # NEW BEST
	return shown


## Whether a key, button or tap counts yet (KEY_WAIT after the win).
func taking_keys() -> bool:
	return won_at < 0 or Time.get_ticks_msec() - won_at >= KEY_WAIT


## While the rows are still coming down: all of them down at once, true (the
## key that did it does nothing else). False when the show is over or was
## never drawn (a check, a versus match's results).
func hurry() -> bool:
	if won_at < 0 or rows_total <= 0 or game.flash_scale <= 0.0:
		return false
	var beats := rows_total + (2 if fresh() else 1)
	if thuds >= beats:
		return false
	won_at = Time.get_ticks_msec() - beats * ROW_GAP
	thuds = beats
	game.sound.play("stamp_thud", 1.0)  # one thud for the lot
	if fresh():
		game.sound.play("yee_haw", .9)
	return true


## A best fell this run (not on a first run: there was none to beat).
func fresh() -> bool:
	return ChapterBests.fresh(card)


## The ribbon for the chapter: kills, secrets, aim and, with a par, the pace,
## out of one.
func ribbon() -> String:
	var kills := float(game.kills) / maxf(1.0, game.total_kills)
	var secrets := (
		float(game.secrets) / maxf(1.0, game.total_secrets) if game.total_secrets > 0 else 1.0
	)
	var stats: ChapterStats = game.features.get("stats")
	var aim: float = stats.accuracy() / 100.0 if stats != null and stats.shots > 0 else .5
	var score := kills * .55 + secrets * .25 + aim * .2
	var pace := ChapterBests.pace(game.level.id, game.clock)
	if pace >= 0.0:
		var keep := 1.0 - ChapterBests.PACE_SHARE
		score = score * keep + pace * ChapterBests.PACE_SHARE
	for pair: Array in RIBBONS:
		var least: float = pair[0]
		if score >= least:
			return str(pair[1])
	return "CITY SLICKER"
