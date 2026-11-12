## The true finale: what shows once a campaign run finishes the last chapter
## (Campaign.ORDER's last, the Mothership). First the whole campaign's tally
## under a county-fair heading, then the credits rolling up over the title
## backdrop, then the tally again, round and round till ENTER takes the player
## back to the Crossroads (main_flow.gd continue_campaign). hud.gd
## campaign_report() draws the backdrop and hands over to this.
class_name Finale
extends RefCounted

## Seconds the tally stands before the credits roll, and how fast they go up
## (canvas rows a second).
const TALLY_SECONDS := 9.0
const ROLL_SPEED := 16.0
const TOP := 20
const BOTTOM := 170
## The roll: [kind, text]; kind sets the type and the gap under it.
const ROLL := [
	["title", "CRAZY LEGS MUNDELL"],
	["title", "RAMPAGE"],
	["gap", ""],
	["head", "STARRING"],
	["line", "CRAZY LEGS MUNDELL AS HIMSELF"],
	["line", "BESSIE AS THE COW"],
	["line", "MAW GLORB AS EVERYBODY'S MAW"],
	["line", "THE ALIEN SHERIFF (DECEASED)"],
	["gap", ""],
	["head", "ALSO APPEARING"],
	["line", "JERRY JONES, RUDY RACKET"],
	["line", "THE SPLINTER FOREMAN AND THE COPPER BARON"],
	["line", "BILLIES, COOTS, CLONES AND SKEETERS"],
	["line", "GREYS IN DEAD MEN'S OVERALLS"],
	["line", "TIN GUARDS, ONE TAILGATE APIECE"],
	["line", "A PROBE WITH ONE EYE AND NO MANNERS"],
	["line", "FORTY HEAD OF CATTLE, MAD AS HORNETS"],
	["gap", ""],
	["head", "THE 1997 INSPIRATION"],
	["line", "REDNECK RAMPAGE / XATRIX ENTERTAINMENT"],
	["head", "PHOTOGRAPHS"],
	["line", "JERRY JONES / KEITH ALLISON (CC BY-SA 2.0)"],
	["line", "ROADSIDE / JOHN MARGOLIES, LIBRARY OF CONGRESS"],
	["head", "MATERIALS AND AUDIO"],
	["line", "SCORE AND EFFECTS / ELEVENLABS, FINISHED BY HAND"],
	["line", "FULL CREDITS IN THIRD_PARTY_NOTICES.MD"],
	["gap", ""],
	["line", "NO COWS WERE PROBED IN THE MAKING OF THIS GAME."],
	["line", "ONE WAS ASKED. SHE SAID NO."],
	["gap", ""],
	["head", "THE END"],
	["line", "TELL YER MAW."],
]
const ROW_HEIGHT := {"title": 18, "head": 13, "line": 10, "gap": 10}


static func draw(c: Canvas, game) -> void:
	HUD.panel(c, 10, 9, 300, 180)
	var since := _since(game)
	var roll_length := 0
	for row: Array in ROLL:
		roll_length += int(ROW_HEIGHT[String(row[0])])
	var cycle := TALLY_SECONDS + (roll_length + BOTTOM - TOP) / ROLL_SPEED + 1.0
	var t := fmod(since, cycle)
	if t < TALLY_SECONDS:
		_tally(c, game)
	else:
		_roll(c, (t - TALLY_SECONDS) * ROLL_SPEED)
	HUD.text(c, "ENTER  RETURN TO CROSSROADS", 160, 177, "body", HUD.INK, true)


## Seconds since the chapter was won (real time: play has stopped).
static func _since(game) -> float:
	var show = game.features.get("tally")
	var won_at: int = show.won_at if show != null else -1
	if won_at < 0:
		return 0.0
	return (Time.get_ticks_msec() - won_at) / 1000.0


## Every chapter's kills, secrets and time, the totals, the last chapter's line.
static func _tally(c: Canvas, game) -> void:
	HUD.text(c, "THE COUNTY IS SAFE", 160, 14, "heading", HUD.AMBER, true)
	HUD.text(c, "FOR NOW.", 160, 32, "mini", HUD.DIM, true)
	var columns := [186, 237, 296]
	var heads := ["KILLS", "SECRETS", "TIME"]
	HUD.text(c, "CHAPTER", 21, 42, "body", HUD.INK)
	for i in 3:
		HUD.text(c, heads[i], columns[i], 42, "body", HUD.INK, false, true, true)
	var results: Array = game.history.duplicate()
	results.append(game.result())
	var step := 12 if results.size() > 6 else 14
	var totals := [0, 0, 0, 0, 0]
	for i in results.size():
		var row: Array = results[i]
		var y := 54 + step * i
		c.fill_rect(17, y - 2, 286, step - 2, Color(30 / 255.0, 21 / 255.0, 17 / 255.0))
		HUD.text(c, Campaign.title_of(String(row[0])), 21, y, "body", HUD.INK)
		var values := [
			"%d/%d" % [int(row[1]), int(row[2])],
			"%d/%d" % [int(row[3]), int(row[4])],
			"%d:%02d" % [int(row[5]) / 60, int(row[5]) % 60]
		]
		for k in 3:
			HUD.text(c, values[k], columns[k], y, "body", HUD.AMBER, false, true, true)
		for k in 5:
			totals[k] += int(row[k + 1])
	var total_y := 54 + step * results.size() + 3
	HUD.text(c, "TOTAL", 21, total_y, "body", HUD.AMBER)
	var summed := [
		"%d/%d" % [totals[0], totals[1]],
		"%d/%d" % [totals[2], totals[3]],
		"%d:%02d" % [totals[4] / 60, totals[4] % 60]
	]
	for k in 3:
		HUD.text(c, summed[k], columns[k], total_y, "body", HUD.AMBER, false, true, true)
	HUD.text(c, game.level.ending, 160, mini(total_y + 14, 164), "body", HUD.AMBER, true)


## The credits, `scrolled` rows up from the bottom of the panel.
static func _roll(c: Canvas, scrolled: float) -> void:
	var y := BOTTOM - scrolled
	for row: Array in ROLL:
		var kind := String(row[0])
		var tall := int(ROW_HEIGHT[kind])
		if kind != "gap" and y > TOP - 2 and y < BOTTOM - 8:
			var style := "heading" if kind == "title" else "body"
			var colour := HUD.AMBER if kind != "line" else HUD.INK
			HUD.text(c, String(row[1]), 160, int(y), style, colour, true)
		y += tall
