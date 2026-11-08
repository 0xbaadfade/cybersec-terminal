class_name SimHistory
extends SimTool
## history: the lines typed in this session.


func tool_name() -> String:
	return "history"


func run(_argv: Array, ctx: SimContext, _stdin: Array) -> Dictionary:
	var out: Array = []
	for i in ctx.history.size():
		out.append("%5d  %s" % [i + 1, ctx.history[i]])
	return done(out)
