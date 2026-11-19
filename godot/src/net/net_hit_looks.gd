## A hand our shot or blow struck flinches at once. The copy only hurts it
## when it plays our input, a round trip and the playout later, so the mark
## and the blood showed at the press (net_shot_predict.gd) while the hand
## stood unmoved and then jerked a third of a second after. Now, looks only:
## from the press the hand is drawn with the hit's flash and its pain pose
## (Enemy.hit_flash, flinch: Enemy.hurt's sums for the gun's damage); when
## the copy's own hurt lands (the hit confirmed) its flash and flinch are not
## drawn again for their length; a hit the host judged a miss stops at once.
## Fields set for the frame only (begin) and put back after it (end).
class_name NetHitLooks
extends RefCounted

## Off: the hand flinches when the copy plays the hit (net_feel `old`).
static var enabled := true

## {"who": Enemy, "at" (ms), "flash", "flinch", "from" (the shown shot)}.
var shown: Array = []
## Enemy -> the copy's clock until which its own flinch is not drawn.
var muted := {}
## For net_feel.gd: reactions drawn at the press.
var drawn := 0


## Our hit on `who` shown at the press (`from`: net_shot_predict.gd's
## shown dictionary), `amount` the gun's damage.
func struck(who: Object, amount: float, from: Dictionary, now_ms: float) -> void:
	if not enabled or not (who is Enemy):
		return
	var e: Enemy = who
	if not e.hostile:
		return
	(
		shown
		. append(
			{
				"who": e,
				"at": now_ms,
				"flash": .075 + minf(.06, amount * .0016),
				"flinch": .14 + minf(.16, amount * .004),
				"from": from,
			}
		)
	)
	drawn += 1


## The host said no: the flinch stops.
func withdraw(from: Dictionary) -> void:
	for r: Dictionary in shown.duplicate():
		if r["from"] == from:
			shown.erase(r)


## The copy's own hurt for a hit we showed: not drawn again for its length.
func confirmed(game: Game, from: Dictionary) -> void:
	for r: Dictionary in shown:
		if r["from"] == from:
			var e: Enemy = r["who"]
			muted[e] = game.clock + maxf(e.flinch, e.hit_flash) + NetSync.STEP


## Puts the reactions on for this frame; returns what end() puts back.
func begin(game: Game, now_ms: float) -> Array:
	var kept: Array = []
	for e: Enemy in muted.keys():
		var until: float = muted[e]
		if game.clock >= until:
			muted.erase(e)
	for r: Dictionary in shown.duplicate():
		var at: float = r["at"]
		var flash0: float = r["flash"]
		var flinch0: float = r["flinch"]
		var age := (now_ms - at) / 1000.0
		var flash := flash0 - age
		var flinch := flinch0 - age
		if flash <= 0.0 and flinch <= 0.0:
			shown.erase(r)
			continue
		var e: Enemy = r["who"]
		if not e.alive:
			continue
		kept.append([e, e.hit_flash, e.flinch])
		e.hit_flash = maxf(0.0, flash)
		e.flinch = maxf(0.0, flinch)
	for e: Enemy in muted:
		if _has(kept, e):
			continue
		kept.append([e, e.hit_flash, e.flinch])
		e.hit_flash = 0.0
		e.flinch = 0.0
	return kept


static func end(kept: Array) -> void:
	for i in range(kept.size() - 1, -1, -1):
		var row: Array = kept[i]
		var e: Enemy = row[0]
		e.hit_flash = row[1]
		e.flinch = row[2]


func forget() -> void:
	shown.clear()
	muted.clear()


static func _has(kept: Array, e: Enemy) -> bool:
	for row: Array in kept:
		if row[0] == e:
			return true
	return false
