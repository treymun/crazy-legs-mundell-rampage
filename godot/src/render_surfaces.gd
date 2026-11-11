## The renderer's surfaces: wall segments, wall spans, the sky, floors and
## ceilings, and the window-pane wash (the layers are listed in
## render_state.gd).
class_name RenderSurfaces
extends RenderState


func _prepare(segments: PackedFloat32Array) -> void:
	walls = segments
	seg_n = segments.size() / WALL_STRIDE
	seg_c0.resize(seg_n)
	seg_c1.resize(seg_n)
	seg_order.clear()
	cov_top.resize(vw)
	cov_bot.resize(vw)
	cov_t.resize(vw)
	cov_top.fill(vh)
	cov_bot.fill(-1)
	cov_t.fill(0.0)
	glass_cols.resize(vw)
	glass_cols.fill(0)
	for i in seg_n:
		var o := i * WALL_STRIDE
		var r0x := segments[o] - cx
		var r0y := segments[o + 1] - cy
		var r1x := segments[o + 2] - cx
		var r1y := segments[o + 3] - cy
		var a0 := r0x * fx + r0y * fy
		var a1 := r1x * fx + r1y * fy
		if a0 <= .0001 and a1 <= .0001:
			seg_c0[i] = 0
			seg_c1[i] = 0
			continue
		var s0 := r0x * rx + r0y * ry
		var s1 := r1x * rx + r1y * ry
		if a0 < .02:
			var f := (a0 - .02) / (a0 - a1)
			a0 = .02
			s0 += (s1 - s0) * f
		elif a1 < .02:
			var f := (a1 - .02) / (a1 - a0)
			a1 = .02
			s1 += (s0 - s1) * f
		var m0 := vw / 2.0 + s0 / a0 * focal - .5
		var m1 := vw / 2.0 + s1 / a1 * focal - .5
		seg_c0[i] = maxi(col0, int(floorf(minf(m0, m1))) - 1)
		seg_c1[i] = mini(col1, int(ceilf(maxf(m0, m1))) + 2)
		if seg_c0[i] < seg_c1[i]:
			seg_order.append(int(minf(a0, a1) * 4096.0) * 65536 + i)
	seg_order.sort()


# -------------------------------------------------------------------- sky
func _sky_band(a: int, b: int) -> void:
	var data: PackedByteArray = sky["data"]
	var scale := 512.0 / TAU_
	var n := b - a
	var col_off := PackedInt32Array()
	col_off.resize(n)
	for i in n:
		var ang := view_angle + parity * atan(rays[a + i])
		col_off[i] = (int(ang * scale) & 511) * 3
	var row_off := PackedInt32Array()
	row_off.resize(vh)
	for r in vh:
		row_off[r] = clampi(int(93.0 + sy_rows[r] * res_up * .95), 0, 115) * SKY_W * 3
	var w := out_w
	for r in vh:
		var s := row_off[r]
		var d := r * w * 3 + (a - col0) * 3
		for i in n:
			var o := s + col_off[i]
			out[d] = data[o]
			out[d + 1] = data[o + 1]
			out[d + 2] = data[o + 2]
			d += 3


