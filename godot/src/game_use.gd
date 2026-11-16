## The use key, moved out of game_world.gd: what USE would act on (use_target(),
## the device aim points), what the prompt says (use_prompt()), what pressing it
## does (interact()), and the Crossroads gates and clues. GameWorld keeps
## use_target(), use_prompt(), interact(), portal_target(), hub_clue() and
## gate_prompt() handing on to these.
class_name GameUse
extends RefCounted

## Quest devices (stations, the exit, notes, the jukebox and sink, the tin
## rooster stand) answer USE from a little farther than doors and a little
## wider round the crosshair, at any of their aim points (aim_points).
const DEVICE_REACH := 1.65
const DEVICE_TOUCH := .62
const DEVICE_CONE := .34


## Mirrors Game.use_target: returns [target, x, y] or null.
static func use_target(g: Game) -> Variant:
	if g.gallery != null and g.gallery.active:
		return [
			g.gallery,
			Game.GALLERY_STAND.x + g.gallery.offset.x,
			Game.GALLERY_STAND.y + g.gallery.offset.y
		]
	var facing := Vector2(cos(g.player.view_angle()), sin(g.player.view_angle()))
	if g.bessie != null and g.bessie.alive:
		var dx: float = g.bessie.x - g.player.x
		var dy: float = g.bessie.y - g.player.y
		var distance := sqrt(dx * dx + dy * dy)
		if (
			distance < 1.52
			and (distance < .55 or dx * facing.x + dy * facing.y > distance * .40)
			and g.world.visible(g.player.x, g.player.y, g.bessie.x, g.bessie.y)
		):
			return ["bessie", g.bessie.x, g.bessie.y]
	var doors: Array = []
	for door: LevelData.Door in g.world.doors:
		if (
			door.opened
			and (door.blast_only or g.world.controlled_doors.has(Vector2i(door.x, door.y)))
		):
			continue
		var centre := door.center()
		doors.append([door, centre.x, centre.y])
	var devices: Array = []
	for station: LevelData.Station in g.world.stations:
		if not station.reveals_secret or not g.stations_done.has(station.id):
			devices.append(station)
	if g.world.extraction != null:
		devices.append(g.world.extraction)
	for device: Array in g.level.devices:
		devices.append(device)
	if g.gallery != null:
		devices.append(g.gallery)
	for note: LevelData.Note in g.level.notes:
		devices.append(note)
	# An aimed target beats an unaimed one (the reference's rule); among them
	# the one nearest the crosshair wins, a little in favour of the nearer.
	var best := [true, INF]
	var result: Variant = null
	g.use_aim = Vector3.INF
	for door_entry: Array in doors:
		var x: float = door_entry[1]
		var y: float = door_entry[2]
		var rank := use_rank(g, x, y, 1.57, .50, .48, facing)
		if ranks_above(rank, best) and g.world.visible(g.player.x, g.player.y, x, y):
			best = rank
			result = door_entry
			g.use_aim = Vector3.INF
	for device: Variant in devices:
		for point: Vector3 in aim_points(g, device):
			var rank := use_rank(
				g, point.x, point.y, DEVICE_REACH, DEVICE_TOUCH, DEVICE_CONE, facing
			)
			if ranks_above(rank, best) and g.seen_at(point):
				best = rank
				g.use_aim = point
				var at := use_point(g, device)
				result = [device[0] if device is Array else device, at.x, at.y]
	return result


## [not aimed, score] for something at x, y, or [] when it is out of reach:
## aimed within `cone` (the dot of the facing and the way to it, per unit of
## distance), or closer than `touch` whichever way the player faces. The score
## is how far off the crosshair it is (radians) and a third of its distance.
static func use_rank(
	g: Game, x: float, y: float, reach: float, touch: float, cone: float, facing: Vector2
) -> Array:
	var dx := x - g.player.x
	var dy := y - g.player.y
	var distance := sqrt(dx * dx + dy * dy)
	if distance >= reach:
		return []
	var along := dx * facing.x + dy * facing.y
	var aimed := along > distance * cone
	if not aimed and distance >= touch:
		return []
	var off := acos(clampf(along / maxf(distance, .001), -1.0, 1.0))
	return [not aimed, off + distance * .35]


static func ranks_above(rank: Array, best: Array) -> bool:
	if rank.is_empty():
		return false
	var rank_far: bool = rank[0]
	var best_far: bool = best[0]
	if rank_far != best_far:
		return not rank_far
	var rank_off: float = rank[1]
	var best_off: float = best[1]
	return rank_off < best_off


