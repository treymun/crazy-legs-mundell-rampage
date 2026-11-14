## Maw Glorb's fight and the mothership coming apart (chapter 7, the last).
##
## Maw is the chapter's finale (enemies.cfg [maw]); this runs everything her
## fight has that the other bosses' do not. Three phases by her health: in her
## housecoat (rolling-pin slams on a marked circle, hair-dryer heat in a fan
## along marked lanes, hollers to the pods for her younguns); the housecoat on
## fire (stomps whose ring of cracks rolls out over the deck and has to be
## jumped, and the tractor beam loose on the floor, dragging and burning); out
## of the housecoat (all of it quicker, more beams, wider slams, and her hot
## curlers thrown onto marked spots round the player; the core goes critical:
## features/boss_arenas.gd). On HOG WILD the rolling pin comes down twice, the
## second time where the player stood as it first landed. Each attack is
## picked as she starts to wind up, so its marks lie on the floor the whole
## wind-up and the boss bar names it. When she falls the chamber shakes and
## burns, her pod crew drop where they stand, and the ship keeps coming apart
## round the player all the way to the escape outhouse.
##
## The level gives the pods' places (boss_decoys); the middle of the chamber and
## its reach come from them. The ship's coloured lights come from the glowing
## boards the plan put up (LIGHTS). Saved: whether she has fallen. Her phase
## follows her health; the crew she called are the posse feature's to keep.
extends GameFeature

const LEVEL := "mothership"
const BOSS := "maw"
const TRACK := "boss_mothership"
## Her picks, phase by phase, taken in turn by her attack count.
const PATTERN := {
	1: ["slam", "sweep", "slam", "call", "sweep", "slam", "sweep"],
	2: ["slam", "stomp", "sweep", "call", "slam", "stomp", "sweep"],
	3: ["stomp", "curlers", "slam", "sweep", "curlers", "call", "slam", "sweep"],
}
const TELLS := {
	"slam": "ROLLIN' PIN",
	"sweep": "HAIR DRYER",
	"stomp": "STOMP! JUMP IT",
	"call": "YOUNGUNS!",
	"curlers": "HOT CURLERS!",
}
const PHASE_LINES := ["", "", "HOUSECOAT'S ON FIRE", "OUT OF THE HOUSECOAT"]
## Seconds of wind-up for each attack (then scaled by PACE and the phase) and
## of cooldown after it.
const WINDUP := {"slam": 1.05, "sweep": .85, "stomp": 1.0, "call": .9, "curlers": .95}
const COOLDOWN := {"slam": 1.5, "sweep": 1.35, "stomp": 1.6, "call": 1.9, "curlers": 1.6}
## Her hot curlers: how many, how far round the player, how wide each lands;
## HOG WILD's second pin: how long after the first.
const CURLER_COUNT := 5
const CURLER_SPREAD := 2.1
const CURLER_R := 1.0
const PIN_AGAIN := .6
## By DIFFICULTY, EASY .. HOG WILD: wind-ups and cooldowns stretched or cut,
## how hard she hits, the most pod crew up at once, beams loose in phases 2, 3.
const PACE := [1.35, 1.0, .9, .8]
const HARM := [.45, .66, .9, 1.2]
const CREW_CAP := [2, 3, 4, 5]
const BEAMS := [[1, 1], [1, 2], [2, 2], [2, 3]]
## Who each phase calls up from the pods.
const CALLS := {1: ["drone", "drone"], 2: ["drone", "probe"], 3: ["tin_guard", "drone"]}
const CREW := ["drone", "probe", "tin_guard"]
const SLAM_REACH := [2.1, 2.1, 2.6]
const RING_SPEED := 5.2
const BEAM_REACH := 1.3
## Boards that throw coloured light: image -> [r, g, b, radius, strength].
const LIGHTS := {
	"ship_glyphs_a": [.45, 1.0, .6, 3.2, .7],
	"ship_glyphs_b": [1.0, .75, .4, 3.2, .6],
	"town_cow_tube": [.4, 1.0, .6, 3.2, .85],
	"town_ship_engine": [.5, 1.0, .55, 6.5, 1.5],
	"town_pod": [.45, 1.0, .65, 2.8, .65],
	"town_corn_tray": [.8, .45, 1.0, 3.8, .9],
	"town_jukebox_rig": [1.0, .5, .8, 3.8, .9],
	"town_alien_console": [.5, .9, 1.0, 2.8, .6],
	"town_beam_emitter": [.6, 1.0, .8, 7.0, 1.3],
	"town_specimen_jar": [.4, 1.0, .6, 2.2, .5],
}
## The chapter's own sounds once made (docs/new_chapters/mothership_audio.md),
## and what stands in for each till then.
const CUES := {
	"slam_warn": ["maw_pin_raise", "foreman_warn"],
	"slam": ["maw_pin_slam", "explosion"],
	"sweep_warn": ["maw_dryer_whine", "sheriff_siren"],
	"sweep": ["maw_dryer_blast", "sheriff_shot"],
	"stomp_warn": ["maw_stomp_warn", "baron_warn"],
	"stomp": ["maw_stomp", "distant_quarry_blast"],
	"call_warn": ["maw_holler", "sheriff_spot"],
	"call": ["pod_open", "secret_slide"],
	"rage": ["maw_rage", "sheriff_rage"],
	"bare": ["maw_bare", "baron_rage"],
	"death": ["maw_death", "sheriff_death"],
	"intro": ["maw_intro", "shakedown_intro"],
	"end": ["maw_end", "shakedown_end"],
	"beam": ["beam_hum", "arm_ready"],
	"quake": ["ship_quake", "distant_quarry_blast"],
}

