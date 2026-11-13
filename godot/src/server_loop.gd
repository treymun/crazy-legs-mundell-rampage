## The --server mode (main.gd): a GameHost runs a chapter at the game's fixed
## 120 Hz with no window work, and every few seconds prints what its ticks
## and its deltas cost. Run it headless:
##
##   godot --headless --path godot -- --server=fair --server-players=2
##         [--server-ticks=N] (quit after N ticks) [--server-report=S] (seconds)
##
## The players stand idle until a transport hands their controls in
## (`controls`, slot -> Game.Controls, kept until replaced); the host takes a
## delta for a client acknowledging every fourth tick, as a 30 Hz update would.
class_name ServerLoop
extends Node

var host: GameHost
## Each player's last controls from the network (slot -> Game.Controls).
var controls := {}
var limit := 0
var report_every := 5.0
var _accumulator := 0.0
var _since_report := 0.0
var _ticks := 0
var _window := 0
var _spent := 0.0
var _worst := 0.0
var _delta_spent := 0.0
var _delta_bytes := 0
var _deltas := 0
var _acked := -1


func _init(level_id: String, slots: int, options: Dictionary, p_limit := 0, every := 5.0) -> void:
	var t0 := Time.get_ticks_msec()
	host = GameHost.new(level_id, slots, options)
	limit = p_limit
	report_every = every
	print(
		(
			"SERVER %s: %d player(s), %d enemies, made in %d ms; 120 Hz"
			% [level_id, slots, host.game.enemies.size(), Time.get_ticks_msec() - t0]
		)
	)


func _ready() -> void:
	if limit > 0:
		# A run with a tick limit plays as fast as it can, for timing.
		set_process(false)
		_flat_out.call_deferred()


func _process(delta: float) -> void:
	_accumulator = minf(_accumulator + delta, .25)
	while _accumulator >= GameHost.STEP:
		_accumulator -= GameHost.STEP
		_step()
	_since_report += delta
	if _since_report >= report_every:
		_report()


## One tick, and a client's delta every DELTA_EVERY ticks.
func _step() -> void:
	host.step(controls)
	_ticks += 1
	_window += 1
	_spent += host.step_ms
	_worst = maxf(_worst, host.step_ms)
	if host.tick % GameHost.DELTA_EVERY == 0:
		var d := host.delta_since(_acked)
		_acked = host.tick
		_delta_spent += host.delta_ms
		_delta_bytes += d.size()
		_deltas += 1


func _flat_out() -> void:
	while _ticks < limit:
		_step()
		if _window >= 1200:
			_report()
	_report()
	print("SERVER DONE after %d ticks" % _ticks)
	get_tree().quit()


func _report() -> void:
	if _window == 0:
		return
	print(
		(
			"SERVER tick %d: tick %.3f ms mean, %.2f worst; delta %.3f ms, %d bytes (%d deltas)"
			% [
				host.tick,
				_spent / _window,
				_worst,
				_delta_spent / maxf(1.0, _deltas),
				_delta_bytes / maxi(1, _deltas),
				_deltas
			]
		)
	)
	_since_report = 0.0
	_spent = 0.0
	_worst = 0.0
	_window = 0
	_delta_spent = 0.0
	_delta_bytes = 0
	_deltas = 0
