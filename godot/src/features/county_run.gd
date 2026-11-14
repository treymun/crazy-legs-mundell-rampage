## COUNTY RUN's state (CLAUDE.md "County Run"): the clock, XP and level, the
## three weapon slots and every upgrade, perk and milestone taken, the level
## ups waiting for a choice and the cards on offer, the XP lying about, the
## spawner and the milestone abilities' timers. Plain values only (a
## simulation feature, carried in snapshots); a run is never saved.
##
## Nothing here runs outside a run: `on` is set by CountyMode.start on the
## first tick. The rules (src/modes/county_mode.gd) and its helpers
## (county_build.gd, county_spawner.gd, county_orbs.gd, county_moves.gd) do
## the work; this listens to the game's events and hands them over.
extends GameFeature

var on := false
var map_id := ""
## Seconds survived: the score. It stops while a choice is on screen (the
## whole world does: CountyMode.holds).
var run_time := 0.0
var level := 1
var xp := 0
var xp_total := 0
## The weapon in each slot (weapons.cfg index, -1 empty).
var slots: Array = []
## Ranks taken: "<gun>/<upgrade>" (dropped with the gun), "perk/<id>",
## "m/<milestone>".
var ranks := {}
## Every reward taken, in order: [level, words] (the build screen's log).
var picks: Array = []
## Level ups waiting for a choice, in order: [level, milestone, gun equipped
## when it was earned]; and the three cards for the first of them.
var pending: Array = []
var offer: Array = []
## XP and supplies lying about: [x, y, z, value, kind ("xp", "ammo",
## "food"), born, merged]. Collected ones pop: [x, y, z, until, value].
var orbs: Array = []
var pops: Array = []
## The spawner (county_spawner.gd): when the next one comes, the next elite,
## the lull, how many so far; each county hand's last place and when it last
## moved or was seen (uid -> [x, y, moved at, seen at]).
var next_spawn := 0.0
var next_elite := 0.0
var next_lull := 0.0
var lull_until := -1.0
var spawned := 0
var elites := 0
var watch := {}
## The elites up or down (instance id -> true): they drop more XP.
var elite_ids := {}
## The shot in the air for the streak upgrades (DEADEYE, CALLED SHOT, the
## SHOWDOWN): its gun, whether it hit, the streak, the tough varmint being
## called and its hits, the showdown's charge.
var shot_gun := -1
var shot_hit := false
var streak := 0
var called_uid := -1
var called_hits := 0
var six_hits := 0
var six_ready := false
## STEADY STOCK: the pitch before the rifle's climb this tick (-999: none);
## the player's shots in flight whose damage HOT LOADS has raised; whether
## the blast going off is the player's own (CHAIN REACTION).
var pitch_before := -999.0
var scaled := {}
var blast_mine := false
## Milestone abilities: GRIT ARMOR, SECOND WIND used, LAST STAND's guard,
## MUDSLIDE (ready at, sliding for, which way), BREAKAWAY (last crowded,
## burst until, ready at), CHAIN REACTION's blasts waiting [x, y, z, at,
## damage, origin] and what each shot has left.
var armor := 0.0
var second_wind_used := false
var guard_until := -1.0
var safe_until := -1.0
var dash_ready := 0.0
var dash_left := 0.0
var dash_angle := 0.0
var crowd_at := -10.0
var burst_until := -1.0
var burst_ready := 0.0
var chains: Array = []
var chain_left := {}
var chain_origin := 0
var blast_origin := 0
var chain_serial := 0
## The end: the run's numbers ({} until it ends; best_before is the map's
## record as it stood).
var over := false
var result := {}
## The build screen is up mid-fight (county_input.gd): the world holds.
var paused := false


func id() -> String:
	return "county"


func attach() -> void:
	game.ticked.connect(_tick)
	game.shot_fired.connect(_fired)
	game.enemy_killed.connect(_killed)


func _tick(dt: float) -> void:
	if on and not over:
		CountyMode.step(game, self, dt)


func _fired(gun: int) -> void:
	if on and not over:
		CountyMoves.fired(game, self, gun)


func _killed(e: Enemy) -> void:
	if on:
		CountyMoves.killed(game, self, e)


func sprites() -> Array:
	return CountyOrbs.sprites(game, self) if on else []


func draw_view(c: Canvas) -> void:
	if on:
		CountyOrbs.draw_pops(c, game, self)
