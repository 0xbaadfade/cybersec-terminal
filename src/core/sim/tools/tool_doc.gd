class_name SimToolDoc
extends SimTool
## `tool <name>`: a short manual page written for the exam, from the pack's
## tools.json. `tool` alone lists the tools.


func tool_name() -> String:
	return "tool"


func run(argv: Array, ctx: SimContext, _stdin: Array) -> Dictionary:
	if argv.is_empty():
		var out: Array = []
		for t in ctx.tool_names:
			var doc: Dictionary = ctx.tool_docs.get(t, {}).duplicate()
			if ctx.lab.you["os"] == "windows" and doc.has("windows"):
				doc.merge(doc["windows"], true)
			out.append("  %-8s %s" % [t, doc.get("summary", "")])
		out.append("tool <name> shows one in full.")
		return done(out)
	var name: String = argv[0]
	if not ctx.tool_docs.has(name) or not ctx.tool_names.has(name):
		return done(["tool: no manual entry for '%s'" % name], 1)
	var d: Dictionary = ctx.tool_docs[name].duplicate()
	if ctx.lab.you["os"] == "windows" and d.has("windows"):
		d.merge(d["windows"], true)
	var out2: Array = ["%s - %s" % [name, d.get("summary", "")]]
	if d.has("usage"):
		out2.append("  usage: %s" % d["usage"])
	for f in d.get("flags", []):
		out2.append("  %-12s %s" % [f[0], f[1]])
	for cid in d.get("concepts", []):
		out2.append("Concept: %s" % ctx.concept_titles.get(cid, cid))
	if d.has("note"):
		out2.append(d["note"])
	return done(out2)
