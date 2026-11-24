## What the game draws: the sprite list, the frame (view, weapon, HUD), the
## view effects (the software look pass: screen_look.gd) and the automap
## (game_automap.gd) (the game layers are listed in game_state.gd).
class_name GameView
extends GameCombat


func reflection() -> Variant:
	if is_nan(world.mirror_x):
		return null
	var me: Game = self as Object
	if ModeBodies.hidden_in_vehicle(me, player):
		return null
	return ModeBodies.player_sprite(me, player)


# ------------------------------------------------------------------ sprites


## What the fixed sprites show: when any of it changes they are listed again.
func _fixed_key() -> Array:
	return [
		world.get_instance_id(),
		in_hub,
		legacy_key_route,
		exit_ready(),
		won,
		stations_done.hash(),
		scenery_spent.hash(),
		drums.size(),
		drums.keys().hash() if drums.size() < 64 else drums.size(),
		gallery != null,
		props.size(),
		world.boards_version,
	]


func _list_fixed() -> void:
	# The Crossroads is its own level (data/hub.json): everything in it shows.
	var sprites: Array = props.duplicate()
	for board: LevelData.Billboard in world.billboards:
		if board.hidden:
			continue  # taken over by a boss arena's wreck (features/arena_wreck.gd)
		var image := board.image
		if board.signal_name == "legacy-key":
			if legacy_key_route:
				image = "wing_town_legacy_key"
		elif board.signal_name != "":
			var active := (
				exit_ready()
				if board.signal_name == "exit"
				else won if board.signal_name == "cleared" else stations_done.has(board.signal_name)
			)
			image += "_on" if active else "_off"
		var z: float = world.elevation(board.x, board.y) + board.z
		var spr := View.Sprite.new(board.x, board.y, image, board.height, z)
		spr.glow = board.glow
		spr.plane = board.plane
		if board.signal_name != "":
			spr.face = _station_face(board)
		sprites.append(spr)
		if board.back != "":
			var back := View.Sprite.new(board.x, board.y, board.back, board.height, z)
			back.plane = board.plane + PI
			sprites.append(back)
	for point: Vector2 in drums.keys():
		var vec: Vector2 = point
		sprites.append(
			View.Sprite.new(vec.x, vec.y, "prop_fuel", 1.04, world.elevation(vec.x, vec.y))
		)
	fixed_windmills.clear()
	for sprite: View.Sprite in sprites:
		if sprite.image.begins_with("prop_windmill_"):
			fixed_windmills.append(sprite)
	fixed_sprites = sprites
	var late: Array = []
	if not in_hub:
		for note: LevelData.Note in level.notes:
			var note_sprite := View.Sprite.new(
				note.x, note.y, "county_note", .23, world.elevation(note.x, note.y) + .90
			)
			note_sprite.plane = note.plane
			fixed_sprites.append(note_sprite)
		if gallery != null:
			var gallery_sign := View.Sprite.new(25.95, 32.72, "county_gallery_sign", .51, 1.03)
			gallery_sign.plane = 0.0
			fixed_sprites.append(gallery_sign)
			var backstop := View.Sprite.new(29.90, 33.48, "county_gallery_backstop", 1.49, .19)
			backstop.plane = PI / 2.0
			fixed_sprites.append(backstop)
		for room: LevelData.Interior in level.interior_art:
			var room_sprite := View.Sprite.new(
				room.x,
				room.y,
				"county_room_" + room.art,
				room.height,
				world.elevation(room.x, room.y) + room.z
			)
			room_sprite.plane = room.plane
			late.append(room_sprite)
		for prop: LevelData.Scenery in world.scenery:
			var state := "spent" if scenery_used(prop) else "whole"
			late.append(
				View.Sprite.new(
					prop.x,
					prop.y,
					"scenery_%s_%s" % [prop.kind, state],
					prop.height,
					world.elevation(prop.x, prop.y) + prop.z
				)
			)
	fixed_sprites_late = late
	fixed_blocks = _blocks_of(fixed_sprites)
	late_blocks = _blocks_of(fixed_sprites_late)
	fixed_cull = PackedFloat64Array()
	for block: Array in fixed_blocks:
		fixed_cull.append_array([block[0], block[1], block[2]])
	late_cull = PackedFloat64Array()
	for block: Array in late_blocks:
		late_cull.append_array([block[0], block[1], block[2]])


## A side of a block of fixed sprites, in cells.
const SPRITE_BLOCK := 6.0


## `list` in blocks for _seen(): [middle x, middle y, reach, the sprites' places].
## The reach takes in each sprite's half width, from its picture.
func _blocks_of(list: Array) -> Array:
	var by_key := {}
	for i in list.size():
		var s: View.Sprite = list[i]
		var key := Vector2i(floori(s.x / SPRITE_BLOCK), floori(s.y / SPRITE_BLOCK))
		var places: PackedInt32Array = by_key.get(key, PackedInt32Array())
		places.append(i)
		by_key[key] = places
	var blocks: Array = []
	for key: Vector2i in by_key:
		var places: PackedInt32Array = by_key[key]
		var mx := (key.x + .5) * SPRITE_BLOCK
		var my := (key.y + .5) * SPRITE_BLOCK
		var reach := 0.0
		for i in places:
			var s: View.Sprite = list[i]
			if s.image == "":
				continue  # a breakable gone to pieces (breakables.gd `gone`)
			var art: Dictionary = self.art.art(s.image)
			var half := s.height * _view_num(art["w"]) / maxf(1.0, _view_num(art["h"])) * .5
			reach = maxf(reach, Vector2(s.x - mx, s.y - my).length() + half + .3)
		blocks.append([mx, my, reach, places])
	return blocks


