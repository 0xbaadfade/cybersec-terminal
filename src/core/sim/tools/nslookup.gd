class_name SimNslookup
extends SimTool
## nslookup, in the shape of BIND 9.20.30's, one question per command (no
## interactive mode). Checked against a real nslookup talking to a real named,
## see tests/golden/nslookup_*.txt. Like the real one it adds the search domain to
## a name with no dot.


func tool_name() -> String:
	return "nslookup"


func run(argv: Array, ctx: SimContext, _stdin: Array) -> Dictionary:
	var lab := ctx.lab
	var qtype := ""
	var args: Array = []
	for tok in argv:
		var t: String = tok
		if t.begins_with("-type=") or t.begins_with("-q=") or t.begins_with("-querytype="):
			qtype = t.get_slice("=", 1).to_upper()
		elif t.begins_with("-") and t.length() > 1:
			return unsupported("nslookup", t.get_slice("=", 0))
		else:
			args.append(t)
	if args.is_empty():
		return done(["nslookup: interactive mode is not supported in this simulator; give a name, e.g. nslookup web-03"], 1)
	if args.size() > 2:
		return done(["nslookup: too many arguments"], 1)
	if qtype != "" and not SimDig.TYPE_WORDS.has(qtype):
		return done(["nslookup: query type %s is not supported in this simulator" % qtype], 1)

	var server: String = lab.network.get("dns", "")
	if args.size() == 2:
		server = args[1]
		if SimNet.parse_ip(server) < 0:
			return done(["nslookup: the server must be an address in this simulator"], 1)
	var host: String = args[0]
	var reverse := SimNet.parse_ip(host) >= 0
	var qname := SimLab.reverse_name(host) if reverse else host.to_lower().trim_suffix(".")
	if reverse and qtype == "":
		qtype = "PTR"
	if qtype == "":
		qtype = "A"

	var dns_host := lab.dns_host()
	if dns_host.is_empty() or dns_host["ip"] != server:
		var how := "connection refused" if not lab.host_at(server).is_empty() else "timed out"
		var out: Array = []
		for _n in 3:
			out.append(";; communications error to %s#53: %s" % [server, how])
		out.append(";; no servers could be reached")
		out.append("")
		return done(out, 1)

	# The search domain is tried first for a name without a dot, then the name itself.
	var res := SimDns.query(lab, qname, qtype)
	var shown := qname
	var domain := lab.domain()
	if not reverse and not qname.contains(".") and domain != "":
		var searched := SimDns.query(lab, "%s.%s" % [qname, domain], qtype)
		if searched["status"] == "NOERROR" and not (searched["answer"] as Array).is_empty():
			res = searched
			shown = "%s.%s" % [qname, domain]
	var rows: Array = []
	if res["status"] == "SERVFAIL":
		rows.append(";; Got SERVFAIL reply from %s" % server)
	if not reverse:
		rows.append_array(["Server:\t\t%s" % server, "Address:\t%s#53" % server, ""])
	if res["status"] != "NOERROR":
		rows.append("** server can't find %s: %s" % [qname if reverse else _typed(host), res["status"]])
		rows.append("")
		return done(rows, 1)
	if (res["answer"] as Array).is_empty():
		rows.append("*** Can't find %s: No answer" % _typed(host))
		rows.append("")
		return done(rows, 1)
	for r in res["answer"]:
		rows.append_array(_lines(r))
	rows.append("")
	return done(rows)


## What the user typed, without a final dot (the name in an error message).
static func _typed(host: String) -> String:
	return host.trim_suffix(".")


static func _lines(r: Dictionary) -> Array:
	var owner: String = r["name"]
	var v: String = r["value"]
	match r["type"]:
		"A":
			return ["Name:\t%s" % owner, "Address: %s" % v]
		"CNAME":
			return ["%s\tcanonical name = %s." % [owner, v]]
		"PTR":
			return ["%s\tname = %s." % [owner, v]]
		"MX":
			var parts := v.split(" ")
			return ["%s\tmail exchanger = %s %s." % [owner, parts[0], parts[1]]]
		"NS":
			return ["%s\tnameserver = %s." % [owner, v]]
		"TXT":
			return ["%s\ttext = \"%s\"" % [owner, v]]
		"SOA":
			var f := v.split(" ")
			return [owner, "\torigin = %s" % f[0], "\tmail addr = %s" % f[1], "\tserial = %s" % f[2],
					"\trefresh = %s" % f[3], "\tretry = %s" % f[4], "\texpire = %s" % f[5], "\tminimum = %s" % f[6]]
	return []
