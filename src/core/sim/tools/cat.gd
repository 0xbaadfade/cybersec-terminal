class_name SimCat
extends SimTool
## cat on the learner's own lab files, or piped text; -n numbers the lines.

const SPEC := {"-n": false}


func tool_name() -> String:
	return "cat"


func run(argv: Array, ctx: SimContext, stdin: Array) -> Dictionary:
	var p := parse_flags(argv, SPEC)
	if p["bad"] != "":
		return unsupported("cat", p["bad"])
	var lines: Array = []
	var code := 0
	if (p["args"] as Array).is_empty():
		lines = stdin.duplicate()
	else:
		var files := ctx.lab.files_for_you()
		for f in p["args"]:
			if not files.has(f):
				lines.append("cat: %s: No such file or directory" % f)
				code = 1
			else:
				lines.append_array((files[f] as String).trim_suffix("\n").split("\n"))
	if p["opts"].has("-n"):
		for i in lines.size():
			lines[i] = "%6d\t%s" % [i + 1, lines[i]]
	return done(lines, code)