var maw: Enemy = null
var center := Vector2.ZERO
var reach := 9.0
var pods: Array = []
var phase := 1
var phase_at := -10.0
## The attack she is winding up (picked at the wind-up's start), and whether
## she was winding up last tick.
var pending := ""
var winding := false
## Stomp rings rolling out: [x, y, born, struck] (struck: player one; the
## others as bits of a fifth element, added when first needed).
var rings: Array = []
## Where a slam landed lately, for its cracks: [x, y, reach, at].
var cracks: Array = []
## HOG WILD's second pins on their way down: [x, y, lands_at].
var pins: Array = []
## When the loose beam last burned player one, and each other player by slot.
var beam_hurt_at := -10.0
var beam_hurt := {}
var fallen_at := -1.0
var blasts_done := 0
var next_quake := 0.0
var said := 0
var music_check := 0.0
## Beam emitters' places and heights: each throws a column of light to the deck.
var emitters: Array = []


func id() -> String:
	return "mothership"


func attach() -> void:
	if game.level.id != LEVEL:
		return
	for e: Enemy in game.wave:
		if e.kind == BOSS:
			maw = e
	pods = game.world.boss_decoys.duplicate()
	if not pods.is_empty():
		var sum := Vector2.ZERO
		for p: Vector2 in pods:
			sum += p
		center = sum / pods.size()
		reach = 99.0
		for p: Vector2 in pods:
			reach = minf(reach, center.distance_to(p) - 1.2)
	elif maw != null:
		center = Vector2(maw.x, maw.y)
	_light_the_ship()
	game.ticked.connect(_tick)
	game.station_done.connect(_station)
	game.enemy_killed.connect(_killed)


func save() -> Dictionary:
	return {"fallen": true} if fallen_at >= 0.0 else {}


func restore(state: Dictionary) -> void:
	if maw == null:
		return
	if bool(state.get("fallen", false)) or maw.hp <= 0.0:
		# Down already: no second fall, only the ship still shaking.
		fallen_at = game.clock - 60.0
		blasts_done = 99
		said = 9
	phase = _phase_of()
	maw.enraged = phase >= 2
	maw.speed = float(Enemy.KINDS[BOSS][1]) * (1.2 if phase == 3 else 1.0)


