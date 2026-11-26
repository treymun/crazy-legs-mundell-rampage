## The tables of tools/flow_report.gd's lines (markdown): per chapter the
## time and the fights, how many alerted hands at once, the quiet between
## fights, damage from out of view, melee, dry seconds, the fight music, what
## deaths cost, the director's beats; time to kill by kind; a line per skill
## against pass 15's targets. Medians over the cleared attempts unless said.
extends RefCounted

const SKILLS := ["ROOKIE", "REGULAR", "SHARP"]
const MELEE := ["crowbar", "slingblade"]


static func tables(source: String) -> String:
	var rows := read(source)
	if rows.is_empty():
		return "no rows in " + source
	var out := PackedStringArray()
	out.append("Flow report: %d attempts from %s" % [rows.size(), source])
	out.append("")
	out.append(_targets(rows))
	out.append(_chapters(rows))
	out.append(_fights(rows))
	out.append(_crowds(rows))
	out.append(_feel(rows))
	out.append(_music(rows))
	out.append(_deaths(rows))
	out.append(_kinds(rows))
	out.append(_director(rows))
	out.append(_lost(rows))
	return "\n".join(out)


## Every line of a file, of each file in a comma list, or of each .jsonl in a dir.
static func read(source: String) -> Array:
	var files: Array = []
	if DirAccess.dir_exists_absolute(source):
		for name: String in DirAccess.get_files_at(source):
			if name.ends_with(".jsonl"):
				files.append(source.path_join(name))
		files.sort()
	else:
		files = Array(source.split(",", false))
	var rows: Array = []
	for path: String in files:
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		var run := path.get_file().get_basename()
		while not f.eof_reached():
			var line := f.get_line().strip_edges()
			if line == "":
				continue
			var row: Variant = JSON.parse_string(line)
			if row is Dictionary:
				row["run"] = run
				rows.append(row)
	return rows


static func median(xs: Array) -> float:
	if xs.is_empty():
		return 0.0
	var s := xs.duplicate()
	s.sort()
	var n := s.size()
	if n % 2 == 1:
		return float(s[n / 2])
	return (float(s[n / 2 - 1]) + float(s[n / 2])) / 2.0


static func _cleared(rows: Array, chapter: String) -> Array:
	var out: Array = []
	for r: Dictionary in rows:
		if r.get("chapter", "") == chapter and r.get("outcome", "") == "clear":
			out.append(r)
	return out


static func _in(rows: Array, chapter: String) -> Array:
	var out: Array = []
	for r: Dictionary in rows:
		if r.get("chapter", "") == chapter:
			out.append(r)
	return out


static func _runs(rows: Array) -> int:
	var seen := {}
	for r: Dictionary in rows:
		seen[r["run"]] = true
	return maxi(1, seen.size())


## Alive-at-once samples [0, 1, .. 6+] summed.
static func _hist(rows: Array) -> Array:
	var h := [0, 0, 0, 0, 0, 0, 0]
	for r: Dictionary in rows:
		var got: Array = r.get("alive_hist", [])
		# (The audit's lines had no 0 bucket: 1..6+.)
		var shift := 0 if got.size() == 7 else 1
		for i in got.size():
			h[i + shift] += int(got[i])
	return h


## Share of the samples with any alerted near that had `least` or more.
static func _share_at_least(h: Array, least: int) -> float:
	var any := 0
	var many := 0
	for i in range(1, h.size()):
		any += int(h[i])
		if i >= least:
			many += int(h[i])
	return 100.0 * many / maxf(1.0, any)


static func _melee_kills(rows: Array) -> Array:
	var melee := 0
	var all := 0
	for r: Dictionary in rows:
		var kb: Dictionary = r.get("kills_by", {})
		for gun: String in kb:
			all += int(kb[gun])
			if MELEE.has(gun):
				melee += int(kb[gun])
	return [melee, all]


static func _melee_pulls(rows: Array) -> Array:
	var melee := 0
	var all := 0
	for r: Dictionary in rows:
		var sh: Dictionary = r.get("shots", {})
		for gun: String in sh:
			all += int(sh[gun])
			if MELEE.has(gun):
				melee += int(sh[gun])
	return [melee, all]


