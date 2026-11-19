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
## - a stick of dynamite (pass 9): the match struck and the stick lit at the
##   press, the throw at the release, each heard once; one the host refuses
##   (the trigger never reached it) gives its stick back;
## - a melee swing (pass 9): the crowbar's blow on player two heard and
##   marked when it comes due, before the copy plays it, once in all;
## - USE's boot (pass 9, co-op): the boot drawn and the grunt heard at the
##   press, once in all, and the copy kicks;
## - a crossbow bolt (pass 12): drawn from the press as a ghost, then as the
##   copy's own drawn on to our time, one in the picture at every frame and
##   no step bigger than its flight's; one the host refuses goes after
##   NetOwnShots.WAIT;
## - pass 12 round 2: the scope up at the press (and, off, LAG frames on); a
##   crossbow bolt's blast where its ghost lands, LAG frames before the
##   copy's, heard once (the copy's quiet); a stick of dynamite drawn from the
##   release, one at a time, gone off when its fuse is out, heard once; a
##   hand's flinch drawn at the press and once only; USE on a door swinging
##   from the press, never back, its sound heard once;
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
	## Called each frame while the copy is led (before it is put back); what
	## it returns is kept in `probes`.
	var frame_probe := Callable()
	var probes: Array = []
	## Each frame: our own thrown shots drawn (ghosts and the copy's); every
	## frame the copy's shots were left as it has them.
	var drawn_own: Array = []
	var own_put_back := true
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
		# Our thrown shots at our time (net_own_shots.gd), as main.gd draws them.
		var copy_shots_at := []
		for s: GameState.Shot in g.shots:
			copy_shots_at.append([s, s.x, s.y, s.z])
		pred.own.begin(g, me, client.unplayed_inputs().size(), STEP)
		var own := 0
		for s: GameState.Shot in g.shots:
			own += 1 if s.slot == me.slot and not s.enemy else 0
		drawn_own.append(own)
		drawn_rounds.append(me.armory.loaded[me.armory.active])
		drawn_pickups.append(g.pickups.size())
		var feel: Object = g.features.get("feel")
		var kick: float = feel.get("kick")
		if kick > _kick_was + .3:
			kicks += 1
		_kick_was = kick
		if frame_probe.is_valid():
			probes.append(frame_probe.call())
		pred.own.end(g)
		var back := g.shots.size() == copy_shots_at.size()
		for row: Array in copy_shots_at:
			var s: GameState.Shot = row[0]
			back = back and g.shots.has(s) and s.x == row[1] and s.y == row[2] and s.z == row[3]
		own_put_back = own_put_back and back
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
	_dynamite(main, false)
	_dynamite(main, true)
	_melee(main)
	_boot(main)
	_thrown(main, false)
	_thrown(main, true)
	_scope(main, true)
	_scope(main, false)
	var copy_blast := _bolt_blast(main, false, -1)
	_bolt_blast(main, true, copy_blast)
	_dynamite_flight(main)
	_flinch(main, true)
	_flinch(main, false)
	_door(main, true)
	_door(main, false)
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


## A stick lit (the trigger held half a second) and let go.
func _dynamite(main, refused: bool) -> void:
	var r := _rig(main)
	var arms := r.me.armory
	arms.owned[Weapons.DYNAMITE] = true
	arms.reserve[Weapons.CROSSBOW] = 3
	arms.select(Weapons.DYNAMITE, r.g)
	r.idle(30)
	if refused:
		r.refuse = func(c: Game.Controls) -> Game.Controls:
			c.fire = false
			return c
	r.frame_probe = func() -> Array:
		return [arms.fuse, arms.reserve[Weapons.CROSSBOW], arms.shot_age]
	var shots_before := r.g.shots.size()
	r.step(_fire())
	var first: Array = r.probes[-1]
	var lit_at_once: bool = first[0] > 0.0 and first[1] == 2 and arms.fuse == 0.0
	var struck_then := r.ears.count("match_strike")
	for i in 29:
		r.step(_fire())
	r.step(Game.Controls.new())
	var thrown: Array = r.probes[-1]
	var thrown_at_once: bool = thrown[0] == 0.0 and thrown[2] == 0.0
	var throw_then := r.ears.count("tnt_throw")
	var flew := false
	for i in LAG + 6:
		r.step(Game.Controls.new())
		for shot: Object in r.g.shots:
			flew = flew or str(shot.get("kind")) == "tnt"
	r.settle()
	if refused:
		_check(
			(
				lit_at_once
				and struck_then == 1
				and r.ears.count("match_strike") == 1
				and not flew
				and r.g.shots.size() == shots_before
				and arms.reserve[Weapons.CROSSBOW] == 3
			),
			(
				"a stick the host never lit: struck at the press (heard once), no throw played,"
				+ (
					" the stick back in the pouch (%d; %s %d %s %d)"
					% [
						arms.reserve[Weapons.CROSSBOW],
						lit_at_once,
						r.ears.count("match_strike"),
						flew,
						r.g.shots.size() - shots_before
					]
				)
			)
		)
		return
	_check(
		lit_at_once and struck_then == 1,
		"a stick lit at the press: the match heard, the fuse burning, a stick out of the pouch"
	)
	_check(
		(
			thrown_at_once
			and throw_then == 1
			and r.pred.stats["throws"] == 1
			and flew
			and r.ears.count("match_strike") == 1
			and r.ears.count("tnt_throw") == 1
			and arms.reserve[Weapons.CROSSBOW] == 2
		),
		(
			(
				"let go: thrown at the release (heard %d then), the copy throws it %d frames on;"
				+ " the match and the throw heard once each (%d, %d)"
			)
			% [
				throw_then,
				LAG,
				r.ears.count("match_strike"),
				r.ears.count("tnt_throw"),
			]
		)
	)


