class_name SimFindstr
extends SimTool
## findstr as a filter and a file searcher: /i, /v, /n, /c:"text". Several search
## words separated by spaces match any of them, as in the real tool. Searches are
## literal (the real default is a limited regular expression). UNVERIFIED against
## a real Windows machine (README "Phase 4c-2 as built").


func tool_name() -> String:
	return "findstr"


func run(argv: Array, ctx: SimContext, stdin: Array) -> Dictionary:
	var ignore_case := false
	var invert := false
	var numbers := false
	var literal := ""
	var rest: Array = []
	for tok in argv:
		var t: String = tok
		var low := t.to_lower()
		if low == "/i":
			ignore_case = true
		elif low == "/v":
			invert = true
		elif low == "/n":
			numbers = true
		elif low.begins_with("/c:"):
			literal = t.substr(3)
		elif t.begins_with("/"):
			return done(["findstr: option '%s' is not supported in this simulator" % t.get_slice(":", 0)], 2)
		else:
			rest.append(t)
	var words: Array = []
	if literal != "":
		words = [literal]
	elif not rest.is_empty():
		words = (rest.pop_front() as String).split(" ", false)
	if words.is_empty():
		return done(["FINDSTR: Bad command line"], 2)
	var lines: Array = stdin
	if not rest.is_empty():
		lines = []
		var files := ctx.lab.files_for_you()
		for f in rest:
			if not files.has(f):
				return done(["FINDSTR: Cannot open %s" % f], 2)
			lines.append_array((files[f] as String).trim_suffix("\n").split("\n"))
	var out: Array = []
	for i in lines.size():
		var line: String = lines[i]
		var hit := false
		for w in words:
			hit = hit or (line.to_lower().contains((w as String).to_lower()) if ignore_case else line.contains(w))
		if hit != invert:
			out.append("%d:%s" % [i + 1, line] if numbers else line)
	return done(out, 0 if not out.is_empty() else 1)
