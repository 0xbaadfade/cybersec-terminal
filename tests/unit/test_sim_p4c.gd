extends GutTest
## P4c: the lab's name server and web servers, and dig, nslookup, curl and ip.
## The output layouts are pinned to the real tools in test_sim_golden_p4c.gd;
## this file tests the rules around them: the lab model, error and refusal
## texts, the shipped missions and the questions that show a command's output.

const Support := preload("res://tests/unit/support.gd")
const REAL_PACK := "res://packs/linux-cli"

var _shell := SimShell.new()
var _dir := ""


func before_each() -> void:
	_dir = Support.make_dir()


func after_each() -> void:
	Support.remove_dir(_dir)


func _data(mutate: Callable = Callable()) -> Dictionary:
	var d := Support.demo_lab()
	d["dns"] = [
		{"name": "www.corp.local", "type": "CNAME", "value": "web-03.corp.local"},
		{"name": "corp.local", "type": "MX", "value": "10 web-03.corp.local"},
		{"name": "corp.local", "type": "TXT", "value": "v=spf1 -all"}]
	d["hosts"][2]["ports"].append({"port": 80, "http": {"server": "Apache/2.4.6", "headers": {"X-Test": "1"},
			"pages": {"/": {"body": "hello\n"}, "/gone": {"status": 404, "body": ""}}}})
	d["hosts"][2]["ports"].append({"port": 8443, "service": "https-alt"})
	d["hosts"][3]["ports"] = [{"port": 80, "state": "open"}]
	d["hosts"].append({"ip": "10.20.0.40", "name": "dark-01", "default_ports": "filtered"})
	if mutate.is_valid():
		mutate.call(d)
	return d


func _lab(mutate: Callable = Callable()) -> SimLab:
	var lab := SimLab.from_data(_data(mutate), "labs/test.json")
	assert_true(lab.ok(), "\n".join(lab.errors))
	return lab


func _errors(mutate: Callable) -> String:
	return "\n".join(SimLab.from_data(_data(mutate), "labs/test.json").errors)


func _run(line: String, lab: SimLab = null) -> Dictionary:
	var ctx := SimContext.new()
	ctx.lab = lab if lab != null else _lab()
	ctx.rng = SimNet.rng_for(ctx.lab.seed_value, line)
	ctx.now = Support.T0
	ctx.tool_names = _shell.tool_names()
	return _shell.execute(line, ctx)


func _text(line: String, lab: SimLab = null) -> String:
	return "\n".join(_run(line, lab)["out"])


# --- the lab model -------------------------------------------------------------

func test_the_name_server_holds_host_alias_reverse_and_apex_records() -> void:
	var lab := _lab()
	assert_eq(lab.records_at("web-03.corp.local")[0], {"name": "web-03.corp.local", "type": "A", "value": "10.20.0.10", "ttl": 3600})
	assert_eq(lab.records_at("www.corp.local")[0]["type"], "CNAME")
	assert_eq(lab.records_at("10.0.20.10.in-addr.arpa")[0], {"name": "10.0.20.10.in-addr.arpa", "type": "PTR", "value": "web-03.corp.local", "ttl": 3600})
	var apex := lab.records_at("corp.local")
	var types: Array = apex.map(func(r): return r["type"])
	types.sort()
	assert_eq(types, ["MX", "NS", "SOA", "TXT"])
	assert_eq(lab.records_at("nope.corp.local"), [])
	assert_eq(lab.records_at("example.com"), [], "outside both zones")


func test_resolve_follows_an_alias_and_old_style_records_still_load() -> void:
	assert_eq(_lab().resolve("www.corp.local"), "10.20.0.10")
	var old := SimLab.from_data(Support.demo_lab(), "labs/test.json")
	assert_true(old.ok(), "\n".join(old.errors))
	assert_eq(old.resolve("www.corp.local"), "10.20.0.10")


func test_reverse_zone_follows_the_prefix() -> void:
	assert_eq(_lab().reverse_zone(), "0.20.10.in-addr.arpa")
	assert_eq(_lab(func(d): d["network"]["cidr"] = "10.20.0.0/16").reverse_zone(), "20.10.in-addr.arpa")


