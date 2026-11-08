extends GutTest
## The lab model and its validator (README "Phase 4 plan").

const Support := preload("res://tests/unit/support.gd")


func _lab(mutate: Callable = Callable()) -> SimLab:
	var data := Support.demo_lab()
	if mutate.is_valid():
		mutate.call(data)
	return SimLab.from_data(data, "labs/test.json")


func _errors(lab: SimLab) -> String:
	return "\n".join(lab.errors)


func test_the_demo_lab_is_valid() -> void:
	var lab := _lab()
	assert_true(lab.ok(), _errors(lab))
	assert_eq(lab.id, "lab-a")
	assert_eq(lab.hosts.size(), 4)
	assert_eq(lab.you["user"], "analyst")


func test_defaults_are_filled_in() -> void:
	var lab := _lab()
	var web := lab.host_at("10.20.0.10")
	assert_eq(web["icmp"], true)
	assert_eq(web["default_ports"], "closed")
	assert_eq(web["ports"][0]["proto"], "tcp")
	assert_eq(lab.host_at("10.20.0.30")["icmp"], false)


func test_you_is_a_host_too() -> void:
	var lab := _lab()
	assert_eq(lab.all_hosts().size(), 5)
	assert_true(lab.host_at("10.20.0.50")["is_you"])
	assert_eq(lab.host_at("10.20.0.99"), {})


func test_name_resolution_and_reverse() -> void:
	var lab := _lab()
	assert_eq(lab.resolve("web-03"), "10.20.0.10", "the search domain is implied")
	assert_eq(lab.resolve("web-03.corp.local"), "10.20.0.10")
	assert_eq(lab.resolve("WEB-03.Corp.Local."), "10.20.0.10", "case and a trailing dot")
	assert_eq(lab.resolve("www.corp.local"), "10.20.0.10", "an explicit alias")
	assert_eq(lab.resolve("nope"), "")
	assert_eq(lab.reverse("10.20.0.10"), "web-03.corp.local")
	assert_eq(lab.reverse("10.20.0.99"), "")
	assert_eq(lab.files_for_you().keys(), ["notes.txt", "scope.txt"])


func test_an_empty_domain_gives_bare_names() -> void:
	var lab := _lab(func(d): d["network"]["domain"] = "")
	assert_eq(lab.fqdn(lab.host_at("10.20.0.10")), "web-03")


func test_ip_outside_the_cidr() -> void:
	var lab := _lab(func(d): d["hosts"][2]["ip"] = "10.21.0.10")
	assert_string_contains(_errors(lab), "is outside 10.20.0.0/24")


func test_duplicate_ip_and_name() -> void:
	assert_string_contains(_errors(_lab(func(d): d["hosts"][2]["ip"] = "10.20.0.30")), "duplicate ip 10.20.0.30")
	assert_string_contains(_errors(_lab(func(d): d["hosts"][2]["name"] = "fw-01")), "duplicate host name 'fw-01'")
	assert_string_contains(_errors(_lab(func(d): d["hosts"][2]["ip"] = "10.20.0.50")), "duplicate ip 10.20.0.50")


func test_bad_ports() -> void:
	var p := func(port: Dictionary) -> SimLab:
		return _lab(func(d): d["hosts"][2]["ports"] = [port])
	assert_string_contains(_errors(p.call({"port": 0})), "1 to 65535")
	assert_string_contains(_errors(p.call({"port": 65536})), "1 to 65535")
	assert_string_contains(_errors(p.call({"port": 80, "state": "ajar"})), "unknown state 'ajar'")
	assert_string_contains(_errors(p.call({"port": 80, "proto": "icmp"})), "unknown proto 'icmp'")
	var twice := _lab(func(d): d["hosts"][2]["ports"] = [{"port": 80}, {"port": 80}])
	assert_string_contains(_errors(twice), "port 80/tcp listed twice")
	var both := _lab(func(d): d["hosts"][2]["ports"] = [{"port": 53}, {"port": 53, "proto": "udp"}])
	assert_true(both.ok(), _errors(both))


func test_dns_must_point_at_a_host() -> void:
	var lab := _lab(func(d): d["dns"] = [{"name": "ghost.corp.local", "a": "10.20.0.77"}])
	assert_string_contains(_errors(lab), "points at 10.20.0.77, which is not a host")


func test_gateway_and_dns_must_be_hosts_inside_the_network() -> void:
	assert_string_contains(_errors(_lab(func(d): d["network"]["gateway"] = "10.20.0.99")), "gateway 10.20.0.99 is not a host")
	assert_string_contains(_errors(_lab(func(d): d["network"]["gateway"] = "10.99.0.1")), "must be an address inside")
	assert_string_contains(_errors(_lab(func(d): d["network"]["dns"] = "10.20.0.77")), "dns 10.20.0.77 is not a host")
	assert_true(_lab(func(d): d["network"].erase("dns")).ok(), "dns is optional")