## Where USE acts on a device, as the game has always reported it.
static func use_point(g: Game, device: Variant) -> Vector2:
	if device is Array:
		var ax: float = device[1]
		var ay: float = device[2]
		return Vector2(ax, ay)
	if device is GameState.Gallery:
		return Game.GALLERY_STAND + g.gallery.offset
	var dx: float = device.x
	var dy: float = device.y
	return Vector2(dx, dy)


## The points a device can be aimed at, with the height of what is seen there:
## its own point, and for a station or the exit the board that lights up for it
## close by (the panel the player looks at), for a note the slip on the table,
## for the jukebox and sink the thing itself.
static func aim_points(g: Game, device: Variant) -> Array:
	if g.aim_cache.get("level") != g.world:
		# A level reloaded from the editor: its boards may have moved.
		g.aim_cache = {"level": g.world}
	var key: Variant = device if not (device is Array) else str(device[0])
	if g.aim_cache.has(key):
		return g.aim_cache[key]
	var at := use_point(g, device)
	var lift := .9
	var signal_name := ""
	var near_art := ""
	if device is LevelData.Station:
		signal_name = device.id
	elif device is LevelData.Extraction:
		signal_name = "exit"
	elif device is LevelData.Note:
		lift = 1.01
		near_art = "note"
	elif device is Array:
		near_art = str(device[0])
	var base := g.world.elevation(at.x, at.y)
	var placed := device is LevelData.Station or device is LevelData.Extraction
	var device_z: float = device.z if placed else NAN
	if placed and not is_nan(device_z):
		base = device_z
	var points: Array = [Vector3(at.x, at.y, base + lift)]
	for board: LevelData.Billboard in g.world.billboards:
		var d := Vector2(board.x, board.y).distance_to(at)
		var mine := signal_name != "" and board.signal_name == signal_name and d < 3.5
		if near_art == "note":
			mine = d < .8 and (board.image == "county_note" or board.image.begins_with("story_"))
		if mine:
			var z: float = g.world.elevation(board.x, board.y) + board.z + board.height * .5
			points.append(Vector3(board.x, board.y, z))
	if near_art != "" and near_art != "note":
		for prop: LevelData.Scenery in g.world.scenery:
			if prop.kind == near_art and Vector2(prop.x, prop.y).distance_to(at) < 1.5:
				var z: float = g.world.elevation(prop.x, prop.y) + prop.z + prop.height * .5
				points.append(Vector3(prop.x, prop.y, z))
		for spec: Variant in g.level.props:
			var spec_x: float = spec[1]
			var spec_y: float = spec[2]
			var q := Vector2(spec_x, spec_y)
			if str(spec[0]) == near_art and q.distance_to(at) < 1.5:
				var h: float = Game.PROP_HEIGHTS.get(near_art, 1.0)
				points.append(Vector3(q.x, q.y, g.world.elevation(q.x, q.y) + h * .5))
	g.aim_cache[key] = points
	return points


static func use_prompt(g: Game) -> String:
	if g.players.size() > 1 and ModeScreens.revive_prompt(g) != "":
		g.use_aim = Vector3.INF  # a partner down beside you (src/modes/)
		return ModeScreens.revive_prompt(g)
	var mst: Game.ModeFeature = g.features.get("mode")
	if mst != null and mst.mode != Modes.CAMPAIGN:
		var special: String = mst.rules().use_prompt(g)
		if special != "":
			g.use_aim = Vector3.INF  # the mode's own (a hostage, the bomb)
			return special
	var rides: Game.VehiclesScript = g.features.get("vehicles")
	if rides != null and (rides.seated(g.player) or rides.prompt(g.player) != ""):
		g.use_aim = Vector3.INF  # getting in or out of a vehicle
		return rides.prompt(g.player)
	var found: Variant = use_target(g)
	if found == null:
		return ""
	var target: Variant = found[0]
	if target is String:
		if target == "bessie":
			var boss_alive: bool = g.boss != null and g.boss.alive
			var jerry_alive: bool = g.jerry != null and g.jerry.alive
			return "CLEAR THE PEN FIRST" if boss_alive or jerry_alive else "E  RESCUE BESSIE"
		if target == "jukebox":
			return "E  STOP JUKEBOX" if g.jukebox_on else "E  PLAY JUKEBOX"
		if target == "sink":
			return "E  USE SINK"
	if target is Game.Gallery:
		var booth: Game.Gallery = target
		return booth.prompt()
	if target is LevelData.Note:
		return "E  READ " + target.label
	if target is LevelData.Station:
		var station: LevelData.Station = target
		if g.stations_done.has(station.id):
			return "ALREADY SET"
		if station.reveals_secret:
			return "E  CHECK THE LOOSE PANEL"
		for key: Variant in station.requires:
			if not g.stations_done.has(str(key)):
				return g.objective()
		if station.held != "" and not g.task_items.has(station.held):
			return "FIND THE PATCH LEAD AT THE RAFFLE OFFICE"
		if station.action == "strike":
			return "STRIKE THE BELT RELEASE"
		if station.action == "crank":
			var turned: int = g.valve_turns.get(station.id, 0)
			return "E  TURN THE CONDENSER  %d/3" % turned
		return "E  " + station.label
	if target is LevelData.Extraction:
		return "E  " + target.label if g.exit_ready() else "EXIT LOCKED / CHECK THE MAP"
	var door: LevelData.Door = target
	if g.world.controlled_doors.has(Vector2i(door.x, door.y)):
		return (
			""
			if door.opened
			else BossFight.door_note(g.world, door, "CONTROLLED BY A REMOTE SWITCH")
		)
	if door.blast_only:
		return "POWDER STORE  /  BLAST PANEL"
	if door.key != "" and not g.keys.has(door.key):
		return "BRASS KEY NEEDED" if door.key.ends_with("brass") else "STEEL KEY NEEDED"
	if door.secret and not door.discovered:
		if g.world.crouch_doors.has(Vector2i(door.x, door.y)):
			return "CROUCH / USE THE LOW HATCH"
		return ""
	return "E  CLOSE DOOR" if door.opened else "E  OPEN DOOR"


