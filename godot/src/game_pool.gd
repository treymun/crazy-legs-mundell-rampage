## The games one owner made (the front end, the lobby server), so the ones it
## has let go are disposed (Game.dispose(): a game and its features hold each
## other, which reference counting never frees by itself). The owner track()s
## each game it makes and sweep()s with the games it still keeps, at a
## moment nothing is half way through a change (main_flow.gd: deferred to the
## frame's end). A game kept is kept with every chapter it retains.
class_name GamePool
extends RefCounted

var _games: Array[Game] = []


## Notes `g` as made here; gives it back.
func track(g: Game) -> Game:
	if g != null and not _games.has(g):
		_games.append(g)
	return g


## How many games are tracked (kept or not yet swept).
func size() -> int:
	return _games.size()


## Disposes every tracked game that is not in `kept` (Games, nulls skipped)
## nor retained by one that is; returns how many went.
func sweep(kept: Array) -> int:
	var live := {}
	var stack: Array = kept.duplicate()
	while not stack.is_empty():
		var next: Variant = stack.pop_back()
		if not next is Game:
			continue
		var g: Game = next
		if live.has(g):
			continue
		live[g] = true
		stack.append_array(g.retained.values())
	var gone := 0
	for g: Game in _games.duplicate():
		if not live.has(g):
			_games.erase(g)
			g.dispose()
			gone += 1
	return gone


## Disposes every tracked game (the owner itself is going).
func clear() -> void:
	sweep([])
