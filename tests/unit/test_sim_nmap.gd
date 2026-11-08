extends GutTest
## nmap on the shipped lab and on small labs: what the learner sees, the options,
## the errors. The exact layout is pinned against the real tool in test_sim_golden.

const Support := preload("res://tests/unit/support.gd")
const REAL_PACK := "res://packs/linux-cli"

var _shell := SimShell.new()
var _lab: SimLab


func before_each() -> void:
	_lab = Pack.load_dir(REAL_PACK).labs["lab-dmz-01"]


func _run(line: String, lab: SimLab = null) -> Dictionary:
	var l := lab if lab != null else _lab
	var ctx := SimContext.new()
	ctx.lab = l
	ctx.rng = SimNet.rng_for(l.seed_value, line)
	ctx.now = Support.T0
	ctx.tool_names = _shell.tool_names()
	return _shell.execute(line, ctx)


func _text(line: String, lab: SimLab = null) -> String:
	return "\n".join(_run(line, lab)["out"])


func _small_lab(mutate: Callable) -> SimLab:
	var data := Support.demo_lab()
	mutate.call(data)
	var lab := SimLab.from_data(data, "t")
	assert_true(lab.ok(), "\n".join(lab.errors))
	return lab


func test_default_scan_of_a_host_by_name() -> void:
	var text := _text("nmap web-03")
	assert_string_contains(text, "Starting Nmap 7.99 ( https://nmap.org ) at 2024-10-04 00:00 +0000")
	assert_string_contains(text, "Nmap scan report for web-03 (10.20.0.10)")  # the name as typed
	assert_string_contains(text, "Not shown: 997 closed tcp ports (conn-refused)")
	assert_string_contains(text, "22/tcp open  ssh\n23/tcp open  telnet\n80/tcp open  http")
	assert_string_contains(text, "Nmap done: 1 IP address (1 host up) scanned in ")
	assert_eq(_run("nmap web-03")["code"], 0)


func test_how_the_host_is_named_in_the_report() -> void:
	assert_string_contains(_text("nmap -p 80 10.20.0.10"), "Nmap scan report for web-03.corp.local (10.20.0.10)")
	assert_string_contains(_text("nmap -n -p 80 10.20.0.10"), "Nmap scan report for 10.20.0.10\n")
	assert_string_contains(_text("nmap -p 80 www.corp.local"), "Nmap scan report for www.corp.local (10.20.0.10)")
	assert_string_contains(_text("nmap -n -p 80 web-03"), "Nmap scan report for web-03 (10.20.0.10)")


func test_service_version_detection() -> void:
	var text := _text("nmap -sV -p 80 10.20.0.10")
	assert_string_contains(text, "PORT   STATE SERVICE VERSION\n80/tcp open  http    Apache httpd 2.4.6 ((CentOS))")
	assert_string_contains(text, "Service detection performed. Please report any incorrect results at https://nmap.org/submit/ .")
	var plain := _text("nmap -p 80 10.20.0.10")
	assert_false(plain.contains("Apache"), "without -sV there is no version")
	assert_false(plain.contains("Service detection"))
	assert_string_contains(_text("nmap -sV -p 22,23,80 web-03"), "23/tcp open  telnet\n")


func test_a_sweep_counts_every_address_and_every_live_host() -> void:
	var text := _text("nmap -sn 10.20.0.0/24")
	assert_string_contains(text, "Nmap done: 256 IP addresses (7 hosts up) scanned in ")
	for name in ["fw-01.corp.local (10.20.0.1)", "dns-01.corp.local (10.20.0.2)", "web-03.corp.local (10.20.0.10)",
			"db-02.corp.local (10.20.0.11)", "files-01.corp.local (10.20.0.20)",
			"printer-01.corp.local (10.20.0.30)", "analyst-ws.corp.local (10.20.0.50)"]:
		assert_string_contains(text, "Nmap scan report for " + name)
	assert_eq(text.count("Host is up ("), 7)
	assert_false(text.contains("PORT"))
	assert_string_contains(_text("nmap -sn 10.20.0.0/16"), "65536 IP addresses (7 hosts up)")