## The crowbar swung at player two, close by: the blow's sound and mark when
## it comes due here, the copy's own not heard again.
func _melee(main) -> void:
	var r := _rig(main)
	var a := r.me
	var b := r.them
	var arms := a.armory
	arms.owned[Weapons.CROWBAR] = true
	arms.select(Weapons.CROWBAR, r.g)
	var near := Vector2(a.x, a.y) + Vector2(cos(a.angle), sin(a.angle)) * .7
	Modes.place(r.g, b, near.x, near.y, 0.0)
	_aim(a, b)
	r.idle(30)
	var health_before := b.health
	var how: Dictionary = Weapons.FIRING[Weapons.CROWBAR]
	var swing_at: float = how["swing_at"]
	var due := ceili(swing_at / STEP) + 1
	r.step(_fire())
	for i in due:
		r.step(Game.Controls.new())
	var heard_early := r.ears.count("crowbar_hit")
	var marked_early := r.g.hit_mark_until > r.g.clock
	var copy_struck_yet := b.health < health_before
	r.settle()
	_check(
		(
			heard_early == 1
			and marked_early
			and r.pred.stats["blows"] == 1
			and r.pred.stats["blows_confirmed"] == 1
			and r.ears.count("crowbar_hit") == 1
			and r.ears.count("crowbar") == 1
			and not copy_struck_yet
			and b.health < health_before
		),
		(
			(
				"a crowbar's blow lands at once: its sound (%d then) and the mark before the copy"
				+ " plays it; confirmed, heard once in all (%d)"
			)
			% [heard_early, r.ears.count("crowbar_hit")]
		)
	)


## USE in front of one of the county's hands in co-op: the boot.
func _boot(main) -> void:
	var g: Game = main.make_game("hickston")
	g.configure({"difficulty": 1})
	Modes.setup(g, Modes.COOP, 2)
	g.cheats.god = true
	g.tick(STEP, Game.Controls.new())
	var a: Player = g.players[0]
	var man: Enemy = null
	for e: Enemy in g.enemies:
		if e.alive and e.hostile and HitZones.limbs(e) and not Game.BrawlScript.FLYING.has(e.brain):
			man = e
			break
	if man == null:
		_check(false, "a hand to kick in Hickston")
		return
	var ahead := Vector2(a.x, a.y) + Vector2(cos(a.angle), sin(a.angle)) * .9
	if g.world.blocked(ahead.x, ahead.y, .3):
		a.angle += PI
		ahead = Vector2(a.x, a.y) + Vector2(cos(a.angle), sin(a.angle)) * .9
	man.x = ahead.x
	man.y = ahead.y
	man.dormant = false
	var r := Rig.new(g)
	r.idle(LAG + 4)
	man.x = ahead.x
	man.y = ahead.y
	var looks: Object = g.features.get("brawl_looks")
	r.frame_probe = func() -> bool: return not looks.call("boot").is_empty()
	var kick := Game.Controls.new()
	kick.use = true
	r.step(kick)
	var drawn_at_once: bool = r.probes[-1]
	var grunt_then := r.ears.count("blow_grunt")
	var brawl: Game.BrawlScript = g.features.get("brawl")
	var copy_kicked_then := brawl.kicked_at.has(0)
	for i in LAG + 2:
		r.step(Game.Controls.new())
	var copy_kicked := brawl.kicked_at.has(0)
	r.settle()
	_check(
		(
			drawn_at_once
			and grunt_then == 1
			and not copy_kicked_then
			and copy_kicked
			and r.pred.stats["boots"] == 1
			and r.ears.count("blow_grunt") == 1
		),
		(
			(
				"USE's boot shows at the press: the boot drawn, the grunt heard (%d then, %d in all);"
				+ " the copy kicks %d frames on"
			)
			% [grunt_then, r.ears.count("blow_grunt"), LAG]
		)
	)


