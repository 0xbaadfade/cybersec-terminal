extends GutTest
## P4c-2: the Windows-flavoured workstation (ipconfig, ping, nslookup, netstat,
## findstr, type). There is no Windows machine to capture, so these layouts are
## NOT pinned to a real tool: the expected text below is the documented output the
## code was written from (README "Phase 4c-2 as built"), and these tests keep it
## from changing by accident.

const Support := preload("res://tests/unit/support.gd")
const REAL_PACK := "res://packs/windows-cli"
const LINUX_PACK := "res://packs/linux-cli"

var _shell := SimShell.new()


func _lab() -> SimLab:
	var data := Support.demo_lab()
	data["network"]["cidr"] = "192.168.10.0/24"
	data["network"]["gateway"] = "192.168.10.1"
	data["network"]["dns"] = "192.168.10.5"
	data["network"]["domain"] = "office.lan"
	data["you"] = {"ip": "192.168.10.50", "name": "ws-win", "os": "windows", "user": "mia", "mac": "52:54:00:5e:1c:88",
		"ports": [
			{"port": 135, "process": "svchost", "owner": "SYSTEM", "pid": 1204},
			{"port": 3389, "process": "svchost", "owner": "SYSTEM", "pid": 1876},
			{"port": 123, "proto": "udp", "process": "svchost", "owner": "SYSTEM", "pid": 1052}],
		"connections": [{"local_port": 49722, "remote_ip": "192.168.10.20", "remote_port": 445, "process": "System", "owner": "SYSTEM", "pid": 4},
			{"proto": "udp", "local_port": 53000, "remote_ip": "192.168.10.5", "remote_port": 53, "process": "svchost", "owner": "SYSTEM", "pid": 1052}]}
	data["hosts"] = [
		{"ip": "192.168.10.1", "name": "gw-01", "os": "network", "ports": [{"port": 80, "http": {"server": "Boa/0.94", "pages": {"/": {"body": "x\n"}}}}]},
		{"ip": "192.168.10.5", "name": "dc-01", "os": "windows", "latency_ms": 0.4, "ports": [{"port": 53, "proto": "udp"}]},
		{"ip": "192.168.10.20", "name": "fs-01", "os": "windows", "latency_ms": 0.4},
		{"ip": "192.168.10.30", "name": "slow-01", "os": "windows", "latency_ms": 20.0},
		{"ip": "192.168.10.31", "name": "mid-01", "os": "windows", "latency_ms": 1.3},
		{"ip": "192.168.10.40", "name": "print-01", "os": "network", "icmp": false}]
	data["dns"] = [{"name": "files.office.lan", "type": "CNAME", "value": "fs-01.office.lan"},
		{"name": "office.lan", "type": "MX", "value": "10 fs-01.office.lan"}, {"name": "office.lan", "type": "TXT", "value": "v=spf1 -all"}]
	data["files"] = {"ws-win": {"readme.txt": "one\ntwo 3389\nthree\n"}}
	var lab := SimLab.from_data(data, "labs/win.json")
	assert_true(lab.ok(), "\n".join(lab.errors))
	return lab


func _run(line: String, lab: SimLab = null) -> Dictionary:
	var ctx := SimContext.new()
	ctx.lab = lab if lab != null else _lab()
	ctx.rng = SimNet.rng_for(ctx.lab.seed_value, line)
	ctx.now = Support.T0
	ctx.tool_names = _shell.tool_names_for("windows")
	return _shell.execute(line, ctx)


func _text(line: String) -> String:
	return "\n".join(_run(line)["out"])


# --- the shell around them ---------------------------------------------------------

func test_a_windows_lab_is_accepted_and_offers_windows_tools() -> void:
	assert_eq(_lab().you["os"], "windows")
	assert_eq(_shell.tool_names_for("windows"), ["curl", "findstr", "hostname", "ipconfig", "netstat", "nslookup", "ping", "type"])
	assert_true(_shell.tool_names_for("linux").has("grep"))
	assert_false(_shell.tool_names_for("linux").has("ipconfig"))


