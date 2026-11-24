## The chapter openers (PLAY setting OPENERS: FIRST TIME, ALWAYS, OFF): before
## a campaign chapter's first tick a short cinematic, like a 1990s cutscene:
## the camera flies a few authored paths over the level as it stands (its own
## sky and weather; opener_camera.gd), the title card drops in the chapter's
## own style with a tagline, and the boss is teased in silhouette against a
## light, growling a line; an old storyteller reads two lines over it, and
## the camera comes down into the player's eyes as play begins. Under it all
## the chapter's own song, the ambience and spot sounds (opener_mix.gd).
## Any key, button, click or tap skips it at once.
##
## Looks only. The front end does not tick the game while it plays (as PHOTO
## MODE and the KILL CAM), the view is drawn from the opener's camera through
## game.eye_override set only for the draw, and nothing carried or simulated
## changes: the game starts after it exactly as it would have (opener_check).
## Never online (a shared game cannot hold still for one machine, and a
## client joining mid-chapter has missed the start anyway), never in COUNTY
## RUN, versus, a rematch, the hub, a revisit, a loaded save or a retry.
##
## Each chapter is authored in data/tuning/openers.json (camera keys,
## tagline, card style, boss, the narrator's lines); the title comes from
## Campaign. `--opener=<chapter>` previews one (`--opener-data=<file>` from
## a draft of the file); `--opener-out=<dir>` saves its key frames from a
## window and quits.
class_name ChapterOpener
extends RefCounted

const DATA := "res://data/tuning/openers.json"
const FIRST_TIME := 0
const ALWAYS := 1
const OFF := 2
## The bars over and under the picture (canvas rows).
const BAR_TOP := 14
const BAR_LOW := 142
## Seconds: the fade in from black, each cut's dip, the card's drop, swing
## and stay, the boss's part after the last shot, the fade out at the end.
const FADE_IN := .55
const DIP := .2
const DROP := .55
const STAY := 4.6
const LIFT := .45
const BOSS_FADE := .7
## The landing starts this long before the boss's line ends; over its first
## LIGHT seconds the dark and the boss go and the bars draw back after.
const LAND_EARLY := .15
const LIGHT := .5
## The boss's line after his growl (the growl mostly over, the line heard clear).
const LINE_AFTER := .75
## Where the card hangs (its top) and the tagline under it.
const CARD_Y := 30
const GAP_TAG := 6
const TYPE_RATE := 34.0
const SEEN_FILE := "user://openers_seen.json"

static var _data := {}
## --opener-data=<file>: another openers file to preview (an author's draft).
static var data_path := DATA

var mode := FIRST_TIME
var playing := false
var game: Game
var chapter := ""
## Seconds into the opener and its whole length.
var at := 0.0
var length := 0.0
## The game a chapter just started with (play()), waiting for its first frame.
var pending: Game = null
## --opener=<chapter>: play it whatever the setting; --opener-out: its key
## frames' folder.
var forced := ""
var shots_out := ""
## --opener-strip=<n>: with --opener-out, n frames evenly over the flight and
## three of the landing instead of its key moments (the frame-strip sheets).
var strip := 0
## Set by the death screen's retry: the chapter starts over without one.
var retrying := false
## Chapters seen (FIRST TIME), kept in SEEN_FILE; the checks point it
## elsewhere and say whether a tool run may write it.
var seen := {}
var seen_path := SEEN_FILE
var tools_write := false
var _seen_loaded := false
## The schedule worked out at the start: shots' start times, the card's
## drop, the boss's part, the storyteller's lines, the landing, and the sounds
## ([time, kind, cue, volume, pan]) not yet played.
var _starts := PackedFloat32Array()
var _shots_end := 0.0
var _title_at := 0.0
var boss_at := 0.0
var growl_at := 0.0
var line_at := 0.0
var land_at := 0.0
var _narr: PackedFloat32Array = PackedFloat32Array()
var _cues: Array = []
## The camera's flight and the sound's plan.
var camera := OpenerCamera.new()
var mix := OpenerMix.new()
## Whether the bed is the chapter's song (else the old sting, the score held).
var _bed := false
var _caption := ""
var _caption_from := 0.0
var _caption_until := 0.0
var _boss_caption := false
## The pictures (OpenerArt), made at the start.
var _card: Dictionary = {}
var _card_tex: Texture2D = null
var _boss_tex: Texture2D = null
var _boss_img: Image = null
var _lights: Array[Texture2D] = []
var _light_imgs: Array[Image] = []
var _black: Texture2D = null
var _white: Texture2D = null
var _ground: Array = []


