class_name SimLab
extends RefCounted
## A lab: a small fake network the learner pokes at (README "Phase 4 plan").
## Data in, answers out: the tool emulators compute their output from this
## model and never touch the real network. `errors` lists every problem; a lab
## with errors is not used.

const OS_NAMES: Array = ["linux", "windows", "network", "kali"]
const STATES: Array = ["open", "closed", "filtered"]
const PROTOS: Array = ["tcp", "udp"]
const MAX_HOSTS := 254
const CONNECTION_STATES: Array = ["ESTABLISHED", "TIME_WAIT", "CLOSE_WAIT", "SYN_SENT", "FIN_WAIT2"]
const RECORD_TYPES: Array = ["A", "CNAME", "MX", "NS", "TXT"]
const ZONE_TTL := 3600
const HTTP_REASONS := {100: "Continue", 200: "OK", 201: "Created", 204: "No Content", 301: "Moved Permanently",
		302: "Found", 304: "Not Modified", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden",
		404: "Not Found", 405: "Method Not Allowed", 500: "Internal Server Error", 502: "Bad Gateway",
		503: "Service Unavailable"}
## Headers the simulated web server writes itself.
const HTTP_GENERATED: Array = ["date", "content-length", "content-type", "server"]

var id := ""
var title := ""
var seed_value := 0
var you: Dictionary = {}  # {ip, name, os, user, ports}
var connections: Array = []  # the workstation's open connections (for ss, netstat)
var network: Dictionary = {}  # {cidr, gateway, dns, domain}
var hosts: Array = []  # the other hosts, normalised
var dns: Array = []  # explicit records [{name, type, value, ttl}]; host A and PTR records are implied
var files: Dictionary = {}  # host name -> {file name -> text}
var binaries: Dictionary = {}  # host name -> {binary name -> {file_output, nm, strings, relro, canary, nx, pie, functions}}
var captures: Dictionary = {}  # host name -> {capture name -> {aps, stations, frames, ...}} for airodump-ng, aircrack-ng, tshark
var errors: Array = []

var _cidr: Dictionary = {}


static func from_data(data: Variant, label: String) -> SimLab:
	var lab := SimLab.new()
	lab._load(data, label)
	return lab


func ok() -> bool:
	return errors.is_empty()


func cidr() -> Dictionary:
	return _cidr


## Every host including the learner's own machine, which answers like any other.
func all_hosts() -> Array:
	var out: Array = hosts.duplicate()
	if not you.is_empty():
		out.append({"ip": you["ip"], "name": you["name"], "os": you["os"], "latency_ms": 0.03,
				"icmp": true, "default_ports": "closed", "ports": you["ports"], "is_you": true})
	return out


func host_at(ip: String) -> Dictionary:
	for h in all_hosts():
		if h["ip"] == ip:
			return h
	return {}


func fqdn(host: Dictionary) -> String:
	var domain: String = network.get("domain", "")
	return host["name"] if domain == "" else "%s.%s" % [host["name"], domain]


## An address for a name, "" when the lab DNS does not know it. Bare host names
## resolve as if the search domain were appended, and CNAMEs are followed.
func resolve(name: String) -> String:
	var key := name.to_lower().trim_suffix(".")
	var domain: String = network.get("domain", "")
	if not key.contains(".") and domain != "":
		key = "%s.%s" % [key, domain]
	for _hop in 8:
		var next := ""
		for r in records_at(key):
			if r["type"] == "A":
				return r["value"]
			if r["type"] == "CNAME" and next == "":
				next = r["value"]
		if next == "":
			break
		key = next
	for h in all_hosts():
		if name.to_lower().trim_suffix(".") == h["name"]:
			return h["ip"]
	return ""


## The canonical name of the host at `ip`, "" when there is none.
func reverse(ip: String) -> String:
	var h := host_at(ip)
	return fqdn(h) if not h.is_empty() else ""


# --- the lab's name server ---------------------------------------------------

func domain() -> String:
	return network.get("domain", "")


