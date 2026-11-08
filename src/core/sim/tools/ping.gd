class_name SimPing
extends SimTool
## ping, in the shape of Linux iputils (checked against iputils 20250605
## captured on localhost; see tests/golden). Without -c it sends 4 and prints
## ^C before the statistics, as a real session looks after Ctrl-C.

const SPEC := {"-c": true, "-i": true, "-W": true, "-s": true, "-n": false, "-q": false, "-4": false}
const DEFAULT_COUNT := 4
const MAX_COUNT := 9223372036854775807


func tool_name() -> String:
	return "ping"


func run(argv: Array, ctx: SimContext, _stdin: Array) -> Dictionary:
	var p := parse_flags(argv, SPEC)
	if p["bad"] != "":
		return unsupported("ping", p["bad"])
	if p["missing"] != "":
		return done(["ping: option requires an argument -- '%s'" % (p["missing"] as String).trim_prefix("-")], 2)
	var opts: Dictionary = p["opts"]
	var args: Array = p["args"]
	if args.is_empty():
		return done(["ping: usage error: Destination address required"], 2)
	if args.size() > 1:
		return done(["ping: only one destination is supported in this simulator"], 2)

	var count := DEFAULT_COUNT
	if opts.has("-c"):
		var text: String = opts["-c"]
		if not text.is_valid_int():
			return done(["ping: invalid argument: '%s'" % text], 2)
		count = int(text)
		if count < 1:
			return done(["ping: invalid argument: '%s': out of range: 1 <= value <= %d" % [text, MAX_COUNT]], 2)
	var interval := 1.0
	if opts.has("-i"):
		if not (opts["-i"] as String).is_valid_float() or float(opts["-i"]) < 0.0:
			return done(["ping: invalid argument: '%s'" % opts["-i"]], 2)
		interval = float(opts["-i"])
	if opts.has("-W") and (not (opts["-W"] as String).is_valid_float() or float(opts["-W"]) < 0.0):
		return done(["ping: invalid argument: '%s'" % opts["-W"]], 2)
	var size := 56
	if opts.has("-s"):
		var s_text: String = opts["-s"]
		if not s_text.is_valid_int() or int(s_text) < 0 or int(s_text) > 65507:
			return done(["ping: invalid argument: '%s': out of range: 0 <= value <= 65507" % s_text], 2)
		size = int(s_text)

	var target: String = args[0]
	var by_name := SimNet.parse_ip(target) < 0
	var ip := target
	if by_name:
		ip = ctx.lab.resolve(target)
		if ip == "":
			return done(["ping: %s: Name or service not known" % target], 2)
	var host := ctx.lab.host_at(ip)
	var label := ip
	if by_name:
		label = ctx.lab.fqdn(host) if not host.is_empty() else target
	var show_name := by_name and not opts.has("-n") and not host.is_empty()

	var out: Array = ["PING %s (%s) %d(%d) bytes of data." % [label, ip, size, size + 28]]
	var interval_ms := int(round(interval * 1000.0))
	var elapsed := 0 if count == 1 else (count - 1) * interval_ms + ctx.rng.randi_range(0, 45)
	var ctrl_c := not opts.has("-c")
	var replies: Array = []
	var errors := 0
	var reachable: bool = not host.is_empty() and host["icmp"]
	var on_link := SimNet.in_cidr(SimNet.parse_ip(ip), ctx.lab.cidr())
	if reachable:
		var from := "%s (%s)" % [ctx.lab.fqdn(host), ip] if show_name else ip
		for i in count:
			var t := _rtt(host, i, ctx.rng)
			replies.append(t)
			if not opts.has("-q"):
				out.append("%d bytes from %s: icmp_seq=%d ttl=%d time=%s ms" % [size + 8, from, i + 1, _ttl(host), _fmt_time(t)])
	elif host.is_empty() and on_link:
		errors = count
		for i in count:
			out.append("From %s icmp_seq=%d Destination Host Unreachable" % [ctx.lab.you["ip"], i + 1])
	out.append("^C" if ctrl_c else "")
	out.append("--- %s ping statistics ---" % label)
	var received := replies.size()
	var summary := "%d packets transmitted, %d received, " % [count, received]
	if errors > 0:
		summary += "+%d errors, " % errors
	summary += "%d%% packet loss, time %dms" % [(count - received) * 100 / count, elapsed]
	out.append(summary)
	if received > 0:
		out.append(_rtt_line(replies))
	elif errors > 0:
		out.append("pipe %d" % count)
	else:
		out.append("")
	return done(out, 0 if received > 0 else (2 if errors > 0 else 1))


static func _ttl(host: Dictionary) -> int:
	return {"linux": 64, "windows": 128, "network": 255}.get(host["os"], 64)


## Base latency with a little deterministic jitter; the first reply of a remote
## host is slower (it pays for address resolution).
static func _rtt(host: Dictionary, index: int, rng: RandomNumberGenerator) -> float:
	var t: float = host["latency_ms"] * (1.0 + rng.randf_range(-0.15, 0.15))
	if index == 0 and not host.get("is_you", false):
		t *= 1.0 + rng.randf_range(0.2, 0.7)
	return t


## Three significant figures, as iputils prints them.
static func _fmt_time(t: float) -> String:
	if t < 1.0:
		return "%.3f" % t
	if t < 10.0:
		return "%.2f" % t
	if t < 100.0:
		return "%.1f" % t
	return "%.0f" % t


static func _rtt_line(times: Array) -> String:
	var lo: float = times[0]
	var hi: float = times[0]
	var sum := 0.0
	for t in times:
		lo = minf(lo, t)
		hi = maxf(hi, t)
		sum += t
	var avg := sum / times.size()
	var var_sum := 0.0
	for t in times:
		var_sum += (t - avg) * (t - avg)
	return "rtt min/avg/max/mdev = %.3f/%.3f/%.3f/%.3f ms" % [lo, avg, hi, sqrt(var_sum / times.size())]
