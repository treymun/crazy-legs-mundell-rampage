## Search and destroy (CLAUDE.md "Modes"; the rounds, money and sides are
## tactical_mode.gd's). The OUTLAWS carry a shine bomb (a crate of moonshine
## and dynamite) to one of the map's two sites, A or B (LevelData.tactical
## "sites": [x0, y0, x1, y1] each) and plant it: stand on the site and hold
## USE for PLANT_TIME. Once planted it blows BOMB_TIMER seconds later, killing
## anyone near (BLAST_RADIUS). The DEPUTIES cut its fuse: stand by it and
## hold USE for DEFUSE_TIME (SNIPS_TIME with wire snips, sold to deputies).
## Planting or cutting, you stand still and do not shoot.
##
## The bomb goes to one outlaw at the start of a round (the game's dice); a
## carrier who goes down drops it, and any outlaw who walks over it picks it
## up. Outlaws win by the bomb going up or by downing every deputy; deputies
## by cutting the fuse, downing every outlaw before it is planted, or the
## round's clock running out with it unplanted.
class_name BombMode
extends TacticalMode

const PLANT_TIME := 3.2
const BOMB_TIMER := 40.0
const DEFUSE_TIME := 7.0
const SNIPS_TIME := 3.5
const DEFUSE_REACH := 1.25
const PICK_UP_REACH := .75
const BLAST_RADIUS := 10.0
const BLAST_HEART := 420.0


func id() -> String:
	return Modes.BOMB


func title() -> String:
	return "SEARCH & DESTROY"


func objective_title() -> String:
	return "PLANT THE SHINE BOMB"


func round_time() -> float:
	return 105.0


func attack_team(st) -> int:
	return int(st.outlaws)


## The site under (x, y): "A", "B" or "".
static func site_at(game, x: float, y: float) -> String:
	var sites = game.world.tactical.get("sites", {})
	if not sites is Dictionary:
		return ""
	for name: String in sites:
		if TacticalMode.in_box(sites[name], x, y):
			return name
	return ""


func clock_left(game, st) -> float:
	if String(st.phase) == "live" and String(st.bomb.get("state", "")) == "planted":
		return maxf(0.0, BOMB_TIMER - (game.clock - float(st.bomb["planted_at"])))
	return super.clock_left(game, st)


func reset_objective(game, st) -> void:
	var outlaws: Array = []
	for p: Player in game.players:
		if p.team == attack_team(st):
			outlaws.append(p)
	var carrier: Player = (
		outlaws[mini(outlaws.size() - 1, int(game.rng.random() * outlaws.size()))]
		if not outlaws.is_empty()
		else null
	)
	st.bomb = {
		"state": "carried" if carrier != null else "dropped",
		"slot": carrier.slot if carrier != null else -1,
		"x": carrier.x if carrier != null else float(game.level.spawn[0]),
		"y": carrier.y if carrier != null else float(game.level.spawn[1]),
		"site": "",
		"planted_at": -1.0,
		"plant": 0.0,
		"defuse": 0.0,
		"defuser": -1,
		"by": -1,
	}


func objective_tick(game, st, dt: float) -> void:
	var bomb: Dictionary = st.bomb
	match String(bomb["state"]):
		"carried":
			_carry(game, st, bomb, dt)
		"dropped":
			for p: Player in game.players:
				if p.health <= 0 or p.team != attack_team(st):
					continue
				var gap := Vector2(float(bomb["x"]) - p.x, float(bomb["y"]) - p.y).length()
				if gap < PICK_UP_REACH:
					bomb["state"] = "carried"
					bomb["slot"] = p.slot
					if p == game.local_player:
						Modes.say(game, "YOU GOT THE SHINE BOMB. GET IT TO A SITE.", 2.4)
					break
		"planted":
			_beep(game, bomb)
			_defuse(game, st, bomb, dt)
			if (
				String(bomb["state"]) == "planted"
				and game.clock - float(bomb["planted_at"]) >= BOMB_TIMER
			):
				_blow(game, st, bomb)


func _carry(game, st, bomb: Dictionary, dt: float) -> void:
	var slot := int(bomb["slot"])
	var p: Player = game.players[slot] if slot >= 0 and slot < game.players.size() else null
	if p == null or p.health <= 0:
		bomb["state"] = "dropped"
		bomb["plant"] = 0.0
		return
	bomb["x"] = p.x
	bomb["y"] = p.y
	var site := site_at(game, p.x, p.y)
	if site == "" or not p.holding or p.air > .01:
		bomb["plant"] = 0.0
		return
	bomb["plant"] = float(bomb["plant"]) + dt
	if float(bomb["plant"]) < PLANT_TIME:
		return
	bomb["state"] = "planted"
	bomb["site"] = site
	bomb["planted_at"] = game.clock
	bomb["plant"] = 0.0
	bomb["by"] = p.slot
	TacticalMode.pay(st, p, TacticalShop.PLANT_REWARD)
	Modes.say(game, "SHINE BOMB PLANTED ON %s!" % site, 3.0)
	game.sound_at("bomb_arm", p.x, p.y)
	game.sound.play("ann_planted", .95)
	bomb["beep_at"] = game.clock + 1.0


