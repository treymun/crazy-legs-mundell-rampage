## What the game draws: the sprite list, the frame (view, weapon, HUD), the
## view effects and the automap (the game layers are listed in game_state.gd).
class_name GameView
extends GameCombat


func reflection() -> Variant:
	if is_nan(world.mirror_x):
		return null
	var p := player
	var facing := fposmod(TAU - p.angle, TAU) - PI
	var direction := mini(4, int(absf(facing) / (PI / 4.0) + .5))
	var heading: String = ["front", "quarter", "side", "away", "back"][direction]
	var stride := 0
	if p.motion > .15 and p.air == 0.0:
		stride = int(round(sin(p.walk_phase)))
	var height := 1.24 if p.crouched else 1.65
	var feet: float = world.elevation(p.x, p.y) + p.air
	var out := Renderer.Sprite.new(p.x, p.y, "player_%s_%d" % [heading, stride], height, feet)
	out.flip = facing < 0.0 and direction < 4
	return out


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
	]


func _list_fixed() -> void:
	# The Crossroads is its own level (data/hub.json): everything in it shows.
	var sprites: Array = props.duplicate()
	for board: LevelData.Billboard in world.billboards:
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
		var spr := Renderer.Sprite.new(board.x, board.y, image, board.height, z)
		spr.glow = board.glow
		spr.plane = board.plane
		sprites.append(spr)
		if board.back != "":
			var back := Renderer.Sprite.new(board.x, board.y, board.back, board.height, z)
			back.plane = board.plane + PI
			sprites.append(back)
	for point in drums.keys():
		var vec: Vector2 = point
		sprites.append(
			Renderer.Sprite.new(vec.x, vec.y, "prop_fuel", 1.04, world.elevation(vec.x, vec.y))
		)
	fixed_windmills.clear()
	for sprite: Renderer.Sprite in sprites:
		if sprite.image.begins_with("prop_windmill_"):
			fixed_windmills.append(sprite)
	fixed_sprites = sprites
	var late: Array = []
	if not in_hub:
		for note: LevelData.Note in level.notes:
			var note_sprite := Renderer.Sprite.new(
				note.x, note.y, "county_note", .23, world.elevation(note.x, note.y) + .90
			)
			note_sprite.plane = note.plane
			fixed_sprites.append(note_sprite)
		if gallery != null:
			var gallery_sign := Renderer.Sprite.new(25.95, 32.72, "county_gallery_sign", .51, 1.03)
			gallery_sign.plane = 0.0
			fixed_sprites.append(gallery_sign)
			var backstop := Renderer.Sprite.new(29.90, 33.48, "county_gallery_backstop", 1.49, .19)
			backstop.plane = PI / 2.0
			fixed_sprites.append(backstop)
		for room: LevelData.Interior in level.interior_art:
			var room_sprite := Renderer.Sprite.new(
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
				Renderer.Sprite.new(
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


## A side of a block of fixed sprites, in cells.
const SPRITE_BLOCK := 6.0


## `list` in blocks for _seen(): [middle x, middle y, reach, the sprites' places].
## The reach takes in each sprite's half width, from its picture.
func _blocks_of(list: Array) -> Array:
	var by_key := {}
	for i in list.size():
		var s: Renderer.Sprite = list[i]
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
			var s: Renderer.Sprite = list[i]
			var art: Dictionary = renderer.sprite_art(s.image)
			var half := s.height * float(art["w"]) / maxf(1.0, float(art["h"])) * .5
			reach = maxf(reach, Vector2(s.x - mx, s.y - my).length() + half + .3)
		blocks.append([mx, my, reach, places])
	return blocks


## The sprites of `list` in the blocks the view can see, in list order: the
## renderer would skip every other one (behind the eye, past its reach or off
## the side), so leaving them out changes nothing drawn. A level with a mirror
## also keeps what the mirror's view could show.
func _seen(list: Array, blocks: Array) -> Array:
	if view_cone.is_empty():
		return list.duplicate()
	var places := PackedInt32Array()
	for block: Array in blocks:
		if in_view(block[0], block[1], block[2]):
			places.append_array(block[3])
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
			renderer.vw * .5 / renderer.focal + .02,
			edge,
			2.0 * edge - float(view_eye["x"]) if not is_nan(edge) else 0.0
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
	_aim_view()
	var key := _fixed_key()
	if key != fixed_sprites_key:
		fixed_sprites_key = key
		_list_fixed()
	var mill := "prop_windmill_%d" % (int(clock * 5.0) % 3)
	for sprite: Renderer.Sprite in fixed_windmills:
		sprite.image = mill
	var sprites: Array = _seen(fixed_sprites, fixed_blocks)
	if in_hub:
		# plane = 0: these are flat boards fixed in the world, as in the
		# reference, not sprites that turn to face the camera.
		var board_at: Vector2 = level.hub_board
		var shift: Vector2 = board_at - HUB_BOARD
		var dispatch := Renderer.Sprite.new(
			board_at.x, board_at.y, "county_dispatch_%d" % hub_milestone, .46, 1.02
		)
		dispatch.plane = 0.0
		sprites.append(dispatch)
		if hub_milestone != 0:
			var trunk := hub_milestone in [2, 3]
			var prop := "county_dispatch_trunk" if trunk else "county_dispatch_tag"
			var tag := Renderer.Sprite.new(
				29.67 + shift.x, 44.12 + shift.y, prop, .31 if trunk else .24, .83
			)
			tag.plane = 0.0
			sprites.append(tag)
		var detail: int = renderer.world_motion
		var motion_speed: float = [1.0, .32, 0.0][detail]
		var dust_rows: Array = [
			[30.40, 46.85, 1.46, .19], [30.48, 45.95, 1.64, .28], [30.73, 44.95, 1.48, .37]
		]
		var dust: Array = []
		for i in 3 - detail:
			var row: Array = dust_rows[i]
			var dx: float = float(row[0]) + .11 * sin(clock * motion_speed * .68 + float(row[1]))
			var puff := Renderer.Sprite.new(
				dx + shift.x, float(row[1]) + shift.y, "hub_dust", float(row[2]), float(row[3])
			)
			puff.translucent = true
			puff.plane = 0.0
			dust.append(puff)
		dust.sort_custom(
			func(a, b):
				return (
					sqrt(pow(a.x - player.x, 2) + pow(a.y - player.y, 2))
					> sqrt(pow(b.x - player.x, 2) + pow(b.y - player.y, 2))
				)
		)
		sprites.append_array(dust)
		return sprites
	if gallery != null and gallery.active:
		sprites.append(gallery.sprite(self))
	sprites.append_array(_seen(fixed_sprites_late, late_blocks))
	if finale != null and finale.kind == "rudy" and finale.alive:
		for point: Vector2 in world.boss_decoys:
			var decoy := Renderer.Sprite.new(
				point.x, point.y, "rudy_decoy", 1.65, world.elevation(point.x, point.y)
			)
			decoy.plane = 0.0
			sprites.append(decoy)
	for hazard: Hazard in hazards:
		if hazard.age >= hazard.warning:
			var mist := Renderer.Sprite.new(
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
	for enemy: Enemy in enemies:
		# Not even a boss or a corpse reaches 3.5 from where it stands.
		if not in_view(enemy.x, enemy.y, 3.5):
			continue
		var sprite = enemy.sprite(observer, relieved, clock)
		if sprite != null:
			sprite.z += world.elevation(sprite.x, sprite.y)
			sprites.append(sprite)
	for entry in pickups:
		var x := float(entry[1])
		var y := float(entry[2])
		if not in_view(x, y, 1.0):
			continue
		var hover := .06 + sin(clock * 3.5 + x) * .035
		sprites.append(
			Renderer.Sprite.new(
				x, y, "item_" + String(entry[0]), .33, world.elevation(x, y) + hover
			)
		)
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
			var shot_sprite := Renderer.Sprite.new(shot.x, shot.y, "fx_" + name, size, shot.z)
			shot_sprite.glow = Shots.glows(shot.kind)
			sprites.append(shot_sprite)
	sprites.append_array(Features.sprites(self))
	for fx: Speck in specks:
		if not in_view(fx.x, fx.y, .3):
			continue
		var speck_sprite := Renderer.Sprite.new(fx.x, fx.y, "fx_" + fx.kind, .095, fx.z)
		speck_sprite.glow = fx.kind == "spark"
		sprites.append(speck_sprite)
	for puff: Gore.Puff in gore_fx.puffs:
		if not in_view(puff.x, puff.y, 1.6):
			continue
		var hot := puff.kind == "sparks"
		var step := mini(2 if hot else 3, int(puff.age * (14.0 if hot else 11.0)))
		# A puff right in front (a swing at a wall) stays small: at full size it
		# would fill the view.
		var near_k := clampf(Vector2(puff.x - player.x, puff.y - player.y).length() / 2.5, .35, 1.0)
		var cloud := Renderer.Sprite.new(
			puff.x,
			puff.y,
			"fx_%s_%d" % [puff.kind, step],
			(.20 + puff.age * .85) * near_k,
			puff.z - .08 * near_k
		)
		cloud.glow = hot
		cloud.translucent = true
		sprites.append(cloud)
	for g: Gore.Gib in gore_fx.gibs:
		if not in_view(g.x, g.y, g.size + .4):
			continue
		var chunk := Renderer.Sprite.new(g.x, g.y, g.image, g.size, g.z)
		chunk.flip = g.flip
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
	blast_order.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
	for entry in blast_order:
		var blast: Blast = entry[1]
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
		var blast_sprite := Renderer.Sprite.new(
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
	var dx: float = x - float(view_eye["x"])
	var dy: float = y - float(view_eye["y"])
	var ahead := dx * fx + dy * fy
	if ahead < .12:
		return Vector3(0, 0, -1)
	var horizon: float = (
		Renderer.VIEW / 2.0
		+ float(view_eye["pitch"])
		+ float(view_eye["bob"])
		+ float(view_eye["sway"])
	)
	var focal := Renderer.base_focal
	return Vector3(
		Renderer.WIDTH / 2.0 + (dy * fx - dx * fy) / ahead * focal,
		horizon - (z - float(view_eye["eye"])) / ahead * focal,
		ahead
	)


# ---------------------------------------------------------------- objective


func feedback(c: Canvas) -> void:
	if not in_hub:
		var p := player
		var alert = null
		var nearest := 10.5 * 10.5
		for enemy: Enemy in enemies:
			if not (
				enemy.alive
				and enemy.windup > 0.0
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
			var side := "REAR" if absf(alert) > 2.41 else "LEFT" if float(alert) < 0.0 else "RIGHT"
			var label := "WINDUP " + side
			var width := 10 + PixelType.text_width(label, "mini")
			var x := (
				(WIDTH - width) / 2
				if side == "REAR"
				else 6 if side == "LEFT" else WIDTH - width - 6
			)
			HUD.panel(c, x, 74, width, 14, Canvas.rgb(40, 29, 22))
			HUD.text(c, label, x + 5, 78, "mini", Canvas.rgb(233, 188, 111), false, false)
	if item_feedback != null:
		var name := String(item_feedback[0])
		var text := String(item_feedback[1])
		var end := float(item_feedback[2])
		if clock < end:
			var y := 102 + int(round(maxf(0.0, end - clock - .79) * 25.0 * bob_scale))
			var label: String = (
				text if text != "" else String(HUD.ITEM_LABELS[HUD.ITEMS.find(name)])
			)
			HUD.panel(c, 8, y, 29 + PixelType.text_width(label, "mini"), 20, Canvas.rgb(38, 27, 21))
			var image := art.art("item_" + name)
			var iw: int = image["w"]
			var ih: int = image["h"]
			var data: PackedByteArray = image["data"]
			for ty in 16:
				var sy := clampi(ty * ih / 16, 0, ih - 1)
				for tx in 16:
					var sx := clampi(tx * iw / 16, 0, iw - 1)
					var sp := (sy * iw + sx) * 4
					if data[sp + 3] == 0:
						continue
					c.set_pixel(11 + tx, y + 2 + ty, data[sp], data[sp + 1], data[sp + 2])
			HUD.text(c, label, 30, y + 7, "mini", Canvas.rgb(249, 205, 144), false, false)
	if damage_feedback != null:
		var heading = damage_feedback[0]
		var cause := String(damage_feedback[1])
		var end2 := float(damage_feedback[2])
		if clock >= end2:
			return
		var side := ""
		if heading != null and not NO_MARK_SURFACE.has(cause):
			var turn2 := fposmod(float(heading) - player.view_angle() + PI, TAU) - PI
			side = (
				" REAR"
				if absf(turn2) > 2.41
				else " LEFT" if turn2 < -.40 else " RIGHT" if turn2 > .40 else " FRONT"
			)
		HUD.banner(c, cause + side, 87, 288, Canvas.rgb(244, 160, 108))
		if heading != null and not NO_MARK_SURFACE.has(cause):
			_hurt_arc(c, fposmod(float(heading) - player.view_angle() + PI, TAU) - PI, end2)


# ---------------------------------------------------------------- main draw


func draw(c: Canvas, crosshair := 1, grade := true) -> void:
	_draw(c, crosshair, grade)
	if _render_open:
		# The band threads drew the view while the weapon and HUD were painted.
		_render_open = false
		var began := Time.get_ticks_usec()
		renderer.render_end()
		stage_ms[1] += (Time.get_ticks_usec() - began) / 1000.0


func _draw(c: Canvas, crosshair: int, grade: bool) -> void:
	var p := player
	look_live = false
	tone_live = false
	hurt_alpha = 0
	scene_live = false
	drunk_k = 0.0
	c.layer = false
	if showing_tally:
		hud.intermission(c, self)
		return
	var practice := gallery != null and gallery.active
	var weapon = gallery.pistol if practice else armory
	var flash: float = (weapon.flash * 4.0 + blast_flash * .85) * flash_scale
	renderer.time = clock
	renderer.layered = layered and gpu_look
	if renderer.detail < 0 and not renderer.layered:
		# HD is the display shader's: the software view draws at HIGH.
		renderer.set_detail(0)
	var t0 := Time.get_ticks_usec()
	# The renderer sorts out the wall segments on a band thread while the
	# sprites and marks are listed here.
	var eye := p.as_render_player()
	var trauma := shake * shake * shake_scale
	if trauma > .001:
		# The view shakes, the gun does not: a jolt of yaw and of horizon.
		eye["view_angle"] += (sin(clock * 71.0) + sin(clock * 43.0 + 1.3)) * .009 * trauma
		eye["pitch"] += (sin(clock * 59.0 + .7) + sin(clock * 37.0)) * 2.4 * trauma
	renderer.frame_begin(eye, flash)
	view_eye = eye
	var listing := Time.get_ticks_usec()
	var marks: Array = ground_marks()
	var marks_list: Array = wall_marks if bullet_marks else []
	if not gore_fx.walls.is_empty():
		marks_list = marks_list + gore_fx.walls
	var listed: Array = sprites()
	var t1 := Time.get_ticks_usec()
	renderer.frame_sprites(listed, reflection(), marks_list, marks)
	if renderer.layered:
		# The display shader composes the view from the renderer's layers; the
		# weapon and the HUD are painted on an empty layer that goes over it,
		# and that happens here while the band threads are still drawing.
		c.begin_layer()
		scene_live = true
		_render_open = true
	else:
		# render_end() hands back a private copy so the HUD, weapon and grade passes
		# can composite into it while the renderer keeps its own band buffers untouched.
		c.pixels = renderer.render_end()
		c.base_set = true
	var t2 := Time.get_ticks_usec()
	# What the features draw over the view (tracers, the milk, sparks), under the gun.
	c.view_tint = Color(1, 1, 1)
	if weapon.has_method("place_muzzle"):
		weapon.place_muzzle(p, bob_scale, 12 if weapon_view == 1 else 0)
	if c.gpu:
		c.gpu_item(Canvas.ITEM_NORMAL_VIEW)
	Features.draw_view(self, c)
	if c.gpu:
		c.gpu_item(Canvas.ITEM_NORMAL)
	c.view_tint = gun_light() if c.gpu and Effects.enabled else Color(1, 1, 1)
	if p.health > 0 and not in_hub and (weapon_view != 2 or armory.fuse > 0.0):
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
			_drunk_warp(c)
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
			var table = tone if grade else null
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
		if callout_until > clock and not map:
			# A kill streak's call, big, shaking a little as it lands.
			var fresh := 1.3 - (callout_until - clock)
			var jolt := int(maxf(0.0, .2 - fresh) * 20.0 * shake_scale)
			HUD.text(c, callout, 160 + jolt, 30, "heading", HUD.AMBER, true)
		var after_notice := 5
		if not map:
			if practice:
				after_notice = HUD.banner(c, gallery.hud(), 5) + 3
			elif message_until > clock and (hints or notice != level.introduction):
				after_notice = HUD.banner(c, notice, 5) + 3
			elif district_labels and district_until > clock:
				after_notice = (
					HUD.banner(c, level.districts[district], 5, 288, Canvas.rgb(245, 196, 122)) + 3
				)
			var boss = (
				finale if finale != null else (jerry if jerry != null and jerry.alive else boss)
			)
			if boss != null:
				var in_finale: bool = (
					sqrt((boss.x - p.x) * (boss.x - p.x) + (boss.y - p.y) * (boss.y - p.y)) < 14.0
					if finale != null
					else p.y < 10.0
				)
				if in_finale and boss.alive and boss.alerted and not in_hub:
					var y := after_notice
					var tell: String = String(
						Enemy.TELLS.get(
							boss.kind, "PLASMA CHARGE" if boss == self.boss else "WHISTLE"
						)
					)
					if boss.brain == "baron" and boss.attacks % 2 == 1:
						tell = "STEAM SWEEP"
					if boss.brain == "foreman" and boss.attacks % 2 == 1:
						tell = "GAP IN THE MIDDLE"
					if boss.brain == "rudy":
						tell = "LEFT HORN" if boss.attacks % 2 == 1 else "RIGHT HORN"
					if BayouBrains.is_king(boss) and boss.aim_mark != null:
						var toward := atan2(boss.aim_mark[1] - boss.y, boss.aim_mark[0] - boss.x)
						var run := BayouBrains.runs_on(boss, boss.attacks + 1, world, toward)
						tell = "AIRBOAT RUN" if run else "PUNT GUN"
					var phase: String = (
						tell if boss.windup > 0.0 else "RECOVERING" if boss.recovery > .16 else ""
					)
					if boss.enraged and clock - boss.enraged_at < 1.6:
						phase = "FIGHTIN' MAD"
					HUD.panel(
						c,
						193,
						y,
						122,
						27 if phase != "" else 20,
						Canvas.rgb(35, 24, 20),
						Canvas.rgb(126, 85, 57)
					)
					HUD.text(c, _boss_title(boss.kind), 253, y + 3, "body", HUD.INK, true, false)
					c.fill_rect(199, y + 12, 110, 4, Canvas.rgb(70, 42, 32))
					c.fill_rect(
						199,
						y + 12,
						int(round(110.0 * boss.hp / boss.max_hp)),
						4,
						Canvas.rgb(236, 143, 69) if boss.windup > 0.0 else Canvas.rgb(204, 77, 47)
					)
					if phase != "":
						HUD.text(
							c, phase, 253, y + 19, "mini", Canvas.rgb(249, 194, 124), true, false
						)
		if not map and armory.fuse == 0.0:
			var hint := gate_prompt()
			if hint == "" and hints and not in_hub:
				hint = use_prompt()
			if hint != "":
				HUD.banner(c, hint, 137, 288, Canvas.rgb(251, 207, 142))
			if voice_captions and caption_until > clock:
				HUD.banner(c, caption, 121 if hint != "" else 137, 288, Canvas.rgb(209, 221, 179))
			elif barks.visible(self) and hint == "":
				HUD.banner(c, '"' + barks.text + '"', 137, 288, Canvas.rgb(255, 214, 150))
		if not map:
			feedback(c)
	else:
		HUD.panel(c, 27, 54, 266, 52, Canvas.rgb(43, 26, 22))
		HUD.text(c, "YOU BOUGHT THE FARM", 160, 64, "heading", HUD.INK, true)
		HUD.text(
			c,
			(
				"ENTER CROSSROADS  /  ESC TITLE"
				if revisiting
				else "ENTER RETRY  /  F9 QUICKLOAD  /  ESC TITLE"
			),
			160,
			90,
			"body",
			HUD.INK,
			true
		)
	if map and p.health > 0:
		automap(c)
	gore_fx.draw_lens(c)
	hud.draw(c, self, weapon)
	stage_ms[4] = (Time.get_ticks_usec() - t4) / 1000.0


## This frame's lights for the graphics-card view (effects.cfg): the gun's
## flash, blasts, glowing shots, lamps and trigger lights, nearest first, at
## most Effects.MAX_LIGHTS of them.
func effect_lights() -> Array:
	var p := player
	var found: Array = []
	if armory.flash > 0.0:
		var aim := p.view_angle()
		found.append(
			Effects.light(
				"muzzle",
				p.x + cos(aim) * .45,
				p.y + sin(aim) * .45,
				p.eye - .1,
				armory.flash / .072
			)
		)
	for blast: Blast in blasts:
		var source := "blast_energy" if blast.kind == "energy" else "blast_fire"
		if blast.kind != "energy" and blast.kind != "fire":
			continue
		var life := float(Effects.LIGHTS.get(source, {}).get("life", .64))
		found.append(
			Effects.light(source, blast.x, blast.y, blast.z, 1.0 - blast.age / maxf(life, .01))
		)
	for shot in shots:
		if Effects.LIGHTS.has("shot_" + String(shot.kind)):
			found.append(Effects.light("shot_" + String(shot.kind), shot.x, shot.y, shot.z))
	var lamps_key := Vector2i(world.get_instance_id(), props.size())
	if lamps_key != lamps_of:
		lamps_of = lamps_key
		lamp_props = props.filter(func(spr): return spr.image == "prop_lamp")
		lamp_boards = world.billboards.filter(
			func(board): return board.glow and board.image == "hub_lamp"
		)
	for spr: Renderer.Sprite in lamp_props:
		if absf(spr.x - p.x) < 12.0 and absf(spr.y - p.y) < 12.0:
			found.append(Effects.light("lamp", spr.x, spr.y, spr.z, 1.0, clock))
	# Street lamps pool their light on the ground; the keys glint where they lie.
	for board: LevelData.Billboard in lamp_boards:
		if absf(board.x - p.x) < 14.0 and absf(board.y - p.y) < 14.0:
			var top := world.elevation(board.x, board.y) + board.z + board.height * .9
			found.append(Effects.light("streetlamp", board.x, board.y, top, 1.0, clock))
	for entry: Array in pickups:
		var item := String(entry[0])
		if item.begins_with("key_") and absf(float(entry[1]) - p.x) < 10.0:
			if absf(float(entry[2]) - p.y) < 10.0:
				var x := float(entry[1])
				var y := float(entry[2])
				found.append(Effects.light(item, x, y, world.elevation(x, y) + .4, 1.0, clock))
	for l: Array in trigger_lights:
		if clock < float(l[6]):
			found.append([l[0], l[1], l[2], l[3], l[4], l[5]])
	var lights: Array = []
	for l in found:
		if l != null:
			var dx: float = l[0] - p.x
			var dy: float = l[1] - p.y
			lights.append([dx * dx + dy * dy, l])
	lights.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	var out: Array = []
	for i in mini(Effects.MAX_LIGHTS, lights.size()):
		out.append(lights[i][1])
	return out


## The light on the gun: the frame's lights where the player stands (a blast
## turns it orange, a lamp warms it, its own flash brightens it), the level's
## tint and a lightning flash. White is the gun as drawn.
func gun_light() -> Color:
	var p := player
	var sum := Vector3.ONE
	for l: Array in effect_lights():
		var reach := clampf(
			1.0 - Vector3(p.x, p.y, p.eye).distance_to(Vector3(l[0], l[1], l[2])) / float(l[3]),
			0,
			1
		)
		var c: Color = l[4]
		sum += Vector3(c.r, c.g, c.b) * float(l[5]) * reach * reach
	var tone: Color = Effects.mood(level.id, "grade", Color(1, 1, 1))
	sum *= Vector3(tone.r, tone.g, tone.b) * (1.0 + lightning * .5)
	return Color(minf(sum.x, 1.8), minf(sum.y, 1.8), minf(sum.z, 1.8))


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


## Four short ticks around the crosshair when a hit lands; red and wider on a kill.
func _hit_mark(c: Canvas) -> void:
	var gap := 4 if hit_mark_kill else 3
	var r := 236 if hit_mark_kill else 246
	var g := 72 if hit_mark_kill else 228
	var b := 48 if hit_mark_kill else 190
	for k in 3:
		var d := gap + k
		c.set_pixel(160 - d, VIEW / 2 - d, r, g, b)
		c.set_pixel(160 + d, VIEW / 2 - d, r, g, b)
		c.set_pixel(160 - d, VIEW / 2 + d, r, g, b)
		c.set_pixel(160 + d, VIEW / 2 + d, r, g, b)


func _boss_title(kind: String) -> String:
	return String(
		(
			{
				"boss": "ALIEN SHERIFF",
				"jerry": "JERRY JONES",
				"rudy": "RUDY RACKET",
				"foreman": "SPLINTER FOREMAN",
				"baron": "COPPER BARON"
			}
			. get(kind, Enemy.BOSS_TITLES.get(kind, "BOSS"))
		)
	)


# ------------------------------------------------------------- view effects


func _build_grit() -> void:
	var count := WIDTH * VIEW
	_grit_r.resize(count)
	_grit_g.resize(count)
	_grit_b.resize(count)
	_dither.resize(count)
	var wash: Array = WASH.get(level.id, [255, 255, 255, 0])
	var amount := float(wash[3])
	var tr := float(wash[0]) / 255.0
	var tg := float(wash[1]) / 255.0
	var tb := float(wash[2]) / 255.0
	var w := float(maxi(WIDTH - 1, 1))
	var h := float(maxi(VIEW - 1, 1))
	for y in VIEW:
		var ny := (float(y) / h - .5) * 2.0
		for x in WIDTH:
			var nx := (float(x) / w - .5) * 2.0
			var radius := sqrt(nx * nx + ny * ny) / 1.4142
			var vignette := 1.0 - .13 * pow(radius, 2.1)
			var i := y * WIDTH + x
			_grit_r[i] = ((1.0 - amount) + tr * amount) * vignette
			_grit_g[i] = ((1.0 - amount) + tg * amount) * vignette
			_grit_b[i] = ((1.0 - amount) + tb * amount) * vignette
			_dither[i] = (float(BAYER[(x % 4) * 4 + (y % 4)]) / 16.0 - .5) * 6.0


func _apply_hurt_flash(c: Canvas) -> void:
	var alpha := clampi(int(round(hurt_flash * 310.0 * flash_scale)), 0, 255)
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


## rampage2.drunk_warp: per-row sine shear, ghost double image, amber tint.
func _drunk_warp(c: Canvas) -> void:
	var drunk := player.drunk
	if drunk < 38.0:
		return
	var strength := minf(1.0, (drunk - 38.0) / 62.0)
	var width := WIDTH
	var source := PackedByteArray()
	source.resize(width * VIEW * 3)
	var shift := PackedInt32Array()
	shift.resize(VIEW)
	for y in VIEW:
		shift[y] = int(round(sin(y * .16 + clock * 3.1) * (1.0 + 3.4 * strength)))
	var pix := c.pixels
	for y in VIEW:
		var row := y * width * 3
		var offset := shift[y]
		for x in width:
			var sx := posmod(x + offset, width)
			var sp := row + sx * 3
			var dp := row + x * 3
			source[dp] = pix[sp]
			source[dp + 1] = pix[sp + 1]
			source[dp + 2] = pix[sp + 2]
	var ghost_dx := int(2 + 4 * strength)
	if sin(clock * 1.7) <= 0.0:
		ghost_dx = -ghost_dx
	var mix := .30 * strength
	for y in VIEW:
		var row := y * width * 3
		for x in width:
			var gx := posmod(x - ghost_dx, width)
			var gp := row + gx * 3
			var dp := row + x * 3
			var r := float(source[dp]) * (1.0 - mix) + float(source[gp]) * mix
			var g := float(source[dp + 1]) * (1.0 - mix) + float(source[gp + 1]) * mix
			var b := float(source[dp + 2]) * (1.0 - mix) + float(source[gp + 2]) * mix
			pix[dp] = clampi(int(r * (1.0 + .06 * strength)), 0, 255)
			pix[dp + 1] = clampi(int(g), 0, 255)
			pix[dp + 2] = clampi(int(b * (1.0 - .10 * strength)), 0, 255)


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
	_look_gain = gain
	_look_frame = int(clock * 17.0) % GRAIN_FRAMES
	_look_blast = blast_flash * 60.0


func _look_pass(c: Canvas, grade_tone = null) -> void:
	_look_params()
	_look_tone = grade_tone
	# Row-banded across explicit threads. This pass is ~10 ms of per-pixel float
	# work at 50k pixels, so it is worth splitting. Each worker owns a private
	# output buffer for its own rows; only writes need a single owner, and a
	# shared buffer would make every worker detach on its first write (packed
	# arrays are copy-on-write). The bands are concatenated natively with
	# append_array, and the status rows below VIEW are carried over verbatim.
	var src := c.pixels
	var view_bytes := WIDTH * VIEW * 3
	var bands := _look_band_count()
	if bands <= 1:
		var dst := src.slice(0)
		_look_rows(dst, src, 0, VIEW)
		c.pixels = dst
		return
	_look_rows_per = int(ceil(float(VIEW) / bands))
	while _look_threads.size() < bands:
		_look_threads.append(Thread.new())
	for i in bands:
		var t: Thread = _look_threads[i]
		if t.is_started():
			t.wait_to_finish()
		t.start(_look_worker.bind(src, i))
	# Each worker builds and returns its own buffer, so no band ever writes into
	# memory another thread can see; the main thread collects the results.
	var out := PackedByteArray()
	for i in bands:
		var part: PackedByteArray = _look_threads[i].wait_to_finish()
		if part.size() > 0:
			out.append_array(part)
	if src.size() > view_bytes:
		out.append_array(src.slice(view_bytes))
	c.pixels = out


func _look_band_count() -> int:
	if VIEW < 48 or not OS.has_feature("threads"):
		return 1
	if look_bands > 0:
		return mini(look_bands, VIEW)
	# Four bands measured fastest: the renderer already fills the machine with
	# its own band threads, and more look workers just contend with them.
	return mini(4, VIEW)


func _look_worker(src: PackedByteArray, slot: int) -> PackedByteArray:
	var y0 := slot * _look_rows_per
	var y1 := mini(VIEW, y0 + _look_rows_per)
	if y0 >= y1:
		return PackedByteArray()
	# Private buffer: one owner, so the band write cannot race with a detach.
	var part := PackedByteArray()
	part.resize((y1 - y0) * WIDTH * 3)
	_look_rows(part, src, y0, y1)
	return part


## Apply the look + tone passes to rows [y0, y1) of `src`, writing them into
## `dst` starting at its row 0. Both buffers are row-aligned to `y0`.
func _look_rows(dst: PackedByteArray, src: PackedByteArray, y0: int, y1: int) -> void:
	var grain := art.grain
	var grit_r := _grit_r
	var grit_g := _grit_g
	var grit_b := _grit_b
	var dither := _dither
	var tone = _look_tone
	var gain := _look_gain
	var blast_add := _look_blast
	var frame_index := _look_frame
	# Yields: the reference runs look_pass over (0,0,WIDTH,VIEW) and then the
	# brightness grade over the same rectangle, so folding the two passes
	# together here produces identical pixels for half the memory traffic.
	var dst_row := 0
	var y := y0
	while y < y1:
		var i := y * WIDTH
		var o := dst_row
		var so := i * 3
		var gx := frame_index * VIEW + y
		var x := 0
		while x < WIDTH:
			var add := float(int(grain[gx]) - 2) + blast_add + dither[i]
			var r := clampi(int(float(src[so]) * (grit_r[i] * gain) + add), 0, 255)
			var g := clampi(int(float(src[so + 1]) * (grit_g[i] * gain) + add), 0, 255)
			var b := clampi(int(float(src[so + 2]) * (grit_b[i] * gain) + add), 0, 255)
			if tone != null:
				dst[o] = tone[r]
				dst[o + 1] = tone[g]
				dst[o + 2] = tone[b]
			else:
				dst[o] = r
				dst[o + 1] = g
				dst[o + 2] = b
			gx += GRAIN_STRIDE
			i += 1
			o += 3
			so += 3
			x += 1
		dst_row += WIDTH * 3
		y += 1


func _grade_view(c: Canvas) -> void:
	var pix := c.pixels
	var n := WIDTH * VIEW * 3
	for i in n:
		pix[i] = tone[pix[i]]


# ----------------------------------------------------------------- automap

## The map over the view: the window it shows the level in, with two lines of
## text under it (the status bar stays below).
const MAP_X := 6
const MAP_Y := 6
const MAP_W := 308
const MAP_H := 126
## Pixels a cell at each zoom; 0 fits the whole level in the window.
const MAP_ZOOMS := [0.0, 2.0, 3.0, 4.0]
const MAP_BACK := Color8(22, 17, 13)
const MAP_WALL := Color8(214, 178, 118)
## Ground not walked yet, then walked: under the sky, under a roof, water.
const MAP_GROUND := [Color8(54, 58, 47), Color8(70, 58, 45), Color8(44, 68, 72)]
## A wall's own mass, against the void beyond the level.
const MAP_MASS := Color8(40, 31, 23)
const MAP_WALKED := [Color8(104, 92, 64), Color8(132, 104, 72), Color8(66, 104, 110)]


func automap(c: Canvas) -> void:
	var region := _map_region()
	var scale := _map_scale(region)
	if _map_image == null or _map_built_scale != scale or _map_signature_changed():
		_build_map_image(region, scale)
	_paint_walked(region, scale)
	# The window follows the player (clamped to the level), or shows it all.
	var full := Vector2(region.size) * scale
	var origin := Vector2.ZERO
	for k in 2:
		var span: float = MAP_W if k == 0 else MAP_H
		var at: float = (player.x if k == 0 else player.y) - float(region.position[k])
		if full[k] <= span:
			origin[k] = -(span - full[k]) / 2.0
		else:
			origin[k] = clampf(at * scale - span / 2.0, 0.0, full[k] - span)
	_map_origin = origin.floor()
	_map_scale_now = scale
	_map_region_now = region
	c.fill_rect(MAP_X - 4, MAP_Y - 4, MAP_W + 8, 152, Canvas.rgb(30, 23, 18))
	c.rect_outline(MAP_X - 4, MAP_Y - 4, MAP_W + 8, 152, Canvas.rgb(149, 117, 81))
	c.rect_outline(MAP_X - 1, MAP_Y - 1, MAP_W + 2, MAP_H + 2, Canvas.rgb(84, 64, 45))
	_blit_map(c)
	if not in_hub:
		for door: LevelData.Door in world.doors:
			if not door.secret or door.discovered:
				var color := (
					Canvas.rgb(110, 136, 90)
					if door.opened
					else Canvas.rgb(222, 128, 52) if door.key != "" else Canvas.rgb(176, 132, 82)
				)
				_map_cell_mark(c, float(door.x), float(door.y), color)
	for station: LevelData.Station in world.stations:
		if not station.reveals_secret and (not station.hidden or stations_done.has(station.id)):
			var at2 := _map_point(station.x, station.y)
			if _map_shows(at2):
				var done := stations_done.has(station.id)
				var mark := Canvas.rgb(151, 187, 110) if done else Canvas.rgb(236, 168, 84)
				c.fill_rect(int(at2.x) - 2, int(at2.y) - 2, 5, 5, Canvas.rgb(22, 17, 13))
				c.fill_rect(int(at2.x) - 1, int(at2.y) - 1, 3, 3, mark)
	if world.extraction != null:
		var at3 := _map_point(world.extraction.x, world.extraction.y)
		if _map_shows(at3):
			c.circle(
				int(at3.x),
				int(at3.y),
				3,
				Canvas.rgb(151, 187, 110) if exit_ready() else Canvas.rgb(190, 110, 84),
				false
			)
	_map_labels(c)
	_map_goal(c)
	_map_player(c)
	c.line(MAP_X, MAP_Y + MAP_H + 3, MAP_X + MAP_W - 1, MAP_Y + MAP_H + 3, Canvas.rgb(120, 87, 59))
	HUD.text(
		c,
		objective() if hints else level.title,
		160,
		MAP_Y + MAP_H + 6,
		"body",
		Canvas.rgb(248, 199, 127),
		true
	)
	var tally := (
		"ROAD NOTES %d/%d" % [hub_findings.size(), world.hub_clues.size()]
		if in_hub
		else "SECRETS %d/%d" % [secrets, total_secrets]
	)
	HUD.text(
		c,
		tally + ("   /   TAP TO ZOOM" if touch_aim else "   /   PGUP PGDN ZOOM   /   TAB CLOSE"),
		160,
		MAP_Y + MAP_H + 15,
		"body",
		HUD.INK,
		true
	)


## The part of the level the map covers, in cells: all of it, or the
## Crossroads' own window of hub.json.
func _map_region() -> Rect2i:
	if in_hub and not level.map_window.is_empty():
		var wnd: Array = level.map_window
		return Rect2i(int(wnd[0]), int(wnd[1]), int(wnd[2]), int(wnd[3]))
	return Rect2i(0, 0, int(world.width), int(world.height))


func _map_scale(region: Rect2i) -> float:
	var fit := minf(float(MAP_W) / region.size.x, float(MAP_H) / region.size.y)
	var zoom: float = MAP_ZOOMS[clampi(map_zoom, 0, MAP_ZOOMS.size() - 1)]
	return fit if zoom <= 0.0 or zoom <= fit else zoom


func _map_signature_changed() -> bool:
	var signature: Array = []
	for door: LevelData.Door in world.doors:
		if door.secret and not door.discovered:
			signature.append(Vector2i(door.x, door.y))
	return signature != map_signature


## The whole map at this scale, in an image: ground by kind, walls drawn as
## lines along every edge between open ground and a wall. Ground still hidden
## behind a secret door stays dark.
func _build_map_image(region: Rect2i, scale: float) -> void:
	var signature: Array = []
	for door: LevelData.Door in world.doors:
		if door.secret and not door.discovered:
			signature.append(Vector2i(door.x, door.y))
	map_signature = signature
	_map_hidden.clear()
	for point: Vector2i in signature:
		_map_hidden[point] = true
		for room in level.hidden_rooms:
			if room[0] == point:
				var box: Vector4i = room[1]
				for yy in range(box.y, box.w + 1):
					for xx in range(box.x, box.z + 1):
						_map_hidden[Vector2i(xx, yy)] = true
	var size := (Vector2(region.size) * scale).ceil()
	_map_image = Image.create_empty(
		maxi(1, int(size.x)), maxi(1, int(size.y)), false, Image.FORMAT_RGB8
	)
	_map_image.fill(MAP_BACK)
	_map_built_scale = scale
	_map_region_now = region
	_map_painted = 0
	for yy in range(region.position.y, region.end.y):
		for xx in range(region.position.x, region.end.x):
			if _map_open(xx, yy):
				_map_paint_cell(xx, yy, false)


func _map_open(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= world.width or y >= world.height:
		return false
	return int(world.solid[y * int(world.width) + x]) < 0 and not _map_hidden.has(Vector2i(x, y))


func _map_cell_rect(x: int, y: int) -> Rect2i:
	var region := _map_region_now
	var s := _map_built_scale
	var x0 := int(roundf((x - region.position.x) * s))
	var y0 := int(roundf((y - region.position.y) * s))
	var x1 := int(roundf((x - region.position.x + 1) * s))
	var y1 := int(roundf((y - region.position.y + 1) * s))
	return Rect2i(x0, y0, maxi(1, x1 - x0), maxi(1, y1 - y0))


## One cell of ground, walked or not, with its wall edges.
func _map_paint_cell(x: int, y: int, walked: bool) -> void:
	var cell := y * int(world.width) + x
	var kind := 0 if world.roof[cell] == 0.0 else 1
	if world.surface_sound(int(world.floor_tile[cell])) == "water":
		kind = 2
	var r := _map_cell_rect(x, y)
	_map_image.fill_rect(r, (MAP_WALKED if walked else MAP_GROUND)[kind])
	var line := 2 if _map_built_scale >= 4.0 else 1
	for k: Vector2i in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		var n := Vector2i(x, y) + k
		if not _map_open(n.x, n.y) and _map_region_now.has_point(n):
			_map_image.fill_rect(_map_cell_rect(n.x, n.y), MAP_MASS)
	if not _map_open(x - 1, y):
		_map_image.fill_rect(Rect2i(r.position.x, r.position.y, line, r.size.y), MAP_WALL)
	if not _map_open(x + 1, y):
		_map_image.fill_rect(Rect2i(r.end.x - line, r.position.y, line, r.size.y), MAP_WALL)
	if not _map_open(x, y - 1):
		_map_image.fill_rect(Rect2i(r.position.x, r.position.y, r.size.x, line), MAP_WALL)
	if not _map_open(x, y + 1):
		_map_image.fill_rect(Rect2i(r.position.x, r.end.y - line, r.size.x, line), MAP_WALL)


## The ground walked since the image was last brought up to date.
func _paint_walked(region: Rect2i, _scale: float) -> void:
	var keys: Array = visited.keys()
	for i in range(_map_painted, keys.size()):
		var key: Vector2i = keys[i]
		if region.has_point(key) and _map_open(key.x, key.y):
			_map_paint_cell(key.x, key.y, true)
	_map_painted = keys.size()


## Where a point of the level is on the canvas, this frame.
func _map_point(x: float, y: float) -> Vector2:
	return Vector2(
		MAP_X + (x - _map_region_now.position.x) * _map_scale_now - _map_origin.x,
		MAP_Y + (y - _map_region_now.position.y) * _map_scale_now - _map_origin.y
	)


func _map_shows(at: Vector2) -> bool:
	return at.x >= MAP_X and at.y >= MAP_Y and at.x < MAP_X + MAP_W and at.y < MAP_Y + MAP_H


func _map_cell_mark(c: Canvas, x: float, y: float, color: Color) -> void:
	var a := _map_point(x, y)
	var b := _map_point(x + 1.0, y + 1.0)
	var x0 := maxi(MAP_X, int(a.x))
	var y0 := maxi(MAP_Y, int(a.y))
	var x1 := mini(MAP_X + MAP_W, maxi(int(b.x), int(a.x) + 1))
	var y1 := mini(MAP_Y + MAP_H, maxi(int(b.y), int(a.y) + 1))
	if x1 > x0 and y1 > y0:
		c.fill_rect(x0, y0, x1 - x0, y1 - y0, color)


func _map_labels(c: Canvas) -> void:
	var labels: Array = []
	if in_hub:
		for gate: LevelData.Gate in world.hub_gates:
			labels.append(
				[
					String(Campaign.GATE_LABELS.get(gate.destination, "")),
					gate.x,
					gate.y,
					not world.locked_gates.has(gate)
				]
			)
		for clue in world.hub_clues:
			if hub_findings.has(String(clue[0])):
				var at := _map_point(float(clue[1]), float(clue[2]))
				if _map_shows(at):
					c.polygon(
						[
							Vector2(at.x, at.y - 3),
							Vector2(at.x + 3, at.y),
							Vector2(at.x, at.y + 3),
							Vector2(at.x - 3, at.y)
						],
						Canvas.rgb(200, 173, 111)
					)
	else:
		for row in level.map_labels:
			labels.append([String(row[0]), float(row[1]), float(row[2]), true])
	var placed: Array[Rect2i] = []
	for label_row in labels:
		var label := String(label_row[0])
		if label == "":
			continue
		var at := _map_point(float(label_row[1]), float(label_row[2]))
		var wide := PixelType.text_width(label)
		var left := int(at.x) - wide / 2
		if left < MAP_X + 1 or left + wide > MAP_X + MAP_W - 1:
			continue
		if at.y < MAP_Y + 1 or at.y > MAP_Y + MAP_H - 9:
			continue
		# Zoomed out, names that would sit on each other: the first one only.
		var box := Rect2i(left - 3, int(at.y) - 2, wide + 6, 11)
		var crowded := false
		for other: Rect2i in placed:
			if other.intersects(box):
				crowded = true
				break
		if crowded:
			continue
		placed.append(box)
		c.fill_rect(left - 2, int(at.y) - 1, wide + 4, 9, Canvas.rgb(30, 23, 18))
		HUD.text(
			c,
			label,
			left,
			int(at.y),
			"body",
			Canvas.rgb(244, 223, 185) if bool(label_row[3]) else Canvas.rgb(185, 123, 85),
			false,
			false
		)


## Where the objective pin points: a blinking diamond, or an arrow on the
## window's edge pointing to it when it is off the map.
func _map_goal(c: Canvas) -> void:
	var goal = objective_target()
	if goal == null or not (goal is Vector2):
		return
	var at := _map_point(goal.x, goal.y)
	var color := (
		Canvas.rgb(255, 214, 110) if int(clock * 3.0) % 2 == 0 else Canvas.rgb(214, 120, 60)
	)
	if _map_shows(at):
		c.polygon(
			[
				Vector2(at.x, at.y - 4),
				Vector2(at.x + 4, at.y),
				Vector2(at.x, at.y + 4),
				Vector2(at.x - 4, at.y)
			],
			color
		)
		return
	var middle := Vector2(MAP_X + MAP_W / 2.0, MAP_Y + MAP_H / 2.0)
	var way := (at - middle).normalized()
	var reach := minf(
		(MAP_W / 2.0 - 6.0) / maxf(.001, absf(way.x)), (MAP_H / 2.0 - 6.0) / maxf(.001, absf(way.y))
	)
	var tip := middle + way * reach
	var side := Vector2(-way.y, way.x)
	c.polygon([tip + way * 4.0, tip - way * 3.0 + side * 3.5, tip - way * 3.0 - side * 3.5], color)


func _map_player(c: Canvas) -> void:
	var at := _map_point(player.x, player.y)
	var way := Vector2(cos(player.angle), sin(player.angle))
	var side := Vector2(-way.y, way.x)
	var size := clampf(_map_scale_now * 1.4, 3.0, 5.0)
	var tip := at + way * size * 1.3
	var back_l := at - way * size * .8 + side * size * .8
	var back_r := at - way * size * .8 - side * size * .8
	c.polygon([tip, back_l, at - way * size * .3, back_r], Canvas.rgb(255, 170, 80))
	c.line(int(tip.x), int(tip.y), int(back_l.x), int(back_l.y), Canvas.rgb(70, 32, 14))
	c.line(int(tip.x), int(tip.y), int(back_r.x), int(back_r.y), Canvas.rgb(70, 32, 14))


## The visible part of the map image into the window.
func _blit_map(c: Canvas) -> void:
	var src := Rect2i(maxi(0, int(_map_origin.x)), maxi(0, int(_map_origin.y)), 0, 0)
	var dst := Vector2i(MAP_X + maxi(0, -int(_map_origin.x)), MAP_Y + maxi(0, -int(_map_origin.y)))
	src.size = Vector2i(
		mini(_map_image.get_width() - src.position.x, MAP_X + MAP_W - dst.x),
		mini(_map_image.get_height() - src.position.y, MAP_Y + MAP_H - dst.y)
	)
	if src.size.x <= 0 or src.size.y <= 0:
		return
	var crop := _map_image.get_region(src)
	if c.gpu:
		if _map_texture == null or _map_texture.get_size() != Vector2(src.size):
			_map_texture = ImageTexture.create_from_image(crop)
		else:
			_map_texture.update(crop)
		c.gpu_texture(_map_texture, dst.x, dst.y, src.size.x, src.size.y)
		return
	var data := crop.get_data()
	var pix := c.pixels
	var row_bytes := src.size.x * 3
	for row in src.size.y:
		var from := row * row_bytes
		var to := ((dst.y + row) * Canvas.WIDTH + dst.x) * 3
		for k in row_bytes:
			pix[to + k] = data[from + k]
		if c.layer:
			var at := (dst.y + row) * Canvas.WIDTH + dst.x
			for k in src.size.x:
				c.cover[at + k] = 255

# ------------------------------------------------------------------ controls
