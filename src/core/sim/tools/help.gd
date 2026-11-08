class_name SimHelp
extends SimTool
## The shell's own help: what is available and how to ask for more.


func tool_name() -> String:
	return "help"


func run(_argv: Array, ctx: SimContext, _stdin: Array) -> Dictionary:
	var out: Array = [
		"tools:  %s" % "  ".join(ctx.tool_names),
		"shell:  help   tool <name> (a short manual page)   history   clear   exit",
		"pipes:  command | grep text | head -n 5   (grep, head, tail, wc -l work on any output)",
	]
	out.append_array(ctx.extra_help)
	return done(out)
