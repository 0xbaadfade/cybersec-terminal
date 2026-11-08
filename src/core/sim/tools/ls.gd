class_name SimLs
extends SimTool
## ls on the learner's own lab files. Like the real one it prints a row on a
## terminal and one name per line when piped.

const SPEC := {"-1": false}


func tool_name() -> String:
	return "ls"


func run(argv: Array, ctx: SimContext, _stdin: Array) -> Dictionary:
	var p := parse_flags(argv, SPEC)
	if p["bad"] != "":
		return unsupported("ls", p["bad"])
	var files := ctx.lab.files_for_you()
	var names: Array = []
	var out: Array = []
	var code := 0
	if (p["args"] as Array).is_empty():
		names = files.keys()
	else:
		for f in p["args"]:
			if files.has(f):
				names.append(f)
			else:
				out.append("ls: cannot access '%s': No such file or directory" % f)
				code = 2
	names.sort()
	if names.is_empty():
		return done(out, code)
	if ctx.tty and not p["opts"].has("-1"):
		out.append("  ".join(names))
	else:
		out.append_array(names)
	return done(out, code)
