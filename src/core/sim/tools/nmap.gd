class_name SimNmap
extends SimTool
## nmap as an unprivileged user runs it: connect scans only (checked against
## nmap 7.99 captured on localhost with NMAP_UNPRIVILEGED=1; see tests/golden).
## Host discovery is a TCP probe of ports 80 and 443, so a host is "down" only
## when both are filtered. Everything is computed from the lab; nothing is sent.
##
## Supported: targets (host name, address, a.b.c.d/n with n 16 to 32, octet
## ranges like 10.20.0.1-30 or 10.20.0.*), -p, -sV, -sn, -Pn, -n, --open, -sT,
## -T0..5. Anything else is named as unsupported; the options that need root say
## so, as the real tool does for an ordinary user.

const VERSION := "7.99"
const ROOT_SCANS: Array = ["-sS", "-sA", "-sW", "-sM", "-sF", "-sN", "-sX", "-sU", "-sY", "-sZ", "-sO", "-sI"]
const IGNORE_LIMIT := 25  # more ports than this in one state are summarised
const MAX_PN_ADDRESSES := 256
const REASONS := {"closed": "conn-refused", "filtered": "no-response"}
const NOTE_DOWN := "Note: Host seems down. If it is really up, but blocking our ping probes, try -Pn"
const SERVICE_FOOTER := "Service detection performed. Please report any incorrect results at https://nmap.org/submit/ ."


func tool_name() -> String:
	return "nmap"


func run(argv: Array, ctx: SimContext, _stdin: Array) -> Dictionary:
	var o := _parse(argv)
	if o.has("bad"):
		return unsupported("nmap", o["bad"])
	if o.has("missing"):
		return done(["nmap: option requires an argument -- 'p'"], 255)
	if argv.is_empty():
		return done(["Nmap %s ( https://nmap.org )" % VERSION,
				"Usage: nmap [Scan Type(s)] [Options] {target specification}",
				"(the simulator supports a subset of the options: type tool nmap)"], 1)
	if o["root"] == "scan":
		return done(["You requested a scan type which requires root privileges.", "QUITTING!"], 1)
	if o["root"] == "fingerprint":
		return done(["TCP/IP fingerprinting (for OS scan) requires root privileges.", "QUITTING!"], 1)

	var out: Array = ["Starting Nmap %s ( https://nmap.org ) at %s" % [VERSION, _date(ctx.now)]]
	if o["sn"] and o["ports"] != null:
		out.append("You cannot use -F (fast scan) or -p (explicit port selection) when not doing a port scan")
		out.append("QUITTING!")
		return done(out, 1)
	var port_list: Array = []
	if o["ports"] != null:
		var parsed := _parse_ports(o["ports"])
		if parsed.has("error"):
			out.append(parsed["error"])
			out.append("QUITTING!")
			return done(out, 1)
		port_list = parsed["ports"]

	var targets: Array = []
	for spec in o["targets"]:
		var t := _parse_target(spec, ctx.lab)
		if t.is_empty():
			out.append("Failed to resolve \"%s\"." % spec)
		else:
			targets.append(t)
	var elapsed := 0.25 + ctx.rng.randf() * 0.25
	if targets.is_empty():
		out.append("WARNING: No targets were specified, so 0 hosts scanned.")
		out.append("Nmap done: 0 IP addresses (0 hosts up) scanned in %.2f seconds" % elapsed)
		return done(out)

	var total := 0
	var order: Array = []  # {ip, ip_int, host, name}
	var seen: Dictionary = {}
	for t in targets:
		total += t["count"]
		if o["pn"] and t["count"] > MAX_PN_ADDRESSES:
			out.append("nmap: -Pn on more than %d addresses is not supported in this simulator" % MAX_PN_ADDRESSES)
			return done(out, 1)
		for ip_int in _addresses(t, ctx.lab, o["pn"]):
			var ip := SimNet.ip_string(ip_int)
			if seen.has(ip):
				continue
			seen[ip] = true
			order.append({"ip": ip, "ip_int": ip_int, "host": ctx.lab.host_at(ip), "name": t["name"]})

	var up := 0
	var scanned_any := false
	var slow := 0.0
	for e in order:
		var host: Dictionary = e["host"]
		var alive: bool = o["pn"] or _discovered(host)
		if not alive:
			continue
		up += 1
		var label_name: String = e["name"]
		if label_name == "" and not o["n"] and not host.is_empty():
			label_name = ctx.lab.fqdn(host)
		var label: String = "%s (%s)" % [label_name, e["ip"]] if label_name != "" else e["ip"]
		if o["sn"]:
			out.append("Nmap scan report for %s" % label)
			out.append(_up_line(host, _discovered(host), ctx.rng))
			continue
		var scan := _scan_host(host, port_list, o["ports"] != null, o["open"])
		if o["open"] and scan["rows"].is_empty():
			continue  # with --open a host without open ports is not reported
		# A round-trip time exists only if something answered: with -Pn a host that
		# drops every probe is "up" without a latency.
		var answered: bool = _discovered(host) or scan["counts"]["open"] + scan["counts"]["closed"] > 0
		var up_line := _up_line(host, answered, ctx.rng)
		scanned_any = true
		if scan["any_open"]:
			slow += 6.0 + ctx.rng.randf() * 1.5 if o["sv"] else 0.0
		if scan["counts"]["filtered"] > 0:
			slow += 1.0
		out.append("Nmap scan report for %s" % label)
		out.append(up_line)
		out.append_array(_host_block(scan, label, o["sv"]))
	if o["sv"] and scanned_any:
		out.append(SERVICE_FOOTER)
	if up == 0 and total == 1 and not o["pn"]:
		out.append(NOTE_DOWN)
		slow += 2.5 + ctx.rng.randf() * 0.6
	if o["sn"]:
		elapsed += total * 0.004
	elif port_list.size() > 1000:
		elapsed += port_list.size() / 1000.0 * 0.3
	out.append("Nmap done: %d IP address%s (%d host%s up) scanned in %.2f seconds" % [
			total, "" if total == 1 else "es", up, "" if up == 1 else "s", elapsed + slow])
	return done(out)