static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(data_path))
		_data = parsed if parsed is Dictionary else {"chapters": {}}
	return _data


static func entry(level_id: String) -> Dictionary:
	var chapters: Dictionary = data().get("chapters", {})
	return chapters.get(level_id, {})


static func has_opener(level_id: String) -> bool:
	return not entry(level_id).is_empty()


## "CHAPTER ONE" for the campaign's first chapter.
static func number_of(level_id: String) -> String:
	var words: Array = data().get("number_words", [])
	var index := Campaign.ORDER.find(level_id)
	if index < 0 or index >= words.size():
		return "CHAPTER"
	return "CHAPTER " + str(words[index])


static func lines_of(level_id: String) -> PackedStringArray:
	var out := PackedStringArray()
	for line: Variant in entry(level_id).get("lines", []):
		out.append(str(line))
	return out


static func shots_of(level_id: String) -> Array:
	return entry(level_id).get("shots", [])


# ------------------------------------------------------------------ when


## A game about to be played (main_flow.gd play()): note it if its opener is
## due; `chapter` says it is a campaign chapter played on this machine.
func offer(m: MainState, target: Game, is_chapter: bool) -> void:
	pending = target if due(m, target, is_chapter) else null
	retrying = false


func due(m: MainState, target: Game, is_chapter: bool) -> bool:
	var id := target.level.id
	if not has_opener(id):
		return false
	if forced != "":
		return forced == id
	if not is_chapter or mode == OFF or m.net != null or retrying:
		return false
	var plain := (
		m.view_tour == ""
		and m.view_bench == 0
		and m.smoke_frames == 0
		and not m.demo
		and not m.showcase
	)
	var tool_run := Engine.get_main_loop() != null and Engine.get_main_loop().get_script() != null
	if not plain or (tool_run and not tools_write):
		return false
	var kind := Modes.mode_of(target)
	if kind != Modes.CAMPAIGN and kind != Modes.COOP:
		return false
	if target.clock > 0.0 or target.showing_tally or target.won:
		return false  # a loaded save, or a chapter already under way
	_load_seen()
	return mode == ALWAYS or not seen.has(id)


func _load_seen() -> void:
	if _seen_loaded:
		return
	_seen_loaded = true
	if not FileAccess.file_exists(seen_path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(seen_path))
	if parsed is Dictionary:
		var kept: Dictionary = parsed
		var ids: Array = kept.get("seen", [])
		for id: Variant in ids:
			seen[str(id)] = true


func _save_seen() -> void:
	var tool_run := Engine.get_main_loop() != null and Engine.get_main_loop().get_script() != null
	if tool_run and not tools_write:
		return
	var file := FileAccess.open(seen_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"seen": seen.keys()}))


## Begin the opener noted for the game on screen (main.gd, each play frame).
func start(m: MainState) -> bool:
	if playing or pending == null:
		return false
	if pending != m.game or m.state != "play":
		pending = null
		return false
	begin(m, pending)
	return true


func begin(m: MainState, target: Game) -> void:
	pending = null
	game = target
	chapter = target.level.id
	playing = true
	at = 0.0
	if forced == "":
		_load_seen()
		seen[chapter] = true
		_save_seen()
	_schedule(m)
	_make_pictures(m)
	m.sound.pause_world()
	_bed = m.sound.opener_bed(target.level.score, mix.song, mix.bed_at(0.0))
	if not _bed:
		# The chapter's song is not here (a browser pack still coming): the
		# pass 8 sting, the score held till the end.
		mix.song = ""
		m.sound.opener_music(str(entry(chapter).get("sting", "sting_open_" + chapter)))


