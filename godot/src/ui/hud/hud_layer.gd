## The play HUD as Control nodes, the size of the picture (320x200; WIDE
## wider), in the
## overlay viewport the display shader lays over the 3D view, under the
## canvas's own drawing (the notices, the 5v5 store and COUNTY RUN's cards go
## over it as they went over the old bar) and under the menu screens (UiRoot).
##
## - `bar` (StatusBar) stands at the foot (0, 156), 320x44: the bare plate of
##   the mode (campaign, 5v5, COUNTY RUN) under one box per part of the bar
##   (BOXES: the ammo rail, health, ammo, keys or vest, the face, the gauges
##   or the 5v5 side or COUNTY RUN's gun slots, the pocket). Each box shows
##   its own rectangle of the bar as HUD draws it (bar_texture(), in software,
##   only when something on it changes), so the picture is the old one pixel
##   for pixel; HUD MINIMAL hides the rail, the face and the campaign's meters,
##   and the plate shows through.
## - `pin` (HudPin) is the objective pin, repainted every frame.
## - ASPECT WIDE (fit()): the layer is the picture's width; the bar's left
##   part (the rail, health, ammo, keys, the face) keeps the left edge, its
##   right part (the gauges, the pocket) the right, and the plate's wood and
##   rail between them is a stretch of its own planks (FILL) laid end to end.
##
## The overlay is scaled to the window by the display shader with whole,
## crisp pixels, so the HUD scales as the picture does, on a phone (inside its
## safe area) as on a big screen. Headless runs have no overlay and draw the
## HUD in software on the canvas, as before (hud.gd draw()).
class_name HudLayer
extends Control

## Each part of the status bar: its rectangle in the bar's 320x44. The
## gauges' column is the bar's whole height (COUNTY RUN's gun slots reach up
## into the rail's rows), so the rail is two pieces either side of it.
const BOXES := {
	"rail": Rect2i(0, 0, 171, 9),
	"rail_end": Rect2i(272, 0, 48, 9),
	"health": Rect2i(0, 9, 53, 35),
	"ammo": Rect2i(53, 9, 48, 35),
	"third": Rect2i(101, 9, 27, 35),
	"face": Rect2i(128, 9, 43, 35),
	"gauges": Rect2i(171, 0, 101, 44),
	"pocket": Rect2i(272, 9, 48, 35),
}
## ASPECT WIDE: where the bar parts at the left edge end, and the plate's
## columns laid end to end between the parts (plain planks, one of the
## rail's sections).
const SPLIT := 171
const FILL := Vector2i(183, 228)

var hud: HUD
var bar: Control
var plate: TextureRect
## ASPECT WIDE: the plate's right part and the planks between (hidden at 320).
var plate_right: TextureRect
var filler: TextureRect
var _filled_for: Texture2D = null
var boxes: Dictionary = {}
var pin: HudPin
## The game shown this frame (null: no HUD this frame).
var game: Game


func _init(p_hud: HUD) -> void:
	hud = p_hud
	name = "HudLayer"
	size = Vector2(320, 200)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bar = Control.new()
	bar.name = "StatusBar"
	bar.position = Vector2(0, View.VIEW)
	bar.size = Vector2(320, 200 - View.VIEW)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)
	plate = TextureRect.new()
	plate.name = "Plate"
	plate.size = bar.size
	_flat(plate)
	bar.add_child(plate)
	plate_right = TextureRect.new()
	plate_right.name = "PlateRight"
	plate_right.texture = AtlasTexture.new()
	_flat(plate_right)
	plate_right.visible = false
	bar.add_child(plate_right)
	filler = TextureRect.new()
	filler.name = "Planks"
	_flat(filler)
	filler.visible = false
	bar.add_child(filler)
	for part: String in BOXES:
		var r: Rect2i = BOXES[part]
		var box := TextureRect.new()
		box.name = part.capitalize()
		box.position = r.position
		box.size = r.size
		var region := AtlasTexture.new()
		region.region = Rect2(r)
		box.texture = region
		_flat(box)
		bar.add_child(box)
		boxes[part] = box
	pin = HudPin.new()
	pin.hud = hud
	pin.size = size
	add_child(pin)
	visible = false


