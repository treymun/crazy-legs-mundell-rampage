## The blackout (features/county_events.gd), in the night chapters: the power
## dies (the lamps, the street lights and the floodlights, the lit windows and
## the signs go dark, `dark` of the light gone; the fires and lanterns burn
## on), and every player gets a flashlight, switched on: L (online
## Controls.item == Game.TORCH) puts it out and on again. Its battery runs
## down while it shines, flickers near the end and dies; off a while it gets
## some back. A share of the county's hands carry lanterns.
##
## The dark is play: a hand notices a player in the dark only `dark_sight` as
## far, but `lit_sight` as far when their light is on (a hand with a lantern
## sees as ever). The power comes back after `back_after`, or at the main
## breaker (a switch box on a wall somewhere near, its red lamp blinking:
## USE). Play: game.rng and the feature's carried state; the dark and the
## beams are drawn by the 3D view (view_light.gdshaderinc `dark`, a spot
## light's flags).
class_name EventDark
extends RefCounted

const FADING := 0
const DARK := 1
## The beam's colour, and a lantern's.
const BEAM := Color(1.0, .93, .76)
const LANTERN := Color(1.0, .62, .28)
## A light's flags: Effects.POOL is 1; a spot is 2, its way packed above.
const SPOT := 2
const BREAKER_ART := "town_quest_switch"


static func n(ev: CountyEvents, key: String) -> float:
	return ev.n("blackout", key)


static func start(ev: CountyEvents) -> bool:
	var g := ev.game
	var p := ev.someone()
	if p == null:
		return false
	var spot := _breaker_spot(ev, p)
	if spot == Vector3.INF:
		return false
	ev.breaker = spot
	ev.power = false
	var back := CountyEvents.span("blackout", "back_after")
	ev.back_at = g.clock + g.rng.uniform(back.x, back.y)
	ev.torches.clear()
	for q: Player in g.players:
		ev.torches.append([1, n(ev, "battery")])
	ev.lanterns.clear()
	for i in g.enemies.size():
		var e: Enemy = g.enemies[i]
		if e.alive and not e.dormant and e.tactical() and not Enemy.BOSS_TITLES.has(e.kind):
			if g.rng.random() < n(ev, "lanterns"):
				ev.lanterns.append(i)
	g.message("POWER'S OUT! YOU GOT A FLASHLIGHT: L.", 4.0)
	return true


## A spot on a wall `breaker_far` from the player, on their floor, that their
## flow field reaches: [x, y, 0] (the box faces the open side), or INF.
static func _breaker_spot(ev: CountyEvents, p: Player) -> Vector3:
	var g := ev.game
	var w := g.world
	var far := CountyEvents.span("blackout", "breaker_far")
	var ground := w.elevation(p.x, p.y)
	var found: Array = []
	var reach := int(far.y) + 1
	for cy in range(maxi(1, int(p.y) - reach), mini(w.height - 1, int(p.y) + reach)):
		for cx in range(maxi(1, int(p.x) - reach), mini(w.width - 1, int(p.x) + reach)):
			var at := Vector2(cx + .5, cy + .5)
			var d := at.distance_to(Vector2(p.x, p.y))
			if d < far.x or d > far.y:
				continue
			if w.solid[w.cell(at.x, at.y)] >= 0 or w.blocked(at.x, at.y, .3):
				continue
			if absf(w.elevation(at.x, at.y) - ground) > .3 or w.deep_at(at.x, at.y):
				continue
			for k in 4:
				var off := Vector2.from_angle(k * PI * .5)
				var wall := at + off
				if w.solid[w.cell(wall.x, wall.y)] < 0:
					continue
				var box := at + off * .36
				if w.blocked(box.x, box.y, .1):
					continue
				found.append(Vector3(box.x, box.y, k))
				break
	if found.is_empty():
		return Vector3.INF
	for tries in 12:
		var pick: Vector3 = g.rng.choice(found)
		if p.flow == null or p.flow.distance(pick.x, pick.y, ground) < FlowField.FAR:
			if ev.far_from_bosses(pick.x, pick.y):
				return pick
	return Vector3.INF


static func step(ev: CountyEvents, dt: float) -> void:
	var g := ev.game
	if ev.phase == FADING and g.clock - ev.since >= n(ev, "fade"):
		ev.phase = DARK
	while ev.torches.size() < g.players.size():
		ev.torches.append([1, n(ev, "battery")])
	var full := n(ev, "battery")
	for slot in ev.torches.size():
		var row: Array = ev.torches[slot]
		var lit: int = row[0]
		var left: float = row[1]
		if lit == 1:
			left -= dt
			if left <= 0.0:
				left = 0.0
				row[0] = 0
				if slot < g.players.size():
					g.sound_at("torch_click", g.players[slot].x, g.players[slot].y, .5)
					_tell(ev, g.players[slot], "FLASHLIGHT'S DEAD. GIVE IT A REST.")
		else:
			left = minf(full, left + n(ev, "rest") * dt)
		row[1] = left
	if g.clock >= ev.back_at:
		g.message("THE POWER'S BACK ON.", 2.5)
		ev.finish()


## The power is back: the lights, the hands see as ever.
static func stop(ev: CountyEvents) -> void:
	ev.power = true
	ev.torches.clear()
	ev.lanterns.clear()


static func _tell(ev: CountyEvents, p: Player, text: String) -> void:
	var g := ev.game
	if p == g.player:
		g.message(text, 2.2)


