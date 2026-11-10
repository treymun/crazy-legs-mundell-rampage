## Load every asset bank and report what is available, so a broken/absent blob
## shows up as a count instead of silence at runtime.
##
##   Godot --headless --path <project> --script res://tools/verify_assets.gd
extends SceneTree


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var assets := Assets.new()
	print("tiles      ", assets.tiles.size() / (128 * 128 * 3), " tiles")
	print("palette    ", assets.palette.size(), " bytes")
	print("grain      ", assets.grain.size(), " bytes")
	print("art        ", assets.art_index.size(), " images")
	print("music      ", assets.music_index.size(), " tracks")
	print("jingles    ", assets.stream_index.size(), " streams")
	print("sky        ", assets.sky_index.size(), " panoramas")
	print("sfx        ", assets.sfx_index.size(), " cues at ", assets.sfx_rate, " Hz")
	print("levels     ", Campaign.ORDER.size(), " -> ", " ".join(PackedStringArray(Campaign.ORDER)))
	var missing := []
	for cue in ["revolver", "shotgun", "step_wood_0", "actor_shell_pain"]:
		if not assets.has_cue(cue):
			missing.append(cue)
	print("has_cue    ", "ok" if missing.is_empty() else "MISSING " + str(missing))
	var wav := assets.cue("revolver")
	print("pcm decode ", "ok %.3f s" % wav.get_length() if wav != null else "FAILED")
	var ogg := assets.track("music")
	print("ogg decode ", "ok %.2f s" % ogg.get_length() if ogg != null else "FAILED")
	var jingle := assets.jingle("title")
	print("jingle     ", "ok %.2f s" % jingle.get_length() if jingle != null else "FAILED")
	for id: String in Campaign.ORDER:
		var level := LevelData.load_level(id, assets)
		if level == null:
			print("level ", id, " FAILED")
			continue
		print(
			(
				(
					"level %-8s walls=%d doors=%d enemies=%d props=%d scenery=%d "
					+ "stations=%d billboards=%d notes=%d"
				)
				% [
					id,
					level.wall_count,
					level.doors.size(),
					level.enemies.size(),
					level.props.size(),
					level.scenery.size(),
					level.stations.size(),
					level.billboards.size(),
					level.interior_art.size()
				]
			)
		)
	quit()