## The sprites of `list` in the blocks the view can see, in list order: the
## renderer would skip every other one (behind the eye, past its reach or off
## the side), so leaving them out changes nothing drawn. A level with a mirror
## also keeps what the mirror's view could show. `cull` is the blocks' middles
## and reaches, flat (fixed_cull, late_cull): in_view()'s test written out.
func _seen(list: Array, blocks: Array, cull: PackedFloat64Array) -> Array:
	if view_cone.is_empty():
		return list.duplicate()
	var cx := view_cone[0]
	var cy := view_cone[1]
	var fx := view_cone[2]
	var fy := view_cone[3]
	var k := view_cone[4]
	var edge := view_cone[5]
	var mx := view_cone[6]
	var mirror := not is_nan(edge)
	var places := PackedInt32Array()
	for b in blocks.size():
		var x := cull[b * 3]
		var y := cull[b * 3 + 1]
		var r := cull[b * 3 + 2]
		var dx := x - cx
		var dy := y - cy
		var d := dx * fx + dy * fy
		if not (d > .13 - r and d < 51.0 + r and absf(dy * fx - dx * fy) < (d + r) * k + r):
			if not mirror or x + r < edge:
				continue
			dx = x - mx
			d = -dx * fx + dy * fy
			if not (d > .13 - r and d < 51.0 + r and absf(dy * fx + dx * fy) < (d + r) * k + r):
				continue
		var block_places: PackedInt32Array = blocks[b][3]
		places.append_array(block_places)
	places.sort()
	var out: Array = []
	out.resize(places.size())
	for j in places.size():
		out[j] = list[places[j]]
	return out


## Set this frame's view for in_view() from the eye the renderer was given.
func _aim_view() -> void:
	if view_eye.is_empty():
		view_cone = PackedFloat64Array()
		return
	var angle: float = view_eye["view_angle"]
	var edge: float = world.mirror_x
	view_cone = PackedFloat64Array(
		[
			view_eye["x"],
			view_eye["y"],
			cos(angle),
			sin(angle),
			view.vw * .5 / view.focal + .02,
			edge,
			2.0 * edge - _view_num(view_eye["x"]) if not is_nan(edge) else 0.0
		]
	)


## Whether anything standing within `reach` of (x, y) can show in this frame's
## view (or a mirror's, in a level with one): if not, the renderer would skip it.
func in_view(x: float, y: float, reach: float) -> bool:
	if view_cone.is_empty():
		return true
	var fx := view_cone[2]
	var fy := view_cone[3]
	var k := view_cone[4]
	var dx := x - view_cone[0]
	var dy := y - view_cone[1]
	var d := dx * fx + dy * fy
	if d > .13 - reach and d < 51.0 + reach and absf(dy * fx - dx * fy) < (d + reach) * k + reach:
		return true
	var edge := view_cone[5]
	if is_nan(edge) or x + reach < edge:
		return false
	# The mirror shows the room as seen from the eye mirrored in its line.
	dx = x - view_cone[6]
	d = -dx * fx + dy * fy
	return (
		d > .13 - reach and d < 51.0 + reach and absf(dy * fx + dx * fy) < (d + reach) * k + reach
	)


