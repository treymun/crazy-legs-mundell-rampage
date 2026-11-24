## What the game modes draw (CLAUDE.md "Modes"), all for this machine's
## player: the partners in the world (their pictures, tinted by slot, or by
## team in team deathmatch: RED warm, BLUE cold, the tags too), a tag and
## health over each (or at the view's edge when out of sight), the revive
## prompt and its progress, the frags and the clock in versus, the screen of a
## player who is down (game_view.gd, instead of the death screen while a
## partner is up or a respawn is coming) and the versus results (hud.gd
## intermission, the tally's look). None of it is drawn with one player.
class_name ModeScreens
extends RefCounted

const ModeFeature := preload("res://src/features/mode_feature.gd")

const HEADINGS := ["_front", "_quarter", "_side", "_away", "_back"]
const RED := Color8(238, 89, 52)
const GREEN := Color8(120, 210, 90)
const PLATE := Color8(30, 21, 17)
## Team deathmatch: RED's and BLUE's tint on the pictures and ink on the tags.
const TEAM_TINTS := [[1.3, .76, .66], [.68, .88, 1.32]]
const TEAM_INKS := [Color8(244, 104, 84), Color8(110, 184, 255)]
## How tall a partner's picture stands (map units), the model too.
const PARTNER_HEIGHT := 1.02
## A player down lies on the floor: player_down_side (seen across, the head
## to the left; flipped from the other side), _head and _feet (seen from
## each end), from tools/art/build_player_down.gd (the 3D model's own down
## frame, drawn as the 3D view draws it), DOWN_ROWS rows a map unit tall.
const DOWN_ROWS := 122.0
## The results' last line (empty online: the lobby's line is there).
const FOOTER := "ENTER  ANOTHER ROUND  /  ESC TITLE"
static var footer := FOOTER


## The other players' pictures for this frame (pooled sprites). The 3D view
## draws each as Mundell's model (ModeBodies: walking, aiming, firing, hurt,
## falling), tinted as the picture is; the picture is what shows without it.
static func sprites(game: Game) -> Array:
	var out: Array = []
	var me: Player = game.local_player
	ModeBodies.watch(game)
	for q: Player in game.players:
		if q == me or q.away or not game.in_view(q.x, q.y, 1.0):
			continue
		if ModeBodies.hidden_in_vehicle(game, q):
			continue
		if Modes.is_tactical(game):
			out.append(TacticalScreens.player_sprite(game, q, me))
			continue
		var bearing := atan2(me.y - q.y, me.x - q.x)
		var relative := Enemy.angle_delta(bearing, q.angle)
		var direction := mini(4, int(absf(relative) / (PI / 4.0) + .5))
		var step := int(q.walk_phase / PI) % 2 if q.motion > .1 and q.health > 0 else 0
		var base := "player%s_%d" % [HEADINGS[direction], step]
		var tall := PARTNER_HEIGHT if q.health > 0 else .5
		var lying := q.health <= 0 and game.art.has_art("player_down_side")
		if lying:
			# The model falls onto its side, its head to its right of the way
			# it faced: seen across from in front (behind: flipped), else
			# from the head or the feet.
			base = "player_down_side"
			if absf(relative) > PI / 4.0 and absf(relative) < PI * .75:
				base = "player_down_head" if relative > 0.0 else "player_down_feet"
			var rows: int = game.art.art(base)["h"]
			tall = rows / DOWN_ROWS
		var image := base
		if Modes.mode_of(game) == Modes.TEAM:
			var team_tint: Array = TEAM_TINTS[q.team % 2]
			image = game.art.tinted_art(base, team_tint)
		elif q.slot != 0:
			var tint: Array = Modes.TINTS[q.slot % Modes.TINTS.size()]
			image = game.art.tinted_art(base, tint)
		var spr := game.pooled(q.x, q.y, image, tall, ModeBodies.feet_of(game, q))
		spr.flip = relative < 0.0 and direction < 4
		if lying:
			spr.flip = absf(relative) >= PI * .75
		spr.body = true
		var kind := ModeBodies.PLAYER_KIND
		var model_tall := PARTNER_HEIGHT * (.8 if q.crouched and q.health > 0 else 1.0)
		spr.who = ModeBodies.for_player(game, q, kind, model_tall)
		spr.pose = ModeBodies.player_pose(game, q, kind)
		out.append(spr)
	return out


