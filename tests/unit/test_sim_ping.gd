extends GutTest
## The ping emulator: flags, outputs, errors, determinism, and the golden
## comparison with the real iputils ping captured on localhost.

const Support := preload("res://tests/unit/support.gd")
const GOLDEN := "res://tests/golden/"

var _shell: SimShell
var _lab: SimLab


func before_each() -> void:
	_shell = SimShell.new()
	_lab = SimLab.from_data(Support.demo_lab(), "t")


func _run(line: String, lab: SimLab = null) -> Dictionary:
	var l := lab if lab != null else _lab
	var ctx := SimContext.new()
	ctx.lab = l
	ctx.rng = SimNet.rng_for(l.seed_value, line)
	ctx.tool_names = _shell.tool_names()
	return _shell.execute(line, ctx)


func _text(line: String) -> String:
	return "\n".join(_run(line)["out"])


func _count(text: String, needle: String) -> int:
	return text.count(needle)


func test_default_sends_four_then_prints_ctrl_c() -> void:
	var out: Array = _run("ping web-03")["out"]
	assert_eq(out[0], "PING web-03.corp.local (10.20.0.10) 56(84) bytes of data.")
	assert_eq(out.filter(func(l): return (l as String).begins_with("64 bytes")).size(), 4)
	assert_eq(out[5], "^C", "what a real session shows after Ctrl-C")
	assert_eq(out[6], "--- web-03.corp.local ping statistics ---")
	assert_string_contains(out[7], "4 packets transmitted, 4 received, 0% packet loss, time ")
	assert_string_contains(out[8], "rtt min/avg/max/mdev = ")


func test_with_c_there_is_a_blank_line_not_ctrl_c() -> void:
	var out: Array = _run("ping -c 2 10.20.0.10")["out"]
	assert_eq(out[3], "")
	assert_false(out.has("^C"))
	assert_eq(out.size(), 7)


func test_ip_target_shows_no_name_but_a_name_target_does() -> void:
	assert_string_contains(_text("ping -c 1 10.20.0.10"), "64 bytes from 10.20.0.10: icmp_seq=1 ttl=64")
	assert_string_contains(_text("ping -c 1 web-03"), "64 bytes from web-03.corp.local (10.20.0.10): icmp_seq=1")
	assert_string_contains(_text("ping -c 1 www.corp.local"), "PING web-03.corp.local (10.20.0.10)")
	assert_string_contains(_text("ping -c 1 -n web-03"), "64 bytes from 10.20.0.10: icmp_seq=1")


func test_ttl_follows_the_hosts_os() -> void:
	assert_string_contains(_text("ping -c 1 10.20.0.1"), "ttl=255")
	assert_string_contains(_text("ping -c 1 10.20.0.10"), "ttl=64")
	var lab := SimLab.from_data(Support.demo_lab(), "t")
	lab.hosts[2]["os"] = "windows"
	assert_string_contains(_run("ping -c 1 10.20.0.10", lab)["out"][1], "ttl=128")


func test_the_workstation_answers_itself_quickly() -> void:
	var out: String = _text("ping -c 1 analyst-ws")
	assert_string_contains(out, "time=0.0")


func test_size_changes_the_header_and_the_reply_bytes() -> void:
	var out := _text("ping -c 1 -s 100 10.20.0.10")
	assert_string_contains(out, "100(128) bytes of data.")
	assert_string_contains(out, "108 bytes from")


func test_quiet_prints_only_the_statistics() -> void:
	var out: Array = _run("ping -c 2 -q 10.20.0.10")["out"]
	assert_eq(out.size(), 5)
	assert_false(out.any(func(l): return (l as String).begins_with("64 bytes")))


