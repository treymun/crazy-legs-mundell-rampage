## The renderer's overlays: sprites, painted boards, wall marks and ground
## marks, with the tables they are drawn from (the layers are listed in
## render_state.gd).
class_name RenderSprites
extends RenderSurfaces


func _warm_art() -> void:
	var count := _sprite_list.size()
	_spr_c0.resize(count)
	_spr_c1.resize(count)
	_spr_f.resize(count * SPR_F)
	_spr_i.resize(count * SPR_I)
	_spr_data.resize(count)
	var mirrored := parity < 0
	var edge := level.mirror_x
	var lights := level.light
	var areas := level.area
	var tint_max := tints.size() / 3 - 1
	for i in count:
		var s: Sprite = _sprite_list[i]
		var io := i * SPR_I
		_spr_i[io] = 0
		_spr_c0[i] = 0
		_spr_c1[i] = 0
		var sx := s.x
		var sy := s.y
		var tall := s.height
		var dx := sx - cx
		var dy := sy - cy
		if mirrored and sx < edge:
			continue
		var dist := dx * fx + dy * fy
		var limit := 51.0 if tall > 2.7 else 32.0
		if dist <= .13 or dist >= limit:
			continue
		var height := int(tall / dist * focal)
		if height < 2:
			continue
		var board := not is_nan(s.plane)
		var body := s.body
		var top := 0
		if not board:
			top = int(roundf(horizon - (s.z + tall - cz) / dist * focal))
			if top >= vh or (top + height <= 0 and not body):
				continue
		var image := s.image
		var art := sprite_art(image)
		var sw: int = art["w"]
		var sh: int = art["h"]
		var data: PackedByteArray = art["data"]
		_spr_data[i] = data
		_spr_i[io + 4] = sw
		_spr_i[io + 5] = sh
		if board:
			# A painted board is projected along its own axis (_draw_sign); there
			# are few enough of them that it stays a call.
			_spr_i[io] = 2
			_spr_c1[i] = vw
			continue
		var width := maxi(1, int(height * float(sw) / float(sh)))
		var centre := vw / 2.0 + (dx * rx + dy * ry) / dist * focal
		if body:
			top += body_offset(image, data, sw, sh, height)
		if top >= vh or top + height <= 0:
			continue
		var glow := s.glow
		var ci := level.cell(sx, sy)
		var light := 1.1 if glow else light_at(dist, lights[ci])
		if body:
			light = maxf(light, .58 - .021 * dist)
		if not glow:
			light = floorf(light * 32.0 + .5) / 32.0
		var ti := mini(maxi(1 if glow else areas[ci], 0), tint_max) * 3
		var hurt := s.hurt
		var see_through := s.translucent
		var fo := i * SPR_F
		_spr_f[fo] = centre
		_spr_f[fo + 1] = dist
		_spr_f[fo + 2] = light
		_spr_f[fo + 3] = tints[ti]
		_spr_f[fo + 4] = tints[ti + 1]
		_spr_f[fo + 5] = tints[ti + 2]
		_spr_f[fo + 6] = minf(.46, hurt / .18 * .44) if hurt > 0.0 else 0.0
		_spr_i[io] = 1
		_spr_i[io + 1] = height
		_spr_i[io + 2] = top
		_spr_i[io + 3] = width
		_spr_i[io + 6] = 12 if see_through else 100
		_spr_i[io + 7] = (1 if s.flip != mirrored else 0) | (2 if see_through else 0)
		# Its left column, decided once for the whole view. Rounded per band (as
		# it used to be) a sprite landing on an exact half column, which is every
		# odd-width sprite dead ahead, sat one column further right in the band
		# holding its left edge than in the bands after it. A half goes down, as
		# it did in all those other bands.
		var left := int(ceilf(centre - width / 2.0 - .5))
		_spr_i[io + 8] = left
		_spr_c0[i] = left
		_spr_c1[i] = left + width

	count = _mark_list.size()
	_mk_f.resize(count * MK_F)
	_mk_i.resize(count * MK_I)
	_mk_data.resize(count)
	for k in count:
		var m: WallMark = _mark_list[k]
		var io := k * MK_I
		_mk_i[io] = 0
		var rxv := m.x - cx
		var ryv := m.y - cy
		var d := rxv * fx + ryv * fy
		if d <= .19 or d >= 15.0:
			continue
		var lateral := rxv * rx + ryv * ry
		var ux := m.ux
		var uy := m.uy
		var axis := ux * rx + uy * ry
		var fall := ux * fx + uy * fy
		if absf(axis * d - lateral * fall) < .08:
			continue
		var extent: float = m.radius
		var mz := m.z
		var half := focal * extent / d
		var cy_screen := horizon - (mz - cz) * focal / d
		var y0 := maxi(0, int(cy_screen - half - 1.0))
		var y1 := mini(vh, int(cy_screen + half + 2.0))
		if y0 >= y1:
			continue
		var art := sprite_art(m.image)
		_mk_data[k] = art["data"]
		var fo := k * MK_F
		_mk_f[fo] = d
		_mk_f[fo + 1] = lateral
		_mk_f[fo + 2] = axis
		_mk_f[fo + 3] = fall
		_mk_f[fo + 4] = extent
		_mk_f[fo + 5] = (lateral - axis * extent) * focal / (d - fall * extent)
		_mk_f[fo + 6] = (lateral + axis * extent) * focal / (d + fall * extent)
		_mk_f[fo + 7] = light_at(d, 1.0)
		_mk_f[fo + 8] = mz
		_mk_i[io] = 1
		_mk_i[io + 1] = y0
		_mk_i[io + 2] = y1
		_mk_i[io + 3] = int(art["w"])
		_mk_i[io + 4] = int(art["h"])

	count = _ground_list.size()
	_gm_f.resize(count * GM_F)
	_gm_i.resize(count * GM_I)
	_gm_data.resize(count)
	for k in count:
		var m: GroundMark = _ground_list[k]
		var io := k * GM_I
		_gm_i[io] = 0
		var gx := m.x
		var gy := m.y
		var gz := m.z
		var reach := m.reach
		var width := m.width
		var mx := gx - cx
		var my := gy - cy
		var radial := sqrt((gx - cx) * (gx - cx) + (gy - cy) * (gy - cy))
		if cz <= gz + .015 or radial > 26.0:
			continue
		var angle := m.angle
		var art := sprite_art(m.image)
		_gm_data[k] = art["data"]
		var fo := k * GM_F
		_gm_f[fo] = cx - gx
		_gm_f[fo + 1] = cy - gy
		_gm_f[fo + 2] = cz - gz
		_gm_f[fo + 3] = radial
		_gm_f[fo + 4] = sqrt(reach * reach + width * width)
		_gm_f[fo + 5] = cos(angle)
		_gm_f[fo + 6] = sin(angle)
		_gm_f[fo + 7] = reach
		_gm_f[fo + 8] = width
		_gm_f[fo + 9] = mx * fx + my * fy
		_gm_f[fo + 10] = mx * rx + my * ry
		_gm_i[io] = 1
		_gm_i[io + 1] = int(art["w"])
		_gm_i[io + 2] = int(art["h"])
		# The mark is a rectangle on the floor; seen from in front, it lies between
		# the screen columns of its corners. (Any corner beside or behind the eye:
		# no shortcut, every column is tested as before.)
		var lo := 1e9
		var hi := -1e9
		for corner in 4:
			var along := reach if corner < 2 else -reach
			var across := width if corner % 2 == 0 else -width
			var px := mx + along * _gm_f[fo + 5] - across * _gm_f[fo + 6]
			var py := my + along * _gm_f[fo + 6] + across * _gm_f[fo + 5]
			var ahead := px * fx + py * fy
			if ahead <= .05:
				lo = -1e9
				hi = 1e9
				break
			var column := vw / 2.0 + (px * rx + py * ry) / ahead * focal
			lo = minf(lo, column)
			hi = maxf(hi, column)
		_gm_i[io + 3] = clampi(int(floorf(maxf(lo, -4.0))) - 2, 0, vw)
		_gm_i[io + 4] = clampi(int(ceilf(minf(hi, vw + 4.0))) + 3, 0, vw)


