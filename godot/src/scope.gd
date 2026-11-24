## A rifle scope (weapons.cfg `scope`, Player.scoped): while this machine's
## player has one up the view closes in by its zoom (the renderer's focal
## length; aiming works its slopes out from the same View.base_focal, so
## the crosshair stays true), the gun is not drawn and the view is masked to
## a round glass with a cross-hair. Presentation only: the scope's play (its
## tight spread, ALT FIRE putting it up) is the game's own (game.gd, weapons.gd).
class_name Scope
extends RefCounted

const RADIUS := 66.0
## The picture's pixels are taller than wide on a 4:3 screen: the glass is
## drawn this much wider than tall to look round there.
const ASPECT := 1.2
const HAIR := Color8(8, 8, 8)

static var _mask := PackedByteArray()
## The picture's columns and glass shape the mask was made for.
static var _made_for := Vector2(0, 0)


## The renderer's focal length for this frame: the FIELD OF VIEW's, times the
## zoom while the scope is up.
static func focal(game: Game, p: Player) -> void:
	var zoom := 1.0
	if p.scoped and p.health > 0:
		var firing := game.armory.firing(game.armory.active)
		zoom = firing.get("scope", 1.0)
	var want := View.fov_focal * zoom
	if absf(want - View.base_focal) > .01:
		View.base_focal = want
		game.view.set_detail(game.view.detail, true)


## The mask made again at the next frame (WIDE changed the picture's width).
static func forget() -> void:
	_mask = PackedByteArray()


## The scope's black surround, its rim and cross-hair, over the view: across
## the whole picture in WIDE, where the pixels are square and the glass round.
static func mask(c: Canvas) -> void:
	var w := View.cols
	var h := View.VIEW
	var aspect := 1.0 if View.square else ASPECT
	if _mask.is_empty() or _made_for != Vector2(w, aspect):
		_made_for = Vector2(w, aspect)
		_mask = PackedByteArray()
		_mask.resize(w * h * 4)
		var cx := w * .5
		var cy := h * .5
		for y in h:
			for x in w:
				var d := Vector2((x + .5 - cx) / aspect, y + .5 - cy).length()
				var o := (y * w + x) * 4
				var a := 0
				if d > RADIUS:
					a = 255
				elif d > RADIUS - 3.0:
					a = 200
				elif absf(x + .5 - cx) < 1.0 and absf(y + .5 - cy) > 3.0:
					a = 230 if absf(y + .5 - cy) < RADIUS * .55 else 255
				elif absf(y + .5 - cy) < 1.0 and absf(x + .5 - cx) > 3.0:
					a = 230 if absf(x + .5 - cx) < RADIUS * aspect * .55 else 255
				_mask[o] = HAIR.r8
				_mask[o + 1] = HAIR.g8
				_mask[o + 2] = HAIR.b8
				_mask[o + 3] = a
	var key := (
		"scope_mask"
		if w == View.WIDTH and aspect == ASPECT
		else "scope_mask_%d_%d" % [w, aspect * 10]
	)
	c.blit_rgba(_mask, w, h, -View.shift, 0, key)