func test_a_host_that_drops_ping_is_still_found_by_the_scan() -> void:
	assert_string_contains(_text("ping -c 2 printer-01"), "100% packet loss")
	var text := _text("nmap -sn printer-01")
	assert_string_contains(text, "Nmap scan report for printer-01 (10.20.0.30)")
	assert_string_contains(text, "(1 host up)")
	assert_eq(_text("ping -c 2 10.20.0.30").count("64 bytes"), 0)


func test_finding_the_one_telnet_host() -> void:
	var text := _text("nmap -p 23 --open 10.20.0.0/24")
	assert_eq(text.count("Nmap scan report"), 1)
	assert_string_contains(text, "web-03.corp.local (10.20.0.10)")
	assert_string_contains(text, "23/tcp open  telnet")
	assert_string_contains(text, "256 IP addresses (7 hosts up)")
	var without := _text("nmap -p 23 10.20.0.0/24")
	assert_eq(without.count("Nmap scan report"), 7, "every host that is up is reported")
	assert_eq(without.count("23/tcp closed telnet"), 6)


func test_scanning_the_workstation_hides_what_is_bound_to_loopback() -> void:
	var text := _text("nmap -n 10.20.0.50")
	assert_string_contains(text, "22/tcp open  ssh")
	assert_false(text.contains("5432"), "postgres listens on 127.0.0.1 only")
	assert_string_contains(_text("nmap -n -p 5432 10.20.0.50"), "5432/tcp closed postgresql")


func test_the_default_scan_misses_a_port_outside_the_common_ones() -> void:
	var lab := _small_lab(func(d): d["hosts"][2]["ports"].append({"port": 31337, "service": "Elite"}))
	assert_false(_text("nmap -n 10.20.0.10", lab).contains("31337"))
	assert_string_contains(_text("nmap -n -p 31337 10.20.0.10", lab), "31337/tcp open  Elite")
	assert_string_contains(_text("nmap -n -p- 10.20.0.10", lab), "31337/tcp open  Elite")
	assert_string_contains(_text("nmap -n -p- 10.20.0.10", lab), "Not shown: 65533 closed tcp ports (conn-refused)")


func test_ports_in_ranges_lists_and_names() -> void:
	assert_string_contains(_text("nmap -n -p 22,80 web-03"), "22/tcp open  ssh\n80/tcp open  http")
	assert_string_contains(_text("nmap -n -p22,80 web-03"), "22/tcp open  ssh\n80/tcp open  http")
	assert_string_contains(_text("nmap -n -p ssh,telnet web-03"), "22/tcp open  ssh\n23/tcp open  telnet")
	assert_string_contains(_text("nmap -n -p 1-100 web-03"), "Not shown: 97 closed tcp ports")
	var low := _text("nmap -n -p -25 web-03")
	assert_string_contains(low, "22/tcp open   ssh", "the state column is as wide as 'closed' when closed rows are listed")
	assert_eq(low.count("closed"), 23)
	assert_string_contains(_text("nmap -n -p 79- web-03"), "80/tcp open  http")


func test_more_than_25_ports_in_one_state_are_summarised() -> void:
	var lab := _small_lab(func(d): pass)
	var listed := _text("nmap -n -p 100-124 10.20.0.10", lab)
	assert_false(listed.contains("Not shown"), "25 ports are still listed one by one")
	assert_eq(listed.count("/tcp closed"), 25)
	var folded := _text("nmap -n -p 100-125 10.20.0.10", lab)
	assert_string_contains(folded, "Not shown: 26 closed tcp ports (conn-refused)")
	assert_false(folded.contains("/tcp closed"))
	assert_string_contains(folded, "All 26 scanned ports on 10.20.0.10 are in ignored states.")


