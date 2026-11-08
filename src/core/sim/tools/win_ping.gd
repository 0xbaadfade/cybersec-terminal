class_name SimWinPing
extends SimTool
## ping as Windows prints it. UNVERIFIED: there is no Windows machine to capture
## on, so the layout is written from Microsoft's documented output (README "Phase
## 4c-2 as built"). Hosts answer with their own TTL; an unreachable on-link address
## is reported as `Destination host unreachable` and, as on Windows, counted as received.

const SPEC := {"-n": true, "-l": true, "-w": true, "-4": false}


func tool_name() -> String:
	return "ping"


func run(argv: Array, ctx: SimContext, _stdin: Array) -> Dictionary:
	var p := parse_flags(SimWinTools.dash_options(argv), SPEC)
	if p["bad"] != "":
		return unsupported("ping", p["bad"])
	if p["missing"] != "":
		return done(["Value must be supplied for option %s." % p["missing"]], 1)
	var o: Dictionary = p["opts"]
	var args: Array = p["args"]
	if args.is_empty():
		return done(["IP address must be specified."], 1)
	if args.size() > 1:
		return done(["ping: only one destination is supported in this simulator"], 1)
	var count := 4
	if o.has("-n"):
		if not (o["-n"] as String).is_valid_int() or int(o["-n"]) < 1:
			return done(["Bad value for option -n, valid range is from 1 to 4294967295."], 1)
		count = int(o["-n"])
	var size := 32
	if o.has("-l"):
		if not (o["-l"] as String).is_valid_int() or int(o["-l"]) < 0 or int(o["-l"]) > 65500:
			return done(["Bad value for option -l, valid range is from 0 to 65500."], 1)
		size = int(o["-l"])
	if o.has("-w") and (not (o["-w"] as String).is_valid_int() or int(o["-w"]) < 1):
		return done(["Bad value for option -w, valid range is from 1 to 4294967295."], 1)

	var target: String = args[0]
	var ip := target
	if SimNet.parse_ip(target) < 0:
		ip = ctx.lab.resolve(target)
		if ip == "":
			return done(["Ping request could not find host %s. Please check the name and try again." % target], 1)
	var host := ctx.lab.host_at(ip)
	var label := ip
	if SimNet.parse_ip(target) < 0:
		label = "%s [%s]" % [ctx.lab.fqdn(host) if not host.is_empty() else target, ip]
	var out: Array = ["", "Pinging %s with %d bytes of data:" % [label, size]]
	var reachable: bool = not host.is_empty() and host["icmp"]
	var on_link := SimNet.in_cidr(SimNet.parse_ip(ip), ctx.lab.cidr())
	var times: Array = []
	var unreachable := host.is_empty() and on_link
	for i in count:
		if reachable:
			var ms := int(SimPing._rtt(host, i, ctx.rng))  # the API reports whole milliseconds, truncated
			times.append(ms)
			var shown := "time<1ms" if ms < 1 else "time=%dms" % ms
			out.append("Reply from %s: bytes=%d %s TTL=%d" % [ip, size, shown, SimPing._ttl(host)])
		elif unreachable:
			out.append("Reply from %s: Destination host unreachable." % ctx.lab.you["ip"])
		else:
			out.append("Request timed out.")
	var received := count if unreachable else times.size()
	out.append("")
	out.append("Ping statistics for %s:" % ip)
	out.append("    Packets: Sent = %d, Received = %d, Lost = %d (%d%% loss)," % [count, received, count - received, (count - received) * 100 / count])
	if not times.is_empty():
		var lo: int = times.min()
		var hi: int = times.max()
		var sum := 0
		for t in times:
			sum += int(t)
		out.append("Approximate round trip times in milli-seconds:")
		out.append("    Minimum = %dms, Maximum = %dms, Average = %dms" % [lo, hi, sum / times.size()])
	return done(out, 0 if not times.is_empty() else 1)
