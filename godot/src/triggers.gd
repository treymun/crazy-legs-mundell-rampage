## Level triggers: set pieces as data in a level's JSON ("triggers"), not
## code. Each one waits for its condition, then runs its actions, once (or
## every time, with "once": false, each time the condition comes true again).
##
##   {"id": "office-alarm",
##    "when": {"area": [x0, y0, x1, y1]}      the player stands in the box
##            {"key": "key_brass"}            the player holds that key
##            {"station": "games"}            that station is done
##            {"kills": 12}                   that many kills in the chapter
##            {"after": 30.0}                 seconds into the chapter
##            {"down": ["id", ...]}           every one of those enemies is down
##            {"run": "channel_run"}          that vehicle set piece has been
##                                            started (features/vehicle_runs.gd)
##    "once": true,
##    "do": [{"message": "TEXT", "for": 3.0},
##           {"sound": "cue", "at": [x, y]},  ("at" left out: heard everywhere)
##           {"open": [x, y]},                the door in that cell
##           {"wake": ["id", ...]},           enemies this trigger holds back
##                                            (dormant until it fires) come in
##           {"alert": 12.0},                 every enemy that close comes for
##                                            the player, round walls included
##           {"light": {"at": [x, y], "z": 1.2, "color": [r, g, b],
##                      "radius": 5.0, "strength": 1.4, "for": 4.0}},
##                                            (effects.cfg [light.trigger]
##                                            fills in what is left out)
##           {"shake": 0.6},
##           {"pickup": {"name": "shells", "at": [x, y]}}]}
##
## Fired triggers are saved (Game.triggers_fired). The level editors draw the
## areas (level_editor.gd in the game, addons/clmr_levels in the Godot editor).
class_name Triggers
extends RefCounted


## Enemies held back by a trigger's "wake" start dormant (Game._init).
static func held_back(level: LevelData) -> Dictionary:
	var held := {}
	for trigger: Dictionary in level.triggers:
		for action: Dictionary in trigger.get("do", []):
			for id: Variant in action.get("wake", []):
				held[str(id)] = true
	return held


static func tick(game: Game) -> void:
	if game.in_hub or game.revisiting or Modes.is_versus(game):
		return
	for trigger: Dictionary in game.level.triggers:
		var id := str(trigger.get("id", ""))
		var once: bool = trigger.get("once", true)
		if once and game.triggers_fired.has(id):
			continue
		var when: Dictionary = trigger.get("when", {})
		var now := _met_any(game, when)
		if not once:
			# Fires on the way in, not on every tick spent inside.
			var was: bool = game.triggers_inside.get(id, false)
			game.triggers_inside[id] = now
			if not now or was:
				continue
		elif not now:
			continue
		game.triggers_fired[id] = true
		for action: Dictionary in trigger.get("do", []):
			run(game, action)
	game.focus(game.local_player)


## Whether any player meets `when`; the first who does (by slot) is left
## acting, so what the trigger does (a wake, a light) is about them.
static func _met_any(game: Game, when: Dictionary) -> bool:
	if game.players.size() == 1:
		return _met(game, when)
	for q: Player in game.players:
		if q.health > 0:
			game.focus(q)
			if _met(game, when):
				return true
	game.focus(game.local_player)
	return false


static func _met(game: Game, when: Dictionary) -> bool:
	var p := game.player
	if when.has("area"):
		var box: Array = when["area"]
		if not (
			_float(box[0]) <= p.x
			and p.x <= _float(box[2])
			and _float(box[1]) <= p.y
			and p.y <= _float(box[3])
		):
			return false
	if when.has("key") and not game.keys.has(str(when["key"])):
		return false
	if when.has("station") and not game.stations_done.has(str(when["station"])):
		return false
	if when.has("kills") and game.kills < _int(when["kills"]):
		return false
	if when.has("after") and game.clock < _float(when["after"]):
		return false
	if when.has("run"):
		var runs: GameFeature = game.features.get("vehicle_runs")
		if runs == null or not runs.call("started", str(when["run"])):
			return false
	if when.has("down"):
		for id: Variant in when["down"]:
			var at: int = game.enemy_ids.find(str(id))
			if at >= 0 and game.enemies[at].hp > 0.0:
				return false
	return true


## One action (also used by the level editor to try a trigger out).
static func run(game: Game, action: Dictionary) -> void:
	var p := game.player
	if action.has("message"):
		game.message(str(action["message"]), _float(action.get("for", 3.0)))
	if action.has("sound"):
		var at: Variant = action.get("at")
		if at is Array:
			game.sound_at(str(action["sound"]), _float(at[0]), _float(at[1]))
		else:
			game.sound.play(str(action["sound"]))
	if action.has("open"):
		var cell: Array = action["open"]
		for door: LevelData.Door in game.world.doors:
			if door.x == _int(cell[0]) and door.y == _int(cell[1]):
				game.toggle_door(door, true)
	if action.has("wake"):
		for id: Variant in action["wake"]:
			var at: int = game.enemy_ids.find(str(id))
			if at < 0:
				continue
			var enemy: Enemy = game.enemies[at]
			enemy.dormant = false
			enemy.wake(game, p.x, p.y)
	if action.has("alert"):
		# Walking distance on the flow field, not through walls; never a boss,
		# whose waking is its own scene.
		var reach := int(_float(action["alert"]))
		for enemy: Enemy in game.enemies:
			if (
				enemy.alive
				and enemy.hostile
				and not Enemy.BOSS_TITLES.has(enemy.kind)
				and game.flow.distance(enemy.x, enemy.y) <= reach
			):
				enemy.wake(game, p.x, p.y)
	if action.has("light"):
		var spec: Dictionary = action["light"]
		var base: Dictionary = Effects.LIGHTS.get("trigger", {})
		var where: Array = spec.get("at", [p.x, p.y])
		var tint: Variant = spec.get("color")
		var color: Color = (
			Color(_float(tint[0]), _float(tint[1]), _float(tint[2]))
			if tint is Array
			else base.get("color", Color(1, .3, .2))
		)
		var x := _float(where[0])
		var y := _float(where[1])
		game.trigger_lights.append(
			[
				x,
				y,
				game.world.elevation(x, y) + _float(spec.get("z", base.get("height", 1.2))),
				_float(spec.get("radius", base.get("radius", 5.0))),
				color,
				_float(spec.get("strength", base.get("strength", 1.4))),
				game.clock + _float(spec.get("for", 4.0))
			]
		)
	if action.has("shake"):
		game.shake = minf(1.0, game.shake + _float(action["shake"]))
	if action.has("pickup"):
		var drop: Dictionary = action["pickup"]
		var spot: Array = drop.get("at", [p.x, p.y])
		game.add_pickup(str(drop["name"]), _float(spot[0]), _float(spot[1]))


## int() and float() of a value read from data or a dictionary, typed (the
## same result for a number, a bool or a number written as text).
static func _int(v: Variant) -> int:
	return str(v).to_int() if v is String else v


static func _float(v: Variant) -> float:
	return str(v).to_float() if v is String else v