func test_a_firewalled_host_shows_filtered_ports() -> void:
	var lab := _small_lab(func(d):
		d["hosts"][2]["default_ports"] = "filtered"
		d["hosts"][2]["ports"] = [{"port": 443, "service": "https"}])
	var text := _text("nmap -n 10.20.0.10", lab)
	assert_string_contains(text, "Not shown: 999 filtered tcp ports (no-response)")
	assert_string_contains(text, "443/tcp open  https")
	var down := _small_lab(func(d):
		d["hosts"][2]["default_ports"] = "filtered"
		d["hosts"][2]["ports"] = [])
	var gone := _text("nmap -n 10.20.0.10", down)
	assert_string_contains(gone, "Note: Host seems down. If it is really up, but blocking our ping probes, try -Pn")
	assert_string_contains(gone, "(0 hosts up)")
	var forced := _text("nmap -n -Pn -p 80 10.20.0.10", down)
	assert_string_contains(forced, "Host is up.\n")
	assert_string_contains(forced, "80/tcp filtered http")


func test_an_address_nobody_uses_is_down_and_a_sweep_is_silent_about_it() -> void:
	var one := _text("nmap 10.20.0.99")
	assert_string_contains(one, "Note: Host seems down.")
	assert_string_contains(one, "1 IP address (0 hosts up)")
	var many := _text("nmap -sn 10.20.0.98-99")
	assert_false(many.contains("Note:"))
	assert_string_contains(many, "2 IP addresses (0 hosts up)")


func test_target_forms() -> void:
	assert_string_contains(_text("nmap -sn 10.20.0.1-2"), "2 IP addresses (2 hosts up)")
	assert_string_contains(_text("nmap -sn 10.20.0.*"), "256 IP addresses (7 hosts up)")
	assert_string_contains(_text("nmap -sn 10.20.0.0/24 10.20.0.50"), "257 IP addresses (7 hosts up)")
	var both := _text("nmap -sn web-03 10.20.0.10")
	assert_eq(both.count("Nmap scan report"), 1, "an address is reported once")
	assert_string_contains(both, "2 IP addresses (1 host up)")
	assert_string_contains(_text("nmap -sn 10.20.0.10/32"), "1 IP address (1 host up)")
	var first := _text("nmap -sn 10.20.0.30 10.20.0.1")
	assert_lt(first.find("10.20.0.30"), first.find("10.20.0.1)"), "targets are reported in the order given")


func test_pn_scans_addresses_that_may_not_exist() -> void:
	var text := _text("nmap -n -Pn -p 80 10.20.0.98-99")
	assert_eq(text.count("Host is up.\n"), 2)
	assert_eq(text.count("80/tcp filtered http"), 2, "an address with no host never answers")
	assert_string_contains(text, "2 IP addresses (2 hosts up)")
	assert_string_contains(_text("nmap -Pn 10.20.0.0/16"), "-Pn on more than 256 addresses is not supported in this simulator")


func test_resolution_failures() -> void:
	var text := _text("nmap nosuch.corp.local")
	assert_string_contains(text, "Failed to resolve \"nosuch.corp.local\".")
	assert_string_contains(text, "WARNING: No targets were specified, so 0 hosts scanned.")
	assert_string_contains(text, "0 IP addresses (0 hosts up)")
	assert_string_contains(_text("nmap 10.20.0.0/8"), "Failed to resolve \"10.20.0.0/8\".")
	assert_string_contains(_text("nmap 10.20.0.300"), "Failed to resolve \"10.20.0.300\".")
	assert_string_contains(_text("nmap -sn"), "WARNING: No targets were specified")


func test_options_that_need_root_are_refused_as_the_real_tool_does() -> void:
	for flag in ["-sS", "-sU", "-sA", "-sF", "-sN", "-sX"]:
		assert_eq(_run("nmap %s web-03" % flag)["out"], ["You requested a scan type which requires root privileges.", "QUITTING!"], flag)
	assert_eq(_run("nmap -O web-03")["out"], ["TCP/IP fingerprinting (for OS scan) requires root privileges.", "QUITTING!"])
	assert_eq(_run("nmap -sS web-03")["code"], 1)


func test_unsupported_options_are_named() -> void:
	for flag in ["-v", "-A", "-F", "-oN", "--script", "--top-ports", "-sL", "-iL", "-R"]:
		var r := _run("nmap %s web-03" % flag)
		assert_eq(r["out"], ["nmap: option '%s' is not supported in this simulator" % flag], flag)
		assert_eq(r["code"], 2)


