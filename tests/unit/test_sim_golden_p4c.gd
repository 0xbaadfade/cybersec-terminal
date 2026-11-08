extends GutTest
## The dig, nslookup, curl and ip emulators against the real tools. tests/golden/
## holds captures taken inside an empty network namespace on this machine
## (tools/golden_capture.sh p4c): a real named (BIND) serving the zone below, a web
## server, and an eth0 with the workstation's address. The lab here mirrors it.

const GOLDEN := "res://tests/golden/"
const PREFIXES: Array = ["dig_", "nslookup_", "curl_", "ip_"]

var _shell := SimShell.new()


func _run(line: String, lab: SimLab) -> Array:
	var ctx := SimContext.new()
	ctx.lab = lab
	ctx.rng = SimNet.rng_for(lab.seed_value, line)
	ctx.now = 1730000000
	ctx.tool_names = _shell.tool_names()
	return _shell.execute(line, ctx)["out"]


func _sub(text: String, pattern: String, with: String) -> String:
	var re := RegEx.new()
	re.compile(pattern)
	return re.sub(text, with, true)


## The same normalisation as tools/golden/lab_net.sh.
func _norm(lines: Array) -> String:
	if lines.is_empty():
		return ""
	var text := "\n".join(lines) + "\n"
	text = _sub(text, "id: [0-9]+\n", "id: ID\n")
	text = _sub(text, "(?m)^; COOKIE: [0-9a-f]+ \\(good\\)", "; COOKIE: C (good)")
	text = _sub(text, "Query time: [0-9]+ msec", "Query time: Q msec")
	text = _sub(text, "(?m)^;; WHEN: .*", ";; WHEN: W")
	text = _sub(text, "(?m)^Date: .*", "Date: DATE")
	text = _sub(text, "after [0-9]+ ms", "after N ms")
	return _sub(text, "after [0-9]+ milliseconds", "after N milliseconds")


const CASES := {
	"dig_a": "dig web-03.corp.local",
	"dig_at": "dig @10.20.0.2 web-03.corp.local",
	"dig_short": "dig +short web-03.corp.local",
	"dig_cname": "dig www.corp.local",
	"dig_short_cname": "dig +short www.corp.local",
	"dig_mx": "dig corp.local MX",
	"dig_short_mx": "dig +short corp.local MX",
	"dig_ns": "dig corp.local NS",
	"dig_txt": "dig corp.local TXT",
	"dig_soa": "dig corp.local SOA",
	"dig_t_mx": "dig -t MX corp.local",
	"dig_ptr": "dig -x 10.20.0.30",
	"dig_short_ptr": "dig +short -x 10.20.0.30",
	"dig_ptr_nx": "dig -x 10.20.0.99",
	"dig_nx": "dig nosuch.corp.local",
	"dig_short_nx": "dig +short nosuch.corp.local",
	"dig_nodata": "dig web-03.corp.local MX",
	"dig_refused": "dig example.com",
	"dig_bare": "dig web-03",
	"dig_noall": "dig +noall +answer web-03.corp.local",
	"dig_noall_cname": "dig +noall +answer www.corp.local",
	"dig_a_lower": "dig WEB-03.Corp.Local",
	"dig_dead_server": "dig @10.20.0.77 web-03.corp.local",
	"dig_x_bad": "dig -x 1.2.3",
	"dig_x_text": "dig -x notanaddress",
	"dig_server_name_bad": "dig @nosuch.invalid web-03.corp.local",
	"dig_noserver": "dig @10.20.0.11 web-03.corp.local",
	"nslookup_a": "nslookup web-03.corp.local",
	"nslookup_bare": "nslookup web-03",
	"nslookup_server": "nslookup web-03.corp.local 10.20.0.2",
	"nslookup_cname": "nslookup www.corp.local",
	"nslookup_ptr": "nslookup 10.20.0.30",
	"nslookup_ptr_nx": "nslookup 10.20.0.99",
	"nslookup_mx": "nslookup -type=MX corp.local",
	"nslookup_ns": "nslookup -type=NS corp.local",
	"nslookup_txt": "nslookup -type=TXT corp.local",
	"nslookup_soa": "nslookup -type=SOA corp.local",
	"nslookup_nx": "nslookup nosuch.corp.local",
	"nslookup_refused": "nslookup example.com",
	"nslookup_nodata": "nslookup -type=MX web-03.corp.local",
	"nslookup_dead": "nslookup web-03.corp.local 10.20.0.77",
	"nslookup_noserver": "nslookup web-03.corp.local 10.20.0.11",
	"nslookup_bare_nx": "nslookup nosuch",
	"curl_I": "curl --no-styled-output -I http://10.20.0.10/",
	"curl_head_long": "curl --no-styled-output --head http://10.20.0.10/",
	"curl_I_bare": "curl --no-styled-output -I web-03",
	"curl_i": "curl --no-styled-output -i http://10.20.0.10/",
	"curl_body": "curl --no-styled-output http://10.20.0.10/",
	"curl_s_I": "curl --no-styled-output -s -I http://10.20.0.10/",
	"curl_301": "curl --no-styled-output -I http://10.20.0.10/old",
	"curl_403": "curl --no-styled-output -I http://10.20.0.10/admin",
	"curl_404": "curl --no-styled-output -I http://10.20.0.10/missing",
	"curl_404_body": "curl --no-styled-output http://10.20.0.10/missing",
	"curl_refused": "curl --no-styled-output -I http://10.20.0.11",
	"curl_refused_port": "curl --no-styled-output -I http://10.20.0.10:8080/",
	"curl_empty": "curl --no-styled-output -I http://10.20.0.30",
	"curl_empty_body": "curl --no-styled-output http://10.20.0.30",
	"curl_timeout": "curl --no-styled-output -I --connect-timeout 2 http://10.20.0.40",
	"curl_timeout_default": "curl --no-styled-output -I http://10.20.0.40",
	"curl_m_timeout": "curl --no-styled-output -I -m 2 http://10.20.0.40",
	"curl_nohost": "curl --no-styled-output -I http://nosuch.corp.local",
	"curl_nourl": "curl",
	"curl_s_refused": "curl --no-styled-output -s -I http://10.20.0.11",
	"curl_s_nohost": "curl --no-styled-output -s -I http://nosuch.corp.local",
	"curl_https_refused": "curl --no-styled-output -I https://10.20.0.10/",
	"ip_addr": "ip addr",
	"ip_a_show_eth0": "ip a show eth0",
	"ip_addr_dev": "ip addr show dev eth0",
	"ip_br": "ip -br addr",
	"ip_4": "ip -4 addr",
	"ip_4_br": "ip -4 -br addr",
	"ip_br_4": "ip -br -4 addr",
	"ip_link": "ip link",
	"ip_br_link": "ip -br link",
	"ip_route": "ip route",
	"ip_route_show": "ip route show",
	"ip_no_dev": "ip addr show dev eth9",
	"ip_bad_object": "ip frobnicate",
	"ip_noargs": "ip",
	"ip_addr_lo": "ip addr show lo",
	"curl_noroute": "curl --no-styled-output -I http://10.20.0.99/",
	"curl_noroute_m": "curl --no-styled-output -I -m 2 http://10.20.0.99/",
}

