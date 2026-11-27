## Moved out of main_state.gd to keep it under the line limit; the originals call these.
class_name LaunchArgs
extends RefCounted


static func parse_smoke(m: MainState) -> void:
	for arg in OS.get_cmdline_user_args():
		var text := String(arg)
		if text.begins_with("--smoke-frames="):
			m.smoke_frames = int(text.substr(15))
		elif text.begins_with("--smoke-marker="):
			m.smoke_marker = text.substr(15)
		elif text.begins_with("--smoke-level="):
			m.smoke_level = text.substr(14)
		elif text.begins_with("--smoke-shot="):
			m.smoke_shot = text.substr(13)
		elif text.begins_with("--view-shot="):
			m.view_shot = text.substr(12)
		elif text == "--cpu-look":
			m.cpu_look = true
		elif text == "--cpu-canvas":
			m.cpu_canvas = true
		elif text == "--launch-check":
			m.launch_check = true
		elif text.begins_with("--view-tour="):
			m.view_tour = text.substr(12)
		elif text.begins_with("--opener="):
			m.opener.forced = text.substr(9)  # a chapter's opener, whatever the setting
		elif text.begins_with("--opener-data="):
			ChapterOpener.data_path = text.substr(14)  # a draft of openers.json
		elif text.begins_with("--opener-out="):
			m.opener.shots_out = text.substr(13)  # its key frames saved, then quit
		elif text.begins_with("--opener-strip="):
			m.opener.strip = int(text.substr(15))  # (with --opener-out) evenly spaced frames
		elif text.begins_with("--view-out="):
			m.view_out = text.substr(11)
		elif text.begins_with("--view-bench="):
			m.view_bench = int(text.substr(13))
		elif text.begins_with("--play-bench="):
			m.play_bench = int(text.substr(13))
			m.view_bench = -1
		elif text == "--demo":
			m.demo = true
		elif text == "--showcase":
			m.showcase = true
		elif text.begins_with("--showcase="):
			m.showcase = true
			m.showcase_only = int(text.substr(11))
		elif text.begins_with("--dev="):
			m.dev_commands = text.substr(6)
		elif text == "--rematch-all":
			# Every boss on the rematch board (from the project folder only).
			BossRematch.unlock_all = DevConsole.available()
		elif text.begins_with("--replay="):
			# A replay (src/replay.gd) played in the game's view: a path, or a
			# name in user://replays.
			m.replay_file = text.substr(9)
		elif text.begins_with("--play-at="):
			m.play_at = text.substr(10)
		elif text == "--server":
			m.server_level = "hickston"
		elif text.begins_with("--server="):
			m.server_level = text.substr(9)
		elif text.begins_with("--server-players="):
			m.server_players = clampi(int(text.substr(17)), 1, 16)
		elif text.begins_with("--server-ticks="):
			m.server_ticks = int(text.substr(15))
		elif text.begins_with("--server-report="):
			m.server_report = maxf(.5, float(text.substr(16)))
		elif text.begins_with("--lobby-server="):
			m.lobby_server = text.substr(15)
		elif text.begins_with("--server-difficulty="):
			m.server_difficulty = clampi(int(text.substr(20)), 0, 3)
		elif text == "--mode=tagteam":
			m.mode_name = Modes.BOMB
			m.tag_team_arg = true
		elif text.begins_with("--mode="):
			m.mode_name = text.substr(7) if Modes.NAMES.has(text.substr(7)) else ""
		elif text.begins_with("--players="):
			m.mode_players = clampi(int(text.substr(10)), 1, Modes.MAX_PLAYERS)
		elif text.begins_with("--arena="):
			m.mode_options["arena"] = text.substr(8)
		elif text.begins_with("--frag-limit="):
			m.mode_options["frag_limit"] = maxi(1, int(text.substr(13)))
		elif text.begins_with("--time-limit="):
			m.mode_options["time_limit"] = maxf(10.0, float(text.substr(13)))
		elif text.begins_with("--rules="):
			m.mode_options["store_rules"] = text.substr(8)
		elif text.begins_with("--rounds="):
			m.mode_options["rounds"] = clampi(int(text.substr(9)), 1, 16)
		elif text.begins_with("--level="):
			m.mode_level = text.substr(8)
		elif text == "--host-online" or text.begins_with("--host-online="):
			m.online_args["host"] = int(text.substr(14)) if text.length() > 14 else NetSession.PORT
		elif text.begins_with("--join-online="):
			m.online_args["join"] = text.substr(14)
		elif text.begins_with("--online-name="):
			m.online_args["name"] = text.substr(14)
		elif text.begins_with("--online-password="):
			m.online_args["password"] = text.substr(18)
		elif text.begins_with("--online-start="):
			m.online_args["start"] = int(text.substr(15))
		elif text.begins_with("--online-map="):
			m.online_args["map"] = text.substr(13)
		elif text == "--online-bot":
			m.online_args["bot"] = true
		elif text.begins_with("--party-line="):
			# Another party line than servers.json's (a lobby server on this PC).
			var at := NetPlay.parse_address(text.substr(13))
			if not at.is_empty():
				RelayLink.server = {"host": at["host"], "port": at["port"]}
		elif text.begins_with("--smoke-screen="):
			# A front-end screen instead of a level: title, setup, controls,
			# credits, replays or slots; "setup:3" opens the fourth settings page
			# ("setup:3:9" picks its tenth row), "title:4" the fifth title entry.
			m.smoke_screen = text.substr(15)
	if Modes.TACTICAL.has(m.mode_name):
		# A 5v5 mode: five a side unless --players says, on a 5v5 map; on a
		# TAG TEAM map (or --tag-team) two a side by its rules.
		var arena := str(m.mode_options.get("arena", ""))
		if m.tag_team_arg or Modes.TAGTEAM_MAPS.has(arena):
			m.mode_name = Modes.BOMB
			if not Modes.TAGTEAM_MAPS.has(arena):
				m.mode_options["arena"] = Modes.TAGTEAM_MAPS[0]
			for key: String in Modes.TAGTEAM_OPTIONS:
				if not m.mode_options.has(key):
					m.mode_options[key] = Modes.TAGTEAM_OPTIONS[key]
			if m.mode_players < 2:
				m.mode_players = Modes.TAGTEAM_PLAYERS
		if m.mode_players < 2:
			m.mode_players = Modes.MAX_PLAYERS
		if not (
			Modes.SHOWDOWN_MAPS.has(str(m.mode_options.get("arena", "")))
			or Modes.TAGTEAM_MAPS.has(str(m.mode_options.get("arena", "")))
			or _has_teams(str(m.mode_options.get("arena", "")))
		):
			m.mode_options["arena"] = Modes.SHOWDOWN_MAPS[0]
	m.smoke = m.smoke_frames > 0
	m.focused = true


## Whether a built level (data/<id>.json, a map source's build) has the 5v5
## starts, so --mode=bomb --arena=<id> plays a new map before it is listed in
## Modes.SHOWDOWN_MAPS (pass 16, T7: a map maker's test run).
static func _has_teams(level_id: String) -> bool:
	if level_id == "" or not level_id.is_valid_ascii_identifier():
		return false
	var path := "res://data/%s.json" % level_id
	return (
		FileAccess.file_exists(path)
		and FileAccess.get_file_as_string(path).contains('"attack_spawns"')
	)
