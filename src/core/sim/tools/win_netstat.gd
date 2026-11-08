class_name SimWinNetstat
extends SimTool
## netstat -an / -ano in the layout Windows documents. UNVERIFIED: written from
## Microsoft's published output, not captured (README "Phase 4c-2 as built").
## Without -a only established TCP connections are listed; -o adds the owning
## process id. Name resolution (no -n) and -b (needs an administrator) are refused.

const SPEC := {"-a": false, "-n": false, "-o": false}


func tool_name() -> String:
	return "netstat"


func run(argv: Array, ctx: SimContext, _stdin: Array) -> Dictionary:
	var p := parse_flags(SimWinTools.dash_options(argv), SPEC)
	if p["bad"] != "":
		if p["bad"] == "-b":
			return done(["The requested operation requires elevation."], 1)
		return unsupported("netstat", p["bad"])
	if not (p["args"] as Array).is_empty():
		return done(["netstat: arguments are not supported in this simulator"], 1)
	var o: Dictionary = p["opts"]
	if not o.has("-n"):
		return done(["netstat: resolving names is not simulated; add -n (netstat -an, netstat -ano)"], 1)
	var all := o.has("-a")
	var sockets := SimSockets.rows(ctx.lab, ["tcp", "udp"], all, true)
	sockets.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["proto"] == "tcp" and b["proto"] == "udp")
	var out: Array = ["", "Active Connections", ""]
	var head := "  Proto  %s %s %s" % ["Local Address".rpad(22), "Foreign Address".rpad(22), "State".rpad(16)]
	out.append(head + "PID" if o.has("-o") else head.rstrip(" "))
	for s in sockets:
		if s["proto"] == "udp" and not all:
			continue
		var tcp: bool = s["proto"] == "tcp"
		var state: String = ""
		if tcp:
			state = "LISTENING" if s["listening"] else s["state"]
		var remote := "0.0.0.0:0" if s["listening"] else "%s:%s" % [s["remote_ip"], s["remote_port"]]
		if not tcp:
			remote = "*:*"
		var row := "  %s %s %s %s" % [(s["proto"] as String).to_upper().rpad(6), ("%s:%d" % [s["local_ip"], s["local_port"]]).rpad(22), remote.rpad(22), state.rpad(16)]
		out.append((row + str(s["pid"])) if o.has("-o") else row.rstrip(" "))
	out.append("")
	return done(out)