func sprites() -> Array:
	var me: Game = self as Object
	_aim_view()
	# Everything listed below but the fixed sprites comes from the pool.
	sprite_pool_n = 0
	var key := _fixed_key()
	if key != fixed_sprites_key:
		fixed_sprites_key = key
		_list_fixed()
	var mill := (
		"prop_windmill_%d" % (int(clock * 5.0) % 3) if not fixed_windmills.is_empty() else ""
	)
	for sprite: View.Sprite in fixed_windmills:
		sprite.image = mill
	var sprites: Array = _seen(fixed_sprites, fixed_blocks, fixed_cull)
	if in_hub:
		# plane = 0: these are flat boards fixed in the world, as in the
		# reference, not sprites that turn to face the camera.
		var board_at: Vector2 = level.hub_board
		var shift: Vector2 = board_at - HUB_BOARD
		var dispatch_cue: String = HUB_DISPATCH_CUES[hub_milestone]
		var dispatch := pooled(board_at.x, board_at.y, dispatch_cue, .46, 1.02)
		dispatch.plane = 0.0
		sprites.append(dispatch)
		if hub_milestone != 0:
			var trunk := hub_milestone in [2, 3]
			var prop := "county_dispatch_trunk" if trunk else "county_dispatch_tag"
			var tag := pooled(29.67 + shift.x, 44.12 + shift.y, prop, .31 if trunk else .24, .83)
			tag.plane = 0.0
			sprites.append(tag)
		var detail: int = view.world_motion
		var motion_speed: float = [1.0, .32, 0.0][detail]
		var dust_rows: Array = [
			[30.40, 46.85, 1.46, .19], [30.48, 45.95, 1.64, .28], [30.73, 44.95, 1.48, .37]
		]
		var dust: Array = []
		for i in 3 - detail:
			var row: Array = dust_rows[i]
			var dx: float = (
				_view_num(row[0]) + .11 * sin(clock * motion_speed * .68 + _view_num(row[1]))
			)
			var puff := pooled(
				dx + shift.x,
				_view_num(row[1]) + shift.y,
				"hub_dust",
				_view_num(row[2]),
				_view_num(row[3])
			)
			puff.translucent = true
			puff.plane = 0.0
			dust.append(puff)
		dust.sort_custom(
			func(a: View.Sprite, b: View.Sprite) -> bool:
				return (
					sqrt(pow(a.x - player.x, 2) + pow(a.y - player.y, 2))
					> sqrt(pow(b.x - player.x, 2) + pow(b.y - player.y, 2))
				)
		)
		sprites.append_array(dust)
		# Mundell's trophy shack (features/trophy_shack.gd): the hub's only
		# feature that stands things in it.
		var shack: GameFeature = features.get("trophy_shack")
		if shack != null:
			sprites.append_array(shack.sprites())
		var bench: GameFeature = features.get("bench")  # the junk bench on its counter
		if bench != null:
			sprites.append_array(bench.sprites())
		return sprites
	if gallery != null and gallery.active:
		sprites.append(gallery.sprite(me))
	sprites.append_array(_seen(fixed_sprites_late, late_blocks, late_cull))
	if finale != null and finale.kind == "rudy" and finale.alive:
		for point: Vector2 in world.boss_decoys:
			var decoy := pooled(
				point.x, point.y, "rudy_decoy", 1.65, world.elevation(point.x, point.y)
			)
			decoy.plane = 0.0
			sprites.append(decoy)
	for hazard: Hazard in hazards:
		if hazard.age >= hazard.warning:
			var mist := pooled(
				hazard.x,
				hazard.y,
				"fx_%s_mist" % hazard.kind,
				.47 if hazard.kind == "steam" else .32,
				world.elevation(hazard.x, hazard.y) + .03
			)
			mist.translucent = true
			sprites.append(mist)
	var observer := [player.x, player.y]
	var relieved := not world.pressure_ports.is_empty() and relief_open()
	# in_view() written out for the many enemies and pickups (the same sums).
	var culling := not view_cone.is_empty()
	var cx := view_cone[0] if culling else 0.0
	var cy := view_cone[1] if culling else 0.0
	var fx := view_cone[2] if culling else 0.0
	var fy := view_cone[3] if culling else 0.0
	var k := view_cone[4] if culling else 0.0
	var edge := view_cone[5] if culling else NAN
	var mx := view_cone[6] if culling else 0.0
	var mirror := not is_nan(edge)
	for enemy: Enemy in enemies:
		if culling:
			# Not even a boss or a corpse reaches 3.5 from where it stands.
			var dx := enemy.x - cx
			var dy := enemy.y - cy
			var d := dx * fx + dy * fy
			if not (
				d > .13 - 3.5 and d < 51.0 + 3.5 and absf(dy * fx - dx * fy) < (d + 3.5) * k + 3.5
			):
				if not mirror or enemy.x + 3.5 < edge:
					continue
				dx = enemy.x - mx
				d = -dx * fx + dy * fy
				if not (
					d > .13 - 3.5
					and d < 51.0 + 3.5
					and absf(dy * fx + dx * fy) < (d + 3.5) * k + 3.5
				):
					continue
		var slot := pooled(0.0, 0.0, "", 1.0, 0.0)
		var sprite: View.Sprite = enemy.sprite(observer, relieved, clock, slot)
		if sprite != null and not enemy.alive and gore_fx.headless.has(enemy):
			GoreExtras.headless_cel(me, sprite)
		if sprite != null:
			sprite.z += world.floor_under(sprite.x, sprite.y, world.stand(enemy) + .3)
			sprite.who = enemy
			sprites.append(sprite)
		else:
			sprite_pool_n -= 1
	# A pickup bobs (looks only); EASY ON THE EYES calms it (STILL: none).
	var bob: float = [.035, .014, 0.0][clampi(view.world_motion, 0, 2)]
	for entry: Array in pickups:
		var x: float = entry[1]
		var y: float = entry[2]
		if culling:
			var dx := x - cx
			var dy := y - cy
			var d := dx * fx + dy * fy
			if not (
				d > .13 - 1.0 and d < 51.0 + 1.0 and absf(dy * fx - dx * fy) < (d + 1.0) * k + 1.0
			):
				if not mirror or x + 1.0 < edge:
					continue
				dx = x - mx
				d = -dx * fx + dy * fy
				if not (
					d > .13 - 1.0
					and d < 51.0 + 1.0
					and absf(dy * fx + dx * fy) < (d + 1.0) * k + 1.0
				):
					continue
		var hover := .06 + sin(clock * 3.5 + x) * bob
		var lies: float = entry[4] if entry.size() > 4 else world.elevation(x, y)
		sprites.append(pooled(x, y, "item_" + str(entry[0]), .33, lies + hover))
	for shot: Shot in shots:
		if (
			shot.enemy
			or shot.kind == "tnt"
			or (
				sqrt(
					(
						(shot.x - player.x) * (shot.x - player.x)
						+ (shot.y - player.y) * (shot.y - player.y)
					)
				)
				> .95
			)
		):
			var name := (
				"blade_%d" % (int(shot.travelled * 9.0) % 3) if shot.kind == "blade" else shot.kind
			)
			if shot.kind == "tnt":
				var phase := (
					int(shot.travelled * 12.0) if not shot.resting else int(shot.life * 9.0)
				)
				name += "_%d" % (phase % 3)
			var size := Shots.size(shot.kind, shot.enemy)
			var shot_sprite := pooled(shot.x, shot.y, "fx_" + name, size, shot.z)
			shot_sprite.glow = Shots.glows(shot.kind)
			if shot.kind == "bowling":
				Shots.ball_look(shot_sprite, shot)
			sprites.append(shot_sprite)
	sprites.append_array(Features.sprites(me))
	for fx_speck: Speck in specks:
		if not in_view(fx_speck.x, fx_speck.y, .3):
			continue
		var speck_sprite := pooled(
			fx_speck.x,
			fx_speck.y,
			"fx_" + fx_speck.kind,
			View.speck_size(Vector2(fx_speck.x - player.x, fx_speck.y - player.y).length()),
			fx_speck.z
		)
		speck_sprite.glow = fx_speck.kind == "spark"
		sprites.append(speck_sprite)
	for puff: Gore.Puff in gore_fx.puffs:
		if not in_view(puff.x, puff.y, 1.6):
			continue
		var hot := puff.kind == "sparks"
		var step := mini(2 if hot else 3, int(puff.age * (14.0 if hot else 11.0)))
		# A puff right in front (a swing at a wall) stays small: at full size it
		# would fill the view.
		var near_k := clampf(Vector2(puff.x - player.x, puff.y - player.y).length() / 2.5, .35, 1.0)
		var cloud := pooled(
			puff.x,
			puff.y,
			Enemy.cel_name("fx_" + puff.kind, step),
			(.20 + puff.age * .85) * near_k,
			puff.z - .08 * near_k
		)
		cloud.glow = hot
		cloud.translucent = true
		sprites.append(cloud)
	for g: Gore.Gib in gore_fx.gibs:
		if not in_view(g.x, g.y, g.size + .4):
			continue
		var chunk := pooled(g.x, g.y, g.image, g.size, g.z)
		chunk.flip = g.flip
		chunk.spin = g.spin
		# Rolling it turns over by its run; at rest it settles onto a face.
		chunk.lying = g.rest
		if g.rest:
			chunk.settle = minf(g.age, View.SETTLED)
		sprites.append(chunk)
	var blast_order: Array = []
	for blast: Blast in blasts:
		blast_order.append(
			[
				sqrt(
					(
						(blast.x - player.x) * (blast.x - player.x)
						+ (blast.y - player.y) * (blast.y - player.y)
					)
				),
				blast
			]
		)
	blast_order.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	for entry: Array in blast_order:
		var blast: Blast = entry[1]
		if Effects.rich and blast.kind == "fire":
			# features/gun_fx.gd draws the shader view's fireball.
			continue
		var smoke := blast.age >= .27
		var age := blast.age - .27 if smoke else blast.age
		var frame := mini(3, int(age * (11.0 if smoke else 16.0)))
		var size := .55 + blast.age * 1.3
		var z := maxf(.03, blast.z - size * .43 + blast.age * .63)
		var ball := (
			"blast"
			if blast.kind == "fire"
			else "blast_energy" if blast.kind == "energy" else blast.kind
		)
		var blast_sprite := pooled(
			blast.x, blast.y, "fx_%s_%d" % ["smoke" if smoke else ball, frame], size, z
		)
		blast_sprite.glow = not smoke
		blast_sprite.translucent = true
		sprites.append(blast_sprite)
	return sprites


