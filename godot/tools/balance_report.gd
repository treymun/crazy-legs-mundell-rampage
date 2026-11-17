## The tables tools/balance.gd prints from its runs' lines of JSON (`report
## in=<dir or file>`): per difficulty and chapter the attempts, deaths and
## death rate, clear time, health, rounds and scrap at the end, finishers,
## boots, hazard kills and the hound's work; where the deaths cluster; the
## bosses' times; each gun's kills and shots a kill; when the bench's mods
## were bought; COUNTY RUN's survival, XP curve and cards picked.
extends RefCounted

const DIFFS := ["EASY", "NORMAL", "HARD", "HOG WILD"]
const SKILLS := ["rookie", "regular", "sharp"]


static func load_rows(source: String) -> Array:
	var files: Array = []
	if DirAccess.dir_exists_absolute(source):
		for name: String in DirAccess.get_files_at(source):
			if name.ends_with(".jsonl"):
				files.append(source.path_join(name))
	elif FileAccess.file_exists(source):
		files.append(source)
	var rows: Array = []
	for path: String in files:
		var f := FileAccess.open(path, FileAccess.READ)
		while not f.eof_reached():
			var line := f.get_line().strip_edges()
			if line == "":
				continue
			var row: Variant = JSON.parse_string(line)
			if row is Dictionary:
				rows.append(row)
	return rows