func test_statistics_add_up_and_the_times_are_ordered() -> void:
	var out: Array = _run("ping -c 5 10.20.0.30".replace("0.30", "0.10"))["out"]
	var line: String = out[out.size() - 1]
	var nums := line.trim_prefix("rtt min/avg/max/mdev = ").trim_suffix(" ms").split("/")
	assert_lte(float(nums[0]), float(nums[1]))
	assert_lte(float(nums[1]), float(nums[2]))
	assert_gte(float(nums[3]), 0.0)
	var stats := (out[out.size() - 2] as String)
	assert_string_contains(stats, "5 packets transmitted, 5 received, 0% packet loss, time ")
	var ms := int(stats.get_slice("time ", 1).trim_suffix("ms"))
	assert_between(ms, 4000, 4045, "(count - 1) intervals plus a little")


func test_interval_changes_the_elapsed_time() -> void:
	var stats := (_run("ping -c 3 -i 0.2 10.20.0.10")["out"] as Array)
	var line: String = stats[stats.size() - 2]
	assert_between(int(line.get_slice("time ", 1).trim_suffix("ms")), 400, 445)


func test_the_first_reply_of_a_remote_host_is_the_slowest_on_average() -> void:
	var first := 0.0
	var rest := 0.0
	for i in 20:
		var lab := SimLab.from_data(Support.demo_lab(), "t")
		lab.seed_value = i
		var out: Array = _run("ping -c 2 10.20.0.10", lab)["out"]
		first += float((out[1] as String).get_slice("time=", 1).trim_suffix(" ms"))
		rest += float((out[2] as String).get_slice("time=", 1).trim_suffix(" ms"))
	assert_gt(first, rest)


func test_a_host_that_drops_icmp_times_out_with_100_percent_loss() -> void:
	var r := _run("ping -c 3 printer-01")
	assert_eq(r["out"][0], "PING printer-01.corp.local (10.20.0.30) 56(84) bytes of data.")
	assert_eq(r["out"][1], "")
	assert_eq(r["out"][2], "--- printer-01.corp.local ping statistics ---")
	assert_string_contains(r["out"][3], "3 packets transmitted, 0 received, 100% packet loss, time ")
	assert_eq(r["out"][4], "", "iputils ends a no-reply run with a blank line")
	assert_eq(r["out"].size(), 5)
	assert_eq(r["code"], 1)


func test_an_unused_address_on_the_network_is_unreachable() -> void:
	var r := _run("ping -c 2 10.20.0.99")
	assert_eq(r["out"][1], "From 10.20.0.50 icmp_seq=1 Destination Host Unreachable")
	assert_eq(r["out"][2], "From 10.20.0.50 icmp_seq=2 Destination Host Unreachable")
	var text := "\n".join(r["out"])
	assert_string_contains(text, "2 packets transmitted, 0 received, +2 errors, 100% packet loss, time ")
	assert_string_contains(text, "pipe 2")
	assert_eq(r["code"], 2)


func test_an_address_outside_the_network_just_times_out() -> void:
	var r := _run("ping -c 1 8.8.8.8")
	assert_false("\n".join(r["out"]).contains("Unreachable"))
	assert_string_contains("\n".join(r["out"]), "1 packets transmitted, 0 received, 100% packet loss, time 0ms")


func test_errors() -> void:
	assert_eq(_run("ping")["out"], ["ping: usage error: Destination address required"])
	assert_eq(_run("ping nosuchhost")["out"], ["ping: nosuchhost: Name or service not known"])
	assert_eq(_run("ping nosuchhost")["code"], 2)
	assert_eq(_run("ping -c x 10.20.0.10")["out"], ["ping: invalid argument: 'x'"])
	assert_eq(_run("ping -c 0 10.20.0.10")["out"], ["ping: invalid argument: '0': out of range: 1 <= value <= 9223372036854775807"])
	assert_eq(_run("ping -c")["out"], ["ping: option requires an argument -- 'c'"])
	assert_eq(_run("ping -i x 10.20.0.10")["out"], ["ping: invalid argument: 'x'"])
	assert_eq(_run("ping -s 99999 10.20.0.10")["out"][0], "ping: invalid argument: '99999': out of range: 0 <= value <= 65507")
	assert_eq(_run("ping a b")["out"], ["ping: only one destination is supported in this simulator"])