func test_unknown_commands_say_what_cmd_says() -> void:
	assert_eq(_run("grep x")["out"], ["'grep' is not recognized as an internal or external command,", "operable program or batch file."])
	assert_eq(_run("nmap 192.168.10.5")["code"], 9009)
	assert_eq(_run("ipconfig")["code"], 0)
	var linux := SimLab.from_data(Support.demo_lab(), "x")
	var ctx := SimContext.new()
	ctx.lab = linux
	ctx.rng = SimNet.rng_for(1, "ipconfig")
	assert_eq(_shell.execute("ipconfig", ctx)["out"], ["bash: ipconfig: command not found"])


func test_backslashes_are_literal_in_a_windows_line() -> void:
	assert_eq(SimShell.tokenize("type C:\\Users\\mia\\readme.txt", true)["stages"], [["type", "C:\\Users\\mia\\readme.txt"]])
	assert_eq(SimShell.tokenize("findstr /c:\"a b\" x", true)["stages"], [["findstr", "/c:a b", "x"]])
	assert_eq(SimShell.tokenize("a;b", true)["stages"], [["a;b"]], "cmd has no ; operator")
	assert_eq(SimShell.tokenize("a\\ b", false)["stages"], [["a b"]], "the Linux shell still escapes")


func test_the_prompt_is_a_windows_path() -> void:
	var s := TerminalSession.new(_lab(), {}, {}, {}, null)
	assert_eq(s.prompt(), "C:\\Users\\mia>")


# --- ipconfig ---------------------------------------------------------------------

func test_ipconfig_layout() -> void:
	var out: Array = _run("ipconfig")["out"]
	var v6: String = (out[7] as String).get_slice(": ", 1)
	assert_true(v6.begins_with("fe80::") and v6.ends_with("%6"), v6)
	out[7] = "V6"
	assert_eq(out, ["", "Windows IP Configuration", "", "", "Ethernet adapter Ethernet0:", "",
		"   Connection-specific DNS Suffix  . : office.lan", "V6",
		"   IPv4 Address. . . . . . . . . . . : 192.168.10.50",
		"   Subnet Mask . . . . . . . . . . . : 255.255.255.0",
		"   Default Gateway . . . . . . . . . : 192.168.10.1", ""])


func test_ipconfig_all_adds_the_details() -> void:
	var text := _text("ipconfig /all")
	for want in ["   Host Name . . . . . . . . . . . . : ws-win", "   Node Type . . . . . . . . . . . . : Hybrid",
			"   DNS Suffix Search List. . . . . . : office.lan", "   Physical Address. . . . . . . . . : 52-54-00-5E-1C-88",
			"   DHCP Enabled. . . . . . . . . . . : Yes", "   IPv4 Address. . . . . . . . . . . : 192.168.10.50(Preferred) ",
			"   DHCP Server . . . . . . . . . . . : 192.168.10.1", "   DNS Servers . . . . . . . . . . . : 192.168.10.5",
			"   Primary Dns Suffix  . . . . . . . :", "   NetBIOS over Tcpip. . . . . . . . : Enabled"]:
		assert_string_contains(text, want)
	assert_eq(_text("ipconfig /ALL"), text, "the option is case-insensitive")


func test_ipconfig_lease_runs_eight_days_from_three_hours_ago() -> void:
	var text := _text("ipconfig /all")
	var obtained: int = Support.T0 - 3 * 3600
	assert_string_contains(text, "   Lease Obtained. . . . . . . . . . : " + SimWinTools.lease_time(obtained))
	assert_string_contains(text, "   Lease Expires . . . . . . . . . . : " + SimWinTools.lease_time(obtained + 8 * 86400))


