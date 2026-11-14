## The enemy balance yardstick: the bot (tools/bot_pilot.gd, never dodging)
## fights one hand of each hostile kind alone, in a chapter where that kind
## lives, at every difficulty, a few times, from a few cells off. Prints, per
## kind and difficulty, how long the hand lasts and how much it hurts the bot
## (and whether the bot went down), then which kinds stand out from the rest.
##
##   godot --headless --path godot --script res://tools/enemy_duels.gd
##       [-- kinds=billy,coot] [runs=3] [gun=revolver|shotgun|rifle] [gap=9] [danger]
##
## danger: the player stands still and never fires for 12 s and the hand is
## kept whole: "hurts" is what each kind deals (time to kill is tools/ttk.gd).
##
## Not in CI: it is for tuning data/tuning/enemies.cfg.
extends SceneTree

const Pilot := preload("res://tools/bot_pilot.gd")
const STEP := 1.0 / 60.0
const LIMIT := 40.0
var GAP := 9.0
## danger: how much a hand hurts a player who stands and takes it for
## DANGER_TIME seconds (the hand kept whole); otherwise a duel to the end.
var danger := false
const DANGER_TIME := 12.0
const LEVELS := ["hickston", "fair", "sawmill", "quarry", "bayou", "speedway", "mothership"]

var sound: Sound


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var kinds: Array = []
	var runs := 3
	var gun := "revolver"
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("kinds="):
			kinds = Array(String(arg).substr(6).split(",", false))
		elif String(arg).begins_with("runs="):
			runs = maxi(1, int(String(arg).substr(5)))
		elif arg == "danger":
			danger = true
		elif String(arg).begins_with("gap="):
			GAP = float(String(arg).substr(4))
		elif String(arg).begins_with("gun="):
			gun = String(arg).substr(4)
	var art := Assets.new()
	var hud := HUD.new(art)
	sound = Sound.new(art)
	root.add_child(sound)
	# Where each kind lives (the first chapter it appears in), and the hand to use.
	var home := {}
	for id: String in LEVELS:
		var data: Dictionary = JSON.parse_string(
			FileAccess.get_file_as_string("res://data/%s.json" % id)
		)
		for spec: Dictionary in data["enemies"]:
			var k := String(spec["kind"])
			if not home.has(k):
				home[k] = id
	var wanted: Array = []
	for k: String in Enemy.KINDS:
		if not bool(Enemy.KINDS[k][4]) or Enemy.BOSS_TITLES.has(k):
			continue
		if kinds.is_empty() or kinds.has(k):
			wanted.append(k)
	var rows: Array = []
	print("ENEMY DUELS (bot with the %s, %d runs, %.0f cells off)" % [gun, runs, GAP])
	print("  %-15s %-8s %10s %10s %6s" % ["kind", "level", "lasts (s)", "hurts", "downs"])
	for kind: String in wanted:
		var level := String(
			home.get(kind, home.get(String(Enemy.DEFS[kind].get("brain", "")), "hickston"))
		)
		for difficulty in 4:
			var lasted := 0.0
			var hurt := 0.0
			var downs := 0
			for run in runs:
				var r := _duel(art, hud, level, kind, difficulty, run, gun)
				lasted += float(r[0])
				hurt += float(r[1])
				downs += int(r[2])
			rows.append([kind, difficulty, lasted / runs, hurt / runs, downs])
			print(
				(
					"  %-15s %-8s %s %8.1f %10.1f %4d/%d"
					% [
						kind,
						level,
						["E", "N", "H", "W"][difficulty],
						lasted / runs,
						hurt / runs,
						downs,
						runs
					]
				)
			)
	# Who stands out at NORMAL: more than twice the median hurt, or lasting
	# more than twice / under a third of the median.
	var normal := rows.filter(func(r): return int(r[1]) == 1)
	var hurts: Array = normal.map(func(r): return float(r[3]))
	var lasts: Array = normal.map(func(r): return float(r[2]))
	hurts.sort()
	lasts.sort()
	if not normal.is_empty():
		var mh: float = hurts[hurts.size() / 2]
		var ml: float = lasts[lasts.size() / 2]
		print("\nNORMAL medians: lasts %.1f s, hurts %.1f" % [ml, mh])
		for r: Array in normal:
			var notes: Array = []
			if float(r[3]) > maxf(8.0, mh * 2.0):
				notes.append("hits hard")
			if float(r[2]) > ml * 2.0:
				notes.append("lasts long")
			if float(r[2]) < ml / 3.0:
				notes.append("folds fast")
			if int(r[4]) > 0:
				notes.append("downed the bot")
			if not notes.is_empty():
				print("  %-15s %s" % [r[0], ", ".join(notes)])
	quit()


