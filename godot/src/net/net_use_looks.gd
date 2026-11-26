## USE on a door (or a note) answered at the press. The copy only opens a
## door when it plays our USE, a round trip and the playout later, so the
## door stood shut under the hand for a third of a second. Now, looks only:
## at a fresh USE press that the copy would answer with a door (game_use.gd
## interact's checks: no remote switch, the key held, not a powder store,
## the hatch crouched under) the door's sound plays and it is drawn swinging
## from the press at the copy's speed (Level.update's 1.65 a second); once
## the copy has toggled it too, the drawn one keeps ahead until the copy's
## catches up; a USE the host never played (the door still as it was after
## WAIT) lets the door go back to the copy's. A note's words show at once.
## Fields set for the frame only (begin) and put back after it (end).
class_name NetUseLooks
extends RefCounted

## Off: a door swings when the copy plays USE (net_feel `old`).
static var enabled := true
## Seconds a door swung on our screen waits for the copy's.
const WAIT := 1.2
## Level.update's door speed (a second).
const SPEED := 1.65

## {"door", "open" (where it is going), "from" (its progress at the press),
## "at" (ms), "copied" (the copy toggled it)}.
var doors: Array = []
## For net_feel.gd and predict_check: doors answered at the press.
var answered := 0


## A fresh USE press: answered here when the copy would answer it with a
## door or a note. Returns the cue played ("" none), for the copy's own to
## be dropped (net_echo_sound.gd).
func press(game: Game, me: Player, now_ms: float) -> String:
	if not enabled or me.health <= 0 or game.showing_tally or game.boss_hold > 0.0:
		return ""
	var was := game.player
	game.player = me
	var found: Variant = GameUse.use_target(game)
	game.player = was
	if found == null:
		return ""
	var list: Array = found
	var target: Variant = list[0]
	if target is LevelData.Note:
		var note: LevelData.Note = target
		game.message(note.text, 4.0)
		game.sound.play("menu_move", .40)
		answered += 1
		return "menu_move"
	if not (target is LevelData.Door):
		return ""
	var door: LevelData.Door = target
	var cell := Vector2i(door.x, door.y)
	if game.world.controlled_doors.has(cell) or door.blast_only or door.bar_side != 0:
		return ""
	if door.key != "" and not game.keys.has(door.key):
		return ""
	if game.world.crouch_doors.has(cell) and not me.crouched and not door.discovered:
		return ""
	for d: Dictionary in doors:
		if d["door"] == door:
			return ""  # already swinging on our screen
	(
		doors
		. append(
			{
				"door": door,
				"open": not door.opened,
				"from": door.progress,
				"at": now_ms,
				"copied": false,
			}
		)
	)
	var cue := "secret_slide" if door.secret else "gate" if door.key != "" else "door"
	var centre := door.center()
	game.sound_at(cue, centre.x, centre.y)
	answered += 1
	return cue


## The doors drawn where our USE has them this frame; returns what end()
## puts back.
func begin(now_ms: float) -> Array:
	var kept: Array = []
	for d: Dictionary in doors.duplicate():
		var door: LevelData.Door = d["door"]
		var open: bool = d["open"]
		var at: float = d["at"]
		var from: float = d["from"]
		var age := (now_ms - at) / 1000.0
		var copied: bool = d["copied"]
		if door.opened == open:
			copied = true
			d["copied"] = true
		elif copied or age > WAIT:
			doors.erase(d)  # the copy shut it again, or never opened it
			continue
		var want := clampf(from + (SPEED if open else -SPEED) * age, 0.0, 1.0)
		var drawn := maxf(want, door.progress) if open else minf(want, door.progress)
		if copied and is_equal_approx(drawn, door.progress):
			doors.erase(d)  # the copy's has caught up
			continue
		kept.append([door, door.progress])
		door.progress = drawn
	return kept


static func end(kept: Array) -> void:
	for i in range(kept.size() - 1, -1, -1):
		var row: Array = kept[i]
		var door: LevelData.Door = row[0]
		door.progress = row[1]


func forget() -> void:
	doors.clear()