static func median(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var v := values.duplicate()
	v.sort()
	return float(v[v.size() / 2])


static func mean(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var s := 0.0
	for x: Variant in values:
		s += float(x)
	return s / values.size()


static func tables(source: String) -> String:
	var rows := load_rows(source)
	var out: PackedStringArray = []
	var chapter_rows: Array = []
	var county_rows: Array = []
	for r: Dictionary in rows:
		if str(r.get("mode", "")) == "county":
			county_rows.append(r)
		elif r.has("outcome"):
			chapter_rows.append(r)
	out.append(
		"%d chapter attempts, %d County Run runs" % [chapter_rows.size(), county_rows.size()]
	)
	_chapters(chapter_rows, out)
	_skills(chapter_rows, out)
	_clusters(chapter_rows, out)
	_bosses(chapter_rows, out)
	_guns(chapter_rows, out)
	_bench(chapter_rows, out)
	_county(county_rows, out)
	return "\n".join(out) + "\n"


## Keyed groups: key -> rows.
static func group(rows: Array, key: Callable) -> Dictionary:
	var g := {}
	for r: Dictionary in rows:
		var k: Variant = key.call(r)
		if not g.has(k):
			g[k] = []
		g[k].append(r)
	return g


static func _chapters(rows: Array, out: PackedStringArray) -> void:
	out.append("\n## Chapters by difficulty (all skills)")
	out.append(
		(
			"| diff | chapter | runs | attempts | deaths/run | died first try | clear s (med)"
			+ " | health end | ammo end | dry s | scrap found | kills | eaten | finishers"
			+ " | boots | hazards | hound bites/pins | ride s |"
		)
	)
	out.append("| --- ".repeat(18) + "|")
	var by := group(
		rows,
		func(r: Dictionary) -> String:
			return "%d|%02d|%s" % [int(r["diff"]), int(r["order"]), r["chapter"]]
	)
	var keys := by.keys()
	keys.sort()
	for k: String in keys:
		var list: Array = by[k]
		var runs := {}
		var deaths := 0
		var first_dead := 0
		var clear_secs := {}
		var health: Array = []
		var ammo: Array = []
		var dry: Array = []
		var scrap: Array = []
		var kills: Array = []
		var eaten: Array = []
		var fin := 0
		var boots := 0
		var haz := 0
		var bites := 0
		var pins := 0
		var ride: Array = []
		for r: Dictionary in list:
			var run := "%s|%s" % [r["skill"], r["seed"]]
			runs[run] = true
			clear_secs[run] = float(clear_secs.get(run, 0.0)) + float(r["secs"])
			if r["outcome"] != "clear":
				deaths += 1
				if int(r["attempt"]) == 1:
					first_dead += 1
			else:
				health.append(r["health"])
				ammo.append(r["ammo"])
			dry.append(r["dry"])
			scrap.append(r["scrap_found"])
			kills.append(r["kills"])
			eaten.append(r["eaten"])
			fin += int(r.get("finishers", 0))
			boots += int(r.get("boots", 0))
			haz += int(r.get("hazards", 0))
			var dog: Variant = r.get("dog", r.get("hound", {}))
			var h: Dictionary = dog if dog is Dictionary else {}
			bites += int(h.get("bites", 0))
			pins += int(h.get("pins", 0))
			ride.append(r.get("ride_s", 0.0))
		var parts := k.split("|")
		var n := maxi(1, runs.size())
		out.append(
			(
				(
					"| %s | %s | %d | %d | %.2f | %d%% | %.0f | %.0f | %.2f | %.1f | %.1f"
					+ " | %.0f | %.1f | %.1f | %.1f | %.2f | %.1f/%.1f | %.0f |"
				)
				% [
					DIFFS[int(parts[0])],
					parts[2],
					runs.size(),
					list.size(),
					float(deaths) / n,
					roundi(100.0 * first_dead / n),
					median(clear_secs.values()),
					mean(health),
					mean(ammo),
					mean(dry),
					float(_sum(scrap)) / n,
					mean(kills),
					float(_sum(eaten)) / n,
					float(fin) / n,
					float(boots) / n,
					float(haz) / n,
					float(bites) / n,
					float(pins) / n,
					mean(ride)
				]
			)
		)


static func _sum(values: Array) -> float:
	var s := 0.0
	for v: Variant in values:
		s += float(v)
	return s


static func _skills(rows: Array, out: PackedStringArray) -> void:
	out.append("\n## Deaths a run by skill and difficulty (whole campaign)")
	out.append("| diff | rookie | regular | sharp |")
	out.append("| --- | --- | --- | --- |")
	for d in 4:
		var line := "| %s |" % DIFFS[d]
		for s in 3:
			var runs := {}
			var deaths := 0
			for r: Dictionary in rows:
				if int(r["diff"]) == d and int(r["skill"]) == s:
					runs[str(r["seed"])] = true
					if r["outcome"] != "clear":
						deaths += 1
			line += (
				(" %.1f (%d runs) |" % [float(deaths) / maxi(1, runs.size()), runs.size()])
				if not runs.is_empty()
				else " - |"
			)
		out.append(line)


static func _clusters(rows: Array, out: PackedStringArray) -> void:
	out.append("\n## Where the deaths are (top 25: chapter, district or boss)")
	out.append(
		"| chapter | where | deaths | EASY | NORMAL | HARD | HOG WILD | usual causes | near |"
	)
	out.append("| --- | --- | --- | --- | --- | --- | --- | --- | --- |")
	var by := {}
	for r: Dictionary in rows:
		if r["outcome"] != "death":
			continue
		var where: String = (
			"BOSS " + str(r["fighting"]) if bool(r["boss_fight"]) else str(r["district"])
		)
		var k := "%s|%s" % [r["chapter"], where]
		if not by.has(k):
			by[k] = {"n": 0, "d": [0, 0, 0, 0], "cause": {}, "near": {}}
		var e: Dictionary = by[k]
		e["n"] = int(e["n"]) + 1
		e["d"][int(r["diff"])] += 1
		e["cause"][r["cause"]] = int(e["cause"].get(r["cause"], 0)) + 1
		for kind: Variant in r["near"]:
			e["near"][kind] = int(e["near"].get(kind, 0)) + 1
	var keys := by.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return int(by[a]["n"]) > int(by[b]["n"]))
	for k: String in keys.slice(0, 25):
		var e: Dictionary = by[k]
		var parts := k.split("|")
		out.append(
			(
				"| %s | %s | %d | %d | %d | %d | %d | %s | %s |"
				% [
					parts[0],
					parts[1],
					e["n"],
					e["d"][0],
					e["d"][1],
					e["d"][2],
					e["d"][3],
					_top(e["cause"], 2),
					_top(e["near"], 3)
				]
			)
		)


static func _top(counts: Dictionary, n: int) -> String:
	var keys := counts.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return int(counts[a]) > int(counts[b]))
	var bits: PackedStringArray = []
	for k: Variant in keys.slice(0, n):
		bits.append("%s %d" % [k, counts[k]])
	return ", ".join(bits)


