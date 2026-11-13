## The campaign: one player, the game as it always was (the default mode).
## Nothing here changes play: every hook is the base's, and with more than
## one player (the multiplayer foundation's own checks) they pass through
## each other and a blast hurts whoever it reaches in full, as it left them.
class_name CampaignMode
extends GameMode


func id() -> String:
	return Modes.CAMPAIGN


func bodies_block() -> bool:
	return false


func hurt_scale(_game, _attacker: Player, _victim: Player, _blast: bool) -> float:
	return 1.0