func test_ipconfig_lease_times_follow_the_clock() -> void:
	assert_string_contains(_text("ipconfig /all"), "Lease Obtained. . . . . . . . . . : Thursday, ")
	assert_eq(SimWinTools.lease_time(1728000000), "Friday, October 4, 2024 12:00:00 AM")
	assert_eq(SimWinTools.lease_time(1728000000 + 13 * 3600), "Friday, October 4, 2024 1:00:00 PM")


func test_ipconfig_refusals() -> void:
	assert_string_contains(_text("ipconfig /renew"), "changes the system")
	assert_string_contains(_text("ipconfig /flushdns"), "changes the system")
	assert_string_contains(_text("ipconfig /displaydns"), "not supported in this simulator")


# --- ping -------------------------------------------------------------------------

func test_ping_a_host() -> void:
	var out: Array = _run("ping fs-01")["out"]
	assert_eq(out[0], "")
	assert_eq(out[1], "Pinging fs-01.office.lan [192.168.10.20] with 32 bytes of data:")
	for i in range(2, 6):
		assert_true((out[i] as String).begins_with("Reply from 192.168.10.20: bytes=32 time"), out[i])
		assert_true((out[i] as String).ends_with("TTL=128"), out[i])
	assert_eq(out[6], "")
	assert_eq(out[7], "Ping statistics for 192.168.10.20:")
	assert_eq(out[8], "    Packets: Sent = 4, Received = 4, Lost = 0 (0% loss),")
	assert_eq(out[9], "Approximate round trip times in milli-seconds:")
	assert_true((out[10] as String).begins_with("    Minimum = "))


func test_ping_reports_whole_milliseconds_truncated() -> void:
	for line in (_run("ping dc-01")["out"] as Array).slice(2, 6):
		assert_true((line as String).contains("time<1ms"), "0.4 ms is under a millisecond: %s" % line)
	for line in (_run("ping mid-01")["out"] as Array).slice(2, 6):
		assert_false((line as String).contains("<1ms"), "1.3 ms is at least a millisecond: %s" % line)
		assert_true((line as String).contains("time=1ms") or (line as String).contains("time=2ms"), line)
	var slow: Array = _run("ping slow-01")["out"]
	for line in slow.slice(2, 6):
		var ms := int((line as String).get_slice("time=", 1).get_slice("ms", 0))
		assert_true(ms >= 15 and ms <= 40, line)


func test_ping_by_address_ttl_and_options() -> void:
	assert_eq(_run("ping 192.168.10.20")["out"][1], "Pinging 192.168.10.20 with 32 bytes of data:")
	assert_true(_text("ping 192.168.10.1").contains("TTL=255"))
	assert_eq(_run("ping -n 2 fs-01")["out"].size(), 2 + 2 + 5)
	assert_eq(_run("ping /n 2 fs-01")["out"], _run("ping -n 2 fs-01")["out"])
	assert_string_contains(_text("ping -l 100 fs-01"), "bytes=100 ")
	assert_string_contains(_text("ping -l 100 fs-01"), "with 100 bytes of data")


func test_ping_without_an_answer() -> void:
	var out: Array = _run("ping 192.168.10.40")["out"]
	assert_eq(out.slice(2, 6), ["Request timed out.", "Request timed out.", "Request timed out.", "Request timed out."])
	assert_eq(out[8], "    Packets: Sent = 4, Received = 0, Lost = 4 (100% loss),")
	assert_eq(out.size(), 9, "no round trip block when nothing came back")
	assert_eq(_run("ping 192.168.10.40")["code"], 1)
	var gone: Array = _run("ping 192.168.10.99")["out"]
	assert_eq(gone[2], "Reply from 192.168.10.50: Destination host unreachable.")
	assert_eq(gone[8], "    Packets: Sent = 4, Received = 4, Lost = 0 (0% loss),", "Windows counts these as received")