# --- arguments ---------------------------------------------------------

## {"sn", "pn", "n", "sv", "open", "ports" (String or null), "targets", "root"},
## or "bad" / "missing" for an option the simulator does not take.
static func _parse(argv: Array) -> Dictionary:
	var o := {"sn": false, "pn": false, "n": false, "sv": false, "open": false, "ports": null,
			"targets": [], "root": ""}
	var i := 0
	while i < argv.size():
		var tok: String = argv[i]
		i += 1
		if tok == "-sn":
			o["sn"] = true
		elif tok == "-Pn":
			o["pn"] = true
		elif tok == "-n":
			o["n"] = true
		elif tok == "-sV":
			o["sv"] = true
		elif tok == "-sT":
			pass
		elif tok == "--open":
			o["open"] = true
		elif tok == "-p":
			if i >= argv.size():
				return {"missing": "-p"}
			o["ports"] = argv[i]
			i += 1
		elif tok.begins_with("-p") and tok.length() > 2:
			o["ports"] = tok.substr(2)
		elif tok.length() == 3 and tok.begins_with("-T") and tok[2] >= "0" and tok[2] <= "5":
			pass
		elif ROOT_SCANS.has(tok):
			if o["root"] == "":
				o["root"] = "scan"
		elif tok == "-O":
			if o["root"] == "":
				o["root"] = "fingerprint"
		elif tok.begins_with("-") and tok != "-":
			return {"bad": tok}
		else:
			(o["targets"] as Array).append(tok)
	return o


## {"ports": sorted Array of ints} or {"error": the tool's message}.
static func _parse_ports(spec: String) -> Dictionary:
	var ports: Dictionary = {}
	for part in spec.split(",", false):
		if part == "-":
			for p in range(1, 65536):
				ports[p] = true
			continue
		var pieces := part.split("-")
		var range_like := pieces.size() == 2 and (pieces[0] == "" or pieces[0].is_valid_int()) \
				and (pieces[1] == "" or pieces[1].is_valid_int())
		if range_like and not (pieces[0] == "" and pieces[1] == ""):
			var lo := 1 if pieces[0] == "" else int(pieces[0])
			var hi := 65535 if pieces[1] == "" else int(pieces[1])
			if lo < 0 or hi > 65535:
				return {"error": "Ports specified must be between 0 and 65535 inclusive"}
			if lo > hi:
				return {"error": "Your port specifications are illegal.  Example of proper form: \"-100,200-1024,T:3000-4000,U:60000-\""}
			for p in range(lo, hi + 1):
				ports[p] = true
		elif part.is_valid_int() and not part.begins_with("-") and not part.begins_with("+"):
			if int(part) > 65535:
				return {"error": "Ports specified must be between 0 and 65535 inclusive"}
			ports[int(part)] = true
		else:
			var named := SimServices.ports_named(part)
			if named.is_empty():
				return {"error": "Found no matches for the service mask '%s' and your specified protocols" % part}
			for p in named:
				ports[p] = true
	var sorted: Array = ports.keys()
	sorted.sort()
	return {"ports": sorted}


