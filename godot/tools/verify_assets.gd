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
	# Each chapter's fight loop opens, from that chapter's own music file.
	for bank: String in Sound.FIGHTS:
		var stem: String = Sound.FIGHTS[bank]
		var ogg := assets.track(stem)
		var home := String(assets.music_index.get(stem, {}).get("file", ""))
		var chapter := String(assets.music_index.get(Sound.SCORES[bank][0], {}).get("file", ""))
		if ogg == null or ogg.get_length() < 20.0 or home != chapter:
			print("fight loop ", stem, " FAILED (", home, ")")
			failed = true
		else:
			print("fight loop %-18s %.2f s, in %s" % [stem, ogg.get_length(), home])
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
	# A browser build waits only for its own chapter's pack (main_flow.gd play()):
	# every enemy a level has must be drawn from art.bin or that chapter's file.
	for id: String in Campaign.ORDER:
		var data := LevelEdit.read(id)
		var kinds := {}
		for spec: Dictionary in data.get("enemies", []):
			kinds[String(spec["kind"])] = true
		for kind: String in kinds:
			for name: String in assets.art_index:
				if not name.begins_with(kind + "_"):
					continue
				var home := String(assets.art_index[name].get("file", ""))
				if home != "" and home != String(Assets.CHAPTER_ART.get(id, "")):
					print("art ", name, " is in ", home, " but ", id, " needs it")
					failed = true
	print("ASSETS OK" if not failed else "ASSETS FAILED")
	quit(1 if failed else 0)
