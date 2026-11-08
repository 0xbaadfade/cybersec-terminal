class_name SimChecksec
extends SimTool
## checksec <binary>: a short report of the four exploit mitigations a binary
## was compiled with (RELRO, stack canary, NX, PIE). The real `checksec` tool
## was not available to build this simulator (README "Binary triage tools");
## this report's wording is the simulator's own, composed from the same real
## readelf facts `readelf -l`/`-d` show, not a copy of checksec.sh's table.


func tool_name() -> String:
	return "checksec"


func run(argv: Array, ctx: SimContext, _stdin: Array) -> Dictionary:
	if argv.size() != 1 or (argv[0] as String).begins_with("-"):
		return done(["Usage: checksec <file>"], 1)
	var name: String = argv[0]
	var bins := ctx.lab.binaries_for_you()
	if not bins.has(name):
		return done(["checksec: '%s': No such file" % name], 1)
	var b: Dictionary = bins[name]
	var relro_text: String = {"none": "No RELRO", "partial": "Partial RELRO", "full": "Full RELRO"}[b["relro"]]
	var canary_text := "Canary found" if b["canary"] else "No canary found"
	var nx_text := "NX enabled" if b["nx"] else "NX disabled (stack is executable)"
	var pie_text := "PIE enabled" if b["pie"] else "No PIE (fixed load address)"
	return done([
		"%s:" % name,
		"  RELRO:         %s" % relro_text,
		"  Stack canary:  %s" % canary_text,
		"  NX:            %s" % nx_text,
		"  PIE:           %s" % pie_text,
	])
