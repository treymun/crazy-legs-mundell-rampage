## Voice chat's sound on the wire (docs/dev/multiplayer.md "Voice chat").
##
## Godot 4.7 has no Opus, so the codec is written here: the mic at the
## mixer's rate is filtered (a high-pass for rumble and the mic's offset,
## two low-pass stages for the telephone band) and taken down to 8 kHz, then
## IMA-ADPCM squeezes each sample into 4 bits: 32 kbit/s, 4 KB a second while
## someone talks and nothing while they don't. Each 40 ms frame carries its
## own starting state, so a lost one costs only itself. A telephone's band is
## a CB radio's too, which suits the county.
##
## CLEAR 16K (VOICE QUALITY) is two bands, as G.722 is: the mic taken down
## to 16 kHz (up to `clear_top_hz`, still a radio's top) is split by a
## half-band filter pair (Split) into the band under 4 kHz and the band over
## it, each at 8 kHz. The low band is the very frame CB 8K sends (BYTES,
## IMA-ADPCM), the high band follows it in 2 bits a sample (HighCoder,
## HIGH_BYTES): a WIDE_BYTES frame, 49 kbit/s. Whoever passes a frame on can
## cut it back to its first BYTES for a listener that takes only CB 8K: a
## byte slice, no decoding. Join puts the bands back together at 16 kHz (a
## CB 8K frame with no high band: the same filter as a clean 2x upsampler).
##
##   var down := VoiceCodec.Down.new()
##   var pcm8k := down.take(mono_at_mix_rate, AudioServer.get_mix_rate())
##   var bytes := coder.encode(pcm8k.slice(0, VoiceCodec.FRAME))   # coder: VoiceCodec.Coder
##   var back := VoiceCodec.decode(bytes)
##   var pcm16k := joiner.take(bytes)   # joiner: VoiceCodec.Join; either kind of frame
class_name VoiceCodec
extends RefCounted

const VOICE_DATA := "res://data/tuning/voice.cfg"
## Samples a second on the wire (each band), and what a voice plays at.
const RATE := 8000
const OUT_RATE := 16000
## Samples in one frame (40 ms), and what a frame plays as.
const FRAME := 320
const OUT_FRAME := FRAME * 2
## A frame's bytes: the predictor (s16) and step index (u8) it starts from,
## then two samples a byte. CLEAR 16K's high band: its own start, then four
## samples a byte, after the low band's frame.
const HEADER := 3
const BYTES := HEADER + FRAME / 2
const HIGH_BYTES := HEADER + FRAME / 4
const WIDE_BYTES := BYTES + HIGH_BYTES
## The band kept (Hz): rumble under LOW_CUT, nothing past HIGH_CUT (CB 8K)
## or CLEAR_TOP (CLEAR 16K).
static var LOW_CUT: float = Tuning.file(VOICE_DATA).get_value("voice", "low_cut_hz", 120.0)
static var HIGH_CUT: float = Tuning.file(VOICE_DATA).get_value("voice", "high_cut_hz", 3500.0)
static var CLEAR_TOP: float = Tuning.file(VOICE_DATA).get_value("voice", "clear_top_hz", 6500.0)
## The half-band pair's all-pass coefficients (a polyphase IIR half-band
## of four, transition a tenth of the rate: flat to 3.4 kHz, 25 dB down at
## 4.4 and 70 past 4.8). 0 and 2 are the newer sample's path, 1 and 3 the
## older's.
const HALF: PackedFloat64Array = [
	0.07986642623635744, 0.28382934487410966, 0.5453236510711317, 0.8344118914807366
]

const STEPS: PackedInt32Array = [
	7,
	8,
	9,
	10,
	11,
	12,
	13,
	14,
	16,
	17,
	19,
	21,
	23,
	25,
	28,
	31,
	34,
	37,
	41,
	45,
	50,
	55,
	60,
	66,
	73,
	80,
	88,
	97,
	107,
	118,
	130,
	143,
	157,
	173,
	190,
	209,
	230,
	253,
	279,
	307,
	337,
	371,
	408,
	449,
	494,
	544,
	598,
	658,
	724,
	796,
	876,
	963,
	1060,
	1166,
	1282,
	1411,
	1552,
	1707,
	1878,
	2066,
	2272,
	2499,
	2749,
	3024,
	3327,
	3660,
	4026,
	4428,
	4871,
	5358,
	5894,
	6484,
	7132,
	7845,
	8630,
	9493,
	10442,
	11487,
	12635,
	13899,
	15289,
	16818,
	18500,
	20350,
	22385,
	24623,
	27086,
	29794,
	32767
]
const INDEX_MOVE: PackedInt32Array = [-1, -1, -1, -1, 2, 4, 6, 8]


