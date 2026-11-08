class_name SimTail
extends SimTool
## tail -n N (also -N), over piped text or a lab file.


func tool_name() -> String:
	return "tail"


func run(argv: Array, ctx: SimContext, stdin: Array) -> Dictionary:
	return SimHead.take(tool_name(), argv, ctx, stdin, false)