## Where a point of the world falls on the 320-wide canvas this frame:
## (x, y, distance ahead), the distance below zero when it is behind the eye.
func to_canvas(x: float, y: float, z: float) -> Vector3:
	if view_eye.is_empty():
		return Vector3(0, 0, -1)
	var angle: float = view_eye["view_angle"]
	var fx := cos(angle)
	var fy := sin(angle)
	var dx: float = x - _view_num(view_eye["x"])
	var dy: float = y - _view_num(view_eye["y"])
	var ahead := dx * fx + dy * fy
	if ahead < .12:
		return Vector3(0, 0, -1)
	var horizon: float = (
		View.VIEW / 2.0
		+ _view_num(view_eye["pitch"])
		+ _view_num(view_eye["bob"])
		+ _view_num(view_eye["sway"])
	)
	var focal := View.base_focal
	return Vector3(
		View.WIDTH / 2.0 + (dy * fx - dx * fy) / ahead * focal,
		horizon - (z - _view_num(view_eye["eye"])) / ahead * focal,
		ahead
	)


# ---------------------------------------------------------------- objective


func feedback(c: Canvas) -> void:
	if not in_hub:
		var p := player
		var alert: Variant = null
		var nearest := 10.5 * 10.5
		for enemy: Enemy in enemies:
			if not (
				enemy.windup > 0.0
				and enemy.alive
				and enemy.player_seen
				and (Enemy.RANGED.has(enemy.kind) or enemy.brain in ["clone", "billy", "coot"])
			):
				continue
			var dx := enemy.x - p.x
			var dy := enemy.y - p.y
			var square := dx * dx + dy * dy
			var turn := fposmod(atan2(dy, dx) - p.view_angle() + PI, TAU) - PI
			if absf(turn) > .70 and square < nearest:
				alert = turn
				nearest = square
		if alert != null:
			var turned: float = alert
			var side := "REAR" if absf(turned) > 2.41 else "LEFT" if turned < 0.0 else "RIGHT"
			var label := "WINDUP " + side
			var width := 10 + PixelType.text_width(label, "mini")
			var x := (
				(WIDTH - width) / 2
				if side == "REAR"
				else 6 if side == "LEFT" else WIDTH - width - 6
			)
			var at := hud.layout.down("windup", HudLayout.panel_rect(0, 0, width, 14).size, x, 74)
			if at.size.x > 0:
				HudLayout.begin(c, "windup")
				HUD.panel(c, at.position.x, at.position.y, width, 14, Canvas.rgb(40, 29, 22))
				HUD.text(
					c,
					label,
					at.position.x + 5,
					at.position.y + 4,
					"mini",
					Canvas.rgb(233, 188, 111),
					false,
					false
				)
				HudLayout.end(c)
	if item_feedback != null:
		var name := str(item_feedback[0])
		var end: float = item_feedback[2]
		var label := _item_label()
		var width := 29 + PixelType.text_width(label, "mini")
		var spot := hud.layout.find("item")
		if clock < end and spot.size.x > 0:
			var y := spot.position.y
			HudLayout.begin(c, "item")
			HUD.panel(c, 8, y, width, 20, Canvas.rgb(38, 27, 21))
			var image := art.art("item_" + name)
			var iw: int = image["w"]
			var ih: int = image["h"]
			var data: PackedByteArray = image["data"]
			if c.gpu:
				# The same 16x16 pixels as one picture, not 256 draw commands.
				c.gpu_texture(_item_icon(name, data, iw, ih), 11, y + 2, 16, 16)
			else:
				for ty in 16:
					var sy := clampi(ty * ih / 16, 0, ih - 1)
					for tx in 16:
						var sx := clampi(tx * iw / 16, 0, iw - 1)
						var sp := (sy * iw + sx) * 4
						if data[sp + 3] == 0:
							continue
						c.set_pixel(11 + tx, y + 2 + ty, data[sp], data[sp + 1], data[sp + 2])
			HUD.text(c, label, 30, y + 7, "mini", Canvas.rgb(249, 205, 144), false, false)
			HudLayout.end(c)
	if damage_feedback != null:
		var heading: Variant = damage_feedback[0]
		var cause := str(damage_feedback[1])
		var end2: float = damage_feedback[2]
		if clock >= end2:
			return
		var side := ""
		if heading != null and not NO_MARK_SURFACE.has(cause):
			var turn2 := fposmod(_view_num(heading) - player.view_angle() + PI, TAU) - PI
			side = (
				" REAR"
				if absf(turn2) > 2.41
				else " LEFT" if turn2 < -.40 else " RIGHT" if turn2 > .40 else " FRONT"
			)
		var hurt := hud.layout.banner("hurt", cause + side, 87)
		if hurt.size.x > 0:
			HudLayout.begin(c, "hurt")
			HUD.banner(
				c, cause + side, hurt.position.y, hud.layout.limit, Canvas.rgb(244, 160, 108)
			)
			HudLayout.end(c)


