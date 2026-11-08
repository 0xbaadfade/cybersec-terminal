class_name SimIp
extends SimTool
## ip for addresses, links and routes, in the shape of iproute2 7.0.0 (checked
## against the real tool on an eth0 built to look like the lab workstation, see
## tests/golden/ip_*.txt). It reads the workstation's address, network and gateway
## from the lab; it never changes anything, so `ip addr add` and friends are refused.

const OBJECTS_REFUSED: Array = ["addrlabel", "fou", "ila", "ioam", "l2tp", "macsec", "maddress", "monitor", "mptcp",
		"mroute", "mrule", "neighbor", "neighbour", "netconf", "netns", "nexthop", "ntable", "ntbl", "rule", "sr",
		"stats", "tap", "tcpmetrics", "token", "tunnel", "tuntap", "vrf", "xfrm"]
const USAGE: Array = [
	"Usage: ip [ OPTIONS ] OBJECT { COMMAND | help }",
	"       ip [ -force ] -batch filename",
	"where  OBJECT := { address | addrlabel | fou | help | ila | ioam | l2tp | link |",
	"                   macsec | maddress | monitor | mptcp | mroute | mrule |",
	"                   neighbor | neighbour | netconf | netns | nexthop | ntable |",
	"                   ntbl | route | rule | sr | stats | tap | tcpmetrics |",
	"                   token | tunnel | tuntap | vrf | xfrm }",
	"       OPTIONS := { -V[ersion] | -s[tatistics] | -d[etails] | -r[esolve] |",
	"                    -h[uman-readable] | -iec | -j[son] | -p[retty] |",
	"                    -f[amily] { inet | inet6 | mpls | bridge | link } |",
	"                    -4 | -6 | -M | -B | -0 |",
	"                    -l[oops] { maximum-addr-flush-attempts } | -echo | -br[ief] |",
	"                    -o[neline] | -t[imestamp] | -ts[hort] | -b[atch] [filename] |",
	"                    -rc[vbuf] [size] | -n[etns] name | -N[umeric] | -a[ll] |",
	"                    -c[olor]}",
]


func tool_name() -> String:
	return "ip"


func run(argv: Array, ctx: SimContext, _stdin: Array) -> Dictionary:
	var brief := false
	var ipv4_only := false
	var i := 0
	while i < argv.size() and (argv[i] as String).begins_with("-"):
		var opt: String = argv[i]
		i += 1
		if opt == "-4":
			ipv4_only = true
		elif opt == "-br" or opt == "-brief":
			brief = true
		else:
			return unsupported("ip", opt)
	if i >= argv.size():
		return done(USAGE.duplicate(), 255)
	var object: String = argv[i]
	i += 1
	var kind := ""
	if _prefix_of(object, "address"):
		kind = "address"
	elif _prefix_of(object, "link"):
		kind = "link"
	elif _prefix_of(object, "route"):
		kind = "route"
	elif OBJECTS_REFUSED.any(func(o): return (o as String).begins_with(object)) and object.length() >= 2:
		return done(["ip: '%s' is not supported in this simulator (address, link and route are)" % object], 1)
	else:
		return done(["Object \"%s\" is unknown, try \"ip help\"." % object], 1)

	var rest: Array = argv.slice(i)
	if not rest.is_empty():
		var verb: String = rest[0]
		if verb == "list" or verb == "lst" or (verb != "" and "show".begins_with(verb)):
			rest = rest.slice(1)
		elif _is_change(verb):
			return done(["ip: 'ip %s %s' changes the system, which this simulator does not do" % [object, verb]], 1)
	var dev := ""
	if kind != "route" and not rest.is_empty():
		var word: String = rest[0]
		if word == "dev" and rest.size() >= 2:
			dev = rest[1]
			rest = rest.slice(2)
		else:
			dev = word
			rest = rest.slice(1)
	if not rest.is_empty():
		return done(["ip: '%s' is not supported in this simulator" % " ".join(rest)], 1)

	var lab := ctx.lab
	var nics := _nics(lab)
	if dev != "":
		nics = nics.filter(func(n): return n["name"] == dev)
		if nics.is_empty():
			return done(["Device \"%s\" does not exist." % dev], 1)
	match kind:
		"route":
			return done(_routes(lab))
		"link":
			return done(_link_brief(nics) if brief else _link_full(nics))
	return done(_addr_brief(nics, ipv4_only) if brief else _addr_full(nics, ipv4_only))


