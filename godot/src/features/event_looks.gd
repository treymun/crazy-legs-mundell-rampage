## The county events' sights and sounds (features/county_events.gd plays
## them): the civil defence siren, the twister's roar and the debris whirling
## round its foot, the herd's hooves and squeals and the dust they kick up,
## the revenue men's sirens and their shots' streaks, the power dying and
## coming back, the flashlight's battery on the HUD; Mundell's word on each,
## and the county radio's (KPSM's bulletin over the music, the scanner's
## call, Dub's word on it at the next break). Looks and sound only: its own
## dice, nothing saved, play never changes; a host leaves it off.
extends GameFeature

const Radio := preload("res://src/features/radio.gd")

## The debris kept whirling round a twister's foot, and the dust it raises.
const BITS := 34
const BIT_ART := [
	"fx_brk_wood_0",
	"fx_brk_wood_1",
	"fx_brk_tin_0",
	"fx_brk_redtin_1",
	"fx_brk_straw_0",
	"fx_brk_straw_1",
	"fx_splinter_0",
	"fx_chunk_1"
]
const PUFFS := 60
## How far the twister's roar carries (cells), and the hooves'.
const ROAR_REACH := 48.0
const HOOVES_REACH := 30.0
## The HUD's flashlight plate: its top left and size.
const PLATE_W := 50
const PLATE_H := 11

var dice := RandomNumberGenerator.new()
## The event and its phase as last seen (a change is a moment to mark).
var _kind := ""
var _phase := -1
## Debris round the funnel: [angle, radius, height, climb, image, spin, size].
var _bits: Array = []
## Dust: [x, y, z, age, life, size, drift x, drift y].
var _puffs: Array = []
var _squeal_at := 0.0
var _puff_at := 0.0


func id() -> String:
	return "event_looks"


func attach() -> void:
	dice.seed = 1491
	tick_with(_tick)


func _ev() -> CountyEvents:
	var ev: CountyEvents = game.features.get("events")
	return ev


func _tick(dt: float) -> void:
	var ev := _ev()
	if ev == null:
		return
	if ev.kind != _kind or ev.phase != _phase:
		_moment(ev, _kind)
		_kind = ev.kind
		_phase = ev.phase
	_beds(ev)
	_age(dt)
	match ev.kind:
		"twister":
			_whirl(ev, dt)
		"hogs":
			_herd(ev)
	if ev.kind != "twister" and not _bits.is_empty():
		_bits.clear()


## An event begun, moved on or ended: the siren, the radio, Mundell's word.
func _moment(ev: CountyEvents, was: String) -> void:
	var st := _station()
	if ev.kind == "" and was != "":
		if was == "blackout":
			game.sound.play("power_up", .8)
			game.barks.say(game, "event_light", true)
		if st != null:
			st.news("outage" if was == "blackout" else was)
		return
	if ev.phase != 0:
		return
	match ev.kind:
		"twister":
			game.sound.play("tornado_siren", .85)
			game.barks.say(game, "event_twister", true)
			if st != null:
				st.news("twister")
				st.bulletin("twister")
		"hogs":
			game.barks.say(game, "event_hogs", true)
			if st != null:
				st.news("hogs")
		"raid":
			if not ev.raiders.is_empty():
				var i: int = ev.raiders[0]
				if i < game.enemies.size():
					var e: Enemy = game.enemies[i]
					game.sound_at("raid_siren", e.x, e.y, 1.6)
			game.barks.say(game, "event_raid", true)
			if st != null:
				st.news("raid")
		"blackout":
			game.sound.play("power_down", .9)
			game.barks.say(game, "event_dark", true)
			if st != null:
				st.news("outage")
				st.bulletin("outage")


func _station() -> RadioStation:
	var radio: Radio = game.features.get("radio")
	return radio.the_station() if radio != null else null


