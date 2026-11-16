## Something that watches one player's hands step on this machine's game
## (game.gd calls it round `_step_hands` for the player whose slot it names):
## an online client's copy, where the shots, reloads and pickups this machine
## already showed the moment the button went down (src/net/net_shot_predict.gd)
## must not show again when the copy plays them a round trip later. Looks
## only: nothing it does may change play. `game.hands_watch` is null on a
## single-player game and a host, so they never come here.
class_name HandsWatch
extends RefCounted

## The slot whose hands are watched (-1: none).
var slot := -1


## Before player `p`'s hands step (p.slot == slot) with `controls`.
func before_hands(_game: GameState, _p: Player, _controls: GameState.Controls) -> void:
	pass


## After it, before anyone else acts.
func after_hands(_game: GameState, _p: Player, _controls: GameState.Controls) -> void:
	pass


## While `game.own_quiet` is on, a looks-only call (a muzzle puff, a tracer, a
## spray of blood) is handed here instead of done: `kind` says what it shows
## ("shot", "trace", "hit", "reload"); the watcher does it later or drops it.
func defer(_call: Callable, _kind: String) -> void:
	pass


## burst()'s specks held back while `game.own_quiet` is on (the dice were
## spent as ever): shown later off the watcher's own dice, or dropped.
func held_burst(_x: float, _y: float, _z: float, _kind: String, _count: int, _speed: float) -> void:
	pass
