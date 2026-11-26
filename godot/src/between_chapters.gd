## Between chapters (pass 15): the ways on from a won chapter's card and the
## bests it keeps. BETWEEN CHAPTERS (PLAY page, `between`) says what the one
## tap does: STRAIGHT ON (the default) into the next chapter, kit carried,
## THE CROSSROADS to the hub, standing at the next chapter's gate facing it;
## the other is a plate of its own, and so is TRY TO BEAT IT (the chapter
## again as the hub's REPLAY gate starts it). main_flow.gd take_road does
## what a plate says; this file says which plates there are.
class_name BetweenChapters
extends RefCounted

const TallyFeature := preload("res://src/features/tally.gd")
const STRAIGHT_ON := 0
const THE_CROSSROADS := 1
## The keys' slots: the one tap's (ENTER, A), the other way's (the MAP key,
## Y), TRY TO BEAT IT's (the RELOAD key, X).
const GO := 0
const OTHER := 1
const AGAIN := 2
## Steps out in front of a gate the Crossroads puts the player.
const GATE_STEP := 1.8


static func straight(options: Dictionary) -> bool:
	var pick: int = options.get("between", STRAIGHT_ON)
	return pick != THE_CROSSROADS


## Whether this won game's bests are kept: a campaign chapter played alone by
## a person (not co-op or online, a rematch, a recorded replay, a tour, a
## bench, the demo, or with cheats).
static func keeps_bests(main: MainFlow, game: Game) -> bool:
	if not Campaign.ORDER.has(game.level.id) or game.in_hub or game.revisiting:
		return false
	if Modes.mode_of(game) != Modes.CAMPAIGN or BossRematch.active(game):
		return false
	if main.net != null or main.replay_play != null or game.cheats.used or game.cheats.god:
		return false
	return (
		main.view_tour == ""
		and main.view_bench == 0
		and main.smoke_frames == 0
		and not main.demo
		and not main.showcase
	)


## Once, at a won chapter's card: its bests read and, where they fell, kept
## (chapter_bests.json), for the card to show (features/tally.gd `card`).
static func settle(main: MainFlow, game: Game) -> void:
	var show: TallyFeature = game.features.get("tally")
	if show == null or show.card.has("settled") or not game.showing_tally:
		return
	var card := {"settled": true, "difficulty": ChapterBests.difficulty_name(game.difficulty)}
	if keeps_bests(main, game):
		var result := ChapterBests.record(
			game.level.id, game.difficulty, game.clock, game.kills, game.secrets
		)
		card.merge(result, true)
		card["kept_bests"] = true
	show.card = card


## The ways on from a won game's card: [key word, label, action, slot] each,
## the one tap's first; none where the card has its own way (a versus
## match, a rematch, a player's map, COUNTY RUN, online, the finale).
static func choices(main: MainFlow, game: Game) -> Array:
	if game.net_role != "" or Modes.is_versus(game) or BossRematch.active(game):
		return []
	if UserMap.is_custom(game.level.id) or CountyMode.active(game):
		return []
	if not Campaign.ORDER.has(game.level.id) or Modes.mode_of(game) == Modes.COOP:
		return []
	var ways: Array = []
	var run := main.campaign_run
	if game.replay:
		if run == null:
			ways = [["RETURN TO TITLE", "title"]]
		elif run.won:
			ways = [["THE CROSSROADS", "hub"]]
		else:
			ways = [["HIT THE ROAD", "road"], ["THE CROSSROADS", "hub"]]
	elif Campaign.next_level(game.level.id) == "":
		return []  # the finale's card (finale.gd)
	else:
		ways = [["NEXT CHAPTER", "next"], ["THE CROSSROADS", "hub"]]
	if ways.size() == 2 and not straight(main.options):
		ways.reverse()
	var words := key_words(main)
	var out: Array = []
	for i in ways.size():
		var way: Array = ways[i]
		out.append([words[i], way[0], way[1], i])
	if keeps_bests(main, game):
		out.append([words[AGAIN], "TRY TO BEAT IT", "replay", AGAIN])
	return out


## The three slots' keys in the words of the device last used.
static func key_words(main: MainFlow) -> Array:
	if main.input_device == "pad":
		return ["A", "Y", "X"]
	if main.input_device == "touch":
		return ["TAP", "TAP", "TAP"]
	var map_key: int = main.options.get(KeyBindings.option_key("map"), KEY_TAB)
	var reload_key: int = main.options.get(KeyBindings.option_key("reload"), KEY_R)
	return ["ENTER", KeyBindings.key_name(map_key), KeyBindings.key_name(reload_key)]


## The hub's player one put in front of `destination`'s gate, facing it, near
## enough to take it with USE; false (left where they were) when the hub has
## no such gate or no room there.
static func stand_at_gate(hub: Game, destination: String) -> bool:
	for gate: LevelData.Gate in hub.world.hub_gates:
		if gate.destination != destination:
			continue
		var x := gate.x
		var y := gate.y + gate.side * GATE_STEP
		if hub.world.blocked(x, y, GameState.PLAYER_RADIUS + .05):
			return false
		var p: Player = hub.players[0]
		p.x = x
		p.y = y
		p.angle = -gate.side * PI / 2.0
		p.pitch = 0.0
		p.vx = 0.0
		p.vy = 0.0
		p.eye = hub.world.stand(p) + .95
		hub.district = int(hub.world.area[hub.world.cell(x, y)])
		return true
	return false