func test_the_workstation_mac_is_given_or_derived() -> void:
	assert_eq(_lab().you_mac(), "52:54:00:14:00:32")
	assert_eq(_lab(func(d): d["you"]["mac"] = "AA:bb:cc:00:11:22").you_mac(), "aa:bb:cc:00:11:22")
	assert_string_contains(_errors(func(d): d["you"]["mac"] = "12:34"), "you.mac")


func test_dns_record_rules() -> void:
	assert_string_contains(_errors(func(d): d["dns"].append({"name": "x.corp.local", "type": "SRV", "value": "x"})), "type SRV")
	assert_string_contains(_errors(func(d): d["dns"].append({"name": "x.example.org", "type": "TXT", "value": "x"})), "outside the lab domain")
	assert_string_contains(_errors(func(d): d["dns"].append({"name": "x.corp.local", "type": "CNAME", "value": "nowhere.corp.local"})), "does not know")
	assert_string_contains(_errors(func(d): d["dns"].append({"name": "corp.local", "type": "MX", "value": "web-03"})), "looks like '10 mail-01.corp.local'")
	assert_string_contains(_errors(func(d): d["dns"].append({"name": "x.corp.local", "type": "TXT"})), "needs a value")
	assert_string_contains(_errors(func(d): d["dns"].append({"name": "x.corp.local", "type": "TXT", "value": "x", "ttl": 0})), "ttl")
	assert_string_contains(_errors(func(d): d["dns"].append({"name": "web-03.corp.local", "type": "CNAME", "value": "dns-01.corp.local"})), "must stand alone")
	assert_string_contains(_errors(func(d): d["dns"].append({"name": "www.corp.local", "type": "TXT", "value": "x"})), "must stand alone")


func test_http_block_rules() -> void:
	var web := func(d, http): d["hosts"][2]["ports"][1]["http"] = http
	assert_string_contains(_errors(func(d): web.call(d, {"headers": {"Date": "x"}})), "written by the simulator")
	assert_string_contains(_errors(func(d): web.call(d, {"pages": {"/": {"headers": {"Content-Length": "3"}}}})), "written by the simulator")
	assert_string_contains(_errors(func(d): web.call(d, {"pages": {"index": {}}})), "path starting with /")
	assert_string_contains(_errors(func(d): web.call(d, {"pages": {"/": {"status": 777}}})), "status 777")
	assert_string_contains(_errors(func(d): web.call(d, {"pages": {"/": {"body": 5}}})), "'body' and 'type' must be text")
	assert_string_contains(_errors(func(d): web.call(d, "yes")), "must be an object")
	assert_string_contains(_errors(func(d): d["hosts"][2]["ports"][2].merge({"state": "closed", "http": {}})), "has an 'http' block but is not an open tcp port")


# --- the name server ------------------------------------------------------------

func test_query_outcomes() -> void:
	var lab := _lab()
	var res := SimDns.query(lab, "example.com", "A")
	assert_eq(res["status"], "SERVFAIL")
	assert_false(res["aa"])
	res = SimDns.query(lab, "nope.corp.local", "A")
	assert_eq(res["status"], "NXDOMAIN")
	assert_eq(res["authority"][0]["type"], "SOA")
	assert_eq(res["authority"][0]["ttl"], 300, "negative answers carry the SOA minimum")
	res = SimDns.query(lab, "web-03.corp.local", "MX")
	assert_eq(res["status"], "NOERROR", "the name exists, there is no MX: an empty answer, not NXDOMAIN")
	assert_eq(res["answer"], [])
	assert_eq(res["authority"].size(), 1)
	res = SimDns.query(lab, "www.corp.local", "A")
	assert_eq(res["answer"].map(func(r): return r["type"]), ["CNAME", "A"])
	res = SimDns.query(lab, "corp.local", "MX")
	assert_eq(res["additional"].size(), 1, "the MX host's address comes along")
	res = SimDns.query(lab, "www.corp.local", "CNAME")
	assert_eq(res["answer"].size(), 1, "asking for the CNAME itself stops there")


func test_a_name_server_answer_is_authoritative_in_both_zones() -> void:
	var lab := _lab()
	assert_true(SimDns.query(lab, "web-03.corp.local", "A")["aa"])
	assert_true(SimDns.query(lab, "10.0.20.10.in-addr.arpa", "PTR")["aa"])


