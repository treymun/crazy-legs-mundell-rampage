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


## What USE would do here for this machine's player ("": nothing special),
## and whether use() took it (the hostage carry, the 5v5 modes).
func use_prompt(_game) -> String:
	return ""


func use(_game) -> bool:
	return false


## The controls each player plays this tick (by slot), changed as the
## mode needs before the tick (the 5v5 freeze time holds everyone still).
func hold_controls(_game, _st, by_slot: Array) -> Array:
	return by_slot


## How much of `attacker`'s hit on `victim` lands (1 all, 0 none). A player's
## own blast always lands (a BACKBLAST).
func hurt_scale(_game, attacker: Player, victim: Player, _blast: bool) -> float:
	return 1.0 if attacker == victim else 0.0


## The damage `attacker`'s hit of `amount` (what it does to a hand) does to
## `victim`, from gun `weapon` (-1 not known) at `height` up the body (0..1;
## -1 not known): PVP_SCALE and friendly fire. The 5v5 modes have their own.
func pvp_damage(
	game, attacker: Player, victim: Player, amount: float, _weapon: int, _height: float
) -> float:
	return amount * hurt_scale(game, attacker, victim, false) * Modes.PVP_SCALE


## A player's blast of `amount` on `victim` (as Modes.blast_hit hands it
## over), from a shot of `kind` ("tnt", "bottle_rocket"...).
func blast_damage(game, thrower: Player, victim: Player, amount: float, _kind: String) -> float:
	return amount * hurt_scale(game, thrower, victim, true)


func won(_game, _st) -> void:
	pass


## The rows of the results screen ([label, value]), best first.
func scores(_game, _st) -> Array:
	return []