## The longest fight; `bosses` false: leaving out a fight a boss fell in
## (or the attempt ended in, in a boss fight).
static func _longest_fight(rows: Array, bosses := true) -> float:
	var most := 0.0
	for r: Dictionary in rows:
		for f: Array in r.get("fights", []):
			if bosses or not _boss_in(r, f):
				most = maxf(most, float(f[1]))
	return most


static func _boss_in(r: Dictionary, f: Array) -> bool:
	var from := float(f[0])
	var to := from + float(f[1]) + 6.0
	for mark: Array in r.get("progress", []):
		if str(mark[1]) == "boss" and float(mark[0]) >= from and float(mark[0]) <= to:
			return true
	return bool(r.get("boss_fight", false)) and to >= float(r.get("secs", 0.0)) - 1.0


static func _targets(rows: Array) -> String:
	var t := PackedStringArray()
	t.append("### Against the targets (by skill; all attempts)")
	t.append("")
	t.append(
		(
			"| skill | runs | 3+ alerted within 14 (% of fighting) | melee kills %"
			+ " | melee pulls % | longest fight s | longest with no boss s"
			+ " | deaths a run | cleared s (sum of chapter medians) |"
		)
	)
	t.append("| --- | --- | --- | --- | --- | --- | --- | --- | --- |")
	for s in SKILLS.size():
		var mine: Array = []
		for r: Dictionary in rows:
			if int(r.get("skill", 1)) == s:
				mine.append(r)
		if mine.is_empty():
			continue
		var mk := _melee_kills(mine)
		var mp := _melee_pulls(mine)
		var deaths := 0
		for r: Dictionary in mine:
			if r.get("outcome", "") == "death":
				deaths += 1
		var secs := 0.0
		for ch: String in Campaign.ORDER:
			var c := _cleared(mine, ch)
			var xs: Array = []
			for r: Dictionary in c:
				xs.append(r["secs"])
			secs += median(xs)
		t.append(
			(
				"| %s | %d | %.0f | %.1f | %.1f | %.0f | %.0f | %.2f | %.0f |"
				% [
					SKILLS[s],
					_runs(mine),
					_share_at_least(_hist(mine), 3),
					100.0 * mk[0] / maxf(1.0, mk[1]),
					100.0 * mp[0] / maxf(1.0, mp[1]),
					_longest_fight(mine),
					_longest_fight(mine, false),
					float(deaths) / _runs(mine),
					secs
				]
			)
		)
	t.append("")
	return "\n".join(t)


static func _chapters(rows: Array) -> String:
	var t := PackedStringArray()
	t.append("### Where the time goes (cleared attempts, medians)")
	t.append("")
	t.append(
		(
			"| chapter | secs | fight % | walk % | idle % | first fight s"
			+ " | longest calm s | kills a minute | deaths a run |"
		)
	)
	t.append("| --- | --- | --- | --- | --- | --- | --- | --- | --- |")
	var runs := _runs(rows)
	for ch: String in Campaign.ORDER:
		var rs := _cleared(rows, ch)
		if rs.is_empty():
			continue
		var secs: Array = []
		var fight: Array = []
		var walk: Array = []
		var idle: Array = []
		var first: Array = []
		var calm: Array = []
		var kpm: Array = []
		for r: Dictionary in rs:
			var s: float = maxf(.1, float(r["secs"]))
			var fl: Dictionary = r["flow"]
			secs.append(s)
			fight.append(100.0 * float(fl["fight"]) / s)
			walk.append(100.0 * float(fl["walk"]) / s)
			idle.append(100.0 * float(fl["idle"]) / s)
			first.append(fl["first_fight"])
			calm.append(fl["longest_calm"])
			kpm.append(60.0 * float(r["kills"]) / s)
		var deaths := 0
		for r: Dictionary in _in(rows, ch):
			if r.get("outcome", "") == "death":
				deaths += 1
		t.append(
			(
				"| %s | %.0f | %.0f | %.0f | %.0f | %.1f | %.0f | %.1f | %.2f |"
				% [
					ch,
					median(secs),
					median(fight),
					median(walk),
					median(idle),
					median(first),
					median(calm),
					median(kpm),
					float(deaths) / runs
				]
			)
		)
	t.append("")
	return "\n".join(t)


