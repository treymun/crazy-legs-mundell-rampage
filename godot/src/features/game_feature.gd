## A feature of play kept in a file of its own: it listens to the game's events
## (game_state.gd: enemy_killed, player_hurt, pickup_taken, station_done,
## shot_fired, hit_landed, level_won, ticked) instead of being written into
## the code that does those things, and it saves its own state.
##
## To add one: extend this, give it an id(), connect what it needs in
## attach(), and list it in features.gd. Its save() goes in the save's
## "features" block under its id and comes back through restore(), which gets
## {} from a save made before the feature existed, so a new feature never needs
## a new save version. tally_rows() adds lines to the chapter's tally.
class_name GameFeature
extends RefCounted

var game: Game


func _init(p_game: Game) -> void:
	game = p_game
	attach()


func id() -> String:
	return ""


func attach() -> void:
	pass


## `on_tick(dt)` every tick, after the world (the events' `ticked`), in the
## features' order, while this feature is awake. Use this, not
## `ticked.connect`, so the order holds when a feature sleeps.
func tick_with(on_tick: Callable) -> void:
	game.events.add_tick(self, on_tick)


## Off the tick until wake(): call it only when every tick until then would
## do nothing at all (play must not change), and wake() wherever work comes
## (an event, a call from another feature). A snapshot or a save put on the
## game wakes every feature (GameEvents.wake_all()).
func sleep() -> void:
	game.events.set_awake(self, false)


func wake() -> void:
	game.events.set_awake(self, true)


## The game is let go for good (Game.dispose(), which has already cut every
## listener of its events): drop what points back at it. A feature holding
## more than `game` that points at the game (a helper keeping it) lets that
## go too, then calls super().
func detach() -> void:
	game = null


## What to keep in a save (plain values: numbers, strings, arrays, dictionaries).
func save() -> Dictionary:
	return {}


## Back from a save; `state` is {} when the save had nothing for this feature.
func restore(_state: Dictionary) -> void:
	pass


## [label, value] rows for the chapter's tally.
func tally_rows() -> Array:
	return []


## This machine's own shot shown ahead of the game (an online client's
## prediction, src/net/net_shot_predict.gd): the gun going off, a round's line
## ending at `end` on `struck` (as `traced` says), a reload starting. The
## looks-only features answer as they do to those events.
func own_shot(_gun: int) -> void:
	pass


func own_trace(_end: Vector3, _struck: String) -> void:
	pass


func own_reload(_gun: int) -> void:
	pass


## Sprites it adds to the view this frame (View.Sprite).
func sprites() -> Array:
	return []


## Draws over the view this frame, under the gun: lines and drops on the
## 320-wide canvas `c` (game.to_canvas() says where a point of the world falls).
func draw_view(_c: Canvas) -> void:
	pass


## Its HUD pieces that keep to the view's edges whatever else is up (a
## badge in a corner, a mode's strip): taken first, before the notice
## (ui/hud/hud_layout.gd; game_view.gd _lay_hud). draw_view draws them where
## they were taken.
func hud_fixed(_layout: HudLayout) -> void:
	pass


## Its HUD pieces that hang under the top of the view (the driving plates,
## a station's card): placed after the notice, the boss bar and the pin.
func hud_flow(_layout: HudLayout) -> void:
	pass


## Its HUD pieces that give way to the prompt and the caption (the kill
## feed): placed last, in what room is left.
func hud_late(_layout: HudLayout) -> void:
	pass


## Marks it lays on the floors this frame (View.GroundMark).
func ground_marks() -> Array:
	return []


## Marks it lays on the walls this frame (View.WallMark, as
## Renderer.wall_mark() finds them): scorches, blood running down.
func wall_marks() -> Array:
	return []
