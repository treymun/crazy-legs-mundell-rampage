## Time to kill: every gun against every enemy, from the tuned numbers in
## data/tuning/weapons.cfg and enemies.cfg, so each gun's job shows at a glance.
##
##   godot --headless --path godot --script res://tools/ttk.gd [-- <out.md>]
##
## A shot is assumed to land squarely (explosives at the centre of the blast);
## the shotgun's pellets land in proportion to how much of their cone the body
## fills at the range in the heading. Times count the gun's fire time between
## shots and a reload whenever a loaded gun runs dry (it starts full).
extends SceneTree

## Guns whose shot is an explosion: [blast strength (0 = the gun's damage), radius].
const BLASTS := {
	Weapons.CROSSBOW: [160.0, 2.8],
	Weapons.ARMGUN: [0.0, 1.4],
	Weapons.ROCKET: [0.0, 1.72],
	Weapons.KEG: [240.0, 3.7],
	Weapons.COW: [0.0, 2.3],
}
## Shotgun pellet cone (weapons.gd fire()): half-angles across and up.
const PELLET_SPREAD := Vector2(.135, .09)
const RANGES := [2.0, 5.0, 9.0]


func _init() -> void:
	var out_path := ""
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		out_path = args[0]
	var foes: Array = []
	for kind: String in Enemy.KINDS:
		if bool(Enemy.KINDS[kind][4]):
			foes.append(kind)
	foes.sort_custom(func(a, b): return float(Enemy.KINDS[a][0]) < float(Enemy.KINDS[b][0]))
	var lines: Array[String] = []
	lines.append("# Time to kill\n")
	lines.append(
		"Seconds from the first shot to the kill, shots in brackets. Made by `tools/ttk.gd`"
	)
	lines.append("from `data/tuning/*.cfg`; run it again after changing them.\n")
	for distance: float in [RANGES[0], RANGES[1]]:
		lines.append("## At %.0f cells\n" % distance)
		var head := "| gun | dmg/shot | dps | ammo |"
		var rule := "| --- | ---: | ---: | ---: |"
		for kind: String in foes:
			head += " %s (%d) |" % [kind, int(Enemy.KINDS[kind][0])]
			rule += " ---: |"
		lines.append(head)
		lines.append(rule)
		for slot in Weapons.COUNT:
			if slot == Weapons.DYNAMITE:
				continue
			var per_shot := shot_damage(slot, distance, .3, .9)
			if per_shot <= 0.0:
				continue
			var row := (
				"| %s | %.0f | %.0f | %s |"
				% [Weapons.NAMES[slot], per_shot, sustained(slot, per_shot), ammo_text(slot)]
			)
			for kind: String in foes:
				var spec: Array = Enemy.KINDS[kind]
				var hit := shot_damage(slot, distance, float(spec[2]), float(spec[3]))
				var shots := int(ceil(float(spec[0]) / maxf(hit, .001)))
				row += " %.2f (%d) |" % [kill_time(slot, shots), shots]
			lines.append(row)
		lines.append("")
	var text := "\n".join(lines)
	print(text)
	if out_path != "":
		var file := FileAccess.open(out_path, FileAccess.WRITE)
		file.store_string(text + "\n")
		print("wrote ", out_path)
	quit()


## Damage one squarely aimed shot does to a body of this size at this range.
func shot_damage(slot: int, distance: float, radius: float, height: float) -> float:
	if slot == Weapons.CROWBAR or slot == Weapons.SLING:
		var reach := 2.15 if slot == Weapons.SLING else 1.65
		return float(Weapons.MELEE[slot][0]) if distance <= reach + .5 else 0.0
	if slot == Weapons.SHOTGUN:
		if distance > 11.5:
			return 0.0
		var across := minf(1.0, (radius + .04) / distance / PELLET_SPREAD.x)
		var up := minf(1.0, height * .5 / distance / PELLET_SPREAD.y)
		return Weapons.SHOTGUN_PELLETS * Weapons.SHOTGUN_DAMAGE * across * up
	if BLASTS.has(slot):
		var blast: Array = BLASTS[slot]
		return float(blast[0]) if float(blast[0]) > 0.0 else float(Weapons.DAMAGE.get(slot, 0))
	return float(Weapons.DAMAGE.get(slot, 0))


## Seconds to fire `shots` shots from a full gun, reloading when it runs dry.
func kill_time(slot: int, shots: int) -> float:
	var t := (shots - 1) * float(Weapons.FIRE_TIME[slot])
	var capacity := int(Weapons.CAPACITY[slot])
	if capacity > 0:
		t += int((shots - 1) / capacity) * float(Weapons.RELOAD_TIME[slot])
	return t


## Damage a second over a long fight, reloads included.
func sustained(slot: int, per_shot: float) -> float:
	var capacity := int(Weapons.CAPACITY[slot])
	var fire := float(Weapons.FIRE_TIME[slot])
	if capacity > 0:
		return per_shot * capacity / (capacity * fire + float(Weapons.RELOAD_TIME[slot]))
	return per_shot / fire


func ammo_text(slot: int) -> String:
	if int(Weapons.MAX_RESERVE[slot]) == 0:
		return "-"
	return "%d/+%d" % [int(Weapons.MAX_RESERVE[slot]), int(Weapons.PICKUP_RESERVE[slot])]
