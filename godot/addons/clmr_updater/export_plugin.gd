## Puts the updater's AAR (bin/clmr_updater.aar, built from java/ by
## tools/android_plugin.gd) into an Android Gradle export: the plugin class
## the game calls (src/apk_installer.gd) and its manifest part, the
## REQUEST_INSTALL_PACKAGES leave. An Android export without the AAR fails
## loudly rather than ship an APK that cannot update itself.
@tool
extends EditorExportPlugin

## Relative to res://addons/ (EditorExportPlugin._get_android_libraries).
const AAR := "clmr_updater/bin/clmr_updater.aar"


func _get_name() -> String:
	return "CrazyLegsUpdater"


func _supports_platform(platform: EditorExportPlatform) -> bool:
	return platform is EditorExportPlatformAndroid


func _get_android_libraries(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
	if not FileAccess.file_exists("res://addons/" + AAR):
		push_error(
			(
				"The Android updater is not built: run tools/android_plugin.gd"
				+ " (after --install-android-build-template) before exporting."
			)
		)
		return PackedStringArray()
	return PackedStringArray([AAR])


func _export_begin(
	features: PackedStringArray, _is_debug: bool, _path: String, _flags: int
) -> void:
	if features.has("android") and not FileAccess.file_exists("res://addons/" + AAR):
		push_error("Android export failed: the updater AAR (addons/%s) is missing." % AAR)