static func _fights(rows: Array) -> String:
	var t := PackedStringArray()
	t.append("### The fights (hot until 6 s quiet; all attempts)")
	t.append("")
	t.append(
		(
			"| chapter | fights an attempt | median length s | longest s"
			+ " | median kills a fight | median peak alerted within 14"
			+ " | median quiet gap s | gaps of 12 s+ an attempt |"
		)
	)
	t.append("| --- | --- | --- | --- | --- | --- | --- | --- |")
	for ch: String in Campaign.ORDER:
		var rs := _in(rows, ch)
		if rs.is_empty():
			continue
		var lengths: Array = []
		var kills: Array = []
		var peaks: Array = []
		var gaps: Array = []
		var long_gaps := 0
		var n := 0
		var longest := 0.0
		for r: Dictionary in rs:
			var fl: Array = r.get("fights", [])
			for f: Array in fl:
				n += 1
				lengths.append(f[1])
				longest = maxf(longest, float(f[1]))
				kills.append(f[2])
				peaks.append(f[3])
			for i in range(1, fl.size()):
				var a: Array = fl[i - 1]
				var b: Array = fl[i]
				var gap := float(b[0]) - (float(a[0]) + float(a[1]))
				gaps.append(gap)
				if gap >= 12.0:
					long_gaps += 1
		t.append(
			(
				"| %s | %.1f | %.1f | %.0f | %.0f | %.0f | %.1f | %.1f |"
				% [
					ch,
					float(n) / rs.size(),
					median(lengths),
					longest,
					median(kills),
					median(peaks),
					median(gaps),
					float(long_gaps) / rs.size()
				]
			)
		)
	t.append("")
	return "\n".join(t)


static func _crowds(rows: Array) -> String:
	var t := PackedStringArray()
	t.append("### Alerted hands within 14 while fighting (4 Hz samples with any)")
	t.append("")
	t.append("| chapter | 1 | 2 | 3 | 4 | 5 | 6+ | 3+ |")
	t.append("| --- | --- | --- | --- | --- | --- | --- | --- |")
	var chapters: Array = Campaign.ORDER.duplicate()
	chapters.append("all")
	for ch: String in chapters:
		var rs: Array = rows if ch == "all" else _in(rows, ch)
		if rs.is_empty():
			continue
		var h := _hist(rs)
		var any := 0
		for i in range(1, 7):
			any += int(h[i])
		var cells := PackedStringArray()
		for i in range(1, 7):
			cells.append("%.0f" % (100.0 * int(h[i]) / maxf(1.0, any)))
		t.append("| %s | %s | %.0f |" % [ch, " | ".join(cells), _share_at_least(h, 3)])
	t.append("")
	return "\n".join(t)


## Pass 15: the music's four levels (features/fight_music.gd) as shares of
## the chapter, and the RAMPAGES (features/rampage.gd).
static func _music(rows: Array) -> String:
	var t := PackedStringArray()
	t.append("### Music levels and RAMPAGE (all attempts; % of the chapter, medians)")
	t.append("")
	t.append(
		(
			"| chapter | CALM % | BUILD % | FIGHT % | PEAK % | whole loop % | loop swaps"
			+ " | RAMPAGES an attempt | on one s an attempt |"
		)
	)
	t.append("| --- | --- | --- | --- | --- | --- | --- | --- | --- |")
	var all_r := 0.0
	var all_n := 0
	for ch: String in Campaign.ORDER:
		var rs := _in(rows, ch)
		if rs.is_empty():
			continue
		var shares := [[], [], [], []]
		var loop: Array = []
		var swaps: Array = []
		var count := 0.0
		var on := 0.0
		for r: Dictionary in rs:
			var fl: Dictionary = r["flow"]
			var secs := maxf(.1, float(r["secs"]))
			var lv: Array = fl.get("music_levels", [0.0, 0.0, 0.0, 0.0])
			for i in 4:
				shares[i].append(100.0 * float(lv[i]) / secs)
			loop.append(100.0 * float(fl.get("music_fight", 0.0)) / secs)
			swaps.append(fl.get("music_flips", 0))
			count += float(fl.get("rampages", 0))
			on += float(fl.get("raging", 0.0))
		all_r += count
		all_n += rs.size()
		t.append(
			(
				"| %s | %.0f | %.0f | %.0f | %.0f | %.0f | %.0f | %.2f | %.1f |"
				% [
					ch,
					median(shares[0]),
					median(shares[1]),
					median(shares[2]),
					median(shares[3]),
					median(loop),
					median(swaps),
					count / rs.size(),
					on / rs.size()
				]
			)
		)
	t.append("")
	t.append("RAMPAGES an attempt, every chapter: %.2f" % (all_r / maxf(1.0, all_n)))
	t.append("")
	return "\n".join(t)


