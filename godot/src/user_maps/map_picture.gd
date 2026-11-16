## A player map drawn from above for the MAP SHED and the CUSTOM MAPS list:
## each cell its own tile's picture shrunk to the cell (so the plan looks like
## the place), walls lit on their top and left edges and shaded on the others,
## raised ground lighter with a shadow where it drops, inside floors in the
## dim, doors as a slab across their way. Things are drawn over it each frame
## as small marks (icon()). The cell pictures are made once a size.
class_name MapPicture
extends RefCounted

const WALL_LIFT := 1.12
const INSIDE_DIM := .78
const EDGE_LIGHT := Color8(250, 226, 170)
const EDGE_DARK := Color8(16, 11, 8)
const SHADOW := Color8(20, 14, 10)
const DOOR := Color8(150, 94, 46)
const DOOR_EDGE := Color8(54, 32, 16)
const BAD := Color8(238, 89, 52)
const GRID := Color8(0, 0, 0)
## Icon colours: hands, loot, props, marks.
const HAND := Color8(214, 72, 48)
const HAND_EDGE := Color8(60, 14, 8)
const LOOT := Color8(244, 206, 92)
const LOOT_EDGE := Color8(84, 58, 18)
const GUN := Color8(206, 214, 222)
const PROP_TREE := Color8(96, 150, 66)
const PROP := Color8(176, 132, 82)
const PROP_EDGE := Color8(34, 24, 16)
const GLOW := Color8(255, 200, 96)
const START := Color8(251, 183, 98)
const ATTACK := Color8(110, 150, 226)
const DEFEND := Color8(226, 92, 70)
const SITE := Color8(236, 168, 84)
const HOSTAGE := Color8(236, 226, 196)
const WHITE := Color8(250, 240, 214)
const BLACK := Color8(22, 16, 12)

static var _swatches := {}


## The picture of tile `name` shrunk to px x px (box filtered), in `look`
## ("" as it is, "wall" lifted and edged, "inside" dimmed, "rise1".."rise3").
static func swatch(art: Assets, name: String, px: int, look := "", flip := 0) -> Image:
	var key := "%s|%d|%s|%d" % [name, px, look, flip]
	if _swatches.has(key):
		var kept: Image = _swatches[key]
		return kept
	var img := Image.create_empty(px, px, false, Image.FORMAT_RGB8)
	var index: int = art.tile_index.get(name, 0)
	var base := index * Assets.TILE_BYTES
	var ok := art.tiles.size() >= base + Assets.TILE_BYTES
	var step := float(Assets.TILE_W) / px
	var scale := 1.0
	match look:
		"wall":
			scale = WALL_LIFT
		"inside":
			scale = INSIDE_DIM
		"rise1":
			scale = 1.08
		"rise2":
			scale = 1.16
		"rise3":
			scale = 1.24
	for y in px:
		for x in px:
			var r := 0
			var g := 0
			var b := 0
			var n := 0
			if ok:
				var y0 := int(y * step)
				var y1 := maxi(y0 + 1, int((y + 1) * step))
				var x0 := int(x * step)
				var x1 := maxi(x0 + 1, int((x + 1) * step))
				# Two samples a pixel, not the whole block: the grain stays.
				for k in 2:
					var sx := x0 + (x1 - x0) * (1 + k * 2) / 4
					var sy := y0 + (y1 - y0) * (3 - k * 2) / 4
					var o := base + (sy * Assets.TILE_W + sx) * 3
					r += art.tiles[o]
					g += art.tiles[o + 1]
					b += art.tiles[o + 2]
					n += 1
			var c := Color8(r / maxi(1, n), g / maxi(1, n), b / maxi(1, n)) if n > 0 else PROP
			img.set_pixel(
				x, y, Color(minf(1.0, c.r * scale), minf(1.0, c.g * scale), minf(1.0, c.b * scale))
			)
	if flip & 1:
		img.flip_x()
	if flip & 2:
		img.flip_y()
	if look == "wall" and px >= 3:
		img.fill_rect(Rect2i(0, 0, px, 1), EDGE_LIGHT.darkened(.25))
		img.fill_rect(Rect2i(0, 0, 1, px), EDGE_LIGHT.darkened(.4))
		img.fill_rect(Rect2i(0, px - 1, px, 1), EDGE_DARK)
		img.fill_rect(Rect2i(px - 1, 0, 1, px), EDGE_DARK)
	_swatches[key] = img
	return img


