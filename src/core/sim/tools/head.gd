class_name SimHead
extends SimTool
## head -n N (also -N), over piped text or a lab file.

const SPEC := {"-n": true}


func tool_name() -> String:
	return "head"


func run(argv: Array, ctx: SimContext, stdin: Array) -> Dictionary:
	return SimHead.take(tool_name(), argv, ctx, stdin, true)


## Shared by head and tail.
static func take(name: String, argv: Array, ctx: SimContext, stdin: Array, from_start: bool) -> Dictionary:
	var fixed: Array = []
	for tok in argv:
		var s: String = tok
		if s.length() > 1 and s.begins_with("-") and s.substr(1).is_valid_int():
			fixed.append_array(["-n", s.substr(1)])
		else:
			fixed.append(s)
	var p := parse_flags(fixed, SPEC)
	if p["bad"] != "":
		return unsupported(name, p["bad"])
	if p["missing"] != "":
		return done(["%s: option requires an argument -- 'n'" % name], 1)
	var n := 10
	if p["opts"].has("-n"):
		var text: String = p["opts"]["-n"]
		if not text.is_valid_int() or int(text) < 0:
			return done(["%s: invalid number of lines: '%s'" % [name, text]], 1)
		n = int(text)
	var lines: Array = stdin
	if not (p["args"] as Array).is_empty():
		var files := ctx.lab.files_for_you()
		var file: String = p["args"][0]
		if not files.has(file):
			return done(["%s: cannot open '%s' for reading: No such file or directory" % [name, file]], 1)
		lines = Array((files[file] as String).trim_suffix("\n").split("\n"))
	if from_start:
		return done(lines.slice(0, n))
	return done(lines.slice(maxi(0, lines.size() - n)) if n > 0 else [])
