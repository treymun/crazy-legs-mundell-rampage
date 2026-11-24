## voice_chat_check.gd's measures of CLEAR 16K against CB 8K: real speech
## to put through the codecs, and the SNR of what came back by its spectra.
extends RefCounted


## The test speech: voiced lines from audio_src (16-bit WAV) taken up to
## `rate` (empty when the files are not there).
static func speech(rate: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var dir := ProjectSettings.globalize_path("res://").path_join("../audio_src/final/sfx")
	for name: String in ["cuss_mundell_boss_0_clean.wav", "cuss_coot_brawl_0_clean.wav"]:
		var f := FileAccess.open(dir.path_join(name), FileAccess.READ)
		if f == null:
			return PackedFloat32Array()
		var bytes := f.get_buffer(f.get_length())
		var at := 12
		var from := 0
		var channels := 1
		var src_rate := 22050
		var pcm := PackedFloat32Array()
		while at + 8 <= bytes.size():
			var id := bytes.slice(at, at + 4).get_string_from_ascii()
			var size := bytes.decode_u32(at + 4)
			if id == "fmt ":
				channels = bytes.decode_u16(at + 10)
				src_rate = bytes.decode_u32(at + 12)
			elif id == "data":
				from = at + 8
				for i in range(from, mini(from + size, bytes.size()) - 1, 2 * channels):
					pcm.append(bytes.decode_s16(i) / 32768.0)
			at += 8 + size + (size & 1)
		var peak := 0.0
		for v: float in pcm:
			peak = maxf(peak, absf(v))
		# Up to the mic's rate, each sample between its two neighbours, at half level.
		var step := src_rate / rate
		var t := 0.0
		while t < pcm.size() - 1:
			var i := int(t)
			out.append((pcm[i] + (pcm[i + 1] - pcm[i]) * (t - i)) * .5 / maxf(peak, .01))
			t += step
	return out


## The SNR (dB) of `test` against `ref` (both at OUT_RATE) in each band
## [low Hz, high Hz]: from their short-time magnitude spectra (512 samples,
## a Hann window), so a filter's phase does not count, only what is heard.
static func band_snrs(ref: PackedFloat32Array, test: PackedFloat32Array, bands: Array) -> Array:
	var n := 512
	var sig: Array[float] = []
	var err: Array[float] = []
	for b in bands.size():
		sig.append(0.0)
		err.append(0.0)
	var count := mini(ref.size(), test.size())
	var at := 0
	while at + n <= count:
		var a := spectrum(ref.slice(at, at + n))
		var b2 := spectrum(test.slice(at, at + n))
		for k in a.size():
			var hz := k * float(VoiceCodec.OUT_RATE) / n
			for b in bands.size():
				var band: Array = bands[b]
				if hz >= float(band[0]) and hz <= float(band[1]):
					sig[b] += a[k] * a[k]
					err[b] += (a[k] - b2[k]) * (a[k] - b2[k])
		at += n
	var out: Array = []
	for b in bands.size():
		out.append(10.0 * log(sig[b] / maxf(err[b], 1e-12)) / log(10.0))
	return out


## The magnitudes of `x`'s spectrum (size a power of two; Hann windowed), to half.
static func spectrum(x: PackedFloat32Array) -> PackedFloat64Array:
	var n := x.size()
	var re := PackedFloat64Array()
	var im := PackedFloat64Array()
	re.resize(n)
	im.resize(n)
	var j := 0
	for i in n:
		re[j] = x[i] * (.5 - .5 * cos(TAU * i / n))
		var bit := n >> 1
		while bit > 0 and j & bit:
			j ^= bit
			bit >>= 1
		j |= bit
	var size := 2
	while size <= n:
		var half := size >> 1
		var w := -TAU / size
		for start in range(0, n, size):
			for k in half:
				var c := cos(w * k)
				var s := sin(w * k)
				var p := start + k
				var q := p + half
				var tr := re[q] * c - im[q] * s
				var ti := re[q] * s + im[q] * c
				re[q] = re[p] - tr
				im[q] = im[p] - ti
				re[p] += tr
				im[p] += ti
		size <<= 1
	var out := PackedFloat64Array()
	out.resize(n / 2 + 1)
	for k in out.size():
		out[k] = sqrt(re[k] * re[k] + im[k] * im[k])
	return out