## The loops: the twister's roar by how near and strong (muffled under a
## roof), the herd's hooves.
func _beds(ev: CountyEvents) -> void:
	var sound: Sound = game.sound.node() if game.sound != null else null
	if sound == null:
		return
	var p := game.local_player if game.local_player != null else game.player
	var cue := ""
	var level := 0.0
	var pan := 0.0
	var cutoff := Sound.OPEN_CUTOFF
	if ev.kind == "twister" and p != null:
		var d := Vector2(p.x, p.y).distance_to(ev.tw_at)
		level = pow(clampf(1.0 - d / ROAR_REACH, 0.0, 1.0), 1.4) * (.35 + .65 * ev.tw_k)
		pan = game.sound_position(ev.tw_at.x, ev.tw_at.y, 1.0).y
		if ev.roofed(p.x, p.y, game.world.stand(p)):
			level *= .6
			cutoff = 1500.0
		cue = "tornado_roar"
	elif ev.kind == "hogs" and p != null and not ev.herd.is_empty():
		var mid := _herd_middle(ev)
		if mid != Vector2.INF:
			var d := Vector2(p.x, p.y).distance_to(mid)
			level = pow(clampf(1.0 - d / HOOVES_REACH, 0.0, 1.0), 1.2)
			pan = game.sound_position(mid.x, mid.y, 1.0).y
			cutoff = game.sound_cutoff(mid.x, mid.y)
			cue = "hog_stampede"
	sound.set_bed(Sound.BED_EVENT, cue, level, pan, cutoff)


func _herd_middle(ev: CountyEvents) -> Vector2:
	var sum := Vector2.ZERO
	var count := 0
	for row: Array in ev.herd:
		var state: int = row[EventHerd.STATE]
		if state == EventHerd.RUN or state == EventHerd.SCATTER:
			sum += Vector2(EventHerd.f(row, EventHerd.X), EventHerd.f(row, EventHerd.Y))
			count += 1
	return sum / count if count > 0 else Vector2.INF


## The debris round the funnel's foot, kept whirling, and its dust.
func _whirl(ev: CountyEvents, dt: float) -> void:
	var k := ev.tw_k
	while _bits.size() < int(BITS * k):
		_bits.append(_new_bit())
	for b: Array in _bits:
		var r: float = b[1]
		var spin := (5.5 / maxf(.5, r)) * dt
		b[0] = CountyEvents.at(b, 0) + spin
		b[2] = CountyEvents.at(b, 2) + CountyEvents.at(b, 3) * dt
		b[5] = CountyEvents.at(b, 5) + dt * 9.0
		if CountyEvents.at(b, 2) > 13.0 or CountyEvents.at(b, 2) < 0.0:
			var fresh := _new_bit()
			for i in b.size():
				b[i] = fresh[i]
	_puff_at -= dt
	if _puff_at <= 0.0 and k > .2:
		_puff_at = .05
		var a := dice.randf() * TAU
		var r := dice.randf_range(.8, 2.8) * (.5 + .5 * k)
		var x := ev.tw_at.x + cos(a) * r
		var y := ev.tw_at.y + sin(a) * r
		var z := game.world.elevation(x, y)
		var round := Vector2(-sin(a), cos(a)) * dice.randf_range(2.0, 4.0)
		_puff(x, y, z + dice.randf_range(0.0, .6), dice.randf_range(1.0, 1.8), 1.2, round)


func _new_bit() -> Array:
	return [
		dice.randf() * TAU,
		dice.randf_range(.7, 3.6),
		dice.randf_range(0.0, 2.0) if dice.randf() < .6 else dice.randf_range(2.0, 9.0),
		dice.randf_range(.6, 2.4),
		BIT_ART[dice.randi() % BIT_ART.size()],
		dice.randf() * TAU,
		dice.randf_range(.14, .34)
	]


## The herd's squeals now and then, and the dust behind the hogs.
func _herd(ev: CountyEvents) -> void:
	if game.clock >= _squeal_at and not ev.herd.is_empty():
		_squeal_at = game.clock + dice.randf_range(.35, .9)
		var row: Array = ev.herd[dice.randi() % ev.herd.size()]
		var state: int = row[EventHerd.STATE]
		if state == EventHerd.RUN or state == EventHerd.SCATTER:
			game.sound_at(
				"hog_squeal", EventHerd.f(row, EventHerd.X), EventHerd.f(row, EventHerd.Y), .8
			)
	if game.clock < _puff_at:
		return
	_puff_at = game.clock + .07
	for row: Array in ev.herd:
		var state: int = row[EventHerd.STATE]
		if (state != EventHerd.RUN and state != EventHerd.SCATTER) or dice.randf() > .22:
			continue
		var a := EventHerd.f(row, EventHerd.ANGLE) + PI + dice.randf_range(-.5, .5)
		var x := EventHerd.f(row, EventHerd.X) + cos(a) * .35
		var y := EventHerd.f(row, EventHerd.Y) + sin(a) * .35
		var back := Vector2.from_angle(a) * dice.randf_range(.3, .9)
		_puff(x, y, EventHerd.f(row, EventHerd.FLOOR) + .05, dice.randf_range(.6, 1.0), .38, back)


