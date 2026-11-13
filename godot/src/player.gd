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

# What each player has of their own (src/players.gd: the per-player vs shared
# split). The game's `armory`, `inventory`, `keys`, `task_items`, `sprint`,
# `inventory_slot` and `flow` are those of the acting player (Game.focus()).

## Its place in game.players, never reused while the game runs: the stable id a
## network snapshot names it by (0 is player one).
var slot := 0
var armory: Weapons.Armory
## The pockets (rinds, beer...), a key ring and carried quest items. A
## Dictionary Players.SHARED names is one object every player holds.
var inventory := {}
var inventory_slot := 0
var keys := {}
var task_items := {}
## Moonshine's burst of speed, seconds left.
var sprint := 0.0
## Steps from this player over open floor: the enemies after this player
## walk it when they lose sight of them (flow_field.gd).
var flow: FlowField
## With more than one player: the flow field is to be walked from where they
## stand when something first needs it this tick (Game.focus()).
var flow_due := false
## USE was held last tick (Controls.use acts on a fresh press).
var use_held := false
## Footsteps taken (a sound each) and when a full gut may belch next.
var step_number := 0
var next_belch := 0.0
## Heard from: what the acting player's own sounds play through when this is
## not the local player (player_voice.gd places them where this player stands).
var voice = null

# What the game modes keep on each player (src/modes/; CLAUDE.md "Modes").

## USE is held down this tick (Controls.use or Controls.hold): reviving a partner.
var holding := false
## When this player went down (game.clock; -1 while up), and how far a partner
## has got reviving them (seconds of REVIVE_TIME).
var down_at := -1.0
var revive := 0.0
## Versus: frags (a kill of another player +1, a fall to the world or your
## own blast -1), deaths, and the team (team deathmatch: 0 red, 1 blue).
var frags := 0
var deaths := 0
var team := 0
## Who last brought this player down (a slot; -1 the world or an enemy).
var downed_by := -1


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
