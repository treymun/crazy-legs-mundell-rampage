## The Android updater plugin as the game sees it (addons/clmr_updater: the
## Java CrazyLegsUpdater in the Gradle-built APK): the download folder,
## whether Android lets this app open the package installer, the setting
## that allows it, and handing it the checked APK. Only the system's own
## Update prompt installs anything; the player confirms it. A check hands
## in a stand-in with the same methods and signals.
class_name ApkInstaller
extends RefCounted

## The app came back to the front (from the setting or the installer).
signal resumed
## The installer's answer: -1 done (rarely seen: Android stops the app to
## update it), 0 the player said no, anything else it failed.
signal answered(code: int)

const SINGLETON := "CrazyLegsUpdater"
const DONE := -1
const DECLINED := 0

var plugin: Object = null


func _init(p_plugin: Object) -> void:
	plugin = p_plugin
	if plugin.has_signal("resumed"):
		plugin.connect("resumed", func() -> void: resumed.emit())
	if plugin.has_signal("install_result"):
		plugin.connect("install_result", func(code: int) -> void: answered.emit(code))


## The phone's updater, or null (not Android, or an APK built without it).
static func android() -> ApkInstaller:
	if not OS.has_feature("android") or not Engine.has_singleton(SINGLETON):
		return null
	return ApkInstaller.new(Engine.get_singleton(SINGLETON))


## The absolute folder downloads go to ("" when there is none).
func download_dir() -> String:
	var dir: String = plugin.call("downloadDir")
	return dir


func can_install() -> bool:
	var ok: bool = plugin.call("canInstall")
	return ok


## Open the system's "install unknown apps" setting for this game.
func open_settings() -> bool:
	var ok: bool = plugin.call("openInstallSettings")
	return ok


## Hand the APK to the installer: "" once it opens, else what went wrong.
func install(apk: String) -> String:
	var why: String = plugin.call("install", apk)
	return why
