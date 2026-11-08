class_name SimGrep
extends SimTool
## grep over piped text or a lab file. Patterns are basic regular expressions
## (+ ? | ( ) { } are literal unless escaped, as in real grep); -E makes them
## extended.

const SPEC := {"-i": false, "-v": false, "-c": false, "-n": false, "-E": false}


func tool_name() -> String:
	return "grep"


func run(argv: Array, ctx: SimContext, stdin: Array) -> Dictionary:
	var p := parse_flags(argv, SPEC)
	if p["bad"] != "":
		return unsupported("grep", p["bad"])
	var opts: Dictionary = p["opts"]
	var args: Array = p["args"]
	if args.is_empty():
		return done(["Usage: grep [OPTION]... PATTERNS [FILE]..."], 2)
	var pattern: String = args[0]
	if not opts.has("-E"):
		pattern = _basic_to_extended(pattern)
	if opts.has("-i"):
		pattern = "(?i)" + pattern
	if _unbalanced(pattern):
		return done(["grep: Invalid regular expression"], 2)
	var re := RegEx.new()
	if re.compile(pattern) != OK:
		return done(["grep: Invalid regular expression"], 2)
	var sources: Array = []  # [name or "", lines]
	if args.size() == 1:
		sources.append(["", stdin])
	else:
		var files := ctx.lab.files_for_you()
		for i in range(1, args.size()):
			if not files.has(args[i]):
				return done(["grep: %s: No such file or directory" % args[i]], 2)
			sources.append([args[i] if args.size() > 2 else "", Array((files[args[i]] as String).trim_suffix("\n").split("\n"))])
	var out: Array = []
	var matches := 0
	for src in sources:
		var n := 0
		for i in (src[1] as Array).size():
			var line: String = src[1][i]
			var hit := re.search(line) != null
			if hit == opts.has("-v"):
				continue
			n += 1
			if not opts.has("-c"):
				var prefix := ""
				if src[0] != "":
					prefix += "%s:" % src[0]
				if opts.has("-n"):
					prefix += "%d:" % (i + 1)
				out.append(prefix + line)
		matches += n
		if opts.has("-c"):
			out.append(("%s:%d" % [src[0], n]) if src[0] != "" else str(n))
	return done(out, 0 if matches > 0 else 1)


## True for the typos a learner makes: an unclosed ( [ or {, a stray ), or a
## trailing backslash. Checked first so an invalid pattern never reaches the
## regex engine (which would print an engine error).
static func _unbalanced(pattern: String) -> bool:
	var depth := 0
	var in_class := false
	var braces := 0
	var i := 0
	while i < pattern.length():
		var ch := pattern[i]
		if ch == "\\":
			if i + 1 >= pattern.length():
				return true
			i += 2
			continue
		if in_class:
			if ch == "]":
				in_class = false
		elif ch == "[":
			in_class = true
		elif ch == "(":
			depth += 1
		elif ch == ")":
			depth -= 1
			if depth < 0:
				return true
		elif ch == "{":
			braces += 1
		elif ch == "}":
			braces -= 1
			if braces < 0:
				return true
		i += 1
	return in_class or depth != 0 or braces != 0


static func _basic_to_extended(pattern: String) -> String:
	var out := ""
	var i := 0
	while i < pattern.length():
		var ch := pattern[i]
		if ch == "\\" and i + 1 < pattern.length() and "+?|(){}".contains(pattern[i + 1]):
			out += pattern[i + 1]
			i += 2
			continue
		if ch == "\\" and i + 1 < pattern.length():
			out += ch + pattern[i + 1]
			i += 2
			continue
		out += ("\\" + ch) if "+?|(){}".contains(ch) else ch
		i += 1
	return out
