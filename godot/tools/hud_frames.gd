## Pictures of every menu screen and of the HUD in its crowded moments
## (tools/hud_crowd.gd) in a real window, to read for overlaps, clipped or
## tiny text and anything out of theme: menu_<state>.png (each SETTINGS page
## as menu_setup_<n>.png), hud_<moment>.png, tally_<level>.png and the end
## card as a run leaves it, tally_card_<n>.png. Run it at
## several window sizes (--resolution) to see the picture scaled.
##
##   godot --path godot --audio-driver Dummy --resolution 1280x800 \
##       --script res://tools/hud_frames.gd -- out=<dir> [only=menus,hud,tally]
##
## Point APPDATA at a scratch folder: it runs the game with the profile there.
extends SceneTree

const Crowd := preload("res://tools/hud_crowd.gd")
const MENUS := [
	"title",
	"slots",
	"replays",
	"controls",
	"credits",
	"rematch",
	"county",
	"maps",
	"mapedit",
	"multi",
	"showdown",
	"servers",
	"nethost",
	"netjoin",
]

var main
var out := ""
var only: Array = ["menus", "hud", "tally"]


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("out="):
			out = String(arg).substr(4)
		elif String(arg).begins_with("only="):
			only = String(arg).substr(5).split(",")
	if out == "":
		push_error("out=<dir> is needed")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out)
	main = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.touring = true
	Effects.enabled = true
	if only.has("menus"):
		await _menus()
	if only.has("hud"):
		for moment: Array in Crowd.MOMENTS:
			var g: Game = Crowd.make(main, str(moment[0]))
			if g != null:
				await _snap("hud_" + str(moment[0]))
		PixelType.clear_small = false
		main.hud.minimal = false
		main.touch.showing = false
	if only.has("tally"):
		for level: String in ["hickston", "moonshine"]:
			var g: Game = main.make_game(level)
			main.game = g
			main.state = "play"
			g.configure(SessionStore.defaults())
			g.won = true  # the chapter won: its tally is up
			await _snap("tally_" + level)
		await _cards()
	print("hud frames written to ", out)
	main.queue_free()
	await process_frame
	quit()


## The end card as a run leaves it (pass 15, src/tally_card.gd): the bests
## beside the rows, the ribbon and NEW BEST, its plates in each device's
## words, and in SMALL TEXT: tally_card_<n>.png.
func _cards() -> void:
	var looks := [
		["fair", "keys", false, true],
		["sawmill", "pad", false, false],
		["bayou", "touch", true, true],
		["hickston", "keys", true, false],
	]
	for i in looks.size():
		var look: Array = looks[i]
		var g: Game = main.make_game(str(look[0]))
		main.game = g
		main.state = "play"
		g.configure(SessionStore.defaults())
		g.kills = g.total_kills - 3
		g.secrets = 1
		g.clock = ChapterBests.par(g.level.id) * (.8 if look[3] else 1.3)
		g.won = true
		main.input_device = str(look[1])
		g.input_device = main.input_device
		main.watch_tally()
		var show = g.features["tally"]
		var faster: bool = look[3]
		show.card = {
			"settled": true,
			"kept_bests": true,
			"difficulty": "NORMAL",
			"old":
			{"time": g.clock + (20.0 if faster else -40.0), "kills": g.kills - 2, "secrets": 2},
			"time": faster,
			"kills": faster,
			"secrets": false,
		}
		PixelType.clear_small = look[2]
		main.touch.active = main.input_device == "touch"  # its buttons as a phone shows them
		await _snap("tally_card_%d" % i)
	PixelType.clear_small = false
	main.input_device = "keys"
	main.touch.active = false
	main.touch.set_showing(false)


func _menus() -> void:
	main.game = null
	for state: String in MENUS:
		if state == "slots":
			main.refresh_slots()
		main.state = state
		await _snap("menu_" + state)
	main.state = "setup"
	for page in SessionStore.setup_pages().size():
		main.option_page = page
		main.option_scroll = 0
		await _snap("menu_setup_%d" % page)


func _snap(name: String) -> void:
	main.render()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))