## The whole map at px a cell.
static func image(art: Assets, map: Dictionary, px: int) -> Image:
	var w := UserMap.width(map)
	var h := UserMap.height(map)
	var img := Image.create_empty(w * px, h * px, false, Image.FORMAT_RGB8)
	for y in h:
		for x in w:
			paint_cell(art, img, map, x, y, px)
	return img


static func paint_cell(art: Assets, img: Image, map: Dictionary, x: int, y: int, px: int) -> void:
	var key := UserMap.at(map, x, y)
	var spec := UserMap.cell(key)
	var group := str(spec.get("group", ""))
	var at := Vector2i(x * px, y * px)
	var whole := Rect2i(0, 0, px, px)
	match group:
		"wall":
			img.blit_rect(swatch(art, str(spec["tile"]), px, "wall"), whole, at)
		"door":
			var way := UserMap.door_way(map, x, y)
			var beside := UserMap.at(map, x + 1, y) if way == 1 else UserMap.at(map, x, y + 1)
			var floor_spec := UserMap.cell(beside)
			var floor_look := "inside" if str(floor_spec.get("group", "")) == "inside" else ""
			img.blit_rect(
				swatch(art, str(floor_spec.get("tile", "dirt")), px, floor_look), whole, at
			)
			var t := maxi(1, px / 4)
			if way == 1:
				img.fill_rect(Rect2i(at.x + px / 2 - t, at.y, t * 2, px), DOOR_EDGE)
				img.fill_rect(
					Rect2i(at.x + px / 2 - t + 1, at.y + 1, maxi(1, t * 2 - 2), maxi(1, px - 2)),
					DOOR
				)
			elif way == 0:
				img.fill_rect(Rect2i(at.x, at.y + px / 2 - t, px, t * 2), DOOR_EDGE)
				img.fill_rect(
					Rect2i(at.x + 1, at.y + px / 2 - t + 1, maxi(1, px - 2), maxi(1, t * 2 - 2)),
					DOOR
				)
			else:
				img.fill_rect(Rect2i(at.x, at.y, px, px), BAD.darkened(.4))
				for i in px:
					img.set_pixel(at.x + i, at.y + i, BAD)
					img.set_pixel(at.x + px - 1 - i, at.y + i, BAD)
		"inside":
			img.blit_rect(swatch(art, str(spec["tile"]), px, "inside", _flip(x, y)), whole, at)
		"rise":
			var lift: float = spec.get("ground", 0.0)
			var level := clampi(roundi(lift / .24), 1, 3)
			img.blit_rect(swatch(art, str(spec["tile"]), px, "rise%d" % level), whole, at)
			# A dark lip where it drops to lower ground (south and east read
			# as the shadowed sides).
			for side: Vector2i in [
				Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)
			]:
				var g := UserMap.ground_of(map, x + side.x, y + side.y)
				if is_nan(g) or g >= lift - .01:
					continue
				var lip := SHADOW if side.x + side.y > 0 else EDGE_LIGHT.darkened(.3)
				if side.y == 1:
					img.fill_rect(Rect2i(at.x, at.y + px - 1, px, 1), lip)
				elif side.x == 1:
					img.fill_rect(Rect2i(at.x + px - 1, at.y, 1, px), lip)
				elif side.y == -1:
					img.fill_rect(Rect2i(at.x, at.y, px, 1), lip)
				else:
					img.fill_rect(Rect2i(at.x, at.y, 1, px), lip)
		_:
			img.blit_rect(
				swatch(art, str(spec.get("tile", "dirt")), px, "", _flip(x, y)), whole, at
			)
	# A wall drops a shadow on open ground south of it.
	if group != "wall" and UserMap.is_wall(UserMap.at(map, x, y - 1)) and px >= 4:
		var s := Rect2i(at.x, at.y, px, maxi(1, px / 5))
		img.fill_rect(s, SHADOW.lerp(img.get_pixelv(at + Vector2i(px / 2, px - 1)), .45))


## Which way a floor cell's picture is flipped, so a field of one tile does
## not read as a grid of stamps.
static func _flip(x: int, y: int) -> int:
	return (x * 7 + y * 13 + (x * y) % 3) % 4