## One duel: [seconds the hand lasted, damage it did, 1 if the bot went down].
func _duel(
	art: Assets, hud: HUD, level: String, kind: String, difficulty: int, run: int, gun: String
) -> Array:
	var g := Game.new(art, hud, sound, level)
	var options := SessionStore.defaults()
	options["difficulty"] = difficulty
	options["hints"] = 0
	g.configure(options)
	for k in run * 5:
		g.rng.random()
	# The one hand: the first of its kind (or of its regular, or its brain)
	# with open ground a few cells off in sight of it; the rest put away, and a
	# variant made from its regular.
	var matches: Array = []
	for e: Enemy in g.enemies:
		if (
			e.kind == kind
			or e.kind == String(Enemy.DEFS[kind].get("swap", ""))
			or e.kind == String(Enemy.DEFS[kind].get("brain", ""))
		):
			matches.append(e)
	var p := g.player
	var foe: Enemy = null
	for e: Enemy in matches:
		var at = _stand_off(g, e)
		if at != null:
			foe = e
			p.x = at.x
			p.y = at.y
			break
	if foe == null:
		return [0.0, 0.0, 0]
	for e: Enemy in g.enemies:
		if e != foe:
			e.alive = false
			e.hostile = false
	if foe.kind != kind:
		Variants.become(foe, kind)
	g.tick(STEP, Game.Controls.new())
	for e: Enemy in g.enemies:
		if e != foe:
			e.alive = false
	p.eye = .95 + g.world.stand(p)
	p.angle = atan2(foe.y - p.y, foe.x - p.x)
	var slot := Weapons.NAMES.find(gun)
	if slot >= 0:
		g.armory.owned[slot] = true
		g.armory.reserve[slot] = Weapons.MAX_RESERVE[slot]
		g.armory.loaded[slot] = Weapons.CAPACITY[slot]
		g.armory.active = slot
	foe.wake(g, p.x, p.y)
	var pilot = Pilot.new()
	pilot.whole = true
	var start := g.clock
	var health_was := p.health
	var hurt := 0
	while g.clock - start < (DANGER_TIME if danger else LIMIT) and foe.alive and p.health > 0:
		if danger:
			# Danger: the player stands and takes it, the hand kept whole.
			foe.hp = foe.max_hp
			var still := Game.Controls.new()
			still.turn = clampf(
				fposmod(atan2(foe.y - p.y, foe.x - p.x) - p.angle + PI, TAU) - PI, -.12, .12
			)
			g.tick(STEP, still)
		else:
			g.tick(STEP, pilot.steer(g))
			pilot.moved(g)
		if p.health < health_was:
			hurt += health_was - p.health
		health_was = p.health
	return [g.clock - start, float(hurt), 1 if p.health <= 0 else 0]


## Open ground in sight of `e`, GAP cells off or nearer, or null.
func _stand_off(g: Game, e: Enemy) -> Variant:
	for r: float in [GAP, GAP * .75, GAP * .55]:
		for k in 16:
			var a := k * TAU / 16.0
			var at := Vector2(e.x + cos(a) * r, e.y + sin(a) * r)
			if not g.world.blocked(at.x, at.y, .3) and g.world.visible(at.x, at.y, e.x, e.y):
				return at
	return null
