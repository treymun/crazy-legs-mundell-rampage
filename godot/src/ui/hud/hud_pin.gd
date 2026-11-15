## The objective pin as a Control of the HUD (HudLayer): the tin arrow and
## its plate of steps, painted every frame by HUD.objective_pin() at the
## same place and in the same pixels as on the canvas, under whatever notice,
## place name or boss bar is up (game.pin_top).
class_name HudPin
extends Painted

var hud: HUD
var game: Game


func _init() -> void:
	name = "ObjectivePin"
	animated = true


func paint(c: Canvas) -> void:
	if game != null and hud != null:
		hud.objective_pin(c, game, game.pin_top)
