## The guard for tools that write the game's profile (user://: the campaign
## entry, the unlocks, the quicksave, replays, road notes, their own scratch
## saves): they run only in a scratch profile, never a player's. check_all
## gives every row its own (APPDATA, LOCALAPPDATA and the XDG folders pointed
## at a folder of its own, and CLMR_SCRATCH_PROFILE naming that folder). A
## run by hand needs APPDATA (and LOCALAPPDATA) pointed at a folder under the
## system's TEMP, or CLMR_SCRATCH_PROFILE naming the folder APPDATA points at
## (tools/balance_runs.sh sets it). Anywhere else the tool refuses before it
## writes anything (Godot's own log under user://logs aside).
##
##   const ScratchProfile := preload("res://tools/scratch_profile.gd")
##   func _init() -> void:
##       if ScratchProfile.refuse(self, "ROAD CHECK"):
##           return
extends RefCounted

const MARKER := "CLMR_SCRATCH_PROFILE"


## Whether user:// is a scratch profile: under the folder check_all (or the
## caller) named, or under the system's TEMP.
static func scratch() -> bool:
	var user := _norm(OS.get_user_data_dir())
	var marked := OS.get_environment(MARKER)
	if marked != "" and user.begins_with(_norm(marked)):
		return true
	for key: String in ["TEMP", "TMP", "TMPDIR"]:
		var temp := OS.get_environment(key)
		if temp != "" and user.begins_with(_norm(temp)):
			return true
	return false


## Call first, in _init: true (a line said, the tool quitting with 2) when
## user:// is not a scratch profile.
static func refuse(tree: SceneTree, name: String) -> bool:
	if scratch():
		return false
	print(
		(
			"%s: run through check_all or with a scratch APPDATA (user:// is %s). Nothing written."
			% [name, OS.get_user_data_dir()]
		)
	)
	tree.quit(2)
	return true


static func _norm(path: String) -> String:
	var out := path.replace("\\", "/").simplify_path()
	if OS.get_name() == "Windows":
		out = out.to_lower()
	return out.trim_suffix("/") + "/"