func _defuse(game, st, bomb: Dictionary, dt: float) -> void:
	var at := Vector2(float(bomb["x"]), float(bomb["y"]))
	var who: Player = null
	var current := int(bomb["defuser"])
	for p: Player in game.players:
		if p.health <= 0 or p.team == attack_team(st) or not p.holding or p.air > .01:
			continue
		if Vector2(p.x, p.y).distance_to(at) > DEFUSE_REACH:
			continue
		# Whoever was cutting keeps at it; else the first one there.
		if who == null or p.slot == current:
			who = p
	if who == null:
		bomb["defuse"] = 0.0
		bomb["defuser"] = -1
		return
	if who.slot != current:
		bomb["defuse"] = 0.0
		bomb["defuser"] = who.slot
	bomb["defuse"] = float(bomb["defuse"]) + dt
	if float(bomb["defuse"]) >= defuse_time(st, who):
		bomb["state"] = "defused"
		TacticalMode.pay(st, who, TacticalShop.DEFUSE_REWARD)
		game.sound_at("fuse_cut", at.x, at.y)
		end_round(game, st, who.team, "DEFUSED")


## The bomb's beep, faster as its time runs out (once a second to 8 a second).
static func _beep(game, bomb: Dictionary) -> void:
	if game.clock < float(bomb.get("beep_at", 0.0)):
		return
	var left := clampf(
		(BOMB_TIMER - (game.clock - float(bomb["planted_at"]))) / BOMB_TIMER, 0.0, 1.0
	)
	bomb["beep_at"] = game.clock + lerpf(.12, 1.0, left * left)
	game.sound_at("bomb_beep", float(bomb["x"]), float(bomb["y"]), .8)


static func defuse_time(st, p: Player) -> float:
	return SNIPS_TIME if bool(st.snips[p.slot]) else DEFUSE_TIME


## The bomb goes up: a big blast, everyone near it hurt by how near.
func _blow(game, st, bomb: Dictionary) -> void:
	bomb["state"] = "blown"
	var x := float(bomb["x"])
	var y := float(bomb["y"])
	var z: float = game.world.elevation(x, y) + .3
	for k in 5:
		var a := k * TAU / 5.0
		var r := 0.0 if k == 0 else 1.6
		var bx := x + cos(a) * r
		var by := y + sin(a) * r
		game.blasts.append(Game.Blast.new(bx, by, z + .2 * k, "fire"))
		game.exploded.emit(bx, by, z, false)
	game.sound_at("explosion", x, y)
	game.burst(x, y, z, "spark", 40, 4.0)
	game.burst(x, y, z, "dust", 30, 3.0)
	game.blast_flash = .5
	game.shake = 1.0
	for p: Player in game.players:
		if p.health <= 0:
			continue
		var d := Vector2(p.x - x, p.y - y).length()
		if d >= BLAST_RADIUS:
			continue
		var amount := BLAST_HEART * pow(1.0 - d / BLAST_RADIUS, 1.5)
		if amount >= 1.0:
			game.damage(amount / maxf(.05, float(game.incoming)), [x, y], "BLAST", p)
	end_round(game, st, attack_team(st), "BOMB")


func round_check(game, st) -> Array:
	var attack := attack_team(st)
	var defend := 1 - attack
	var planted := String(st.bomb.get("state", "")) == "planted"
	if TacticalMode.alive(game, defend) == 0:
		return [attack, "WIPE"]
	if planted:
		return []
	if TacticalMode.alive(game, attack) == 0:
		return [defend, "WIPE"]
	if game.clock - float(st.live_from) >= round_time():
		return [defend, "TIME"]
	return []


func dropped(_game, st, p: Player) -> void:
	var bomb: Dictionary = st.bomb
	if String(bomb.get("state", "")) == "carried" and int(bomb["slot"]) == p.slot:
		bomb["state"] = "dropped"
		bomb["x"] = p.x
		bomb["y"] = p.y
		bomb["plant"] = 0.0
	if int(bomb.get("defuser", -1)) == p.slot:
		bomb["defuser"] = -1
		bomb["defuse"] = 0.0


func busy_with_objective(st, p: Player) -> bool:
	var bomb: Dictionary = st.bomb
	if bomb.is_empty():
		return false
	if String(bomb["state"]) == "carried" and int(bomb["slot"]) == p.slot:
		return float(bomb["plant"]) > 0.0
	return int(bomb["defuser"]) == p.slot and float(bomb["defuse"]) > 0.0


func use_prompt(game) -> String:
	var st = Modes.feature(game)
	var me: Player = game.player
	if st == null or me.health <= 0 or String(st.phase) != "live":
		return ""
	var bomb: Dictionary = st.bomb
	var state := String(bomb.get("state", ""))
	if state == "carried" and int(bomb["slot"]) == me.slot:
		var site := site_at(game, me.x, me.y)
		if site != "":
			return "HOLD %s  PLANT ON %s" % [game.use_key, site]
	elif state == "planted" and me.team != attack_team(st):
		var gap := Vector2(float(bomb["x"]) - me.x, float(bomb["y"]) - me.y).length()
		if gap <= DEFUSE_REACH:
			return "HOLD %s  CUT THE FUSE" % game.use_key
	return ""


## Planting and cutting are held, not pressed: a press only shows the prompt.
func use(game) -> bool:
	return use_prompt(game) != ""