func test_ping_errors_and_refusals() -> void:
	assert_eq(_run("ping nosuchhost")["out"], ["Ping request could not find host nosuchhost. Please check the name and try again."])
	assert_eq(_run("ping")["out"], ["IP address must be specified."])
	assert_eq(_run("ping -n 0 fs-01")["out"], ["Bad value for option -n, valid range is from 1 to 4294967295."])
	assert_eq(_run("ping -t fs-01")["out"], ["ping: option '-t' is not supported in this simulator"])
	assert_eq(_run("ping -n")["out"], ["Value must be supplied for option -n."])


# --- nslookup ---------------------------------------------------------------------

func test_nslookup_layout() -> void:
	assert_eq(_run("nslookup fs-01")["out"], ["Server:  dc-01.office.lan", "Address:  192.168.10.5", "",
		"Name:    fs-01.office.lan", "Address:  192.168.10.20", ""])
	assert_eq(_run("nslookup fs-01.office.lan 192.168.10.5")["out"], _run("nslookup fs-01")["out"])
	assert_eq(_run("nslookup files.office.lan")["out"].slice(3), ["Name:    fs-01.office.lan", "Address:  192.168.10.20",
		"Aliases:  files.office.lan", ""])


func test_nslookup_ptr() -> void:
	assert_eq(_run("nslookup 192.168.10.20")["out"].slice(3), ["Name:    fs-01.office.lan", "Address:  192.168.10.20", ""])


func test_nslookup_failures() -> void:
	assert_eq(_run("nslookup nosuch.office.lan")["out"].slice(3), ["*** dc-01.office.lan can't find nosuch.office.lan: Non-existent domain", ""])
	assert_eq(_run("nslookup example.com")["out"].slice(3), ["*** dc-01.office.lan can't find example.com: Server failed", ""])
	assert_eq(_run("nslookup -type=MX fs-01.office.lan")["out"].slice(3), ["*** No mail exchanger (MX) records available for fs-01.office.lan", ""])
	var dead := _text("nslookup fs-01 192.168.10.77")
	assert_string_contains(dead, "Server:  UnKnown")
	assert_string_contains(dead, "DNS request timed out.\n    timeout was 2 seconds.")
	assert_string_contains(dead, "*** Request to UnKnown timed-out")


func test_nslookup_record_types() -> void:
	var mx := _text("nslookup -type=MX office.lan")
	assert_string_contains(mx, "office.lan\tMX preference = 10, mail exchanger = fs-01.office.lan")
	assert_string_contains(mx, "fs-01.office.lan\tinternet address = 192.168.10.20")
	assert_string_contains(_text("nslookup -type=NS office.lan"), "office.lan\tnameserver = dc-01.office.lan")
	assert_string_contains(_text("nslookup -type=TXT office.lan"), "office.lan\ttext =\n\n\t\"v=spf1 -all\"")
	var soa := _text("nslookup -type=SOA office.lan")
	assert_string_contains(soa, "\tprimary name server = dc-01.office.lan")
	assert_string_contains(soa, "\trefresh = 3600 (1 hour)")
	assert_string_contains(soa, "\tretry   = 600 (10 mins)")
	assert_string_contains(soa, "\texpire  = 86400 (1 day)")
	assert_string_contains(soa, "\tdefault TTL = 300 (5 mins)")


func test_nslookup_refusals() -> void:
	assert_string_contains(_text("nslookup"), "interactive mode is not supported")
	assert_string_contains(_text("nslookup -debug fs-01"), "not supported in this simulator")
	assert_string_contains(_text("nslookup fs-01 dc-01"), "must be an address")


# --- netstat ----------------------------------------------------------------------

func test_netstat_ano_layout() -> void:
	var out: Array = _run("netstat -ano")["out"]
	assert_eq(out.slice(0, 4), ["", "Active Connections", "", "  Proto  Local Address          Foreign Address        State           PID"])
	assert_true(out.has("  TCP    0.0.0.0:135            0.0.0.0:0              LISTENING       1204"))
	assert_true(out.has("  TCP    0.0.0.0:3389           0.0.0.0:0              LISTENING       1876"))
	assert_true(out.has("  TCP    192.168.10.50:49722    192.168.10.20:445      ESTABLISHED     4"))
	assert_true(out.has("  UDP    0.0.0.0:123            *:*                                    1052"))
	assert_eq(out[-1], "")


