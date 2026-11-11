## Kills close together get called out big across the middle of the screen,
## county-fair style: TWOFER, HAT TRICK, HOG WILD, then a full RAMPAGE with a
## yee-haw. Shown with PLAYER ONE-LINERS on; game_view.gd draws game.callout.
extends GameFeature

## Seconds a kill keeps the streak going.
const WINDOW := 1.8
const CALLS := ["", "", "TWOFER!", "HAT TRICK!", "HOG WILD!", "RAMPAGE!"]

var streak := 0
var last_kill := -10.0


func id() -> String:
	return "callouts"


func attach() -> void:
	game.enemy_killed.connect(_killed)


func _killed(enemy: Enemy) -> void:
	if not enemy.hostile:
		return
	streak = streak + 1 if game.clock - last_kill <= WINDOW else 1
	last_kill = game.clock
	if streak < 2 or not game.barks.enabled:
		return
	game.callout = CALLS[mini(streak, CALLS.size() - 1)]
	game.callout_until = game.clock + 1.3
	if streak >= 4:
		game.sound.play("yee_haw", .7)