static func _bosses(rows: Array, out: PackedStringArray) -> void:
	out.append("\n## Bosses: seconds to bring down (when brought down) and deaths in the fight")
	out.append("| boss | EASY | NORMAL | HARD | HOG WILD | deaths E/N/H/W |")
	out.append("| --- | --- | --- | --- | --- | --- |")
	var secs := {}
	var deaths := {}
	for r: Dictionary in rows:
		for b: Array in r.get("bosses", []):
			var k := str(b[0])
			if float(b[1]) <= 0.0:
				continue  # (an early run's untimed fight)
			if not secs.has(k):
				secs[k] = [[], [], [], []]
			secs[k][int(r["diff"])].append(float(b[1]))
		if r["outcome"] == "death" and bool(r["boss_fight"]):
			var k := str(r["fighting"])
			if not deaths.has(k):
				deaths[k] = [0, 0, 0, 0]
			deaths[k][int(r["diff"])] += 1
	for k: String in BossRematch.BOSSES:
		if not secs.has(k) and not deaths.has(k):
			continue
		var s: Array = secs.get(k, [[], [], [], []])
		var d: Array = deaths.get(k, [0, 0, 0, 0])
		var line := "| %s |" % k
		for i in 4:
			line += " %.0f (n %d) |" % [median(s[i]), s[i].size()]
		out.append(line + " %d/%d/%d/%d |" % d)


static func _guns(rows: Array, out: PackedStringArray) -> void:
	out.append("\n## Guns: kills, shots and shots a kill (all runs)")
	out.append("| gun | kills | shots | shots/kill |")
	out.append("| --- | --- | --- | --- |")
	var kills := {}
	var shots := {}
	for r: Dictionary in rows:
		for g: Variant in r.get("kills_by", {}):
			kills[g] = int(kills.get(g, 0)) + int(r["kills_by"][g])
		for g: Variant in r.get("shots", {}):
			shots[g] = int(shots.get(g, 0)) + int(r["shots"][g])
	var keys := kills.keys()
	for g: Variant in shots:
		if not keys.has(g):
			keys.append(g)
	keys.sort_custom(
		func(a: Variant, b: Variant) -> bool: return int(kills.get(a, 0)) > int(kills.get(b, 0))
	)
	for g: Variant in keys:
		var k := int(kills.get(g, 0))
		var s := int(shots.get(g, 0))
		out.append("| %s | %d | %d | %s |" % [g, k, s, "%.1f" % (float(s) / k) if k > 0 else "-"])


