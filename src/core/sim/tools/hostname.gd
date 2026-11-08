class_name SimHostname
extends SimTool
## hostname: the workstation's name.


func tool_name() -> String:
	return "hostname"


func run(_argv: Array, ctx: SimContext, _stdin: Array) -> Dictionary:
	return done([ctx.lab.you["name"]])