## Over the view, under the gun: each partner's tag and health, the revive
## prompt, versus's frags and clock.
## Where versus's frags line is drawn from (right aligned).
const FRAGS_AT := Vector2i(316, 12)


static func draw_view(c: Canvas, game: Game, st: ModeFeature) -> void:
	var me: Player = game.local_player
	# Nearest first: a farther partner's tag steps up out of a nearer one's way.
	var others: Array = []
	var rides: Game.VehiclesScript = game.features.get("vehicles")
	var my_seat := rides.seat_of(me).x if rides != null and rides.seated(me) else -1
	for q: Player in game.players:
		# A partner in the same vehicle is right there (no tag at the edge).
		if q != me and (my_seat < 0 or rides.seat_of(q).x != my_seat):
			others.append([Vector2(q.x - me.x, q.y - me.y).length(), q])
	others.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var taken: Array[Rect2i] = []
	for entry: Array in others:
		var q: Player = entry[1]
		if not q.away:
			_tag(c, game, me, q, taken)
	var lay := game.hud.layout
	var watch := _watch_lines(game, me)
	var at := lay.find("watching")
	if not watch.is_empty() and at.size.x > 0:
		HudLayout.begin(c, "watching")
		HUD.text(c, watch[0], 160, at.position.y + 1, "body", HUD.AMBER, true)
		HUD.text(c, watch[1], 160, at.position.y + 11, "mini", HUD.INK, true)
		HudLayout.end(c)
	var down := _reviving(game, me, st)
	at = lay.find("revive")
	if down != null and at.size.x > 0:
		HudLayout.begin(c, "revive")
		HUD.text(
			c, "REVIVING " + Modes.tag(down), at.position.x + 1, at.position.y + 1, "mini", GREEN
		)
		_bar(
			c, at.position.x + 1, at.position.y + 10, 60, down.revive / CoopMode.REVIVE_TIME, GREEN
		)
		HudLayout.end(c)
	var frags := _frags_line(game, me, st)
	if frags != "":
		HudLayout.begin(c, "frags")
		HUD.text(c, frags, FRAGS_AT.x, FRAGS_AT.y, "mini", HUD.AMBER, false, true, true)
		HudLayout.end(c)


## Versus's frags and clock keep the view's top right corner; the watching
## lines and the revive line are fitted in round the rest of the HUD
## (ui/hud/hud_layout.gd).
static func hud_fixed(layout: HudLayout, game: Game, st: ModeFeature) -> void:
	var frags := _frags_line(game, game.local_player, st)
	if frags != "":
		var w := PixelType.text_width(frags, "mini")
		layout.take("frags", HudLayout.text_rect(frags, FRAGS_AT.x - w, FRAGS_AT.y, "mini"))


static func hud_flow(layout: HudLayout, game: Game, st: ModeFeature) -> void:
	var me: Player = game.local_player
	var watch := _watch_lines(game, me)
	if not watch.is_empty():
		var w := maxi(
			PixelType.text_width(watch[0], "body"), PixelType.text_width(watch[1], "mini")
		)
		var mini_h: int = PixelType.style_of("mini")[1]
		var tall := 11 + mini_h + 2
		layout.centred("watching", Vector2i(w + 2, tall), 20)
	var down := _reviving(game, me, st)
	if down != null:
		var w := maxi(PixelType.text_width("REVIVING " + Modes.tag(down), "mini") + 2, 62)
		layout.up("revive", Vector2i(w, 14), HudLayout.EDGE + 7)