## The schedule from the shots and the lines' own lengths, the camera's
## flight and the sound's plan.
func _schedule(m: MainState) -> void:
	var e := entry(chapter)
	camera.build(shots_of(chapter), game.world, game.props, m.art)
	_starts = PackedFloat32Array()
	for shot in camera.shots:
		_starts.append(shot.start)
	_shots_end = maxf(camera.shots_end, 1.0)
	_title_at = e.get("title_at", 1.7)
	var boss: Dictionary = e.get("boss", {})
	var lines := lines_of(chapter)
	boss_at = _shots_end
	var second := seconds(m, "narr_%s_1" % chapter, 2.6) if lines.size() > 1 else 0.0
	_narr = PackedFloat32Array([.55])
	if lines.size() > 1:
		_narr.append(boss_at + .3)
	growl_at = boss_at + .3 + second + .05
	line_at = growl_at + LINE_AFTER
	var line_secs := seconds(m, str(boss.get("line", "")), 1.8)
	land_at = line_at + line_secs - LAND_EARLY
	length = land_at + OpenerCamera.LAND
	camera.land(land_at, game.world, game.player.as_render_player())
	mix.build(self, m)
	_cues = mix.cues.duplicate()
	_caption = ""
	_boss_caption = false


## A cue's length in seconds (`otherwise` when it is not in the bank).
func seconds(m: MainState, cue: String, otherwise: float) -> float:
	var stream := m.art.cue(cue) if cue != "" else null
	return stream.get_length() if stream != null else otherwise


## The schedule as opener_mix.gd reads it.
func starts() -> PackedFloat32Array:
	return _starts


func title_land() -> float:
	return _title_at + DROP


func lines_count() -> int:
	return _narr.size()


func narr_at(n: int) -> float:
	return _narr[n]


func boss_sting() -> String:
	var boss: Dictionary = entry(chapter).get("boss", {})
	return str(boss.get("sting", ""))


func _make_pictures(m: MainState) -> void:
	var e := entry(chapter)
	_card = OpenerArt.card(
		str(e.get("card", "plank")), number_of(chapter), Campaign.title_of(chapter), chapter
	)
	var boss: Dictionary = e.get("boss", {})
	var col := OpenerArt.color_of(boss.get("color", [255, 240, 200]))
	var cel := m.art.art(str(boss.get("cel", "")))
	var tall: int = boss.get("tall", 104)
	_boss_img = OpenerArt.silhouette(cel, tall, col.lerp(Color(1, 1, 1), .35))
	var kind := str(boss.get("light", "glow"))
	_light_imgs.clear()
	if kind == "flasher":
		_light_imgs.append(OpenerArt.backlight(kind, col, -1))
		_light_imgs.append(
			OpenerArt.backlight(kind, OpenerArt.color_of(boss.get("color_b", [80, 120, 255])), 1)
		)
	else:
		_light_imgs.append(OpenerArt.backlight(kind, col))
	_ground = boss.get("ground", [])
	if m.canvas.gpu:
		var card_img: Image = _card["image"]
		_card_tex = ImageTexture.create_from_image(card_img)
		_boss_tex = ImageTexture.create_from_image(_boss_img)
		_lights.clear()
		for img: Image in _light_imgs:
			_lights.append(ImageTexture.create_from_image(img))
		if _black == null:
			var one := Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
			one.fill(Color(0, 0, 0, 1))
			_black = ImageTexture.create_from_image(one)
			one.fill(Color(1, 1, 1, 1))
			_white = ImageTexture.create_from_image(one)


# ------------------------------------------------------------------ playing