const PAGE := "<html><head><title>Corp web tier</title></head><body>It works.</body></html>\n"


func _web() -> Dictionary:
	return {"server": "Apache/2.4.6 (CentOS)", "headers": {"X-Powered-By": "PHP/5.4.16"}, "pages": {
		"/": {"status": 200, "type": "text/html; charset=UTF-8", "body": PAGE, "headers": {
			"Last-Modified": "Mon, 02 Nov 2026 09:14:03 GMT", "ETag": "\"4d-5f2c1a7c0b4d3\"", "Accept-Ranges": "bytes"}},
		"/old": {"status": 301, "type": "text/html; charset=iso-8859-1", "headers": {"Location": "https://web-03.corp.local/"},
			"body": "<html><body>Moved: <a href=\"https://web-03.corp.local/\">here</a>.</body></html>\n"},
		"/admin": {"status": 403, "type": "text/html; charset=iso-8859-1", "headers": {}, "body": "<html><body>Forbidden.</body></html>\n"}}}


## The environment of tools/golden/lab_net.sh and iface_net.sh.
func _lab() -> SimLab:
	var lab := SimLab.from_data({
		"id": "golden-p4c", "title": "namespace", "seed": 1,
		"you": {"ip": "10.20.0.50", "name": "analyst-ws", "os": "linux", "user": "tester", "mac": "52:54:00:12:34:56"},
		"network": {"cidr": "10.20.0.0/24", "gateway": "10.20.0.1", "dns": "10.20.0.2", "domain": "corp.local"},
		"hosts": [
			{"ip": "10.20.0.1", "name": "fw-01"},
			{"ip": "10.20.0.2", "name": "dns-01", "ports": [{"port": 53, "proto": "udp"}, {"port": 53}]},
			{"ip": "10.20.0.10", "name": "web-03", "ports": [{"port": 80, "http": _web()}]},
			{"ip": "10.20.0.11", "name": "db-02"},
			{"ip": "10.20.0.20", "name": "files-01"},
			{"ip": "10.20.0.30", "name": "printer-01", "ports": [{"port": 80}]},
			{"ip": "10.20.0.40", "name": "filtered-01", "ports": [{"port": 80, "state": "filtered"}]}],
		"dns": [
			{"name": "www.corp.local", "type": "CNAME", "value": "web-03.corp.local"},
			{"name": "corp.local", "type": "MX", "value": "10 web-03.corp.local"},
			{"name": "corp.local", "type": "TXT", "value": "v=spf1 ip4:10.20.0.0/24 -all"}]}, "golden")
	assert_true(lab.ok(), "\n".join(lab.errors))
	return lab


func test_every_p4c_golden_file_is_covered() -> void:
	var on_disk: Array = []
	for f in DirAccess.get_files_at(GOLDEN):
		var base: String = (f as String).trim_suffix(".txt")
		for pre in PREFIXES:
			if base.begins_with(pre) and (f as String).ends_with(".txt"):
				on_disk.append(base)
	on_disk.sort()
	var covered: Array = CASES.keys()
	covered.sort()
	assert_eq(covered, on_disk, "a capture without a test, or a test without a capture")


func test_emulators_match_the_real_tools() -> void:
	var lab := _lab()
	for file_name in CASES:
		var want := FileAccess.get_file_as_string(GOLDEN + file_name + ".txt")
		assert_eq(_norm(_run(CASES[file_name], lab)), want, "%s: %s" % [file_name, CASES[file_name]])