## The encoder's running state (one per talker): frames follow each other
## without a jump, and each still says where it starts.
class Coder:
	extends RefCounted
	var predicted := 0
	var index := 0

	## FRAME samples (-1..1 at RATE) as BYTES bytes.
	func encode(pcm: PackedFloat32Array) -> PackedByteArray:
		var out := PackedByteArray()
		out.resize(BYTES)
		out.encode_s16(0, predicted)
		out[2] = index
		var pred := predicted
		var at := index
		var n := mini(pcm.size(), FRAME)
		for i in FRAME:
			var s := 0
			if i < n:
				s = clampi(roundi(pcm[i] * 32767.0), -32768, 32767)
			var diff := s - pred
			var code := 0
			if diff < 0:
				code = 8
				diff = -diff
			var step := STEPS[at]
			var delta := step >> 3
			if diff >= step:
				code |= 4
				diff -= step
				delta += step
			step >>= 1
			if diff >= step:
				code |= 2
				diff -= step
				delta += step
			step >>= 1
			if diff >= step:
				code |= 1
				delta += step
			pred = clampi(pred - delta if code & 8 else pred + delta, -32768, 32767)
			at = clampi(at + INDEX_MOVE[code & 7], 0, 88)
			var byte_at := HEADER + (i >> 1)
			if i & 1 == 0:
				out[byte_at] = code
			else:
				out[byte_at] = out[byte_at] | (code << 4)
		predicted = pred
		index = at
		return out


## A frame back to FRAME samples (-1..1); empty when it is not a frame.
static func decode(bytes: PackedByteArray) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if bytes.size() != BYTES:
		return out
	out.resize(FRAME)
	var pred := bytes.decode_s16(0)
	var at := clampi(bytes[2], 0, 88)
	for i in FRAME:
		var byte := bytes[HEADER + (i >> 1)]
		var code := byte & 15 if i & 1 == 0 else byte >> 4
		var step := STEPS[at]
		var delta := step >> 3
		if code & 4:
			delta += step
		if code & 2:
			delta += step >> 1
		if code & 1:
			delta += step >> 2
		pred = clampi(pred - delta if code & 8 else pred + delta, -32768, 32767)
		at = clampi(at + INDEX_MOVE[code & 7], 0, 88)
		out[i] = pred / 32768.0
	return out


## The level of `pcm` in dB under full scale (its root mean square).
static func level_db(pcm: PackedFloat32Array) -> float:
	if pcm.is_empty():
		return -120.0
	var sum := 0.0
	for s: float in pcm:
		sum += s * s
	return 10.0 * log(maxf(sum / pcm.size(), 1e-12)) / log(10.0)