static func _feel(rows: Array) -> String:
	var t := PackedStringArray()
	t.append("### Damage, melee, supply and music (all attempts; music % of the chapter)")
	t.append("")
	t.append(
		(
			"| chapter | taken an attempt | unseen % | melee kills %"
			+ " | melee pulls % | dry s an attempt | ammo pickups left | food left"
			+ " | eaten | fight loop % | loop swaps | held s | slow-mo s |"
		)
	)
	t.append("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |")
	for ch: String in Campaign.ORDER:
		var rs := _in(rows, ch)
		if rs.is_empty():
			continue
		var taken := 0.0
		var unseen := 0.0
		var dry := 0.0
		var ammo: Array = []
		var food: Array = []
		var eaten: Array = []
		var music: Array = []
		var swaps: Array = []
		var held: Array = []
		var slow: Array = []
		for r: Dictionary in rs:
			taken += float(r.get("taken", 0))
			unseen += float(r.get("dmg", {}).get("unseen", 0))
			var fl: Dictionary = r["flow"]
			dry += float(fl.get("dry", 0.0))
			ammo.append(r.get("pickups_left", {}).get("ammo", 0))
			food.append(r.get("pickups_left", {}).get("food", 0))
			eaten.append(r.get("eaten", 0))
			music.append(100.0 * float(fl.get("music_fight", 0.0)) / maxf(.1, float(r["secs"])))
			swaps.append(fl.get("music_flips", 0))
			held.append(fl.get("held", 0.0))
			slow.append(fl.get("slowmo", 0.0))
		var mk := _melee_kills(rs)
		var mp := _melee_pulls(rs)
		var row := (
			"| %s | %.0f | %.0f | %.1f | %.1f | %.1f | %.0f | %.0f | %.0f | %.0f"
			+ " | %.0f | %.1f | %.1f |"
		)
		t.append(
			(
				row
				% [
					ch,
					taken / rs.size(),
					100.0 * unseen / maxf(1.0, taken),
					100.0 * mk[0] / maxf(1.0, mk[1]),
					100.0 * mp[0] / maxf(1.0, mp[1]),
					dry / rs.size(),
					median(ammo),
					median(food),
					median(eaten),
					median(music),
					median(swaps),
					median(held),
					median(slow)
				]
			)
		)
	t.append("")
	return "\n".join(t)


static func _deaths(rows: Array) -> String:
	var t := PackedStringArray()
	t.append("### Deaths and what each cost (seconds of play thrown away)")
	t.append("")
	t.append("| run | chapter | attempt | at s | where | boss | cause | near | cost s |")
	t.append("| --- | --- | --- | --- | --- | --- | --- | --- | --- |")
	var any := false
	for r: Dictionary in rows:
		if r.get("outcome", "") == "clear":
			continue
		any = true
		t.append(
			(
				"| %s | %s | %d | %.0f | %s | %s | %s | %s | %.0f |"
				% [
					r["run"],
					r["chapter"],
					int(r.get("attempt", 0)),
					float(r.get("secs", 0.0)),
					r.get("district", ""),
					r.get("fighting", "") if r.get("fighting", "") != "" else "-",
					r.get("cause", ""),
					",".join(PackedStringArray(r.get("near", []))),
					float(r.get("death_cost", r.get("secs", 0.0)))
				]
			)
		)
	if not any:
		t.append("| (none) | | | | | | | | |")
	t.append("")
	return "\n".join(t)


