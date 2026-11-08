class_name SimWc
extends SimTool
## wc -l / -w / -c over piped text or a lab file.

const SPEC := {"-l": false, "-w": false, "-c": false}


func tool_name() -> String:
	return "wc"


func run(argv: Array, ctx: SimContext, stdin: Array) -> Dictionary:
	var p := parse_flags(argv, SPEC)
	if p["bad"] != "":
		return unsupported("wc", p["bad"])
	var lines: Array = stdin
	var label := ""
	if not (p["args"] as Array).is_empty():
		var files := ctx.lab.files_for_you()
		label = p["args"][0]
		if not files.has(label):
			return done(["wc: %s: No such file or directory" % label], 1)
		lines = Array((files[label] as String).trim_suffix("\n").split("\n"))
	var words := 0
	var bytes := 0
	for l in lines:
		words += (l as String).split(" ", false).size()
		bytes += (l as String).to_utf8_buffer().size() + 1
	var counts: Array = []
	var chosen: Array = [p["opts"].has("-l"), p["opts"].has("-w"), p["opts"].has("-c")]
	var values: Array = [lines.size(), words, bytes]
	if not chosen.has(true):
		chosen = [true, true, true]
	for i in 3:
		if chosen[i]:
			counts.append(values[i])
	var text := ""
	if counts.size() == 1 and label == "":
		text = str(counts[0])
	else:
		var width := 7 if label == "" else (1 if counts.size() == 1 else str(bytes).length())
		var parts: Array = []
		for c in counts:
			parts.append(str(c).lpad(width))
		text = " ".join(parts)
		if label != "":
			text += " " + label
	return done([text])
