## A game mode's rules (CLAUDE.md "Modes"). One instance per mode, shared by
## every game (Modes.rules_for): it keeps no state of its own. What a mode
## remembers lives on the players (Player.down_at, revive, frags, deaths,
## team, downed_by) and in the mode feature (features/mode_feature.gd, `st`
## below: plain values, saved and carried in snapshots).
##
## The hooks, each handed the game and the feature:
##   start       the first tick: scaling, enemies off, spawn points
##   joined      a player joined (left: one left)
##   tick        every tick after the world: revive, respawn, limits
##   downed      a player's health reached 0 (by: the slot that did it, -1
##               the world or an enemy)
##   respawn     put a downed player back on their feet
##   defeated    the game is lost: the death screen
##   over        a versus match is finished: the results screen
##   pickup      the acting player took `name` (co-op shares ammo)
##   hurt_scale  how much of one player's hit on another lands
##   won         the level was won
class_name GameMode
extends RefCounted


func id() -> String:
	return ""


## Players against each other (no enemies, frags, a results screen).
func versus() -> bool:
	return false


## A player's bullets, pellets and swings can strike another player.
func bullets_hit_players() -> bool:
	return false


## Players who are up block each other (game_world.gd move_actor).
func bodies_block() -> bool:
	return true


func start(_game, _st) -> void:
	pass


func joined(_game, _st, _p: Player) -> void:
	pass


func left(_game, _st, _p: Player) -> void:
	pass


func tick(_game, _st, _dt: float) -> void:
	pass


func downed(_game, _st, _p: Player, _by: int) -> void:
	pass


func respawn(_game, _st, _p: Player) -> void:
	pass


## The death screen: nobody is up.
func defeated(game, _st) -> bool:
	return not Players.anyone_alive(game)


func over(_game, _st) -> bool:
	return false


func pickup(_game, _st, _name: String) -> void:
	pass


## How much of `attacker`'s hit on `victim` lands (1 all, 0 none). A player's
## own blast always lands (a BACKBLAST).
func hurt_scale(_game, attacker: Player, victim: Player, _blast: bool) -> float:
	return 1.0 if attacker == victim else 0.0


func won(_game, _st) -> void:
	pass


## The rows of the results screen ([label, value]), best first.
func scores(_game, _st) -> Array:
	return []
