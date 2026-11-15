## Hostage rescue (CLAUDE.md "Modes"; the rounds, money and sides are
## tactical_mode.gd's). The OUTLAWS hold the hostages (LevelData.tactical
## "hostages": [x, y] each) in the defenders' end of the map; the DEPUTIES
## come in from the attackers' end. A deputy stands by a hostage and presses
## USE to take them (USE again sets them down; a carrier who goes down drops
## them) and leads them at a run (a hostage keeps up) into the rescue box ("rescue":
## [x0, y0, x1, y1], round the deputies' spawn). One hostage out wins the
## round for the deputies, as does downing every outlaw; the outlaws win by
## downing every deputy or by the clock running out.
class_name HostageMode
extends TacticalMode

static var CARRY_REACH: float = ModeData.get_value("hostage", "carry_reach", 1.5)
static var CARRY_GAP: float = ModeData.get_value("hostage", "carry_gap", .55)


func id() -> String:
	return Modes.HOSTAGE


func title() -> String:
	return "HOSTAGE RESCUE"


func round_time() -> float:
	var seconds: float = ModeData.get_value("hostage", "round_seconds", 115.0)
	return seconds


## The deputies go in.
func attack_team(st: ModeFeature) -> int:
	return 1 - int(st.outlaws)


static func rescue_box(game: Game) -> Array:
	var box: Variant = game.world.tactical.get("rescue", [])
	return box if box is Array else []


## Every place a hostage counts as out: the box round the deputies' spawn and
## the map's nearer rescue points ("rescue_more", on the lanes back from the
## sites).
static func rescue_boxes(game: Game) -> Array:
	var out: Array = []
	var main := rescue_box(game)
	if not main.is_empty():
		out.append(main)
	var more: Variant = game.world.tactical.get("rescue_more", [])
	if more is Array:
		for box: Variant in more:
			if box is Array:
				var corners: Array = box
				if corners.size() >= 4:
					out.append(box)
	return out


## The rescue point nearest (x, y) (straight line), [] when there is none.
static func nearest_rescue(game: Game, x: float, y: float) -> Array:
	var best: Array = []
	var near := INF
	for box: Array in rescue_boxes(game):
		var d := TacticalMode.box_centre(box).distance_to(Vector2(x, y))
		if d < near:
			near = d
			best = box
	return best


func reset_objective(game: Game, st: ModeFeature) -> void:
	st.hostages = []
	st.rescued = 0
	for at: Array in game.world.tactical.get("hostages", []):
		var hx: float = at[0]
		var hy: float = at[1]
		st.hostages.append([hx, hy, "free", -1])


func objective_tick(game: Game, st: ModeFeature, _dt: float) -> void:
	var boxes := rescue_boxes(game)
	for hostage: Array in st.hostages:
		if str(hostage[2]) != "carried":
			continue
		var slot: int = hostage[3]
		var carrier: Player = (
			game.players[slot] if slot >= 0 and slot < game.players.size() else null
		)
		if carrier == null or carrier.health <= 0:
			hostage[2] = "free"
			hostage[3] = -1
			continue
		if boxes.any(
			func(box: Array) -> bool: return TacticalMode.in_box(box, carrier.x, carrier.y)
		):
			hostage[2] = "rescued"
			hostage[3] = -1
			hostage[0] = carrier.x
			hostage[1] = carrier.y
			st.rescued = int(st.rescued) + 1
			TacticalMode.pay(st, carrier, TacticalShop.RESCUE_REWARD)
			game.burst(carrier.x, carrier.y, carrier.eye, "dust", 10, 1.4)
			continue
		var back := Vector2(
			carrier.x - cos(carrier.angle) * CARRY_GAP, carrier.y - sin(carrier.angle) * CARRY_GAP
		)
		if game.world.blocked(back.x, back.y, .18):
			back = Vector2(carrier.x, carrier.y)
		hostage[0] = back.x
		hostage[1] = back.y


func round_check(game: Game, st: ModeFeature) -> Array:
	var attack := attack_team(st)
	var defend := 1 - attack
	if int(st.rescued) > 0:
		return [attack, "RESCUE"]
	if TacticalMode.alive(game, attack) == 0:
		return [defend, "WIPE"]
	if TacticalMode.alive(game, defend) == 0:
		return [attack, "WIPE"]
	if game.clock - float(st.live_from) >= round_time_of(st):
		return [defend, "TIME"]
	return []


func dropped(_game: Game, st: ModeFeature, p: Player) -> void:
	for hostage: Array in st.hostages:
		var holder: int = hostage[3]
		if str(hostage[2]) == "carried" and holder == p.slot:
			hostage[2] = "free"
			hostage[3] = -1


## A carrier may run: walking them out took most of the round and nearly
## every one was run down from behind (tools/tactical_check.gd).
func slowed(_st: ModeFeature, _p: Player) -> bool:
	return false


## The hostage the acting player carries, else the nearest free one in reach:
## its index, or -1.
static func target(game: Game, st: ModeFeature) -> int:
	var me: Player = game.player
	if me.team != (Modes.rules(game) as TacticalMode).attack_team(st):
		return -1
	for i in st.hostages.size():
		var hostage: Array = st.hostages[i]
		var holder: int = hostage[3]
		if str(hostage[2]) == "carried" and holder == me.slot:
			return i
	var near := CARRY_REACH
	var best := -1
	for i in st.hostages.size():
		var hostage: Array = st.hostages[i]
		if str(hostage[2]) != "free":
			continue
		var hx: float = hostage[0]
		var hy: float = hostage[1]
		var d := Vector2(hx - me.x, hy - me.y).length()
		if d < near:
			near = d
			best = i
	return best


func use_prompt(game: Game) -> String:
	var st: ModeFeature = Modes.feature(game)
	if st == null or String(st.phase) != "live" or game.player.health <= 0:
		return ""
	var i := target(game, st)
	if i < 0:
		return ""
	if str(st.hostages[i][2]) == "carried":
		return "%s  SET THE HOSTAGE DOWN" % game.use_key
	return "%s  TAKE THE HOSTAGE" % game.use_key


func use(game: Game) -> bool:
	var st: ModeFeature = Modes.feature(game)
	if st == null or String(st.phase) != "live" or game.player.health <= 0:
		return false
	var i := target(game, st)
	if i < 0:
		return false
	var hostage: Array = st.hostages[i]
	if str(hostage[2]) == "carried":
		hostage[2] = "free"
		hostage[3] = -1
		if game.acting_local():
			Modes.say(game, "HOSTAGE SET DOWN.", 1.8)
		return true
	hostage[2] = "carried"
	hostage[3] = game.player.slot
	TacticalMode.pay(st, game.player, TacticalShop.HOSTAGE_TAKE_REWARD)
	if game.acting_local():
		Modes.say(game, "HOSTAGE TAKEN. RUN 'EM TO A RESCUE POINT.", 2.4)
	game.sound.play("menu_accept", .5)
	return true
