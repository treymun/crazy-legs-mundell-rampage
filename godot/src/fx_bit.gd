## One bit of the gun and blast effects' layer (features/gun_fx.gd and its
## helpers src/blast_looks.gd, src/vehicle_wreck_looks.gd): smoke, a spark,
## an ember, a scrap, a splinter, a drop. Looks only.
class_name FxBit
extends RefCounted

var x := 0.0
var y := 0.0
var z := 0.0
var vx := 0.0
var vy := 0.0
var vz := 0.0
## Below zero: not out yet.
var age := 0.0
var life := 1.0
var kind := ""
var size := .05
var grow := 0.0
var gravity := 0.0
var rest := false
var trail := 0.0
## Its age when it came to rest (the 3D view settles it onto a face).
var landed := -1.0
## A scrap's own picture set (fx_scrap_<it>_N, fx_chunk_N when ""), a smoke
## puff's (billow, billowhot, billowpowder, soot, dirtpuff, smoke): drawn by
## gun_fx.sprites().
var look := ""
## Which of a picture set's shapes it is (a billow's), and mirrored.
var shape := 0
var flip := false
## Which way a column's puff drifts out as it rises (a mushroom's cap), cells
## a second.
var spread := Vector2.ZERO


static func make(
	kind_name: String, at: Vector3, v: Vector3, seconds: float, start_size: float, fall := 0.0
) -> FxBit:
	var bit := FxBit.new()
	bit.kind = kind_name
	bit.x = at.x
	bit.y = at.y
	bit.z = at.z
	bit.vx = v.x
	bit.vy = v.y
	bit.vz = v.z
	bit.life = seconds
	bit.size = start_size
	bit.gravity = fall
	return bit
