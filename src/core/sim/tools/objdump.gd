class_name SimObjdump
extends SimTool
## objdump -d -M intel --disassemble=<function> <binary>: the disassembly of
## one function, Intel syntax, exactly as captured from the real tool and
## stored by the lab. A bare `-d` (every function, AT&T syntax, other
## disassembler options) is more than this simulator models.

const SPEC := {"-d": false, "-M": true, "--disassemble": true}


func tool_name() -> String:
	return "objdump"


func run(argv: Array, ctx: SimContext, _stdin: Array) -> Dictionary:
	var p := parse_flags(argv, SPEC)
	if p["bad"] != "":
		return unsupported("objdump", p["bad"])
	if p["missing"] != "":
		return done(["objdump: option '%s' requires an argument" % p["missing"]], 1)
	var args: Array = p["args"]
	if not p["opts"].has("--disassemble") or args.size() != 1:
		return done(["objdump: this simulator only supports",
				"  objdump -d -M intel --disassemble=<function> <file>"], 1)
	if p["opts"].get("-M", "") != "intel":
		return unsupported("objdump", "-M " + str(p["opts"].get("-M", "")))
	var func_name: String = p["opts"]["--disassemble"]
	var name: String = args[0]
	var bins := ctx.lab.binaries_for_you()
	if not bins.has(name):
		return done(["objdump: '%s': No such file" % name], 1)
	var functions: Dictionary = bins[name]["functions"]
	if not functions.has(func_name):
		return done(["objdump: %s: no symbol '%s' in this simulator's disassembly" % [name, func_name]], 1)
	return done((functions[func_name] as Array).duplicate())
