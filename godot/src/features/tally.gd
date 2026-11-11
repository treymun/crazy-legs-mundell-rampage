## The chapter tally's show: when a chapter is won its rows come down one at a
## time with a thud, then a ribbon is stamped on by how it went (hud.gd
## intermission draws it). Time here is real time: play stops at the tally.
extends GameFeature

const ROW_GAP := 380
const RIBBONS := [
	[.9, "BLUE RIBBON"],
	[.7, "GOOD OL' BOY"],
	[.45, "WEEKEND HUNTER"],
	[0.0, "CITY SLICKER"],
]

var won_at := -1
var thuds := 0


func id() -> String:
	return "tally"


func attach() -> void:
	game.level_won.connect(func() -> void: won_at = Time.get_ticks_msec())


## How many rows are down by now (all of them when there is no show running),
## thudding for each new one.
func rows_shown(total: int) -> int:
	if won_at < 0 or game.flash_scale <= 0.0:
		return total
	var shown := mini(total + 1, int((Time.get_ticks_msec() - won_at) / ROW_GAP) + 1)
	while thuds < shown:
		thuds += 1
		game.sound.play("stamp_thud", .8 if thuds <= total else 1.0)
	return shown


## The ribbon for the chapter: kills, secrets and aim, out of one.
func ribbon() -> String:
	var kills := float(game.kills) / maxf(1.0, game.total_kills)
	var secrets := (
		float(game.secrets) / maxf(1.0, game.total_secrets) if game.total_secrets > 0 else 1.0
	)
	var stats = game.features.get("stats")
	var aim: float = stats.accuracy() / 100.0 if stats != null and stats.shots > 0 else .5
	var score := kills * .55 + secrets * .25 + aim * .2
	for pair: Array in RIBBONS:
		if score >= float(pair[0]):
			return String(pair[1])
	return "CITY SLICKER"