## The zone for addresses of the lab network (192.168.1.0/24 -> 1.168.192.in-addr.arpa),
## as many octets as the prefix has whole bytes.
func reverse_zone() -> String:
	if _cidr.is_empty():
		return ""
	var octets := SimNet.ip_string(int(_cidr["base"])).split(".")
	var keep := clampi(int(_cidr["prefix"]) / 8, 1, 3)
	var parts: Array = []
	for i in keep:
		parts.push_front(octets[i])
	return ".".join(parts) + ".in-addr.arpa"


static func reverse_name(ip: String) -> String:
	var parts := ip.split(".")
	parts.reverse()
	return ".".join(parts) + ".in-addr.arpa"


## The host that runs the lab's name server, {} when there is none.
func dns_host() -> Dictionary:
	return host_at(network.get("dns", "")) if network.get("dns", "") != "" else {}


func soa() -> Dictionary:
	var h := dns_host()
	return {"mname": fqdn(h) if not h.is_empty() else "ns.%s" % domain(), "rname": "hostmaster.%s" % domain(),
			"serial": 2026110501, "refresh": 3600, "retry": 600, "expire": 86400, "minimum": 300}


static func _rr(name: String, type: String, value: String, ttl: int = ZONE_TTL) -> Dictionary:
	return {"name": name, "type": type, "value": value, "ttl": ttl}


## Which of the lab's two zones holds `name` ("" for neither). The lab's server is
## authoritative for them and fails every other name: it has no upstream.
func zone_of(name: String) -> String:
	var d := domain()
	if d != "" and (name == d or name.ends_with("." + d)):
		return d
	var rev := reverse_zone()
	if rev != "" and (name == rev or name.ends_with("." + rev)):
		return rev
	return ""


## Every record the lab's name server holds at `name` (lower case, no final dot):
## the explicit records, an A record per host, a PTR per address, and the apex
## NS and SOA of each zone.
func records_at(name: String) -> Array:
	var out: Array = []
	var zone := zone_of(name)
	if zone == "":
		return out
	if zone == domain():
		for r in dns:
			if r["name"] == name:
				out.append(r)
		for h in all_hosts():
			if fqdn(h) == name:
				var rr := _rr(name, "A", h["ip"])
				if not out.has(rr):
					out.append(rr)
	else:
		for h in all_hosts():
			if reverse_name(h["ip"]) == name:
				out.append(_rr(name, "PTR", fqdn(h)))
	if name == zone:
		var has_ns := false
		for r in out:
			has_ns = has_ns or r["type"] == "NS"
		var server := dns_host()
		if not has_ns and not server.is_empty():
			out.append(_rr(name, "NS", fqdn(server)))
		var z := soa()
		out.append(_rr(name, "SOA", "%s %s %d %d %d %d %d" % [z["mname"], z["rname"], z["serial"], z["refresh"],
				z["retry"], z["expire"], z["minimum"]]))
	return out


## The MAC of the workstation's network card: given in the lab or derived from
## the address, so every lab has one.
func you_mac() -> String:
	if you.get("mac", "") != "":
		return you["mac"]
	var o := SimNet.ip_string(SimNet.parse_ip(you["ip"])).split(".")
	return "52:54:00:%02x:%02x:%02x" % [int(o[1]), int(o[2]), int(o[3])]


func files_for_you() -> Dictionary:
	return files.get(you.get("name", ""), {})


## The compiled binaries the learner's own workstation carries, for the
## binary-analysis tools (file, nm, strings, readelf, objdump, checksec).
## {} for a lab that names none (every other tool ignores this field).
func binaries_for_you() -> Dictionary:
	return binaries.get(you.get("name", ""), {})


## The recorded captures the learner's own workstation carries, for the wireless
## tools (airodump-ng, aircrack-ng, tshark). {} for a lab that names none.
func captures_for_you() -> Dictionary:
	return captures.get(you.get("name", ""), {})


# --- loading -----------------------------------------------------------

static func _text(v: Variant) -> bool:
	return typeof(v) == TYPE_STRING and (v as String).strip_edges() != ""