# ---------------------------------------------------------------- main draw


func draw(c: Canvas, crosshair := 1, grade := true) -> void:
	_draw(c, crosshair, grade)


func _draw(c: Canvas, crosshair: int, grade: bool) -> void:
	var me: Game = self as Object
	var p := player
	look_live = false
	tone_live = false
	hurt_alpha = 0
	scene_live = false
	view_frame = {}
	drunk_k = 0.0
	c.layer = false
	if showing_tally:
		hud.intermission(c, me)
		return
	var practice := gallery != null and gallery.active
	var weapon: Weapons.Armory = gallery.pistol if practice else armory
	var flash: float = (weapon.flash * 4.0 + blast_flash * .85) * flash_scale
	view.time = clock
	view.fit()
	view.layered = layered and gpu_look
	Effects.rich = view.layered and Effects.enabled
	Scope.focal(me, p)
	if view.detail < 0 and not view.layered:
		# HD is the 3D view's: without one the view keeps HIGH and the wish,
		# and the next frame drawn with a window is HD again.
		view.set_detail(0, true)
	elif view.hd_wanted and view.detail == 0 and view.layered:
		view.set_detail(-1)
	var t0 := Time.get_ticks_usec()
	var eye := p.as_render_player()
	# PHOTO MODE: the free camera's eye, steady, with the player in view.
	var posing := not eye_override.is_empty()
	if posing:
		eye = eye_override.duplicate()
	var trauma := 0.0 if posing else shake * shake * shake_scale
	if trauma > .001:
		# The view shakes, the gun does not: a jolt of yaw and of horizon.
		eye["view_angle"] += (sin(clock * 71.0) + sin(clock * 43.0 + 1.3)) * .009 * trauma
		eye["pitch"] += (sin(clock * 59.0 + .7) + sin(clock * 37.0)) * 2.4 * trauma
	if p.health > 0 and not posing:
		# The springs' jolts (features/feel.gd): a landing, a blow.
		eye["view_angle"] += view_kick.x
		eye["pitch"] += view_kick.y
		eye["eye"] -= view_kick.z
		# A vehicle's seat rides its springs (features/vehicles.gd, looks).
		var riding: GameFeature = features.get("vehicles")
		if riding != null:
			riding.call("sway_eye", eye)
	view_eye = eye
	var listing := Time.get_ticks_usec()
	var marks: Array = ground_marks()
	var marks_list: Array = wall_marks if bullet_marks else []
	if not gore_fx.walls.is_empty():
		marks_list = marks_list + gore_fx.walls
	marks_list = marks_list + Features.wall_marks(me)
	var listed: Array = sprites()
	# A chapter opener's camera coming down into the player's eyes leaves him out.
	var hidden: bool = eye_override.get("hide_player", false)
	if posing and not hidden and not ModeBodies.hidden_in_vehicle(me, p):
		listed.append(ModeBodies.player_sprite(me, p))
	var t1 := Time.get_ticks_usec()
	# What the 3D view (view3d/world_view.gd) draws this frame: it reads this
	# after the draw. Headless nothing draws the world; the canvas is a layer
	# over an empty view either way.
	view_frame = {
		"eye": eye,
		"horizon":
		(
			(VIEW / 2.0 + _view_num(eye["pitch"]) + _view_num(eye["bob"]) + _view_num(eye["sway"]))
			/ view.res_up
		),
		"flash": flash,
		"sprites": listed,
		"marks": marks_list,
		"ground": marks,
		"reflection": reflection(),
		"gear_lost": BossGearFeature.lost_of(me),
	}
	c.begin_layer()
	var t2 := Time.get_ticks_usec()
	# What the features draw over the view (tracers, the milk, sparks), under the gun.
	c.view_tint = Color(1, 1, 1)
	if weapon.has_method("place_muzzle"):
		weapon.place_muzzle(p, bob_scale, 12 if weapon_view == 1 else 0)
	if c.gpu:
		c.gpu_item(Canvas.ITEM_NORMAL_VIEW)
	var scoped := p.scoped and p.health > 0
	if scoped:
		Scope.mask(c)  # under the features' marks (the 5v5 score and cash stay)
	var top_note := _lay_hud(practice, posing)
	Features.draw_view(me, c)
	if c.gpu:
		c.gpu_item(Canvas.ITEM_NORMAL)
	c.view_tint = gun_light() if c.gpu and Effects.enabled else Color(1, 1, 1)
	if (
		not scoped
		and not posing
		and p.health > 0
		and not in_hub
		and (weapon_view != 2 or armory.fuse > 0.0)
	):
		weapon.draw(
			c.pixels,
			art,
			p,
			world.light[world.cell(p.x, p.y)],
			bob_scale,
			flash_scale,
			12 if weapon_view == 1 else 0,
			c if c.layer or c.gpu else null
		)
		if c.gpu:
			# The weapon drew on items clipped to the view rows.
			c.gpu_item(Canvas.ITEM_NORMAL)
	var t3 := Time.get_ticks_usec()
	if hurt_flash > 0.0 and flash_scale > 0.0:
		_apply_hurt_flash(c)
	if p.drunk >= 38.0 and flash_scale > 0.0:
		if scene_live or c.gpu:
			drunk_k = minf(1.0, (p.drunk - 38.0) / 62.0)
		else:
			ScreenLook.drunk_warp(c, p.drunk, clock)
	# The look pass and the brightness grade touch the same view rectangle; the
	# lookup table is folded into the look pass when both are active.
	var graded := false
	look_live = retro_look and flash_scale > 0.0
	tone_live = grade and tone != null
	if gpu_look:
		# The display shader grades the view; only its numbers are worked out here.
		if look_live:
			_look_params()
	else:
		if look_live:
			var table: Variant = tone if grade else null
			_look_pass(c, table)
			graded = tone_live
		if tone_live and not graded:
			_grade_view(c)
	var t4 := Time.get_ticks_usec()
	stage_ms = [
		(t1 - listing) / 1000.0,
		(listing - t0 + t2 - t1) / 1000.0,
		(t3 - t2) / 1000.0,
		(t4 - t3) / 1000.0,
		0.0
	]
	if posing:
		return  # PHOTO MODE draws its own strip (photo_mode.gd): no gun, sights or HUD
	if p.health > 0:
		var tint := crosshair_tint
		if crosshair == 2:
			c.circle(160, VIEW / 2, 4, tint, false)
		elif crosshair == 3:
			# CROSS: four short arms around an open middle.
			c.fill_rect(156, VIEW / 2, 3, 1, tint)
			c.fill_rect(162, VIEW / 2, 3, 1, tint)
			c.fill_rect(160, VIEW / 2 - 4, 1, 3, tint)
			c.fill_rect(160, VIEW / 2 + 2, 1, 3, tint)
		elif crosshair != 0:
			c.set_pixel(
				160,
				VIEW / 2,
				roundi(tint.r * 255.0),
				roundi(tint.g * 255.0),
				roundi(tint.b * 255.0)
			)
		if hit_mark_until > clock and hit_feedback:
			_hit_mark(c)
		var lay := hud.layout
		var called := lay.find("callout")
		if called.size.x > 0:
			# A kill streak's call, big, shaking a little as it lands.
			var fresh := 1.3 - (callout_until - clock)
			var jolt := int(maxf(0.0, .2 - fresh) * 20.0 * shake_scale)
			HudLayout.begin(c, "callout")
			HUD.text(c, callout, 160 + jolt, called.position.y + 1, "heading", HUD.AMBER, true)
			HudLayout.end(c)
		# A boss's entrance: its name slammed onto a fair ribbon (boss_kit.gd).
		BossKit.draw_intro(me, c)
		# Marks over the view go under every banner (pass 12: a hit from in
		# front drew the hurt arc across the notice and the tip).
		var marked: bool = top_note.get("mark", false)
		if marked:
			_use_mark(c)
		if not map:
			_hurt_arc_now(c)
		for top_piece: String in ["notice", "tip"]:
			if top_note.has(top_piece):
				var note: Array = top_note[top_piece]
				var note_text: String = note[0]
				var note_top: int = note[1]
				var note_wrap: int = note[2]
				var note_ink: Color = note[3]
				HudLayout.begin(c, top_piece)
				HUD.banner(c, note_text, note_top, note_wrap, note_ink)
				HudLayout.end(c)
		var boss_at := lay.find("boss")
		if boss_at.size.x > 0:
			HudLayout.begin(c, "boss")
			BossBar.draw(me, c, boss_at.position.y)
			HudLayout.end(c)
		if not map:
			feedback(c)
		# The prompt and the caption (or a hand's bark), laid out in _lay_hud.
		for piece: String in ["prompt", "caption"]:
			if top_note.has(piece):
				var said: Array = top_note[piece]
				var said_text: String = said[0]
				var said_top: int = said[1]
				var said_wrap: int = said[2]
				var said_ink: Color = said[3]
				HudLayout.begin(c, piece)
				HUD.banner(c, said_text, said_top, said_wrap, said_ink)
				HudLayout.end(c)
	elif not defeated():
		# Down, but a partner is up or a respawn is coming (src/modes/).
		ModeScreens.draw_down(c, me)
	else:
		HUD.panel(c, 27, 54, 266, 52, Canvas.rgb(43, 26, 22))
		HUD.text(c, "YOU BOUGHT THE FARM", 160, 64, "heading", HUD.INK, true)
		# A rematch, or a boss fight with its checkpoint (features/boss_*.gd),
		# says its own two lines.
		var lines: Array = []
		for key: String in ["boss_rematch", "boss_checkpoint"]:
			if lines.is_empty() and features.has(key):
				var death: Object = features[key]
				lines = death.call("death_lines")
		if net_role == "copy":
			# Online co-op: the host picks (net_coop.gd retry).
			lines = ["THE HOST PICKS WHAT COMES NEXT", "ESC  LEAVE THE GAME"]
		elif net_role == "host" and lines.size() != 2:
			lines = ["ENTER  THE CHAPTER AGAIN", "ESC  LEAVE THE GAME"]
		if lines.size() == 2:
			HUD.text(c, str(lines[0]), 160, 82, "body", HUD.AMBER, true)
			HUD.text(c, str(lines[1]), 160, 94, "body", HUD.INK, true)
		else:
			HUD.text(
				c,
				"ENTER CROSSROADS  /  ESC TITLE" if revisiting else _retry_words(),
				160,
				90,
				"body",
				HUD.INK,
				true
			)
	if map and p.health > 0:
		automap(c)
	gore_fx.draw_lens(c)
	HudLayout.begin(c, "pin")
	hud.draw(c, me, weapon)
	HudLayout.end(c)
	stage_ms[4] = (Time.get_ticks_usec() - t4) / 1000.0


