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

var game


func _init(p_game) -> void:
	game = p_game
	attach()


func id() -> String:
	return ""


func attach() -> void:
	pass


## What to keep in a save (plain values: numbers, strings, arrays, dictionaries).
func save() -> Dictionary:
	return {}


## Back from a save; `state` is {} when the save had nothing for this feature.
func restore(_state: Dictionary) -> void:
	pass


## [label, value] rows for the chapter's tally.
func tally_rows() -> Array:
	return []


## Sprites it adds to the view this frame (Renderer.Sprite).
func sprites() -> Array:
	return []


## Draws over the view this frame, under the gun: lines and drops on the
## 320-wide canvas `c` (game.to_canvas() says where a point of the world falls).
func draw_view(_c: Canvas) -> void:
	pass


## Marks it lays on the floors this frame (Renderer.GroundMark).
func ground_marks() -> Array:
	return []


## Marks it lays on the walls this frame (Renderer.WallMark, as
## Renderer.wall_mark() finds them): scorches, blood running down.
func wall_marks() -> Array:
	return []