## A thing's mark at (cx, cy) (its cell's middle), `size` pixels across.
static func icon(
	c: Canvas, kind: String, name: String, cx: int, cy: int, size: int, facing := 0
) -> void:
	var r := maxi(1, size / 2)
	var spec := UserMap.thing(kind, name)
	match kind:
		"hand":
			var face := WHITE if name == "cow" else HAND
			c.fill_rect(cx - r, cy - r + 1, r * 2, maxi(1, r * 2 - 2), HAND_EDGE)
			c.fill_rect(cx - r + 1, cy - r, maxi(1, r * 2 - 2), r * 2, HAND_EDGE)
			c.fill_rect(cx - r + 1, cy - r + 1, maxi(1, r * 2 - 2), maxi(1, r * 2 - 2), face)
			if size >= 7:
				c.fill_rect(cx - 1, cy - 1, 1, 1, BLACK)
				c.fill_rect(cx + 1, cy - 1, 1, 1, BLACK)
		"loot":
			var gun := ["shotgun", "rifle", "crossbow", "bottle_launcher"].has(name)
			c.fill_rect(cx - r, cy - r, r * 2, r * 2, LOOT_EDGE)
			c.fill_rect(
				cx - r + 1, cy - r + 1, maxi(1, r * 2 - 2), maxi(1, r * 2 - 2), GUN if gun else LOOT
			)
		"prop":
			var glow: float = spec.get("glow", 0.0)
			var tree := name in ["tree", "tree_b", "dead_snag"]
			var face := GLOW if glow > 0.0 else (PROP_TREE if tree else PROP)
			c.circle(cx, cy, r, PROP_EDGE)
			c.circle(cx, cy, maxi(0, r - 1), face)
		"erase":
			c.line(cx - r, cy - r, cx + r, cy + r, BAD, 2)
			c.line(cx + r, cy - r, cx - r, cy + r, BAD, 2)
		"mark":
			match name:
				"start":
					var tip := Vector2(cx, cy) + Vector2.from_angle(facing * PI / 4.0) * (r + 1)
					var back := Vector2.from_angle(facing * PI / 4.0 + PI)
					var side := Vector2.from_angle(facing * PI / 4.0 + PI / 2.0)
					var p1 := Vector2(cx, cy) + back * r + side * r
					var p2 := Vector2(cx, cy) + back * r - side * r
					c.polygon([tip, p1, p2], START)
					c.line(int(tip.x), int(tip.y), int(p1.x), int(p1.y), BLACK)
					c.line(int(tip.x), int(tip.y), int(p2.x), int(p2.y), BLACK)
				"lever":
					c.fill_rect(cx - r, cy + r - 1, r * 2, 2, BLACK)
					c.line(cx, cy + r - 1, cx + r - 1, cy - r, BLACK, 2)
					c.fill_rect(cx + r - 2, cy - r, 3, 3, DEFEND)
				"goal":
					for yy in 4:
						for xx in 4:
							var cell := maxi(1, size / 4)
							var ink := WHITE if (xx + yy) % 2 == 0 else BLACK
							c.fill_rect(cx - r + xx * cell, cy - r + yy * cell, cell, cell, ink)
				"attack", "defend":
					var ink := ATTACK if name == "attack" else DEFEND
					c.fill_rect(cx - r, cy - r, r * 2, r * 2, BLACK)
					c.fill_rect(cx - r + 1, cy - r + 1, maxi(1, r * 2 - 2), maxi(1, r * 2 - 2), ink)
					if size >= 8:
						HUD.text(
							c,
							"A" if name == "attack" else "D",
							cx,
							cy - 3,
							"mini",
							BLACK,
							true,
							false
						)
				"site_a", "site_b":
					c.rect_outline(cx - r - 1, cy - r - 1, r * 2 + 2, r * 2 + 2, SITE)
					c.fill_rect(
						cx - r + 1, cy - r + 1, maxi(1, r * 2 - 2), maxi(1, r * 2 - 2), Menu.RUST
					)
					if size >= 8:
						HUD.text(
							c,
							"A" if name == "site_a" else "B",
							cx,
							cy - 3,
							"mini",
							WHITE,
							true,
							false
						)
				"hostage":
					c.circle(cx, cy, r, BLACK)
					c.circle(cx, cy, maxi(0, r - 1), HOSTAGE)


## The picture `img`'s region `src` drawn at `dst` on a GPU canvas, through
## the texture kept in `holder` (made again only when the size changes).
static func blit(c: Canvas, img: Image, src: Rect2i, dst: Vector2i, holder: Dictionary) -> void:
	var region := src.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	if region.size.x <= 0 or region.size.y <= 0:
		return
	var key := "%s|%s|%s" % [region, img.get_size(), holder.get("version", 0)]
	var made: ImageTexture = holder.get("texture")
	if made == null or made.get_size() != Vector2(region.size):
		made = ImageTexture.create_from_image(img.get_region(region))
		holder["texture"] = made
		holder["key"] = key
	elif str(holder.get("key", "")) != key:
		made.update(img.get_region(region))
		holder["key"] = key
	c.gpu_texture(made, dst.x, dst.y, region.size.x, region.size.y)