## Lays out this frame's HUD over the view (ui/hud/hud_layout.gd), first
## come keeps its place: the features' fixed pieces at the edges; the top
## stack (the notice or place name, the boss bar, the objective pin's row);
## the features' pieces that hang under it; a picked-up item; the prompt and
## the caption rising from the view's foot; a streak's call; last the kill
## feed. Returns the banners to draw ("notice", "prompt", "caption": [text,
## top, wrap width, colour]; "mark": USE's mark is wanted) and sets pin_top.
func _lay_hud(practice: bool, posing: bool) -> Dictionary:
	var me: Game = self as Object
	var lay := hud.layout
	lay.reset()
	var out := {}
	if posing:
		return out
	Features.hud_fixed(me, lay)
	var p := player
	if p.health > 0 and not map:
		var text := ""
		var ink := HUD.INK
		# A new player's tip (lessons.gd) outranks a place's name.
		var tip_up := tip_until > clock and tip != "" and tips != 0 and not practice
		if practice:
			text = gallery.hud()
		elif message_until > clock and (hints or notice != level.introduction):
			text = notice
		elif district_labels and district_until > clock and not tip_up:
			text = level.districts[district]
			ink = Canvas.rgb(245, 196, 122)
		if text != "":
			var at := lay.banner("notice", text, 5)
			if at.size.x > 0:
				out["notice"] = [text, at.position.y, lay.limit, ink]
		if tip_up:
			# A new player's tip (lessons.gd): its own banner, under the notice.
			var tip_at := lay.banner("tip", tip, 5)
			if tip_at.size.x > 0:
				out["tip"] = [tip, tip_at.position.y, lay.limit, Lessons.INK]
		var boss := BossBar.height(me)
		if boss > 0:
			lay.down("boss", HudLayout.panel_rect(0, 0, 122, boss).size, 193, 5)
	# The objective pin's row: it swings across the view's middle.
	pin_top = 5
	if p.health > 0 and not map:
		# Under the top stack only (what starts in the top rows), not under a
		# corner piece lower down.
		pin_top = maxi(5, lay.under(30, 291, 40))
		if hints and not hud.minimal and objective_target() != null:
			lay.pin_row(Rect2i(30, pin_top, 261, 28))
	Features.hud_flow(me, lay)
	_lay_item()
	if p.health > 0 and not map and armory.fuse == 0.0:
		var hint := gate_prompt()
		if hint == "" and hints and not in_hub:
			hint = use_prompt()
			out["mark"] = hint != ""
		if hint.begins_with("E  ") and use_key != "E":
			hint = use_key + "  " + hint.substr(3)
		# The prompt and the caption (or a hand's bark) rise from the view's
		# foot, narrowed clear of BLUE's badge and the like.
		if hint != "":
			_rise(out, "prompt", hint, Canvas.rgb(251, 207, 142))
		if voice_captions and caption_until > clock:
			_rise(out, "caption", caption, Canvas.rgb(209, 221, 179))
		elif barks.visible(me) and hint == "":
			_rise(out, "caption", '"' + barks.text + '"', Canvas.rgb(255, 214, 150))
	if p.health > 0 and not map and callout_until > clock:
		# A streak's call under the pin: after the prompt and the caption.
		var tall: int = PixelType.style_of("heading")[1]
		var wide := PixelType.text_width(callout, "heading") + 10
		lay.centred("callout", Vector2i(wide, tall + 3), pin_top + 2)
	Features.hud_late(me, lay)
	return out