func cue(key: String) -> String:
	var pair: Array = CUES[key]
	return ShipAliens.cue(game, String(pair[0]), String(pair[1]))


# ------------------------------------------------------------------ the ship


## Every glowing board in LIGHTS lights the room round it (the triggers
## feature keeps game.trigger_lights; these never run out).
func _light_the_ship() -> void:
	for board: LevelData.Billboard in game.world.billboards:
		if board.image == "town_beam_emitter":
			emitters.append(Vector3(board.x, board.y, board.z))
		var spec = LIGHTS.get(board.image)
		if spec == null:
			continue
		var top: float = game.world.elevation(board.x, board.y) + board.z + board.height * .6
		game.trigger_lights.append(
			[
				board.x,
				board.y,
				top,
				float(spec[3]),
				Color(float(spec[0]), float(spec[1]), float(spec[2])),
				float(spec[4]),
				INF
			]
		)


# ------------------------------------------------------------------ the fight


func _phase_of() -> int:
	if maw == null:
		return 1
	var left := maw.hp / maw.max_hp
	return 3 if left <= ShipAliens.BARE_AT else 2 if left <= 2.0 / 3.0 else 1


func _fighting() -> bool:
	return maw != null and maw.alive and not maw.dormant


## The core iris is open: she wakes (the game's wave does the waking).
func _station(station_id: String) -> void:
	if game.world.extraction == null or station_id != game.world.extraction.shutdown:
		return
	game.message("MAW GLORB: YOU KILLED MY BABY BOY.", 4.0)
	game.sound.sting(cue("intro"))
	game.shake = minf(1.0, game.shake + .5)


func _tick(dt: float) -> void:
	if maw == null:
		return
	if fallen_at >= 0.0:
		_coming_apart()
		return
	if not _fighting():
		return
	if game.clock >= music_check and game.sound != null:
		music_check = game.clock + 1.0
		if String(game.sound.score) != TRACK:
			game.sound.set_score(TRACK)
	# In her own chamber she always knows where the player is: round the beam
	# column she comes the long way, on the flow field, rather than waiting.
	# (The player she is after, with more than one: her attacks are about them.)
	var p: Player = maw.hunted if maw.hunted != null else game.player
	if Vector2(p.x, p.y).distance_to(center) < reach + 2.0:
		maw.target = [p.x, p.y]
		maw.hunt_until = game.clock + 1.0
	var now := _phase_of()
	if now > phase:
		_new_phase(now)
	if maw.windup > 0.0 and not winding:
		_wind_up()
	winding = maw.windup > 0.0
	_rings(dt)
	_beams(dt)
	_pins()
	cracks = cracks.filter(func(c: Array) -> bool: return game.clock - float(c[3]) < 1.2)


## Half way through a phase change she staggers, hollers, and the floor jumps.
func _new_phase(to: int) -> void:
	phase = to
	phase_at = game.clock
	maw.enraged = true
	maw.enraged_at = game.clock
	maw.stun = maxf(maw.stun, 1.1)
	maw.windup = 0.0
	maw.aim_mark = null
	maw.cooldown = maxf(maw.cooldown, 1.5 * PACE[game.difficulty])
	pending = ""
	game.hitstop = maxf(game.hitstop, .15)
	game.shake = minf(1.0, game.shake + .7)
	game.blast_flash = maxf(game.blast_flash, .5)
	var floor_z: float = game.world.stand(maw)
	game.burst(maw.x, maw.y, floor_z + maw.height * .6, "spark", 24, 2.6)
	if to == 2:
		game.message("MAW GLORB IS FIGHTIN' MAD! HER HOUSECOAT'S ON FIRE!", 3.0)
		game.sound_at(cue("rage"), maw.x, maw.y, 1.0)
		game.boss_enraged.emit(maw)
	else:
		game.message("THE HOUSECOAT'S GONE. THAT'S A GIRDLE OF POWER CELLS.", 3.2)
		game.sound_at(cue("bare"), maw.x, maw.y, 1.0)
		maw.speed = float(Enemy.KINDS[BOSS][1]) * 1.2
		game.burst(maw.x, maw.y, floor_z + maw.height * .5, "powder", 20, 2.2)
	_call_crew()


