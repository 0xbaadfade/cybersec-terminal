class_name SimAirodump
extends SimTool
## airodump-ng <capture>: one snapshot of the access-point and station tables
## from a recorded survey. The real tool needs a monitor-mode adapter and keeps
## scanning; this one reads a recording and prints one screen (README
## "Wireless Security skill plan"). The column layout is modelled from the
## tool's documentation and is unverified against the real tool.

const SPEC := {"--bssid": true}
## One layout for the header and the rows, so the columns line up even when a
## transition-mode row ("WPA3 WPA2", "SAE PSK") is wider than the real tool's.
const ROW := " %-17s  %3s  %7s  %7s %3s  %2s  %3s  %-9s %-10s %-7s %s"


func tool_name() -> String:
	return "airodump-ng"


func run(argv: Array, ctx: SimContext, _stdin: Array) -> Dictionary:
	var p := parse_flags(argv, SPEC)
	if p["bad"] != "":
		return unsupported("airodump-ng", p["bad"])
	if p["missing"] != "":
		return done(["airodump-ng: option '%s' needs a value" % p["missing"]], 2)
	var args: Array = p["args"]
	if args.size() != 1:
		return done(["Usage: airodump-ng [--bssid <mac>] <capture-file>   (the simulator reads a recording, not an interface)"], 1)
	var caps := ctx.lab.captures_for_you()
	var name: String = (args[0] as String).trim_prefix("./")
	if not caps.has(name):
		return done(["airodump-ng: %s: no such capture (this simulator reads recordings, not live interfaces)" % name], 1)
	var cap: Dictionary = caps[name]
	var only := ""
	if p["opts"].has("--bssid"):
		only = str(p["opts"]["--bssid"]).to_lower()
	var out: Array = []
	var banner := " CH %2d ][ Elapsed: %s ][ %s" % [cap["header_channel"], cap["elapsed"], cap["start"]]
	for ap in cap["aps"]:
		if ap.get("handshake", false) and (only == "" or only == ap["bssid"]):
			banner += " ][ WPA handshake: %s" % (ap["bssid"] as String).to_upper()
			break
	out.append(banner)
	out.append("")
	out.append(ROW % ["BSSID", "PWR", "Beacons", "#Data,", "#/s", "CH", "MB", "ENC", "CIPHER", "AUTH", "ESSID"])
	out.append("")
	for ap in cap["aps"]:
		if only != "" and ap["bssid"] != only:
			continue
		var essid: String = ap["essid"]
		if essid == "":
			essid = "<length: %2d>" % int(ap.get("hidden_length", 0))
		var rate := "%d" % int(ap["rate"]) if int(ap["rate"]) > 0 else "-1"
		out.append(ROW % [(ap["bssid"] as String).to_upper(), str(int(ap["pwr"])), str(int(ap["beacons"])), str(int(ap["data"])),
				str(int(ap.get("rate_per_s", 0))), str(int(ap["channel"])), rate, ap["enc"], ap["cipher"], ap["auth"], essid])
	out.append("")
	out.append(" BSSID              STATION            PWR   Rate    Lost    Frames  Notes  Probes")
	out.append("")
	for st in cap["stations"]:
		var b: String = st.get("bssid", "")
		if only != "" and b != only:
			continue
		var bssid_text := "(not associated)" if b == "" else (b as String).to_upper()
		out.append(" %-17s  %s  %3d  %-6s  %6d  %8d         %s" % [bssid_text, (st["mac"] as String).to_upper(), int(st.get("pwr", 0)),
				str(st.get("rate", "0 - 1")), int(st.get("lost", 0)), int(st.get("frames", 0)), str(st.get("probes", ""))])
	return done(out)
