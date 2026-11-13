## Team deathmatch: deathmatch in two teams (CLAUDE.md "Modes"): RED (slots
## 0 and 2) against BLUE (1 and 3). A teammate's bullets and blasts pass you
## by (your own blast still bites you); a frag counts for the team, a death
## to your own blast or the world takes one off it. The frag limit is the
## team's score. Everything else is deathmatch's.
class_name TeamDeathmatchMode
extends DeathmatchMode

const TEAMS := ["RED", "BLUE"]


func id() -> String:
	return Modes.TEAM


func title() -> String:
	return "TEAM DEATHMATCH"


func joined(_game, _st, p: Player) -> void:
	p.team = p.slot % 2


func hurt_scale(_game, attacker: Player, victim: Player, _blast: bool) -> float:
	if attacker == victim:
		return 1.0
	return 0.0 if attacker.team == victim.team else 1.0


func team_score(game, team: int) -> int:
	var sum := 0
	for p: Player in game.players:
		if p.team == team:
			sum += p.frags
	return sum


func leader_score(game) -> int:
	return maxi(team_score(game, 0), team_score(game, 1))


func winner(game) -> String:
	var red := team_score(game, 0)
	var blue := team_score(game, 1)
	return "TIE" if red == blue else String(TEAMS[0 if red > blue else 1])
