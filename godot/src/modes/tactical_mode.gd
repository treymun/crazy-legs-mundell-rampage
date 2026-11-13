## The 5v5 round modes (CLAUDE.md "Modes"): what search and destroy
## (bomb_mode.gd) and hostage rescue (hostage_mode.gd) share.
##
## Two teams of five, fixed by slot (team 0 the HOGS: the even slots, player
## one among them; team 1 the GATORS: the odd slots). Each half one team plays
## the OUTLAWS and the other the DEPUTIES (st.outlaws); they swap after
## `rounds_to_win - 1` rounds and the money starts over. The first team to
## win `rounds_to_win` rounds (7) takes the match; after twice that less two
## rounds (12) with nobody there, it is a draw.
##
## A round: FREEZE seconds with everyone held still at their spawn to shop
## (the buy menu, tactical_screens.gd, opened with B), then live play for the
## mode's round time, the bomb's timer or until a team is wiped out, then POST
## seconds to look round before the next one. Nobody comes back inside a
## round. Buying is open through the freeze and BUY_WINDOW seconds after,
## near your own spawn. A survivor keeps their guns, topped up, and their
## vest; the fallen start the next round with the crowbar and their side's
## pistol (the outlaws' .38, the deputies' .45).
##
## Which team attacks (goes for the objective) is the mode's: the OUTLAWS plant
## the shine bomb, the DEPUTIES go in for the hostages. The map says where the
## attackers and the defenders start (LevelData.tactical: attack_spawns,
## defend_spawns), so in hostage rescue the deputies come in from the far end.
##
## Hits between players use TacticalShop's own table (head and vest), never
## a teammate's; teammates walk through one another. Never saved.
class_name TacticalMode
extends GameMode

const ROUNDS_TO_WIN := 7
const FREEZE := 6.0
const BUY_WINDOW := 20.0
const BUY_REACH := 7.5
const POST := 5.0
const TEAM_NAMES := ["HOGS", "GATORS"]
const SIDE_NAMES := ["OUTLAWS", "DEPUTIES"]
const FEED_SECONDS := 5.0


func versus() -> bool:
	return true


func bullets_hit_players() -> bool:
	return true


## Ten bodies in the same doorways: teammates pass through each other.
func bodies_block() -> bool:
	return false


## The round's length once it is live (seconds).
func round_time() -> float:
	return 105.0


## Which team goes for the objective this half.
func attack_team(st) -> int:
	return int(st.outlaws)


func objective_title() -> String:
	return ""


# ------------------------------------------------------------------- sides


static func outlaws_team(st) -> int:
	return int(st.outlaws)


static func side_of(st, p: Player) -> int:
	return 0 if p.team == int(st.outlaws) else 1


static func side_name(st, p: Player) -> String:
	return SIDE_NAMES[side_of(st, p)]


static func team_name(team: int) -> String:
	return TEAM_NAMES[clampi(team, 0, 1)]


## Whether `p` attacks this half (by the game's own mode).
static func attacks(game, st, p: Player) -> bool:
	return p.team == (Modes.rules(game) as TacticalMode).attack_team(st)


## Whether `p` is on the deputies' side of a search and destroy (the side
## that defends the sites, and may buy wire snips).
static func defends(st, p: Player) -> bool:
	return p.team != int(st.outlaws)


static func alive(game, team: int) -> int:
	var n := 0
	for p: Player in game.players:
		if p.team == team and p.health > 0:
			n += 1
	return n


## The spawn points of `team` this half: [[x, y, angle]...].
static func spawns_of(game, st, team: int) -> Array:
	var plan: Dictionary = game.world.tactical
	var attacker := (Modes.rules(game) as TacticalMode).attack_team(st)
	var key := "attack_spawns" if team == attacker else "defend_spawns"
	var rows = plan.get(key, [])
	return rows if rows is Array else []


## Whether `p` may shop right now: up, in the freeze or the first
## BUY_WINDOW seconds of play, within BUY_REACH of one of their spawns.
static func can_buy(game, st, p: Player) -> bool:
	if p.health <= 0:
		return false
	var phase := String(st.phase)
	if phase != "freeze" and not (phase == "live" and game.clock - st.live_from < BUY_WINDOW):
		return false
	for spot: Array in spawns_of(game, st, p.team):
		if Vector2(float(spot[0]) - p.x, float(spot[1]) - p.y).length() < BUY_REACH:
			return true
	return false


## Seconds of buying left (0 when shut).
static func buy_left(game, st) -> float:
	if String(st.phase) == "freeze":
		return float(st.phase_until) - game.clock + BUY_WINDOW
	if String(st.phase) == "live":
		return maxf(0.0, BUY_WINDOW - (game.clock - float(st.live_from)))
	return 0.0


