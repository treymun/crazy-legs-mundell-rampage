## The Android updater in the export (export_plugin.gd). Editor only;
## exports leave addons/ out of the game's files.
@tool
extends EditorPlugin

const UpdaterExport := preload("res://addons/clmr_updater/export_plugin.gd")

var export_plugin: EditorExportPlugin


func _enter_tree() -> void:
	export_plugin = UpdaterExport.new()
	add_export_plugin(export_plugin)


func _exit_tree() -> void:
	if export_plugin != null:
		remove_export_plugin(export_plugin)
		export_plugin = null