## Pass 12: the dynamite crossbow's bolt (a projectile gun) drawn from the
## press as a ghost (net_own_shots.gd) and, once the copy fires it, as the
## copy's own drawn on to our time: one bolt in the picture at every frame
## from the press, never two, the copy's shots put back after each frame; a
## bolt the host refuses goes after NetOwnShots.WAIT.
func _thrown(main, refused: bool) -> void:
	var r := _rig(main)
	var a := r.me
	a.armory.owned[Weapons.CROSSBOW] = true
	a.armory.select(Weapons.CROSSBOW, r.g)
	a.armory.reserve[Weapons.CROSSBOW] = 8
	a.angle = fposmod(a.angle + PI, TAU)  # away from player two
	a.pitch = 0.0
	r.idle(90)
	if refused:
		r.refuse = func(c: Game.Controls) -> Game.Controls:
			c.fire = false
			return c
	r.frame_probe = func() -> Variant:
		for s: GameState.Shot in r.g.shots:
			if s.slot == a.slot and not s.enemy:
				return Vector3(s.x, s.y, s.z)
		return null
	var from := r.drawn_own.size()
	var probed := r.probes.size()
	r.step(_fire())
	r.idle(LAG + 4)
	var flying: Array = r.drawn_own.slice(from)
	# The bolt's step from frame to frame (the ghost handing over to the copy's).
	var jump := 0.0
	var was: Variant = null
	for at: Variant in r.probes.slice(probed):
		if at != null and was != null:
			var here: Vector3 = at
			var there: Vector3 = was
			jump = maxf(jump, here.distance_to(there))
		was = at
	r.frame_probe = Callable()
	r.idle(roundi(NetOwnShots.WAIT / STEP))
	var most := 0
	for n: int in flying:
		most = maxi(most, n)
	var ghosts_left := 0
	for s: GameState.Shot in r.g.shots:
		ghosts_left += 1 if s.uid <= 0 else 0
	if refused:
		_check(
			(
				r.pred.own.made == 1
				and r.pred.own.matched == 0
				and r.pred.own.ghosts.is_empty()
				and flying[0] == 1
				and r.copy_shots == 0
				and ghosts_left == 0
				and r.own_put_back
			),
			(
				"a bolt the host refuses: its ghost drawn from the press (%d), gone after %.1f s"
				% [flying[0], NetOwnShots.WAIT]
			)
		)
		return
	_check(
		(
			r.pred.own.made == 1
			and r.pred.own.matched == 1
			and flying[0] == 1
			and most == 1
			and r.copy_shots == 1
			and ghosts_left == 0
			and r.own_put_back
			and jump < .4
		),
		(
			(
				"a crossbow bolt: drawn from the press (%d), never two at once (most %d),"
				+ " the ghost matched by the copy's (%d), the copy's shots put back; its"
				+ " biggest step a frame %.2f cells (%.2f a tick in flight)"
			)
			% [flying[0], most, r.pred.own.matched, jump, 10.8 * STEP]
		)
	)


## The scope up at the press (pass 12, NetGunLead.scopes; off: when the copy
## plays ALT FIRE, LAG frames on).
func _scope(main, on: bool) -> void:
	NetGunLead.scopes = on
	var r := _rig(main)
	var a := r.me
	a.armory.owned[Weapons.HUNTER] = true
	a.armory.select(Weapons.HUNTER, r.g)
	a.armory.reserve[Weapons.HUNTER] = 20
	a.armory.loaded[Weapons.HUNTER] = Weapons.CAPACITY[Weapons.HUNTER]
	r.idle(60)
	r.frame_probe = func() -> bool: return a.scoped
	var from := r.probes.size()
	var alt := Game.Controls.new()
	alt.alt_fire = true
	r.step(alt)
	var copy_then := a.scoped
	r.idle(LAG + 4)
	var drawn: Array = r.probes.slice(from)
	var first := drawn.find(true)
	var steady := first >= 0 and not drawn.slice(first).has(false)
	NetGunLead.scopes = true
	_check(
		steady and a.scoped and not copy_then and (first == 0) == on,
		(
			"the scope (%s): drawn up %d frames after ALT FIRE (the copy's %d on), down never after"
			% ["led" if on else "the copy's", first, LAG]
		)
	)


