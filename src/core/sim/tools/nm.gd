class_name SimNm
extends SimTool
## nm <binary>: list the symbol table (address, type letter, name) of a
## not-stripped binary. Output is the lab's stored, real-captured lines; no
## flags are modelled (nm -D/-C/--size-sort and friends say so).


func tool_name() -> String:
	return "nm"


func run(argv: Array, ctx: SimContext, _stdin: Array) -> Dictionary:
	if argv.is_empty():
		return done(["nm: no input files"], 1)
	if argv.size() > 1 or (argv[0] as String).begins_with("-"):
		return unsupported("nm", argv[0] if (argv[0] as String).begins_with("-") else argv[1])
	var name: String = argv[0]
	var bins := ctx.lab.binaries_for_you()
	if not bins.has(name):
		return done(["nm: '%s': No such file" % name], 1)
	return done((bins[name]["nm"] as Array).duplicate())
