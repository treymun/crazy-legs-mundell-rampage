## A tuning .cfg file's text with one key's value rewritten in place
## (DevTune.save): the rest of the file, its comments, order and line endings
## stay as they are. A value may run over several lines (an array or a
## dictionary): the whole of it is replaced.
class_name TuneText
extends RefCounted


## How many brackets ( [ { are open at the end of `text` (strings skipped).
static func depth(text: String) -> int:
	var open := 0
	var quoted := false
	var i := 0
	while i < text.length():
		var ch := text[i]
		if quoted:
			if ch == "\\":
				i += 1
			elif ch == '"':
				quoted = false
		elif ch == '"':
			quoted = true
		elif ch == ";" and open == 0:
			break  # a comment
		elif ch in ["(", "[", "{"]:
			open += 1
		elif ch in [")", "]", "}"]:
			open -= 1
		i += 1
	return open


static func _is_header(line: String) -> bool:
	var s := line.strip_edges()
	return s.begins_with("[") and s.ends_with("]") and not s.contains("=") and s.length() > 2


## `text` with [section] key's value set to `value` (Godot value text); the key
## (or the section) is added when the file lacks it.
static func rewrite(text: String, section: String, key: String, value: String) -> String:
	var nl := "\r\n" if text.contains("\r\n") else "\n"
	var lines := text.split(nl)
	var made := PackedStringArray((key + "=" + value).replace("\r\n", "\n").split("\n"))
	var header := "[%s]" % section
	var inside := false
	var last_value_end := -1
	var i := 0
	while i < lines.size():
		var line := lines[i]
		if _is_header(line):
			if inside:
				break  # the section ended without the key
			inside = line.strip_edges() == header
			if inside:
				last_value_end = i
			i += 1
			continue
		if not inside or line.strip_edges().begins_with(";") or not line.contains("="):
			i += 1
			continue
		var name := line.left(line.find("=")).strip_edges()
		# The value's lines: on till its brackets close.
		var end := i
		var open := depth(line.substr(line.find("=") + 1))
		while open > 0 and end + 1 < lines.size():
			end += 1
			open += depth(lines[end])
		if name == key:
			var out := lines.slice(0, i)
			out.append_array(made)
			out.append_array(lines.slice(end + 1))
			return nl.join(out)
		last_value_end = end
		i = end + 1
	if last_value_end < 0:
		# No such section: a new one at the end.
		var tail := lines.duplicate()
		if not tail.is_empty() and tail[tail.size() - 1] == "":
			tail.remove_at(tail.size() - 1)
		tail.append("")
		tail.append(header)
		tail.append_array(made)
		tail.append("")
		return nl.join(tail)
	var added := lines.slice(0, last_value_end + 1)
	added.append_array(made)
	added.append_array(lines.slice(last_value_end + 1))
	return nl.join(added)
