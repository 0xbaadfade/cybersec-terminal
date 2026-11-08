class_name SimIpconfig
extends SimTool
## ipconfig and ipconfig /all, in the layout Windows documents. UNVERIFIED: written
## from Microsoft's published output, not captured (README "Phase 4c-2 as built").
## The workstation has one Ethernet adapter named Ethernet0 that takes its settings
## from DHCP (the gateway is the DHCP server).

const ADAPTER := "Intel(R) 82574L Gigabit Network Connection"


func tool_name() -> String:
	return "ipconfig"


func run(argv: Array, ctx: SimContext, _stdin: Array) -> Dictionary:
	var lab := ctx.lab
	var opts := argv.map(func(a): return (a as String).to_lower())
	for o in opts:
		if o != "/all" and o != "-all":
			if ["/release", "/renew", "/flushdns", "/registerdns", "/release6", "/renew6", "/setclassid"].has(o):
				return done(["ipconfig: %s changes the system, which this simulator does not do" % o], 1)
			return done(["ipconfig: option '%s' is not supported in this simulator (only /all)" % argv[opts.find(o)]], 1)
	var full := not opts.is_empty()
	var domain := lab.domain()
	var gateway: String = lab.network.get("gateway", "")
	var out: Array = ["", "Windows IP Configuration", ""]
	if full:
		out = ["", "Windows IP Configuration", "",
				_row("   Host Name . . . . . . . . . . . . ", lab.you["name"]),
				_row("   Primary Dns Suffix  . . . . . . . ", ""),
				_row("   Node Type . . . . . . . . . . . . ", "Hybrid"),
				_row("   IP Routing Enabled. . . . . . . . ", "No"),
				_row("   WINS Proxy Enabled. . . . . . . . ", "No"),
				_row("   DNS Suffix Search List. . . . . . ", domain)]
	else:
		out.append("")
	out.append("Ethernet adapter Ethernet0:")
	out.append("")
	out.append(_row("   Connection-specific DNS Suffix  . ", domain))
	if full:
		out.append(_row("   Description . . . . . . . . . . . ", ADAPTER))
		out.append(_row("   Physical Address. . . . . . . . . ", SimWinTools.mac_dashes(lab.you_mac())))
		out.append(_row("   DHCP Enabled. . . . . . . . . . . ", "Yes"))
		out.append(_row("   Autoconfiguration Enabled . . . . ", "Yes"))
	out.append(_row("   Link-local IPv6 Address . . . . . ", SimWinTools.link_local(lab) + "%6" + ("(Preferred) " if full else "")))
	out.append(_row("   IPv4 Address. . . . . . . . . . . ", lab.you["ip"] + ("(Preferred) " if full else "")))
	out.append(_row("   Subnet Mask . . . . . . . . . . . ", SimWinTools.netmask(lab)))
	if full:
		var obtained := ctx.now - 3 * 3600
		out.append(_row("   Lease Obtained. . . . . . . . . . ", SimWinTools.lease_time(obtained)))
		out.append(_row("   Lease Expires . . . . . . . . . . ", SimWinTools.lease_time(obtained + 8 * 86400)))
	out.append(_row("   Default Gateway . . . . . . . . . ", gateway))
	if full:
		var rng := SimNet.rng_for(lab.seed_value, "duid:" + lab.you["name"])
		var duid: Array = []
		for _n in 10:
			duid.append("%02X" % rng.randi_range(0, 255))
		out.append(_row("   DHCP Server . . . . . . . . . . . ", gateway))
		out.append(_row("   DHCPv6 IAID . . . . . . . . . . . ", str(rng.randi_range(100000000, 999999999))))
		out.append(_row("   DHCPv6 Client DUID. . . . . . . . ", "00-01-00-01-" + "-".join(duid)))
		out.append(_row("   DNS Servers . . . . . . . . . . . ", lab.network.get("dns", "")))
		out.append(_row("   NetBIOS over Tcpip. . . . . . . . ", "Enabled"))
	out.append("")
	return done(out)


static func _row(label: String, value: String) -> String:
	return "%s: %s" % [label, value] if value != "" else "%s:" % label
