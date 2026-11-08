class_name SimStrings
extends SimTool
## strings [-n N] <binary>: printable sequences embedded in a binary (text
## sitting in .rodata, library names, symbol names in a not-stripped file).
## The lab stores a curated, real-captured list (the real tool's default
## minimum length is 4; this lab's list was captured at -n 6, so -n below 6
## cannot show anything shorter that was trimmed from the capture).

const SPEC := {"-n": true}


func tool_name() -> String:
	return "strings"


func run(argv: Array, ctx: SimContext, _stdin: Array) -> Dictionary:
	var p := parse_flags(argv, SPEC)
	if p["bad"] != "":
		return unsupported("strings", p["bad"])
	if p["missing"] != "":
		return done(["strings: option requires an argument -- 'n'"], 1)
	var args: Array = p["args"]
	if args.is_empty():
		return done(["Usage: strings [-n min-len] <file>"], 1)
	var name: String = args[0]
	var bins := ctx.lab.binaries_for_you()
	if not bins.has(name):
		return done(["strings: '%s': No such file" % name], 1)
	var out: Array = (bins[name]["strings"] as Array).duplicate()
	if p["opts"].has("-n"):
		var n_text: String = p["opts"]["-n"]
		if not n_text.is_valid_int():
			return done(["strings: invalid minimum string length %s" % n_text], 1)
		var n := int(n_text)
		out = out.filter(func(s): return (s as String).length() >= n)
	return done(out)
