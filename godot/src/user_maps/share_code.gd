## A player map as a code to pass around (docs/online.md "Sharing maps";
## the numbers are data/tuning/map_share.json's):
##
##   long   CLMR1:<base64url of 3 bytes of size + the zstd'd canonical
##          text><4 letters of check>: the whole map, offline (COPY ITS CODE,
##          ENTER A CODE in CUSTOM MAPS), for a chat, a forum, a file
##   short  7KQ2-M9XD: 8 letters of the map's hash, for a map on the server's
##          shelf (src/net/map_shelf.gd); only the shelf can turn it back
##
## Letters are Crockford's base 32 (no I, L, O or U, so nothing reads as a
## word or as another letter; O, I and L typed are read as 0, 1 and 1). A
## code is only ever read back into a map through UserMap.parse_text and its
## canonical form, the same way a file or a lobby's MAP is: nothing in it is
## run, and a code that claims more than a map's size is refused before it
## is unpacked. pack() and unpack_bytes() are the MAP packet's and the
## shelf's own bytes (zstd past "pack_over", sizes checked both sides).
class_name ShareCode
extends RefCounted

const TUNING := "res://data/tuning/map_share.json"
const LETTERS := "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
const BASE64URL := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
## Letters a typed short code may hold besides LETTERS, read as these.
const READ_AS := {"O": "0", "I": "1", "L": "1"}

static var _tuning := {}


static func tuning() -> Dictionary:
	if _tuning.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TUNING))
		_tuning = parsed if parsed is Dictionary else {}
	return _tuning


## A number of one of the file's parts ("codes", "packet", "shelf").
static func number(part: String, key: String) -> int:
	var block: Dictionary = tuning().get(part, {})
	var value: int = block.get(key, 0)
	return value


static func prefix() -> String:
	var block: Dictionary = tuning().get("codes", {})
	return str(block.get("long_prefix", "CLMR1:"))


# ------------------------------------------------------------------ short


## The shelf's code of a map's hash (hex): its first 40 bits as 8 letters.
static func short_of(hash: String) -> String:
	var bits := hash.substr(0, 10).hex_to_int()
	var count := number("codes", "short_letters")
	var out := ""
	for i in count:
		out = LETTERS[bits & 31] + out
		bits >>= 5
	return out


## A short code as it is shown: 7KQ2-M9XD.
static func shown(code: String) -> String:
	if code.length() != 8:
		return code
	return code.substr(0, 4) + "-" + code.substr(4)


## A typed short code made plain ("7kq2 m9xd", "7KQ2-M9XD" -> "7KQ2M9XD"), or
## "" when it is not one.
static func clean_short(text: String) -> String:
	var out := ""
	for ch in text.to_upper():
		if ch == "-" or ch == " ":
			continue
		var c := str(READ_AS.get(ch, ch))
		if not LETTERS.contains(c):
			return ""
		out += c
	return out if out.length() == number("codes", "short_letters") else ""


# ------------------------------------------------------------------ long


static func _check(text: String) -> String:
	return short_of(text.sha256_text()).left(number("codes", "check_letters"))


## The long code of a map (its canonical text, packed).
static func long_of(map: Dictionary) -> String:
	var bytes := UserMap.to_text(map).to_utf8_buffer()
	var body := PackedByteArray([(bytes.size() >> 16) & 255, (bytes.size() >> 8) & 255])
	body.append(bytes.size() & 255)
	body.append_array(bytes.compress(FileAccess.COMPRESSION_ZSTD))
	var b64 := Marshalls.raw_to_base64(body).replace("+", "-").replace("/", "_")
	return prefix() + b64.trim_suffix("=").trim_suffix("=") + _check(UserMap.to_text(map))


## Whether `text` looks like a long code at all (CUSTOM MAPS' ENTER A CODE
## tells it from a short one).
static func is_long(text: String) -> bool:
	return text.strip_edges().to_upper().begins_with(prefix().get_slice(":", 0).left(4))


