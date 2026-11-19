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
##   var down := VoiceCodec.Down.new()
##   var pcm8k := down.take(mono_at_mix_rate, AudioServer.get_mix_rate())
##   var bytes := coder.encode(pcm8k.slice(0, VoiceCodec.FRAME))   # coder: VoiceCodec.Coder
##   var back := VoiceCodec.decode(bytes)
class_name VoiceCodec
extends RefCounted

## Samples a second on the wire.
const RATE := 8000
## Samples in one frame (40 ms).
const FRAME := 320
## A frame's bytes: the predictor (s16) and step index (u8) it starts from,
## then two samples a byte.
const HEADER := 3
const BYTES := HEADER + FRAME / 2
## The band kept (Hz): rumble under LOW_CUT, nothing past HIGH_CUT.
const LOW_CUT := 120.0
const HIGH_CUT := 3500.0

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


## The mic's sound at any rate down to RATE: a one-pole high-pass, two
## Butterworth low-pass stages (24 dB an octave past HIGH_CUT, so little
## folds back), then each output sample read between its two neighbours.
class Down:
	extends RefCounted
	var _rate := 0.0
	var _step := 1.0
	var _pos := 0.0
	var _prev := 0.0
	var _hp_in := 0.0
	var _hp_out := 0.0
	var _hp := 0.0
	var _b: PackedFloat32Array = []
	var _z: PackedFloat32Array = [0.0, 0.0, 0.0, 0.0]

	func _setup(rate: float) -> void:
		_rate = rate
		_step = rate / RATE
		_hp = exp(-TAU * LOW_CUT / rate)
		var w := TAU * minf(HIGH_CUT, rate * .45) / rate
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
