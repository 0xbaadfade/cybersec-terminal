class_name SimDig
extends SimTool
## dig, in the shape of BIND 9.20.30's (checked against a real dig talking to a
## real named, see tests/golden/dig_*.txt). One query per command; the answers
## come from the lab's name server (SimDns).

const TYPE_WORDS: Array = ["A", "AAAA", "CNAME", "MX", "NS", "PTR", "SOA", "TXT"]
const VERSION := "9.20.30"


func tool_name() -> String:
	return "dig"


func run(argv: Array, ctx: SimContext, _stdin: Array) -> Dictionary:
	var lab := ctx.lab
	var server := ""
	var server_text := ""
	var name := ""
	var qtype := ""
	var reverse := ""
	var short := false
	var noall := false
	var answer_only := false
	var i := 0
	while i < argv.size():
		var tok: String = argv[i]
		i += 1
		if tok.begins_with("@"):
			server_text = tok.substr(1)
		elif tok.begins_with("+"):
			match tok:
				"+short":
					short = true
				"+noall":
					noall = true
				"+answer":
					answer_only = true
				_:
					return unsupported("dig", tok)
		elif tok == "-x" or tok == "-t":
			if i >= argv.size():
				return done(["dig: option requires an argument -- '%s'" % tok.trim_prefix("-")], 1)
			if tok == "-x":
				reverse = argv[i]
			else:
				qtype = (argv[i] as String).to_upper()
			i += 1
		elif tok.begins_with("-"):
			return unsupported("dig", tok)
		elif name == "":
			name = tok
		elif TYPE_WORDS.has(tok.to_upper()) and qtype == "":
			qtype = tok.to_upper()
		elif tok.to_upper() == "ANY":
			return done(["dig: query type ANY is not supported in this simulator"], 1)
		else:
			return done(["dig: only one query per command is supported in this simulator"], 1)

	if reverse != "":
		if reverse.contains(":"):
			return done(["dig: IPv6 addresses are not supported in this simulator"], 1)
		# dig -x reverses the dotted labels of whatever it is given (a partial address
		# such as 1.2.3 and even a word are turned into a query without complaint).
		var parts := reverse.split(".")
		parts.reverse()
		name = ".".join(parts) + ".in-addr.arpa"
		if qtype == "":
			qtype = "PTR"
	if name == "":
		return done(["dig: a name to look up is required in this simulator (dig -h lists the real options)"], 1)
	if qtype == "":
		qtype = "A"
	if not TYPE_WORDS.has(qtype):
		return done(["dig: query type %s is not supported in this simulator" % qtype], 1)

	# Which server answers, and how it appears on the SERVER line.
	var shown := ""
	if server_text == "":
		server = lab.network.get("dns", "")
		shown = server
	elif SimNet.parse_ip(server_text) >= 0:
		server = server_text
		shown = server_text
	else:
		server = lab.resolve(server_text)
		if server == "":
			return done(["dig: couldn't get address for '%s': not found" % server_text], 9)
		shown = server_text
	var typed := " ".join(argv)
	var dns_host := lab.dns_host()
	var serves: bool = not dns_host.is_empty() and dns_host["ip"] == server
	if not serves:
		# A host that exists but runs no name server refuses at once; an address
		# nobody answers for is tried three times and times out.
		var refuses := server != "" and not lab.host_at(server).is_empty()
		var errors: Array = []
		for _n in 3:
			errors.append(";; communications error to %s#53: %s" % [server, "connection refused" if refuses else "timed out"])
		return _unreachable(errors, typed, server_text != "")

	var qname := name.to_lower().trim_suffix(".")
	var res := SimDns.query(lab, qname, qtype)
	if short:
		var lines: Array = []
		if res["status"] == "NOERROR":
			for r in res["answer"]:
				lines.append(SimDns.rdata(r))
		return done(lines)

	var qdisplay := name if name.ends_with(".") else name + "."
	var rows: Array = []
	if not noall:
		rows = _banner(typed, ctx, res, qdisplay, qtype, qname, server_text != "")
	if not noall or answer_only:
		for r in res["answer"]:
			rows.append(_rr_line(r))
	if noall:
		return done(rows)
	var sections: Array = [["AUTHORITY", res["authority"]], ["ADDITIONAL", res["additional"]]]
	for sec in sections:
		if not (sec[1] as Array).is_empty():
			rows.append("")
			rows.append(";; %s SECTION:" % sec[0])
			for r in sec[1]:
				rows.append(_rr_line(r))
	rows.append("")
	rows.append(";; Query time: %d msec" % ctx.rng.randi_range(0, 2))
	rows.append(";; SERVER: %s#53(%s) (UDP)" % [server, shown])
	rows.append(";; WHEN: %s" % SimNet.dig_date(ctx.now))
	rows.append(";; MSG SIZE  rcvd: %d" % SimDns.message_size(name.trim_suffix("."), res["answer"], res["authority"], res["additional"]))
	rows.append("")
	return done(rows)