## One frame: the clock runs, the sounds come in on time, the bed follows its
## keys, and at the end (the camera in the player's eyes) the game starts.
func frame(m: MainState, dt: float) -> void:
	if not playing:
		return
	if m.game != game:
		stop(m)
		return
	at += dt
	while not _cues.is_empty():
		var next: Array = _cues[0]
		var when: float = next[0]
		if when > at:
			break
		var cue: Array = _cues.pop_front()
		_play(m, cue)
	if _bed:
		m.sound.set_opener_hold(mix.bed_at(at))
	if at >= length:
		stop(m, true)


func _play(m: MainState, row: Array) -> void:
	var kind := str(row[1])
	var cue := str(row[2])
	var volume: float = row[3]
	var pan: float = row[4]
	if cue == "":
		return
	match kind:
		"voice":
			var secs := m.sound.play_voice(cue, volume, pan)
			_caption = _caption_for(cue)
			_caption_from = at
			_caption_until = at + secs + .35
			_boss_caption = not cue.begins_with("narr_")
		"effect":
			m.sound.play(cue, volume, pan)
		"sting":
			if _bed:
				m.sound.sting(cue, volume)
			else:
				m.sound.opener_music(cue)
		"amb":
			m.sound.set_room(cue)
		"rain":
			m.sound.set_bed(Sound.BED_RAIN, cue, volume)


func _caption_for(cue: String) -> String:
	var lines := lines_of(chapter)
	for n in lines.size():
		if cue == "narr_%s_%d" % [chapter, n]:
			return lines[n]
	var boss: Dictionary = entry(chapter).get("boss", {})
	return '"%s"' % str(boss.get("say", ""))


## Skipped or done: the voices hushed, the bed let up to play's level (the
## chapter's song goes on), the ambience left for play to take over. Skipped,
## the opener's own effects stop and the iris opens on play; landed, the
## picture is already the player's.
func stop(m: MainState, landed := false) -> void:
	if not playing:
		return
	playing = false
	_cues.clear()
	if game != null:
		game.eye_override = {}
	m.sound.stop_voice()
	var own := PackedStringArray()
	if not landed:
		for row: Array in mix.cues:
			if str(row[1]) == "effect":
				own.append(str(row[2]))
	m.sound.end_opener(own)
	m.sound.opener_music("")
	m.mouse_rel = Vector2.ZERO
	m.block_fire = true
	m.screen_age = 1.0 if landed else 0.0
	game = null


# ------------------------------------------------------------------ camera


## The camera's eye at `t` (opener_camera.gd).
func eye_at(t: float) -> Dictionary:
	if camera.shots.is_empty():
		var p := game.player
		return p.as_render_player()
	return camera.eye(t, View.base_focal)


static func v3(v: Variant) -> Vector3:
	var a: Array = v
	var x: float = a[0]
	var y: float = a[1]
	var z: float = a[2] if a.size() > 2 else 2.0
	return Vector3(x, y, z)


# ------------------------------------------------------------------ drawing


## The opener's frame: the level from its camera (no gun, no HUD), black bars,
## the card, the boss, the caption and how to skip; landing, the bars draw
## back and the picture is the player's own as play begins.
func draw(m: MainState) -> void:
	var g := m.game
	var c := m.canvas
	var kept := _keep_caches(g)
	g.eye_override = eye_at(at)
	g.draw(c, 0, true)
	g.eye_override = {}
	_put_caches(g, kept)
	m.show_view()
	if c.gpu:
		c.gpu_item(Canvas.ITEM_NORMAL)
	var dark := _darkness()
	if dark > 0.0:
		_shade(c, 0, 0, View.WIDTH, View.VIEW, Color(0, 0, 0), dark)
	_draw_boss(c)
	var open := smoothstep(land_at + LIGHT, length, at)
	var top := roundi(BAR_TOP * (1.0 - open))
	var low := roundi(lerpf(BAR_LOW, View.HEIGHT, open))
	if top > 0:
		c.fill_rect(0, 0, View.WIDTH, top, Color(0, 0, 0))
	if low < View.HEIGHT:
		c.fill_rect(0, low, View.WIDTH, View.HEIGHT - low, Color(0, 0, 0))
	_draw_card(c)
	_draw_caption(c)
	if at < land_at:
		var skip := "TAP TO SKIP" if m.input_device == "touch" else "ANY KEY SKIPS"
		c.anchor(View.shift)  # ASPECT WIDE: at the picture's right edge
		HUD.text(c, skip, 312, 4, "mini", HUD.DIM, false, false, true)
		c.anchor(0)
	var fade := 1.0 - clampf(at / FADE_IN, 0.0, 1.0)
	if fade > 0.0:
		_shade(c, 0, 0, View.WIDTH, View.HEIGHT, Color(0, 0, 0), fade)


