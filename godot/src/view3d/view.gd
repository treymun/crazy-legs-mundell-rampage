## What the game knows of its view: the picture's size and focal length (the
## old renderer's projection, which aiming, the crosshair and every screen
## overlay still use), the VIEW DETAIL and motion settings, and the things it
## hands the 3D view to draw (View.Sprite, View.WallMark, View.GroundMark).
## Nothing here draws: view3d/world_view.gd does, from these.
class_name View
extends RefCounted

## The canvas (HUD, menus, weapon) and the view's part of it.
const WIDTH := 320
const VIEW := 156
const HEIGHT := 200
const FOCAL := 230.0
## FIELD OF VIEW: the focal length for 70 (the view the game was drawn for),
## 80, 90 and 100 degrees across. base_focal is the one in use; aiming
## (weapons.gd, game_state.gd) works its slopes out with it too.
const FOCAL_FOR := [230.0, 190.7, 160.0, 134.3]
static var base_focal := FOCAL
## The FIELD OF VIEW setting's focal; base_focal is this times a scope's
## zoom while this machine's player has one up (scope.gd).
static var fov_focal := FOCAL
## VIEW DETAIL AUTO has dropped to LOW (main.gd _auto_detail); kept for the
## session so the next level starts where the last one settled.
static var auto_low := false
## RAGDOLLS (game_world.gd configure): dead enemies' models flop as ragdolls
## (ActorView, src/ragdoll.gd); off, they play their old scripted fall.
static var ragdolls := true


## A picture standing in the world: x, y on the map, z its feet, `height` tall
## (width from the picture's own shape). plane NaN faces the camera; an angle
## is a board fixed along it, seen from one side. body: an actor's picture
## (dropped by its empty bottom rows, never darker than a body's floor).
## translucent: blended (smoke, mist). hurt: a hit's wash. who: the enemy it
## shows (the 3D view draws that enemy's model when there is one).
class Sprite:
	var x := 0.0
	var y := 0.0
	var image := ""
	var height := 1.0
	var z := 0.0
	var glow := false
	var flip := false
	var translucent := false
	var body := false
	var plane := NAN
	## Which way a modelled prop faces when it is not a board (radians: its
	## front toward map (sin face, cos face)); NAN: the view picks the most
	## open way. A quest prop faces where its station is used from.
	var face := NAN
	var hurt := 0.0
	var who: Object = null
	## The model's frame when it is not the picture's (`<kind>[_hurt]_<frame>`,
	## read like a picture name by ActorView): a player body drawn with another
	## kind's model than its pictures (ModeBodies.player_pose). "": the picture's.
	var pose := ""
	## How far a billboard is turned over in the view's plane (radians, about
	## its middle; a gib or a chunk tumbling through the air). 0: upright.
	var spin := 0.0
	## A solid body drawn as a 3D mesh (SolidLayer3D: "pin", "ball") instead
	## of the picture, standing at (x, y, z) turned by `turn` (map axes, z up).
	var solid := ""
	var turn := Basis.IDENTITY
	## A slab's lean back about its foot, away from its front (radians; the
	## 3D view's range targets: a duck knocked flat, a gong's plate swinging
	## from its bar, a dummy rocking). Billboards ignore it.
	var tilt := 0.0
	## A loose thing on its floor, rolling or at rest: the 3D view lays its
	## slab flat (SlabLayer3D). Billboards ignore it.
	var lying := false
	## Seconds a lying loose thing has been on its floor: its slab eases over
	## from its tumble (`spin` as it came down) onto its face and rocks a
	## little (SlabLayer3D.settled). Below 0: it lies flat at once.
	var settle := -1.0
	## A lying round thing's turn about its length (a shell rolling).
	var roll := 0.0
	## A modelled prop on the move (a boss arena's wreck: a floodlight tower
	## toppling, a lamp coming down, a crate flung): a name the prop keeps
	## while it moves, so the 3D view moves one model instead of making one at
	## each new place; it stands at (x, y, z) turned by `turn` (map axes, z up)
	## about its foot. "": a prop standing where the level put it.
	var track := ""
	## A boss's gear shot off (features/boss_gear.gd): the gear's name, drawn
	## as that part of `who`'s model (ActorLayer3D) with its middle at (x, y,
	## z), turned by `turn`.
	var gear := ""

	func _init(px := 0.0, py := 0.0, img := "", h := 1.0, pz := 0.0) -> void:
		x = px
		y = py
		image = img
		height = h
		z = pz