## Everything up to and including the ANSWER SECTION header.
func _banner(typed: String, ctx: SimContext, res: Dictionary, qdisplay: String, qtype: String, qname: String,
		with_server: bool) -> Array:
	var rows: Array = ["", "; <<>> DiG %s <<>> %s" % [VERSION, typed]]
	if with_server:
		rows.append("; (1 server found)")
	rows.append_array([";; global options: +cmd", ";; Got answer:"])
	if qname.ends_with(".local") or qname == "local":
		rows.append(";; WARNING: .local is reserved for Multicast DNS")
		rows.append(";; You are currently testing what happens when an mDNS query is leaked to DNS")
	var flags := "qr aa rd ra" if res["aa"] else "qr rd ra"
	rows.append(";; ->>HEADER<<- opcode: QUERY, status: %s, id: %d" % [res["status"], ctx.rng.randi_range(1, 65535)])
	rows.append(";; flags: %s; QUERY: 1, ANSWER: %d, AUTHORITY: %d, ADDITIONAL: %d" % [flags, res["answer"].size(),
			res["authority"].size(), res["additional"].size() + 1])
	rows.append("")
	rows.append(";; OPT PSEUDOSECTION:")
	rows.append("; EDNS: version: 0, flags:; udp: 1232")
	rows.append("; COOKIE: %s (good)" % _cookie(ctx.rng))
	rows.append(";; QUESTION SECTION:")
	rows.append(";%s%sIN\t%s" % [qdisplay, _tabs(qdisplay.length(), 32), qtype])
	if not (res["answer"] as Array).is_empty():
		rows.append("")
		rows.append(";; ANSWER SECTION:")
	return rows


func _unreachable(errors: Array, typed: String, with_server: bool) -> Dictionary:
	var out: Array = errors.duplicate()
	out.append("")
	out.append("; <<>> DiG %s <<>> %s" % [VERSION, typed])
	if with_server:
		out.append("; (1 server found)")
	out.append(";; global options: +cmd")
	out.append(";; no servers could be reached")
	return done(out, 9)


static func _cookie(rng: RandomNumberGenerator) -> String:
	var s := ""
	for _n in 24:
		s += "%02x" % rng.randi_range(0, 255)
	return s


## The tabs dig puts after a name to reach column `width` (a tab goes to the next
## multiple of 8).
static func _tabs(name_length: int, width: int) -> String:
	return "\t".repeat(maxi(1, int(ceil(float(width - name_length) / 8.0))))


static func _rr_line(r: Dictionary) -> String:
	var owner: String = r["name"] + "."
	var lead := " " if owner.length() >= 24 else _tabs(owner.length(), 24)
	return "%s%s%d\tIN\t%s\t%s" % [owner, lead, r["ttl"], r["type"], SimDns.rdata(r)]