func _sprite_band(a: int, b: int) -> void:
	var n := _sprite_list.size()
	var first := _spr_c0
	var last := _spr_c1
	var fs := _spr_f
	var ns := _spr_i
	var w := out_w
	var out_ := spr
	var dep_ := dep
	var gls_ := gls
	var lay := _lay
	var cover_ := over_a
	var far_ := over_d
	var lx0 := a - col0
	var span := b - a
	var rows := vh
	# Each sprite's texture column for every screen column, worked out once per
	# sprite instead of once per pixel.
	var across := PackedInt32Array()
	across.resize(span)
	for i in n:
		if last[i] <= a or first[i] >= b:
			continue
		var io := i * SPR_I
		if ns[io] == 2:
			_draw_sign(_sprite_list[i], a, b, _spr_data[i], ns[io + 4], ns[io + 5])
			continue
		var fo := i * SPR_F
		var width := ns[io + 3]
		var left := ns[io + 8] - a
		var height := ns[io + 1]
		var top := ns[io + 2]
		var x0 := maxi(0, left)
		var x1 := mini(span, left + width)
		var y0 := maxi(0, top)
		var y1 := mini(rows, top + height)
		if x0 >= x1 or y0 >= y1:
			continue
		# Most sprites of a town are behind a wall. Where a column already holds
		# wall from the sprite's top row to its bottom row, all of it nearer than
		# the sprite (see cov_top in _wall_band), no pixel of that column can pass
		# the depth test below: trim such columns off both sides first.
		var dist := fs[fo + 1]
		var hidden := dist - .014
		var foot := y1 - 1
		while x0 < x1:
			var c := a + x0
			if hidden >= cov_t[c] and y0 >= cov_top[c] and foot <= cov_bot[c]:
				x0 += 1
			else:
				break
		while x0 < x1:
			var c := a + x1 - 1
			if hidden >= cov_t[c] and y0 >= cov_top[c] and foot <= cov_bot[c]:
				x1 -= 1
			else:
				break
		if x0 >= x1:
			continue
		var data: PackedByteArray = _spr_data[i]
		var sw := ns[io + 4]
		var sh := ns[io + 5]
		var threshold := ns[io + 6]
		var flip := (ns[io + 7] & 1) != 0
		var translucent := (ns[io + 7] & 2) != 0
		var light := fs[fo + 2]
		var tr := fs[fo + 3]
		var tg := fs[fo + 4]
		var tb := fs[fo + 5]
		var hurt_k := fs[fo + 6]
		for x in range(x0, x1):
			var sxi := (x - left) * sw / width
			across[x] = (sw - sxi - 1 if flip else sxi) * 4
		for y in range(y0, y1):
			var srow := (y - top) * sh / height * sw * 4
			var drow := y * w + lx0
			for x in range(x0, x1):
				var sp := srow + across[x]
				var alpha := data[sp + 3]
				if alpha <= threshold:
					continue
				var gi := drow + x
				if dist >= dep_[gi] + .014:
					continue
				# The reference's order: shade (and clip) the texel first, then wash
				# the lit colour toward hot white, so a hit flash reads the same on a
				# dark or distant enemy as on a bright near one.
				var cr := clampi(int(data[sp] * light * tr), 0, 255)
				var cg := clampi(int(data[sp + 1] * light * tg), 0, 255)
				var cb := clampi(int(data[sp + 2] * light * tb), 0, 255)
				if hurt_k > 0.0:
					cr = int(cr * (1.0 - hurt_k) + 255.0 * hurt_k)
					cg = int(cg * (1.0 - hurt_k) + 232.0 * hurt_k)
					cb = int(cb * (1.0 - hurt_k) + 208.0 * hurt_k)
				var o := gi * 3
				if translucent:
					var cov := alpha / 255.0
					out_[o] = clampi(int(roundf(out_[o] * (1.0 - cov) + cr * cov)), 0, 255)
					out_[o + 1] = clampi(int(roundf(out_[o + 1] * (1.0 - cov) + cg * cov)), 0, 255)
					out_[o + 2] = clampi(int(roundf(out_[o + 2] * (1.0 - cov) + cb * cov)), 0, 255)
					if lay:
						var have := cover_[gi]
						if have == 0:
							far_[gi] = dist
						cover_[gi] = have + int((255 - have) * cov + .5)
				else:
					out_[o] = cr
					out_[o + 1] = cg
					out_[o + 2] = cb
					dep_[gi] = dist
					if lay:
						cover_[gi] = 255
						far_[gi] = dist
					else:
						gls_[gi] = 0


