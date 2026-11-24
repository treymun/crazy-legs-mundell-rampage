## What a chapter's first visit used to build, built once at pack time
## (tools/level_bake.gd, the last step of tools/pack_assets.gd) into
## assets_gen and read back here: each level's nav graph (LevelGeometry.nav)
## and the wreck pieces of every breakable a shipped level has (WreckCuts.parts,
## each key's own pieces: its further variants are cut as before). A bake is
## read only while its key still matches what it was made from; anything else
## (a player's map, a level a tool hands in, a missing or stale bake) is built
## as before, the same nodes and pieces either way (tools/prebake_check.gd).
##
##   bake_nav_<level>.bin  the level file's MD5 (any change to the file), the
##                         tile list's, FORMAT, and the MD5 of the scripts that
##                         read a level and build its graph (NAV_SCRIPTS)
##   bake_cuts.bin         per cut key: FORMAT, the cutting scripts' MD5
##                         (CUT_SCRIPTS), a model's .glb and .glb.import MD5,
##                         a picture's own pixels (the lighter copy's are the
##                         same pixels). The keys only a chapter's levels cut
##                         (the chapter and its County Run map) are in
##                         bake_cuts_<stem>.bin (Assets.stem_of), which the
##                         browser build fetches with that chapter's pack
##                         (tools/make_packs.gd); bake_cuts.bin names them
##
## The scripts' and the models' MD5 are asked only where those files can be
## read (the project folder: an export holds compiled scripts and imported
## scenes, and the bake its own pack made beside them). Each file: a magic
## word, a header (var_to_bytes, its size before it), then zstd payloads.
class_name LevelBakes
extends RefCounted

## Bump when what a bake holds or how it is built changes.
const FORMAT := 1
const DIR := "res://assets_gen/"
const NAV_FILE := "bake_nav_%s.bin"
const CUTS_FILE := "bake_cuts.bin"
const CHAPTER_CUTS := "bake_cuts_%s.bin"
const NAV_MAGIC := "CLNV"
const CUTS_MAGIC := "CLWC"
## What a level's graph is read and built by.
const NAV_SCRIPTS := [
	"res://src/level.gd",
	"res://src/level_load.gd",
	"res://src/level_tiles.gd",
	"res://src/level_geometry.gd",
	"res://src/level_nav.gd",
	"res://src/nav_graph.gd",
]
## What a key's pieces are cut by.
const CUT_SCRIPTS := [
	"res://src/wreck_cuts.gd",
	"res://src/wreck_fracture.gd",
	"res://src/set_piece_mesh.gd",
]

## Off: everything is built as before (the bake itself, the checks that hold
## a bake to a build, benchmarks of the building).
static var off := false
## Where the bakes are read from (a check points it at a doctored copy).
static var dir := DIR
## How many bakes were read since the start (the checks).
static var navs_read := 0
static var cuts_read := 0
## Path -> MD5 ("" when it cannot be read), once a session.
static var _md5s := {}
static var _stamps := {}
## Each cuts file read: its name -> [its index (key -> entry), where its
## payloads start]; a file not there is asked again (a chapter's pack may
## come later). The keys kept in a chapter's file -> that file's name.
static var _cut_files := {}
static var _homes: Variant = null


## A file's MD5, "" when it is not there to read (asked once).
static func file_md5(path: String) -> String:
	var known: Variant = _md5s.get(path)
	if known != null:
		var md5: String = known
		return md5
	var out := FileAccess.get_md5(path) if FileAccess.file_exists(path) else ""
	_md5s[path] = out
	return out


## The MD5 of a list of scripts' text, "" when any cannot be read (an export).
static func scripts_md5(paths: Array) -> String:
	var name := ",".join(paths)
	var known: Variant = _stamps.get(name)
	if known != null:
		var md5: String = known
		return md5
	var sums := ""
	for path: String in paths:
		var one := file_md5(path)
		if one == "":
			sums = ""
			break
		sums += one
	var out := sums.md5_text() if sums != "" else ""
	_stamps[name] = out
	return out


