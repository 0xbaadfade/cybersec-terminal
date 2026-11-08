class_name SimTool
extends RefCounted
## One command of the simulated shell. run() returns {"out": Array of text
## lines, "code": exit code}. A tool computes everything from the lab; it never
## starts a process or opens a socket.


func tool_name() -> String:
	return ""


func run(_argv: Array, _ctx: SimContext, _stdin: Array) -> Dictionary:
	return done([])


static func done(out: Array, code: int = 0) -> Dictionary:
	return {"out": out, "code": code}


static func unsupported(tool: String, flag: String) -> Dictionary:
	return done(["%s: option '%s' is not supported in this simulator" % [tool, flag]], 2)


## Short and long options. `spec` maps a flag to whether it takes a value, e.g.
## {"-c": true, "-n": false}. Short flags may be clustered (-nq) and take an
## attached value (-c3). Returns {"opts": {flag: value or true}, "args": [...],
## "bad": first unsupported flag or "", "missing": a flag lacking its value or ""}.
static func parse_flags(argv: Array, spec: Dictionary) -> Dictionary:
	var opts: Dictionary = {}
	var args: Array = []
	var i := 0
	var only_args := false
	while i < argv.size():
		var tok: String = argv[i]
		i += 1
		if only_args or tok == "-" or not tok.begins_with("-"):
			args.append(tok)
		elif tok == "--":
			only_args = true
		elif tok.begins_with("--"):
			var key := tok.get_slice("=", 0)
			if not spec.has(key):
				return {"opts": opts, "args": args, "bad": key, "missing": ""}
			if spec[key]:
				if tok.contains("="):
					opts[key] = tok.substr(key.length() + 1)
				elif i < argv.size():
					opts[key] = argv[i]
					i += 1
				else:
					return {"opts": opts, "args": args, "bad": "", "missing": key}
			else:
				opts[key] = true
		else:
			var j := 1
			while j < tok.length():
				var flag := "-" + tok[j]
				if not spec.has(flag):
					return {"opts": opts, "args": args, "bad": flag, "missing": ""}
				if spec[flag]:
					var attached := tok.substr(j + 1)
					if attached != "":
						opts[flag] = attached
					elif i < argv.size():
						opts[flag] = argv[i]
						i += 1
					else:
						return {"opts": opts, "args": args, "bad": "", "missing": flag}
					break
				opts[flag] = true
				j += 1
	return {"opts": opts, "args": args, "bad": "", "missing": ""}