## The mic's sound at any rate down to RATE (CLEAR 16K: OUT_RATE): a
## one-pole high-pass, two Butterworth low-pass stages (24 dB an octave past
## HIGH_CUT or CLEAR_TOP, so little folds back), then each output sample
## read between its two neighbours.
class Down:
	extends RefCounted
	var _to := RATE
	var _top := 0.0
	var _rate := 0.0
	var _step := 1.0
	var _pos := 0.0
	var _prev := 0.0
	var _hp_in := 0.0
	var _hp_out := 0.0
	var _hp := 0.0
	var _b: PackedFloat32Array = []
	var _z: PackedFloat32Array = [0.0, 0.0, 0.0, 0.0]

	## `top`: the band's top (Hz; 0: HIGH_CUT).
	func _init(to := RATE, top := 0.0) -> void:
		_to = to
		_top = top if top > 0.0 else VoiceCodec.HIGH_CUT

	func _setup(rate: float) -> void:
		_rate = rate
		_step = rate / _to
		_hp = exp(-TAU * VoiceCodec.LOW_CUT / rate)
		var w := TAU * minf(_top, rate * .45) / rate
		var alpha := sin(w) / (2.0 * .70710678)
		var cw := cos(w)
		var a0 := 1.0 + alpha
		var b0 := (1.0 - cw) * .5 / a0
		_b = [b0, 2.0 * b0, b0, -2.0 * cw / a0, (1.0 - alpha) / a0]

	## `mono` at `rate` as samples at RATE (as many as it makes).
	func take(mono: PackedFloat32Array, rate: float) -> PackedFloat32Array:
		if rate != _rate:
			_setup(rate)
		var out := PackedFloat32Array()
		var b0 := _b[0]
		var b1 := _b[1]
		var b2 := _b[2]
		var a1 := _b[3]
		var a2 := _b[4]
		var z0 := _z[0]
		var z1 := _z[1]
		var z2 := _z[2]
		var z3 := _z[3]
		var pos := _pos
		var prev := _prev
		for x: float in mono:
			var h := _hp * (_hp_out + x - _hp_in)
			_hp_in = x
			_hp_out = h
			# Two biquads, transposed direct form II.
			var y := b0 * h + z0
			z0 = b1 * h - a1 * y + z1
			z1 = b2 * h - a2 * y
			var v := b0 * y + z2
			z2 = b1 * y - a1 * v + z3
			z3 = b2 * y - a2 * v
			while pos <= 1.0:
				out.append(prev + (v - prev) * pos)
				pos += _step
			pos -= 1.0
			prev = v
		_z = [z0, z1, z2, z3]
		_pos = pos
		_prev = prev
		return out


## CLEAR 16K's high band, 2 bits a sample: a sign and whether the step was
## passed (half a step or one and a half back), the step growing three
## places when passed and shrinking one when not, from a guess of three
## quarters of the last sample (the band is turned over so it changes slowly).
class HighCoder:
	extends RefCounted
	var predicted := 0
	var index := 0

	## FRAME samples (-1..1 at RATE) as HIGH_BYTES bytes.
	func encode(pcm: PackedFloat32Array) -> PackedByteArray:
		var out := PackedByteArray()
		out.resize(HIGH_BYTES)
		out.encode_s16(0, predicted)
		out[2] = index
		var pred := predicted
		var at := index
		var n := mini(pcm.size(), FRAME)
		for i in FRAME:
			var s := 0
			if i < n:
				s = clampi(roundi(pcm[i] * 32767.0), -32768, 32767)
			var guess := (pred * 3) >> 2
			var diff := s - guess
			var step := STEPS[at]
			var code := 2 if diff < 0 else 0
			var delta := step >> 1
			if absi(diff) >= step:
				code |= 1
				delta += step
			pred = clampi(guess - delta if code & 2 else guess + delta, -32768, 32767)
			at = clampi(at + (3 if code & 1 else -1), 0, 88)
			var byte_at := HEADER + (i >> 2)
			out[byte_at] = out[byte_at] | (code << ((i & 3) << 1))
		predicted = pred
		index = at
		return out


## A high band's HIGH_BYTES back to FRAME samples (-1..1); empty when not one.
static func decode_high(bytes: PackedByteArray) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if bytes.size() != HIGH_BYTES:
		return out
	out.resize(FRAME)
	var pred := bytes.decode_s16(0)
	var at := clampi(bytes[2], 0, 88)
	for i in FRAME:
		var code := (bytes[HEADER + (i >> 2)] >> ((i & 3) << 1)) & 3
		var guess := (pred * 3) >> 2
		var step := STEPS[at]
		var delta := step >> 1
		if code & 1:
			delta += step
		pred = clampi(guess - delta if code & 2 else guess + delta, -32768, 32767)
		at = clampi(at + (3 if code & 1 else -1), 0, 88)
		out[i] = pred / 32768.0
	return out


