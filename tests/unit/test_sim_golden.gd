extends GutTest
## The nmap, ss and netstat emulators against the real tools. tests/golden/ holds
## normalised captures taken inside an empty network namespace on this machine
## (tools/golden_capture.sh); each lab below mirrors that environment.

const GOLDEN := "res://tests/golden/"

var _shell := SimShell.new()


func _run(line: String, lab: SimLab) -> Array:
	var ctx := SimContext.new()
	ctx.lab = lab
	ctx.rng = SimNet.rng_for(lab.seed_value, line)
	ctx.now = 1730000000
	ctx.tool_names = _shell.tool_names()
	return _shell.execute(line, ctx)["out"]


func _golden(name: String) -> String:
	return FileAccess.get_file_as_string(GOLDEN + name + ".txt")


func _sub(text: String, pattern: String, with: String) -> String:
	var re := RegEx.new()
	re.compile(pattern)
	return re.sub(text, with, true)


# --- nmap ----------------------------------------------------------------

## 127.0.0.1 listens on 22, 23, 80 (and 8080 is dropped by the firewall);
## 127.0.0.5 drops ports 80 and 443; 127.0.0.6 drops everything but 443.
func _nmap_lab() -> SimLab:
	var hosts: Array = []
	for n in [0, 2, 3, 4, 7]:
		hosts.append({"ip": "127.0.0.%d" % n, "name": "h%d" % n, "latency_ms": 0.1})
	hosts.append({"ip": "127.0.0.1", "name": "localhost", "latency_ms": 0.1, "ports": [
		{"port": 22, "service": "ssh"}, {"port": 23, "service": "telnet"},
		{"port": 80, "service": "http", "version": "SimpleHTTPServer 0.6 (Python 3.13.17)"},
		{"port": 8080, "state": "filtered", "service": "http-proxy"}]})
	hosts.append({"ip": "127.0.0.5", "name": "h5", "latency_ms": 0.1, "default_ports": "filtered"})
	hosts.append({"ip": "127.0.0.6", "name": "h6", "latency_ms": 0.1, "default_ports": "filtered",
			"ports": [{"port": 443, "service": "https"}]})
	var lab := SimLab.from_data({
		"id": "golden-nmap", "title": "namespace", "seed": 1,
		"you": {"ip": "127.0.0.250", "name": "golden-ws", "os": "linux", "user": "tester"},
		"network": {"cidr": "127.0.0.0/8", "gateway": "127.0.0.1"},
		"hosts": hosts}, "golden")
	assert_true(lab.ok(), "\n".join(lab.errors))
	return lab


## The same normalisation as tools/golden/nmap_env.sh.
func _norm_nmap(lines: Array) -> String:
	var text := "\n".join(lines) + "\n"
	text = _sub(text, " at [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9:]{5} \\+0000\n", " at D\n")
	text = _sub(text, "\\([0-9.]+s latency\\)", "(Ls latency)")
	text = _sub(text, "scanned in [0-9.]+ seconds", "scanned in Ts seconds")
	return _sub(text, "SimpleHTTPServer 0\\.6 \\(Python [0-9.]+\\)", "PYHTTP")


const NMAP_CASES := {
	"nmap_default": "nmap 127.0.0.1",
	"nmap_p80": "nmap -p 80 127.0.0.1",
	"nmap_mixed": "nmap -p 22,80,443,8080 127.0.0.1",
	"nmap_range30": "nmap -p 70-100 127.0.0.1",
	"nmap_sv": "nmap -sV -p 80 127.0.0.1",
	"nmap_sv_closed": "nmap -n -sV -p 443 127.0.0.1",
	"nmap_sn_one": "nmap -sn 127.0.0.1",
	"nmap_sn_sweep": "nmap -n -sn 127.0.0.0/30",
	"nmap_sn_down": "nmap -n -sn 127.0.0.5",
	"nmap_sn_mixed": "nmap -n -sn 127.0.0.4/30",
	"nmap_sweep_ports": "nmap -n -p 80 127.0.0.0/30",
	"nmap_open_sweep": "nmap -n --open -p 80 127.0.0.0/30",
	"nmap_open_none": "nmap --open -p 443 127.0.0.1",
	"nmap_open_mixed": "nmap --open -p 80,443 127.0.0.1",
	"nmap_open_states": "nmap -n --open -p 80,443,8080 127.0.0.1",
	"nmap_pn": "nmap -Pn -p 80 127.0.0.1",
	"nmap_pn_down": "nmap -n -Pn -p 80,443 127.0.0.5",
	"nmap_down": "nmap -n 127.0.0.5",
	"nmap_ignored": "nmap -n 127.0.0.2",
	"nmap_firewall": "nmap -n 127.0.0.6",
	"nmap_two_targets": "nmap -n -p 80 127.0.0.1 127.0.0.2",
	"nmap_sorted": "nmap -n -p 80,22 127.0.0.1",
	"nmap_cidr32": "nmap -n -p 80 127.0.0.1/32",
	"nmap_octet_range": "nmap -n -sn 127.0.0.1-3",
	"nmap_resolve_fail": "nmap nosuchhost.invalid",
	"nmap_resolve_mixed": "nmap -sn nosuchhost.invalid 127.0.0.1",
	"nmap_root_ss": "nmap -sS 127.0.0.1",
	"nmap_root_o": "nmap -O 127.0.0.1",
	"nmap_root_su": "nmap -sU 127.0.0.1",
	"nmap_p_range_bad": "nmap -p 99999 127.0.0.1",
	"nmap_p_name_bad": "nmap -p abc 127.0.0.1",
	"nmap_p_names": "nmap -n -p ssh,http 127.0.0.1",
	"nmap_sn_p": "nmap -n -sn -p 80 127.0.0.1",
	"nmap_t4": "nmap -T4 -p 80 127.0.0.1",
	"nmap_all_ports": "nmap -n -p- 127.0.0.1",
}