## A thing just picked up: its plate up the view's left over the badge and
## the feed, dropping into its place as it lands.
func _lay_item() -> void:
	if item_feedback == null or map or player.health <= 0:
		return
	var end: float = item_feedback[2]
	if clock >= end:
		return
	var width := 29 + PixelType.text_width(_item_label(), "mini")
	var drop := roundi(maxf(0.0, end - clock - .79) * 25.0 * bob_scale)
	hud.layout.up("item", HudLayout.panel_rect(0, 0, width, 20 + drop).size, 8)


## The picked-up item's icon as feedback() sets its pixels (16x16, every
## pixel not clear drawn solid), as a kept texture for the Godot canvas.
func _item_icon(name: String, data: PackedByteArray, iw: int, ih: int) -> Texture2D:
	var rgba := PackedByteArray()
	rgba.resize(16 * 16 * 4)
	for ty in 16:
		var sy := clampi(ty * ih / 16, 0, ih - 1)
		for tx in 16:
			var sx := clampi(tx * iw / 16, 0, iw - 1)
			var sp := (sy * iw + sx) * 4
			if data[sp + 3] == 0:
				continue
			var o := (ty * 16 + tx) * 4
			rgba[o] = data[sp]
			rgba[o + 1] = data[sp + 1]
			rgba[o + 2] = data[sp + 2]
			rgba[o + 3] = 255
	return Canvas.texture("item_icon|" + name, rgba, 16, 16)


func _item_label() -> String:
	var text := str(item_feedback[1])
	return text if text != "" else str(HUD.ITEM_LABELS[HUD.ITEMS.find(str(item_feedback[0]))])


## The death screen's way on, in the words of the device last used (pass 12:
## a pad or a touch screen was told ENTER and F9).
func _retry_words() -> String:
	if input_device == "pad":
		return "A  RETRY  /  B  TITLE"
	if input_device == "touch":
		return "TAP  RETRY"
	return "ENTER RETRY  /  F9 QUICKLOAD  /  ESC TITLE"


## A banner risen from the view's foot into the room the layout has left.
func _rise(out: Dictionary, piece: String, text: String, ink: Color) -> void:
	var lay := hud.layout
	var at := lay.banner(piece, text, HudLayout.BOTTOM - 1, 288, true)
	if at.size.x > 0:
		out[piece] = [text, at.position.y, lay.limit, ink]


## This frame's lights for the graphics-card view (effects.cfg), nearest
## first, at most Effects.MAX_LIGHTS of them (view_lights.gd).
func effect_lights() -> Array:
	var me: Game = self as Object
	return ViewLights.effect_lights(me)


## The light on the gun (view_lights.gd): white is the gun as drawn.
func gun_light() -> Color:
	var me: Game = self as Object
	return ViewLights.gun_light(me)


## The hurt arc of the hit now marked, if any (drawn before every banner).
func _hurt_arc_now(c: Canvas) -> void:
	if damage_feedback == null:
		return
	var heading: Variant = damage_feedback[0]
	var end: float = damage_feedback[2]
	if clock >= end or heading == null or NO_MARK_SURFACE.has(str(damage_feedback[1])):
		return
	_hurt_arc(c, fposmod(_view_num(heading) - player.view_angle() + PI, TAU) - PI, end)


