## Load every asset bank and report what is available, so a broken/absent blob
## shows up as a count instead of silence at runtime.
##
##   Godot --headless --path <project> --script res://tools/verify_assets.gd
extends SceneTree


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var assets := Assets.new()
	var failed := false
	print("tiles      ", assets.tiles.size() / (128 * 128 * 3), " tiles")
	print("palette    ", assets.palette.size(), " bytes")
	print("grain      ", assets.grain.size(), " bytes")
	print("art        ", assets.art_index.size(), " images")
	print("music      ", assets.music_index.size(), " tracks")
	print("sky        ", assets.sky_index.size(), " panoramas")
	print("sfx        ", assets.sfx_index.size(), " cues at ", assets.sfx_rate, " Hz")
	print("levels     ", Campaign.ORDER.size(), " -> ", " ".join(PackedStringArray(Campaign.ORDER)))
	var missing := []
	for cue in ["revolver", "shotgun", "step_wood_0", "actor_shell_pain"]:
		if not assets.has_cue(cue):
			missing.append(cue)
	print("has_cue    ", "ok" if missing.is_empty() else "MISSING " + str(missing))
	failed = failed or not missing.is_empty()
	# Every cue in the bank decodes to something audible, and every chapter
	# track opens and has a cut-off point inside its own length.
	var seconds := 0.0
	for cue: String in assets.sfx_index:
		var wav := assets.cue(cue)
		if wav == null or wav.get_length() <= 0.0:
			print("cue ", cue, " FAILED")
			failed = true
		else:
			seconds += wav.get_length()
	print("pcm decode ", "%d cues, %.1f s" % [assets.sfx_index.size(), seconds])
	for bank: String in Sound.SCORES:
		for stem: String in Sound.SCORES[bank]:
			var ogg := assets.track(stem)
			var cut := float(assets.music_ends.get(stem, 0.0))
			if ogg == null or cut <= 0.0 or cut > ogg.get_length():
				print("track ", stem, " FAILED (cut-off ", cut, ")")
				failed = true
			else:
				print("track      %-22s %.2f s, ends %.2f" % [stem, ogg.get_length(), cut])
	for stem: String in ["title", "victory"]:
		var jingle := assets.jingle(stem)
		print("%-10s " % stem, "ok %.2f s" % jingle.get_length() if jingle != null else "FAILED")
		if jingle == null:
			failed = true
	for id: String in Campaign.ORDER:
		var level := LevelData.load_level(id, assets)
		if level == null:
			print("level ", id, " FAILED")
			failed = true
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
	print("ASSETS OK" if not failed else "ASSETS FAILED")
	quit(1 if failed else 0)