func test_netstat_an_has_no_pid_column() -> void:
	var out: Array = _run("netstat -an")["out"]
	assert_eq(out[3], "  Proto  Local Address          Foreign Address        State")
	assert_true(out.has("  TCP    0.0.0.0:3389           0.0.0.0:0              LISTENING"))
	assert_true(out.has("  UDP    0.0.0.0:123            *:*"))


func test_netstat_without_a_lists_only_established_tcp() -> void:
	var out: Array = _run("netstat -n")["out"]
	assert_eq(out.size(), 6, "one established TCP connection; the UDP one and the listeners need -a")
	assert_string_contains(out[4], "ESTABLISHED")
	assert_true(_run("netstat -an")["out"].any(func(l): return (l as String).contains("UDP    192.168.10.50:53000")))


func test_netstat_refusals() -> void:
	assert_string_contains(_text("netstat"), "resolving names is not simulated")
	assert_string_contains(_text("netstat -b"), "requires elevation")
	assert_string_contains(_text("netstat -s"), "not supported in this simulator")


# --- findstr, type, hostname, curl -------------------------------------------------

func test_findstr_filters_a_pipe_and_a_file() -> void:
	assert_eq(_run("netstat -ano | findstr 3389")["out"].size(), 1)
	assert_eq(_run("netstat -ano | findstr /c:\"0.0.0.0:135\"")["out"].size(), 1)
	assert_eq(_run("findstr two readme.txt")["out"], ["two 3389"])
	assert_eq(_run("findstr /n three readme.txt")["out"], ["3:three"])
	assert_eq(_run("findstr /v two readme.txt")["out"], ["one", "three"])
	assert_eq(_run("findstr /i TWO readme.txt")["out"], ["two 3389"])
	assert_eq(_run("findstr \"one three\" readme.txt")["out"], ["one", "three"], "several words in one argument match any")
	assert_eq(_run("findstr one three readme.txt")["out"], ["FINDSTR: Cannot open three"], "the second bare word is a file")
	assert_eq(_run("findstr zzz readme.txt")["code"], 1)
	assert_eq(_run("findstr two nofile.txt")["out"], ["FINDSTR: Cannot open nofile.txt"])
	assert_eq(_run("findstr")["out"], ["FINDSTR: Bad command line"])
	assert_string_contains(_text("findstr /r a readme.txt"), "not supported")


func test_type_hostname_and_curl() -> void:
	assert_eq(_run("type readme.txt")["out"], ["one", "two 3389", "three"])
	assert_eq(_run("type nofile.txt")["out"], ["The system cannot find the file specified."])
	assert_eq(_run("hostname")["out"], ["ws-win"])
	assert_eq(_run("curl http://gw-01")["out"], ["x"])


# --- the shipped Windows lab -----------------------------------------------------------

func _session(pack: Pack, id: String) -> TerminalSession:
	return TerminalSession.new(pack.labs["lab-office-01"], pack.tool_docs, pack.concept_titles(), pack.items[id], Rules.load_default())


func _out(s: TerminalSession, line: String) -> String:
	return "\n".join(s.run(line, Support.T0)["out"])


