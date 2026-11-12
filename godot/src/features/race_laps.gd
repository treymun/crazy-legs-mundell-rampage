## Cars still running laps on a level's track (its "lap_cars": the racing
## line, how many cars, how fast, the station that stops them, how hard they
## hit). Each car runs the line at speed with its headlights painted on the
## dirt ahead of it and its engine heard as it comes; whoever is on the line
## when it arrives is run down, the county's hands as well as the player. Once
## the station is done the cars run dry and coast to a stop where they are.
## Only the speedway has them; any other level has no "lap_cars".
extends GameFeature

## How close a car's middle may come to a body before it hits it.
const REACH := .78

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
	for point in spec.get("path", []):
		path.append(Vector2(float(point[0]), float(point[1])))
	if path.size() < 3:
		path = PackedVector2Array()
		return
	path.append(path[0])
	lengths.append(0.0)
	for i in range(1, path.size()):
		total += path[i].distance_to(path[i - 1])
		lengths.append(total)
	var count := int(spec.get("cars", 1))
	for k in count:
		cars.append([total * k / count, float(spec.get("speed", 8.0)), 0.0, float(k)])
	game.ticked.connect(_tick)
	game.station_done.connect(_station)


func save() -> Dictionary:
	if cars.is_empty():
		return {}
	var along: Array = []
	for car: Array in cars:
		along.append(snappedf(float(car[0]), .01))
	return {"along": along, "dry": dry}


func restore(state: Dictionary) -> void:
	var along: Array = state.get("along", [])
	for k in mini(along.size(), cars.size()):
		cars[k][0] = float(along[k])
	dry = bool(state.get("dry", false))
	if dry:
		for car: Array in cars:
			car[1] = 0.0


func _station(station_id: String) -> void:
	if station_id == String(spec.get("stop_at", "")) and not dry:
		dry = true
		game.message("THE CARS ARE COUGHING. THEY'RE RUNNING DRY.", 3.0)


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
	if game.stations_done.has(String(spec.get("stop_at", ""))):
		dry = true
	var p = game.player
	for car: Array in cars:
		if dry:
			car[1] = maxf(0.0, float(car[1]) - dt * 3.0)
		if float(car[1]) <= 0.0:
			continue
		car[0] = fposmod(float(car[0]) + float(car[1]) * dt, total)
		var where: Array = _at(float(car[0]))
		var at: Vector2 = where[0]
		var heading: float = where[1]
		var gap := Vector2(p.x - at.x, p.y - at.y).length()
		if gap < 12.0 and game.clock >= float(car[3]):
			car[3] = game.clock + 2.2
			game.sound_at("lap_car_pass", at.x, at.y, .9)
		# Any player on the track is run down (one a car at a time).
		for q: Player in game.players:
			var near := gap if q == p else Vector2(q.x - at.x, q.y - at.y).length()
			if (
				near < REACH + GameState.PLAYER_RADIUS
				and q.air < .5
				and game.clock >= float(car[2])
			):
				car[2] = game.clock + 1.0
				game.focus(q)
				game.damage(float(spec.get("damage", 30)), [at.x, at.y], "RUN DOWN")
				var side := (
					-1.0 if (q.x - at.x) * sin(heading) - (q.y - at.y) * cos(heading) > 0.0 else 1.0
				)
				var away := heading + side * PI / 2.0
				game.move_actor(q, cos(away) * 1.2, sin(away) * 1.2, GameState.PLAYER_RADIUS)
				game.focus(game.local_player)
			game.shake = minf(1.0, game.shake + .8)
			game.sound_at("lap_car_hit", p.x, p.y, 1.0)
		for e: Enemy in game.enemies:
			if not e.alive or Enemy.BOSS_TITLES.has(e.kind) or e.z > .3:
				continue
			if absf(e.x - at.x) < 1.2 and absf(e.y - at.y) < 1.2:
				if Vector2(e.x - at.x, e.y - at.y).length() < REACH + e.radius:
					e.hurt(80.0, game, true, false, null, "car")


## The car's picture for where it is seen from: race_car_0 nose on to the
## viewer, round by eighths to race_car_7.
func sprites() -> Array:
	var out: Array = []
	if cars.is_empty() or game.revisiting:
		return out
	var p = game.player
	for car: Array in cars:
		var where: Array = _at(float(car[0]))
		var at: Vector2 = where[0]
		if not game.in_view(at.x, at.y, 1.6):
			continue
		var heading: float = where[1]
		var toward_eye := atan2(p.y - at.y, p.x - at.x)
		var turn := Enemy.angle_delta(toward_eye, heading)
		var k := posmod(roundi(turn / (PI / 4.0)), 8)
		var spr := Renderer.Sprite.new(
			at.x, at.y, "town_race_car_%d" % k, 1.05, game.world.elevation(at.x, at.y)
		)
		spr.body = true
		out.append(spr)
	return out


## Headlights on the dirt ahead of every car still running.
func ground_marks() -> Array:
	var out: Array = []
	if cars.is_empty() or game.revisiting:
		return out
	var p = game.player
	for car: Array in cars:
		if float(car[1]) < 1.0:
			continue
		var ahead: Array = _at(float(car[0]) + 2.2)
		var at: Vector2 = ahead[0]
		if Vector2(p.x - at.x, p.y - at.y).length() > 16.0:
			continue
		out.append(
			Renderer.GroundMark.new(
				at.x,
				at.y,
				game.world.elevation(at.x, at.y) + .003,
				float(ahead[1]),
				1.6,
				.45,
				"mark_lane"
			)
		)
	return out