# --- dig ------------------------------------------------------------------------

func test_dig_short_prints_only_the_data() -> void:
	assert_eq(_run("dig +short web-03.corp.local")["out"], ["10.20.0.10"])
	assert_eq(_run("dig +short www.corp.local")["out"], ["web-03.corp.local.", "10.20.0.10"])
	assert_eq(_run("dig +short nope.corp.local")["out"], [])
	assert_eq(_run("dig +short -x 10.20.0.30")["out"], ["printer-01.corp.local."])
	assert_eq(_run("dig +short corp.local TXT")["out"], ["\"v=spf1 -all\""])


func test_dig_type_can_come_after_the_name_or_after_t() -> void:
	assert_eq(_run("dig +short corp.local mx")["out"], _run("dig +short -t MX corp.local")["out"])
	assert_eq(_run("dig +short corp.local MX")["out"], ["10 web-03.corp.local."])


func test_dig_shows_the_question_as_typed_and_names_a_server_by_its_name() -> void:
	var text := _text("dig @dns-01 WEB-03.corp.local")
	assert_string_contains(text, ";WEB-03.corp.local.")
	assert_string_contains(text, "; (1 server found)")
	assert_string_contains(text, ";; SERVER: 10.20.0.2#53(dns-01) (UDP)")


func test_dig_refusals_and_errors() -> void:
	assert_eq(_run("dig +trace web-03")["out"], ["dig: option '+trace' is not supported in this simulator"])
	assert_eq(_run("dig -4 web-03")["out"], ["dig: option '-4' is not supported in this simulator"])
	assert_string_contains(_text("dig"), "a name to look up is required")
	assert_string_contains(_text("dig web-03 ANY"), "ANY is not supported")
	assert_string_contains(_text("dig a b c"), "only one query per command")
	assert_eq(_run("dig -x")["code"], 1)
	assert_string_contains(_text("dig -x fe80::1"), "IPv6 addresses are not supported")
	assert_eq(_run("dig @nosuch.invalid web-03")["out"], ["dig: couldn't get address for 'nosuch.invalid': not found"])


func test_dig_an_unanswering_server_times_out_and_a_host_without_dns_refuses() -> void:
	assert_string_contains(_text("dig @10.20.0.77 web-03"), "communications error to 10.20.0.77#53: timed out")
	assert_string_contains(_text("dig @10.20.0.10 web-03"), "communications error to 10.20.0.10#53: connection refused")
	assert_eq(_run("dig @10.20.0.10 web-03")["code"], 9)


func test_dig_and_nslookup_answers_are_the_same_data_and_repeatable() -> void:
	assert_eq(_run("dig web-03.corp.local")["out"], _run("dig web-03.corp.local")["out"])
	var dig := _text("dig -x 10.20.0.50 +short")
	assert_eq(dig, "analyst-ws.corp.local.")
	assert_string_contains(_text("nslookup 10.20.0.50"), "name = analyst-ws.corp.local.")


# --- nslookup -------------------------------------------------------------------

func test_nslookup_adds_the_search_domain_to_a_bare_name_only() -> void:
	assert_string_contains(_text("nslookup web-03"), "Name:\tweb-03.corp.local")
	var missing := _text("nslookup nosuch")
	assert_string_contains(missing, "SERVFAIL", "after the search domain fails the bare name goes to the server")
	assert_string_contains(missing, "can't find nosuch:")
	assert_string_contains(_text("nslookup nosuch.corp.local"), "can't find nosuch.corp.local: NXDOMAIN")


func test_nslookup_refusals() -> void:
	assert_string_contains(_text("nslookup"), "interactive mode is not supported")
	assert_eq(_run("nslookup -debug web-03")["out"], ["nslookup: option '-debug' is not supported in this simulator"])
	assert_string_contains(_text("nslookup -type=ANY web-03"), "not supported in this simulator")
	assert_string_contains(_text("nslookup web-03 dns-01"), "must be an address")
	assert_string_contains(_text("nslookup a b c"), "too many arguments")
	assert_string_contains(_text("nslookup web-03 10.20.0.99"), "timed out")
	assert_string_contains(_text("nslookup web-03 10.20.0.10"), "connection refused")


