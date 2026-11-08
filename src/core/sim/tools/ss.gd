class_name SimSs
extends SimTool
## ss in the layout of iproute2 (checked against ss from iproute2 7.0.0,
## captured on a controlled set of sockets; see tests/golden). It lists the
## learner's own workstation: its listening ports and open connections. Without
## -t or -u both are listed and a Netid column appears; without -n ports are
## shown by name; -p shows the process of sockets the learner owns.

const SPEC := {"-t": false, "-u": false, "-l": false, "-a": false, "-n": false, "-p": false}


func tool_name() -> String:
	return "ss"


func run(argv: Array, ctx: SimContext, _stdin: Array) -> Dictionary:
	var p := parse_flags(argv, SPEC)
	if p["bad"] != "":
		return unsupported("ss", p["bad"])
	if not (p["args"] as Array).is_empty():
		return done(["ss: filter expressions are not supported in this simulator"], 2)
	var o: Dictionary = p["opts"]
	var protos: Array = []
	if o.has("-t") or not o.has("-u"):
		protos.append("tcp")
	if o.has("-u") or not o.has("-t"):
		protos.append("udp")
	var netid := protos.size() == 2
	var listening := o.has("-l") or o.has("-a")
	var established := o.has("-a") or not o.has("-l")
	var sockets := SimSockets.rows(ctx.lab, protos, listening, established)
	sockets.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["proto"] == "udp" and b["proto"] == "tcp")  # udp first, otherwise the lab's order

	var names: bool = not o.has("-n")
	var cells: Array = []
	for s in sockets:
		cells.append({
			"netid": s["proto"],
			"state": _state(s),
			"recvq": "0", "sendq": str(s["backlog"]),
			"laddr": s["local_ip"], "lport": _port(s["local_port"], s["proto"], names),
			"paddr": s["remote_ip"], "pport": _port_text(s["remote_port"], s["proto"], names),
			"process": _users_text(ctx.lab, s) if o.has("-p") else "",
		})
	var w := {"netid": 5, "state": 5, "recvq": 6, "sendq": 6, "laddr": 13, "lport": 4, "paddr": 12, "pport": 4}
	for c in cells:
		for k in w:
			w[k] = maxi(w[k], (c[k] as String).length())
	var header := {"netid": "Netid", "state": "State", "recvq": "Recv-Q", "sendq": "Send-Q",
			"laddr": "Local Address", "lport": "Port", "paddr": "Peer Address", "pport": "Port"}
	var out: Array = [_line(header, w, netid, o.has("-p"), true)]
	for c in cells:
		out.append(_line(c, w, netid, o.has("-p"), false))
	return done(out)


static func _state(s: Dictionary) -> String:
	if s["listening"]:
		return "LISTEN" if s["proto"] == "tcp" else "UNCONN"
	return "ESTAB" if s["state"] == "ESTABLISHED" else (s["state"] as String).replace("_", "-")


static func _port(port: int, proto: String, names: bool) -> String:
	if not names:
		return str(port)
	var n := SimServices.system_name(port, proto)
	return n if n != "" else str(port)


static func _port_text(port: Variant, proto: String, names: bool) -> String:
	return "*" if str(port) == "*" else _port(int(port), proto, names)


static func _users_text(lab: SimLab, s: Dictionary) -> String:
	if not SimSockets.visible(lab, s):
		return ""
	return "users:((\"%s\",pid=%d,fd=%d))" % [s["process"], s["pid"], s["fd"]]


## One row or the header. The address is right-aligned and the port left-aligned
## in their halves of a column; the header of the Process column follows the
## last port without a space, as the real one does.
static func _line(c: Dictionary, w: Dictionary, netid: bool, with_process: bool, is_header: bool) -> String:
	var line := ""
	if netid:
		line += (c["netid"] as String).rpad(w["netid"]) + " "
	line += (c["state"] as String).rpad(w["state"]) + " "
	line += (c["recvq"] as String).rpad(w["recvq"]) + " "
	line += (c["sendq"] as String).rpad(w["sendq"]) + " "
	line += (c["laddr"] as String).lpad(w["laddr"]) + ":" + (c["lport"] as String).rpad(w["lport"]) + " "
	line += (c["paddr"] as String).lpad(w["paddr"]) + ":"
	if not with_process:
		return line + c["pport"]  # the last column is not padded
	line += (c["pport"] as String).rpad(w["pport"])
	return line + ("Process" if is_header else " " + c["process"])
