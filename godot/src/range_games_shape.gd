## The shapes of the firing range's midway games and the fair's gallery: the
## play (range_games.gd, range_skeeball.gd, features/fair_gallery.gd) and the
## 3D meshes (view3d/solid_kit.gd) read the same numbers here, so a horseshoe
## rings the stake it is drawn round and a skee-ball drops into the ring it is
## drawn in. Cells throughout (a cell is about a yard); z up.
extends RefCounted

# ------------------------------------------------------------------ horseshoes

## A shoe: the radius of its bar's middle line, the bar's half thickness, and
## how far round from the heel its arms reach each way (radians; the mouth is
## the rest).
const SHOE_R := .085
const SHOE_BAR := .014
const SHOE_ARC := 2.6
## The stake: its radius and how high it stands out of the pit.
const STAKE_R := .022
const STAKE_TOP := .42

# ------------------------------------------------------------------ skee-ball

## The lane, in its own frame: s along it from its foot, u across, z up from
## the floor. Its width between the rails, the bed's height at the foot and
## its rise a cell, its length to the hump, the hump's length and lift and
## the angle it throws the ball up at.
const SKEE_W := .9
const SKEE_FOOT := .62
const SKEE_RISE := .176
const SKEE_LANE := 3.2
const SKEE_HUMP := .24
const SKEE_HUMP_UP := .07
const SKEE_KICK := .5
## The ring board: where along the lane its bottom edge is, how high, how far
## up its slope it runs and the slope (radians up from flat).
const SKEE_BOARD_S := 3.78
const SKEE_BOARD_Z := 1.02
const SKEE_BOARD_LEN := 1.0
const SKEE_TILT := .55
## The back of the cabinet, along the lane, and how high it stands.
const SKEE_BACK_S := 4.7
const SKEE_BACK_TOP := 2.35
const SKEE_BALL_R := .075
## The rings round their middle, up the board RING_AT from its bottom edge:
## [outer radius, points], the smallest first; past the last it is 10.
const SKEE_RING_AT := .5
const SKEE_RINGS := [[.085, 50], [.17, 40], [.255, 30], [.34, 20]]
## The two 100 cups in the board's top corners: up the board, across, radius.
const SKEE_HUNDRED := [.9, .34, .06]

# ------------------------------------------------------------------ bottles

## A milk bottle's body for the rigid-body solver (range_pin_physics.gd):
## spheres up its axis [height, radius], its centre of mass, its foot's
## radius, its height, and its moments across and along its axis.
const BOTTLE := [[.04, .044], [.1, .046], [.155, .041], [.205, .027], [.25, .02]]
const BOTTLE_COM := .1
const BOTTLE_FOOT := .036
const BOTTLE_LEN := .27
const BOTTLE_I := [.0062, .0011]
## A softball's radius, and the table the bottles stand on: its top and half
## its size across and deep.
const SOFTBALL_R := .05
const TABLE_TOP := .82
const TABLE_HALF := Vector2(.62, .38)

# ------------------------------------------------------------------ dunk tank

## The tank: half its size (across, front to back), the rim's height, the
## water's, the seat's height and how far it stands out over the water from
## its hinge at the back, the bullseye's radius and where it hangs off the
## tank's east side (across, front to back, up from the floor).
const TANK := Vector2(.82, .58)
const TANK_TOP := 1.12
const WATER := .96
const SEAT_Z := 1.42
const SEAT_DEEP := .36
const TARGET_R := .2
const TARGET_AT := Vector3(1.45, -.2, 1.32)

# ------------------------------------------------------------------ the fair

## A tin can's radius and height.
const CAN_R := .045
const CAN_H := .13
