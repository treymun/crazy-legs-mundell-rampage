## The play keys of an online co-op, deathmatch or team deathmatch match, on
## the host and on a client alike. A key may never change a game itself
## between ticks (a client's copy would part from the host's, and the host's
## game from every copy), so what the campaign's keys do with main.act() goes
## out with this machine's next controls instead (TacticalScreens.pending_*,
## main.gd _net_advance): the gun keys, the wheel and ; ', reload, USE, the
## pockets (Q [ ] pick one: Game.POCKET_PICK; F and C B M V X use one), and
## BACKSPACE turns round with the mouse's turn. While this machine's player
## is down and the view is on a partner, SPACE or E watches the next one up.
class_name NetKeys
extends RefCounted


static func party(game: Game) -> bool:
	return game.players.size() > 1 and NetPlay.PARTY_MODES.has(Modes.mode_of(game))


## True when the key was taken here (the campaign's handler goes on otherwise:
## the map, ALWAYS RUN, the crouch latch, YEE-HAW).
static func key(main: MainState, game: Game, code: int) -> bool:
	var human := TacticalScreens.human
	if human < 0 or human >= game.players.size() or game.showing_tally or game.defeated():
		return false
	var me: Player = game.players[human]
	if game.local_player != me:
		if code == KEY_SPACE or code == KEY_E:
			TacticalScreens.watch_next = true
			return true
		return code != KEY_TAB
	if me.health <= 0:
		return code != KEY_TAB
	if code == KEY_R:
		TacticalScreens.pending_reload = true
	elif code == KEY_E or code == KEY_SPACE:
		TacticalScreens.pending_use = true
	elif code >= KEY_1 and code <= KEY_9:
		TacticalScreens.pending_weapon = code - KEY_1
	elif code in [KEY_0, KEY_MINUS, KEY_EQUAL, KEY_BACKSLASH, KEY_QUOTELEFT]:
		TacticalScreens.pending_weapon = (
			{
				KEY_0: Weapons.ROCKET,
				KEY_MINUS: Weapons.BOWLING,
				KEY_EQUAL: Weapons.KEG,
				KEY_BACKSLASH: Weapons.COW,
				KEY_QUOTELEFT: Weapons.TEAT
			}
			. get(code, Weapons.ROCKET)
		)
	elif code == KEY_SEMICOLON or code == KEY_APOSTROPHE:
		TacticalScreens.pending_cycle = -1 if code == KEY_SEMICOLON else 1
	elif code == KEY_BACKSPACE:
		main.net_turn += PI
	elif code == KEY_HOME:
		main.net_look -= me.pitch
	elif code == KEY_Q or code == KEY_BRACKETLEFT or code == KEY_BRACKETRIGHT:
		var pocket := posmod(
			me.inventory_slot + (-1 if code == KEY_BRACKETLEFT else 1), HUD.ITEMS.size()
		)
		TacticalScreens.pending_item = Game.POCKET_PICK + pocket
	elif code == KEY_F or code == KEY_ENTER or code == KEY_KP_ENTER:
		TacticalScreens.pending_item = me.inventory_slot
	elif code in [KEY_C, KEY_B, KEY_M, KEY_V, KEY_X]:
		TacticalScreens.pending_item = [KEY_C, KEY_B, KEY_M, KEY_V, KEY_X].find(code)
	elif code == KEY_H or code == KEY_SCROLLLOCK:
		pass  # holstering is the campaign's alone (nothing carries it as controls)
	else:
		return false
	return true
