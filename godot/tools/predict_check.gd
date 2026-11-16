## An online client's own shots, reloads and pickups shown at once and put
## right when the host's word comes (src/net/net_shot_predict.gd), without the
## network: a deathmatch on the range is the client's copy, a NetSync.Client
## filled by hand is its link, and the host plays each input LAG ticks after
## it was pressed (as it can refuse one). Every frame the copy is led and
## drawn as main.gd does (frame, look, restore), and the copy's sound is
## counted. Cases:
##
## - a shot the host plays: one bang, one kick, the rounds down at the press
##   and never back up, the mark and its tick once;
## - a shot the host refuses: the bang was heard, but the rounds come back,
##   the mark goes and its blood is taken away;
## - out of rounds: one dry click, no shot shown;
## - a hit the host judges a miss (the target was elsewhere): the shot stands,
##   the mark and blood are withdrawn;
## - a gun taken up and fired at once: no shot while it comes up;
## - a pickup the host plays (one sound, gone at once) and one it refuses (it
##   comes back in the picture);
## - a reload pressed mid-burst with the trigger held: every bang heard once,
##   the reload's sound once, the rounds only ever go down until it is in;
## - nothing on a game nobody watches (single player, a host).
##
##   godot --headless --path godot --script res://tools/predict_check.gd
##
## Prints PREDICT CHECK OK.
extends SceneTree

const STEP := NetSync.STEP
## Ticks between a press and the host playing it (100 ms).
const LAG := 12

var failures: Array = []


## The copy's sound: what it was asked to play, by name.
class Ears:
	extends GameSound
	var heard: Array = []

	func has(_cue: String) -> bool:
		return true

	func play(name: String, _volume := 1.0, _pan := 0.0, _cutoff := Sound.OPEN_CUTOFF) -> void:
		heard.append(name)

	func play_at_rate(
		name: String, _volume := 1.0, _pan := 0.0, _cutoff := Sound.OPEN_CUTOFF, _rate := 1.0
	) -> void:
		heard.append(name)

	func count(cue: String) -> int:
		return heard.count(cue)


## A copy, its link and its watcher; the host plays each input LAG ticks on.
class Rig:
	extends RefCounted
	var g: Game
	var me: Player
	var them: Player
	var client: NetSync.Client
	var pred := NetShotPredict.new()
	var ears := Ears.new()
	var queue: Array = []
	## Each frame: the rounds drawn, the pickups drawn, the feel's kick.
	var drawn_rounds: Array = []
	var drawn_pickups: Array = []
	var copy_pickups: Array = []
	## Every tracer and every shell or bit of debris seen drawn.
	var seen_streaks := {}
	var seen_bits := {}
	var kicks := 0
	var copy_shots := 0
	var refuse := Callable()
	var _kick_was := 0.0

	func _init(game: Game) -> void:
		g = game
		me = g.players[0]
		them = g.players[1]
		g.sound = ears
		g.speaker = ears
		client = NetSync.Client.new(null, Callable())
		client.slot = 0
		pred.now_ms = 0.0

	## One frame: `c` sent, the host plays what is LAG old, the copy is drawn.
	func step(c: Game.Controls) -> void:
		_send(c)
		queue.append(c)
		while queue.size() > LAG:
			_play()
		_draw()

	func _send(c: Game.Controls) -> void:
		client.sent[client.input_seq] = NetWire.pack_controls(c)
		client.input_seq += 1

	func _play() -> void:
		var c: Game.Controls = queue.pop_front()
		if refuse.is_valid():
			c = refuse.call(c)
		var seq := client.input_ack + 1
		var tick := client.game_tick + 1
		client.input_ack = seq
		client.input_ack_tick = tick
		client.latest = tick
		client.latest_tick = tick
		client.echo[tick] = {0: NetWire.pack_controls(c)}
		g.tick(STEP, {0: c, 1: Game.Controls.new()})
		client.echo.erase(tick)
		client.game_tick = tick
		if me.armory.shot_age == 0.0:
			copy_shots += 1

	func _draw() -> void:
		pred.now_ms += STEP * 1000.0
		var walked := NetPredict.lead(g, me, client.unplayed_inputs())
		var kept := pred.frame(g, me, client)
		drawn_rounds.append(me.armory.loaded[me.armory.active])
		drawn_pickups.append(g.pickups.size())
		var feel: Object = g.features.get("feel")
		var kick: float = feel.get("kick")
		if kick > _kick_was + .3:
			kicks += 1
		_kick_was = kick
		pred.restore(g, me, kept)
		NetPredict.restore(me, walked)
		copy_pickups.append(g.pickups.size())
		var wfx: Object = g.features.get("weapon_fx")
		var streaks: Array = wfx.get("streaks")
		for streak: Array in streaks:
			seen_streaks[str(streak[0]) + str(streak[2])] = true
		var debris: Object = g.features.get("debris")
		var bits: Array = debris.get("bits")
		for bit: Object in bits:
			seen_bits[bit.get_instance_id()] = true

	func idle(frames: int) -> void:
		for i in frames:
			step(Game.Controls.new())

	## Plays out everything pressed and lets the window pass.
	func settle() -> void:
		idle(LAG + NetShotPredict.EXPIRE + 8)