static func _prefix_of(word: String, full: String) -> bool:
	return word != "" and full.begins_with(word)


static func _is_change(verb: String) -> bool:
	for v in ["add", "del", "delete", "change", "replace", "flush", "set", "append", "save", "restore"]:
		if v == verb:
			return true
	return false


## The workstation's interfaces: loopback and its one network card.
static func _nics(lab: SimLab) -> Array:
	var c := lab.cidr()
	var mask := (0xFFFFFFFF << (32 - int(c["prefix"]))) & 0xFFFFFFFF
	var ip := SimNet.parse_ip(lab.you["ip"])
	return [
		{"index": 1, "name": "lo", "flags": "LOOPBACK,UP,LOWER_UP", "mtu": 65536, "state": "UNKNOWN",
			"link": "loopback", "mac": "00:00:00:00:00:00", "brd": "00:00:00:00:00:00",
			"v4": "127.0.0.1/8", "v4_brd": "", "scope": "host", "v6": "::1/128", "v6_scope": "host", "v6_proto": "kernel_lo"},
		{"index": 2, "name": "eth0", "flags": "BROADCAST,MULTICAST,UP,LOWER_UP", "mtu": 1500, "state": "UP",
			"link": "ether", "mac": lab.you_mac(), "brd": "ff:ff:ff:ff:ff:ff",
			"v4": "%s/%d" % [lab.you["ip"], int(c["prefix"])], "v4_brd": SimNet.ip_string(ip | (~mask & 0xFFFFFFFF)),
			"scope": "global", "v6": "%s/64" % _link_local(lab.you_mac()), "v6_scope": "link", "v6_proto": "kernel_ll"}]


## The IPv6 link-local address a card gets from its MAC (EUI-64).
static func _link_local(mac: String) -> String:
	var b: Array = []
	for part in mac.split(":"):
		b.append(("0x" + part).hex_to_int())
	var groups: Array = [((b[0] ^ 2) << 8) | b[1], (b[2] << 8) | 0xff, (0xfe << 8) | b[3], (b[4] << 8) | b[5]]
	return "fe80::" + ":".join(groups.map(func(g): return "%x" % g))


static func _addr_full(nics: Array, ipv4_only: bool) -> Array:
	var out: Array = []
	for n in nics:
		out.append("%d: %s: <%s> mtu %d qdisc noqueue state %s group default qlen 1000" % [n["index"], n["name"], n["flags"], n["mtu"], n["state"]])
		if not ipv4_only:
			out.append("    link/%s %s brd %s" % [n["link"], n["mac"], n["brd"]])
		var brd: String = (" brd " + n["v4_brd"]) if n["v4_brd"] != "" else ""
		out.append("    inet %s%s scope %s %s" % [n["v4"], brd, n["scope"], n["name"]])
		out.append("       valid_lft forever preferred_lft forever")
		if not ipv4_only:
			out.append("    inet6 %s scope %s proto %s" % [n["v6"], n["v6_scope"], n["v6_proto"]])
			out.append("       valid_lft forever preferred_lft forever")
	return out


static func _link_full(nics: Array) -> Array:
	var out: Array = []
	for n in nics:
		out.append("%d: %s: <%s> mtu %d qdisc noqueue state %s mode DEFAULT group default qlen 1000" % [n["index"], n["name"], n["flags"], n["mtu"], n["state"]])
		out.append("    link/%s %s brd %s" % [n["link"], n["mac"], n["brd"]])
	return out


static func _addr_brief(nics: Array, ipv4_only: bool) -> Array:
	var out: Array = []
	for n in nics:
		var addrs: String = n["v4"] if ipv4_only else "%s %s" % [n["v4"], n["v6"]]
		out.append("%s %s %s" % [(n["name"] as String).rpad(16), (n["state"] as String).rpad(14), addrs])
	return out


static func _link_brief(nics: Array) -> Array:
	var out: Array = []
	for n in nics:
		out.append("%s %s %s <%s>" % [(n["name"] as String).rpad(16), (n["state"] as String).rpad(14), n["mac"], n["flags"]])
	return out


static func _routes(lab: SimLab) -> Array:
	var c := lab.cidr()
	var out: Array = []
	if lab.network.get("gateway", "") != "":
		out.append("default via %s dev eth0" % lab.network["gateway"])
	out.append("%s/%d dev eth0 proto kernel scope link src %s" % [SimNet.ip_string(int(c["base"])), int(c["prefix"]), lab.you["ip"]])
	return out