## Painted board: project along the sprite's world axis (draw_sign()).
func _draw_sign(s: Sprite, a: int, b: int, data: PackedByteArray, sw: int, sh: int) -> void:
	var ax := cos(s.plane)
	var ay := sin(s.plane)
	var rxv := s.x - cx
	var ryv := s.y - cy
	var side := rxv * ay - ryv * ax
	if side <= .02:
		return
	var width := s.height * float(sw) / float(sh)
	var near := rays[a]
	var far := rays[b - 1]
	var ahead := rxv * fx + ryv * fy
	var lateral := rxv * rx + ryv * ry
	var half_ahead := (ax * fx + ay * fy) * width * .5
	var half_lateral := (ax * rx + ay * ry) * width * .5
	if near * ahead - lateral > absf(near * half_ahead - half_lateral) + .002:
		return
	if lateral - far * ahead > absf(half_lateral - far * half_ahead) + .002:
		return
	var ci := level.cell(s.x, s.y)
	var area := level.area[ci]
	var ti := tint_index(area, tints)
	var tr := tints[ti]
	var tg := tints[ti + 1]
	var tb := tints[ti + 2]
	var threshold := 12 if s.translucent else 100
	var w := out_w
	var lx0 := a - col0
	for c in range(a, b):
		var ray := rays[c]
		var dxv := fx + rx * ray
		var dyv := fy + ry * ray
		var den := ay * dxv - ax * dyv
		if den <= .001:
			continue
		var d := side / den
		if d <= .13:
			continue
		var along := ((cx - s.x + dxv * d) * ax + (cy - s.y + dyv * d) * ay) / width + .5
		if along < 0.0 or along >= 1.0:
			continue
		var u := clampi(int(along * sw), 0, sw - 1)
		var light := light_at(d, level.light[ci])
		var lx := c - col0
		for r in vh:
			var v := (s.z + s.height - cz + sy_rows[r] * d / focal) / s.height
			if v < 0.0 or v >= 1.0:
				continue
			var gi := r * w + lx
			if d >= dep[gi] + .012:
				continue
			var vv := clampi(int(v * sh), 0, sh - 1)
			var sp := (vv * sw + u) * 4
			var alpha := data[sp + 3]
			if alpha <= threshold:
				continue
			var cr := int(data[sp] * light * tr)
			var cg := int(data[sp + 1] * light * tg)
			var cb := int(data[sp + 2] * light * tb)
			var o := gi * 3
			if s.translucent:
				var cov := alpha / 255.0
				spr[o] = clampi(int(roundf(spr[o] * (1.0 - cov) + cr * cov)), 0, 255)
				spr[o + 1] = clampi(int(roundf(spr[o + 1] * (1.0 - cov) + cg * cov)), 0, 255)
				spr[o + 2] = clampi(int(roundf(spr[o + 2] * (1.0 - cov) + cb * cov)), 0, 255)
				if _lay:
					var have := over_a[gi]
					if have == 0:
						over_d[gi] = d
					over_a[gi] = have + int((255 - have) * cov + .5)
			else:
				spr[o] = clampi(cr, 0, 255)
				spr[o + 1] = clampi(cg, 0, 255)
				spr[o + 2] = clampi(cb, 0, 255)
				dep[gi] = d
				if _lay:
					over_a[gi] = 255
					over_d[gi] = d
				else:
					gls[gi] = 0


