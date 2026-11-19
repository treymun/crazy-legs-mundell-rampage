## Pictures of voice chat's marks in a real window (net/voice_chat.gd): the
## lobby (a talker, a muted player, the posse), the AUDIO page's VOICE CHAT
## rows, and a 5v5 match (ON THE AIR, who is talking, the mark over a
## talker's head, the scoreboard's marks). Nobody really talks: the voices
## are made up on the spot, the mic is never opened.
##
##   godot --path godot --audio-driver Dummy --resolution 1280x800 \
##       --script res://tools/voice_frames.gd -- out=<dir>
##
## Point APPDATA at a scratch folder: it runs the game with the profile there.
extends SceneTree

const NetPorts := preload("res://tools/net_ports.gd")

var main
var out := ""


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("out="):
			out = String(arg).substr(4)
	if out == "":
		push_error("out=<dir> is needed")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out)
	main = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.touring = true
	var net: NetPlay = NetPlay.host_lobby(
		NetPorts.pick("voice_frames"),
		"MUNDELL",
		{"lobby_name": "MUNDELL'S LOBBY"},
		false,
		"127.0.0.1"
	)
	net.make_match = func(info: Dictionary) -> Game: return main.net_match_game(info)
	main.net = net
	net.set_setting("team_size", 2)
	net.set_setting("bots", false)
	net.players.append({"id": 101, "name": "BUBBA", "team": 0, "ready": true})
	net.players.append({"id": 102, "name": "LURLEEN", "team": 1, "ready": false})
	net.players.append({"id": 103, "name": "CLETUS", "team": 1, "ready": true})
	net.voice.muted[103] = true
	main.voice_chat = VoiceChat.new()
	main.add_child(main.voice_chat)
	main.voice_chat.mic_state = "on"
	net.voice.mic = "off"
	main.state = "lobby"
	_talk(net, [101, NetSession.HOST_ID])
	await _snap("voice_lobby")
	net.set_setting("mode", "coop")
	net.set_setting("map", "hickston")
	_talk(net, [101])
	await _snap("voice_posse")
	net.set_setting("mode", "bomb")
	net.set_setting("map", "grainyard")
	net.set_setting("team_size", 2)
	# The AUDIO page at its VOICE CHAT rows.
	main.state = "setup"
	var pages := SessionStore.setup_pages()
	for p in pages.size():
		if String(pages[p][0]) == "AUDIO":
			main.option_page = p
			main.option_scroll = 0
			var rows: Array = pages[p][1]
			for s in rows.size():
				if (rows[s] as SessionStore.Setting).key == "voice_talk":
					main.setup_select(s)
	await _snap("voice_setup")
	# A match: BUBBA talking a few steps ahead, ourselves on the air.
	main.state = "lobby"
	for p: Dictionary in net.players:
		p["ready"] = true
	var why: String = net.start_match()
	if why != "":
		push_error("no match: " + why)
	for change: Dictionary in net.take_changes():
		if change.has("started"):
			main.net_begin_match()
	var g: Game = main.game
	if g != null:
		for i in 400:
			net.host_tick({})
		var me: Player = g.local_player
		var bubba: Player = g.players[int(net.player_of(101)["slot"])]
		bubba.x = me.x + cos(me.angle) * 4.0 + sin(me.angle) * .6
		bubba.y = me.y + sin(me.angle) * 4.0 - cos(me.angle) * .6
		bubba.angle = me.angle + PI
		await _snap("voice_match")  # (the first frame of a match is slow to draw)
		_talk(net, [101, 102, NetSession.HOST_ID])
		await _snap("voice_match")
		Input.parse_input_event(_tab(true))
		await process_frame
		_talk(net, [101, NetSession.HOST_ID])
		await _snap("voice_board")
		Input.parse_input_event(_tab(false))
	print("voice frames written to ", out)
	main.voice_chat.stop()
	net.finish()
	main.net = null
	main.queue_free()
	await process_frame
	quit()


func _tab(down: bool) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = KEY_TAB
	e.physical_keycode = KEY_TAB
	e.pressed = down
	return e


## Made-up voices for `ids` (the host's own: on the air) heard just now.
func _talk(net: NetPlay, ids: Array) -> void:
	var now := Time.get_ticks_usec() / 1000.0
	for id: int in ids:
		if id == net.my_id:
			net.voice.sent_at = now
			continue
		var t := NetVoice.Talker.new()
		t.id = id
		t.heard_at = now
		net.voice.talkers[id] = t
	VoiceChat.marks.clear()
	for p: Dictionary in net.players:
		var slot: int = p.get("slot", -1)
		var id: int = p["id"]
		if slot >= 0 and net.voice.muted.has(id):
			VoiceChat.marks[slot] = 2
		elif slot >= 0 and net.voice.talking(id, net.my_id, now):
			VoiceChat.marks[slot] = 1


func _snap(name: String) -> void:
	main.render()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))