## The partner down this player is hauling up (co-op), or null.
static func _reviving(game: Game, me: Player, st: ModeFeature) -> Player:
	if me.health <= 0 or String(st.mode) != Modes.COOP:
		return null
	var down := CoopMode.downed_near(game, me)
	return down if down != null and down.revive > 0.0 else null


## Versus's line: this player's frags, the lead and the clock ("" none).
static func _frags_line(game: Game, me: Player, st: ModeFeature) -> String:
	if game.players.size() < 2 or Modes.TACTICAL.has(String(st.mode)):
		return ""
	if not Modes.rules_for(String(st.mode)).versus() or bool(st.match_over):
		return ""
	var left := maxi(0, ceili(float(st.time_limit) - game.clock))
	var rules := Modes.rules_for(String(st.mode))
	var lead := 0
	if rules is TacticalMode:
		lead = (rules as TacticalMode).leader_score(game)
	else:
		lead = (rules as DeathmatchMode).leader_score(game)
	return (
		"FRAGS %d  LEAD %d/%d  %d:%02d" % [me.frags, lead, int(st.frag_limit), left / 60, left % 60]
	)


## Watching a partner (main.gd _watch_partner) while this machine's own
## player is down: whose view this is, and how long until they are back or
## SPACE (two lines; none otherwise).
static func _watch_lines(game: Game, me: Player) -> PackedStringArray:
	var human := TacticalScreens.human
	if human < 0 or human >= game.players.size() or me.slot == human:
		return PackedStringArray()
	if Modes.is_tactical(game):
		return PackedStringArray()
	var own: Player = game.players[human]
	if own.health > 0:
		return PackedStringArray()
	var since: float = game.clock - own.down_at if own.down_at >= 0.0 else 0.0
	var line := "SPACE  NEXT"
	if Modes.mode_of(game) == Modes.COOP:
		var back := maxi(0, ceili(CoopMode.RESPAWN_AFTER - since))
		line = "YOU'RE DOWN. BACK IN %d  /  SPACE  NEXT" % back
		if own.revive > 0.0:
			line = "GETTIN' HAULED UP..."
	elif Modes.is_versus(game):
		var back := maxi(0, ceili(DeathmatchMode.RESPAWN_DELAY - since))
		line = "BACK IN %d" % back
	return PackedStringArray(["WATCHING " + Modes.tag(me), line])


## The use prompt over a partner down beside this machine's player (co-op;
## game_world.gd use_prompt shows it where the other prompts go), or "".
static func revive_prompt(game: Game) -> String:
	var me: Player = game.local_player
	if me.health <= 0 or Modes.mode_of(game) != Modes.COOP:
		return ""
	var down := CoopMode.downed_near(game, me)
	if down == null:
		return ""
	return "E  HOLD TO REVIVE " + Modes.tag(down)