## A direction from `a` with a wall 1.5 to 4 cells off (an angle, or NAN).
static func _wall_dir(g: Game, a: Player) -> float:
	for k in 32:
		var angle := k * TAU / 32.0
		for step in range(15, 41):
			var d := step / 10.0
			var x := a.x + cos(angle) * d
			var y := a.y + sin(angle) * d
			if g.world.blocked(x, y, .05):
				if d <= 4.0:
					return angle
				break
	return NAN


## The dynamite crossbow's bolt into a wall (pass 12, net_own_shots.gd): its
## blast heard and drawn where the ghost lands, before the copy's bolt gets
## there, and the copy's own blast not heard or drawn again (blast_quiet).
## Off: when the copy's bolt goes off (returned, frames from the press);
## on, held against that: LAG frames sooner.
func _bolt_blast(main, on: bool, copy_at: int) -> int:
	NetOwnShots.blasts = on
	var r := _rig(main)
	var a := r.me
	a.armory.owned[Weapons.CROSSBOW] = true
	a.armory.select(Weapons.CROSSBOW, r.g)
	a.armory.reserve[Weapons.CROSSBOW] = 8
	var dir := _wall_dir(r.g, a)
	if is_nan(dir):
		_check(false, "a wall near the range's spawn for the bolt")
		NetOwnShots.blasts = true
		return -1
	a.angle = dir
	a.pitch = 0.0
	r.idle(90)
	var heard0 := r.ears.count("explosion")
	r.frame_probe = func() -> int: return r.ears.count("explosion") - heard0
	var from := r.probes.size()
	r.step(_fire())
	r.idle(LAG + 30)
	var heard: Array = r.probes.slice(from)
	var first := heard.find(1)
	var copy_quiet: bool = (
		not r.pred.own.shown_blasts.is_empty() and r.pred.own.shown_blasts[0]["used"]
	)
	NetOwnShots.blasts = true
	if on:
		_check(
			(
				first >= 0
				and first <= copy_at - LAG + 1
				and heard[-1] == 1
				and r.pred.own.boomed == 1
				and copy_quiet
			),
			(
				(
					"a bolt's blast heard and drawn %d frames after the press (the copy's own"
					+ " %d), once in all (%d), the copy's kept quiet"
				)
				% [first, copy_at, heard[-1]]
			)
		)
	else:
		_check(
			first >= LAG and heard[-1] == 1,
			"(off) the bolt's blast heard when the copy's goes off, %d frames on" % first
		)
	return first


## A stick of dynamite lit and thrown (pass 12): its ghost tumbles from the
## release, one stick in the picture at every frame (the copy's hidden), and
## it goes off when its fuse is out, heard once in all (the copy's quiet).
func _dynamite_flight(main) -> void:
	var r := _rig(main)
	var a := r.me
	a.armory.owned[Weapons.DYNAMITE] = true
	a.armory.reserve[Weapons.CROSSBOW] = 3  # the sticks come out of the bolts' pouch
	a.armory.select(Weapons.DYNAMITE, r.g)
	a.angle = fposmod(a.angle + PI, TAU)
	a.pitch = 8.0
	r.idle(60)
	var heard0 := r.ears.count("explosion")
	r.frame_probe = func() -> Array:
		var sticks := 0
		for s: GameState.Shot in r.g.shots:
			sticks += 1 if s.kind == "tnt" else 0
		return [sticks, r.ears.count("explosion") - heard0]
	for i in 20:
		r.step(_fire())  # the match struck, the fuse burning
	var from := r.probes.size()
	r.step(Game.Controls.new())  # let go
	r.idle(roundi(Weapons.DYNAMITE_FUSE / STEP) + LAG + 10)
	var rows: Array = r.probes.slice(from)
	var most := 0
	var drawn_first := -1
	var boom_at := -1
	for i in rows.size():
		var row: Array = rows[i]
		most = maxi(most, row[0])
		if drawn_first < 0 and row[0] > 0:
			drawn_first = i
		if boom_at < 0 and row[1] > 0:
			boom_at = i
	var last: Array = rows[-1]
	_check(
		drawn_first == 0 and most == 1 and last[1] == 1 and boom_at >= 0 and r.pred.own.boomed == 1,
		(
			(
				"a stick thrown: drawn from the release (%d), never two (most %d), gone off"
				+ " %d frames on, heard once in all (%d)"
			)
			% [drawn_first, most, boom_at, last[1]]
		)
	)


