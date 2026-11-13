## The 5v5 store's guns side by side, worked out from weapons.cfg and
## TacticalShop's tables (headless, prints a table):
##
##   Godot --headless --path <project> --script res://tools/gun_sheet.gd [-- md=<file>]
##
## Per gun: price and side, a hit on a player (body, through a vest, head bare,
## head in a hard hat), hits to drop a 100-health player each way, rounds a
## minute, the time to kill when every shot lands (bare, vested), the chance a
## shot lands on a body at 5, 12 and 25 cells standing still (spread and
## pellets; a sniper scoped), the expected time to kill a vested player at
## those ranges, magazine and reload. md= writes the table as Markdown too.
extends SceneTree

const BODY := .24
const RANGES := [5.0, 12.0, 25.0]


func _init() -> void:
	var md := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("md="):
			md = arg.substr(3)
	var rows: Array = []
	var head := [
		"gun",
		"$",
		"side",
		"body",
		"vest",
		"head",
		"hat",
		"to kill b/v/h/hh",
		"rpm",
		"ttk b/v",
		"hit 5/12/25",
		"ttk v 5/12/25",
		"mag",
		"reload",
		"range"
	]
	rows.append(head)
	for row: Array in TacticalShop.ITEMS:
		var gun := int(row[3])
		if gun < 0 or String(row[6]) in ["GEAR", "THROWN"]:
			continue
		rows.append(_row(row, gun))
	for gun: int in [Weapons.REVOLVER, Weapons.COUNTY45]:
		rows.append(_row(["kit", Weapons.LABELS[gun], 0, gun, 0, 0, "PISTOL", "kit"], gun))
	for r: Array in rows:
		var line := ""
		for i in r.size():
			line += String(str(r[i])).rpad(22 if i == 0 else (16 if i in [7, 10, 11] else 7))
		print(line)
	if md != "":
		var f := FileAccess.open(md, FileAccess.WRITE)
		f.store_line("| " + " | ".join(PackedStringArray(head)) + " |")
		f.store_line("|" + "---|".repeat(head.size()))
		for r: Array in rows.slice(1):
			var cells := PackedStringArray()
			for v in r:
				cells.append(str(v))
			f.store_line("| " + " | ".join(cells) + " |")
	quit()


func _row(row: Array, gun: int) -> Array:
	var how: Dictionary = Weapons.FIRING[gun]
	var spec: Array = TacticalShop.DAMAGE.get(gun, TacticalShop.DAMAGE_DEFAULT)
	var pellets := 1
	var per := float(Weapons.DAMAGE.get(gun, 0))
	if String(how.get("fire", "")) == "pellets":
		pellets = int(how.get("pellets", Weapons.SHOTGUN_PELLETS))
		per = float(how.get("pellet_damage", Weapons.SHOTGUN_DAMAGE))
	var shot := per * pellets
	var body := shot * float(spec[0])
	var vest := body * float(spec[1])
	var bare := body * float(spec[2])
	var hat := bare * float(spec[1])
	var kills := []
	for d: float in [body, vest, bare, hat]:
		kills.append(ceili(100.0 / maxf(.01, d)) if d > 0.0 else 0)
	var rate := float(Weapons.FIRE_TIME[gun])
	var spread: Vector2 = how.get("spread", Vector2.ZERO)
	if how.has("scope_spread"):
		spread = how["scope_spread"]
	var reach := float(how.get("range", 99.0))
	var width := float(how.get("width", 0.0))
	var hits := []
	var ttks := []
	for dist: float in RANGES:
		var p := 0.0
		if dist <= reach:
			p = 1.0 if spread.x <= 0.0 else minf(1.0, (BODY + width) / (dist * tan(spread.x)))
		hits.append("%d%%" % roundi(p * 100.0))
		if p <= 0.0:
			ttks.append("-")
			continue
		# Pellets: the share that lands, each shot.
		var dealt := vest * p
		var need := ceili(100.0 / maxf(.01, dealt)) if pellets > 1 else ceili(kills[1] / p)
		ttks.append("%.2f" % (maxf(0, need - 1) * rate))
	return [
		String(row[1]),
		int(row[2]),
		String(row[7]) if String(row[7]) != "" else "both",
		roundi(body),
		roundi(vest),
		roundi(bare),
		roundi(hat),
		"%d/%d/%d/%d" % kills,
		roundi(60.0 / maxf(.01, rate)),
		"%.2f/%.2f" % [(kills[0] - 1) * rate, (kills[1] - 1) * rate],
		"/".join(PackedStringArray(hits)),
		"/".join(PackedStringArray(ttks)),
		Weapons.CAPACITY[gun],
		Weapons.RELOAD_TIME[gun],
		reach,
	]
