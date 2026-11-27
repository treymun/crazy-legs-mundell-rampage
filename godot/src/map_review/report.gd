## A map check's report as plain words (report.md): the verdict first, then
## every finding by level (MUST FIX, SHOULD, NICE) with where it is, what is
## wrong, how to fix it and the county's own word on it, then the numbers, the
## routes walked, the bot's run and the pictures. Made from the check's
## result (tools/map/map_check_cli.gd writes report.json from the same).
class_name MapReport
extends RefCounted

const L := preload("res://src/map_review/review_lines.gd")


static func markdown(res: Dictionary) -> String:
	var t := PackedStringArray()
	var id := str(res.get("id", "?"))
	var verdict := str(res.get("verdict", "?"))
	var findings: Array = res.get("findings", [])
	var counts := L.counts(findings)
	var quick: bool = res.get("quick", false)
	t.append("# Map check: %s" % id)
	t.append("")
	t.append("**%s**" % L.verdict_line(verdict))
	t.append("")
	t.append("> %s" % L.verdict_say(verdict))
	t.append("")
	t.append(
		(
			"%d MUST FIX, %d SHOULD, %d NICE. The check took %s s after Godot started%s."
			% [
				counts["MUST FIX"],
				counts["SHOULD"],
				counts["NICE"],
				str(res.get("seconds", "?")),
				" (quick: no bot run, no pictures)" if quick else ""
			]
		)
	)
	t.append("")
	t.append(
		(
			"How to read this: each item says where (map x, y and z: x east, y south, z up),"
			+ " what is wrong and how to fix it. Fix every MUST FIX (the map is broken"
			+ " without it), then the SHOULD items (it plays worse without them). NICE"
			+ " items are ideas. Then run the check again."
		)
	)
	for level: String in L.LEVELS:
		var mine: Array = []
		for f: Dictionary in findings:
			if f["level"] == level:
				mine.append(f)
		t.append("")
		t.append("## %s (%d)" % [level, mine.size()])
		t.append("")
		if mine.is_empty():
			t.append("Nothing.")
			continue
		var n := 0
		for f: Dictionary in mine:
			n += 1
			var obj := str(f.get("object", ""))
			var spot: Array = f.get("at", [])
			var where := L.place(spot)
			t.append(
				(
					"%d. **%s** at %s%s: %s"
					% [n, f["check"], where, "" if obj == "" else " [%s]" % obj, f["what"]]
				)
			)
			if str(f.get("fix", "")) != "":
				t.append("   - Fix: %s" % f["fix"])
			if str(f.get("say", "")) != "":
				t.append('   - "%s"' % f["say"])
	var numbers: Dictionary = res.get("numbers", {})
	var routes: Array = res.get("routes", [])
	var bot: Dictionary = res.get("bot", {})
	_numbers(t, numbers)
	_routes(t, routes)
	_bot(t, bot)
	_pictures(t, res)
	t.append("")
	return "\n".join(t)


static func _numbers(t: PackedStringArray, numbers: Dictionary) -> void:
	if numbers.is_empty():
		return
	t.append("")
	t.append("## The numbers")
	t.append("")
	t.append("| measure | value |")
	t.append("| --- | --- |")
	var keys: Array = numbers.keys()
	keys.sort()
	for key: Variant in keys:
		t.append("| %s | %s |" % [str(key).replace("_", " "), str(numbers[key])])


static func _routes(t: PackedStringArray, routes: Array) -> void:
	if routes.is_empty():
		return
	t.append("")
	t.append("## Routes walked (a player's body, every door open)")
	t.append("")
	t.append("| route | result | seconds | walked |")
	t.append("| --- | --- | --- | --- |")
	for r: Dictionary in routes:
		var ok: bool = r.get("reached", false)
		t.append(
			(
				"| %s | %s | %s | %s |"
				% [
					r.get("id", "?"),
					"reached" if ok else "FAILED, stopped at %s" % str(r.get("end", "?")),
					str(r.get("seconds", "")),
					str(r.get("walked", ""))
				]
			)
		)


static func _bot(t: PackedStringArray, bot: Dictionary) -> void:
	if bot.is_empty():
		return
	t.append("")
	t.append("## The bot's run")
	t.append("")
	t.append(
		(
			(
				"The balance bot (%s, NORMAL, seed %s, god mode off) played the map from the"
				+ " start kit: **%s** after %s s of play, %s death(s), %s kills."
			)
			% [
				bot.get("skill", "?"),
				str(bot.get("seed", "?")),
				bot.get("outcome", "?"),
				str(bot.get("secs", "?")),
				str(bot.get("deaths", 0)),
				str(bot.get("kills", 0))
			]
		)
	)
	var flow: Dictionary = bot.get("flow", {})
	if not flow.is_empty():
		t.append("")
		t.append("| flow | value |")
		t.append("| --- | --- |")
		for key: String in [
			"fight",
			"walk",
			"idle",
			"first_fight",
			"longest_calm",
			"lost30_n",
			"backtrack",
			"dry",
			"low"
		]:
			if flow.has(key):
				t.append("| %s | %s |" % [key.replace("_", " "), str(flow[key])])


static func _pictures(t: PackedStringArray, res: Dictionary) -> void:
	var pics: Array = res.get("pictures", [])
	var plans: Array = res.get("plans", [])
	t.append("")
	t.append("## Pictures")
	t.append("")
	if str(res.get("sheet", "")) != "":
		t.append("Everything on one sheet: `%s`" % res["sheet"])
		t.append("")
	for p: Variant in plans:
		t.append("- plan from above: `%s`" % str(p))
	for p: Dictionary in pics:
		t.append("- %s: `%s` (%s)" % [p.get("tag", ""), p.get("file", ""), p.get("what", "")])
	if str(res.get("pictures_skipped", "")) != "":
		t.append("- 3D pictures skipped: %s" % res["pictures_skipped"])