## One partner's tag and health bar over their head, or at the view's edge
## (with an arrow) when they are behind or out of sight; stepped up clear of
## the tags already drawn (`taken`).
static func _tag(c: Canvas, game: Game, me: Player, q: Player, taken: Array[Rect2i]) -> void:
	var head: float = game.world.stand(q) + q.air + (1.14 if q.health > 0 else .5)
	var at: Vector3 = game.to_canvas(q.x, q.y, head)
	var seen: bool = (
		at.z > 0.0
		and at.x > 8.0 - View.shift
		and at.x < View.WIDTH + View.shift - 8.0
		and at.y > 6.0
		and at.y < View.VIEW - 6.0
		and game.world.visible(me.x, me.y, q.x, q.y, me.eye, head - .3)
	)
	var tone := Modes.color(q)
	if Modes.mode_of(game) == Modes.TEAM:
		tone = TEAM_INKS[q.team % 2]
	var label := Modes.tag(q) if q.health > 0 else Modes.tag(q) + " DOWN"
	if q.health <= 0:
		tone = RED
	var x := int(at.x)
	var y := int(at.y) - 12
	if not seen:
		var rel := Enemy.angle_delta(atan2(q.y - me.y, q.x - me.x), me.view_angle())
		var side := clampf(rel / (PI * .5), -1.0, 1.0)
		x = clampi(
			int(160.0 + side * (148.0 + View.shift)), 12 - View.shift, View.WIDTH + View.shift - 12
		)
		y = View.VIEW - 24
		label = ("<" if rel < 0.0 else ">") + label if absf(rel) > .55 else label
	var w := maxi(PixelType.text_width(label, "mini"), 22)
	var rect := Rect2i(x - w / 2 - 1, y - 1, w + 2, 16)
	# At the view's edge the tag is the HUD's: it keeps clear of the badge,
	# the feed and the rest (ui/hud/hud_layout.gd) as well as the other tags.
	var lay := game.hud.layout
	var room := false
	for _tries in 8:
		var hit := taken.any(func(r: Rect2i) -> bool: return r.intersects(rect))
		if not hit and (seen or lay.clear(rect)):
			room = true
			break
		rect.position.y -= 16
	if not room and not seen:
		return  # no room at the edge this moment: the tag waits
	y = rect.position.y + 1
	taken.append(rect)
	if not seen:
		lay.take("tag%d" % q.slot, rect)
		HudLayout.begin(c, "tag%d" % q.slot)
	HUD.text(c, label, x, y, "mini", tone, true)
	_bar(c, x - 10, y + 8, 20, float(maxi(0, q.health)) / 100.0, tone)
	if q.health <= 0 and q.revive > 0.0:
		_bar(c, x - 10, y + 11, 20, q.revive / CoopMode.REVIVE_TIME, GREEN)
	if not seen:
		HudLayout.end(c)


static func _bar(c: Canvas, x: int, y: int, w: int, part: float, tone: Color) -> void:
	c.fill_rect(x - 1, y - 1, w + 2, 4, PLATE)
	var filled := clampi(roundi(w * clampf(part, 0.0, 1.0)), 0, w)
	if filled > 0:
		c.fill_rect(x, y, filled, 2, tone)


## This machine's player is down but the game goes on (a partner is up, or a
## respawn is coming): what happened and what comes next.
static func draw_down(c: Canvas, game: Game) -> void:
	var st := Modes.feature(game)
	var me: Player = game.local_player
	var mode := Modes.mode_of(game)
	if Modes.TACTICAL.has(mode):
		TacticalScreens.draw_down(c, game)
		return
	HUD.panel(c, 47, 50, 226, 50, Canvas.rgb(43, 26, 22))
	var since: float = game.clock - me.down_at if me.down_at >= 0.0 else 0.0
	if mode == Modes.COOP:
		HUD.text(c, "YOU'RE DOWN", 160, 58, "heading", HUD.INK, true)
		var back := maxi(0, ceili(CoopMode.RESPAWN_AFTER - since))
		var line := "A PARTNER CAN HOLD %s OVER YOU" % game.use_key
		if me.revive > 0.0:
			line = "YOUR PARTNER IS GETTING YOU UP"
		HUD.text(c, line, 160, 76, "body", HUD.AMBER, true)
		HUD.text(c, "OR BACK BESIDE THEM IN %d" % back, 160, 87, "body", HUD.INK, true)
		if me.revive > 0.0:
			_bar(c, 110, 97, 100, me.revive / CoopMode.REVIVE_TIME, GREEN)
		return
	var by := me.downed_by
	var heading := "YOU CASHED OUT"
	if by >= 0 and by != me.slot and by < game.players.size():
		heading = "FRAGGED BY " + Modes.tag(game.players[by])
	HUD.text(c, heading, 160, 58, "heading", HUD.INK, true)
	var back := maxi(0, ceili(DeathmatchMode.RESPAWN_DELAY - since))
	HUD.text(c, "BACK IN %d" % back, 160, 78, "body", HUD.AMBER, true)
	if st != null:
		HUD.text(c, "FRAGS %d  DEATHS %d" % [me.frags, me.deaths], 160, 89, "body", HUD.INK, true)