func test_nslookup_record_types() -> void:
	assert_string_contains(_text("nslookup -type=MX corp.local"), "corp.local\tmail exchanger = 10 web-03.corp.local.")
	assert_string_contains(_text("nslookup -q=TXT corp.local"), "text = \"v=spf1 -all\"")
	assert_string_contains(_text("nslookup -type=SOA corp.local"), "\tserial = 2026110501")
	assert_string_contains(_text("nslookup -type=AAAA web-03.corp.local"), "*** Can't find web-03.corp.local: No answer")


# --- curl -----------------------------------------------------------------------

func test_curl_reads_the_lab_web_server() -> void:
	var head: Array = _run("curl -I http://web-03")["out"]
	assert_eq(head[0], "HTTP/1.1 200 OK")
	assert_true(head.has("Server: Apache/2.4.6"))
	assert_true(head.has("X-Test: 1"))
	assert_true(head.has("Content-Length: 6"))
	assert_eq(head[-1], "", "headers end with a blank line")
	assert_eq(_run("curl http://web-03")["out"], ["hello"])
	assert_eq(_run("curl -i http://web-03")["out"].slice(-2), ["", "hello"])
	assert_eq(_run("curl --head http://web-03")["out"], head)


func test_curl_pages_and_missing_pages() -> void:
	assert_eq(_run("curl -I http://web-03/gone")["out"][0], "HTTP/1.1 404 Not Found")
	assert_eq(_run("curl -I http://web-03/nothing-here")["out"][0], "HTTP/1.1 404 Not Found", "an unlisted path is a 404")
	assert_eq(_run("curl http://web-03/?x=1")["out"], ["hello"], "the query string is not part of the page")
	assert_eq(_run("curl http://web-03/gone")["out"], [])


func test_curl_connection_failures_and_exit_codes() -> void:
	assert_string_contains(_text("curl -I http://dns-01"), "curl: (7) Failed to connect to dns-01:80")
	assert_eq(_run("curl -I http://dns-01")["code"], 7)
	assert_eq(_run("curl -I http://nosuch.corp.local")["out"], ["curl: (6) Could not resolve host: nosuch.corp.local"])
	assert_eq(_run("curl -I http://nosuch.corp.local")["code"], 6)
	assert_eq(_run("curl -I http://10.20.0.30")["out"], ["curl: (52) Empty reply from server"], "open port, no web server")
	assert_string_contains(_text("curl -I http://10.20.0.40"), "curl: (28) Failed to connect to 10.20.0.40:80 after 13")
	assert_eq(_run("curl http://web-03:8443/")["out"], ["curl: (52) Empty reply from server"])


func test_curl_timeouts_stop_the_wait() -> void:
	assert_string_contains(_text("curl -I --connect-timeout 2 http://10.20.0.40"), "curl: (28) Connection timed out after 20")
	assert_string_contains(_text("curl -I -m 1 http://10.20.0.99"), "curl: (28) Connection timed out after 10")
	assert_string_contains(_text("curl -I -m 10 http://10.20.0.99"), "curl: (7) Failed to connect to 10.20.0.99:80 after 3", "a timeout longer than the wait changes nothing")
	assert_string_contains(_text("curl -I -m abc http://web-03"), "expected a proper numerical parameter")


func test_curl_quiet_hides_the_error_but_keeps_the_code() -> void:
	assert_eq(_run("curl -s -I http://dns-01")["out"], [])
	assert_eq(_run("curl -s -I http://dns-01")["code"], 7)
	assert_string_contains(_text("curl -sS -I http://dns-01"), "curl: (7)")


func test_curl_refusals() -> void:
	assert_eq(_run("curl -L http://web-03")["out"], ["curl: option '-L' is not supported in this simulator"])
	assert_eq(_run("curl -v http://web-03")["out"], ["curl: option '-v' is not supported in this simulator"])
	assert_eq(_run("curl")["out"], ["curl: try 'curl --help' for more information"])
	assert_eq(_run("curl ftp://web-03")["out"], ["curl: (1) Protocol \"ftp\" not supported"])
	assert_string_contains(_text("curl http://web-03 http://dns-01"), "only one URL")
	assert_string_contains(_text("curl -I https://web-03:8443"), "https is not simulated")
	assert_string_contains(_text("curl -I https://web-03"), "curl: (7) Failed to connect to web-03:443")
	assert_string_contains(_text("curl http://web-03:99999/"), "URL rejected")