## Her wind-up started (enemies.gd set it): pick the attack, time its wind-up.
func _wind_up() -> void:
	var list: Array = PATTERN[phase]
	pending = String(list[maw.attacks % list.size()])
	var p: Player = maw.hunted if maw.hunted != null else game.player
	var gap := Vector2(p.x - maw.x, p.y - maw.y).length()
	if pending == "slam" and gap > 6.5:
		pending = "sweep"
	elif pending == "stomp" and gap > reach + 2.0:
		pending = "sweep"
	elif pending == "call" and _crew_alive() >= CREW_CAP[game.difficulty]:
		pending = "sweep" if maw.attacks % 2 else "slam" if gap <= 6.5 else "sweep"
	maw.windup = float(WINDUP[pending]) * PACE[game.difficulty] * (.85 if phase == 3 else 1.0)
	maw.aim_mark = [p.x, p.y, p.eye]
	if pending == "curlers":
		_curlers()
		game.sound_at(cue("sweep_warn"), maw.x, maw.y, .9)
		return
	game.sound_at(cue(pending + "_warn"), maw.x, maw.y, .9)


## HOT CURLERS: she pulls them out of her hair and throws; each comes down on
## a marked spot round the player (features/boss_arenas.gd drops them).
func _curlers() -> void:
	var arenas = game.features.get("boss_arenas")
	if arenas == null:
		return
	var p: Player = maw.hunted if maw.hunted != null else game.player
	var spots: Array = [Vector2(p.x, p.y)]
	for k in CURLER_COUNT - 1:
		var a: float = maw.attacks * .9 + k * TAU / (CURLER_COUNT - 1)
		spots.append(Vector2(p.x + cos(a) * CURLER_SPREAD, p.y + sin(a) * CURLER_SPREAD))
	var k := 0
	for at: Vector2 in spots:
		if game.world.blocked(at.x, at.y, .2):
			continue
		arenas.drop("curler", at.x, at.y, maw.windup + .3 + k * .12, CURLER_R, 0, "HOT CURLERS")
		k += 1


## The wind-up is done (from ShipAliens.attack, by way of enemies.gd attack()).
func maw_attack(enemy: Enemy, direction: float) -> void:
	if enemy != maw:
		enemy.cooldown = 2.0
		return
	var what := pending if pending != "" else "sweep"
	match what:
		"slam":
			_slam()
		"stomp":
			_stomp()
		"call":
			_call_crew()
			game.sound_at(cue("call_warn"), maw.x, maw.y, 1.0)
		"curlers":
			var top: float = game.world.stand(maw) + maw.height * .9
			game.burst(maw.x, maw.y, top, "plasma", 12, 2.2)
			game.sound_at(cue("sweep"), maw.x, maw.y, .8)
		_:
			_sweep(direction)
	maw.cooldown = float(COOLDOWN[what]) * PACE[game.difficulty] * (.8 if phase == 3 else 1.0)
	pending = ""


func _hurt(amount: float, x: float, y: float, cause: String, who: Player = null) -> void:
	game.damage(maxf(1.0, roundf(amount * HARM[game.difficulty])), [x, y], cause, who)