## Seconds left on the round's clock (the bomb's own once it is planted).
func clock_left(game, st) -> float:
	match String(st.phase):
		"freeze":
			return float(st.phase_until) - game.clock
		"live":
			return maxf(0.0, round_time() - (game.clock - float(st.live_from)))
	return 0.0


## The rounds a match lasts at most (12 for first to 7).
static func max_rounds(st) -> int:
	return int(st.rounds_to_win) * 2 - 2


# ------------------------------------------------------------------ hooks


func joined(_game, _st, p: Player) -> void:
	p.team = p.slot % 2


func hurt_scale(_game, attacker: Player, victim: Player, _blast: bool) -> float:
	if attacker == victim:
		return 1.0
	return 0.0 if attacker.team == victim.team else 1.0


func start(game, st) -> void:
	Modes.clear_enemies(game)
	game.pickups.clear()
	st.outlaws = 0
	st.round_no = 0
	st.wins = [0, 0]
	st.losses_in_row = [0, 0]
	st.history = []
	st.feed = []
	st.match_over = false
	st.winner_name = ""
	_new_half(game, st)
	for p: Player in game.players:
		p.team = p.slot % 2
		p.frags = 0
		p.deaths = 0
		p.health = 0  # the first round hands everyone the base kit
	begin_round(game, st)


## Money, vests and guns as at the start of a half.
func _new_half(game, st) -> void:
	var n: int = game.players.size()
	st.money = []
	st.armor = []
	st.helmet = []
	st.snips = []
	for i in n:
		st.money.append(TacticalShop.START_MONEY)
		st.armor.append(0.0)
		st.helmet.append(false)
		st.snips.append(false)
	st.losses_in_row = [0, 0]


func begin_round(game, st) -> void:
	st.round_no = int(st.round_no) + 1
	var swapped := false
	if int(st.round_no) == int(st.rounds_to_win):
		# Half time: the teams change sides and the money starts over.
		st.outlaws = 1 - int(st.outlaws)
		_new_half(game, st)
		for p: Player in game.players:
			p.health = 0
		swapped = true
	var taken := [0, 0]
	for p: Player in game.players:
		var survived := p.health > 0
		var side := side_of(st, p)
		if survived:
			TacticalShop.top_up(p, side)
		else:
			TacticalShop.base_kit(p, side)
			st.armor[p.slot] = 0.0
			st.helmet[p.slot] = false
			st.snips[p.slot] = false
		var pool := spawns_of(game, st, p.team)
		var spot: Array = [float(game.level.spawn[0]), float(game.level.spawn[1]), 0.0]
		if not pool.is_empty():
			spot = pool[int(taken[p.team]) % pool.size()]
			taken[p.team] += 1
		Modes.place(game, p, float(spot[0]), float(spot[1]), float(spot[2]))
		Modes.stand_up(game, p, 100)
		p.downed_by = -1
		p.holding = false
	game.shots.clear()
	st.clouds = []
	st.fires = []
	st.decoys = []
	st.blind = {}
	game.won = false
	game.spawn_grace = 0.0
	st.phase = "freeze"
	st.phase_until = game.clock + FREEZE
	st.live_from = st.phase_until
	st.round_winner = -1
	st.round_reason = ""
	reset_objective(game, st)
	st.last_called = false
	if swapped:
		Modes.say(game, "HALF TIME. SIDES SWAP, CASH STARTS OVER.", FREEZE)
		game.sound.play("ann_half", .95)
	else:
		Modes.say(game, "ROUND %d. B TO BUY." % int(st.round_no), 2.6)


func tick(game, st, dt: float) -> void:
	_trim_feed(game, st)
	match String(st.phase):
		"freeze":
			if game.clock >= float(st.phase_until):
				st.phase = "live"
				st.live_from = game.clock
				Modes.say(game, "LET 'ER RIP!", 1.6)
				game.sound.play("ann_go", .9)
		"live":
			objective_tick(game, st, dt)
			_last_standing(game, st)
			if String(st.phase) == "live":
				var verdict := round_check(game, st)
				if not verdict.is_empty():
					end_round(game, st, int(verdict[0]), String(verdict[1]))
		"post":
			if game.clock >= float(st.phase_until):
				if _decided(st):
					st.phase = "over"
					st.match_over = true
					st.over_clock = game.clock
					st.winner_name = winner(game)
					game.won = true
					if st.winner_name != "TIE":
						game.sound.play(
							"ann_hogs_win" if st.winner_name == TEAM_NAMES[0] else "ann_gators_win"
						)
				else:
					begin_round(game, st)


## This machine's player is the last of their team up, foes still about: once
## a round the announcer says so.
func _last_standing(game, st) -> void:
	if bool(st.last_called):
		return
	var me: Player = game.local_player
	if me.health <= 0 or alive(game, me.team) != 1 or alive(game, 1 - me.team) == 0:
		return
	st.last_called = true
	game.sound.play("ann_last", .9)


