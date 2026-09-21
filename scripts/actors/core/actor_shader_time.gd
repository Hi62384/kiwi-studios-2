class_name ActorShaderTime
extends RefCounted
## Rewrites runtime shader copies only. Authoring resources are never modified.

static func prepare(source: String) -> Dictionary:
	var uniform_name := "kiwi_timeline_time"
	var suffix := 2
	while source.contains(uniform_name):
		uniform_name = "kiwi_timeline_time_%d" % suffix
		suffix += 1
	var output := ""
	var cursor := 0
	var has_time := false
	var inserted := false
	var after_shader_type := false
	while cursor < source.length():
		var current := source[cursor]
		var next := source[cursor + 1] if cursor + 1 < source.length() else ""
		if current == "/" and next == "/":
			var stop := source.find("\n", cursor)
			if stop < 0: stop = source.length()
			output += source.substr(cursor, stop - cursor)
			cursor = stop
			continue
		if current == "/" and next == "*":
			var stop := source.find("*/", cursor + 2)
			stop = source.length() if stop < 0 else stop + 2
			output += source.substr(cursor, stop - cursor)
			cursor = stop
			continue
		if current == '"' or current == "'":
			var quote := current
			var stop := cursor + 1
			while stop < source.length():
				if source[stop] == "\\":
					stop += 2
					continue
				if source[stop] == quote:
					stop += 1
					break
				stop += 1
			output += source.substr(cursor, stop - cursor)
			cursor = stop
			continue
		if _identifier_start(current):
			var stop := cursor + 1
			while stop < source.length() and _identifier_part(source[stop]): stop += 1
			var word := source.substr(cursor, stop - cursor)
			if word == "shader_type" and not inserted: after_shader_type = true
			if word == "TIME":
				output += uniform_name
				has_time = true
			else:
				output += word
			cursor = stop
			continue
		output += current
		if current == ";" and after_shader_type and not inserted:
			output += "\nuniform float %s;\n" % uniform_name
			inserted = true
			after_shader_type = false
		cursor += 1
	return {"code": output if has_time and inserted else source,
		"uniform": uniform_name if has_time and inserted else ""}


static func _identifier_start(character: String) -> bool:
	return character == "_" or (character >= "A" and character <= "Z") or (character >= "a" and character <= "z")


static func _identifier_part(character: String) -> bool:
	return _identifier_start(character) or (character >= "0" and character <= "9")