## The rolling pin comes down where the player stood when she raised it, on
## everyone standing under it.
func _slam() -> void:
	var mark: Array = maw.aim_mark if maw.aim_mark != null else [game.player.x, game.player.y]
	var x := float(mark[0])
	var y := float(mark[1])
	var wide: float = SLAM_REACH[phase - 1]
	var p = game.player
	for q: Player in game.players:
		if Vector2(q.x - x, q.y - y).length() < wide and q.air < .3:
			_hurt(24.0, x, y, "ROLLIN' PIN", q)
	var ear: Player = game.local_player
	var near := Vector2(ear.x - x, ear.y - y).length()
	game.shake = minf(1.0, game.shake + maxf(.2, 1.0 - near / 10.0) * .8)
	var floor_z: float = game.world.elevation(x, y)
	game.burst(x, y, floor_z + .2, "dust", 18, 2.6)
	game.burst(x, y, floor_z + .3, "spark", 10, 2.0)
	game.sound_at(cue("slam"), x, y, 1.0)
	cracks.append([x, y, wide, game.clock])
	# Out of the housecoat on the hard settings, the blow rolls on as a ring.
	if phase == 3 and game.difficulty >= 2:
		rings.append([x, y, game.clock, false])
	# HOG WILD: the pin comes down again where the player stands now.
	if BossKit.moves(BOSS).hog_wild(game) and not bool(mark.size() > 3 and mark[3]):
		pins.append([p.x, p.y, game.clock + PIN_AGAIN])


## HOG WILD's second pins landing.
func _pins() -> void:
	var going: Array = []
	for pin: Array in pins:
		if game.clock >= float(pin[2]):
			going.append(pin)
	for pin: Array in going:
		pins.erase(pin)
		var keep = maw.aim_mark
		maw.aim_mark = [float(pin[0]), float(pin[1]), 0.0, true]
		_slam()
		maw.aim_mark = keep


## The hair dryer: a fan of heat bolts along the lanes its wind-up marked.
func _sweep(direction: float) -> void:
	var count: int = [5, 7, 9][phase - 1]
	var spread := .95
	var floor_z: float = game.world.stand(maw)
	var z := floor_z + maw.height * .62
	var p = game.player
	var gap := maxf(1.0, Vector2(p.x - maw.x, p.y - maw.y).length())
	for i in count:
		var theta := direction + (float(i) / (count - 1) - .5) * spread
		game.launch(
			maw.x + cos(theta) * (maw.radius + .2),
			maw.y + sin(theta) * (maw.radius + .2),
			z,
			theta,
			5.8,
			"lantern_bolt",
			(p.eye - z) / (gap / 5.8),
			true,
			int(roundf(9.0 * HARM[game.difficulty])),
			-1.0,
			maw.get_instance_id()
		)
	game.sound_at(cue("sweep"), maw.x, maw.y, 1.0)


## A stomp: the floor jumps and a ring of cracks rolls out from her feet.
func _stomp() -> void:
	rings.append([maw.x, maw.y, game.clock, false])
	game.shake = minf(1.0, game.shake + .6)
	var floor_z: float = game.world.stand(maw)
	game.burst(maw.x, maw.y, floor_z + .1, "dust", 22, 3.0)
	game.sound_at(cue("stomp"), maw.x, maw.y, 1.0)


## The rings: each player standing on one as it passes is thrown, unless in the air.
func _rings(_dt: float) -> void:
	var kept: Array = []
	for ring: Array in rings:
		var r: float = (game.clock - float(ring[2])) * RING_SPEED + .6
		if r > reach + 3.0:
			continue
		kept.append(ring)
		for q: Player in game.players:
			if _ring_struck(ring, q):
				continue
			var d := Vector2(q.x - float(ring[0]), q.y - float(ring[1])).length()
			if absf(d - r) < .45 and q.air < .22:
				_ring_mark(ring, q)
				_hurt(16.0, float(ring[0]), float(ring[1]), "STOMP", q)
				if q == game.local_player:
					game.shake = minf(1.0, game.shake + .4)
	rings = kept


func _ring_struck(ring: Array, q: Player) -> bool:
	if q.slot == 0:
		return bool(ring[3])
	return ring.size() > 4 and int(ring[4]) & (1 << q.slot) != 0


