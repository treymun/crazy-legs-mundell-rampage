## Port of rampage2.Cheats: the typed codes (HICK MODE). The game's `cheats`;
## typed as GameState.Cheats (game_state.gd preloads this file under that name).
extends RefCounted

const CODES := {
	"hickgod": "HICK MODE: TOO MEAN TO DIE",
	"hickguns": "HICK MODE: ALL THE GUNS",
	"hickhp": "HICK MODE: FULL TANK",
	"hickbooze": "HICK MODE: STOCKED CELLAR",
	"hickbarks": "HICK MODE: BIG MOUTH",
}
var buffer := ""
var god := false
var used := false


func feed(char: String, game: Game) -> String:
	if char.length() != 1 or not char.to_lower() in "abcdefghijklmnopqrstuvwxyz":
		return ""
	buffer = (buffer + char.to_lower()).right(10)
	for code: String in CODES:
		if buffer.ends_with(code):
			buffer = ""
			apply(code, game)
			used = true
			var text: String = CODES[code]
			if code == "hickgod":
				text += " (ON)" if god else " (OFF)"
			return text
	return ""


func apply(code: String, game: Game) -> void:
	var p := game.player
	if code == "hickgod":
		god = not god
	elif code == "hickhp":
		p.health = 100
	elif code == "hickguns":
		var a := game.armory
		for i in Weapons.COUNT:
			a.owned[i] = true
			a.reserve[i] = Weapons.MAX_RESERVE[i]
	elif code == "hickbooze":
		for key: Variant in game.inventory:
			game.inventory[key] = 5
	elif code == "hickbarks":
		game.barks_off_by_code = game.barks.enabled
		game.barks.enabled = not game.barks.enabled
