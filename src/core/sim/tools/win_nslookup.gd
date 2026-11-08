class_name SimWinNslookup
extends SimTool
## nslookup as Windows prints it (a different layout from BIND's): the server is
## shown by its reverse name, answers are `Name:` / `Address:` pairs. UNVERIFIED:
## written from Microsoft's documented output, not captured (README "Phase 4c-2
## as built"). One question per command; no interactive mode.


func tool_name() -> String:
	return "nslookup"


func run(argv: Array, ctx: SimContext, _stdin: Array) -> Dictionary:
	var lab := ctx.lab
	var qtype := ""
	var args: Array = []
	for tok in argv:
		var t: String = tok
		if t.to_lower().begins_with("-type=") or t.to_lower().begins_with("-q="):
			qtype = t.get_slice("=", 1).to_upper()
		elif t.begins_with("-") and t.length() > 1:
			return unsupported("nslookup", t.get_slice("=", 0))
		else:
			args.append(t)
	if args.is_empty():
		return done(["nslookup: interactive mode is not supported in this simulator; give a name, e.g. nslookup fs-01"], 1)
	if args.size() > 2:
		return done(["nslookup: too many arguments"], 1)
	if qtype != "" and not SimDig.TYPE_WORDS.has(qtype):
		return done(["nslookup: query type %s is not supported in this simulator" % qtype], 1)
	var server: String = lab.network.get("dns", "")
	if args.size() == 2:
		server = args[1]
		if SimNet.parse_ip(server) < 0:
			return done(["nslookup: the server must be an address in this simulator"], 1)
	var server_name := lab.reverse(server)
	if server_name == "":
		server_name = "UnKnown"
	var head: Array = ["Server:  %s" % server_name, "Address:  %s" % server, ""]

	var dns_host := lab.dns_host()
	if dns_host.is_empty() or dns_host["ip"] != server:
		var out: Array = head.slice(0, 2) + [""]
		for _n in 2:
			out.append("DNS request timed out.")
			out.append("    timeout was 2 seconds.")
		out.append("*** Request to %s timed-out" % server_name)
		return done(out, 1)

	var host: String = args[0]
	var reverse := SimNet.parse_ip(host) >= 0
	var qname := SimLab.reverse_name(host) if reverse else host.to_lower().trim_suffix(".")
	if reverse and qtype == "":
		qtype = "PTR"
	if qtype == "":
		qtype = "A"
	var res := SimDns.query(lab, qname, qtype)
	var domain := lab.domain()
	var shown := qname
	if not reverse and not qname.contains(".") and domain != "":
		var searched := SimDns.query(lab, "%s.%s" % [qname, domain], qtype)
		if searched["status"] == "NOERROR" and not (searched["answer"] as Array).is_empty():
			res = searched
			shown = "%s.%s" % [qname, domain]
	var typed := host if not reverse else host
	if res["status"] != "NOERROR":
		var why: String = {"NXDOMAIN": "Non-existent domain", "SERVFAIL": "Server failed"}.get(res["status"], res["status"])
		return done(head + ["*** %s can't find %s: %s" % [server_name, typed, why], ""], 1)
	if (res["answer"] as Array).is_empty():
		return done(head + ["*** No %s (%s) records available for %s" % [_record_label(qtype), qtype, typed], ""], 1)
	var out2: Array = head.duplicate()
	var aliases: Array = []
	for r in res["answer"]:
		if r["type"] == "CNAME":
			aliases.append(r["name"])
	var addresses: Array = res["answer"].filter(func(r): return r["type"] == "A")
	if qtype == "A" or qtype == "AAAA" or qtype == "CNAME":
		if addresses.is_empty():
			return done(head + ["*** No A (%s) records available for %s" % [_record_label("A"), typed], ""], 1)
		out2.append("Name:    %s" % addresses[0]["name"])
		out2.append("Address:  %s" % addresses[0]["value"] if addresses.size() == 1 else "Addresses:  " + "\n          ".join(addresses.map(func(r): return r["value"])))
		if not aliases.is_empty():
			out2.append("Aliases:  %s" % ("\n          ".join(aliases)))
	elif qtype == "PTR":
		var ptr: Dictionary = res["answer"][0]
		out2.append("Name:    %s" % ptr["value"])
		out2.append("Address:  %s" % host)
	else:
		for r in res["answer"]:
			out2.append_array(_record_lines(r))
		for g in res["additional"]:
			out2.append("%s\tinternet address = %s" % [g["name"], g["value"]])
	out2.append("")
	return done(out2)


static func _record_label(qtype: String) -> String:
	return {"A": "address", "MX": "mail exchanger", "NS": "name server", "TXT": "text", "SOA": "authority"}.get(qtype, qtype.to_lower())


static func _record_lines(r: Dictionary) -> Array:
	var v: String = r["value"]
	match r["type"]:
		"MX":
			var m := v.split(" ")
			return ["%s\tMX preference = %s, mail exchanger = %s" % [r["name"], m[0], m[1]]]
		"NS":
			return ["%s\tnameserver = %s" % [r["name"], v]]
		"TXT":
			return ["%s\ttext =" % r["name"], "", "\t\"%s\"" % v]
		"SOA":
			var f := v.split(" ")
			return [r["name"], "\tprimary name server = %s" % f[0], "\tresponsible mail addr = %s" % f[1],
					"\tserial  = %s" % f[2], "\trefresh = %s (%s)" % [f[3], _span(int(f[3]))],
					"\tretry   = %s (%s)" % [f[4], _span(int(f[4]))], "\texpire  = %s (%s)" % [f[5], _span(int(f[5]))],
					"\tdefault TTL = %s (%s)" % [f[6], _span(int(f[6]))]]
	return []


## 3600 -> "1 hour", 600 -> "10 mins", 86400 -> "1 day".
static func _span(seconds: int) -> String:
	if seconds % 86400 == 0:
		return "%d day%s" % [seconds / 86400, "" if seconds == 86400 else "s"]
	if seconds % 3600 == 0:
		return "%d hour%s" % [seconds / 3600, "" if seconds == 3600 else "s"]
	if seconds % 60 == 0:
		return "%d min%s" % [seconds / 60, "" if seconds == 60 else "s"]
	return "%d secs" % seconds