static func _whole(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or (typeof(v) == TYPE_FLOAT and v == floorf(v))


static func _mac_ok(s: String) -> bool:
	var parts := s.split(":")
	if parts.size() != 6:
		return false
	for p in parts:
		if p.length() != 2 or not p.is_valid_hex_number(false):
			return false
	return true


static func _name_ok(s: String) -> bool:
	if s == "":
		return false
	for i in s.length():
		var ch := s[i]
		var good := (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or (ch == "-" and i > 0)
		if not good:
			return false
	return true


func _err(message: String, label: String) -> void:
	errors.append("%s: %s" % [label, message])


func _load(data: Variant, label: String) -> void:
	if typeof(data) != TYPE_DICTIONARY:
		_err("expected a JSON object", label)
		return
	id = str(data.get("id", "")) if _text(data.get("id")) else ""
	if id == "":
		_err("'id' must be a non-empty string", label)
	title = str(data.get("title", id))
	if data.has("seed"):
		if _whole(data["seed"]):
			seed_value = int(data["seed"])
		else:
			_err("'seed' must be a whole number", label)
	var net: Variant = data.get("network")
	if typeof(net) != TYPE_DICTIONARY:
		_err("'network' must be an object with a cidr", label)
		return
	_cidr = SimNet.parse_cidr(str(net.get("cidr", "")))
	if _cidr.is_empty():
		_err("network cidr '%s' must look like 10.20.0.0/24 (prefix 8 to 30)" % net.get("cidr", ""), label)
		return
	network = {"cidr": net["cidr"], "gateway": str(net.get("gateway", "")), "dns": str(net.get("dns", "")),
			"domain": str(net.get("domain", "")).to_lower()}

	var host_list: Variant = data.get("hosts")
	if typeof(host_list) != TYPE_ARRAY or (host_list as Array).is_empty():
		_err("'hosts' must be a non-empty array", label)
		host_list = []
	if (host_list as Array).size() > MAX_HOSTS:
		_err("more than %d hosts" % MAX_HOSTS, label)
	var ips: Dictionary = {}
	var names: Dictionary = {}
	var you_data: Variant = data.get("you")
	if typeof(you_data) != TYPE_DICTIONARY:
		_err("'you' must be an object with ip and name", label)
	else:
		var y := _load_host(you_data, label, "you", true)
		if not y.is_empty():
			if y["os"] != "linux" and y["os"] != "windows" and y["os"] != "kali":
				_err("you.os '%s' is not supported (the workstation runs linux, windows or kali)" % y["os"], label)
			var mac := str(you_data.get("mac", ""))
			if mac != "" and not _mac_ok(mac):
				_err("you.mac '%s' must look like 52:54:00:12:34:56" % mac, label)
				mac = ""
			you = {"ip": y["ip"], "name": y["name"], "os": y["os"], "user": str(you_data.get("user", "user")),
					"ports": y["ports"], "mac": mac.to_lower()}
			_load_connections(you_data.get("connections", []), label)
			ips[y["ip"]] = true
			names[y["name"]] = true
	for h in host_list:
		var host := _load_host(h, label, "host", false)
		if host.is_empty():
			continue
		if ips.has(host["ip"]):
			_err("duplicate ip %s" % host["ip"], label)
			continue
		if names.has(host["name"]):
			_err("duplicate host name '%s'" % host["name"], label)
			continue
		ips[host["ip"]] = true
		names[host["name"]] = true
		hosts.append(host)

	for key in ["gateway", "dns"]:
		var addr: String = network[key]
		if addr == "" and key == "dns":
			continue
		if SimNet.parse_ip(addr) < 0 or not SimNet.in_cidr(SimNet.parse_ip(addr), _cidr):
			_err("network %s '%s' must be an address inside %s" % [key, addr, network["cidr"]], label)
		elif not ips.has(addr):
			_err("network %s %s is not a host of the lab" % [key, addr], label)
	_load_dns(data.get("dns", []), label, ips)
	_load_files(data.get("files", {}), label, names)
	_load_binaries(data.get("binaries", {}), label, names)
	_load_captures(data.get("captures", {}), label, names)


## A normalised host, or {} after recording why not.
func _load_host(h: Variant, label: String, what: String, is_you: bool) -> Dictionary:
	if typeof(h) != TYPE_DICTIONARY:
		_err("every %s must be an object" % what, label)
		return {}
	var ip := str(h.get("ip", ""))
	var ip_int := SimNet.parse_ip(ip)
	var host_name := str(h.get("name", ""))
	var where := "%s %s" % [what, ip if ip != "" else "(no ip)"]
	var bad := false
	if ip_int < 0:
		_err("%s: 'ip' must be a dotted address" % where, label)
		bad = true
	elif not SimNet.in_cidr(ip_int, _cidr):
		_err("%s is outside %s" % [where, SimNet.ip_string(_cidr["base"]) + "/" + str(_cidr["prefix"])], label)
		bad = true
	if not _name_ok(host_name):
		_err("%s: 'name' must be lower-case letters, digits and hyphens" % where, label)
		bad = true
	var os_name := str(h.get("os", "linux"))
	if not OS_NAMES.has(os_name):
		_err("%s: unknown os '%s' (known: %s)" % [where, os_name, ", ".join(OS_NAMES)], label)
		bad = true
	var latency: Variant = h.get("latency_ms", 0.5)
	if not (typeof(latency) == TYPE_INT or typeof(latency) == TYPE_FLOAT) or latency <= 0 or latency > 2000:
		_err("%s: 'latency_ms' must be a number above 0 and at most 2000" % where, label)
		bad = true
	var icmp: Variant = h.get("icmp", true)
	if typeof(icmp) != TYPE_BOOL:
		_err("%s: 'icmp' must be true or false" % where, label)
		bad = true
	var default_ports := str(h.get("default_ports", "closed"))
	if default_ports != "closed" and default_ports != "filtered":
		_err("%s: 'default_ports' must be closed or filtered" % where, label)
		bad = true
	var ports: Array = []
	var port_list: Variant = h.get("ports", [])
	if typeof(port_list) != TYPE_ARRAY:
		_err("%s: 'ports' must be an array" % where, label)
		bad = true
		port_list = []
	var seen: Dictionary = {}
	for p in port_list:
		var port := _load_port(p, where, label)
		if port.is_empty():
			bad = true
			continue
		var key := "%d/%s" % [port["port"], port["proto"]]
		if seen.has(key):
			_err("%s: port %s listed twice" % [where, key], label)
			bad = true
			continue
		seen[key] = true
		ports.append(port)
	if bad:
		return {}
	return {"ip": ip, "name": host_name, "os": os_name, "latency_ms": float(latency), "icmp": icmp,
			"default_ports": default_ports, "ports": ports}


func _load_port(p: Variant, where: String, label: String) -> Dictionary:
	if typeof(p) != TYPE_DICTIONARY or not _whole(p.get("port")) or int(p["port"]) < 1 or int(p["port"]) > 65535:
		_err("%s: every port needs a whole 'port' from 1 to 65535" % where, label)
		return {}
	var proto := str(p.get("proto", "tcp"))
	var state := str(p.get("state", "open"))
	if not PROTOS.has(proto):
		_err("%s: port %d has unknown proto '%s'" % [where, int(p["port"]), proto], label)
		return {}
	if not STATES.has(state):
		_err("%s: port %d has unknown state '%s'" % [where, int(p["port"]), state], label)
		return {}
	var bind := str(p.get("bind", "0.0.0.0"))
	if SimNet.parse_ip(bind) < 0:
		_err("%s: port %d 'bind' must be an address" % [where, int(p["port"])], label)
		return {}
	var backlog: Variant = p.get("backlog", 128)
	if not _whole(backlog) or int(backlog) < 0:
		_err("%s: port %d 'backlog' must be a whole number" % [where, int(p["port"])], label)
		return {}
	var http := {}
	if p.has("http"):
		if proto != "tcp" or state != "open":
			_err("%s: port %d has an 'http' block but is not an open tcp port" % [where, int(p["port"])], label)
			return {}
		http = _load_http(p["http"], "%s port %d" % [where, int(p["port"])], label)
		if http.is_empty():
			return {}
	var pid: Variant = p.get("pid", 0)
	if not _whole(pid) or int(pid) < 0:
		_err("%s: port %d 'pid' must be a whole number" % [where, int(p["port"])], label)
		return {}
	return {"port": int(p["port"]), "proto": proto, "state": state, "pid": int(pid),
			"service": str(p.get("service", "")), "version": str(p.get("version", "")),
			"bind": bind, "process": str(p.get("process", "")), "owner": str(p.get("owner", "root")),
			"backlog": int(backlog), "http": http}


## A web server's replies: {server, headers, pages}. Each page has a status,
## extra headers, a content type and a body; the Date and Content-Length headers
## are written by the simulator.
func _load_http(h: Variant, where: String, label: String) -> Dictionary:
	if typeof(h) != TYPE_DICTIONARY:
		_err("%s: 'http' must be an object" % where, label)
		return {}
	var bad := false
	var headers: Variant = _load_headers(h.get("headers", {}), where, label)
	if headers == null:
		bad = true
	var pages: Dictionary = {}
	var raw_pages: Variant = h.get("pages", {})
	if typeof(raw_pages) != TYPE_DICTIONARY:
		_err("%s: http 'pages' must be an object of path to page" % where, label)
		return {}
	for path in raw_pages:
		var page: Variant = raw_pages[path]
		if not (path as String).begins_with("/") or typeof(page) != TYPE_DICTIONARY:
			_err("%s: http page '%s' must have a path starting with / and be an object" % [where, path], label)
			bad = true
			continue
		var status: Variant = page.get("status", 200)
		if not _whole(status) or not HTTP_REASONS.has(int(status)):
			_err("%s: http page %s has status %s (known: %s)" % [where, path, status,
					", ".join(HTTP_REASONS.keys().map(func(k): return str(k)))], label)
			bad = true
			continue
		var page_headers: Variant = _load_headers(page.get("headers", {}), "%s page %s" % [where, path], label)
		if page_headers == null or typeof(page.get("body", "")) != TYPE_STRING or typeof(page.get("type", "")) != TYPE_STRING:
			if page_headers != null:
				_err("%s: http page %s: 'body' and 'type' must be text" % [where, path], label)
			bad = true
			continue
		pages[path] = {"status": int(status), "headers": page_headers, "body": str(page.get("body", "")),
				"type": str(page.get("type", "text/html; charset=UTF-8"))}
	if bad:
		return {}
	return {"server": str(h.get("server", "")), "headers": headers, "pages": pages}


## {name: value} in order, or null after recording why not.
func _load_headers(h: Variant, where: String, label: String) -> Variant:
	if typeof(h) != TYPE_DICTIONARY:
		_err("%s: 'headers' must be an object of name to text" % where, label)
		return null
	for k in h:
		if typeof(h[k]) != TYPE_STRING or (k as String).strip_edges() == "" or (k as String).contains(":"):
			_err("%s: header '%s' needs a plain name and a text value" % [where, k], label)
			return null
		if HTTP_GENERATED.has((k as String).to_lower()):
			_err("%s: header '%s' is written by the simulator (use the 'server' and 'type' fields, never Date or Content-Length)" % [where, k], label)
			return null
	return h.duplicate()


## The workstation's open connections: what `ss` and `netstat` list besides
## its listening ports. The local address is always the workstation's own.
func _load_connections(list: Variant, label: String) -> void:
	if typeof(list) != TYPE_ARRAY:
		_err("you.connections must be an array", label)
		return
	for c in list:
		if typeof(c) != TYPE_DICTIONARY or not _whole(c.get("local_port")) or not _whole(c.get("remote_port")) \
				or SimNet.parse_ip(str(c.get("remote_ip", ""))) < 0:
			_err("every connection needs a local_port, a remote_ip and a remote_port", label)
			continue
		var proto := str(c.get("proto", "tcp"))
		var state := str(c.get("state", "ESTABLISHED"))
		if not PROTOS.has(proto) or not CONNECTION_STATES.has(state):
			_err("connection to %s has an unknown proto or state (states: %s)" % [c["remote_ip"], ", ".join(CONNECTION_STATES)], label)
			continue
		for key in ["local_port", "remote_port"]:
			if int(c[key]) < 1 or int(c[key]) > 65535:
				_err("connection to %s: %s must be 1 to 65535" % [c["remote_ip"], key], label)
		connections.append({"proto": proto, "local_port": int(c["local_port"]), "remote_ip": c["remote_ip"],
				"remote_port": int(c["remote_port"]), "state": state, "process": str(c.get("process", "")),
				"owner": str(c.get("owner", "root")), "pid": int(c.get("pid", 0))})


func _load_dns(records: Variant, label: String, ips: Dictionary) -> void:
	if typeof(records) != TYPE_ARRAY:
		_err("'dns' must be an array", label)
		return
	var domain_name := domain()
	var names: Dictionary = {}  # every name the zone knows, for CNAME / MX / NS targets
	for h in all_hosts():
		names[fqdn(h)] = true
	for r in records:
		if typeof(r) == TYPE_DICTIONARY and _text(r.get("name")):
			names[(r["name"] as String).to_lower().trim_suffix(".")] = true
	var cname_owners: Dictionary = {}
	var other_owners: Dictionary = {}
	for h in all_hosts():
		other_owners[fqdn(h)] = true  # a host name already has its A record
	for r in records:
		if typeof(r) != TYPE_DICTIONARY or not _text(r.get("name")):
			_err("every dns record needs a name", label)
			continue
		var type := str(r.get("type", "A")).to_upper()
		var raw: Variant = r.get("value", r.get("a"))
		var name_text := (r["name"] as String).to_lower().trim_suffix(".")
		if not RECORD_TYPES.has(type):
			_err("dns record %s has type %s (known: %s)" % [r["name"], type, ", ".join(RECORD_TYPES)], label)
			continue
		if not _text(raw):
			_err("dns record %s needs a value" % r["name"], label)
			continue
		var ttl: Variant = r.get("ttl", ZONE_TTL)
		if not _whole(ttl) or int(ttl) < 1:
			_err("dns record %s: 'ttl' must be a whole number above 0" % r["name"], label)
			continue
		var value := str(raw).strip_edges()
		if domain_name == "" or not (name_text == domain_name or name_text.ends_with("." + domain_name)):
			if type == "A" and domain_name == "":
				pass  # a lab without a domain keeps the old free-form A records
			else:
				_err("dns record %s is outside the lab domain '%s'" % [r["name"], domain_name], label)
				continue
		if type == "A":
			if not ips.has(value):
				_err("dns record %s points at %s, which is not a host" % [r["name"], value], label)
				continue
		elif type == "CNAME" or type == "NS" or type == "MX":
			var target := value
			if type == "MX":
				var mx := value.split(" ", false)
				if mx.size() != 2 or not mx[0].is_valid_int() or int(mx[0]) < 0 or int(mx[0]) > 65535:
					_err("dns record %s: an MX value looks like '10 mail-01.corp.local'" % r["name"], label)
					continue
				target = mx[1]
			target = target.to_lower().trim_suffix(".")
			if not target.contains(".") and domain_name != "":
				target = "%s.%s" % [target, domain_name]
			if not names.has(target):
				_err("dns record %s points at %s, which the zone does not know" % [r["name"], target], label)
				continue
			value = ("%s %s" % [value.split(" ", false)[0], target]) if type == "MX" else target
		if type == "CNAME":
			cname_owners[name_text] = true
		else:
			other_owners[name_text] = true
		dns.append({"name": name_text, "type": type, "value": value, "ttl": int(ttl)})
	for owner in cname_owners:
		if other_owners.has(owner):
			_err("dns name %s has a CNAME and other records (a CNAME must stand alone)" % owner, label)


func _load_files(data: Variant, label: String, names: Dictionary) -> void:
	if typeof(data) != TYPE_DICTIONARY:
		_err("'files' must be an object of host name to files", label)
		return
	for host_name in data:
		if not names.has(host_name):
			_err("files for unknown host '%s'" % host_name, label)
			continue
		var per_host: Variant = data[host_name]
		if typeof(per_host) != TYPE_DICTIONARY:
			_err("files of '%s' must be an object of file name to text" % host_name, label)
			continue
		for file_name in per_host:
			if typeof(per_host[file_name]) != TYPE_STRING:
				_err("file '%s' of '%s' must be text" % [file_name, host_name], label)
		files[host_name] = per_host


## Compiled binaries for the binary-analysis tools (optional; a lab with none
## has {} and those tools report "no such binary", like `cat` on a missing
## file). Each binary is static, curated data: real `file`/`readelf`/`nm`
## output composed into fields, never produced by running anything.
const RELRO_STATES: Array = ["none", "partial", "full"]


func _load_binaries(data: Variant, label: String, names: Dictionary) -> void:
	if typeof(data) != TYPE_DICTIONARY:
		_err("'binaries' must be an object of host name to binaries", label)
		return
	for host_name in data:
		if not names.has(host_name):
			_err("binaries for unknown host '%s'" % host_name, label)
			continue
		var per_host: Variant = data[host_name]
		if typeof(per_host) != TYPE_DICTIONARY:
			_err("binaries of '%s' must be an object of binary name to binary" % host_name, label)
			continue
		var loaded: Dictionary = {}
		for bin_name in per_host:
			var b := _load_binary(per_host[bin_name], "%s binary '%s'" % [host_name, bin_name], label)
			if not b.is_empty():
				loaded[bin_name] = b
		binaries[host_name] = loaded


func _load_binary(b: Variant, where: String, label: String) -> Dictionary:
	if typeof(b) != TYPE_DICTIONARY:
		_err("%s must be an object" % where, label)
		return {}
	var bad := false
	if not _text(b.get("file_output")):
		_err("%s needs a non-empty 'file_output' (the text after 'name: ' in real file output)" % where, label)
		bad = true
	for key in ["canary", "nx", "pie"]:
		if typeof(b.get(key)) != TYPE_BOOL:
			_err("%s: '%s' must be true or false" % [where, key], label)
			bad = true
	var relro := str(b.get("relro", ""))
	if not RELRO_STATES.has(relro):
		_err("%s: 'relro' must be one of %s" % [where, ", ".join(RELRO_STATES)], label)
		bad = true
	for key in ["nm", "strings", "readelf_h", "readelf_l", "readelf_d"]:
		var arr: Variant = b.get(key, [])
		if typeof(arr) != TYPE_ARRAY:
			_err("%s: '%s' must be an array of text lines" % [where, key], label)
			bad = true
			continue
		for line in arr:
			if typeof(line) != TYPE_STRING:
				_err("%s: every '%s' line must be text" % [where, key], label)
				bad = true
				break
	var functions: Variant = b.get("functions", {})
	if typeof(functions) != TYPE_DICTIONARY:
		_err("%s: 'functions' must be an object of function name to text lines" % where, label)
		bad = true
		functions = {}
	else:
		for fname in functions:
			var lines: Variant = functions[fname]
			if typeof(lines) != TYPE_ARRAY:
				_err("%s: function '%s' must be an array of text lines" % [where, fname], label)
				bad = true
	if bad:
		return {}
	return {"file_output": str(b["file_output"]), "canary": b["canary"], "nx": b["nx"], "pie": b["pie"],
			"relro": relro, "nm": b.get("nm", []), "strings": b.get("strings", []), "functions": functions,
			"readelf_h": b.get("readelf_h", []), "readelf_l": b.get("readelf_l", []), "readelf_d": b.get("readelf_d", [])}


## Recorded wireless captures for the wireless tools (optional; a lab with none
## has {} and those tools report "no such file"). Curated data only: access
## points and stations as a survey tool would list them, and a frame list a
## frame reader would print. Nothing here is produced by a radio.
const CAPTURE_PROTOS: Array = ["802.11", "EAPOL", "RADIUS", "EAP", "TLS"]


func _load_captures(data: Variant, label: String, names: Dictionary) -> void:
	if typeof(data) != TYPE_DICTIONARY:
		_err("'captures' must be an object of host name to captures", label)
		return
	for host_name in data:
		if not names.has(host_name):
			_err("captures for unknown host '%s'" % host_name, label)
			continue
		var per_host: Variant = data[host_name]
		if typeof(per_host) != TYPE_DICTIONARY:
			_err("captures of '%s' must be an object of capture name to capture" % host_name, label)
			continue
		var loaded: Dictionary = {}
		for cap_name in per_host:
			var c := _load_capture(per_host[cap_name], "%s capture '%s'" % [host_name, cap_name], label)
			if not c.is_empty():
				loaded[cap_name] = c
		captures[host_name] = loaded


func _load_capture(c: Variant, where: String, label: String) -> Dictionary:
	if typeof(c) != TYPE_DICTIONARY:
		_err("%s must be an object" % where, label)
		return {}
	var bad := false
	var aps: Variant = c.get("aps", [])
	var stations: Variant = c.get("stations", [])
	var frames: Variant = c.get("frames", [])
	for pair in [["aps", aps], ["stations", stations], ["frames", frames]]:
		if typeof(pair[1]) != TYPE_ARRAY:
			_err("%s: '%s' must be an array" % [where, pair[0]], label)
			bad = true
	if bad:
		return {}
	for a in aps:
		if typeof(a) != TYPE_DICTIONARY or not _mac_ok(str(a.get("bssid", ""))):
			_err("%s: every access point needs a 'bssid' like 00:00:5e:00:53:01" % where, label)
			bad = true
			continue
		for key in ["channel", "pwr", "beacons", "data", "rate"]:
			if not _whole(a.get(key)):
				_err("%s: access point %s needs a whole number '%s'" % [where, a["bssid"], key], label)
				bad = true
		for key in ["essid", "enc", "cipher", "auth"]:
			if typeof(a.get(key)) != TYPE_STRING:
				_err("%s: access point %s needs text '%s' (may be empty)" % [where, a["bssid"], key], label)
				bad = true
	for st in stations:
		if typeof(st) != TYPE_DICTIONARY or not _mac_ok(str(st.get("mac", ""))):
			_err("%s: every station needs a 'mac'" % where, label)
			bad = true
			continue
		if str(st.get("bssid", "")) != "" and not _mac_ok(str(st["bssid"])):
			_err("%s: station %s: 'bssid' must be a MAC or empty (not associated)" % [where, st["mac"]], label)
			bad = true
	var last_t := -1.0
	for i in (frames as Array).size():
		var f: Variant = frames[i]
		var fwhere := "%s frame %d" % [where, i + 1]
		if typeof(f) != TYPE_DICTIONARY:
			_err("%s must be an object" % fwhere, label)
			bad = true
			continue
		if not (typeof(f.get("t")) == TYPE_INT or typeof(f.get("t")) == TYPE_FLOAT) or float(f["t"]) < last_t:
			_err("%s: 't' must be a number that does not go backwards" % fwhere, label)
			bad = true
		else:
			last_t = float(f["t"])
		for key in ["src", "dst"]:
			if not _mac_ok(str(f.get(key, ""))) and SimNet.parse_ip(str(f.get(key, ""))) < 0:
				_err("%s: '%s' must be a MAC address (or an IP address for wired RADIUS frames)" % [fwhere, key], label)
				bad = true
		if not CAPTURE_PROTOS.has(str(f.get("proto", ""))):
			_err("%s: 'proto' must be one of %s" % [fwhere, ", ".join(CAPTURE_PROTOS)], label)
			bad = true
		if not _whole(f.get("len")) or not _text(f.get("info")):
			_err("%s needs a whole 'len' and non-empty 'info'" % fwhere, label)
			bad = true
		for key in ["tags", "detail"]:
			if typeof(f.get(key, [])) != TYPE_ARRAY:
				_err("%s: '%s' must be an array of text" % [fwhere, key], label)
				bad = true
	if bad:
		return {}
	return {"aps": aps, "stations": stations, "frames": frames, "packets": int(c.get("packets", (frames as Array).size())),
			"start": str(c.get("start", "")), "elapsed": str(c.get("elapsed", "1 min")), "header_channel": int(c.get("header_channel", 6))}
