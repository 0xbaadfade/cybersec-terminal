class_name SimCurl
extends SimTool
## curl for plain http, in the shape of curl 8.23.0 (checked against the real tool,
## see tests/golden/curl_*.txt): -I/--head, -i/--include, -s, -S, --connect-timeout,
## -m/--max-time. https is only simulated as far as the connection (a closed or
## filtered port fails as it would; an open one says TLS is not simulated). A web server's replies come from the lab (a port's `http`
## block); the progress meter a real curl draws on some terminals is not simulated.

const SPEC := {"-I": false, "--head": false, "-i": false, "--include": false, "-s": false, "--silent": false,
		"-S": false, "--show-error": false, "-m": true, "--max-time": true, "--connect-timeout": true,
		"--no-styled-output": false}
const NOT_FOUND := "<html><body>Not Found.</body></html>\n"
const NO_ANSWER_MS := 130000  # the kernel gives up on an unanswered SYN after about this long
const NO_ROUTE_MS := 3000  # ARP finds nobody at an on-link address after about this long


func tool_name() -> String:
	return "curl"


func run(argv: Array, ctx: SimContext, _stdin: Array) -> Dictionary:
	var p := parse_flags(argv, SPEC)
	if p["bad"] != "":
		return unsupported("curl", p["bad"])
	if p["missing"] != "":
		return done(["curl: option %s: requires parameter" % p["missing"]], 2)
	var o: Dictionary = p["opts"]
	var urls: Array = p["args"]
	if urls.is_empty():
		return done(["curl: try 'curl --help' for more information"], 2)
	if urls.size() > 1:
		return done(["curl: only one URL is supported in this simulator"], 2)
	var head: bool = o.has("-I") or o.has("--head")
	var include: bool = o.has("-i") or o.has("--include")
	var quiet: bool = (o.has("-s") or o.has("--silent")) and not (o.has("-S") or o.has("--show-error"))
	var limit_ms := 0
	for flag in ["-m", "--max-time", "--connect-timeout"]:
		if o.has(flag):
			if not (o[flag] as String).is_valid_float() or float(o[flag]) < 0.0:
				return done(["curl: option %s: expected a proper numerical parameter" % flag], 2)
			var ms := int(float(o[flag]) * 1000.0)
			limit_ms = ms if limit_ms == 0 else mini(limit_ms, ms)

	var url := _parse_url(urls[0])
	if url.is_empty():
		return _fail(quiet, 3, "curl: (3) URL rejected: Bad hostname")
	if url["scheme"] != "http" and url["scheme"] != "https":
		return _fail(quiet, 1, "curl: (1) Protocol \"%s\" not supported" % url["scheme"])
	var lab := ctx.lab
	var ip: String = url["host"]
	if SimNet.parse_ip(ip) < 0:
		ip = lab.resolve(url["host"])
		if ip == "":
			return _fail(quiet, 6, "curl: (6) Could not resolve host: %s" % url["host"])
	var target := "%s:%d" % [url["host"], url["port"]]

	var host := lab.host_at(ip)
	var state := _port_state(lab, host, ip, int(url["port"]))
	if state != "open":
		var fail_ms: int = {"closed": ctx.rng.randi_range(0, 2), "noroute": NO_ROUTE_MS + ctx.rng.randi_range(0, 90),
				"filtered": NO_ANSWER_MS + ctx.rng.randi_range(0, 900)}[state]
		if limit_ms > 0 and fail_ms > limit_ms:
			return _fail(quiet, 28, "curl: (28) Connection timed out after %d milliseconds" % (limit_ms + ctx.rng.randi_range(1, 8)))
		var code := 28 if state == "filtered" else 7
		return _fail(quiet, code, "curl: (%d) Failed to connect to %s after %d ms: Could not connect to server" % [code, target, fail_ms])

	if url["scheme"] == "https":
		return _fail(quiet, 1, "curl: https is not simulated (the port is open, but there is no TLS handshake to show); try http")
	var web := _web(host, int(url["port"]))
	if web.is_empty():
		return _fail(quiet, 52, "curl: (52) Empty reply from server")
	var path: String = (url["path"] as String).get_slice("?", 0)
	var page: Dictionary = web["pages"].get(path, {})
	if page.is_empty():
		page = {"status": 404, "headers": {}, "body": NOT_FOUND, "type": "text/html; charset=iso-8859-1"}
	var body: String = page["body"]
	var out: Array = []
	if head or include:
		out.append("HTTP/1.1 %d %s" % [page["status"], SimLab.HTTP_REASONS.get(page["status"], "Unknown")])
		out.append("Date: %s" % SimNet.http_date(ctx.now))
		if web["server"] != "":
			out.append("Server: %s" % web["server"])
		for k in web["headers"]:
			out.append("%s: %s" % [k, web["headers"][k]])
		for k in page["headers"]:
			out.append("%s: %s" % [k, page["headers"][k]])
		out.append("Content-Length: %d" % body.to_utf8_buffer().size())
		out.append("Content-Type: %s" % page["type"])
		out.append("")
	if not head:
		out.append_array(body.trim_suffix("\n").split("\n") if body != "" else [])
	return done(out)


## {"scheme", "host", "port", "path"}, or {} when there is no host.
static func _parse_url(text: String) -> Dictionary:
	var scheme := "http"
	var rest := text
	if text.contains("://"):
		scheme = text.get_slice("://", 0).to_lower()
		rest = text.substr(text.find("://") + 3)
	var slash := rest.find("/")
	var authority := rest if slash < 0 else rest.substr(0, slash)
	var path := "/" if slash < 0 else rest.substr(slash)
	var host := authority
	var port := 443 if scheme == "https" else 80
	if authority.contains(":"):
		host = authority.get_slice(":", 0)
		var port_text := authority.get_slice(":", 1)
		if not port_text.is_valid_int() or int(port_text) < 1 or int(port_text) > 65535:
			return {}
		port = int(port_text)
	if host == "":
		return {}
	return {"scheme": scheme, "host": host.to_lower(), "port": port, "path": path}


## open | closed | filtered | noroute, as a TCP connection to the port would find it.
static func _port_state(lab: SimLab, host: Dictionary, ip: String, port: int) -> String:
	if host.is_empty():
		return "noroute" if SimNet.in_cidr(SimNet.parse_ip(ip), lab.cidr()) else "filtered"
	for pr in host["ports"]:
		if pr["port"] == port and pr["proto"] == "tcp":
			if pr["state"] == "open" and host.get("is_you", false) and pr["bind"] == "127.0.0.1":
				return "closed"  # only the machine itself can reach a loopback-only port
			return pr["state"]
	return host["default_ports"]


static func _web(host: Dictionary, port: int) -> Dictionary:
	for pr in host["ports"]:
		if pr["port"] == port and pr["proto"] == "tcp":
			return pr.get("http", {})
	return {}


## An error exit: curl -s hides the message, the exit code stays.
static func _fail(quiet: bool, code: int, message: String) -> Dictionary:
	return done([] if quiet else [message], code)