func _decided(st) -> bool:
	var w: Array = st.wins
	if int(w[0]) >= int(st.rounds_to_win) or int(w[1]) >= int(st.rounds_to_win):
		return true
	return int(st.round_no) >= max_rounds(st)


## The round is over: `winner` took it, by `how` ("BOMB", "DEFUSED", "RESCUE",
## "WIPE", "TIME"). The money goes out and the post-round look starts.
func end_round(game, st, winner_team: int, how: String) -> void:
	st.round_winner = winner_team
	st.round_reason = how
	st.wins[winner_team] = int(st.wins[winner_team]) + 1
	st.history.append([winner_team, how])
	var loser := 1 - winner_team
	var streak: Array = st.losses_in_row
	var pay_loss := mini(
		TacticalShop.LOSS_MAX, TacticalShop.LOSS_BASE + TacticalShop.LOSS_STEP * int(streak[loser])
	)
	streak[loser] = mini(int(streak[loser]) + 1, 4)
	streak[winner_team] = maxi(0, int(streak[winner_team]) - 1)
	var pay_win := (
		TacticalShop.OBJECTIVE_REWARD
		if how in ["BOMB", "DEFUSED", "RESCUE"]
		else TacticalShop.WIN_REWARD
	)
	var planted := (
		String(st.bomb.get("state", "")) in ["planted", "blown", "defused"]
		if st.bomb is Dictionary
		else false
	)
	for p: Player in game.players:
		var amount := pay_win if p.team == winner_team else pay_loss
		if p.team == loser and planted and p.team == attack_team(st):
			amount += TacticalShop.PLANT_TEAM_BONUS
		pay(st, p, amount)
	st.phase = "post"
	st.phase_until = game.clock + POST
	Modes.say(game, round_line(st), POST)
	var line := "ann_outlaws" if winner_team == int(st.outlaws) else "ann_deputies"
	if how == "DEFUSED":
		line = "ann_defused"
	elif how == "RESCUE":
		line = "ann_hostage_out"
	game.sound.play(line, .95)


## The banner line for the round just taken.
func round_line(st) -> String:
	var team := int(st.round_winner)
	var side: String = SIDE_NAMES[0 if team == int(st.outlaws) else 1]
	var why := ""
	match String(st.round_reason):
		"BOMB":
			why = "THE SHINE BOMB WENT UP"
		"DEFUSED":
			why = "THE FUSE IS CUT"
		"RESCUE":
			why = "A HOSTAGE GOT OUT"
		"WIPE":
			why = "NOBODY LEFT STANDING"
		"TIME":
			why = "THE CLOCK RAN OUT"
	return "%s TAKE IT. %s." % [side, why]


static func pay(st, p: Player, amount: int) -> void:
	st.money[p.slot] = clampi(int(st.money[p.slot]) + amount, 0, TacticalShop.MAX_MONEY)


## Nobody comes back inside a round; a kill pays the killer by their gun.
func downed(game, st, p: Player, by: int) -> void:
	p.deaths += 1
	var text := "%s CASHED OUT" % Modes.tag(p)
	var team := p.team
	if by >= 0 and by != p.slot and by < game.players.size():
		var killer: Player = game.players[by]
		team = killer.team
		if killer.team != p.team:
			killer.frags += 1
			var gun := killer.armory.active
			pay(st, killer, TacticalShop.kill_reward(gun))
			var label := String(Weapons.LABELS[gun]).split(" [")[0]
			text = "%s  %s  %s" % [Modes.tag(killer), label, Modes.tag(p)]
	elif by == p.slot:
		p.frags -= 1
	st.feed.append([text, game.clock + FEED_SECONDS, team])
	dropped(game, st, p)


func _trim_feed(game, st) -> void:
	var keep: Array = []
	for row: Array in st.feed:
		if float(row[1]) > game.clock:
			keep.append(row)
	while keep.size() > 5:
		keep.pop_front()
	st.feed = keep


func defeated(_game, _st) -> bool:
	return false


func over(_game, st) -> bool:
	return bool(st.match_over)


## Freeze time: everyone looks about but stays put. A player planting or
## cutting a fuse stands still too, and a hostage's carrier walks.
func hold_controls(game, st, by_slot: Array) -> Array:
	var phase := String(st.phase)
	var out := by_slot.duplicate()
	for p: Player in game.players:
		var c: Game.Controls = by_slot[p.slot] if p.slot < by_slot.size() else null
		if c == null:
			continue
		var frozen := phase == "freeze" or phase == "over"
		var busy := busy_with_objective(st, p)
		if not frozen and not busy and not slowed(st, p):
			continue
		var held := Game.Controls.new()
		held.turn = c.turn
		held.look = c.look
		held.hold = c.hold
		held.use = c.use
		held.weapon = c.weapon
		held.cycle = c.cycle
		if not frozen and not busy:
			held.forward = c.forward
			held.strafe = c.strafe
			held.fire = c.fire
			held.alt_fire = c.alt_fire
			held.crouch = c.crouch
		out[p.slot] = held
	return out