func _init() -> void:
	_run.call_deferred()


func _check(ok: bool, text: String) -> void:
	print("  ok   " if ok else "  FAIL ", text)
	if not ok:
		failures.append(text)


func _run() -> void:
	var main: Control = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	_shot_played(main)
	_shot_refused(main)
	_dry(main)
	_hit_withdrawn(main)
	_switching(main)
	_pickups(main)
	_reload_mid_burst(main)
	_nobody_watching(main)
	print("")
	print("PREDICT CHECK OK" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


## The range's deathmatch, player two a few steps ahead of player one, who
## holds a full .38 and aims at them.
func _rig(main) -> Rig:
	var g: Game = main.make_game("range")
	g.configure({"difficulty": 1})
	Modes.setup(g, Modes.DEATHMATCH, 2)
	g.tick(STEP, Game.Controls.new())
	var a: Player = g.players[0]
	var b: Player = g.players[1]
	var spot := Modes.open_spot_near(g, a.x, a.y)
	var dir := (spot - Vector2(a.x, a.y)).normalized()
	var far := Vector2(a.x, a.y) + dir * 2.5
	if g.world.blocked(far.x, far.y, .3) or not g.world.visible(a.x, a.y, far.x, far.y):
		far = spot
	Modes.place(g, b, far.x, far.y, 0.0)
	a.armory.select(Weapons.REVOLVER, g)
	a.armory.loaded[Weapons.REVOLVER] = 6
	a.armory.reserve[Weapons.REVOLVER] = 30
	for i in 60:
		g.tick(STEP, Game.Controls.new())
	_aim(a, b)
	var r := Rig.new(g)
	r.idle(LAG + 4)  # the link going: the host has played (and said so) inputs of ours
	return r


func _aim(a: Player, b: Player) -> void:
	a.angle = atan2(b.y - a.y, b.x - a.x)
	a.pitch = (b.eye - .35 - a.eye) / maxf(.5, Vector2(b.x - a.x, b.y - a.y).length())
	a.pitch *= View.base_focal


static func _fire() -> Game.Controls:
	var c := Game.Controls.new()
	c.fire = true
	return c


func _shot_played(main) -> void:
	var r := _rig(main)
	r.step(_fire())
	var pressed_at := r.drawn_rounds.size() - 1
	var shown_now: bool = r.drawn_rounds[pressed_at] == 5
	var heard_at_press := r.ears.count("revolver")
	var marked_at_press := r.g.hit_mark_until > r.g.clock
	r.settle()
	var never_back := true
	for k in range(pressed_at, r.drawn_rounds.size()):
		never_back = never_back and r.drawn_rounds[k] == 5
	_check(
		shown_now and heard_at_press == 1 and marked_at_press,
		"a shot shows at the press: rounds 6 -> 5, the bang, the mark (heard %d)" % heard_at_press
	)
	_check(
		(
			r.copy_shots == 1
			and r.ears.count("revolver") == 1
			and r.kicks == 1
			and r.seen_streaks.size() == 1
			and never_back
			and r.pred.stats["confirmed"] == 1
			and r.pred.stats["withdrawn"] == 0
		),
		(
			(
				"the host plays it: one bang (%d), kick (%d), tracer (%d);"
				+ " the rounds never back up; confirmed"
			)
			% [r.ears.count("revolver"), r.kicks, r.seen_streaks.size()]
		)
	)
	_check(
		r.ears.count("hit_tick") == 1 and r.pred.stats["hits_confirmed"] == 1,
		"the hit is confirmed: its tick heard once (%d)" % r.ears.count("hit_tick")
	)
	_check(
		r.g.hands_watch == r.pred and not r.g.own_quiet and r.pred.pending.is_empty(),
		"nothing left waiting, the copy's looks not held"
	)


func _shot_refused(main) -> void:
	var r := _rig(main)
	r.refuse = func(c: Game.Controls) -> Game.Controls:
		c.fire = false
		return c
	r.step(_fire())
	var specks: Array = r.pred.pending[0]["specks"] if not r.pred.pending.is_empty() else []
	var blood := specks.size()
	r.settle()
	var left := 0
	for s: Variant in specks:
		left += 1 if r.g.specks.has(s) else 0
	_check(
		(
			r.copy_shots == 0
			and r.drawn_rounds[-1] == 6
			and r.pred.stats["withdrawn"] == 1
			and r.pred.stats["hits_withdrawn"] == 1
			and r.g.hit_mark_until <= r.g.clock
			and blood > 0
			and left == 0
			and r.ears.count("revolver") == 1
		),
		(
			(
				"a shot the host refuses: rounds back to %d, the mark and %d bits of blood"
				+ " withdrawn, the bang not heard again"
			)
			% [r.drawn_rounds[-1], blood]
		)
	)


func _dry(main) -> void:
	var r := _rig(main)
	r.me.armory.loaded[Weapons.REVOLVER] = 0
	r.me.armory.reserve[Weapons.REVOLVER] = 0
	r.step(_fire())
	var clicked := r.ears.count("dry_revolver")
	r.settle()
	_check(
		(
			clicked == 1
			and r.ears.count("dry_revolver") == 1
			and r.ears.count("revolver") == 0
			and r.pred.stats["shots"] == 0
		),
		"out of rounds: one dry click at the press, heard once, no shot shown"
	)


func _hit_withdrawn(main) -> void:
	var r := _rig(main)
	r.step(_fire())
	var specks: Array = r.pred.pending[0]["specks"] if not r.pred.pending.is_empty() else []
	# The host had them a step aside: the copy (put back on its word) agrees.
	var side := Vector2(-sin(r.me.angle), cos(r.me.angle)) * 1.2
	var b := r.them
	if not r.g.world.blocked(b.x + side.x, b.y + side.y, .3):
		b.x += side.x
		b.y += side.y
	else:
		b.x -= side.x
		b.y -= side.y
	r.settle()
	var left := 0
	for s: Variant in specks:
		left += 1 if r.g.specks.has(s) else 0
	_check(
		(
			r.pred.stats["confirmed"] == 1
			and r.pred.stats["hits_withdrawn"] == 1
			and r.g.hit_mark_until <= r.g.clock
			and left == 0
			and r.ears.count("revolver") == 1
		),
		"a hit judged a miss: the shot stands, its mark and blood are withdrawn"
	)


func _switching(main) -> void:
	var r := _rig(main)
	var take := _fire()
	take.weapon = Weapons.SHOTGUN
	r.step(take)
	var shown_while_up: int = r.pred.stats["shots"]
	r.settle()
	_check(
		(
			shown_while_up == 0
			and r.copy_shots == 0
			and r.ears.count("shotgun") == 0
			and r.ears.count("equip_shotgun") == 1
		),
		"a gun taken up and fired at once: no shot while it comes up, its sound once"
	)


func _pickups(main) -> void:
	for refused in [false, true]:
		var r := _rig(main)
		var a := r.me
		a.armory.reserve[Weapons.REVOLVER] = 10
		var ahead := Vector2(a.x + 1.2 * cos(a.angle), a.y + 1.2 * sin(a.angle))
		if r.g.world.blocked(ahead.x, ahead.y, .3):
			a.angle += PI
			ahead = Vector2(a.x + 1.2 * cos(a.angle), a.y + 1.2 * sin(a.angle))
		r.g.add_pickup("bullets", ahead.x, ahead.y)
		var lying := r.g.pickups.size()
		var walk := Game.Controls.new()
		walk.forward = 1.0
		var gone_at_once := false
		var heard_then := -1
		for i in 60:
			r.step(walk if i < 30 else Game.Controls.new())
			if r.pred.stats["pickups"] == 1 and heard_then < 0:
				# The frame it was taken in the picture: the copy still has it.
				gone_at_once = r.drawn_pickups[-1] == lying - 1 and r.copy_pickups[-1] == lying
				heard_then = r.ears.count("pickup")
				if refused:
					# The host's word: the pouch was full there (another pickup
					# first), so it leaves them lying.
					a.armory.reserve[Weapons.REVOLVER] = Weapons.MAX_RESERVE[Weapons.REVOLVER]
		r.settle()
		if refused:
			_check(
				(
					gone_at_once
					and heard_then == 1
					and r.ears.count("pickup") == 1
					and r.drawn_pickups[-1] == lying
					and r.pred.stats["pickups_back"] == 1
				),
				"a pickup the host refuses: gone at once with its sound, then back in the picture"
			)
		else:
			_check(
				(
					gone_at_once
					and heard_then == 1
					and r.ears.count("pickup") == 1
					and r.g.pickups.size() == lying - 1
					and r.pred.stats["pickups_taken"] == 1
				),
				(
					"a pickup the host plays: gone at once, its sound heard once (%d)"
					% r.ears.count("pickup")
				)
			)


## Every cue the copy asked for, counted: with the watcher, as a copy with no
## prediction hears it, the same.
func _reload_mid_burst(main) -> void:
	var runs: Array = []
	for predicting in [true, false]:
		NetShotPredict.enabled = predicting
		var r := _rig(main)
		var arms := r.me.armory
		var gun := Weapons.TOMMY
		arms.owned[gun] = true
		arms.loaded[gun] = Weapons.CAPACITY[gun]
		arms.reserve[gun] = Weapons.CAPACITY[gun] * 2
		arms.select(gun, r.g)
		# Away from player two, at the range's walls.
		r.me.angle += PI
		r.me.pitch = 0.0
		r.idle(60)
		var reload_ticks := ceili(Weapons.RELOAD_TIME[gun] / STEP)
		var frames := 40 + reload_ticks + 40
		for i in frames:
			var c := _fire()
			c.reload = i == 40
			r.step(c)
		r.settle()
		r.idle(360)  # every casing landed (each rings as it does)
		runs.append(r)
	NetShotPredict.enabled = true
	var r: Rig = runs[0]
	var plain: Rig = runs[1]
	var name := str(Weapons.NAMES[gun_of(r)])
	var ups := 0
	for k in range(1, r.drawn_rounds.size()):
		var now: int = r.drawn_rounds[k]
		var was: int = r.drawn_rounds[k - 1]
		if now > was:
			ups += 1
	var same := true
	var odd := ""
	var cues := {}
	for cue: String in r.ears.heard + plain.ears.heard:
		cues[cue] = true
	for cue: String in cues:
		if r.ears.count(cue) != plain.ears.count(cue):
			same = false
			odd += " %s %d/%d" % [cue, r.ears.count(cue), plain.ears.count(cue)]
	_check(
		(
			r.copy_shots > 4
			and r.copy_shots == plain.copy_shots
			and r.pred.stats["late"] == 0
			and r.pred.stats["withdrawn"] == 0
			and r.pred.stats["confirmed"] == r.copy_shots
			and ups == 2
		),
		(
			(
				"a reload mid-burst: %d shots all shown at the press, none withdrawn; the rounds"
				+ " go up only when the reload is in (%d rises: the switch, the reload)"
			)
			% [r.copy_shots, ups]
		)
	)
	_check(
		same and r.ears.count(name) == r.copy_shots,
		"every cue heard as often as a copy without prediction hears it%s" % odd
	)
	_check(
		(
			r.seen_streaks.size() == plain.seen_streaks.size()
			and r.seen_bits.size() == plain.seen_bits.size()
			and r.seen_bits.size() > 0
		),
		(
			"every tracer (%d/%d) and shell (%d/%d) shown once, as without prediction"
			% [
				r.seen_streaks.size(),
				plain.seen_streaks.size(),
				r.seen_bits.size(),
				plain.seen_bits.size()
			]
		)
	)


static func gun_of(r: Rig) -> int:
	return r.me.armory.active


func _nobody_watching(main) -> void:
	var g: Game = main.make_game("range")
	g.configure({"difficulty": 1})
	var ears := Ears.new()
	g.sound = ears
	g.speaker = ears
	g.player.armory.select(Weapons.REVOLVER, g)
	for i in 60:
		g.tick(STEP, Game.Controls.new())
	g.tick(STEP, _fire())
	_check(
		g.hands_watch == null and not g.own_quiet and ears.count("revolver") == 1,
		"a game nobody watches (single player, a host) plays and sounds as ever"
	)