func _mark_band(a: int, b: int) -> void:
	var count := _mark_list.size()
	if count == 0:
		return
	var fs := _mk_f
	var ns := _mk_i
	var half_w := vw * .5 - a
	var w := out_w
	var lx0 := a - col0
	var span := b - a
	var lay := _lay
	for k in count:
		var io := k * MK_I
		if ns[io] == 0:
			continue
		var fo := k * MK_F
		var left := half_w + fs[fo + 5]
		var right := half_w + fs[fo + 6]
		if absf(right - left) < .15:
			continue
		var x0 := maxi(0, int(floorf(minf(left, right))))
		var x1 := mini(span, int(ceilf(maxf(left, right))))
		if x0 >= x1:
			continue
		var y0 := ns[io + 1]
		var y1 := ns[io + 2]
		var sw := ns[io + 3]
		var sh := ns[io + 4]
		var data: PackedByteArray = _mk_data[k]
		var d := fs[fo]
		var lateral := fs[fo + 1]
		var axis := fs[fo + 2]
		var fall := fs[fo + 3]
		var extent := fs[fo + 4]
		var light := fs[fo + 7]
		var mz := fs[fo + 8]
		for y in range(y0, y1):
			var vv := (horizon - (y + .5)) * d / focal + cz - mz
			if absf(vv) > extent:
				continue
			var v := clampi(int((1.0 - vv / extent) * .5 * sh), 0, sh - 1)
			var drow := y * w
			for x in range(x0, x1):
				var proj := (x + .5 - half_w) / focal
				var den := axis - proj * fall
				if absf(den) < 1e-12:
					continue
				var along := (proj * d - lateral) / den
				if absf(along) > extent:
					continue
				var dd := d + along * fall
				var gi := drow + lx0 + x
				if absf(dep[gi] - dd) >= .12 or glass[gi] != 0:
					continue
				var u := clampi(int((along / extent + 1.0) * .5 * sw), 0, sw - 1)
				var sp := (v * sw + u) * 4
				var alpha := data[sp + 3]
				if alpha <= 20:
					continue
				var mix := alpha / 255.0
				var o := gi * 3
				if lay and wall_code[gi] != WALL_RGB:
					# The wall here is still a texel and a shade row: colour it the
					# way the shader would have, then the mark can go over it.
					var code := wall_code[gi] & 0xFFFFFFFF
					var pi := (code & 0x1FFFFF) * 3
					var row_base := (code >> WALL_ROW_SHIFT) * SHADE_ROW
					out[o] = shade_rows[row_base + tiles[pi] * 3]
					out[o + 1] = shade_rows[row_base + tiles[pi + 1] * 3 + 1]
					out[o + 2] = shade_rows[row_base + tiles[pi + 2] * 3 + 2]
					wall_code[gi] = WALL_RGB
				out[o] = clampi(int(roundf(out[o] * (1.0 - mix) + data[sp] * light * mix)), 0, 255)
				out[o + 1] = clampi(
					int(roundf(out[o + 1] * (1.0 - mix) + data[sp + 1] * light * mix)), 0, 255
				)
				out[o + 2] = clampi(
					int(roundf(out[o + 2] * (1.0 - mix) + data[sp + 2] * light * mix)), 0, 255
				)