## Draw-time caches kept in play's features that a draw before the first
## tick would set early (the variants' look for who holds a car door, once a
## second of game clock): put back after each frame, so the game starts with
## them as it would have.
const CACHES := {"variants": ["look_again", "looked_over", "shielded"]}


static func _keep_caches(g: Game) -> Dictionary:
	var out := {}
	for id: String in CACHES:
		var f: GameFeature = g.features.get(id)
		if f == null:
			continue
		var row := {}
		for key: String in CACHES[id]:
			var v: Variant = f.get(key)
			if v is Array:
				var list: Array = v
				v = list.duplicate()
			row[key] = v
		out[id] = row
	return out


static func _put_caches(g: Game, kept: Dictionary) -> void:
	for id: String in kept:
		var f: GameFeature = g.features.get(id)
		var row: Dictionary = kept[id]
		for key: String in row:
			f.set(key, row[key])


## How dark the view is: a dip at each cut and at the landing, most of the
## way to black while the boss is on, and light again as the camera lands.
func _darkness() -> float:
	var dark := 0.0
	var cuts := Array(_starts).slice(1)
	cuts.append(land_at)
	for cut: float in cuts:
		var off := absf(at - cut)
		if off < DIP:
			dark = maxf(dark, 1.0 - off / DIP)
	if at > boss_at:
		var shown := clampf((at - boss_at) / BOSS_FADE, 0.0, 1.0) * .9
		dark = maxf(dark, shown * (1.0 - clampf((at - land_at) / LIGHT, 0.0, 1.0)))
	return dark


## A rectangle of `col` laid over at `alpha` (with no window: solid past half).
func _shade(c: Canvas, x: int, y: int, w: int, h: int, col: Color, alpha: float) -> void:
	if c.gpu:
		var tex := _black if col.r < .5 else _white
		c.gpu_texture(tex, x, y, w, h, roundi(clampf(alpha, 0.0, 1.0) * 255.0))
	elif alpha >= .5:
		c.fill_rect(x, y, w, h, col)


func _draw_card(c: Canvas) -> void:
	var t := at - _title_at
	if t < 0.0 or t > STAY + LIFT or _card.is_empty():
		return
	var img: Image = _card["image"]
	var w := img.get_width()
	var h := img.get_height()
	var x := (View.WIDTH - w) / 2
	var y := float(CARD_Y)
	var board: bool = _card.get("board", true)
	var alpha := 1.0
	var scale := 1.0
	if board:
		# Dropped in on its ropes with a bounce, hauled up again at the end.
		if t < DROP:
			var k := t / DROP
			y = lerpf(-h - 4.0, CARD_Y, k * k)
		else:
			var since := t - DROP
			y = CARD_Y + sin(since * 13.0) * 5.0 * exp(-since * 5.5)
		if t > STAY:
			var k := (t - STAY) / LIFT
			y = lerpf(CARD_Y, -h - 6.0, k * k)
	else:
		# A B-movie title: it rushes in from big and settles.
		var k := clampf(t / DROP, 0.0, 1.0)
		scale = lerpf(3.2, 1.0, 1.0 - (1.0 - k) * (1.0 - k))
		alpha = k
		if t > STAY:
			alpha = 1.0 - clampf((t - STAY) / LIFT, 0.0, 1.0)
	var top := roundi(y)
	if board:
		var ropes: Array = _card.get("ropes", [])
		for rx: Variant in ropes:
			var rope_x: int = rx
			var px := x + rope_x
			c.fill_rect(px, BAR_TOP, 1, maxi(0, top - BAR_TOP + 2), Color(.36, .28, .2))
			c.fill_rect(px + 1, BAR_TOP, 1, maxi(0, top - BAR_TOP + 2), Color(.16, .12, .09))
	if c.gpu and _card_tex != null:
		var sw := roundi(w * scale)
		var sh := roundi(h * scale)
		var cx := View.WIDTH / 2 - sw / 2
		var cy := top + h / 2 - sh / 2
		c.gpu_texture(_card_tex, cx, cy, sw, sh, roundi(alpha * 255.0))
	else:
		c.blit_rgba(img.get_data(), w, h, x, top, "opener|card|" + chapter)
	_draw_bulbs(c, x, top, alpha)
	if board and t > DROP + .25 and t < STAY:
		_draw_tagline(c, top + h + GAP_TAG, t - DROP - .25)
	elif not board and t > DROP and t < STAY:
		_draw_tagline(c, top + h + GAP_TAG, t - DROP)