# -------------------------------------------------------------- wall spans
## Every wall span of a band, nearest first. The segment loop is written out
## here rather than called per segment: a script call costs about ten times
## more while the other band threads are making calls of their own.
func _wall_band(band_a: int, band_b: int) -> void:
	var shade := shade_rows
	var depth_here := dep
	var glass_here := gls
	var tint_max := tints.size() / 3 - 1
	var w := out_w
	var lay := _lay
	var code_ := wall_code
	var phase := time - floorf(time / 6.1) * 6.1
	var flicker := phase > .87 and phase < 1.02
	for key in seg_order:
		var i := key & 65535
		var a := maxi(band_a, seg_c0[i])
		var b := mini(band_b, seg_c1[i])
		if a >= b:
			continue
		var o := i * WALL_STRIDE
		var x1 := walls[o]
		var y1 := walls[o + 1]
		var x2 := walls[o + 2]
		var y2 := walls[o + 3]
		var material := int(walls[o + 4])
		var base_light := walls[o + 5] + flash
		var bottom := walls[o + 6]
		var top := walls[o + 7]
		var area := int(walls[o + 8])
		if top <= bottom:
			continue
		var ex := x2 - x1
		var ey := y2 - y1
		var px := x1 - cx
		var py := y1 - cy
		var den_a := fx * ey - fy * ex
		var den_b := rx * ey - ry * ex
		var t_num := px * ey - py * ex
		var u_a := px * fy - py * fx
		var u_b := px * ry - py * rx
		var vspan := top - bottom
		var tile_off := material * TILE_BYTES
		var glow := material == tile_liquor or material == tile_eat or material == tile_window
		var mirror := material == tile_mirror
		var ti := mini(maxi(area, 0), tint_max) * 3
		var glazing := material == tile_glazing
		var hub_wall := hub_fx and material == tile_hub_wall
		var hub_screen := hub_fx and material == tile_hub_screen
		var opaque := not glazing and not hub_screen
		var plain := not (glow or mirror or glazing or hub_wall or hub_screen)
		var mode := int(tile_mode[material]) if (wall_tiling and plain) else 0
		var along := sqrt(ex * ex + ey * ey) * 128.0
		var base_off := tile_base[material] * TILE_BYTES if mode == 2 else 0
		for c in range(a, b):
			var ray := rays[c]
			var den := den_a + ray * den_b
			if absf(den) < 1e-6:
				continue
			var t := t_num / den
			if t <= .015 or t >= 160.0:
				continue
			var u := (u_a + ray * u_b) / den
			if u < -.00002 or u > 1.00002:
				continue
			if mirror_min:
				var dxv := dir_x[c]
				var dnm := dxv if absf(dxv) > .00001 else -.00001
				var min_t := (mirror_x - cx) / dnm + .008
				if min_t > .015 and t <= min_t:
					continue
			var tex_u := 1.0 - u if den < 0.0 else u
			var uu := clampi(int(tex_u * 128.0), 0, 127)
			if mode == 1:
				uu = int(tex_u * along) & 127
			# A glazing tile keeps its frame and mullions opaque; only the pane
			# rectangles are held back and composited after the scene (the reference
			# drops them from the opaque layer's pixel list).
			var pane_ok := glazing and uu > 5 and uu < 122 and (uu < 62 or uu > 67)
			# light_at() and shade_step() written out: a script call costs several
			# times more when the band threads all make it at once.
			var lit := base_light / (1.0 + .102 * t)
			if lit < .19:
				lit = .19
			var sample_off := tile_off + uu * 3
			var step := clampi(int(floorf(lit * 32.0 + .5) / 32.0 * 32.0 + .5), 0, SHADE_STEPS - 1)
			var profile := (ti / 3) * PROFILE_COUNT
			var row_base := (profile + step) * SHADE_ROW
			var glow_base := (profile + PROFILE_GLOW) * SHADE_ROW
			var flick_base := (profile + PROFILE_FLICK) * SHADE_ROW
			var sy_lo := (cz - top) * focal / t
			var sy_hi := (cz - bottom) * focal / t
			if sy_lo > sy_hi:
				var swap := sy_lo
				sy_lo = sy_hi
				sy_hi = swap
			var r0 := maxi(0, int(ceilf(sy_lo + horizon - .5)))
			var r1 := mini(vh - 1, int(floorf(sy_hi + horizon - .5)))
			if r0 > r1:
				continue
			var cover_top := cov_top[c]
			var cover_bot := cov_bot[c]
			if r0 >= cover_top and r1 <= cover_bot and t >= cov_t[c]:
				continue
			var sy := float(r0) + .5 - horizon
			var t_inv := t / focal
			var row := r0
			var lx := c - col0
			var gi := row * w + lx
			var oi := gi * 3
			if plain and lay:
				# Most walls, layered: note the texel and the shade row for the shader.
				var code := material * 16384 + uu + ((profile + step) << WALL_ROW_SHIFT)
				var code_plain := code
				if mode == 2:
					code_plain = (
						tile_base[material] * 16384 + uu + ((profile + step) << WALL_ROW_SHIFT)
					)
				for _row in range(r0, r1 + 1):
					if t < depth_here[gi]:
						var wz := cz - sy * t_inv
						if wz >= bottom and wz <= top:
							var pv := 0
							var texel := code
							if mode == 0:
								pv = int((top - wz) / vspan * 128.0)
								if pv > 127:
									pv = 127
								elif pv < 0:
									pv = 0
							else:
								pv = int((TILE_ANCHOR - wz) * TILE_ROWS_PER_UNIT) & 127
								if mode == 2 and (wz < WINDOW_SILL or wz > WINDOW_HEAD):
									texel = code_plain
							code_[gi] = texel + pv * 128
							depth_here[gi] = t
							glass_here[gi] = 0
					sy += 1.0
					gi += w
				oi = gi * 3
				row = r1 + 1
			elif plain:
				# Most walls: no glow, glass, mesh or hub shadow to test per pixel.
				for _row in range(r0, r1 + 1):
					if t < depth_here[gi]:
						var wz := cz - sy * t_inv
						if wz >= bottom and wz <= top:
							var pv := 0
							var pi := sample_off
							if mode == 0:
								pv = int((top - wz) / vspan * 128.0)
								if pv > 127:
									pv = 127
								elif pv < 0:
									pv = 0
							else:
								pv = int((TILE_ANCHOR - wz) * TILE_ROWS_PER_UNIT) & 127
								if mode == 2 and (wz < WINDOW_SILL or wz > WINDOW_HEAD):
									pi = base_off + uu * 3
							pi += pv * TILE_W * 3
							out[oi] = shade[row_base + tiles[pi] * 3]
							out[oi + 1] = shade[row_base + tiles[pi + 1] * 3 + 1]
							out[oi + 2] = shade[row_base + tiles[pi + 2] * 3 + 2]
							depth_here[gi] = t
							glass_here[gi] = 0
					sy += 1.0
					gi += w
					oi += w * 3
				row = r1 + 1
			var hit_x := cx + t * dir_x[c]
			var hit_y := cy + t * dir_y[c]
			while row <= r1:
				var wall_z := cz - sy * t_inv
				if wall_z >= bottom and wall_z <= top and t < depth_here[gi]:
					var v := int(clampi(int((top - wall_z) / vspan * 128.0), 0, 127))
					# The road shed's hardware cloth: the open mesh is simply not
					# drawn, so whatever stands behind it shows through.
					if not (
						hub_screen
						and uu >= 7
						and uu <= 120
						and v >= 7
						and v <= 119
						and not ((uu >= 48 and uu <= 54) or (v >= 67 and v <= 73))
						and not (v > 95 and uu < 42 + v / 5)
						and (uu + v) % 17 >= 2
						and posmod(uu - v, 18) >= 2
					):
						var si := sample_off + v * TILE_W * 3
						var sr := tiles[si]
						var sg := tiles[si + 1]
						var sb := tiles[si + 2]
						var base := row_base
						var bright := glow and (sr > 156 or sg > 156 or sb > 156)
						if bright and step < GLOW_STEP:
							base = flick_base if flicker and material == tile_liquor else glow_base
						var cr := shade[base + sr * 3]
						var cg := shade[base + sg * 3 + 1]
						var cb := shade[base + sb * 3 + 2]
						if bright and step >= GLOW_STEP and flicker and material == tile_liquor:
							# A tube already lit past the .9 glow floor still dips
							# to .73 of its own light; that grade is off the table.
							var dim := float(step) / 32.0 * .73
							cr = clampi(int(sr * dim * tints[ti]), 0, 255)
							cg = clampi(int(sg * dim * tints[ti + 1]), 0, 255)
							cb = clampi(int(sb * dim * tints[ti + 2]), 0, 255)
						if hub_wall:
							var shadow := tower_shadow(hit_x, hit_y, wall_z)
							if shadow < 1.0:
								cr = int(cr * shadow)
								cg = int(cg * shadow)
								cb = int(cb * shadow)
						var pane := pane_ok and v > 6 and v < 121 and (v < 67 or v > 73)
						if pane:
							if t < pane_dist[gi]:
								pane_dist[gi] = t
								var p := gi * 3
								pane_rgb[p] = cr
								pane_rgb[p + 1] = cg
								pane_rgb[p + 2] = cb
								pane_cols[c] = 1
						else:
							out[oi] = cr
							out[oi + 1] = cg
							out[oi + 2] = cb
							depth_here[gi] = t
							if lay:
								code_[gi] = WALL_RGB
							if mirror:
								glass_cols[c] = 1
							glass_here[gi] = (
								1
								if (
									mirror
									and parity > 0
									and uu >= 12
									and uu < 116
									and v >= 17
									and v < 108
								)
								else 0
							)
				sy += 1.0
				row += 1
				gi += w
				oi += w * 3
			if opaque and r1 - r0 > 2:
				# Every row strictly inside the span now holds this wall or a nearer one.
				if cover_top > cover_bot:
					cov_top[c] = r0 + 1
					cov_bot[c] = r1 - 1
					cov_t[c] = t
				elif r0 <= cover_bot and r1 >= cover_top:
					if r0 + 1 < cover_top:
						cov_top[c] = r0 + 1
					if r1 - 1 > cover_bot:
						cov_bot[c] = r1 - 1
					if t > cov_t[c]:
						cov_t[c] = t


