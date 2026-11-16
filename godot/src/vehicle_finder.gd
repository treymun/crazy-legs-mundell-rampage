## Finding a vehicle (feature pass 7; features/vehicles.gd calls in here; all
## of it looks and sound, never play): a ready vehicle (nobody at its wheel,
## not burnt out) keeps its lamps on (a light each on the ground ahead and a
## glow on the lamp) and its radio playing (the jukebox's tune, quiet, heard
## from `radio_reach`); the automap marks each one with a little picture of
## it in the key's yellow (KEYS IN IT in the map's key); USE's prompt names
## it from `spot_reach` off when it is looked at ("AIRBOAT  /  KEYS IN IT"),
## and the first time a player comes within `spot_told` of it in sight its
## `spotted` line is said. Numbers in data/tuning/vehicles.cfg.
class_name VehicleFinder
extends RefCounted

## The automap's mark: the key's yellow, its outline and the wheels.
const MAP_INK := Color8(250, 214, 96)
const MAP_EDGE := Color8(52, 30, 14)
const MAP_WHEEL := Color8(96, 84, 70)
## Each kind's little picture on the automap, side on, nose to the right:
## '#' its body, 'o' a wheel (9 wide, 5 high).
const ICONS := {
	"airboat": ["......##.", ".....#..#", "#########", ".#######.", "........."],
	"car": ["..####...", ".#....#..", "#########", "#########", ".o....o.."],
	"mower": ["..#......", "..#......", ".######..", "########.", ".o....o.."],
}
## The glow on a lamp left on (its picture and size, cells).
const GLOW := "fx_flare"
const GLOW_SIZE := .22


## Whether `v` stands ready to take: nobody at its wheel, not burnt out.
static func ready(v: VehicleDrive.Ride) -> bool:
	return v.wreck < 0.0 and v.seats[0] < 0


## Where each of `v`'s lamps is (map x, y, z).
static func lamp_points(v: VehicleDrive.Ride, s: VehicleDrive.Spec) -> Array:
	var out: Array = []
	var f := Vector2(cos(v.h), sin(v.h))
	var r := Vector2(-sin(v.h), cos(v.h))
	for lamp: Variant in s.lamps:
		var at: Vector3 = lamp
		var p := Vector2(v.x, v.y) + f * at.x + r * at.y
		out.append(Vector3(p.x, p.y, v.z + at.z))
	return out


## The lamps' lights near `p` (effects.cfg [light.vehicle_lamp]): left on in a
## ready vehicle, and on while it is driven; none on a wreck.
static func lights(rides: Array, p: Player, clock: float) -> Array:
	var out: Array = []
	for v: VehicleDrive.Ride in rides:
		if v.wreck >= 0.0 or absf(v.x - p.x) > 16.0 or absf(v.y - p.y) > 16.0:
			continue
		var s := VehicleDrive.spec(v.kind)
		var f := Vector2(cos(v.h), sin(v.h))
		# The pool falls a little ahead of the lamp, where its beam lands; from
		# the seat further out on the road, not on the hood.
		var throw := 3.0 if v.seats.has(p.slot) else .9
		for at: Vector3 in lamp_points(v, s):
			var l: Variant = Effects.light(
				"vehicle_lamp", at.x + f.x * throw, at.y + f.y * throw, at.z, 1.0, clock
			)
			if l != null:
				out.append(l)
	return out


## The glow on each lamp of the vehicles in view (not the one `skip`, the
## local driver's own: their cab is drawn instead).
static func glows(g: Game, rides: Array, skip: int, out: Array) -> void:
	for i in rides.size():
		var v: VehicleDrive.Ride = rides[i]
		if i == skip or v.wreck >= 0.0 or not g.in_view(v.x, v.y, 3.0):
			continue
		for at: Vector3 in lamp_points(v, VehicleDrive.spec(v.kind)):
			var spr := g.pooled(at.x, at.y, GLOW, GLOW_SIZE, at.z - GLOW_SIZE * .5)
			spr.glow = true
			out.append(spr)