func test_the_windows_missions_have_their_answers_in_the_lab() -> void:
	var pack := Pack.load_dir(REAL_PACK)
	assert_true(pack.ok(), "\n".join(pack.errors))
	assert_eq(pack.labs["lab-office-01"].you["os"], "windows")
	var s := _session(pack, "win-m-01")
	assert_string_contains(_out(s, "ipconfig"), "Default Gateway . . . . . . . . . : 192.168.10.1")
	assert_true(s.is_right("192.168.10.1"))
	s = _session(pack, "win-m-02")
	assert_string_contains(_out(s, "ipconfig /all"), "Physical Address. . . . . . . . . : 52-54-00-5E-1C-88")
	assert_true(s.is_right("52-54-00-5E-1C-88"))
	assert_true(s.is_right("52:54:00:5e:1c:88"))
	s = _session(pack, "win-m-03")
	assert_string_contains(_out(s, "netstat -ano | findstr 3389"), "LISTENING       1876")
	assert_true(s.is_right("1876"))
	s = _session(pack, "win-m-04")
	assert_string_contains(_out(s, "nslookup fs-01"), "Server:  dc-01.office.lan")
	assert_true(s.is_right("dc-01"))
	s = _session(pack, "win-m-05")
	assert_string_contains(_out(s, "curl -I http://cam-01"), "Server: Boa/0.94.14rc21")
	assert_true(s.is_right("Boa/0.94.14rc21"))
	assert_true(s.is_right("boa"))
	assert_eq(s.prompt(), "C:\\Users\\mia>")


func test_the_windows_show_question_renders() -> void:
	var pack := Pack.load_dir(REAL_PACK)
	var router := CommandRouter.new(ProfileStore.new(Support.make_dir()), pack, null, RandomNumberGenerator.new(), func() -> int: return Support.T0)
	var lines := router.show_lines(pack.items["win-r-01"]["show"])
	assert_eq(lines[0]["t"], "C:\\Users\\mia> netstat -ano")
	assert_string_contains("\n".join(lines.map(func(l): return l["t"])), "LISTENING       1876")


func test_tool_pages_follow_the_workstation_os() -> void:
	var pack := Pack.load_dir(REAL_PACK)
	var lin_pack := Pack.load_dir(LINUX_PACK)
	var win := TerminalSession.new(pack.labs["lab-office-01"], pack.tool_docs, pack.concept_titles(), {}, null)
	var lin := TerminalSession.new(lin_pack.labs["lab-dmz-01"], lin_pack.tool_docs, lin_pack.concept_titles(), {}, null)
	assert_string_contains("\n".join(win.run("tool ping", Support.T0)["out"]), "-n N")
	assert_false("\n".join(win.run("tool ping", Support.T0)["out"]).contains("-c N"))
	assert_string_contains("\n".join(lin.run("tool ping", Support.T0)["out"]), "-c N")
	assert_string_contains("\n".join(win.run("tool", Support.T0)["out"]), "ipconfig")
	assert_eq(win.run("tool ip", Support.T0)["out"], ["tool: no manual entry for 'ip'"], "a Linux tool has no page on Windows")
	assert_eq(lin.run("tool ipconfig", Support.T0)["out"], ["tool: no manual entry for 'ipconfig'"])


func test_every_windows_show_question_renders() -> void:
	var pack := Pack.load_dir(REAL_PACK)
	var router := CommandRouter.new(ProfileStore.new(Support.make_dir()), pack, null, RandomNumberGenerator.new(), func() -> int: return Support.T0)
	var seen := 0
	for id in pack.items:
		var it: Dictionary = pack.items[id]
		if not it.has("show"):
			continue
		seen += 1
		var lines := router.show_lines(it["show"])
		assert_eq(lines[0]["t"], "C:\\Users\\mia> " + it["show"]["command"], id)
		var joined := "\n".join(lines.map(func(l): return l["t"]))
		assert_true(lines.size() > 1, "%s prints something" % id)
		for refusal in ["not supported", "is not recognized", "unknown command"]:
			assert_false(joined.contains(refusal), "%s: %s" % [id, refusal])
		assert_true(it["answer"].size() == 1 and it["options"].size() == 4, id)
	assert_true(seen >= 20, "the Windows skill has its read-the-output questions")


func test_windows_tool_pages_exist() -> void:
	var pack := Pack.load_dir(REAL_PACK)
	for t in _shell.tool_names_for("windows"):
		assert_true(pack.tool_docs.has(t), "a manual page for %s" % t)
