## COUNTY RUN's map picker (a map per row, the DAILY RUN switch, BACK):
## CountyScreens draws it, CountyInput reads its taps and keys.
class_name CountyMapsScreen
extends ZonedScreen


func draw_zoned(c: Canvas) -> void:
	CountyScreens.draw_maps(c, main.menu)


func hover_at(at: Vector2i) -> void:
	CountyInput.hover(main, at)


func tap_at(at: Vector2i) -> void:
	CountyInput.tap(main, at)