func test_unsupported_flags_are_named_not_faked() -> void:
	var r := _run("ping -f 10.20.0.10")
	assert_eq(r["out"], ["ping: option '-f' is not supported in this simulator"])
	assert_eq(_run("ping --ttl=3 10.20.0.10")["out"], ["ping: option '--ttl' is not supported in this simulator"])


func test_clustered_and_attached_flags() -> void:
	var out: Array = _run("ping -nc2 web-03")["out"]
	assert_string_contains(out[1], "from 10.20.0.10:")
	assert_eq(out.size(), 7)


func test_same_command_same_text_different_seed_different_times() -> void:
	assert_eq(_run("ping -c 3 10.20.0.10"), _run("ping -c 3 10.20.0.10"))
	var other := SimLab.from_data(Support.demo_lab(), "t")
	other.seed_value = 8
	assert_ne(_run("ping -c 3 10.20.0.10")["out"], _run("ping -c 3 10.20.0.10", other)["out"])
	assert_ne(_run("ping -c 3 10.20.0.10")["out"], _run("ping -c 3 -n 10.20.0.10")["out"])


# --- golden: the emulator against real iputils on localhost ------------------

func _golden_lab() -> SimLab:
	return SimLab.from_data({
		"id": "golden", "title": "localhost", "seed": 1,
		"you": {"ip": "127.0.0.2", "name": "golden-ws", "os": "linux", "user": "tester"},
		"network": {"cidr": "127.0.0.0/8", "gateway": "127.0.0.1"},
		"hosts": [{"ip": "127.0.0.1", "name": "localhost", "os": "linux", "latency_ms": 0.07}],
	}, "golden")


## Same normalisation as tools/golden_capture.sh.
func _normalise(lines: Array) -> String:
	var rules: Array = [["time=[0-9.]+ ms", "time=T ms"], ["time [0-9]+ms", "time Tms"],
			["^rtt min/avg/max/mdev = .* ms", "rtt min/avg/max/mdev = R ms"]]
	var out: Array = []
	for line in lines:
		var l: String = line
		for r in rules:
			var re := RegEx.new()
			re.compile(r[0])
			l = re.sub(l, r[1])
		out.append(l)
	return "\n".join(out) + "\n"


func test_golden_files_exist_and_name_their_tool_version() -> void:
	assert_true(FileAccess.file_exists(GOLDEN + "VERSIONS.txt"))
	assert_string_contains(FileAccess.get_file_as_string(GOLDEN + "VERSIONS.txt"), "iputils")


func test_emulator_matches_the_real_ping_on_localhost() -> void:
	var cases := {
		"ping_ip3": "ping -c 3 127.0.0.1",
		"ping_name": "ping -4 -c 2 localhost",
		"ping_size": "ping -c 2 -s 100 -i 0.2 127.0.0.1",
		"ping_quiet": "ping -c 3 -q 127.0.0.1",
		"ping_numeric": "ping -4 -c 2 -n localhost",
		"ping_nohost": "ping -c 1 nosuchhost.invalid",
		"ping_nodest": "ping",
		"ping_badcount": "ping -c x 127.0.0.1",
		"ping_zerocount": "ping -c 0 127.0.0.1",
		"ping_timeout": "ping -c 1 -W 1 10.255.255.1",
	}
	var lab := _golden_lab()
	assert_true(lab.ok(), "\n".join(lab.errors))
	for file_name in cases:
		var want := FileAccess.get_file_as_string(GOLDEN + file_name + ".txt")
		assert_ne(want, "", file_name)
		assert_eq(_normalise(_run(cases[file_name], lab)["out"]), want, "%s: %s" % [file_name, cases[file_name]])