static func toggle(ev: CountyEvents, p: Player) -> void:
	var g := ev.game
	if p.slot >= ev.torches.size():
		return
	var row: Array = ev.torches[p.slot]
	var lit: int = row[0]
	var left: float = row[1]
	if lit == 0 and left < 1.0:
		_tell(ev, p, "BATTERY'S FLAT. GIVE IT A MINUTE.")
		return
	row[0] = 0 if lit == 1 else 1
	g.sound_at("torch_click", p.x, p.y, .5)


static func notice(ev: CountyEvents, e: Enemy, p: Player) -> float:
	if ev.lanterns.has(ev.game.enemies.find(e)):
		return 1.0
	if p.slot < ev.torches.size():
		var row: Array = ev.torches[p.slot]
		var lit: int = row[0]
		if lit == 1:
			return n(ev, "lit_sight")
	return n(ev, "dark_sight")


static func prompt(ev: CountyEvents, p: Player) -> String:
	if ev.breaker == Vector3.INF:
		return ""
	if Vector2(ev.breaker.x - p.x, ev.breaker.y - p.y).length() > 1.4:
		return ""
	return "USE: THROW THE MAIN BREAKER"


static func use(ev: CountyEvents, p: Player) -> bool:
	if prompt(ev, p) == "":
		return false
	var g := ev.game
	g.sound_at("breaker_throw", ev.breaker.x, ev.breaker.y, 1.0)
	g.message("BREAKER THROWN. LET THERE BE LIGHT.", 2.5)
	ev.finish()
	return true


## How dark now: the power dying in stutters over `fade`, then `dark`.
static func darkness(ev: CountyEvents) -> float:
	var g := ev.game
	var full := n(ev, "dark")
	var age := g.clock - ev.since
	var fade := n(ev, "fade")
	if age >= fade:
		return full
	# The lights stutter twice before they go.
	var k := age / fade
	var stutter := 1.0 if fmod(age, .23) < .12 else .35
	return full * clampf(k * 1.4, 0.0, 1.0) * (stutter if k < .7 else 1.0)


## A spot light's flags: SPOT, its yaw (10 bits), pitch (9 bits) and cone
## (4 bits) packed above (view_light.gdshaderinc reads them back).
static func spot_flags(yaw: float, pitch: float, cone: float) -> int:
	var y := int(fposmod(yaw, TAU) / TAU * 1024.0) & 1023
	var pt := clampi(int((pitch + PI * .5) / PI * 511.0), 0, 511)
	var c := clampi(int((cone - .05) / .8 * 15.0 + .5), 0, 15)
	return SPOT | (y << 8) | (pt << 18) | (c << 27)


static func lights(ev: CountyEvents, _p: Player) -> Array:
	var g := ev.game
	var out: Array = []
	var full := n(ev, "battery")
	for slot in mini(ev.torches.size(), g.players.size()):
		var row: Array = ev.torches[slot]
		var lit: int = row[0]
		var q: Player = g.players[slot]
		if lit == 0 or q.away or q.health <= 0:
			continue
		var left: float = row[1]
		var power := 5.5
		if left < full * n(ev, "flicker"):
			# A weak battery: the beam browns and stutters.
			var beat := fmod(g.clock * 7.3 + slot, 1.0)
			power *= .55 if beat < .18 else .85
		var yaw := q.view_angle()
		var pitch := atan(q.pitch / maxf(1.0, View.base_focal))
		var flags := spot_flags(yaw, pitch, n(ev, "beam_cone"))
		out.append(
			[
				q.x + cos(yaw) * .2,
				q.y + sin(yaw) * .2,
				q.eye - .14,
				n(ev, "beam_reach"),
				BEAM,
				power,
				flags,
				0.0
			]
		)
	for i: int in ev.lanterns:
		if i >= g.enemies.size():
			continue
		var e: Enemy = g.enemies[i]
		if not e.alive:
			continue
		var a := e.angle + .9
		var sway := sin(g.clock * 3.1 + i) * .05
		var flick := .9 + .1 * sin(g.clock * 17.0 + i * 3.0)
		out.append(
			[
				e.x + cos(a) * .28 + sway,
				e.y + sin(a) * .28,
				g.world.stand(e) + .72,
				4.6,
				LANTERN,
				1.35 * flick,
				1,
				0.0
			]
		)
	if ev.breaker != Vector3.INF:
		var blink := fmod(g.clock, 1.0) < .5
		out.append(
			[
				ev.breaker.x,
				ev.breaker.y,
				g.world.elevation(ev.breaker.x, ev.breaker.y) + 1.25,
				1.8,
				Color(1.0, .16, .1),
				1.3 if blink else .25,
				0,
				0.0
			]
		)
	return out


## The breaker box on its wall, and a lantern in each lantern hand's fist.
static func sprites(ev: CountyEvents) -> Array:
	var g := ev.game
	var out: Array = []
	if ev.breaker != Vector3.INF and g.in_view(ev.breaker.x, ev.breaker.y, 1.0):
		var z := g.world.elevation(ev.breaker.x, ev.breaker.y)
		out.append(g.pooled(ev.breaker.x, ev.breaker.y, BREAKER_ART + "_off", 1.35, z))
	for i: int in ev.lanterns:
		if i >= g.enemies.size():
			continue
		var e: Enemy = g.enemies[i]
		if not e.alive or not g.in_view(e.x, e.y, 1.0):
			continue
		var a := e.angle + .9
		var s := g.pooled(
			e.x + cos(a) * .3, e.y + sin(a) * .3, "event_lantern", .34, g.world.stand(e) + .5
		)
		s.glow = true
		out.append(s)
	return out