## A mark on a wall face: its middle (x, y, z), the wall's direction (ux,
## uy), half its side, the picture, the material struck and the wall's tile.
class WallMark:
	var x := 0.0
	var y := 0.0
	var z := 0.0
	var ux := 0.0
	var uy := 0.0
	var image := ""
	var radius := .06
	var material := "wood"
	## The drawn face's tile (-1 when not from a wall): what the hole looks like.
	var tile := -1


## A mark on the ground: a rectangle at z, `reach` along `angle` and `width`
## across (both halves).
class GroundMark:
	var x := 0.0
	var y := 0.0
	var z := 0.0
	var angle := 0.0
	var reach := 1.0
	var width := 1.0
	var image := ""
	## The floor's rise per unit along x and y under it (a mark on a ramp lies
	## on the ramp): 0 on the flat.
	var gx := 0.0
	var gy := 0.0

	func _init(px := 0.0, py := 0.0, pz := 0.0, pa := 0.0, pr := 1.0, pw := 1.0, img := "") -> void:
		x = px
		y = py
		z = pz
		angle = pa
		reach = pr
		width = pw
		image = img


## DRAW DISTANCE: FAR shows the farthest a level reaches (the speedway seen
## across its oval); NEAR stops at 64 cells, where a wall is a few pixels tall,
## to spare a phone's graphics chip. AUTO is NEAR on phones, FAR elsewhere.
## Seconds after which a loose thing's settle on its floor is over
## (Sprite.settle): from then on it lies still, the same each frame.
const SETTLED := 1.0
const FAR_DRAW := 160.0
const NEAR_DRAW := 64.0


static func draw_far_for(setting: int) -> float:
	if setting == 2:
		return NEAR_DRAW
	if setting == 1:
		return FAR_DRAW
	var phone := (
		OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")
	)
	return NEAR_DRAW if phone else FAR_DRAW


var level: LevelData
var assets: Assets
## The size the view is drawn at: HIGH 320x156, LOW half that each way, HD
## twice (the 3D view's picture); the canvas is 320x200 whatever.
var vw := WIDTH
var vh := VIEW
var focal := FOCAL
var detail := 0
## How far the 3D view draws, in cells (DRAW DISTANCE: View.draw_far_for).
var draw_far := FAR_DRAW
var res_up := 1.0
## VIEW DETAIL HD was chosen (kept while a frame is drawn at HIGH).
var hd_wanted := false
var hd_held := false
## SCENERY MOTION: 0 full, 1 gentle, 2 still (the water, the shimmer, the rain).
var world_motion := 0
## The game's clock, for what moves in the view (signs, floors that run).
var time := 0.0
## The graphics card draws the view (a window); off in tools and the server.
var layered := false


func _init(p_assets: Assets, p_level: LevelData) -> void:
	assets = p_assets
	level = p_level
	set_detail(0)


## Choose HIGH (0), LOW (1) or HD (-1) view detail.
func set_detail(level_of_detail: int, keep_wish := false) -> void:
	detail = clampi(level_of_detail, -1, 1)
	if not keep_wish:
		hd_wanted = detail < 0
	vw = WIDTH * 2 if detail < 0 else WIDTH >> detail
	vh = VIEW * 2 if detail < 0 else VIEW >> detail
	focal = base_focal * vw / WIDTH
	res_up = float(VIEW) / vh


## The level's district tints, three floats a district.
var tints: PackedFloat32Array:
	get:
		return level.tints