## A target as {"lo", "hi" (address range), "octets" (per-octet ranges or null),
## "count", "name" (the name typed, "" for an address)}, or {} when it cannot be
## resolved, which nmap reports as "Failed to resolve".
static func _parse_target(spec: String, lab: SimLab) -> Dictionary:
	if spec.contains("/"):
		var parts := spec.split("/")
		var ip := SimNet.parse_ip(parts[0]) if parts.size() == 2 else -1
		if ip < 0 or not parts[1].is_valid_int() or int(parts[1]) < 16 or int(parts[1]) > 32:
			return {}
		var prefix := int(parts[1])
		var mask := (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF
		var lo := ip & mask
		return {"lo": lo, "hi": lo | (~mask & 0xFFFFFFFF), "octets": null, "count": 1 << (32 - prefix), "name": ""}
	var ip_int := SimNet.parse_ip(spec)
	if ip_int >= 0:
		return {"lo": ip_int, "hi": ip_int, "octets": null, "count": 1, "name": ""}
	var oct_parts := spec.split(".")
	if oct_parts.size() == 4 and (spec.contains("-") or spec.contains("*")):
		var octets: Array = []
		var count := 1
		for part in oct_parts:
			var r := _octet_range(part)
			if r.is_empty():
				return _named(spec, lab)
			octets.append(r)
			count *= r[1] - r[0] + 1
		return {"lo": 0, "hi": 0, "octets": octets, "count": count, "name": ""}
	return _named(spec, lab)


static func _named(spec: String, lab: SimLab) -> Dictionary:
	var ip := lab.resolve(spec)
	if ip == "":
		return {}
	var n := SimNet.parse_ip(ip)
	return {"lo": n, "hi": n, "octets": null, "count": 1, "name": spec.to_lower().trim_suffix(".")}


static func _octet_range(part: String) -> Array:
	if part == "*":
		return [0, 255]
	if part.is_valid_int() and part.length() <= 3 and not part.begins_with("0") or part == "0":
		return [int(part), int(part)] if int(part) <= 255 else []
	var ends := part.split("-")
	if ends.size() == 2 and ends[0].is_valid_int() and ends[1].is_valid_int():
		var a := int(ends[0])
		var b := int(ends[1])
		if a >= 0 and b <= 255 and a <= b:
			return [a, b]
	return []


static func _contains(t: Dictionary, ip_int: int) -> bool:
	if t["octets"] == null:
		return ip_int >= t["lo"] and ip_int <= t["hi"]
	var shifts := [24, 16, 8, 0]
	for i in 4:
		var octet: int = (ip_int >> int(shifts[i])) & 255
		if octet < t["octets"][i][0] or octet > t["octets"][i][1]:
			return false
	return true


## The addresses to look at in a target, ascending: with -Pn every address, else
## only those a lab host has.
static func _addresses(t: Dictionary, lab: SimLab, every: bool) -> Array:
	var found: Array = []
	if every:
		if t["octets"] == null:
			for n in range(t["lo"], t["hi"] + 1):
				found.append(n)
		else:
			var o: Array = t["octets"]
			for a in range(o[0][0], o[0][1] + 1):
				for b in range(o[1][0], o[1][1] + 1):
					for c in range(o[2][0], o[2][1] + 1):
						for d in range(o[3][0], o[3][1] + 1):
							found.append((a << 24) | (b << 16) | (c << 8) | d)
		return found
	for h in lab.all_hosts():
		var n := SimNet.parse_ip(h["ip"])
		if _contains(t, n):
			found.append(n)
	found.sort()
	return found


# --- scanning ----------------------------------------------------------

## State of a TCP port on a host as the network sees it. A service bound to the
## loopback address only answers the machine itself, so it looks closed from outside.
static func _state(host: Dictionary, port: int) -> String:
	for p in host.get("ports", []):
		if p["proto"] == "tcp" and p["port"] == port:
			if host.get("is_you", false) and p["bind"] == "127.0.0.1" and p["state"] == "open":
				return "closed"
			return p["state"]
	return host.get("default_ports", "closed") if not host.is_empty() else "filtered"


## Unprivileged host discovery: a TCP probe of ports 80 and 443. Open and closed
## both answer; a host is down only when both are filtered.
static func _discovered(host: Dictionary) -> bool:
	return not host.is_empty() and (_state(host, 80) != "filtered" or _state(host, 443) != "filtered")


## What a scan of one host finds: counts per state, the rows to print, and the
## ignored (summarised) states.
static func _scan_host(host: Dictionary, port_list: Array, explicit: bool, open_only: bool) -> Dictionary:
	var n_ports := port_list.size() if explicit else SimServices.DEFAULT_SCAN_SIZE
	var wanted: Dictionary = {}
	for p in port_list:
		wanted[p] = true
	var counts := {"open": 0, "closed": 0, "filtered": 0}
	var listed: Array = []  # [port, state, service, version] for the lab's own entries
	var explicit_count := 0
	var lab_ports: Array = host.get("ports", [])
	for p in lab_ports:
		if p["proto"] != "tcp":
			continue
		var in_scan: bool = wanted.has(p["port"]) if explicit else SimServices.in_default_scan(p["port"])
		if not in_scan:
			continue
		var state := _state(host, p["port"])
		counts[state] += 1
		explicit_count += 1
		var service: String = p["service"] if p["service"] != "" else SimServices.nmap_name(p["port"])
		listed.append([p["port"], state, service, p["version"]])
	var default_state: String = host.get("default_ports", "closed") if not host.is_empty() else "filtered"
	counts[default_state] += n_ports - explicit_count

	var ignored: Array = []
	if open_only:
		for s in ["closed", "filtered"]:
			if counts[s] > 0:
				ignored.append(s)
	else:
		var top := "closed" if counts["closed"] >= counts["filtered"] else "filtered"
		if counts[top] > IGNORE_LIMIT:
			ignored.append(top)
	var rows: Array = []
	for l in listed:
		if not ignored.has(l[1]):
			rows.append(l)
	if explicit and not ignored.has(default_state):
		var seen: Dictionary = {}
		for l in listed:
			seen[l[0]] = true
		for p in port_list:
			if not seen.has(p):
				rows.append([p, default_state, SimServices.nmap_name(p), ""])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	return {"n": n_ports, "counts": counts, "rows": rows, "ignored": ignored, "any_open": counts["open"] > 0}


## The lines under "Host is up": the summary of ignored ports, the table, a blank.
static func _host_block(scan: Dictionary, label: String, with_version: bool) -> Array:
	var out: Array = []
	var not_shown := _not_shown(scan)
	if scan["rows"].is_empty():
		out.append("All %d scanned ports on %s are in ignored states." % [scan["n"], label])
		out.append(not_shown)
		out.append("")
		return out
	if not_shown != "":
		out.append(not_shown)
		if scan["ignored"].has("closed") and scan["ignored"].has("filtered"):
			out.append("Some closed ports may be reported as filtered due to --defeat-rst-ratelimit")
	else:
		out.append("")
	var port_w := 4
	var state_w := 5
	var service_w := 7
	for r in scan["rows"]:
		port_w = maxi(port_w, ("%d/tcp" % r[0]).length())
		state_w = maxi(state_w, (r[1] as String).length())
		service_w = maxi(service_w, (r[2] as String).length())
	var header := "%s %s %s" % ["PORT".rpad(port_w), "STATE".rpad(state_w), "SERVICE".rpad(service_w) if with_version else "SERVICE"]
	out.append(header + (" VERSION" if with_version else ""))
	for r in scan["rows"]:
		var line := "%s %s %s" % [("%d/tcp" % r[0]).rpad(port_w), (r[1] as String).rpad(state_w), r[2]]
		if with_version and r[1] == "open" and r[3] != "":
			line = "%s %s %s" % [("%d/tcp" % r[0]).rpad(port_w), (r[1] as String).rpad(state_w), (r[2] as String).rpad(service_w)]
			line += " " + r[3]
		out.append(line)
	out.append("")
	return out


## "Not shown: 996 closed tcp ports (conn-refused)", "" when nothing is summarised.
static func _not_shown(scan: Dictionary) -> String:
	var parts: Array = []
	var states: Array = scan["ignored"].duplicate()
	states.sort_custom(func(a: String, b: String) -> bool:
		if scan["counts"][a] != scan["counts"][b]:
			return scan["counts"][a] > scan["counts"][b]
		return a == "closed")
	for s in states:
		var n: int = scan["counts"][s]
		parts.append("%d %s tcp port%s (%s)" % [n, s, "" if n == 1 else "s", REASONS[s]])
	return "" if parts.is_empty() else "Not shown: " + ", ".join(parts)


static func _up_line(host: Dictionary, answered: bool, rng: RandomNumberGenerator) -> String:
	if host.is_empty() or not answered:
		return "Host is up."
	return "Host is up (%ss latency)." % _latency(host, rng)


## Seconds with two significant figures, as nmap prints a latency.
static func _latency(host: Dictionary, rng: RandomNumberGenerator) -> String:
	var s: float = host["latency_ms"] / 1000.0 * rng.randf_range(0.7, 1.3)
	var decimals := maxi(1, int(1 - floor(log(s) / log(10.0))))
	return ("%." + str(decimals) + "f") % s


static func _date(now: int) -> String:
	var d := Time.get_datetime_dict_from_unix_time(now)
	return "%04d-%02d-%02d %02d:%02d +0000" % [d["year"], d["month"], d["day"], d["hour"], d["minute"]]