# ----------------------------------------------------------- ground marks
func _ground_band(a: int, b: int) -> void:
	var count := _ground_list.size()
	if count == 0:
		return
	var fs := _gm_f
	var ns := _gm_i
	var edge := maxf(absf(rays[a]), absf(rays[b - 1])) + .012
	var edge_scale := sqrt(1.0 + edge * edge)
	var w := out_w
	var lx0 := a - col0
	var lay := _lay
	for k in count:
		var io := k * GM_I
		if ns[io] == 0:
			continue
		var fo := k * GM_F
		var bounds := fs[fo + 4]
		var ahead := fs[fo + 9]
		if ahead + bounds <= 0.0 or absf(fs[fo + 10]) - ahead * edge > bounds * edge_scale:
			continue
		var from_x := fs[fo]
		var from_y := fs[fo + 1]
		var above := fs[fo + 2]
		var radial := fs[fo + 3]
		var cs := fs[fo + 5]
		var sn := fs[fo + 6]
		var reach := fs[fo + 7]
		var width := fs[fo + 8]
		var sw := ns[io + 1]
		var sh := ns[io + 2]
		var first := maxi(a, ns[io + 3])
		var last := mini(b, ns[io + 4])
		if first >= last:
			continue
		var data: PackedByteArray = _gm_data[k]
		for r in vh:
			var sy := sy_rows[r]
			if sy <= 0.0:
				continue
			var distance := above * focal / maxf(sy, .015)
			if distance >= radial + bounds + 1.0:
				continue
			if distance <= maxf(0.0, (radial - bounds) * .76):
				continue
			# light_at(distance, 1.12), written out (no script call in a band).
			var light := maxf(
				.63, floorf(maxf(.19, 1.12 / (1.0 + .102 * distance)) * 32.0 + .5) / 32.0
			)
			var drow := r * w
			for i in range(first, last):
				var ray := rays[i]
				var wx := from_x + distance * (fx + rx * ray)
				var wy := from_y + distance * (fy + ry * ray)
				var u := (wx * cs + wy * sn) / reach
				var v := (-wx * sn + wy * cs) / width
				if absf(u) >= 1.0 or absf(v) >= 1.0:
					continue
				var gi := drow + lx0 + (i - a)
				if distance <= .015:
					continue
				if lay:
					# The shader knows which floor shows here; only a wall in front
					# can be ruled out now.
					if dep[gi] <= distance - .13:
						continue
				elif absf(distance - dep[gi]) >= .13:
					continue
				var au := clampi(int((u + 1.0) * .5 * sw), 0, sw - 1)
				var av := clampi(int((v + 1.0) * .5 * sh), 0, sh - 1)
				var sp := (av * sw + au) * 4
				var alpha := data[sp + 3]
				if alpha == 0:
					continue
				var cov := alpha / 255.0
				var o := gi * 3
				spr[o] = clampi(int(roundf(spr[o] * (1.0 - cov) + data[sp] * light * cov)), 0, 255)
				spr[o + 1] = clampi(
					int(roundf(spr[o + 1] * (1.0 - cov) + data[sp + 1] * light * cov)), 0, 255
				)
				spr[o + 2] = clampi(
					int(roundf(spr[o + 2] * (1.0 - cov) + data[sp + 2] * light * cov)), 0, 255
				)
				if lay:
					var have := over_a[gi]
					over_a[gi] = have + int((255 - have) * cov + .5)
					over_d[gi] = -distance