## The versus results, in the chapter tally's county-fair look: true when it
## drew them (hud.gd intermission asks first).
static func results(c: Canvas, game: Game) -> bool:
	var st := Modes.feature(game)
	if st == null or not bool(st.match_over):
		return false
	var rules := Modes.rules_for(String(st.mode))
	if not rules.versus():
		return false
	if Modes.TACTICAL.has(String(st.mode)):
		TacticalScreens.results(c, game, st)
		return true
	# The other versus modes: deathmatch and team deathmatch.
	var match_rules := rules as DeathmatchMode
	var art: Dictionary = game.art.art("title_backdrop")
	var art_data: PackedByteArray = art["data"]
	var art_w: int = art["w"]
	var art_h: int = art["h"]
	c.blit_rgba(art_data, art_w, art_h, 0, 0, "art|title_backdrop")
	HUD.panel(c, 10, 9, 211, 177)
	HUD.text(c, "COUNTY FAIR", 21, 20, "heading", HUD.AMBER)
	HUD.text(c, match_rules.title(), 21, 38, "heading", HUD.AMBER)
	var place: String = game.level.title if game.level.title != "" else game.level.id.to_upper()
	var minutes := int(st.over_clock) / 60
	var seconds := int(st.over_clock) % 60
	HUD.text(c, "%s  %02d:%02d" % [place, minutes, seconds], 21, 61, "body", HUD.INK)
	c.line(21, 72, 208, 72, Color(135 / 255.0, 95 / 255.0, 63 / 255.0))
	HUD.text(c, "FRAGS", 168, 76, "mini", HUD.DIM, false, true, true)
	HUD.text(c, "DEATHS", 202, 76, "mini", HUD.DIM, false, true, true)
	var rows: Array = rules.scores(game, st)
	if String(st.mode) == Modes.TEAM:
		var team_rules := rules as TeamDeathmatchMode
		var named := [
			["RED", team_rules.team_score(game, 0), -1, -1],
			["BLUE", team_rules.team_score(game, 1), -1, -1]
		]
		rows = named + rows
	# The 5v5 modes list twelve rows: two teams and ten players, packed tighter.
	var many := rows.size() > 6
	var step := 7 if many else 13
	var style := "mini" if many else "body"
	for i in mini(rows.size(), 12):
		var row: Array = rows[i]
		var y := 84 + i * step
		c.fill_rect(21, y, 187, step - 1, PLATE)
		var slot: int = row[3]
		var tone: Color = Modes.COLORS[slot % Modes.COLORS.size()] if slot >= 0 else HUD.AMBER
		var name := str(row[0])
		if slot >= 0 and slot == game.local_player.slot:
			name += "  (YOU)"
		var lift := 1 if many else 2
		HUD.text(c, name, 26, y + lift, style, tone)
		HUD.text(c, str(row[1]), 168, y + lift, style, HUD.AMBER, false, true, true)
		var deaths: int = row[2]
		if deaths >= 0:
			HUD.text(c, str(row[2]), 202, y + lift, style, HUD.INK, false, true, true)
	_ribbon(c, match_rules.winner(game))
	if footer != "":
		HUD.text(c, footer, 22, 172, "body", HUD.INK)
	return true


## The fair's ribbon pinned beside the results: who took the blue.
static func _ribbon(c: Canvas, word: String) -> void:
	var blue := Color8(40, 70, 150)
	var gold := Color8(236, 196, 104)
	c.fill_rect(229, 58, 84, 34, Color(.08, .05, .04))
	c.fill_rect(228, 56, 84, 34, blue)
	c.fill_rect(230, 58, 80, 1, gold)
	c.fill_rect(230, 87, 80, 1, gold)
	HUD.text(c, "WINNER" if word != "TIE" else "DEAD EVEN", 270, 61, "mini", gold, true)
	HUD.text(c, word, 270, 72, "body", HUD.INK, true)
	for x: int in [248, 288]:
		c.fill_rect(x, 90, 8, 14, blue)
		c.fill_rect(x + 2, 104, 4, 3, blue)
