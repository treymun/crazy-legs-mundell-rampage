## Heat lightning over the fields: on a level whose mood has `lightning`
## (effects.cfg), a flash every so often lights the sky and the yard
## (game.lightning, read by the display shader), and thunder rolls in a few
## seconds after. Its own dice, never the game's; off with SCREEN FLASHES off
## or LIGHTS AND GLOW off; the hub stays calm.
extends GameFeature

var dice := RandomNumberGenerator.new()
var next_flash := 0.0
var flash_age := -1.0
var thunder_at := -1.0
var thunder_far := 1.0


func id() -> String:
	return "weather"


func attach() -> void:
	dice.seed = hash(game.level.id) + 51
	next_flash = 12.0 + dice.randf_range(0.0, 20.0)
	game.ticked.connect(_tick)


func _tick(dt: float) -> void:
	var rate := float(Effects.mood(game.level.id, "lightning", 0.0))
	if rate <= 0.0 or game.in_hub or game.flash_scale <= 0.0 or not Effects.enabled:
		game.lightning = 0.0
		return
	if game.clock >= next_flash:
		next_flash = game.clock + 60.0 / rate * dice.randf_range(.5, 1.5)
		flash_age = 0.0
		thunder_far = dice.randf_range(.4, 1.0)
		thunder_at = game.clock + 1.0 + thunder_far * 3.5
	if flash_age >= 0.0:
		flash_age += dt
		# Two quick strokes and a fading glow.
		var flash := 0.0
		if flash_age < .08:
			flash = 1.0
		elif flash_age < .16:
			flash = .25
		elif flash_age < .26:
			flash = .8
		elif flash_age < .9:
			flash = .8 * (1.0 - (flash_age - .26) / .64)
		else:
			flash_age = -1.0
		game.lightning = flash * game.flash_scale
	else:
		game.lightning = 0.0
	if thunder_at > 0.0 and game.clock >= thunder_at:
		thunder_at = -1.0
		game.sound.play("thunder", .55 * (1.2 - thunder_far * .6), dice.randf_range(-.4, .4))