func _ring_mark(ring: Array, q: Player) -> void:
	if q.slot == 0:
		ring[3] = true
		return
	if ring.size() < 5:
		ring.append(0)
	ring[4] = int(ring[4]) | (1 << q.slot)


## Where beam `k` of `count` is on the deck now: wandering loops round the chamber.
func beam_at(k: int) -> Vector2:
	var t: float = game.clock - phase_at
	var a := t * .29 + k * 2.1
	var b := t * .21 * (1.0 + k * .35) + k * 1.3
	return center + Vector2(cos(a), sin(b)) * reach * .62


func beam_count() -> int:
	if phase < 2 or not _fighting():
		return 0
	return int(BEAMS[game.difficulty][phase - 2])


## The tractor beam loose on the floor: it drags whoever it touches and burns.
func _beams(dt: float) -> void:
	for k in beam_count():
		var at := beam_at(k)
		for p: Player in game.players:
			var off := Vector2(at.x - p.x, at.y - p.y)
			if off.length() > BEAM_REACH:
				continue
			var pull := off.normalized() * minf(off.length(), .9 * dt)
			var was: Player = game.player
			if p != was:
				game.focus(p)
			game.move_actor(p, pull.x, pull.y, GameState.PLAYER_RADIUS)
			if p != was:
				game.focus(was)
			var last := beam_hurt_at if p.slot == 0 else float(beam_hurt.get(p.slot, -10.0))
			if game.clock - last > .7:
				if p.slot == 0:
					beam_hurt_at = game.clock
				else:
					beam_hurt[p.slot] = game.clock
				_hurt(6.0, at.x, at.y, "BEAM", p)
				game.sound_at(cue("beam"), at.x, at.y, .8)


func _crew_alive() -> int:
	var count := 0
	for i in range(game.enemy_ids.size(), game.enemies.size()):
		var e: Enemy = game.enemies[i]
		if e.alive and CREW.has(e.kind) and Vector2(e.x, e.y).distance_to(center) < reach + 3.0:
			count += 1
	return count


## The pods open and her younguns come out of them.
func _call_crew() -> void:
	if pods.is_empty():
		return
	var room: int = CREW_CAP[game.difficulty] - _crew_alive()
	var kinds: Array = CALLS[phase]
	var want := kinds.size() + (1 if game.difficulty == 3 else 0)
	var p: Player = maw.hunted if maw.hunted != null else game.player
	var made := 0
	for i in pods.size():
		if made >= mini(room, want):
			break
		var pod: Vector2 = pods[(maw.attacks + i * 3) % pods.size()]
		var kind := String(kinds[made % kinds.size()])
		if game.world.blocked(pod.x, pod.y, float(Enemy.KINDS[kind][2]) + .05):
			continue
		if Vector2(p.x - pod.x, p.y - pod.y).length() < 2.5:
			continue
		var e := Enemy.new(kind, pod.x, pod.y, atan2(center.y - pod.y, center.x - pod.x))
		e.flank = .42 if made % 2 else -.42
		game.enemies.append(e)
		game.total_kills += 1
		e.wake(game, p.x, p.y)
		e.cooldown = 1.3
		game.burst(pod.x, pod.y, game.world.elevation(pod.x, pod.y) + 1.0, "plasma", 14, 1.6)
		game.sound_at(cue("call"), pod.x, pod.y, .9)
		made += 1
	if made > 0:
		game.message("MAW: GET HIM, YOUNGUNS!", 2.0)


# ------------------------------------------------------------------ her fall


