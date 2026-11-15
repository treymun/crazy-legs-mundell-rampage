## The menus' Godot theme: the game's pixel letters as every control's font
## (body, 7 high; labels and line edits in the county's ink), no Godot focus
## or hover boxes (a screen paints its own lit row or plate, Menu's look), and
## the text fields' caret and selection in the HUD's amber. Set on UiRoot, so
## every screen and any control on one inherits it.
class_name UiTheme
extends RefCounted

static var _theme: Theme


static func get_theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = PixelFont.of("body")
	t.default_font_size = int(PixelType.STYLES["body"][1])
	var empty := StyleBoxEmpty.new()
	for kind: String in ["Button", "LineEdit", "Label", "Panel", "PanelContainer"]:
		for box: String in [
			"normal", "hover", "pressed", "focus", "disabled", "panel", "read_only"
		]:
			t.set_stylebox(box, kind, empty)
	for kind: String in ["Button", "Label", "LineEdit"]:
		t.set_color("font_color", kind, HUD.INK)
	t.set_color("font_hover_color", "Button", HUD.AMBER)
	t.set_color("font_focus_color", "Button", HUD.AMBER)
	t.set_color("font_pressed_color", "Button", HUD.AMBER)
	t.set_color("caret_color", "LineEdit", HUD.AMBER)
	t.set_color("selection_color", "LineEdit", Color(HUD.AMBER, .4))
	_theme = t
	return t
