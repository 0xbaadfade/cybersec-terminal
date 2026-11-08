class_name SimNetstat
extends SimTool
## netstat in the layout of net-tools (checked against net-tools 2.10 captured
## on a controlled set of sockets; see tests/golden). It lists the learner's own
## workstation. Without -t and -u the empty UNIX-socket section follows, as it
## does on a machine with none. Without -n it resolves names: 127.0.0.1 becomes
## localhost and ports get names from the simulator's table, which can differ
## from a real system's /etc/services.

const SPEC := {"-t": false, "-u": false, "-l": false, "-a": false, "-n": false, "-p": false}
const UNIX_HEADER := "Proto RefCnt Flags       Type       State         I-Node   Path"


func tool_name() -> String:
	return "netstat"


func run(argv: Array, ctx: SimContext, _stdin: Array) -> Dictionary:
	var p := parse_flags(argv, SPEC)
	if p["bad"] != "":
		return unsupported("netstat", p["bad"])
	if not (p["args"] as Array).is_empty():
		return done(["netstat: no arguments are supported in this simulator"], 2)
	var o: Dictionary = p["opts"]
	var protos: Array = []
	if o.has("-t") or not o.has("-u"):
		protos.append("tcp")
	if o.has("-u") or not o.has("-t"):
		protos.append("udp")
	var with_unix := not o.has("-t") and not o.has("-u")
	var scope := "servers and established" if o.has("-a") else ("only servers" if o.has("-l") else "w/o servers")
	var sockets := SimSockets.rows(ctx.lab, protos, o.has("-a") or o.has("-l"), o.has("-a") or not o.has("-l"))
	sockets.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["proto"] == "tcp" and b["proto"] == "udp")  # tcp first, otherwise the lab's order

	var out: Array = []
	if o.has("-p"):
		out.append("(Not all processes could be identified, non-owned process info")
		out.append(" will not be shown, you would have to be root to see it all.)")
	out.append("Active Internet connections (%s)" % scope)
	var head := "Proto Recv-Q Send-Q %s %s %s" % ["Local Address".rpad(23), "Foreign Address".rpad(23), "State".rpad(11)]
	out.append(head + (" " + "PID/Program name".rpad(20) if o.has("-p") else ""))
	var names: bool = not o.has("-n")
	for s in sockets:
		var row := "%s %6d %6d %s %s %s" % [(s["proto"] as String).rpad(5), 0, 0,
				_address(ctx.lab, s["local_ip"], str(s["local_port"]), s["proto"], names).rpad(23),
				_address(ctx.lab, s["remote_ip"], str(s["remote_port"]), s["proto"], names).rpad(23),
				(s["state"] as String).rpad(11)]
		if o.has("-p"):
			row += " " + (("%d/%s" % [s["pid"], s["process"]]) if SimSockets.visible(ctx.lab, s) else "-").rpad(20)
		out.append(row)
	if with_unix:
		out.append("Active UNIX domain sockets (%s)" % scope)
		out.append(UNIX_HEADER)
	return done(out)


## "ip:port", with names when resolving; a name longer than the column is cut.
static func _address(lab: SimLab, ip: String, port: String, proto: String, names: bool) -> String:
	var host := ip
	var shown := port
	if names:
		if ip == "127.0.0.1":
			host = "localhost"
		elif ip != "0.0.0.0":
			var n := lab.reverse(ip)
			host = n if n != "" else ip
		if port != "*":
			var service := SimServices.system_name(int(port), proto)
			shown = service if service != "" else port
	var text := "%s:%s" % [host, shown]
	return text.substr(0, 23)
