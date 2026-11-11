## The Godot editor's "Levels" screen (level_panel.gd): a level's map to paint
## on, beside 2D, 3D and Script. Editor only; exports leave addons/ out.
@tool
extends EditorPlugin

const LevelPanel := preload("res://addons/clmr_levels/level_panel.gd")

var panel: Control


func _enter_tree() -> void:
	panel = LevelPanel.new()
	panel.plugin = self
	panel.visible = false
	EditorInterface.get_editor_main_screen().add_child(panel)


func _exit_tree() -> void:
	if panel != null:
		panel.queue_free()
		panel = null


func _has_main_screen() -> bool:
	return true


func _make_visible(visible: bool) -> void:
	if panel != null:
		panel.visible = visible
		if visible:
			panel.open()


func _get_plugin_name() -> String:
	return "Levels"


func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon("GridMap", "EditorIcons")