static func _bench(rows: Array, out: PackedStringArray) -> void:
	out.append(
		"\n## The bench: scrap carried into each chapter and the mods owned there (first attempts)"
	)
	out.append("| chapter | scrap carried (mean) | scrap found (mean) | mods owned (mean) | runs |")
	out.append("| --- | --- | --- | --- | --- |")
	var by := group(
		rows, func(r: Dictionary) -> String: return "%02d|%s" % [int(r["order"]), r["chapter"]]
	)
	var keys := by.keys()
	keys.sort()
	var got := {}
	var runs := {}
	# A run's first buy of each mod (a death takes the chapter back to the kit
	# it came in with, before the bench: the bot buys it again).
	var bought_in := {}
	for k: String in keys:
		var carried: Array = []
		var found: Array = []
		var owned: Array = []
		for r: Dictionary in by[k]:
			if int(r["attempt"]) != 1:
				continue
			carried.append(int(r["scrap_carried"]))
			owned.append(r["mods_owned"].size())
			var run := "%s|%s|%s" % [r["diff"], r["skill"], r["seed"]]
			runs[run] = true
			for m: Variant in r["mods_bought"]:
				if bought_in.has(run + str(m)):
					continue
				bought_in[run + str(m)] = true
				if not got.has(m):
					got[m] = {}
				got[m][r["chapter"]] = int(got[m].get(r["chapter"], 0)) + 1
		for r: Dictionary in by[k]:
			found.append(int(r["scrap_found"]))
		out.append(
			(
				"| %s | %.1f | %.1f | %.1f | %d |"
				% [k.split("|")[1], mean(carried), mean(found), mean(owned), carried.size()]
			)
		)
	out.append("\n| mod | price | runs that bought it | where (chapter: runs) |")
	out.append("| --- | --- | --- | --- |")
	for id: String in BenchMods.ids():
		var where: Dictionary = got.get(id, {})
		var n := 0
		for c: Variant in where:
			n += int(where[c])
		out.append(
			(
				"| %s | %d | %d of %d | %s |"
				% [id, int(BenchMods.mod(id)["price"]), n, runs.size(), _top(where, 4)]
			)
		)


static func _county(rows: Array, out: PackedStringArray) -> void:
	if rows.is_empty():
		return
	out.append("\n## COUNTY RUN: survival (s) and level by difficulty and map")
	(
		out
		. append(
			"| diff | map | runs | survived med | min | max | level med | kills med | level at 2/5/10 min |"
		)
	)
	out.append("| --- | --- | --- | --- | --- | --- | --- | --- | --- |")
	var by := group(
		rows, func(r: Dictionary) -> String: return "%d|%s" % [int(r["diff"]), r["map"]]
	)
	var keys := by.keys()
	keys.sort()
	var picked := {}
	var offered := {}
	for k: String in keys:
		var list: Array = by[k]
		var surv: Array = []
		var lv: Array = []
		var kills: Array = []
		var at := [[], [], []]
		for r: Dictionary in list:
			surv.append(r["survived"])
			lv.append(r["level"])
			kills.append(r["kills"])
			for mark: Array in r["curve"]:
				var i := [120, 300, 600].find(int(mark[0]))
				if i >= 0:
					at[i].append(mark[1])
			for p: Array in r["picks"]:
				for o: Variant in p[0]:
					offered[o] = int(offered.get(o, 0)) + 1
				picked[p[1]] = int(picked.get(p[1], 0)) + 1
		var v := surv.duplicate()
		v.sort()
		out.append(
			(
				"| %s | %s | %d | %.0f | %.0f | %.0f | %.0f | %.0f | %s/%s/%s |"
				% [
					DIFFS[int(k.split("|")[0])],
					k.split("|")[1],
					list.size(),
					median(surv),
					v[0],
					v[-1],
					median(lv),
					median(kills),
					"%.0f" % median(at[0]) if not at[0].is_empty() else "-",
					"%.0f" % median(at[1]) if not at[1].is_empty() else "-",
					"%.0f" % median(at[2]) if not at[2].is_empty() else "-"
				]
			)
		)
	out.append("\n| card | offered | picked | pick rate |")
	out.append("| --- | --- | --- | --- |")
	var keys2 := offered.keys()
	keys2.sort_custom(
		func(a: Variant, b: Variant) -> bool: return int(offered[a]) > int(offered[b])
	)
	for c: Variant in keys2:
		out.append(
			(
				"| %s | %d | %d | %d%% |"
				% [
					c,
					offered[c],
					picked.get(c, 0),
					roundi(100.0 * int(picked.get(c, 0)) / int(offered[c]))
				]
			)
		)
