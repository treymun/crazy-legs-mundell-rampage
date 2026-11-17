## Cars still running laps on a level's track (its "lap_cars": the racing
## line, how many cars, how fast, the station that stops them, how hard they
## hit). Each car runs the line at speed with its headlights painted on the
## dirt ahead of it and its engine heard as it comes; whoever is on the line
## when it arrives is run down, the county's hands as well as the player. Once
## the station is done the cars run dry and coast to a stop where they are.
## The speedway's race cars; the Moonshine Run's revenue cruisers patrolling
## the county blacktop ("model", "nose" in degrees, "siren": their light bars
## lit, "dry": the line when they stop); any other level has no "lap_cars".
extends GameFeature

## How close a car's middle may come to a body before it hits it.
const REACH := .78
## race_car_0's nose against the model's front (scripts/blender/props_speedway.py
## _sw_race: the nose turned k * 45 - 90 + 28 degrees).
const NOSE_TURN := -62.0 * PI / 180.0

var path := PackedVector2Array()
var lengths := PackedFloat32Array()
var total := 0.0
var spec := {}
## Each car: how far along the line it is, its speed now, when it may next
## hit the player, when its engine is next heard.
var cars: Array = []
var dry := false


func id() -> String:
	return "race_laps"


func attach() -> void:
	spec = game.level.lap_cars
	if spec.is_empty() or game.in_hub:
		return
	for point: Variant in spec.get("path", []):
		var px: float = point[0]
		var py: float = point[1]
		path.append(Vector2(px, py))
	if path.size() < 3:
		path = PackedVector2Array()
		return
	path.append(path[0])
	lengths.append(0.0)
	for i in range(1, path.size()):
		total += path[i].distance_to(path[i - 1])
		lengths.append(total)
	var count: int = spec.get("cars", 1)
	var speed: float = spec.get("speed", 8.0)
	for k in count:
		cars.append([total * k / count, speed, 0.0, float(k)])
	tick_with(_tick)
	game.events.station_done.connect(_station)


func save() -> Dictionary:
	if cars.is_empty():
		return {}
	var along: Array = []
	for car: Array in cars:
		var car_along: float = car[0]
		along.append(snappedf(car_along, .01))
	return {"along": along, "dry": dry}


func restore(state: Dictionary) -> void:
	var along: Array = state.get("along", [])
	for k in mini(along.size(), cars.size()):
		var saved_along: float = along[k]
		cars[k][0] = saved_along
	dry = state.get("dry", false)
	if dry:
		for car: Array in cars:
			car[1] = 0.0


func _station(station_id: String) -> void:
	if station_id == str(spec.get("stop_at", "")) and not dry:
		dry = true
		game.message(str(spec.get("dry", "THE CARS ARE COUGHING. THEY'RE RUNNING DRY.")), 3.0)


## Where along the line `d` is, and which way the line runs there.
func _at(d: float) -> Array:
	d = fposmod(d, total)
	var i := 1
	while i < lengths.size() - 1 and lengths[i] < d:
		i += 1
	var a := path[i - 1]
	var b := path[i]
	var span := maxf(.001, lengths[i] - lengths[i - 1])
	var t := clampf((d - lengths[i - 1]) / span, 0.0, 1.0)
	return [a.lerp(b, t), atan2(b.y - a.y, b.x - a.x)]