## A long code back to its map: {"map": ..., "text": its canonical text} or
## {"error": one plain line}. Spaces and line breaks a chat put in are
## dropped; the letters' case is the code's own.
static func from_long(text: String) -> Dictionary:
	var code := ""
	for ch in text:
		if ch != " " and ch != "\n" and ch != "\r" and ch != "\t":
			code += ch
	var head := prefix()
	if code.left(head.length()).to_upper() != head.to_upper():
		var said := code.get_slice(":", 0).to_upper()
		if said.begins_with("CLMR") and said.substr(4).to_int() > head.substr(4, 1).to_int():
			return {"error": "THAT CODE'S FROM A NEWER GAME. UPDATE TO USE IT."}
		return {"error": "THAT AIN'T A MAP CODE."}
	var rest := code.substr(head.length())
	var check_n := number("codes", "check_letters")
	var most := UserMap.limit("bytes")
	if rest.length() <= check_n + 4 or rest.length() > most * 2 + 16:
		return {"error": "THAT CODE'S CUT SHORT OR RUNS LONG."}
	var body := rest.left(rest.length() - check_n)
	var check := rest.right(check_n).to_upper()
	for ch in body:
		if not BASE64URL.contains(ch):
			return {"error": "THAT CODE GOT MANGLED ON THE WAY."}
	if body.length() % 4 == 1:
		return {"error": "THAT CODE GOT MANGLED ON THE WAY."}
	var b64 := body.replace("-", "+").replace("_", "/")
	b64 += "=".repeat((4 - b64.length() % 4) % 4)
	var raw := Marshalls.base64_to_raw(b64)
	if raw.size() < 4:
		return {"error": "THAT CODE GOT MANGLED ON THE WAY."}
	var size := (raw[0] << 16) | (raw[1] << 8) | raw[2]
	if size <= 0 or size > most:
		return {"error": "THAT CODE CLAIMS MORE MAP THAN A MAP CAN BE."}
	var bytes := raw.slice(3).decompress(size, FileAccess.COMPRESSION_ZSTD)
	if bytes.size() != size:
		return {"error": "THAT CODE GOT MANGLED ON THE WAY."}
	var map_text := bytes.get_string_from_utf8()
	if _check(map_text) != check:
		return {"error": "THAT CODE GOT MANGLED ON THE WAY."}
	var parsed := UserMap.parse_text(map_text)
	if parsed.has("error"):
		return parsed
	var map: Dictionary = parsed["map"]
	if UserMap.to_text(map) != map_text:
		return {"error": "THE MAP ISN'T IN THE SHED'S OWN FORM."}
	return {"map": map, "text": map_text}


# ------------------------------------------------------------------ bytes


## A map's canonical text for a packet: {"data": the bytes} as they are, or
## {"data": zstd'd, "z": the size unpacked} past "pack_over" bytes.
static func pack(text: String) -> Dictionary:
	var bytes := text.to_utf8_buffer()
	if bytes.size() > number("packet", "pack_over"):
		var packed := bytes.compress(FileAccess.COMPRESSION_ZSTD)
		if packed.size() < bytes.size():
			return {"data": packed, "z": bytes.size()}
	return {"data": bytes}


## pack()'s bytes back, at most `most` either way: {"bytes": ...} or
## {"error": ...}. The size said is checked before unpacking (no more than
## `most` is ever made) and the size made against it after.
static func unpack_bytes(info: Dictionary, most: int) -> Dictionary:
	var data: Variant = info.get("data")
	if not data is PackedByteArray:
		return {"error": "THE MAP CAME MANGLED."}
	var raw: PackedByteArray = data
	if raw.is_empty():
		return {"error": "THE MAP CAME EMPTY."}
	if raw.size() > most:
		return {"error": "THE MAP CAME TOO BIG TO BE ONE."}
	if not info.has("z"):
		return {"bytes": raw}
	var z: Variant = info["z"]
	if not z is int:
		return {"error": "THE MAP CAME MANGLED."}
	var size: int = z
	if size <= 0:
		return {"error": "THE MAP CAME MANGLED."}
	if size > most:
		return {"error": "THE MAP CAME TOO BIG TO BE ONE."}
	var bytes := raw.decompress(size, FileAccess.COMPRESSION_ZSTD)
	if bytes.size() != size:
		return {"error": "THE MAP CAME MANGLED."}
	return {"bytes": bytes}


# ------------------------------------------------------------------ words


## "" when a map's name, author and note are fit for a shelf everybody sees,
## else why not (the shelf asks the same; the game asks first).
static func words_ok(map: Dictionary) -> String:
	var words: Array = tuning().get("words", [])
	for key: String in ["name", "author", "note"]:
		for word: String in _words_of(str(map.get(key, ""))):
			for bad: Variant in words:
				if word.contains(_rot13(str(bad))):
					return (
						"THE MAP'S %s HAS A WORD THE COUNTY WON'T PRINT."
						% {"name": "NAME", "author": "AUTHOR", "note": "NOTE"}[key]
					)
	return ""


## The words of a text, upper case, digits read as the letters they stand in for.
static func _words_of(text: String) -> PackedStringArray:
	var swaps := {"0": "O", "1": "I", "3": "E", "4": "A", "5": "S", "7": "T", "8": "B", "!": "I"}
	var plain := ""
	for ch in text.to_upper():
		var c := str(swaps.get(ch, ch))
		plain += c if c >= "A" and c <= "Z" else " "
	return plain.split(" ", false)


static func _rot13(text: String) -> String:
	var out := ""
	for ch in text.to_upper():
		var c := ch.unicode_at(0)
		if c >= 65 and c <= 90:
			c = 65 + (c - 65 + 13) % 26
		out += String.chr(c)
	return out