## A red arc at the edge of the view on the side the hurt came from, fading.
func _hurt_arc(c: Canvas, turn: float, end: float) -> void:
	var fade := clampf((end - clock) / .64, 0.0, 1.0)
	var colour := Color(.35 + .55 * fade, .06 + .08 * fade, .04)
	for k in range(-14, 15):
		var a := turn + k * .022
		var x := int(160.0 + sin(a) * 132.0)
		var y := int(VIEW / 2.0 - cos(a) * 66.0)
		var thick := 3 if absi(k) < 10 else 2
		c.fill_rect(
			clampi(x - 1, 0, WIDTH - thick), clampi(y - 1, 0, VIEW - thick), thick, thick, colour
		)


## Corner brackets round the quest device USE would act on (use_aim, set by
## use_target), breathing slowly: what the prompt names is the thing marked.
## Doors and things already done get none.
func _use_mark(c: Canvas) -> void:
	var found: Variant = use_target()
	if found == null or found[0] is LevelData.Door or use_aim == Vector3.INF:
		return
	if found[0] is LevelData.Station and stations_done.has(found[0].id):
		return
	var at := to_canvas(use_aim.x, use_aim.y, use_aim.z)
	if at.z <= 0.0:
		return
	var half := int(clampf(.2 / at.z * View.base_focal, 5, 16))
	var cx := int(at.x)
	var cy := int(at.y)
	if (
		cx < half - View.shift
		or cx > WIDTH + View.shift - half
		or cy < half + 2
		or cy > VIEW - half
	):
		return
	var glow := .72 + .28 * sin(clock * 4.2)
	var colour := Color(1.0 * glow, .80 * glow, .42 * glow)
	var arm := maxi(2, half / 3)
	for sx: int in [-1, 1]:
		for sy: int in [-1, 1]:
			var x := cx + sx * half
			var y := cy + sy * half
			c.fill_rect(mini(x, x - sx * arm), y, arm + 1, 1, colour)
			c.fill_rect(x, mini(y, y - sy * arm), 1, arm + 1, colour)


## Four short ticks around the crosshair when a hit lands: they snap out white
## and settle in, red and wider on a kill, gold with a longer tick on the head
## (hit_zones.gd).
func _hit_mark(c: Canvas) -> void:
	var fresh := clock - hit_mark_at < .045
	var gap := (4 if hit_mark_kill else 3) + (2 if fresh else 0)
	var length := 4 if hit_mark_kill or hit_mark_head else 3
	var r := 236 if hit_mark_kill else 255 if hit_mark_head else 246
	var g := 72 if hit_mark_kill else 204 if hit_mark_head else 228
	var b := 48 if hit_mark_kill else 64 if hit_mark_head else 190
	if fresh:
		r = 255
		g = 250
		b = 236
	for k in length:
		var d := gap + k
		c.set_pixel(160 - d, VIEW / 2 - d, r, g, b)
		c.set_pixel(160 + d, VIEW / 2 - d, r, g, b)
		c.set_pixel(160 - d, VIEW / 2 + d, r, g, b)
		c.set_pixel(160 + d, VIEW / 2 + d, r, g, b)
	if hit_mark_kill and not fresh:
		# A dark edge under a kill's ticks, so it reads on a bright sky.
		for k in length:
			var d := gap + k
			c.set_pixel(160 - d, VIEW / 2 - d + 1, 40, 12, 8)
			c.set_pixel(160 + d, VIEW / 2 - d + 1, 40, 12, 8)
			c.set_pixel(160 - d, VIEW / 2 + d + 1, 40, 12, 8)
			c.set_pixel(160 + d, VIEW / 2 + d + 1, 40, 12, 8)


# ------------------------------------------------------------- view effects


func _apply_hurt_flash(c: Canvas) -> void:
	var alpha := clampi(roundi(hurt_flash * 310.0 * flash_scale), 0, 255)
	hurt_alpha = alpha if gpu_look else 0
	if alpha == 0 or gpu_look:
		return
	var pix := c.pixels
	var inv := 255 - alpha
	var n := WIDTH * VIEW * 3
	var i := 0
	while i < n:
		pix[i] = (131 * alpha + pix[i] * inv) / 255
		pix[i + 1] = (27 * alpha + pix[i + 1] * inv) / 255
		pix[i + 2] = (17 * alpha + pix[i + 2] * inv) / 255
		i += 3


## This frame's lamp buzz, grain frame and blast lift, for either look path.
func _look_params() -> void:
	var indoors: bool = world.roof[world.cell(player.x, player.y)] != 0.0
	var gain := 1.0
	# SCREEN FLASH below FULL also stills the lamp buzz, as in the reference.
	if indoors and flicker and flash_scale == 1.0:
		var buzz := .985 + .015 * sin(clock * 53.0)
		if int(clock * 7.3) % 29 == 0 and fmod(clock * 7.3, 1.0) < .35:
			buzz -= .07
		gain = buzz
	screen_look.gain = gain
	screen_look.frame = int(clock * 17.0) % ScreenLook.GRAIN_FRAMES
	screen_look.blast = blast_flash * 60.0


## The software look pass (screen_look.gd), `grade_tone` folded in.
func _look_pass(c: Canvas, grade_tone: Variant = null) -> void:
	_look_params()
	screen_look.run(c, art.grain, grade_tone, _look_band_count())


func _look_band_count() -> int:
	if VIEW < 48 or not OS.has_feature("threads"):
		return 1
	if look_bands > 0:
		return mini(look_bands, VIEW)
	# Four bands measured fastest: the renderer already fills the machine with
	# its own band threads, and more look workers just contend with them.
	return mini(4, VIEW)


func _grade_view(c: Canvas) -> void:
	var pix := c.pixels
	var n := WIDTH * VIEW * 3
	for i in n:
		pix[i] = tone[pix[i]]


# ----------------------------------------------------------------- automap


## The map over the view (game_automap.gd, the game's map_view).
func automap(c: Canvas) -> void:
	var me: Game = self as Object
	map_view.draw(me, c)


## float() and int() of a number read from a list or dictionary, typed (the
## same result for a number or a bool).
static func _view_num(v: Variant) -> float:
	return v


static func _view_int(v: Variant) -> int:
	return v

# ------------------------------------------------------------------ controls
