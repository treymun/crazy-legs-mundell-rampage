## A boss rematch in play (boss_rematch.gd sets it up): the clock runs from
## the fight's start (the boss awake and the player in its arena or within
## BossFight.ARENA of it) to the boss's fall, and shows at the foot of the
## view. main_flow.gd ends the rematch a moment after the fall. In any other
## game it only marks a won chapter beaten, for the rematch board. Saves
## nothing: a rematch is never saved.
extends GameFeature

## Seconds after the fall before the result shows.
const AFTER := 3.0

var active := false
var kind := ""
## game.clock at the fight's start and at the fall (-1: not yet).
var began := -1.0
var fell := -1.0
var said := false


func id() -> String:
	return "boss_rematch"


func attach() -> void:
	game.ticked.connect(_tick)
	game.enemy_killed.connect(_killed)
	game.level_won.connect(_won)


func _tick(_dt: float) -> void:
	if active and fell >= 0.0 and not said:
		# Over the chapter's own word on the fall (Jerry is not coming).
		said = true
		game.message(
			"%s IS DOWN IN %s!" % [BossRematch.title(kind), BossRematch.clock_text(seconds())],
			AFTER
		)
	if not active or began >= 0.0 or fell >= 0.0:
		return
	# In its arena, or within ARENA of it (the sheriff stands below the half of
	# the pen the boss bar counts).
	var foe := BossFight.awake(game)
	var p = game.player
	if foe != null and foe.kind == kind and not BossFight.clear_of(game, foe, p.x, p.y):
		fight_began(foe)


## The clock starts: the one place the fight's start is noticed, so the boss
## framework's intro signal can call it instead.
func fight_began(foe: Enemy) -> void:
	if active and began < 0.0 and foe.kind == kind:
		began = game.clock


func _killed(enemy: Enemy) -> void:
	if not active or fell >= 0.0 or enemy.kind != kind:
		return
	if began < 0.0:
		# Felled from outside the arena: timed from the start of play.
		began = 0.0
	fell = game.clock


func _won() -> void:
	if not active and not game.in_hub and not game.revisiting:
		BossRematch.mark_beaten(game.level.id)


func seconds() -> float:
	if began < 0.0:
		return 0.0
	return (fell if fell >= 0.0 else game.clock) - began


## The result is due: the boss fell AFTER seconds ago (or the player went down
## after it fell).
func finished() -> bool:
	return active and fell >= 0.0 and (game.clock - fell >= AFTER or game.player.health <= 0)


func death_lines() -> Array:
	if not active:
		return []
	if game.use_key == "Y":
		return ["A  FIGHT AGAIN", "B  TITLE"]
	if game.use_key == "USE":
		return ["TAP  FIGHT AGAIN", "MENU  TITLE"]
	return ["ENTER  FIGHT AGAIN", "ESC  TITLE"]


func draw_view(c: Canvas) -> void:
	if not active or game.player.health <= 0:
		return
	var text := BossRematch.clock_text(seconds())
	var colour := HUD.AMBER if fell >= 0.0 else (HUD.INK if began >= 0.0 else Menu.FADED)
	HUD.text(c, text, 5, Renderer.VIEW - 11, "body", colour)
