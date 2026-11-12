## The boss's bar at the top right while a boss fight is on: its title, its
## health, and what it is winding up to (game_view.gd draws it under any
## notice at the top, from `y` down). Returns the row under it (`y` when
## there is none).
class_name BossBar
extends RefCounted


static func draw(game, c: Canvas, y: int) -> int:
	var p = game.player
	var finale = game.finale
	var jerry = game.jerry
	var boss = finale if finale != null else (jerry if jerry != null and jerry.alive else game.boss)
	if boss == null:
		return y
	var in_finale: bool = BossFight.in_arena_at(game, boss, p.x, p.y)
	if not in_finale or not boss.alive or not boss.alerted or game.in_hub:
		return y
	var tell: String = String(
		Enemy.TELLS.get(boss.kind, "PLASMA CHARGE" if boss == game.boss else "WHISTLE")
	)
	if boss.brain == "baron" and not BaronMoves.outlets_next(boss.attacks, boss.enraged):
		tell = "STEAM SWEEP"
	if boss.brain == "foreman" and boss.attacks % 2 == 1:
		tell = "GAP IN THE MIDDLE"
	if boss.brain == "rudy":
		tell = "LEFT HORN" if boss.attacks % 2 == 1 else "RIGHT HORN"
	if boss.brain == "derby_champ":
		tell = DerbyChamp.tell(boss)
	if BayouBrains.is_king(boss) and boss.aim_mark != null:
		var toward := atan2(boss.aim_mark[1] - boss.y, boss.aim_mark[0] - boss.x)
		var run := BayouBrains.runs_on(boss, boss.attacks + 1, game.world, toward)
		tell = "AIRBOAT RUN" if run else "PUNT GUN"
	if boss.has_meta("tell"):
		# An attack of its own moves (src/bosses/) names itself.
		tell = String(boss.get_meta("tell"))
	tell = ShipAliens.tell(game, boss, tell)
	var phase: String = tell if boss.windup > 0.0 else "RECOVERING" if boss.recovery > .16 else ""
	if boss.brain == "derby_champ" and phase == "RECOVERING":
		phase = tell
	if boss.enraged and game.clock - boss.enraged_at < 1.6:
		phase = "FIGHTIN' MAD"
	if game.clock - boss.desperate_at < 1.6:
		phase = "PLUM DESPERATE"
	# Staggered by a big hit (boss_kit.gd): the bar flashes.
	var reeling: bool = game.clock - boss.staggered_at < .35
	if reeling:
		phase = "STAGGERED!"
	phase = ShipAliens.phase_text(game, boss, phase)
	HUD.panel(
		c,
		193,
		y,
		122,
		27 if phase != "" else 20,
		Canvas.rgb(35, 24, 20),
		Canvas.rgb(250, 226, 170) if reeling else Canvas.rgb(126, 85, 57)
	)
	HUD.text(c, title(boss.kind), 253, y + 3, "body", HUD.INK, true, false)
	c.fill_rect(199, y + 12, 110, 4, Canvas.rgb(70, 42, 32))
	var fill := Canvas.rgb(236, 143, 69) if boss.windup > 0.0 else Canvas.rgb(204, 77, 47)
	if reeling:
		fill = Canvas.rgb(255, 238, 200)
	c.fill_rect(199, y + 12, int(round(110.0 * boss.hp / boss.max_hp)), 4, fill)
	if phase != "":
		HUD.text(c, phase, 253, y + 19, "mini", Canvas.rgb(249, 194, 124), true, false)
	return y + (27 if phase != "" else 20) + 2


static func title(kind: String) -> String:
	return String(
		(
			{
				"boss": "ALIEN SHERIFF",
				"jerry": "JERRY JONES",
				"rudy": "RUDY RACKET",
				"foreman": "SPLINTER FOREMAN",
				"baron": "COPPER BARON"
			}
			. get(kind, String(Enemy.BOSS_TITLES.get(kind, "BOSS")))
		)
	)
