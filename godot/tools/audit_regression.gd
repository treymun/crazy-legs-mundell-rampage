## Save replacement, weapon credit, and browser chapter loading regressions.
extends SceneTree

const Server := preload("res://tools/update_server.gd")
const ScratchProfile := preload("res://tools/scratch_profile.gd")

var failures: Array[String] = []


func _init() -> void:
	if not ScratchProfile.refuse(self, "AUDIT REGRESSION"):
		_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	print("  ok   " if ok else "  FAIL ", message)
	if not ok:
		failures.append(message)


func _run() -> void:
	var main: Control = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	main.set_process(false)
	_save_replacement()
	_stats(main)
	_waiting(main)
	await _packs()
	await _pack_http()
	main.queue_free()
	await process_frame
	print("AUDIT REGRESSION OK" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	quit(int(not failures.is_empty()))


func _save_replacement() -> void:
	var path := ProjectSettings.globalize_path("user://audit-save.json")
	var backup := path + SessionStore.BACKUP_SUFFIX
	_check(SessionStore.write_document(path, {"value": 1}), "first save writes")
	_check(
		(
			SessionStore.write_document(path, {"value": 2})
			and FileAccess.get_file_as_string(path) == JSON.stringify({"value": 2})
		),
		"overwriting a save commits the new contents"
	)
	_check(
		(
			not SessionStore._replace_staged(path + ".missing", path, true)
			and FileAccess.get_file_as_string(path) == JSON.stringify({"value": 2})
		),
		"a failed Windows replacement rolls back without losing a save"
	)
	DirAccess.rename_absolute(path, backup)
	_check(
		SessionStore.readable_path(path) == backup,
		"an interrupted Windows replacement can still be read"
	)
	_check(
		(
			SessionStore.write_document(path, {"value": 3})
			and SessionStore.readable_path(path) == path
			and not FileAccess.file_exists(backup)
		),
		"the next save replaces an interrupted one"
	)


func _stats(main) -> void:
	var g: Game = main.make_game("hickston")
	g.configure({})
	var p := g.player
	p.armory.active = Weapons.CROSSBOW
	p.armory.owned[Weapons.CROSSBOW] = true
	p.armory.loaded[Weapons.CROSSBOW] = 1
	p.armory.reserve[Weapons.CROSSBOW] = 1
	p.armory.fire(g)
	if g.shots.is_empty():
		_check(false, "a crossbow shot is launched from the normal fire path")
		return
	p.armory.select(Weapons.REVOLVER, g)
	var path := "user://audit-in-flight.json"
	var restored := SessionStore.save(g, path)
	var back := SessionStore.read(path, main.make_game, false) if restored else null
	if back == null or back.shots.is_empty():
		_check(false, "an in-flight attack survives a save")
		return
	var shot: GameState.Shot = back.shots[0]
	var stats = back.features["stats"]
	var target: Enemy
	for e: Enemy in back.enemies:
		if e.hostile and not Enemy.BOSS_TITLES.has(e.kind):
			target = e
			break
	if target == null or shot.attack == null:
		_check(false, "the saved crossbow attack retains its source")
		return
	for e: Enemy in back.enemies:
		if e != target:
			e.hp = 0.0
	target.hp = 1.0
	shot.x = target.x
	shot.y = target.y
	shot.z = back.world.stand(target) + .85
	shot.damage = 10000
	back.clock += 5.0
	back.explode(shot)
	_check(
		stats.shots == 1 and stats.landed == 1 and stats.kills_by_gun == {"crossbow": 1},
		"a delayed hit after a save and weapon switch credits the crossbow"
	)


func _waiting(main) -> void:
	for state: String in ["title", "play", "replay", "lobby", "county"]:
		main.state = state
		var target: Game = main.make_game("hickston")
		main.waiting_play = target
		main.state = "setup"
		main.state = state
		_check(main.waiting_play == null, "leaving %s clears its pending chapter start" % state)
	main.state = "title"
	main.waiting_play = main.make_game("hickston")
	main.back_to_title()
	_check(main.waiting_play == null, "back cancels a title request while staying on the title")


func _packs() -> void:
	var loader := PackLoader.new()
	root.add_child(loader)
	var good := "chapter_fair"
	var bad := "chapter_bayou"
	var manifest := {}
	for name: String in PackLoader.ROAD_LINES:
		manifest[name] = {"file": name + "-1234567890.pck", "size": 4}
	var poisoned := manifest.duplicate(true)
	poisoned[bad]["file"] = "../outside.pck"
	_check(PackLoader._validated_manifest(poisoned).is_empty(), "invalid pack path is rejected")
	poisoned = manifest.duplicate(true)
	poisoned[bad]["size"] = 4.5
	_check(PackLoader._validated_manifest(poisoned).is_empty(), "fractional pack size is rejected")
	_check(
		not PackLoader._matches_digest("junk".to_utf8_buffer(), "0".repeat(64)),
		"a same-size corrupt pack fails its checksum"
	)
	loader.manifest = PackLoader._validated_manifest(manifest)
	loader.queue.assign([good])
	loader.want_first(bad, true)
	loader._retry(bad)
	_check(loader._dequeue() == good, "a failed priority pack cannot hold up other chapters")
	loader._clock += 4.0
	_check(loader._dequeue() == bad, "the priority pack can be selected after backoff")
	loader._tries[bad] = PackLoader.MAX_ATTEMPTS - 1
	loader._retry(bad)
	_check(loader.road_line(bad).begins_with("ROAD DOWN"), "exhausted retries show a failure")
	loader.want_first(bad, true)
	loader.want_first(bad, true)
	_check(loader.queue == [bad], "re-entering queues one retry")
	loader.queue_free()
	await process_frame


func _pack_http() -> void:
	var server = Server.new()
	if not server.start():
		_check(false, "the chapter pack test server starts")
		return
	var pack := "chapter_fair"
	var file := pack + "-1234567890.pck"
	var store := ProjectSettings.globalize_path(PackLoader.STORE)
	DirAccess.make_dir_recursive_absolute(store)
	if FileAccess.file_exists(store.path_join(file)):
		DirAccess.remove_absolute(store.path_join(file))
	var source := store.path_join("fixture.txt")
	var handle := FileAccess.open(source, FileAccess.WRITE)
	handle.store_string("ready")
	handle.close()
	var source_pack := ProjectSettings.globalize_path("user://fixture.pck")
	var builder := PCKPacker.new()
	builder.pck_start(source_pack)
	builder.add_file("res://audit-pack-ready.txt", source)
	builder.flush()
	var body := FileAccess.get_file_as_bytes(source_pack)
	var bad := body.duplicate()
	bad[0] ^= 255
	var loader := PackLoader.new()
	root.add_child(loader)
	loader._base = "http://127.0.0.1:%d/" % server.port
	loader._http = HTTPRequest.new()
	loader._http.timeout = 3.0
	loader._http.use_threads = true
	loader.add_child(loader._http)
	var responses := []
	loader._http.request_completed.connect(
		func(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
			responses.append([result, code])
	)
	loader._http.request_completed.connect(loader._done)
	loader.manifest[pack] = {
		"file": file, "size": body.size(), "sha256": FileAccess.get_sha256(source_pack)
	}
	loader.queue.append(pack)
	loader.set_process(false)  # advance the backoff after preparing the next response
	loader._next()  # the first attempt starts offline
	var end := Time.get_ticks_msec() + 12000
	while Time.get_ticks_msec() < end and not loader.loaded.has(pack):
		server.poll()
		if loader._retry_at.has(pack):
			var attempts: int = loader._tries[pack]
			server.files["/" + file] = bad if attempts == 1 else body
			loader._clock = loader._retry_at[pack]
			loader._next()
		await process_frame
	var content := FileAccess.get_file_as_string("res://audit-pack-ready.txt")
	_check(
		(
			loader.loaded.has(pack)
			and responses.size() == 3
			and responses[1] == [HTTPRequest.RESULT_SUCCESS, 200]
			and content == "ready"
		),
		(
			"a transport failure and a corrupt pack lead to a good mount (%d HTTP requests, %s, %s)"
			% [server.count(file), responses, content]
		)
	)
	server.stop()
	loader.queue_free()
	await process_frame
