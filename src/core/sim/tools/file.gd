class_name SimFile
extends SimTool
## file <binary>: identify what kind of ELF a binary is (type, architecture,
## linking, interpreter), the way the real `file` tool reads its magic bytes
## and headers. Output is stored per binary in the lab (README "Binary
## triage tools"); the simulator never inspects real bytes.


func tool_name() -> String:
	return "file"


func run(argv: Array, ctx: SimContext, _stdin: Array) -> Dictionary:
	if argv.is_empty():
		return done(["Usage: file [FILE]"], 1)
	if argv.size() > 1 or (argv[0] as String).begins_with("-"):
		return unsupported("file", argv[0] if (argv[0] as String).begins_with("-") else argv[1])
	var name: String = argv[0]
	var bins := ctx.lab.binaries_for_you()
	if not bins.has(name):
		return done(["file: cannot open `%s' (No such file or directory)" % name], 1)
	return done(["%s: %s" % [name, bins[name]["file_output"]]])
