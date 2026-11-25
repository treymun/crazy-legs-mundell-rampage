## How being hurt looks (pass 15, effects.cfg [hurt_looks]; this machine's
## player only): a blow draws a red-brown vignette in from the view's edges,
## the palette's blood dithered in quarters, as deep as the blow was hard,
## fading over `pain_fade`; under `low_from` health the world drains toward
## sepia and the vignette holds; under `heart_from` the heart thumps (a made
## cue), quicker the lower he is, each beat swelling the vignette. The
## display shader draws it (`pain`, `drain`) on the 3D view, under the gun,
## the HUD and a RAMPAGE's burning edge; the old red flash of a blow stays.
## SCREEN FLASHES scales it. Looks only: worked out from the clock, the blows
## and the health, nothing saved or carried, no dice.
class_name HurtLooks
extends GameFeature

## The last blow: when (game clock) and how deep its vignette (0 to 1).
var hit_at := -100.0
var hit_k := 0.0
## The heart: its beats so far (whole beats thump) and the clock it was last
## counted at, and when it last thumped.
var beat := 0.0
var beat_clock := -1.0
var thump_at := -100.0


func id() -> String:
	return "hurt_looks"


func attach() -> void:
	game.events.player_hurt.connect(_hurt)


static func n(key: String, fallback: float) -> float:
	var v: float = Effects.num("hurt_looks", key, fallback)
	return v


func _hurt(amount: float, _cause: String) -> void:
	if not game.acting_local():
		return
	var k := clampf(amount / maxf(1.0, n("pain_full", 30.0)), n("pain_floor", .3), 1.0)
	# A blow on a blow still showing adds to what is left of it.
	hit_k = minf(1.0, maxf(k, _pain_now() + k * .5))
	hit_at = game.clock


## What is left of the last blow's vignette now.
func _pain_now() -> float:
	var fade := maxf(.05, n("pain_fade", 1.1))
	var left := 1.0 - (game.clock - hit_at) / fade
	return hit_k * clampf(left, 0.0, 1.0) if left > 0.0 else 0.0


## How low the local player is: 0 at `low_from` health and over, 1 at
## `drain_full` and under.
func lowness() -> float:
	var p := game.local_player
	if p == null:
		return 0.0
	var low := n("low_from", 30.0)
	var full := n("drain_full", 8.0)
	return clampf((low - float(p.health)) / maxf(1.0, low - full), 0.0, 1.0)


## The vignette (display.gdshader `pain`, 0 to 1) this frame, before SCREEN
## FLASHES.
func vignette() -> float:
	var held := lowness() * n("low_edge", .42)
	var since := game.clock - thump_at
	var thump := n("thump", .22) * clampf(1.0 - since / .32, 0.0, 1.0) if since >= 0.0 else 0.0
	if lowness() <= 0.0:
		thump = 0.0
	return clampf(maxf(_pain_now(), held) + thump, 0.0, 1.0)


## How far the colour has drained (display.gdshader `drain`, 0 to 1).
func drained() -> float:
	return lowness() * n("drain_most", .72)


## The heart, counted as the view draws (a drawn frame is this machine's).
func draw_view(_c: Canvas) -> void:
	var p := game.local_player
	var from := n("heart_from", 20.0)
	if p == null or p.health <= 0 or float(p.health) > from or beat_clock < 0.0:
		beat_clock = game.clock
		beat = 0.0
		return
	var dt := clampf(game.clock - beat_clock, 0.0, .25)
	beat_clock = game.clock
	var share := clampf((from - float(p.health)) / maxf(1.0, from - 1.0), 0.0, 1.0)
	var per_minute := lerpf(n("heart_slow", 72.0), n("heart_fast", 120.0), share)
	var was := beat
	beat += dt * per_minute / 60.0
	if floorf(beat) > floorf(was):
		thump_at = game.clock
		if game.sound != null:
			game.sound.play("heart_thump", n("thump_volume", .7))


## The display shader's hurt numbers for this frame (main_state.gd): the
## old red flash `hurt` as before, the vignette `pain` and the drain `drain`
## (none in the menus, in PHOTO MODE or an opener's or the KILL CAM's eye).
static func uniforms(material: ShaderMaterial, g: Game, playing: bool) -> void:
	material.set_shader_parameter("hurt", g.hurt_alpha if playing else 0)
	var pain := 0.0
	var drain := 0.0
	var looks: HurtLooks = g.features.get("hurt_looks") if g != null else null
	if playing and looks != null and g.eye_override.is_empty() and g.flash_scale > 0.0:
		pain = looks.vignette() * g.flash_scale
		drain = looks.drained() * sqrt(g.flash_scale)
	material.set_shader_parameter("pain", pain)
	material.set_shader_parameter("drain", drain)
