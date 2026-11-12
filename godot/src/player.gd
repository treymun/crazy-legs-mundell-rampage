## Port of game.Player: the player's physical state plus the derived camera
## values the renderer and viewmodel read every frame.
class_name Player
extends RefCounted

var x := 0.0
var y := 0.0
var angle := 0.0
var health := 100
var gut := 0.0
var drunk := 0.0
var pitch := 0.0
var eye := .95
var bob := 0.0
var sway := 0.0
var drift := 0.0
var walk_phase := 0.0
var motion := 0.0
var air := 0.0
var vertical_speed := 0.0
var jump_held := false
var vx := 0.0
var vy := 0.0
var crouched := false
## How far the gun is off its place in screen pixels: behind a turn, away from
## a strafe, down on landing, kicked back by a shot, jolted by a hit
## (features/feel.gd's springs work it out; never saved).
var weapon_lag := Vector2.ZERO


func _init(px := 0.0, py := 0.0, pa := 0.0) -> void:
	x = px
	y = py
	angle = pa


## Camera yaw: the aiming angle leads the facing angle by the drunk drift.
func view_angle() -> float:
	return angle + drift


## Dictionary view for the renderer (Python passes the Player object directly).
func as_render_player() -> Dictionary:
	return {
		"x": x,
		"y": y,
		"eye": eye,
		"view_angle": view_angle(),
		"pitch": pitch,
		"bob": bob,
		"sway": sway,
	}
