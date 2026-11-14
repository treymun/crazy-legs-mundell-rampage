## The automap's key (game_view.gd automap): what each mark on it means, in a
## small box in its lower left corner, in the map's own colours.
class_name MapKey
extends RefCounted

## [colour, words] for each row.
const ROWS := [
	[Color8(255, 170, 80), "YOU"],
	[Color8(236, 168, 84), "GOAL"],
	[Color8(110, 136, 90), "DOOR, OPEN"],
	[Color8(176, 132, 82), "DOOR, SHUT"],
	[Color8(222, 128, 52), "DOOR, LOCKED"],
	[Color8(214, 178, 118), "WALL / EDGE OF A DECK"],
]


static func draw(c: Canvas, x: int, y: int) -> void:
	var h := ROWS.size() * 7 + 4
	c.fill_rect(x, y - h, 96, h, Color8(22, 17, 13))
	c.rect_outline(x, y - h, 96, h, Color8(84, 64, 45))
	for k in ROWS.size():
		var row: Array = ROWS[k]
		var ry := y - h + 3 + k * 7
		c.fill_rect(x + 3, ry, 4, 4, row[0])
		HUD.text(c, String(row[1]), x + 10, ry, "mini", HUD.INK, false, false)