func test_bad_cidr_and_missing_pieces() -> void:
	assert_string_contains(_errors(_lab(func(d): d["network"]["cidr"] = "10.20.0.0")), "must look like 10.20.0.0/24")
	assert_string_contains(_errors(_lab(func(d): d["network"]["cidr"] = "10.20.0.0/31")), "must look like")
	assert_string_contains(_errors(_lab(func(d): d.erase("network"))), "'network' must be an object")
	assert_string_contains(_errors(_lab(func(d): d["hosts"] = [])), "'hosts' must be a non-empty array")
	assert_string_contains(_errors(_lab(func(d): d.erase("you"))), "'you' must be an object")
	assert_string_contains(_errors(_lab(func(d): d["id"] = "")), "'id' must be a non-empty string")


func test_more_than_254_hosts() -> void:
	var lab := _lab(func(d):
		d["network"] = {"cidr": "10.20.0.0/16", "gateway": "10.20.0.1", "domain": "corp.local"}
		d["hosts"] = [d["hosts"][0]]
		d["dns"] = []
		d["files"] = {}
		for i in range(2, 257):
			d["hosts"].append({"ip": "10.20.1.%d" % (i - 1) if i < 256 else "10.20.2.1", "name": "h%d" % i}))
	assert_string_contains(_errors(lab), "more than 254 hosts")


func test_host_field_checks() -> void:
	assert_string_contains(_errors(_lab(func(d): d["hosts"][2]["name"] = "Web_03")), "lower-case letters, digits and hyphens")
	assert_string_contains(_errors(_lab(func(d): d["hosts"][2]["latency_ms"] = 0)), "'latency_ms' must be")
	assert_string_contains(_errors(_lab(func(d): d["hosts"][2]["icmp"] = "no")), "'icmp' must be true or false")
	assert_string_contains(_errors(_lab(func(d): d["hosts"][2]["os"] = "plan9")), "unknown os 'plan9'")
	assert_string_contains(_errors(_lab(func(d): d["hosts"][2]["default_ports"] = "open")), "closed or filtered")
	assert_string_contains(_errors(_lab(func(d): d["hosts"][2]["ip"] = "10.20.0.300")), "'ip' must be a dotted address")


func test_the_workstation_runs_linux_windows_or_kali() -> void:
	assert_true(_lab(func(d): d["you"]["os"] = "windows").ok())
	assert_true(_lab(func(d): d["you"]["os"] = "kali").ok())
	assert_string_contains(_errors(_lab(func(d): d["you"]["os"] = "network")), "workstation runs linux, windows or kali")


func test_files_must_belong_to_a_host_and_be_text() -> void:
	assert_string_contains(_errors(_lab(func(d): d["files"]["ghost"] = {"a": "b"})), "files for unknown host 'ghost'")
	assert_string_contains(_errors(_lab(func(d): d["files"]["analyst-ws"]["x"] = 5)), "must be text")


func test_address_helpers() -> void:
	assert_eq(SimNet.parse_ip("10.20.0.50"), (10 << 24) + (20 << 16) + 50)
	assert_eq(SimNet.ip_string(SimNet.parse_ip("192.168.1.9")), "192.168.1.9")
	for bad in ["", "1.2.3", "1.2.3.4.5", "256.1.1.1", "1.2.3.-4", "01.2.3.4", "a.b.c.d", "1.2.3."]:
		assert_eq(SimNet.parse_ip(bad), -1, bad)
	var c := SimNet.parse_cidr("10.20.0.77/24")
	assert_eq(SimNet.ip_string(c["base"]), "10.20.0.0", "the base is masked")
	assert_true(SimNet.in_cidr(SimNet.parse_ip("10.20.0.255"), c))
	assert_false(SimNet.in_cidr(SimNet.parse_ip("10.20.1.0"), c))
	assert_true(SimNet.in_cidr(SimNet.parse_ip("127.9.9.9"), SimNet.parse_cidr("127.0.0.0/8")))


func test_rng_is_deterministic_per_seed_and_text() -> void:
	var a := SimNet.rng_for(7, "ping x").randf()
	assert_eq(SimNet.rng_for(7, "ping x").randf(), a)
	assert_ne(SimNet.rng_for(8, "ping x").randf(), a)
	assert_ne(SimNet.rng_for(7, "ping y").randf(), a)