func _puff(x: float, y: float, z: float, life: float, size: float, drift: Vector2) -> void:
	if _puffs.size() >= PUFFS:
		_puffs.pop_front()
	_puffs.append([x, y, z, 0.0, life, size, drift.x, drift.y])


func _age(dt: float) -> void:
	var kept: Array = []
	for d: Array in _puffs:
		d[3] = CountyEvents.at(d, 3) + dt
		if CountyEvents.at(d, 3) >= CountyEvents.at(d, 4):
			continue
		d[0] = CountyEvents.at(d, 0) + CountyEvents.at(d, 6) * dt
		d[1] = CountyEvents.at(d, 1) + CountyEvents.at(d, 7) * dt
		d[2] = CountyEvents.at(d, 2) + dt * .5
		kept.append(d)
	_puffs = kept


func sprites() -> Array:
	var ev := _ev()
	var out: Array = []
	if ev == null:
		return out
	if ev.kind == "twister":
		var ground := game.world.elevation(ev.tw_at.x, ev.tw_at.y)
		for b: Array in _bits:
			var a: float = b[0]
			var r: float = b[1]
			var x := ev.tw_at.x + cos(a) * r
			var y := ev.tw_at.y + sin(a) * r
			if not game.in_view(x, y, 1.0):
				continue
			var s := game.pooled(
				x, y, str(b[4]), CountyEvents.at(b, 6), ground + CountyEvents.at(b, 2)
			)
			s.flip = fmod(CountyEvents.at(b, 5), TAU) > PI
			out.append(s)
	for d: Array in _puffs:
		var x: float = d[0]
		var y: float = d[1]
		if not game.in_view(x, y, 1.0):
			continue
		var age: float = d[3]
		var life: float = d[4]
		var k := age / life
		var frame := clampi(int(k * 4.0), 0, 3)
		var s := game.pooled(
			x, y, "fx_puff_%d" % frame, CountyEvents.at(d, 5) * (.6 + .8 * k), CountyEvents.at(d, 2)
		)
		s.translucent = true
		out.append(s)
	return out


func draw_view(c: Canvas) -> void:
	var ev := _ev()
	if ev == null or game.local_player == null:
		return
	if ev.kind == "raid":
		_streaks(ev, c)
	elif ev.kind == "blackout":
		_battery(ev, c)


## The revenue men's shots: a streak from the muzzle a moment.
func _streaks(ev: CountyEvents, c: Canvas) -> void:
	for row: Array in ev.raid_shots:
		var at: float = row[6]
		if game.clock - at > .07:
			continue
		var a := game.to_canvas(
			CountyEvents.at(row, 0), CountyEvents.at(row, 1), CountyEvents.at(row, 2)
		)
		var b := game.to_canvas(
			CountyEvents.at(row, 3), CountyEvents.at(row, 4), CountyEvents.at(row, 5)
		)
		if a.z <= .1 or b.z <= .1:
			continue
		c.line(int(a.x), int(a.y), int(b.x), int(b.y), Color(1.0, .9, .55))


## The flashlight's battery on the HUD: a little plate with five cells, the
## last blinking as it runs out.
func _battery(ev: CountyEvents, c: Canvas) -> void:
	var torch := ev.torch_of(game.local_player)
	if torch.is_empty():
		return
	var lit: bool = torch[0]
	var share: float = torch[1]
	var x := 3
	var y := View.VIEW - HoundLooks.BADGE_H - 6 - PLATE_H
	var hound: Game.HoundScript = game.features.get("hound")
	if hound == null or not hound.on:
		y = View.VIEW - PLATE_H - 3
	c.round_rect(x, y, PLATE_W, PLATE_H, 2, HoundLooks.PLATE)
	c.line(x + 2, y, x + PLATE_W - 3, y, HoundLooks.TRIM)
	HUD.text(c, "LIGHT", x + 3, y + 2, "mini", HUD.AMBER if lit else HUD.INK, false, true)
	var cells := clampi(ceili(share * 5.0 - .001), 0, 5)
	var low := cells <= 1
	for i in 5:
		var on := i < cells and (not low or fmod(game.clock, .6) < .35)
		var ink := (
			Color(.98, .86, .42)
			if on and lit
			else Color(.6, .55, .32) if on else Color(.18, .15, .12)
		)
		c.fill_rect(x + 27 + i * 4, y + 3, 3, 5, ink)
