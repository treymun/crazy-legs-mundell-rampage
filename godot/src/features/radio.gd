## The county radio in a game (content pass 8): tells this machine's station
## (src/radio_station.gd, kept by Sound) what Mundell has been up to and where
## the radio sets are, and captions what it says. Looks and sound only: it
## reads the game and its events, never changes play, saves nothing, and on
## every machine (co-op, online) its own station hears its own game.
##
## The news: a blast, a vehicle burnt out, a boss down, a run of kills, the
## local player drunk, a secret found, a death (a few make a rough night);
## for the scanner also shots fired in a fight and a deputy killed. The sets:
## a jukebox playing, a radio on a desk (a level's "*radio*" exchange or
## picture), the Crossroads' dispatch board, a ready vehicle's radio, and the
## vehicle the local player sits in.
extends GameFeature

const BossVoices := preload("res://src/features/boss_voices.gd")
const FightMusic := preload("res://src/features/fight_music.gd")
const Vehicles := preload("res://src/features/vehicles.gd")

## Seconds between looks at the game.
const LOOK := .25
## A set is heard from this far.
const REACH := 9.0
## This many kills inside KILL_WINDOW seconds is a rampage.
const KILLS := 8
const KILL_WINDOW := 40.0
## Drunk past this (of 100) is news.
const DRUNK := 60.0
## The scanner is captioned only when it is this near (or in a vehicle).
const SCAN_CAPTIONED := .3

## Set by the checks instead of the machine's own (null: Sound's).
var station: RadioStation = null
var _look_left := 0.0
var _sets: Array[Vector2] = []
var _kills: Array[float] = []
var _down := false
var _drunk_told := false
var _secrets := -1
var _burnt := {}
var _riding := false
var _said := 0


func id() -> String:
	return "radio"


func attach() -> void:
	tick_with(_tick)
	game.events.exploded.connect(
		func(_x: float, _y: float, _z: float, _energy: bool) -> void: _news("boom")
	)
	game.events.enemy_killed.connect(_killed)
	game.events.shot_fired.connect(_shot)
	game.events.boss_down.connect(_boss_down)
	_find_sets()


## The machine's station (null with no sound: the lobby server, a voice).
func the_station() -> RadioStation:
	if station != null:
		return station
	var ear: GameSound = game.speaker if game.speaker != null else game.sound
	var node := ear.node() if ear != null else null
	return node.station if node != null else null


func _news(topic: String) -> void:
	var st := the_station()
	if st != null and not game.in_hub:
		st.news(topic)


func _killed(e: Enemy) -> void:
	if e.kind.contains("deputy"):
		_news("officer")
	_kills.append(game.clock)
	while not _kills.is_empty() and game.clock - _kills[0] > KILL_WINDOW:
		_kills.pop_front()
	if _kills.size() >= KILLS:
		_kills.clear()
		_news("rampage")


func _shot(_gun: int) -> void:
	var music: FightMusic = game.features.get("fight_music")
	if music != null and music.fighting:
		_news("shots")


func _boss_down(e: Enemy, _seconds: float) -> void:
	var who := BossVoices.speaker_of(e)
	if who != "":
		_news("boss_" + who)


## The radio sets standing in the level (a jukebox counts only while playing).
func _find_sets() -> void:
	_sets.clear()
	for row: Variant in game.exchanges:
		var talk: LevelData.Exchange = row
		if talk.id.contains("radio"):
			_sets.append(Vector2(talk.x, talk.y))
	for row: Variant in game.level.billboards:
		var board: LevelData.Billboard = row
		if board.image.contains("radio"):
			_sets.append(Vector2(board.x, board.y))
	# A jukebox with no switch of its own (the fair's, the mill's, the quarry's,
	# the diner's) plays the station low; one with a switch only while on.
	var switched := false
	for device: Array in game.level.devices:
		switched = switched or str(device[0]) == "jukebox"
	if not switched:
		for row: Variant in game.level.scenery:
			var thing: LevelData.Scenery = row
			if thing.kind == "jukebox":
				_sets.append(Vector2(thing.x, thing.y))
	if game.in_hub:
		_sets.append(game.level.hub_board)


func _tick(dt: float) -> void:
	_look_left -= dt
	if _look_left > 0.0:
		return
	_look_left = LOOK
	var st := the_station()
	if st == null or game.players.is_empty():
		return
	var p := game.local_player
	st.enabled = not Modes.is_tactical(game)
	st.chatter = int(game.chatter)
	st.place = "hub" if game.in_hub else CountyData.base_of(game.level.id)
	var music: FightMusic = game.features.get("fight_music")
	st.hold = music != null and music.boss_fight
	var dead := p.health <= 0
	if dead and not _down:
		_news("death")
	_down = dead
	if p.drunk >= DRUNK and not _drunk_told:
		_drunk_told = true
		_news("drunk")
	elif p.drunk < DRUNK * .3:
		_drunk_told = false
	if _secrets < 0:
		_secrets = game.secrets
	elif game.secrets > _secrets:
		_secrets = game.secrets
		_news("secret")
	_vehicles(st, p)
	_nearest(st, p)
	_caption(st)


## A vehicle burnt out is news; taking one tunes its radio in.
func _vehicles(st: RadioStation, p: Player) -> void:
	var rides: Vehicles = game.features.get("vehicles")
	var riding := false
	if rides != null:
		for i in rides.rides.size():
			var v: VehicleDrive.Ride = rides.rides[i]
			if v.wreck >= 0.0 and not _burnt.has(i):
				_burnt[i] = true
				_news("wreck")
			if v.seats.has(p.slot):
				riding = true
	if riding and not _riding:
		st.tune_in()
	_riding = riding
	st.driving = riding


## The nearest set heard: how near (sound_position's level, by distance),
## its pan and muffle.
func _nearest(st: RadioStation, p: Player) -> void:
	var spots: Array[Vector2] = _sets.duplicate()
	if game.jukebox_on:
		for device: Array in game.level.devices:
			if str(device[0]) == "jukebox":
				var x: float = device[1]
				var y: float = device[2]
				spots.append(Vector2(x, y))
	var rides: Vehicles = game.features.get("vehicles")
	if rides != null:
		var tune := rides.radio(p)
		if tune != Vector3.INF:
			spots.append(Vector2(tune.x, tune.y))
	var best := 0.0
	var best_at := Vector2.INF
	for at: Vector2 in spots:
		var d := Vector2(at.x - p.x, at.y - p.y).length()
		if d >= REACH:
			continue
		var heard := clampf(game.sound_position(at.x, at.y, 1.0).x, 0.0, 1.0) * (1.0 - d / REACH)
		if heard > best:
			best = heard
			best_at = at
	st.near = clampf(best * 1.6, 0.0, 1.0)
	if best_at != Vector2.INF:
		st.near_pan = game.sound_position(best_at.x, best_at.y, 1.0).y
		st.near_cutoff = game.sound_cutoff(best_at.x, best_at.y)
	else:
		st.near_pan = 0.0
		st.near_cutoff = Sound.OPEN_CUTOFF


## What the radio says, captioned (VOICE CAPTIONS) when nothing else is: Dub
## always, the scanner only near a set or in a vehicle.
func _caption(st: RadioStation) -> void:
	if st.said_count == _said:
		return
	_said = st.said_count
	if not game.voice_captions or game.clock < game.caption_until or st.now >= st.said_until:
		return
	if st.said_channel == RadioStation.SCANNER and st.near < SCAN_CAPTIONED and not st.driving:
		return
	game.caption = st.said
	game.caption_until = game.clock + (st.said_until - st.now)