## The marquee's bulbs, chasing round it.
func _draw_bulbs(c: Canvas, x: int, y: int, alpha: float) -> void:
	var bulbs: Array = _card.get("bulbs", [])
	if bulbs.is_empty() or alpha < .5:
		return
	var step := int(at * 9.0)
	for i in bulbs.size():
		var b: Array = bulbs[i]
		var bx: int = b[0]
		var by: int = b[1]
		var lit := (i + step) % 3 != 0
		c.fill_rect(x + bx, y + by, 2, 2, Color(1, .92, .62) if lit else Color(.45, .3, .14))


## The tagline under the card, typed out a letter at a time.
func _draw_tagline(c: Canvas, y: int, t: float) -> void:
	var line := str(entry(chapter).get("tagline", ""))
	var shown := mini(line.length(), int(t * TYPE_RATE))
	if shown <= 0:
		return
	var full := PixelType.text_width(line, "body")
	var x := View.WIDTH / 2 - full / 2
	HUD.text(c, line.substr(0, shown), x, y, "body", HUD.INK, false, true)


## The boss against his light: the light fades in, he looms a little nearer,
## and as he growls the light flares.
func _draw_boss(c: Canvas) -> void:
	var t := at - boss_at - .15
	if t <= 0.0 or _boss_img == null:
		return
	# Gone into the landing's dip.
	var show := clampf(t / BOSS_FADE, 0.0, 1.0) * clampf((land_at - at) / DIP, 0.0, 1.0)
	if show <= 0.0:
		return
	var flare := 0.0
	var since := at - growl_at
	if since > 0.0:
		flare = exp(-since * 4.0)
	var top := BAR_TOP
	var area := BAR_LOW - BAR_TOP
	var light_alpha := clampf(show * (.88 + flare * .3), 0.0, 1.0)
	var which := 0
	if _light_imgs.size() > 1:
		which = int(at * 5.0) % _light_imgs.size()
	var bw := _boss_img.get_width()
	var bh := _boss_img.get_height()
	var loom := 0.9 + .1 * clampf(t / maxf(1.0, length - boss_at), 0.0, 1.0) + flare * .05
	var sw := roundi(bw * loom)
	var sh := roundi(bh * loom)
	var feet := BAR_LOW - 4
	if c.gpu:
		for n in _lights.size():
			var strength := 1.0 if n == which or _lights.size() == 1 else .3
			c.gpu_texture(
				_lights[n], 0, top, View.WIDTH, area, roundi(light_alpha * strength * 255.0)
			)
		if flare > .05:
			_shade(c, 0, top, View.WIDTH, area, Color(1, 1, 1), flare * .35)
		if _boss_tex != null:
			c.gpu_texture(
				_boss_tex, View.WIDTH / 2 - sw / 2, feet - sh, sw, sh, roundi(show * 255.0)
			)
	elif show >= .5:
		var glow := _light_imgs[which]
		c.blit_rgba(glow.get_data(), glow.get_width(), glow.get_height(), 80, top + 32, "")
		c.blit_rgba(_boss_img.get_data(), bw, bh, View.WIDTH / 2 - bw / 2, feet - bh, "")


