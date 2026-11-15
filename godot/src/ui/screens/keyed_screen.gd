## A screen whose rules stay with the front end's handlers for its state:
## SETUP (pages of settings with bars that slide under a finger, a groove,
## key binding, the display trial) and SAVE SLOTS (naming a save). It draws
## the screen (render_setup, render_slots); keys, the pointer and touch take
## main_input.gd's paths for the state.
class_name KeyedScreen
extends UiScreen


func _init() -> void:
	super._init()
	keys_own = false
	pointer_own = false


func render(_c: Canvas) -> void:
	if main.state == "setup":
		main.render_setup()
	elif main.state == "slots":
		main.render_slots()