func _tick(dt: float) -> void:
	if game.revisiting or game.won:
		return
	if game.stations_done.has(str(spec.get("stop_at", ""))):
		dry = true
	var p := game.player
	var running := false
	for car: Array in cars:
		var speed: float = car[1]
		if dry:
			speed = maxf(0.0, speed - dt * 3.0)
			car[1] = speed
		if speed <= 0.0:
			continue
		running = true
		var car_along: float = car[0]
		car_along = fposmod(car_along + speed * dt, total)
		car[0] = car_along
		var where: Array = _at(car_along)
		var at: Vector2 = where[0]
		var heading: float = where[1]
		var gap := Vector2(p.x - at.x, p.y - at.y).length()
		var pass_at: float = car[3]
		if gap < 12.0 and game.clock >= pass_at:
			car[3] = game.clock + 2.2
			game.sound_at("lap_car_pass", at.x, at.y, .9)
		# Every player on the track is run down, each with their own second
		# before the same car can hit them again: car[2] is player one's,
		# car[3 + slot] another player's (added when first needed).
		for q: Player in game.players:
			var near := gap if q == p else Vector2(q.x - at.x, q.y - at.y).length()
			var at_k := 2 if q.slot == 0 else 3 + q.slot
			if car.size() <= at_k:
				var was := car.size()
				car.resize(at_k + 1)
				for k in range(was, at_k + 1):
					car[k] = 0.0
			var hit_at: float = car[at_k]
			if near < REACH + GameState.PLAYER_RADIUS and q.air < .5 and game.clock >= hit_at:
				car[at_k] = game.clock + 1.0
				game.focus(q)
				var hurt: float = spec.get("damage", 30)
				game.damage(hurt, [at.x, at.y], "RUN DOWN")
				var side := (
					-1.0 if (q.x - at.x) * sin(heading) - (q.y - at.y) * cos(heading) > 0.0 else 1.0
				)
				var away := heading + side * PI / 2.0
				game.move_actor(q, cos(away) * 1.2, sin(away) * 1.2, GameState.PLAYER_RADIUS)
				game.focus(game.local_player)
				if q == game.local_player:
					game.shake = minf(1.0, game.shake + .8)
				game.sound_at("lap_car_hit", q.x, q.y, 1.0)
		for e: Enemy in game.enemies:
			# The cheap test first (the same hands are run down either way).
			if absf(e.x - at.x) >= 1.2 or absf(e.y - at.y) >= 1.2:
				continue
			if not e.alive or Enemy.BOSS_TITLES.has(e.kind) or e.z > .3:
				continue
			if Vector2(e.x - at.x, e.y - at.y).length() < REACH + e.radius:
				# hurt() blames the acting player: the nearest, the same on
				# every machine (not whoever is local here).
				var near_e: Player = Players.nearest(game, e.x, e.y)
				game.focus(near_e if near_e != null else game.players[0])
				e.hurt(80.0, game, true, false, null, "car")
				game.focus(game.local_player)
	if dry and not running:
		# Every car has coasted to a stop for good: nothing to tick.
		sleep()


## Each car as the race car's model (the 3D view's prop `race_car_0`), turned
## along the racing line: the sprite's `plane` is the model's turn, so the
## nose points where the car runs whatever side it is seen from (the eight
## pictures race_car_0..7 were the old view's turns of it).
func sprites() -> Array:
	var out: Array = []
	if cars.is_empty() or game.revisiting:
		return out
	for car: Array in cars:
		var car_along: float = car[0]
		var where: Array = _at(car_along)
		var at: Vector2 = where[0]
		if not game.in_view(at.x, at.y, 1.6):
			continue
		var heading: float = where[1]
		var spr := View.Sprite.new(
			at.x,
			at.y,
			str(spec.get("model", "town_race_car_0")),
			1.05,
			game.world.elevation(at.x, at.y)
		)
		spr.body = true
		spr.plane = heading + _nose()
		out.append(spr)
	return out


## The model's nose against its front: the race car's own turn unless the
## level names another (degrees).
func _nose() -> float:
	if spec.has("nose"):
		var degrees: float = spec["nose"]
		return deg_to_rad(degrees)
	return NOSE_TURN


## The cruisers' light bars going round as they run (effects.cfg
## [light.cruiser]; looks only).
func lights(p: Player) -> Array:
	var out: Array = []
	var siren: bool = spec.get("siren", false)
	if cars.is_empty() or game.revisiting or not siren:
		return out
	for car: Array in cars:
		var car_along: float = car[0]
		var where: Array = _at(car_along)
		var at: Vector2 = where[0]
		if absf(at.x - p.x) > 16.0 or absf(at.y - p.y) > 16.0:
			continue
		var l: Variant = Effects.light(
			"cruiser", at.x, at.y, game.world.elevation(at.x, at.y) + 1.3, 1.0, game.clock
		)
		if l != null:
			out.append(l)
	return out


## Headlights on the dirt ahead of every car still running.
func ground_marks() -> Array:
	var out: Array = []
	if cars.is_empty() or game.revisiting:
		return out
	var p := game.player
	for car: Array in cars:
		var speed: float = car[1]
		if speed < 1.0:
			continue
		var car_along: float = car[0]
		var ahead: Array = _at(car_along + 2.2)
		var at: Vector2 = ahead[0]
		if Vector2(p.x - at.x, p.y - at.y).length() > 16.0:
			continue
		var heading: float = ahead[1]
		out.append(
			View.GroundMark.new(
				at.x, at.y, game.world.elevation(at.x, at.y) + .003, heading, 1.6, .45, "mark_lane"
			)
		)
	return out