static func _flat(rect: TextureRect) -> void:
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


## Show this frame's HUD: what HUD.draw() noted (`hud.shown_game`), or none.
func show_frame() -> void:
	show_for(hud.shown_game, hud.shown_armory)


func show_for(shown: Game, armory: Weapons.Armory) -> void:
	game = shown
	visible = shown != null and armory != null
	pin.game = shown if visible else null
	if not visible:
		return
	var drawn := hud.bar_texture(shown, armory)
	var plate_tex := hud.plate_texture(shown)
	if View.shift > 0:
		_wide_plate(plate_tex)
	else:
		plate.texture = plate_tex
	for part: String in boxes:
		var box: TextureRect = boxes[part]
		(box.texture as AtlasTexture).atlas = drawn
		box.visible = not (hud.minimal and part in hidden_when_minimal(shown))
	pin.visible = shown.hints and not shown.map and not hud.minimal


## The layer as wide as the picture (View.cols): the bar's parts at its edges.
func fit() -> void:
	var cols := View.cols
	size = Vector2(cols, 200)
	pin.size = Vector2(320, 200)
	pin.position.x = View.shift
	bar.size = Vector2(cols, 200 - View.VIEW)
	var wide := cols > 320
	var across := 2 * View.shift
	for part: String in boxes:
		var r: Rect2i = BOXES[part]
		var box: TextureRect = boxes[part]
		box.position.x = r.position.x + (across if r.position.x >= SPLIT else 0)
	plate_right.visible = wide
	filler.visible = wide
	if wide:
		plate.size = Vector2(SPLIT, bar.size.y)
		plate_right.position.x = SPLIT + across
		plate_right.size = Vector2(320 - SPLIT, bar.size.y)
		filler.position.x = SPLIT
		filler.size = Vector2(across, bar.size.y)
		_filled_for = null
	else:
		plate.size = Vector2(320, bar.size.y)


## ASPECT WIDE: the plate in its two parts and the planks laid between them.
func _wide_plate(whole: ImageTexture) -> void:
	if _filled_for == whole:
		return
	_filled_for = whole
	var left := AtlasTexture.new()
	left.atlas = whole
	left.region = Rect2(0, 0, SPLIT, whole.get_height())
	plate.texture = left
	var right := plate_right.texture as AtlasTexture
	right.atlas = whole
	right.region = Rect2(SPLIT, 0, whole.get_width() - SPLIT, whole.get_height())
	var image := whole.get_image()
	var span := FILL.y - FILL.x
	var across := maxi(1, int(filler.size.x))
	var planks := Image.create_empty(across, image.get_height(), false, image.get_format())
	for x in range(0, across, span):
		planks.blit_rect(
			image, Rect2i(FILL.x, 0, mini(span, across - x), image.get_height()), Vector2i(x, 0)
		)
	filler.texture = ImageTexture.create_from_image(planks)


## The boxes HUD MINIMAL leaves off: the rail and the face, and the gut and
## drunk meters in the campaign (the 5v5 side and COUNTY RUN's gun slots stay).
static func hidden_when_minimal(shown: Game) -> Array[String]:
	var out: Array[String] = ["rail", "rail_end", "face"]
	if CountyMode.run(shown) == null and not Modes.is_tactical(shown):
		out.append("gauges")
	return out


## The bar as shown here, composed from its boxes over the plate (what the
## overlay draws), as RGB8 rows: for the checks against HUD's own drawing.
func composed() -> Image:
	var under := hud.plate_image(game)
	var out := Image.create_empty(under.get_width(), under.get_height(), false, Image.FORMAT_RGB8)
	out.blit_rect(under, Rect2i(Vector2i.ZERO, under.get_size()), Vector2i.ZERO)
	for part: String in boxes:
		var box: TextureRect = boxes[part]
		if not box.visible:
			continue
		var region := box.texture as AtlasTexture
		var at: Rect2i = BOXES[part]
		out.blit_rect(hud.bar_rows, Rect2i(region.region), at.position)
	return out