static func interact(g: Game) -> void:
	if g.showing_tally or g.player.health <= 0:
		return
	if g.boss_hold > 0.0:
		# USE cuts a boss's entrance short (BossKit.hold).
		if g.boss_hold_for - g.boss_hold > BossKit.SKIP_AFTER:
			g.boss_hold = 0.0
		return
	var mst: Game.ModeFeature = g.features.get("mode")
	if mst != null and mst.mode != Modes.CAMPAIGN and mst.rules().use(g):
		return  # the mode's own (a hostage taken or set down)
	var rides: Game.VehiclesScript = g.features.get("vehicles")
	if rides != null and rides.use(g.player):
		return  # in or out of a vehicle (features/vehicles.gd)
	var gate: LevelData.Gate = portal_target(g)
	if gate != null:
		if g.world.locked_gates.has(gate):
			g.message(gate_text(g, gate), 3.0)
			g.sound.play("chain_rattle")
		elif g.armory.fuse > 0.0:
			g.message("THROW THE LIT STICK BEFORE LEAVING.", 3.0)
		else:
			g.portal_request = gate.destination
		return
	if g.in_hub:
		var clue: Variant = hub_clue(g)
		if clue != null:
			g.message(str(clue[4]), 4.0)
			if str(clue[0]) == "dispatch":
				if g.clock >= g.hub_dispatch_until:
					g.hub_dispatch_until = g.clock + 6.0
					var place := g.sound_position(g.level.hub_board.x, g.level.hub_board.y, .64)
					g.sound.play_voice("county_dispatch_%d" % g.hub_milestone, place.x, place.y)
					if g.voice_captions:
						g.caption = str(Game.HUB_DISPATCH[g.hub_milestone][2])
						g.caption_until = g.clock + 2.4
			else:
				g.hub_findings[str(clue[0])] = true
				g.sound.play("menu_accept", .55)
		return
	var critters: Object = g.features.get("critters")
	if critters != null and critters.call("tip", g.player):
		return  # a cow tipped over (features/critters.gd)
	var found: Variant = use_target(g)
	if found == null:
		return
	var target: Variant = found[0]
	var x: float = found[1]
	var y: float = found[2]
	if target is String:
		if target == "bessie":
			if (g.boss != null and g.boss.alive) or (g.jerry != null and g.jerry.alive):
				g.message("CLEAR THE PASTURE BEFORE YOU FREE BESSIE.", 2.4)
			elif g.revisiting:
				g.message("BESSIE IS SAFE. RETURN VIA THE ROAD GATE.", 2.4)
			else:
				g.finish_level("got_bessie")
			return
		if target == "jukebox":
			g.jukebox_on = not g.jukebox_on
			g.radio_check = 0.0
			g.sound_at("menu_accept", x, y, .54)
			g.message("JUKEBOX: HICKSTON SHUFFLE" if g.jukebox_on else "JUKEBOX OFF", 1.45)
			return
		if target == "sink":
			if g.clock >= g.flush_until:
				g.flush_until = g.clock + 1.35
				g.sound_at("sink_flush", x, y, .83)
				g.burst(x, y, .86, "splash", 8, .47)
				g.message("WASH UP, YOU ANIMAL.", 1.5)
			return
	if target is Game.Gallery:
		var booth: Game.Gallery = target
		booth.toggle(g)
		return
	if target is LevelData.Note:
		var note: LevelData.Note = target
		g.message(note.text, 4.0)
		g.sound.play("menu_move", .40)
		return
	if target is LevelData.Station:
		var station: LevelData.Station = target
		g.operate_station(station)
		return
	if target is LevelData.Extraction:
		if g.revisiting:
			g.message("SHIFT DONE. RETURN VIA THE ROAD GATE.", 2.4)
		elif g.exit_ready():
			g.finish_level("gate")
		else:
			g.message(g.objective(), 3.0)
			g.sound_at("chain_rattle", x, y, .8)
		return
	var door: LevelData.Door = target
	if g.world.controlled_doors.has(Vector2i(door.x, door.y)):
		if not door.opened:
			g.message(BossFight.door_note(g.world, door, "THAT GATE HAS A REMOTE SWITCH."), 2.5)
		return
	if door.key != "" and not g.keys.has(door.key):
		g.message(
			(
				"NEEDS THE BRASS BARN KEY."
				if door.key.ends_with("brass")
				else "NEEDS THE STEEL PASTURE KEY."
			),
			2.7
		)
		g.sound.play("empty")
		return
	if door.blast_only:
		g.message("POWDER STORE. THAT PANEL NEEDS DYNAMITE.", 2.65)
		g.sound.play("empty", .56)
		return
	if (
		g.world.crouch_doors.has(Vector2i(door.x, door.y))
		and not g.player.crouched
		and not door.discovered
	):
		g.message("GET LOW AND TRY THE HATCH AGAIN.", 3.0)
		return
	g.toggle_door(door, not door.opened)