func _killed(enemy: Enemy) -> void:
	if enemy != maw or fallen_at >= 0.0:
		return
	fallen_at = game.clock
	blasts_done = 0
	said = 0
	game.hitstop = maxf(game.hitstop, .7)
	game.shake = 1.0
	game.blast_flash = maxf(game.blast_flash, .9)
	game.sound_at(cue("death"), maw.x, maw.y, 1.0)
	game.sound.sting(cue("end"))
	rings.clear()
	cracks.clear()
	# The pods' crew drop where they stand, the ship's power going with her.
	for i in range(game.enemy_ids.size(), game.enemies.size()):
		var e: Enemy = game.enemies[i]
		if e.alive and CREW.has(e.kind) and Vector2(e.x, e.y).distance_to(center) < reach + 3.0:
			e.hurt(999.0, game, true)
	if game.sound != null:
		game.sound.set_score(game.level.score)


## The chamber burning and the ship shaking after her, to the very end.
func _coming_apart() -> void:
	var since: float = game.clock - fallen_at
	while blasts_done < 14 and since >= blasts_done * .32:
		var k := blasts_done
		var a := k * 2.4 + .5
		var r := reach * (.3 + .6 * fmod(k * .37, 1.0))
		var x := center.x + cos(a) * r
		var y := center.y + sin(a) * r
		if not game.world.blocked(x, y, .1):
			var z: float = game.world.elevation(x, y) + .6 + fmod(k * .53, 1.0) * 2.0
			game.blasts.append(GameState.Blast.new(x, y, z, "fire"))
			game.exploded.emit(x, y, z, false)
			game.burst(x, y, z, "spark", 14, 3.0)
			game.sound_at("explosion", x, y, .8)
			game.shake = minf(1.0, game.shake + .35)
		blasts_done += 1
	if said == 0 and since > .4:
		said = 1
		game.message("MAW'S DOWN! THE SHIP'S COMING APART!", 4.0)
	elif said == 1 and since > 5.0:
		said = 2
		game.message("GET TO THE ESCAPE OUTHOUSE!", 4.0)
	if since > 5.0 and game.clock >= next_quake and not game.won:
		next_quake = game.clock + 2.6
		var p = game.player
		game.shake = minf(1.0, game.shake + .35)
		game.sound_at(cue("quake"), p.x + 3.0, p.y - 2.0, .7)
		var roof: float = game.world.roof[game.world.cell(p.x, p.y)]
		var top: float = roof - .2 if roof > 0.0 else game.world.stand(p) + 2.5
		game.burst(p.x + .8, p.y + .6, top, "dust", 8, .8)
		game.burst(p.x - .7, p.y + .4, top, "spark", 5, .9)


# ------------------------------------------------------------------ the boss bar


func tell_of() -> String:
	return String(TELLS.get(pending, "ROLLIN' PIN"))


func phase_line(fallback: String) -> String:
	if game.clock - phase_at < 2.2 and phase >= 2:
		return String(PHASE_LINES[phase])
	return fallback


# ------------------------------------------------------------------ the picture


func ground_marks() -> Array:
	if maw == null:
		return []
	var out: Array = []
	for c: Array in cracks:
		out.append(_spot(float(c[0]), float(c[1]), float(c[2]) * .8, "mark_slam"))
	for pin: Array in pins:
		var t := clampf(1.0 - (float(pin[2]) - game.clock) / PIN_AGAIN, 0.0, 1.0)
		out.append(
			_spot(float(pin[0]), float(pin[1]), SLAM_REACH[phase - 1] * (.4 + .6 * t), "mark_slam")
		)
		out.append(_spot(float(pin[0]), float(pin[1]), SLAM_REACH[phase - 1], "mark_warning"))
	if _fighting() and maw.windup > 0.0 and maw.aim_mark != null:
		var mark: Array = maw.aim_mark
		match pending:
			"slam":
				out.append(
					_spot(float(mark[0]), float(mark[1]), SLAM_REACH[phase - 1], "mark_slam")
				)
			"stomp":
				for k in 24:
					var a := k * TAU / 24.0
					out.append(
						_spot(maw.x + cos(a) * 2.3, maw.y + sin(a) * 2.3, .32, "mark_warning")
					)
			"sweep":
				out.append_array(_lanes(atan2(float(mark[1]) - maw.y, float(mark[0]) - maw.x)))
	for ring: Array in rings:
		var r: float = (game.clock - float(ring[2])) * RING_SPEED + .6
		var dots := int(clampf(r * 4.0, 12.0, 44.0))
		for k in dots:
			var a := k * TAU / dots
			var x := float(ring[0]) + cos(a) * r
			var y := float(ring[1]) + sin(a) * r
			if not game.world.blocked(x, y, .05) and game.in_view(x, y, .5):
				out.append(_spot(x, y, .34, "mark_slam"))
	for k in beam_count():
		var at := beam_at(k)
		out.append(_spot(at.x, at.y, BEAM_REACH, "mark_beam"))
	return out