# ------------------------------------------------------- crossroads surfaces
# Port of crossroads.py: three bounded effects the reference applies only while
# the camera is in the County Crossroads half of the Hickston map.


# ----------------------------------------------------------------- planes
func _plane_band(a: int, b: int) -> void:
	_plane_layer(level.roof_boxes, true, 0, split, a, b)
	_plane_layer(level.floor_boxes, false, split, vh, a, b)


func _plane_layer(boxes: Array, overhead: bool, row0: int, row1: int, a: int, b: int) -> void:
	if row1 <= row0:
		return
	var w := out_w
	var n := b - a
	var begin := PackedFloat32Array()
	var end := PackedFloat32Array()
	begin.resize(n)
	end.resize(n)
	var lit_scale := .77 if overhead else .94
	for entry: Array in boxes:
		var h: float = entry[0]
		if overhead:
			if h <= cz:
				continue
		elif h >= cz:
			continue
		var box: Vector4i = entry[1]
		var bx0 := float(box.x)
		var by0 := float(box.y)
		var bx1 := float(box.z)
		var by1 := float(box.w)
		var tscale := absf(h - cz) * focal
		# Conservative column cull: project the bbox corners and skip heights
		# whose whole box lands outside this band. The per-column test below
		# still decides the exact span, so a padded bound is always safe.
		if plane_cull:
			var cull := true
			var cmin := 1e30
			var cmax := -1e30
			for ci2 in 4:
				var px2 := bx0 if ci2 < 2 else bx1
				var py2 := by0 if ci2 % 2 == 0 else by1
				var ddx := px2 - cx
				var ddy := py2 - cy
				var d2 := ddx * fx + ddy * fy
				if d2 <= .02:
					cull = false
					break
				var col2 := vw / 2.0 + (ddx * rx + ddy * ry) / d2 * focal
				if col2 < cmin:
					cmin = col2
				if col2 > cmax:
					cmax = col2
			if cull and (cmax < float(a) - 2.0 or cmin > float(b) + 2.0):
				continue
		var bmin := 1e30
		var emax := -1e30
		var any := false
		var left := -1
		var right := -1
		for i in n:
			var dxv := dir_x[a + i]
			var dyv := dir_y[a + i]
			var sx := dxv if absf(dxv) > 1e-7 else 1e-7
			var syv := dyv if absf(dyv) > 1e-7 else 1e-7
			var ax := (bx0 - cx) / sx
			var bx := (bx1 - cx) / sx
			var ay := (by0 - cy) / syv
			var by := (by1 - cy) / syv
			var mn := maxf(maxf(minf(ax, bx), minf(ay, by)), .015)
			var mx := minf(maxf(ax, bx), maxf(ay, by))
			begin[i] = mn
			end[i] = mx
			if mn <= mx:
				any = true
				if mn < bmin:
					bmin = mn
				if mx > emax:
					emax = mx
				if left < 0:
					left = i
				right = i + 1
		if not any:
			continue
		var low := row1
		var high := row0 - 1
		for r in range(row0, row1):
			var t := minf(tscale / maxf(.02, absf(sy_rows[r])), 80.0)
			if t >= bmin and t <= emax:
				if r < low:
					low = r
				high = r
		if high < low:
			continue
		var caps_here: Array = level.caps.get(h, [])
		var flows: Array = []
		for f in level.moving_floors.get(h, []):
			flows.append([int(f[0]), (int(time * float(f[1]))) & 127])
		var lx0 := a - col0
		var tiles_ := tiles
		var out_ := out
		var dep_ := dep
		var gls_ := gls
		var shade_ := shade_rows
		var roof_ := level.roof
		var ground_ := level.ground
		var ceil_tile_ := level.ceiling_tile
		var floor_tile_ := level.floor_tile
		var light_ := level.light
		var area_ := level.area
		var tints_ := tints
		var tint_max := tints_.size() / 3 - 1
		var dir_x_ := dir_x
		var dir_y_ := dir_y
		var rows_ := sy_rows
		var lw := level.width
		var lh := level.height
		var has_caps := not caps_here.is_empty()
		var has_flows := not flows.is_empty()
		var hub_floor := hub_fx and not overhead
		var t_patch := tile_hub_patch
		var t_wall := tile_hub_wall
		var t_runoff := tile_hub_runoff
		var water := PackedInt32Array([0, 0, 0])
		# Row-major order (the reference's layout): the distance, its light
		# falloff and the shading divisor are constant across the row, so they
		# are computed once instead of once per pixel.
		for r in range(low, high + 1):
			var t := minf(tscale / maxf(.02, absf(rows_[r])), 80.0)
			if t < bmin or t > emax:
				continue
			var falloff := 1.0 / (1.0 + .102 * t)
			var drow := r * w + lx0
			var last_ci := -1
			var tile := -1
			var step := 0
			var ti := 0
			var sbase := 0
			var tile_base := 0
			for i in range(left, right):
				if t < begin[i] or t > end[i]:
					continue
				var gi := drow + i
				if t >= dep_[gi]:
					continue
				var wx := cx + t * dir_x_[a + i]
				var wy := cy + t * dir_y_[a + i]
				var ix := int(wx)
				var iy := int(wy)
				if ix < 0 or iy < 0 or ix >= lw or iy >= lh:
					continue
				var ci := iy * lw + ix
				# Neighbouring pixels of a row mostly land in the same map cell:
				# its tile, light step and tint are worked out once per run.
				if ci != last_ci or has_caps:
					last_ci = ci
					tile = -1
					if overhead:
						if roof_[ci] == h:
							tile = ceil_tile_[ci]
					else:
						if ground_[ci] == h:
							tile = floor_tile_[ci]
						if has_caps:
							for cap in caps_here:
								if wx >= cap[0] and wx <= cap[2] and wy >= cap[1] and wy <= cap[3]:
									tile = int(cap[4])
									break
					if tile >= 0:
						# light_at() and shade_step() inlined: the reference clamps the
						# quotient first, so distant surfaces stop at .19.
						var raw := (light_[ci] * lit_scale + flash) * falloff
						var shade := raw if raw > .19 else .19
						step = int(shade * 32.0 + .5)
						if step > SHADE_STEPS - 1:
							step = SHADE_STEPS - 1
						ti = area_[ci]
						if ti < 0:
							ti = 0
						elif ti > tint_max:
							ti = tint_max
						sbase = (ti * PROFILE_COUNT + step) * SHADE_ROW
						tile_base = tile * TILE_BYTES
				if tile < 0:
					continue
				var pu := int(wx * 128.0) & 127
				var pv := int(wy * 128.0) & 127
				if has_flows:
					for f in flows:
						if tile == f[0]:
							pv = (pv + f[1]) & 127
				var si := tile_base + pv * TILE_W * 3 + pu * 3
				var oi := gi * 3
				var pr := tiles_[si]
				var pg := tiles_[si + 1]
				var pb := tiles_[si + 2]
				var shadow := 1.0
				if hub_floor:
					if tile == t_runoff:
						water[0] = pr
						water[1] = pg
						water[2] = pb
						running_water(water, wx, wy)
						pr = water[0]
						pg = water[1]
						pb = water[2]
					elif tile == t_patch or tile == t_wall:
						shadow = tower_shadow(wx, wy, h)
				if shadow < 1.0:
					# The shadow scales the stepped light, which takes it off
					# the 1/32 grid the shade table is built on.
					var lit := float(step) / 32.0 * shadow
					out_[oi] = clampi(int(pr * lit * tints_[ti * 3]), 0, 255)
					out_[oi + 1] = clampi(int(pg * lit * tints_[ti * 3 + 1]), 0, 255)
					out_[oi + 2] = clampi(int(pb * lit * tints_[ti * 3 + 2]), 0, 255)
				else:
					out_[oi] = shade_[sbase + pr * 3]
					out_[oi + 1] = shade_[sbase + pg * 3 + 1]
					out_[oi + 2] = shade_[sbase + pb * 3 + 2]
				dep_[gi] = t
				gls_[gi] = 0


# --------------------------------------------------------------- glazing
func _pane_wash() -> void:
	for c in range(col0, col1):
		if pane_cols[c] == 0:
			continue
		for r in vh:
			var gi := r * out_w + (c - col0)
			var pd := pane_dist[gi]
			if pd >= 160.0 or pd >= dep[gi]:
				continue
			var o := gi * 3
			out[o] = clampi(int(out[o] * .67 + pane_rgb[o] * .33), 0, 255)
			out[o + 1] = clampi(int(out[o + 1] * .78 + pane_rgb[o + 1] * .33), 0, 255)
			out[o + 2] = clampi(int(out[o + 2] * .82 + pane_rgb[o + 2] * .33), 0, 255)