static func portal_target(g: Game, reach := 2.62) -> Variant:
	var portals: Array = g.world.hub_gates if g.in_hub else [g.world.return_gate]
	for gate: LevelData.Gate in portals:
		if gate == null:
			continue
		if (
			gate.approach(g.player.x, g.player.y, g.player.view_angle(), reach)
			or gate_aimed(g, gate)
		):
			var face: float = gate.y + (.17 if g.player.y - gate.y >= 0.0 else -.17)
			if g.world.visible(
				g.player.x,
				g.player.y,
				g.player.x,
				face,
				g.player.eye,
				g.world.elevation(g.player.x, face) + .93
			):
				return gate
	return null


## A gate the player stands in front of with the crosshair on its opening,
## however slanting (Gate.approach wants the gate fairly square ahead).
static func gate_aimed(g: Game, gate: LevelData.Gate) -> bool:
	var d := (g.player.y - gate.y) * gate.side
	if d < .15 or d > 1.9 or absf(g.player.x - gate.x) > gate.width * .5 + .1:
		return false
	var toward := -sin(g.player.view_angle()) * gate.side
	if toward < .15:
		return false
	var hit := g.player.x + cos(g.player.view_angle()) * d / toward
	return absf(hit - gate.x) < gate.width * .5 and d / toward < 2.4


static func hub_clue(g: Game) -> Variant:
	var label: String = str(Game.HUB_DISPATCH[g.hub_milestone][0])
	var text: String = str(Game.HUB_DISPATCH[g.hub_milestone][1])
	var best: Variant = null
	var best_rank := [true, INF]
	var candidates: Array = g.world.hub_clues.duplicate()
	candidates.append(["dispatch", g.level.hub_board.x, g.level.hub_board.y, "READ " + label, text])
	var facing := Vector2(cos(g.player.view_angle()), sin(g.player.view_angle()))
	for clue: Variant in candidates:
		var x: float = clue[1]
		var y: float = clue[2]
		# As the quest devices: a little reach, the one nearest the crosshair.
		var rank := use_rank(g, x, y, DEVICE_REACH, DEVICE_TOUCH, DEVICE_CONE, facing)
		if (
			ranks_above(rank, best_rank)
			and g.seen_at(Vector3(x, y, g.world.elevation(x, y) + .96))
		):
			best = clue
			best_rank = rank
	return best


static func gate_text(g: Game, gate: LevelData.Gate) -> String:
	if gate.destination == "hub":
		return "E  RETURN TO COUNTY CROSSROADS"
	if g.world.locked_gates.has(gate):
		var index := Campaign.ORDER.find(gate.destination)
		var previous: String = Campaign.ORDER[index - 1] if index > 0 else ""
		return "LOCKED / FINISH " + Campaign.title_of(previous)
	return (
		"E  "
		+ str(g.gate_modes.get(gate.destination, "ENTER"))
		+ " "
		+ Campaign.title_of(gate.destination)
	)


static func gate_prompt(g: Game) -> String:
	var gate: LevelData.Gate = portal_target(g)
	if gate != null:
		return gate_text(g, gate)
	var clue: Variant = hub_clue(g) if g.in_hub else null
	return "E  " + str(clue[3]) if clue != null else ""