## Our shot on a hand (pass 12, net_hit_looks.gd): it flinches at the press
## (its flash and pain pose drawn), and not again when the copy's hurt lands;
## off: LAG frames on, when the copy plays it.
func _flinch(main, on: bool) -> void:
	NetHitLooks.enabled = on
	var g: Game = main.make_game("hickston")
	g.configure({"difficulty": 1})
	Modes.setup(g, Modes.COOP, 2)
	g.cheats.god = true
	g.tick(STEP, Game.Controls.new())
	var a: Player = g.players[0]
	var man: Enemy = null
	for e: Enemy in g.enemies:
		if e.alive and e.hostile and e.hp > 60.0 and not Game.BrawlScript.FLYING.has(e.brain):
			man = e
			break
	if man == null:
		_check(false, "a hand to shoot in Hickston")
		NetHitLooks.enabled = true
		return
	var spot := Vector2(a.x, a.y) + Vector2(cos(a.angle), sin(a.angle)) * 2.2
	if g.world.blocked(spot.x, spot.y, .4):
		a.angle += PI
		spot = Vector2(a.x, a.y) + Vector2(cos(a.angle), sin(a.angle)) * 2.2
	a.armory.select(Weapons.REVOLVER, g)
	a.armory.loaded[Weapons.REVOLVER] = 6
	var r := Rig.new(g)
	var place := func() -> void:
		man.x = spot.x
		man.y = spot.y
		man.dormant = false
		man.alerted = false
		man.windup = 0.0
		a.angle = atan2(man.y - a.y, man.x - a.x)
		a.pitch = (g.world.stand(man) + man.height * .55 - a.eye) / 2.2 * View.base_focal
	place.call()
	r.idle(LAG + 4)
	place.call()
	r.frame_probe = func() -> bool: return man.hit_flash > 0.0
	var from := r.probes.size()
	r.step(_fire())
	for i in LAG + 20:
		r.step(Game.Controls.new())
	var drawn: Array = r.probes.slice(from)
	var first := drawn.find(true)
	var rises := 0
	for i in drawn.size():
		if drawn[i] and (i == 0 or not drawn[i - 1]):
			rises += 1
	NetHitLooks.enabled = true
	_check(
		first >= 0 and rises == 1 and (first == 0) == on and (first >= LAG) == (not on),
		(
			"a hand shot (%s): its flinch drawn %d frames after the press, once (%d)"
			% ["led" if on else "the copy's", first, rises]
		)
	)


## USE on a shut door (pass 12, net_use_looks.gd): it swings from the press,
## never back, its sound heard once in all (the copy's dropped); off: when
## the copy plays USE, LAG frames on.
func _door(main, on: bool) -> void:
	NetUseLooks.enabled = on
	var g: Game = main.make_game("hickston")
	g.configure({"difficulty": 1})
	Modes.setup(g, Modes.COOP, 2)
	g.cheats.god = true
	g.tick(STEP, Game.Controls.new())
	var a: Player = g.players[0]
	var door: LevelData.Door = null
	for d: LevelData.Door in g.world.doors:
		var cell := Vector2i(d.x, d.y)
		if (
			not d.opened
			and d.key == ""
			and not d.secret
			and not d.blast_only
			and not g.world.controlled_doors.has(cell)
			and not g.world.crouch_doors.has(cell)
		):
			for side: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				var at := d.center() + side * 1.1
				if not g.world.blocked(at.x, at.y, .3):
					door = d
					a.x = at.x
					a.y = at.y
					a.angle = atan2(-side.y, -side.x)
					a.pitch = 0.0
					break
		if door != null:
			break
	if door == null:
		_check(false, "a plain shut door in Hickston")
		NetUseLooks.enabled = true
		return
	for e: Enemy in g.enemies:
		e.dormant = true  # nothing in the way, nothing to boot
	var r := Rig.new(g)
	r.idle(LAG + 4)
	var heard0 := r.ears.count("door")
	r.frame_probe = func() -> float: return door.progress
	var from := r.probes.size()
	var use := Game.Controls.new()
	use.use = true
	r.step(use)
	r.idle(LAG + 50)
	var drawn: Array = r.probes.slice(from)
	var first := -1
	var back := false
	for i in drawn.size():
		var p: float = drawn[i]
		if first < 0 and p > 0.0:
			first = i
		if i > 0 and p < float(drawn[i - 1]) - 1e-6:
			back = true
	NetUseLooks.enabled = true
	_check(
		(
			door.opened
			and first >= 0
			and (first <= 1) == on
			and (first >= LAG) == (not on)
			and not back
			and r.ears.count("door") - heard0 == 1
		),
		(
			"USE on a door (%s): it swings %d frames after the press, never back, heard once (%d)"
			% ["led" if on else "the copy's", first, r.ears.count("door") - heard0]
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