func _spot(x: float, y: float, r: float, image: String) -> Renderer.GroundMark:
	return Renderer.GroundMark.new(x, y, game.world.elevation(x, y) + .004, 0.0, r, r, image)


## The hair dryer's fan, marked as lanes along the deck.
func _lanes(toward: float) -> Array:
	var out: Array = []
	var count: int = [5, 7, 9][phase - 1]
	for i in count:
		var bearing := toward + (float(i) / (count - 1) - .5) * .95
		var length := 0.0
		while length < 9.0:
			var step := length + .32
			if game.world.blocked(maw.x + cos(bearing) * step, maw.y + sin(bearing) * step, .03):
				break
			length = step
		if length > 1.2:
			var mx := maw.x + cos(bearing) * (length + maw.radius) / 2.0
			var my := maw.y + sin(bearing) * (length + maw.radius) / 2.0
			out.append(
				Renderer.GroundMark.new(
					mx,
					my,
					game.world.stand(maw) + .004,
					bearing,
					(length - maw.radius) / 2.0,
					.2,
					"mark_lane"
				)
			)
	return out


func sprites() -> Array:
	if maw == null:
		return []
	var out: Array = []
	for e: Vector3 in emitters:
		if game.in_view(e.x, e.y, 1.5):
			var beam := Renderer.Sprite.new(
				e.x, e.y, "fx_beam_column", e.z + .1, game.world.stand(e)
			)
			beam.translucent = true
			beam.glow = true
			out.append(beam)
	var frame := int(game.clock * 10.0) % 4
	# The housecoat burning, all through phase two.
	if _fighting() and phase == 2:
		var floor_z: float = game.world.stand(maw)
		for k in 7:
			var a: float = k * 1.9 + game.clock * .6
			var x := maw.x + cos(a) * maw.radius * .5
			var y := maw.y + sin(a) * maw.radius * .5
			if game.in_view(x, y, 1.5):
				var fire := Renderer.Sprite.new(
					x, y, "fx_fire_%d" % ((frame + k) % 4), 1.5, floor_z + .9 + k * .42
				)
				fire.glow = true
				out.append(fire)
	for k in beam_count():
		var at := beam_at(k)
		if game.in_view(at.x, at.y, 1.5):
			var floor_z: float = game.world.elevation(at.x, at.y)
			var roof: float = game.world.roof[game.world.cell(at.x, at.y)]
			var column := Renderer.Sprite.new(
				at.x, at.y, "fx_beam_column", maxf(2.0, roof - floor_z), floor_z
			)
			column.translucent = true
			column.glow = true
			out.append(column)
	# The chamber left burning where she fell.
	if fallen_at >= 0.0 and game.clock - fallen_at < 40.0:
		for k in pods.size():
			var pod: Vector2 = pods[k]
			var spot := pod.lerp(center, .35)
			if game.in_view(spot.x, spot.y, 1.0):
				var fire := Renderer.Sprite.new(
					spot.x,
					spot.y,
					"fx_fire_%d" % ((frame + k) % 4),
					1.1,
					game.world.elevation(spot.x, spot.y)
				)
				fire.glow = true
				out.append(fire)
	return out
