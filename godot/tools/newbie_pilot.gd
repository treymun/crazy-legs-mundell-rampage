## A brand-new player for tools/onboard_walk.gd: the balance bot at ROOKIE
## (tools/balance_pilot.gd) that only does what the game has shown it. It
## follows the objective pin (the arrow up top points along Game.route, so
## that is fair) and the USE prompt (a door is opened when OPEN DOOR shows),
## shoots what shoots at it, and changes guns when one runs dry (every
## shooter does), but it eats, boots a hand, picks a thing up or whistles for
## BLUE only once a tip has told it how (`taught`: the Lessons ids shown so
## far). What it wanted to do and did not know how is counted in `held_back`
## (the audit's "never explained").
extends "res://tools/balance_pilot.gd"

## What it was held back from, by tip id: [times wanted, first game second].
var held_back := {}

## Slower and wilder than ROOKIE: someone who has never held a mouse in a
## shooter (skill=-1 in onboard_walk.gd).
const GREENHORN := {
	"name": "greenhorn",
	"react": 0.65,
	"err": 0.09,
	"cap": 0.08,
	"strafe": 0.0,
	"boots": false,
	"eat_at": 25,
	"forage": 5.0
}


func _init(level := 0, seed_value := 1) -> void:
	super._init(maxi(level, 0), seed_value)
	if level < 0:
		skill = GREENHORN


func steer(game: Game) -> Game.Controls:
	var c := super.steer(game)
	if c.item >= 0 and not _knows(["heal", "pockets"]):
		_want(game, "heal")
		c.item = -1
		eaten -= 1
	if c.use and foe != null and not _knows(["kick"]):
		# A boot or a finisher: USE at a hand is not something a shooter guesses.
		_want(game, "kick")
		c.use = false
		boots_asked -= 1
	if c.use and foe == null and game.use_prompt() == "":
		# USE pressed with no prompt up (the base bot presses it near any door
		# or the objective): a player would not know to.
		c.use = false
	return c


func _knows(ids: Array) -> bool:
	for id: String in ids:
		if Lessons.taught.has(id):
			return true
	return false


func _want(game: Game, id: String) -> void:
	var row: Array = held_back.get(id, [0, game.clock])
	row[0] = int(row[0]) + 1
	held_back[id] = row
