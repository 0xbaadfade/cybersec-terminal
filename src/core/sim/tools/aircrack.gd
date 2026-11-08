class_name SimAircrack
extends SimTool
## aircrack-ng <capture>: lists the networks in a recording and how many WPA
## handshakes each has (Lab 1's "confirm you have a usable handshake" step).
## The dictionary attack (-w) is deliberately NOT modelled (README "Wireless
## Security skill plan"). Layout modelled from the tool's documentation and
## unverified against the real tool.

const SPEC := {}


func tool_name() -> String:
	return "aircrack-ng"


func run(argv: Array, ctx: SimContext, _stdin: Array) -> Dictionary:
	var p := parse_flags(argv, SPEC)
	if p["bad"] != "":
		return done(["aircrack-ng: option '%s' is not modelled in this simulator (it lists a recording's networks and handshakes; guessing passphrases is not simulated)" % p["bad"]], 2)
	var args: Array = p["args"]
	if args.size() != 1:
		return done(["Usage: aircrack-ng <capture-file>"], 1)
	var caps := ctx.lab.captures_for_you()
	var name: String = (args[0] as String).trim_prefix("./")
	if not caps.has(name):
		return done(["Opening %s failed: No such file or directory" % name], 1)
	var cap: Dictionary = caps[name]
	var out: Array = ["Reading packets, please wait...", "Opening %s" % name, "Read %d packets." % int(cap["packets"]), "",
			"   #  BSSID              ESSID                     Encryption", ""]
	var n := 0
	for ap in cap["aps"]:
		n += 1
		var essid: String = ap["essid"]
		if essid == "":
			essid = "Unknown"
		out.append("%4d  %s  %-24s  %s" % [n, (ap["bssid"] as String).to_upper(), essid, _encryption(ap)])
	out.append("")
	out.append("Index number of target network ? (the simulator does not prompt and does not attack: it stops here)")
	return done(out, 1)


static func _encryption(ap: Dictionary) -> String:
	var enc: String = ap["enc"]
	if enc == "OPN":
		return "None (0.0.0.0)"
	if enc == "WEP":
		return "WEP (%d IVs)" % int(ap.get("ivs", 0))
	if ap["auth"] == "SAE" or ap["auth"] == "OWE":
		return "Unknown"
	return "WPA (%d handshake)" % (1 if ap.get("handshake", false) else 0)