## Planting or cutting a fuse this moment (they stand still).
func busy_with_objective(_st, _p: Player) -> bool:
	return false


## Walking, not running (a hostage on your back).
func slowed(_st, _p: Player) -> bool:
	return false


func pvp_damage(
	game, attacker: Player, victim: Player, amount: float, weapon: int, height: float
) -> float:
	if hurt_scale(game, attacker, victim, false) <= 0.0:
		return 0.0
	var spec: Array = TacticalShop.DAMAGE.get(weapon, TacticalShop.DAMAGE_DEFAULT)
	var head := height >= TacticalShop.HEAD_FROM
	var dealt := amount * float(spec[0]) * (float(spec[2]) if head else 1.0)
	var st = Modes.feature(game)
	if st != null and victim.slot < st.armor.size():
		var shielded: bool = (
			float(st.armor[victim.slot]) > 0.0 and (not head or bool(st.helmet[victim.slot]))
		)
		if shielded:
			dealt = _through_vest(st, victim, dealt, float(spec[1]))
	return dealt / maxf(.05, float(game.incoming))


func blast_damage(game, thrower: Player, victim: Player, amount: float, kind: String) -> float:
	var scale := hurt_scale(game, thrower, victim, true)
	if scale <= 0.0:
		return 0.0
	var dealt := (
		amount * scale * float(TacticalShop.BLAST_SCALE.get(kind, TacticalShop.BLAST_DEFAULT))
	)
	var st = Modes.feature(game)
	if st != null and victim.slot < st.armor.size() and float(st.armor[victim.slot]) > 0.0:
		dealt = _through_vest(st, victim, dealt, TacticalShop.BLAST_THROUGH)
	return dealt / maxf(.05, float(game.incoming))


## A hit of `dealt` on a player in a vest: `through` of it reaches them, the
## vest wears by half the rest, and what it could not stop goes through.
static func _through_vest(st, victim: Player, dealt: float, through: float) -> float:
	var vest := float(st.armor[victim.slot])
	var to_health := dealt * through
	var to_vest := (dealt - to_health) * .5
	if to_vest > vest:
		to_health += (to_vest - vest) * 2.0
		to_vest = vest
	st.armor[victim.slot] = maxf(0.0, vest - to_vest)
	return to_health


# --------------------------------------------------------------- objective


## The objective at the round's start (the bomb handed out, hostages back).
func reset_objective(_game, _st) -> void:
	pass


func objective_tick(_game, _st, _dt: float) -> void:
	pass


## [winning team, how] when the round is decided now, else [].
func round_check(_game, _st) -> Array:
	return []


## A player went down: what they carried falls where they stood.
func dropped(_game, _st, _p: Player) -> void:
	pass


## The two teams' rows in front, then [tag, frags, deaths, slot] per player,
## the most frags first.
func scores(game, st) -> Array:
	var order: Array = game.players.duplicate()
	order.sort_custom(
		func(a: Player, b: Player) -> bool:
			if a.frags != b.frags:
				return a.frags > b.frags
			if a.deaths != b.deaths:
				return a.deaths < b.deaths
			return a.slot < b.slot
	)
	var w: Array = st.wins if st != null else [0, 0]
	var rows: Array = [[TEAM_NAMES[0], int(w[0]), -1, -1], [TEAM_NAMES[1], int(w[1]), -1, -1]]
	for p: Player in order:
		rows.append([Modes.tag(p), p.frags, p.deaths, p.slot])
	return rows


func team_score(game, team: int) -> int:
	var st = Modes.feature(game)
	return int(st.wins[team]) if st != null else 0


func leader_score(game) -> int:
	return maxi(team_score(game, 0), team_score(game, 1))


func winner(game) -> String:
	var a := team_score(game, 0)
	var b := team_score(game, 1)
	return "TIE" if a == b else TEAM_NAMES[0 if a > b else 1]


## The middle of a [x0, y0, x1, y1] box (cells, both corners inside it).
static func box_centre(box: Array) -> Vector2:
	return Vector2(
		(float(box[0]) + float(box[2]) + 1.0) * .5, (float(box[1]) + float(box[3]) + 1.0) * .5
	)


static func in_box(box: Array, x: float, y: float) -> bool:
	return (
		box.size() >= 4
		and x >= float(box[0])
		and x < float(box[2]) + 1.0
		and y >= float(box[1])
		and y < float(box[3]) + 1.0
	)
