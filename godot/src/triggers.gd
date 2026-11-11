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
			for id in action.get("wake", []):
				held[String(id)] = true
	return held


static func tick(game) -> void:
	if game.in_hub or game.revisiting:
		return
	for trigger: Dictionary in game.level.triggers:
		var id := String(trigger.get("id", ""))
		var once := bool(trigger.get("once", true))
		if once and game.triggers_fired.has(id):
			continue
		var now := _met(game, trigger.get("when", {}))
		if not once:
			# Fires on the way in, not on every tick spent inside.
			var was := bool(game.triggers_inside.get(id, false))
			game.triggers_inside[id] = now
			if not now or was:
				continue
		elif not now:
			continue
		game.triggers_fired[id] = true
		for action: Dictionary in trigger.get("do", []):
			run(game, action)


static func _met(game, when: Dictionary) -> bool:
	var p = game.player
	if when.has("area"):
		var box: Array = when["area"]
		if not (
			float(box[0]) <= p.x
			and p.x <= float(box[2])
			and float(box[1]) <= p.y
			and p.y <= float(box[3])
		):
			return false
	if when.has("key") and not game.keys.has(String(when["key"])):
		return false
	if when.has("station") and not game.stations_done.has(String(when["station"])):
		return false
	if when.has("kills") and game.kills < int(when["kills"]):
		return false
	if when.has("after") and game.clock < float(when["after"]):
		return false
	if when.has("down"):
		for id in when["down"]:
			var at: int = game.enemy_ids.find(String(id))
			if at >= 0 and game.enemies[at].hp > 0.0:
				return false
	return true


## One action (also used by the level editor to try a trigger out).
static func run(game, action: Dictionary) -> void:
	var p = game.player
	if action.has("message"):
		game.message(String(action["message"]), float(action.get("for", 3.0)))
	if action.has("sound"):
		var at = action.get("at")
		if at is Array:
			game.sound_at(String(action["sound"]), float(at[0]), float(at[1]))
		else:
			game.sound.play(String(action["sound"]))
	if action.has("open"):
		var cell: Array = action["open"]
		for door: LevelData.Door in game.world.doors:
			if door.x == int(cell[0]) and door.y == int(cell[1]):
				game.toggle_door(door, true)
	if action.has("wake"):
		for id in action["wake"]:
			var at: int = game.enemy_ids.find(String(id))
			if at < 0:
				continue
			var enemy: Enemy = game.enemies[at]
			enemy.dormant = false
			enemy.wake(game, p.x, p.y)
	if action.has("alert"):
		# Walking distance on the flow field, not through walls; never a boss,
		# whose waking is its own scene.
		var reach := int(float(action["alert"]))
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
		var tint = spec.get("color")
		var color: Color = (
			Color(float(tint[0]), float(tint[1]), float(tint[2]))
			if tint is Array
			else base.get("color", Color(1, .3, .2))
		)
		var x := float(where[0])
		var y := float(where[1])
		game.trigger_lights.append(
			[
				x,
				y,
				game.world.elevation(x, y) + float(spec.get("z", base.get("height", 1.2))),
				float(spec.get("radius", base.get("radius", 5.0))),
				color,
				float(spec.get("strength", base.get("strength", 1.4))),
				game.clock + float(spec.get("for", 4.0))
			]
		)
	if action.has("shake"):
		game.shake = minf(1.0, game.shake + float(action["shake"]))
	if action.has("pickup"):
		var drop: Dictionary = action["pickup"]
		var spot: Array = drop.get("at", [p.x, p.y])
		game.add_pickup(String(drop["name"]), float(spot[0]), float(spot[1]))