func test_a_loopback_only_port_is_closed_from_the_network() -> void:
	var lab := _lab(func(d): d["you"]["ports"] = [{"port": 8080, "bind": "127.0.0.1", "http": {"pages": {"/": {"body": "x\n"}}}},
			{"port": 8081, "http": {"pages": {"/": {"body": "y\n"}}}}])
	assert_string_contains(_text("curl http://10.20.0.50:8080/", lab), "curl: (7)")
	assert_eq(_run("curl http://10.20.0.50:8081/", lab)["out"], ["y"])


# --- ip -------------------------------------------------------------------------

func test_ip_abbreviations_and_views() -> void:
	assert_eq(_run("ip a")["out"], _run("ip address show")["out"])
	assert_eq(_run("ip addr list")["out"], _run("ip address")["out"])
	assert_eq(_run("ip r")["out"], _run("ip route show")["out"])
	assert_eq(_run("ip l")["out"], _run("ip link show")["out"])
	assert_eq(_run("ip -br a show dev eth0")["out"].size(), 1)
	assert_eq(_run("ip -brief address")["out"], _run("ip -br a")["out"])


func test_ip_reads_the_lab() -> void:
	var lab := _lab(func(d): d["you"]["mac"] = "52:54:00:a3:7c:19")
	var text := _text("ip addr show eth0", lab)
	assert_string_contains(text, "link/ether 52:54:00:a3:7c:19 brd ff:ff:ff:ff:ff:ff")
	assert_string_contains(text, "inet 10.20.0.50/24 brd 10.20.0.255 scope global eth0")
	assert_string_contains(text, "inet6 fe80::5054:ff:fea3:7c19/64 scope link")
	assert_eq(_run("ip route", lab)["out"][0], "default via 10.20.0.1 dev eth0")
	var wide := _lab(func(d): d["network"]["cidr"] = "10.20.0.0/16")
	assert_string_contains(_text("ip a", wide), "inet 10.20.0.50/16 brd 10.20.255.255")
	assert_eq(_run("ip route", wide)["out"][1], "10.20.0.0/16 dev eth0 proto kernel scope link src 10.20.0.50")


func test_ip_refusals_and_errors() -> void:
	assert_eq(_run("ip frobnicate")["out"], ["Object \"frobnicate\" is unknown, try \"ip help\"."])
	assert_eq(_run("ip addr show dev eth9")["out"], ["Device \"eth9\" does not exist."])
	assert_eq(_run("ip -6 addr")["out"], ["ip: option '-6' is not supported in this simulator"])
	assert_string_contains(_text("ip addr add 10.1.1.1/24 dev eth0"), "changes the system")
	assert_string_contains(_text("ip route del default"), "changes the system")
	assert_string_contains(_text("ip neigh"), "is not supported in this simulator")
	assert_string_contains(_text("ip route get 10.1.1.1"), "is not supported in this simulator")
	assert_eq(_run("ip")["code"], 255)
	assert_string_contains(_text("ip"), "Usage: ip [ OPTIONS ] OBJECT")


# --- the shipped missions and the questions that show output ---------------------

func _session(pack: Pack, id: String) -> TerminalSession:
	return TerminalSession.new(pack.labs["lab-dmz-01"], pack.tool_docs, pack.concept_titles(), pack.items[id], Rules.load_default())


func _out(s: TerminalSession, line: String) -> String:
	return "\n".join(s.run(line, Support.T0)["out"])