## The nearest ready vehicle within `far` cells of `p` that `p` looks at
## (roughly), in sight; -1 when none.
static func looked_at(g: Game, rides: Array, p: Player, far: float, facing: float) -> int:
	var best := -1
	var best_gap := INF
	for i in rides.size():
		var v: VehicleDrive.Ride = rides[i]
		if not ready(v) or absf(v.x - p.x) > far + 2.0 or absf(v.y - p.y) > far + 2.0:
			continue
		var gap := VehicleDrive.gap(VehicleDrive.spec(v.kind), v, p.x, p.y)
		var to := Vector2(v.x - p.x, v.y - p.y)
		if gap > far or gap >= best_gap:
			continue
		if to.length() > .01 and to.normalized().dot(Vector2(cos(p.angle), sin(p.angle))) < facing:
			continue
		if not g.world.visible(p.x, p.y, v.x, v.y, p.eye, v.z + .6):
			continue
		best = i
		best_gap = gap
	return best


## USE's prompt for a ready vehicle looked at from further off than USE
## reaches: its name and that the keys are in it.
static func far_prompt(g: Game, rides: Array, p: Player) -> String:
	var i := looked_at(g, rides, p, VehicleDrive.shared("spot_reach"), .82)
	if i < 0:
		return ""
	var v: VehicleDrive.Ride = rides[i]
	return VehicleDrive.spec(v.kind).name + "  /  KEYS IN IT"


## Says a vehicle's `spotted` line the first time the local player comes
## near it in sight (`told` remembers which, by place in the list: looks).
static func spot(g: Game, rides: Array, told: Dictionary) -> void:
	if g.message_until > g.clock or g.players.is_empty():
		return
	var p := g.local_player
	var i := looked_at(g, rides, p, VehicleDrive.shared("spot_told"), -1.0)
	if i < 0 or told.has(i):
		return
	told[i] = true
	var v: VehicleDrive.Ride = rides[i]
	var line := VehicleDrive.spec(v.kind).spotted
	if line != "":
		g.message(line, 3.2)


## The radio left playing in the nearest ready vehicle within `radio_reach`
## of `p`: Vector3(x, y, how loud 0..1), or Vector3.INF for none.
static func radio(rides: Array, p: Player) -> Vector3:
	var reach := VehicleDrive.shared("radio_reach")
	var best := Vector3.INF
	var best_d := reach
	for v: VehicleDrive.Ride in rides:
		if not ready(v) or not VehicleDrive.spec(v.kind).radio:
			continue
		var d := Vector2(v.x - p.x, v.y - p.y).length()
		if d < best_d:
			best_d = d
			best = Vector3(v.x, v.y, VehicleDrive.shared("radio_volume"))
	return best


## Each ready vehicle on the automap (`map`, the open GameAutomap): its little
## picture where it stands.
static func draw_map(c: Canvas, map: GameAutomap, rides: Array) -> void:
	for v: VehicleDrive.Ride in rides:
		if not ready(v):
			continue
		var at := map.point(v.x, v.y)
		if map.shows(at):
			icon(c, v.kind, int(at.x) - 4, int(at.y) - 2)


## A kind's little picture with its top left at (x, y): outlined in the
## map's dark, the body in the key's yellow, the wheels grey.
static func icon(c: Canvas, kind: String, x: int, y: int) -> void:
	var rows: Array = ICONS.get(kind, ICONS["car"])
	for r in rows.size():
		var row: String = rows[r]
		for k in row.length():
			if row[k] != ".":
				c.fill_rect(x + k - 1, y + r - 1, 3, 3, MAP_EDGE)
	for r in rows.size():
		var row: String = rows[r]
		for k in row.length():
			if row[k] == "#":
				c.fill_rect(x + k, y + r, 1, 1, MAP_INK)
			elif row[k] == "o":
				c.fill_rect(x + k, y + r, 1, 1, MAP_WHEEL)
