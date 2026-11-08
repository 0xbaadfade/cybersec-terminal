class_name SimReadelf
extends SimTool
## readelf -h|-l|-d <binary>: the ELF header, program headers (segments, for
## spotting an executable GNU_STACK or a GNU_RELRO segment) or dynamic
## section (for spotting BIND_NOW). One flag at a time; each is the lab's
## stored, real-captured text for that view.

const SPEC := {"-h": false, "-l": false, "-d": false}
const FIELD := {"-h": "readelf_h", "-l": "readelf_l", "-d": "readelf_d"}


func tool_name() -> String:
	return "readelf"


func run(argv: Array, ctx: SimContext, _stdin: Array) -> Dictionary:
	var p := parse_flags(argv, SPEC)
	if p["bad"] != "":
		return unsupported("readelf", p["bad"])
	var chosen: Array = FIELD.keys().filter(func(f): return p["opts"].has(f))
	var args: Array = p["args"]
	if chosen.size() != 1 or args.size() != 1:
		return done(["Usage: readelf (-h|-l|-d) <elf-file>  (one flag, one file, in this simulator)"], 1)
	var name: String = args[0]
	var bins := ctx.lab.binaries_for_you()
	if not bins.has(name):
		return done(["readelf: Error: '%s': No such file" % name], 1)
	var lines: Array = (bins[name][FIELD[chosen[0]]] as Array).duplicate()
	if lines.is_empty():
		return unsupported("readelf", chosen[0])
	return done(lines)
