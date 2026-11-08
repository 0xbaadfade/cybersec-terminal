class_name SimDns
extends RefCounted
## What the lab's name server answers, in the way BIND does (checked against a real
## named 9.20.30, see tests/golden/dig_*.txt). It is authoritative for the lab
## domain and the reverse zone of the lab network, and fails every other name
## with SERVFAIL: it recurses, but has no upstream in a closed lab.

const TYPES: Array = ["A", "AAAA", "CNAME", "MX", "NS", "PTR", "SOA", "TXT"]


## {"status": NOERROR|NXDOMAIN|SERVFAIL, "aa": bool, "answer": [rr], "authority": [rr],
## "additional": [rr]} where rr = {name, type, value, ttl} (see SimLab.records_at).
## `qname` is lower case without the final dot.
static func query(lab: SimLab, qname: String, qtype: String) -> Dictionary:
	var zone := lab.zone_of(qname)
	if zone == "":
		return {"status": "SERVFAIL", "aa": false, "answer": [], "authority": [], "additional": []}
	var answer: Array = []
	var cur := qname
	var found := false
	var exists := false
	for _hop in 8:
		var here := lab.records_at(cur)
		exists = not here.is_empty()
		var cname := _of_type(here, "CNAME")
		if qtype != "CNAME" and not cname.is_empty():
			answer.append(cname[0])
			cur = cname[0]["value"]  # the lab only allows CNAME targets the zone knows
			continue
		var matching := _of_type(here, qtype)
		if not matching.is_empty():
			answer.append_array(matching)
			found = true
		break
	var authority: Array = []
	var status := "NOERROR"
	if not found:
		if not exists:
			status = "NXDOMAIN"
		var apex := lab.zone_of(cur)
		var soa := _of_type(lab.records_at(apex), "SOA")
		if not soa.is_empty():
			var neg: Dictionary = (soa[0] as Dictionary).duplicate()
			neg["ttl"] = int(lab.soa()["minimum"])
			authority.append(neg)
	return {"status": status, "aa": true, "answer": answer, "authority": authority,
			"additional": _glue(lab, answer)}


static func _of_type(records: Array, type: String) -> Array:
	return records.filter(func(r): return r["type"] == type)


## The A records of the hosts named by MX and NS answers, as BIND adds them.
static func _glue(lab: SimLab, answer: Array) -> Array:
	var out: Array = []
	for r in answer:
		if r["type"] != "MX" and r["type"] != "NS":
			continue
		var target: String = (r["value"] as String).split(" ")[-1]
		for a in _of_type(lab.records_at(target), "A"):
			if not out.has(a):
				out.append(a)
	return out


## A record's data as dig prints it: names get a final dot, text is quoted.
static func rdata(r: Dictionary) -> String:
	var v: String = r["value"]
	match r["type"]:
		"CNAME", "NS", "PTR":
			return v + "."
		"MX":
			var parts := v.split(" ")
			return "%s %s." % [parts[0], parts[1]]
		"TXT":
			return "\"%s\"" % v
		"SOA":
			var f := v.split(" ")
			return "%s. %s. %s %s %s %s %s" % [f[0], f[1], f[2], f[3], f[4], f[5], f[6]]
	return v


## Bytes of a DNS message holding these sections plus dig's EDNS record with a
## server cookie, which is what dig prints as "MSG SIZE rcvd". Names are
## compressed against everything already written, as BIND does. `qname` is the
## name as typed: BIND does not compress against a question in another case.
static func message_size(qname: String, answer: Array, authority: Array, additional: Array) -> int:
	var seen: Dictionary = {}
	var size := 12 + _name_size(qname, seen) + 4
	for r in answer + authority + additional:
		size += _name_size(r["name"], seen) + 10 + _rdata_size(r, seen)
	return size + 11 + 28


static func _name_size(name: String, seen: Dictionary) -> int:
	var labels := name.split(".", false)
	var size := 0
	for i in labels.size():
		var suffix := ".".join(labels.slice(i))
		if seen.has(suffix):
			return size + 2
		size += 1 + (labels[i] as String).length()
		seen[suffix] = true
	return size + 1


static func _rdata_size(r: Dictionary, seen: Dictionary) -> int:
	var v: String = r["value"]
	match r["type"]:
		"A":
			return 4
		"CNAME", "NS", "PTR":
			return _name_size(v, seen)
		"MX":
			return 2 + _name_size(v.split(" ")[1], seen)
		"TXT":
			return 1 + v.to_utf8_buffer().size()
		"SOA":
			var f := v.split(" ")
			return _name_size(f[0], seen) + _name_size(f[1], seen) + 20
	return 4