static func bytes_md5(data: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(data)
	return ctx.finish().hex_encode()


## The tile list a level numbers its tiles by.
static func tiles_md5(names: PackedStringArray) -> String:
	return "\n".join(names).md5_text()


## Forgets what was read (a check that doctors the files).
static func forget() -> void:
	_md5s.clear()
	_stamps.clear()
	_cut_files.clear()
	_homes = null


# ------------------------------------------------------------------- files


## magic, u32 header size, header, payload.
static func pack_file(
	magic: String, header: Dictionary, payload: PackedByteArray
) -> PackedByteArray:
	var head := var_to_bytes(header)
	var out := magic.to_ascii_buffer()
	out.resize(8)
	out.encode_u32(4, head.size())
	out.append_array(head)
	out.append_array(payload)
	return out


## A payload: u32 raw size, then the zstd bytes.
static func pack_value(value: Variant) -> PackedByteArray:
	var raw := var_to_bytes(value)
	var out := PackedByteArray()
	out.resize(4)
	out.encode_u32(0, raw.size())
	out.append_array(raw.compress(FileAccess.COMPRESSION_ZSTD))
	return out


static func unpack_value(data: PackedByteArray) -> Variant:
	if data.size() < 4:
		return null
	var raw := data.slice(4).decompress(data.decode_u32(0), FileAccess.COMPRESSION_ZSTD)
	if raw.is_empty():
		return null
	return bytes_to_var(raw)


## [header, offset of what follows it] of a file's first bytes, [] when it is
## not a bake of `magic`.
static func read_header(data: PackedByteArray, magic: String) -> Array:
	if data.size() < 8 or data.slice(0, 4).get_string_from_ascii() != magic:
		return []
	var size := data.decode_u32(4)
	if data.size() < 8 + size:
		return []
	var head: Variant = bytes_to_var(data.slice(8, 8 + size))
	if not (head is Dictionary):
		return []
	return [head, 8 + size]


# --------------------------------------------------------------------- nav


## The key a level's graph is baked under (`level` the MD5 of the level's
## file, LevelData.source_file: asked each time, as the editors rewrite it).
static func nav_stamp(level_md5: String, tiles: String, code: String) -> Dictionary:
	return {"format": FORMAT, "level": level_md5, "tiles": tiles, "code": code}


## The baked graph of a level as read from its file, or null (no bake, a
## stale one, a level not read from a file, bakes off).
static func nav(lv: LevelData) -> LevelGeometry.NavGraph:
	if off or lv.source_file == "":
		return null
	var path := dir + NAV_FILE % lv.id
	if not FileAccess.file_exists(path):
		return null
	var data := FileAccess.get_file_as_bytes(path)
	var found := read_header(data, NAV_MAGIC)
	if found.is_empty():
		return null
	var head: Dictionary = found[0]
	var level_md5 := FileAccess.get_md5(lv.source_file)
	var want := nav_stamp(level_md5, tiles_md5(lv.tile_names), scripts_md5(NAV_SCRIPTS))
	if not _matches(head, want):
		return null
	var at: int = found[1]
	var row: Variant = unpack_value(data.slice(at))
	if not (row is Array):
		return null
	var g := nav_from(row)
	if g != null:
		navs_read += 1
	return g


## Whether a bake's header is what is wanted now (a want of "" was not asked:
## a script or a model that cannot be read here).
static func _matches(head: Dictionary, want: Dictionary) -> bool:
	for name: String in want:
		var w: Variant = want[name]
		if w is String and w == "":
			continue
		if not head.has(name) or head[name] != w:
			return false
	return true


## A graph's fields as one value: the cells' own nodes are the cells (only
## the decks' are kept), and each neighbour list is its length and each
## neighbour less the node (a cell's are mostly 1 or a row away: a twentieth
## of the bytes packed, a few milliseconds to read back).
static func nav_row(g: LevelGeometry.NavGraph) -> Array:
	return [
		g.count,
		g.cells,
		g.cell.slice(g.cells),
		g.z,
		_lengths(g.first),
		_less_node(g.first, g.edges),
		_lengths(g.dfirst),
		_less_node(g.dfirst, g.dedges),
		g.over,
		g.ladder_ends,
		g.links,
	]


static func _lengths(first: PackedInt32Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(first.size() - 1)
	for n in out.size():
		out[n] = first[n + 1] - first[n]
	return out


static func _less_node(first: PackedInt32Array, edges: PackedInt32Array) -> PackedInt32Array:
	var out := edges.duplicate()
	for n in first.size() - 1:
		for i in range(first[n], first[n + 1]):
			out[i] -= n
	return out


## The CSR arrays [first, edges] back from _lengths and _less_node.
static func _lists(lengths: PackedByteArray, less: PackedInt32Array) -> Array:
	var count := lengths.size()
	var first := PackedInt32Array()
	first.resize(count + 1)
	var edges := less.duplicate()
	var at := 0
	for n in count:
		first[n] = at
		var end := at + lengths[n]
		if end > edges.size():
			return []
		while at < end:
			edges[at] += n
			at += 1
	first[count] = at
	if at != edges.size():
		return []
	return [first, edges]


static func nav_from(value: Variant) -> LevelGeometry.NavGraph:
	var row: Array = value
	if row.size() != 11:
		return null
	var g := LevelGeometry.NavGraph.new()
	g.count = row[0]
	g.cells = row[1]
	var cell := PackedInt32Array(range(g.cells))
	var decks: PackedInt32Array = row[2]
	cell.append_array(decks)
	g.cell = cell
	g.z = row[3]
	var orth_n: PackedByteArray = row[4]
	var orth_e: PackedInt32Array = row[5]
	var diag_n: PackedByteArray = row[6]
	var diag_e: PackedInt32Array = row[7]
	var orth := _lists(orth_n, orth_e)
	var diag := _lists(diag_n, diag_e)
	if orth.is_empty() or diag.is_empty():
		return null
	g.first = orth[0]
	g.edges = orth[1]
	g.dfirst = diag[0]
	g.dedges = diag[1]
	g.over = row[8]
	var ends: Array = row[9]
	g.ladder_ends.assign(ends)
	g.links = row[10]
	if g.cell.size() != g.count or g.z.size() != g.count or g.first.size() != g.count + 1:
		return null
	return g


# -------------------------------------------------------------------- cuts


## A cut key's stamp: FORMAT, the cutting scripts', its source's (a model's
## files, a picture's pixels; "" not asked).
static func cut_stamp(source: String) -> Dictionary:
	return {"format": FORMAT, "code": scripts_md5(CUT_SCRIPTS), "source": source}


## A model's stamp: its .glb's MD5 and its .glb.import's text (line ends
## left out: an import may rewrite them), "" when the .glb is not there to
## read (an export).
static func model_md5(path: String) -> String:
	var name := "model:" + path
	var known: Variant = _stamps.get(name)
	if known != null:
		var md5: String = known
		return md5
	var glb := file_md5(path)
	var out := ""
	if glb != "":
		var settings := FileAccess.get_file_as_string(path + ".import").replace("\r", "")
		out = (glb + settings.md5_text()).md5_text()
	_stamps[name] = out
	return out


## A cuts file's [index, where its payloads start], [] when it is not here.
static func _cut_file(name: String) -> Array:
	var known: Variant = _cut_files.get(name)
	if known != null:
		var read: Array = known
		return read
	var path := dir + name
	if not FileAccess.file_exists(path):
		return []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return []
	var first := file.get_buffer(8)
	var out: Array = [{}, 0]
	if first.size() == 8 and first.slice(0, 4).get_string_from_ascii() == CUTS_MAGIC:
		var size := first.decode_u32(4)
		var head: Variant = bytes_to_var(file.get_buffer(size))
		if head is Dictionary:
			var dict: Dictionary = head
			var index: Variant = dict.get("index")
			if index is Dictionary:
				out = [index, 8 + size]
			if name == CUTS_FILE:
				var homes: Variant = dict.get("homes")
				_homes = homes if homes is Dictionary else {}
	_cut_files[name] = out
	return out


## The file a key is baked in ("" none here: a chapter's not fetched yet).
static func _file_of(key: String) -> String:
	var main := _cut_file(CUTS_FILE)
	if main.is_empty():
		return ""
	var index: Dictionary = main[0]
	if index.has(key):
		return CUTS_FILE
	var homes: Dictionary = _homes if _homes is Dictionary else {}
	var names: Variant = homes.get(key)
	if names is Array:
		var list: Array = names
		for name: String in list:
			if not _cut_file(name).is_empty():
				return name
	return ""


## Whether a key is baked at all (its stamp not asked yet).
static func has_cut(key: String) -> bool:
	return not off and _file_of(key) != ""


## A baked key's entry when its stamp is what it is now and its file is here:
## [offset, size, stamp, tris, box, file] ([] none). `source` the key's
## source's stamp now.
static func cut_entry(key: String, source: String) -> Array:
	if off:
		return []
	var name := _file_of(key)
	if name == "":
		return []
	var file := _cut_file(name)
	if file.is_empty():
		return []
	var index: Dictionary = file[0]
	var found: Variant = index.get(key)
	if found == null:
		return []
	var entry: Array = found
	var stamp: Dictionary = entry[2]
	if not _matches(stamp, cut_stamp(source)):
		return []
	return entry + [name]


## The pieces of a baked entry (cut_entry), or null when it cannot be read.
static func cut_parts(entry: Array) -> Variant:
	var name: String = entry[5]
	var known := _cut_file(name)
	var file := FileAccess.open(dir + name, FileAccess.READ)
	if file == null or known.is_empty():
		return null
	var offset: int = entry[0]
	var size: int = entry[1]
	var base: int = known[1]
	file.seek(base + offset)
	var rows: Variant = unpack_value(file.get_buffer(size))
	if not (rows is Array):
		return null
	var out: Array = []
	for item: Variant in rows:
		out.append(part_from(item))
	cuts_read += 1
	return out


## A piece as one value. Its shown corners are its corners turned to Godot's
## axes (WreckFracture._framed) or none, made again when read (1), or kept
## as they are (2: anything else).
static func part_row(p: WreckCuts.Part) -> Array:
	var shown := 0
	if not p.shown.is_empty() or not p.shown_n.is_empty():
		shown = 2
		if _swap() * p.verts == p.shown and _swap() * p.normals == p.shown_n:
			shown = 1
	return [
		p.centre,
		p.basis,
		p.half,
		p.verts,
		p.normals,
		p.uvs,
		p.colors,
		p.uv2s,
		p.material,
		p.form,
		shown,
		p.shown if shown == 2 else PackedVector3Array(),
		p.shown_n if shown == 2 else PackedVector3Array(),
	]


static func part_from(value: Variant) -> WreckCuts.Part:
	var row: Array = value
	var p := WreckCuts.Part.new()
	p.centre = row[0]
	p.basis = row[1]
	p.half = row[2]
	p.verts = row[3]
	p.normals = row[4]
	p.uvs = row[5]
	p.colors = row[6]
	p.uv2s = row[7]
	p.material = row[8]
	p.form = row[9]
	var shown: int = row[10]
	if shown == 1:
		p.shown = _swap() * p.verts
		p.shown_n = _swap() * p.normals
	elif shown == 2:
		p.shown = row[11]
		p.shown_n = row[12]
	return p


## WreckFracture._framed's turn from map axes to Godot's.
static func _swap() -> Transform3D:
	return Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)), Vector3.ZERO)