func test_every_nmap_golden_file_is_covered() -> void:
	var on_disk: Array = []
	for f in DirAccess.get_files_at(GOLDEN):
		if (f as String).begins_with("nmap_") and (f as String).ends_with(".txt"):
			on_disk.append((f as String).trim_suffix(".txt"))
	on_disk.sort()
	var covered: Array = NMAP_CASES.keys()
	covered.sort()
	assert_eq(covered, on_disk, "a capture without a test, or a test without a capture")


func test_emulator_matches_the_real_nmap() -> void:
	var lab := _nmap_lab()
	for file_name in NMAP_CASES:
		var want := _golden(file_name)
		assert_ne(want, "", file_name)
		assert_eq(_norm_nmap(_run(NMAP_CASES[file_name], lab)), want, "%s: %s" % [file_name, NMAP_CASES[file_name]])


# --- ss and netstat --------------------------------------------------------

## The sockets tools/golden/listeners_net.py opens, plus its one connection (seen
## from both ends). The workstation is 127.0.0.1 here so the addresses match.
func _net_lab() -> SimLab:
	var mine := {"owner": "tester", "process": "python3", "backlog": 5}
	var ports: Array = []
	for spec in [["tcp", 22, "0.0.0.0"], ["tcp", 631, "127.0.0.1"], ["tcp", 80, "0.0.0.0"],
			["udp", 68, "0.0.0.0"], ["udp", 5353, "127.0.0.1"]]:
		var p := {"proto": spec[0], "port": spec[1], "bind": spec[2]}
		p.merge(mine)
		ports.append(p)
	var lab := SimLab.from_data({
		"id": "golden-net", "title": "sockets", "seed": 1,
		"you": {"ip": "127.0.0.1", "name": "golden-ws", "os": "linux", "user": "tester", "ports": ports,
			"connections": [
				{"local_port": 22, "remote_ip": "127.0.0.1", "remote_port": 48528, "process": "python3", "owner": "tester"},
				{"local_port": 48528, "remote_ip": "127.0.0.1", "remote_port": 22, "process": "python3", "owner": "tester"}]},
		"network": {"cidr": "127.0.0.0/8", "gateway": "127.0.0.1"},
		"hosts": [{"ip": "127.0.0.2", "name": "other"}]}, "golden")
	assert_true(lab.ok(), "\n".join(lab.errors))
	return lab


## The same normalisation as tools/golden/net_env.sh. The kernel lists sockets in
## a different order from run to run, so rows are compared as a set.
func _norm_net(lines: Array) -> String:
	var out: Array = []
	for line in lines:
		var l: String = _sub(line, ":[0-9]{5}( |$)", ":PPPPP$1")
		l = _sub(l, "pid=[0-9]+,fd=[0-9]+", "pid=P,fd=F")
		var re := RegEx.new()
		re.compile("[0-9]+/python3")
		l = re.sub(l, "PID/python3", false)
		out.append(_sub(l, " +$", ""))
	out.sort()
	return "\n".join(out)


func _norm_golden(name: String) -> String:
	var lines: Array = Array(_golden(name).trim_suffix("\n").split("\n"))
	lines.sort()
	return "\n".join(lines)


const NET_CASES := {
	"ss_tln": "ss -tln", "ss_uln": "ss -uln", "ss_tuln": "ss -tuln", "ss_tlnp": "ss -tlnp",
	"ss_tl": "ss -tl", "ss_ta": "ss -ta", "ss_tan": "ss -tan", "ss_tn": "ss -tn", "ss_bare": "ss",
	"ss_tulnp": "ss -tulnp",
	"netstat_tln": "netstat -tln", "netstat_tuln": "netstat -tuln", "netstat_tlnp": "netstat -tlnp",
	"netstat_tan": "netstat -tan", "netstat_an": "netstat -an", "netstat_tn": "netstat -tn",
	"netstat_bare": "netstat", "netstat_ln": "netstat -ln", "netstat_uan": "netstat -uan",
}
## Not compared: netstat_tl. It resolves 631 to "ipps" and port 80 to "www-http",
## names that come from this machine's /etc/services, not from the tool.
const NET_NOT_COMPARED := ["netstat_tl"]


func test_every_ss_and_netstat_golden_file_is_covered() -> void:
	var on_disk: Array = []
	for f in DirAccess.get_files_at(GOLDEN):
		var n: String = (f as String).trim_suffix(".txt")
		if ((f as String).begins_with("ss_") or (f as String).begins_with("netstat_")) and (f as String).ends_with(".txt"):
			on_disk.append(n)
	on_disk.sort()
	var covered: Array = NET_CASES.keys() + NET_NOT_COMPARED
	covered.sort()
	assert_eq(covered, on_disk)


func test_emulator_matches_the_real_ss_and_netstat() -> void:
	var lab := _net_lab()
	for file_name in NET_CASES:
		assert_eq(_norm_net(_run(NET_CASES[file_name], lab)), _norm_golden(file_name), "%s: %s" % [file_name, NET_CASES[file_name]])


func test_golden_versions_are_recorded() -> void:
	var text := _golden("VERSIONS")
	for tool in ["iputils", "Nmap version 7.99", "iproute2", "net-tools"]:
		assert_string_contains(text, tool)