func test_the_p4c_missions_have_their_answers_in_the_lab() -> void:
	var pack := Pack.load_dir(REAL_PACK)
	assert_true(pack.ok(), "\n".join(pack.errors))
	var s := _session(pack, "lin-m-10")
	assert_string_contains(_out(s, "curl -I http://web-03"), "X-Powered-By: PHP/5.4.16")
	assert_true(s.is_right("PHP/5.4.16"))
	assert_true(s.is_right("php 5.4.16"))
	assert_false(s.is_right("php"), "the version is part of the answer")
	s = _session(pack, "lin-m-07")
	assert_string_contains(_out(s, "dig -x 10.20.0.30 +short"), "printer-01.corp.local.")
	assert_string_contains(_out(s, "nslookup 10.20.0.30"), "name = printer-01.corp.local.")
	assert_true(s.is_right("printer-01.corp.local"))
	s = _session(pack, "lin-m-06")
	assert_string_contains(_out(s, "dig www.corp.local"), "www.corp.local.\t\t3600\tIN\tCNAME\tweb-03.corp.local.")
	assert_true(s.is_right("web-03.corp.local"))
	s = _session(pack, "lin-m-05")
	assert_string_contains(_out(s, "nslookup web-03"), "Server:\t\t10.20.0.2")
	assert_eq(_out(s, "dig +short -x 10.20.0.2"), "dns-01.corp.local.")
	assert_true(s.is_right("dns-01"))
	s = _session(pack, "lin-m-08")
	assert_string_contains(_out(s, "ip link"), "link/ether 52:54:00:a3:7c:19")
	assert_true(s.is_right("52:54:00:A3:7C:19"), "case does not matter")


func test_every_shipped_show_question_renders_its_command() -> void:
	var pack := Pack.load_dir(REAL_PACK)
	var router := CommandRouter.new(ProfileStore.new(Support.make_dir()), pack, null, RandomNumberGenerator.new(), func() -> int: return Support.T0)
	var checks := {
		"lin-r-01": "X-Powered-By: PHP/5.4.16",
		"lin-r-02": "CNAME\tweb-03.corp.local.",
		"lin-r-03": "23/tcp open  telnet",
	}
	var seen := 0
	for id in pack.items:
		var it: Dictionary = pack.items[id]
		if not it.has("show"):
			continue
		seen += 1
		var lines := router.show_lines(it["show"])
		assert_eq(lines[0]["t"], "analyst@analyst-ws$ " + it["show"]["command"], id)
		var joined := "\n".join(lines.map(func(l): return l["t"]))
		if checks.has(id):
			assert_string_contains(joined, checks[id])
		# Every question's command must really run: output, and no refusal.
		assert_true(lines.size() > 1, "%s prints something" % id)
		for refusal in ["not supported", "command not found", "unknown command", "not recognized"]:
			assert_false(joined.contains(refusal), "%s: %s" % [id, refusal])
		assert_true(it["answer"].size() == 1 and it["options"].size() == 4, id)
	assert_true(seen >= checks.size(), "the three checked questions are in the pack")
	for id in checks:
		assert_true(pack.items.has(id), id)


func test_show_must_name_a_lab_and_a_command() -> void:
	for show in [{"lab": "nowhere", "command": "ping x"}, {"lab": "lab-a"}, "ping x", {"lab": "lab-a", "command": " "}]:
		var item := Support.good_item("s-1")
		item["show"] = show
		Support.write_lab_pack(_dir, [item])
		var pack := Pack.load_dir(_dir)
		assert_false(pack.ok(), "show %s should be refused" % [show])
		assert_string_contains("\n".join(pack.errors), "'show'")
	var good := Support.good_item("s-2")
	good["show"] = {"lab": "lab-a", "command": "ping -c 1 web-03"}
	Support.write_lab_pack(_dir, [good])
	var ok_pack := Pack.load_dir(_dir)
	assert_true(ok_pack.ok(), "\n".join(ok_pack.errors))


func test_an_encounter_prints_the_shown_output_under_the_stem() -> void:
	var item := Support.make_item("s-1", "1.1.a")
	item["show"] = {"lab": "lab-a", "command": "ping -c 1 web-03"}
	Support.write_lab_pack(_dir, [item])
	var profiles := Support.make_dir()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var router := CommandRouter.new(ProfileStore.new(profiles), Pack.load_dir(_dir), null, rng, func() -> int: return Support.T0)
	router.handle("new dana")
	var text := "\n".join(router.handle("breach 1.1").map(func(l): return l.get("t", "")))
	Support.remove_dir(profiles)
	assert_string_contains(text, "Stem of s-1.")
	assert_string_contains(text, "analyst@analyst-ws$ ping -c 1 web-03")
	assert_string_contains(text, "64 bytes from web-03.corp.local (10.20.0.10)")
	assert_true(text.find("64 bytes from") < text.find("  A  "), "the output comes before the options")