## What is said, in the bar under the picture (VOICE CAPTIONS).
func _draw_caption(c: Canvas) -> void:
	if not game.voice_captions or _caption == "" or at > _caption_until:
		return
	var lines := caption_lines(_caption)
	var color := HUD.AMBER if _boss_caption else HUD.INK
	for i in mini(2, lines.size()):
		HUD.text(c, lines[i], View.WIDTH / 2, BAR_LOW + 10 + i * 11, "body", color, true, false)


## A caption in one line, or two split at the sentence nearest the middle
## (else wrapped), so a line never ends on a lone word.
static func caption_lines(text: String) -> PackedStringArray:
	if PixelType.text_width(text, "body") <= 276:
		return PackedStringArray([text])
	var best := -1
	for i in range(1, text.length() - 1):
		var mark := text[i - 1]
		if text[i] == " " and (mark == "." or mark == "?" or mark == "," or mark == "!"):
			if best < 0 or absi(i - text.length() / 2) < absi(best - text.length() / 2):
				best = i
	if best > 0:
		return PackedStringArray([text.substr(0, best), text.substr(best + 1)])
	return PixelType.wrap(text, 296, "body")


# ------------------------------------------------------------------ the frames


## For sorting [time, ...] rows (or [name, time]: `index` says which).
static func sooner(a: Array, b: Array, index: int) -> bool:
	var ta: float = a[index]
	var tb: float = b[index]
	return ta < tb


## The moments worth a picture: the middle of each shot, the card hung, the
## boss lit, the boss growling, the boss's line, the landing.
func key_times() -> Array:
	var out: Array = []
	for k in _starts.size():
		var shot: Dictionary = shots_of(chapter)[k]
		var secs: float = shot.get("secs", 3.0)
		out.append(["shot%d" % k, _starts[k] + secs * .5])
	out.append(["card", _title_at + DROP + 1.6])
	out.append(["boss", boss_at + BOSS_FADE + .6])
	out.append(["growl", growl_at + .25])
	out.append(["line", line_at + .5])
	out.append(["land", land_at + OpenerCamera.LAND * .6])
	out.sort_custom(sooner.bind(1))
	return out


## --opener-out: start the chapter, hold the opener at each key moment, save
## the window's picture of it, quit.
func capture(m: MainState) -> void:
	m.set_process(false)
	for _i in 4:
		await m.get_tree().process_frame
	if not playing:
		start(m)
	if not playing:
		push_error("no opener for " + forced)
		m.get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(shots_out)
	var times := key_times()
	if strip > 0:
		# The flight over the level, then the landing.
		times = []
		for n in strip + 3:
			var when := boss_at * (n + .5) / strip
			if n >= strip:
				when = land_at + OpenerCamera.LAND * (.25 + (n - strip) * .37)
			times.append(["f%03d_%.2f" % [n, when], when])
	for k: Array in times:
		var when: float = k[1]
		at = when
		_cues.clear()
		_caption = ""
		_caption_until = at + 1.0
		if at >= line_at:
			_caption = _caption_for("")
			_boss_caption = true
		elif at > boss_at + .3 and lines_of(chapter).size() > 1:
			_caption = lines_of(chapter)[1]
			_boss_caption = false
		elif at > .55 and at < boss_at:
			_caption = lines_of(chapter)[0]
			_boss_caption = false
		for _f in 3:
			m.render()
			await RenderingServer.frame_post_draw
		m.get_viewport().get_texture().get_image().save_png(
			"%s/%s_%s.png" % [shots_out, chapter, str(k[0])]
		)
	m.get_tree().quit()