## The half-band analysis: OUT_FRAME samples at OUT_RATE as FRAME of the
## band under 4 kHz and FRAME of the band over it (turned over: every other
## sample's sign flipped, so 4 to 6 kHz lies at 0 to 2 kHz), each at RATE.
## Two all-pass paths, one for each sample of a pair; their sum is the low
## band, their difference the high.
class Split:
	extends RefCounted
	var _z: PackedFloat64Array = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]

	## [low, high]
	func take(pcm: PackedFloat32Array) -> Array[PackedFloat32Array]:
		var low := PackedFloat32Array()
		var high := PackedFloat32Array()
		var n := pcm.size() >> 1
		low.resize(n)
		high.resize(n)
		var c0 := HALF[0]
		var c1 := HALF[1]
		var c2 := HALF[2]
		var c3 := HALF[3]
		# Each first-order all-pass: y = c (x - y1) + x1 (x1, y1 its last in and out).
		var ax1 := _z[0]
		var ay1 := _z[1]
		var bx1 := _z[2]
		var by1 := _z[3]
		var cx1 := _z[4]
		var cy1 := _z[5]
		var dx1 := _z[6]
		var dy1 := _z[7]
		for m in n:
			var older: float = pcm[m * 2]
			var newer: float = pcm[m * 2 + 1]
			var a := c0 * (newer - ay1) + ax1
			ax1 = newer
			ay1 = a
			var u0 := c2 * (a - by1) + bx1
			bx1 = a
			by1 = u0
			var b := c1 * (older - cy1) + cx1
			cx1 = older
			cy1 = b
			var u1 := c3 * (b - dy1) + dx1
			dx1 = b
			dy1 = u1
			low[m] = (u0 + u1) * .5
			high[m] = (u0 - u1) * (.5 if m & 1 == 0 else -.5)
		_z = [ax1, ay1, bx1, by1, cx1, cy1, dx1, dy1]
		return [low, high]


## The half-band synthesis, one voice's: a frame (BYTES: CB 8K, WIDE_BYTES:
## CLEAR 16K) as OUT_FRAME samples at OUT_RATE; empty when it is neither.
## The filter's state runs on from frame to frame (a lost frame's cover is
## made from what was played, not through it).
class Join:
	extends RefCounted
	var _z: PackedFloat64Array = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]

	func take(frame: PackedByteArray) -> PackedFloat32Array:
		var low := PackedFloat32Array()
		var high := PackedFloat32Array()
		if frame.size() == BYTES:
			low = VoiceCodec.decode(frame)
		elif frame.size() == WIDE_BYTES:
			low = VoiceCodec.decode(frame.slice(0, BYTES))
			high = VoiceCodec.decode_high(frame.slice(BYTES))
		if low.is_empty():
			return PackedFloat32Array()
		return bands(low, high)

	## `low` and `high` (as Split made them; `high` empty: none) at OUT_RATE.
	func bands(low: PackedFloat32Array, high: PackedFloat32Array) -> PackedFloat32Array:
		var out := PackedFloat32Array()
		var n := low.size()
		out.resize(n * 2)
		var wide := high.size() == n
		var c0 := HALF[0]
		var c1 := HALF[1]
		var c2 := HALF[2]
		var c3 := HALF[3]
		var ax1 := _z[0]
		var ay1 := _z[1]
		var bx1 := _z[2]
		var by1 := _z[3]
		var cx1 := _z[4]
		var cy1 := _z[5]
		var dx1 := _z[6]
		var dy1 := _z[7]
		for m in n:
			var l: float = low[m]
			var h := 0.0
			if wide:
				h = high[m] if m & 1 == 0 else -high[m]
			# Split's paths swapped: the difference through the newer sample's
			# path makes the older sample, the sum through the older's the newer.
			var a := c0 * (l - h - ay1) + ax1
			ax1 = l - h
			ay1 = a
			var older := c2 * (a - by1) + bx1
			bx1 = a
			by1 = older
			var b := c1 * (l + h - cy1) + cx1
			cx1 = l + h
			cy1 = b
			var newer := c3 * (b - dy1) + dx1
			dx1 = b
			dy1 = newer
			out[m * 2] = older
			out[m * 2 + 1] = newer
		_z = [ax1, ay1, bx1, by1, cx1, cy1, dx1, dy1]
		return out


## CLEAR 16K's sending side, one talker's: OUT_FRAME samples at OUT_RATE
## split (`split`, every frame, so the filter runs on through the quiet) and
## squeezed (`encode`, the frames that go) into WIDE_BYTES.
class WideCoder:
	extends RefCounted
	var low := Coder.new()
	var high := HighCoder.new()
	var _split := Split.new()

	func split(pcm: PackedFloat32Array) -> Array[PackedFloat32Array]:
		return _split.take(pcm)

	func encode(bands: Array[PackedFloat32Array]) -> PackedByteArray:
		var out := low.encode(bands[0])
		out.append_array(high.encode(bands[1]))
		return out