static func _kinds(rows: Array) -> String:
	var by := {}
	for r: Dictionary in rows:
		for k: Array in r.get("kills_detail", []):
			var kind := str(k[0])
			if not by.has(kind):
				by[kind] = []
			by[kind].append(k)
	var kinds: Array = by.keys()
	kinds.sort_custom(func(a: String, b: String) -> bool: return by[a].size() > by[b].size())
	var t := PackedStringArray()
	t.append("### Time to kill by kind (kills with 4 or more)")
	t.append("")
	t.append(
		(
			"| kind | hp | kills | median shots at it | median hit ticks"
			+ " | s from first hit | s from targeted |"
		)
	)
	t.append("| --- | --- | --- | --- | --- | --- | --- |")
	for kind: String in kinds:
		var ks: Array = by[kind]
		if ks.size() < 4:
			continue
		var shots: Array = []
		var hits: Array = []
		var from_hit: Array = []
		var from_target: Array = []
		for k: Array in ks:
			hits.append(k[2])
			shots.append(k[3])
			from_hit.append(k[4])
			from_target.append(k[5])
		t.append(
			(
				"| %s | %d | %d | %.0f | %.0f | %.1f | %.1f |"
				% [
					kind,
					int(ks[0][6]),
					ks.size(),
					median(shots),
					median(hits),
					median(from_hit),
					median(from_target)
				]
			)
		)
	t.append("")
	return "\n".join(t)


static func _director(rows: Array) -> String:
	var t := PackedStringArray()
	t.append("### The director's beats (attempts it ran in; % of the attempt)")
	t.append("")
	t.append(
		(
			"| chapter | calm % | build % | peak % | breather % | peaks an attempt"
			+ " | hands a peak |"
		)
	)
	t.append("| --- | --- | --- | --- | --- | --- | --- |")
	var any := false
	for ch: String in Campaign.ORDER:
		var rs: Array = []
		for r: Dictionary in _in(rows, ch):
			if r.has("beats"):
				rs.append(r)
		if rs.is_empty():
			continue
		any = true
		var share := {"calm": 0.0, "build": 0.0, "peak": 0.0, "breather": 0.0}
		var secs := 0.0
		var peaks := 0
		var hands := 0
		for r: Dictionary in rs:
			var d: Dictionary = r["beats"]
			secs += float(r["secs"])
			for k: String in share:
				share[k] = float(share[k]) + float(d["phases"].get(k, 0.0))
			peaks += int(d["peaks"])
			hands += int(d["peak_hands"])
		t.append(
			(
				"| %s | %.0f | %.0f | %.0f | %.0f | %.1f | %.1f |"
				% [
					ch,
					100.0 * float(share["calm"]) / maxf(.1, secs),
					100.0 * float(share["build"]) / maxf(.1, secs),
					100.0 * float(share["peak"]) / maxf(.1, secs),
					100.0 * float(share["breather"]) / maxf(.1, secs),
					float(peaks) / rs.size(),
					float(hands) / maxf(1.0, peaks)
				]
			)
		)
	if not any:
		t.append("| (director off or absent) | | | | | | |")
	t.append("")
	return "\n".join(t)


## Pass 15 (BLUE AND LOOPS): per chapter, over every attempt: lost episodes
## (the pin's way no shorter for 30 s, nothing hot) and their seconds past
## the 30, backtracking seconds, seconds BLUE spent leading the way.
static func _lost(rows: Array) -> String:
	var out := PackedStringArray()
	out.append("### Lost and backtracking (pass 15; every attempt, sums a run)")
	out.append("")
	out.append("| chapter | lost episodes | lost s past 30 | backtrack s | BLUE leading s |")
	out.append("| --- | --- | --- | --- | --- |")
	var runs := maxi(1, _runs(rows))
	for chapter: String in Campaign.ORDER:
		var mine := _in(rows, chapter)
		if mine.is_empty():
			continue
		var sums := [0.0, 0.0, 0.0, 0.0]
		for r: Dictionary in mine:
			var f: Dictionary = r.get("flow", {})
			sums[0] += float(f.get("lost30_n", 0))
			sums[1] += float(f.get("lost30_s", 0.0))
			sums[2] += float(f.get("backtrack", 0.0))
			sums[3] += float(f.get("lead", 0.0))
		out.append(
			(
				"| %s | %.2f | %.1f | %.1f | %.1f |"
				% [chapter, sums[0] / runs, sums[1] / runs, sums[2] / runs, sums[3] / runs]
			)
		)
	out.append("")
	return "\n".join(out)