func test_options_that_change_nothing_are_accepted() -> void:
	assert_eq(_text("nmap -sT -T4 -p 80 web-03").count("80/tcp open"), 1)
	assert_string_contains(_text("nmap -T5 -p 80 web-03"), "80/tcp open")


func test_argument_errors() -> void:
	var usage := _run("nmap")
	assert_string_contains(usage["out"][1], "Usage: nmap [Scan Type(s)] [Options] {target specification}")
	assert_eq(_run("nmap -p")["out"], ["nmap: option requires an argument -- 'p'"])
	assert_string_contains(_text("nmap -p 70000 web-03"), "Ports specified must be between 0 and 65535 inclusive\nQUITTING!")
	assert_string_contains(_text("nmap -p 90-80 web-03"), "Your port specifications are illegal.")
	assert_string_contains(_text("nmap -p nonsense web-03"), "Found no matches for the service mask 'nonsense'")
	assert_string_contains(_text("nmap -sn -p 80 web-03"), "You cannot use -F (fast scan) or -p (explicit port selection) when not doing a port scan\nQUITTING!")


func test_same_command_same_text() -> void:
	assert_eq(_run("nmap web-03"), _run("nmap web-03"))
	assert_eq(_run("nmap -sn 10.20.0.0/24"), _run("nmap -sn 10.20.0.0/24"))


func test_output_pipes_into_grep_and_wc() -> void:
	assert_eq(_run("nmap -p 23 --open 10.20.0.0/24 | grep 'scan report'")["out"].size(), 1)
	assert_eq(_run("nmap -sn 10.20.0.0/24 | grep -c 'scan report'")["out"], ["7"])
	assert_string_contains(_text("nmap -n web-03 | grep open"), "23/tcp open  telnet")


# --- the missions are solvable and have the answers they name -----------------

func test_shipped_missions_have_their_answers_in_the_lab() -> void:
	var pack := Pack.load_dir(REAL_PACK)
	assert_true(pack.ok(), "\n".join(pack.errors))
	var s := TerminalSession.new(pack.labs["lab-dmz-01"], pack.tool_docs, pack.concept_titles(), pack.items["lin-m-03"], Rules.load_default())
	var telnet := "\n".join(s.run("nmap -n --open -p 23 10.20.0.0/24", Support.T0)["out"])
	assert_string_contains(telnet, "Nmap scan report for 10.20.0.10")
	assert_true(s.is_right("10.20.0.10"))
	s = TerminalSession.new(pack.labs["lab-dmz-01"], pack.tool_docs, pack.concept_titles(), pack.items["lin-m-04"], Rules.load_default())
	assert_string_contains("\n".join(s.run("nmap -sV -p 80 web-03", Support.T0)["out"]), "Apache httpd 2.4.6")
	assert_true(s.is_right("Apache httpd 2.4.6"))
	assert_true(s.is_right("2.4.6"))
	assert_false(s.is_right("2.4"))
	s = TerminalSession.new(pack.labs["lab-dmz-01"], pack.tool_docs, pack.concept_titles(), pack.items["lin-m-02"], Rules.load_default())
	assert_string_contains("\n".join(s.run("nmap -sn 10.20.0.0/24", Support.T0)["out"]), "(7 hosts up)")
	assert_true(s.is_right("7"))


func test_when_closed_and_filtered_ports_tie_the_closed_ones_are_summarised() -> void:
	# 30 closed and 30 filtered: both are over the limit and only one state can be
	# folded. Which one the real nmap folds on an exact tie was not captured; the
	# simulator folds the closed ones.
	var lab := _small_lab(func(d):
		var filtered: Array = []
		for p in range(200, 230):
			filtered.append({"port": p, "state": "filtered"})
		d["hosts"][2]["ports"] = filtered)
	var text := _text("nmap -n -p 200-259 10.20.0.10", lab)
	assert_string_contains(text, "Not shown: 30 closed tcp ports (conn-refused)")
	assert_eq(text.count("filtered"), 30, "the 30 filtered ports are listed one by one")
