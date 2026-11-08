class_name SimType
extends SimTool
## type: print one of the workstation's lab files (the Windows cat).


func tool_name() -> String:
	return "type"


func run(argv: Array, ctx: SimContext, _stdin: Array) -> Dictionary:
	if argv.is_empty():
		return done(["The syntax of the command is incorrect."], 1)
	var files := ctx.lab.files_for_you()
	var out: Array = []
	for f in argv:
		if not files.has(f):
			out.append("The system cannot find the file specified.")
			return done(out, 1)
		out.append_array((files[f] as String).trim_suffix("\n").split("\n"))
	return done(out)
