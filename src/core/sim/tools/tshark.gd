class_name SimTshark
extends SimTool
## tshark -r <capture> [-Y <filter>] [-V]: one-line frame summaries from a
## recorded capture, a small display-filter subset, and stored packet detail
## with -V. Layout modelled from Wireshark's documentation and unverified
## against the real tool (README "Wireless Security skill plan").

const SPEC := {"-r": true, "-Y": true, "-V": false}
const KNOWN_TAGS: Array = ["wlan", "eapol", "radius", "eap", "tls"]
const FIELDS: Array = ["wlan.fc.type_subtype", "wlan.addr", "wlan.sa", "wlan.da", "wlan.bssid", "frame.number", "wlan.ssid"]


func tool_name() -> String:
	return "tshark"


func run(argv: Array, ctx: SimContext, _stdin: Array) -> Dictionary:
	var p := parse_flags(argv, SPEC)
	if p["bad"] != "":
		return unsupported("tshark", p["bad"])
	if p["missing"] != "":
		return done(["tshark: option '%s' needs a value" % p["missing"]], 2)
	if not p["opts"].has("-r") or not (p["args"] as Array).is_empty():
		return done(["Usage: tshark -r <capture-file> [-Y <display-filter>] [-V]"], 1)
	var caps := ctx.lab.captures_for_you()
	var name: String = (p["opts"]["-r"] as String).trim_prefix("./")
	if not caps.has(name):
		return done(["tshark: The file \"%s\" doesn't exist." % name], 2)
	var terms: Array = []
	if p["opts"].has("-Y"):
		var parsed := _parse_filter(str(p["opts"]["-Y"]))
		if parsed["error"] != "":
			return done([parsed["error"]], 2)
		terms = parsed["terms"]
	var verbose: bool = p["opts"].has("-V")
	var out: Array = []
	var frames: Array = caps[name]["frames"]
	for i in frames.size():
		var f: Dictionary = frames[i]
		if not _matches(f, i + 1, terms):
			continue
		if verbose:
			out.append("Frame %d: %d bytes on wire" % [i + 1, int(f["len"])])
			var detail: Array = f.get("detail", [])
			if detail.is_empty():
				out.append("    (no packet detail is stored for this frame in the simulator)")
			for line in detail:
				out.append(line)
			out.append("")
		else:
			out.append("%5d %10.6f %s → %s %s %d %s" % [i + 1, float(f["t"]), f["src"], f["dst"], f["proto"], int(f["len"]), f["info"]])
	return done(out)


## {"terms": [[field, op, value]...] or [["tag", word]], "error": ""}.
static func _parse_filter(text: String) -> Dictionary:
	var normalized := text.replace(" and ", " && ")
	var terms: Array = []
	for raw in normalized.split("&&"):
		var term := (raw as String).strip_edges()
		if term == "":
			return {"terms": [], "error": "tshark: empty term in display filter"}
		var op := ""
		if term.contains("=="):
			op = "=="
		elif term.contains("!="):
			op = "!="
		if op == "":
			if not KNOWN_TAGS.has(term):
				return {"terms": [], "error": "tshark: \"%s\" isn't supported by this simulator's display-filter subset (protocols: %s)" % [term, ", ".join(KNOWN_TAGS)]}
			terms.append(["tag", term])
			continue
		var halves := term.split(op)
		var field := (halves[0] as String).strip_edges()
		var value := (halves[1] as String).strip_edges().trim_prefix("\"").trim_suffix("\"").to_lower()
		if halves.size() != 2 or not FIELDS.has(field):
			return {"terms": [], "error": "tshark: \"%s\" isn't supported by this simulator's display-filter subset (fields: %s)" % [term, ", ".join(FIELDS)]}
		terms.append([field, op, value])
	return {"terms": terms, "error": ""}


static func _matches(f: Dictionary, number: int, terms: Array) -> bool:
	for t in terms:
		if t[0] == "tag":
			if not (f.get("tags", []) as Array).has(t[1]):
				return false
			continue
		var field: String = t[0]
		var value: String = t[2]
		var hit := false
		match field:
			"frame.number":
				hit = value.is_valid_int() and int(value) == number
			"wlan.fc.type_subtype":
				hit = _subtype_number(str(f.get("subtype", ""))) >= 0 and _subtype_number(str(f.get("subtype", ""))) == _subtype_number(value)
			"wlan.sa":
				hit = f["src"] == value
			"wlan.da":
				hit = f["dst"] == value
			"wlan.bssid":
				hit = str(f.get("bssid", "")) == value
			"wlan.addr":
				hit = f["src"] == value or f["dst"] == value or str(f.get("bssid", "")) == value
			"wlan.ssid":
				hit = str(f.get("ssid", "")).to_lower() == value
		if (t[1] == "==") != hit:
			return false
	return true


static func _subtype_number(text: String) -> int:
	var t := text.strip_edges().to_lower()
	if t.begins_with("0x") and t.substr(2).is_valid_hex_number(false):
		return t.hex_to_int()
	if t.is_valid_int():
		return int(t)
	return -1
