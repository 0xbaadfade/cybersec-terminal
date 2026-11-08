extends GutTest
## ss and netstat on the shipped lab's workstation: which sockets appear, in what
## order, who can see which process, names and numbers, flags and errors. The
## column layout itself is pinned against the real tools in test_sim_golden.

const Support := preload("res://tests/unit/support.gd")
const REAL_PACK := "res://packs/linux-cli"

var _shell := SimShell.new()
var _lab: SimLab


func before_each() -> void:
	_lab = Pack.load_dir(REAL_PACK).labs["lab-dmz-01"]


func _run(line: String) -> Dictionary:
	var ctx := SimContext.new()
	ctx.lab = _lab
	ctx.rng = SimNet.rng_for(_lab.seed_value, line)
	ctx.tool_names = _shell.tool_names()
	return _shell.execute(line, ctx)


func _out(line: String) -> Array:
	return _run(line)["out"]


func _text(line: String) -> String:
	return "\n".join(_out(line))


## Fields of a row, split on runs of spaces.
func _fields(line: String) -> Array:
	return Array(line.split(" ", false))


func test_ss_lists_listening_tcp_ports_in_lab_order() -> void:
	var out := _out("ss -tln")
	assert_eq(out[0], "State  Recv-Q Send-Q Local Address:Port Peer Address:Port")
	assert_eq(_fields(out[1]), ["LISTEN", "0", "128", "0.0.0.0:22", "0.0.0.0:*"])
	assert_eq(_fields(out[2]), ["LISTEN", "0", "244", "127.0.0.1:5432", "0.0.0.0:*"])
	assert_eq(out.size(), 3)


func test_ss_columns_line_up() -> void:
	var out := _out("ss -tln")
	assert_eq(out[1], "LISTEN 0      128          0.0.0.0:22        0.0.0.0:*")
	assert_eq(out[2], "LISTEN 0      244        127.0.0.1:5432      0.0.0.0:*")


func test_ss_udp_comes_before_tcp_and_a_netid_column_appears() -> void:
	var out := _out("ss -tuln")
	assert_eq(out[0], "Netid State  Recv-Q Send-Q Local Address:Port Peer Address:Port")
	assert_eq(_fields(out[1]), ["udp", "UNCONN", "0", "0", "0.0.0.0:68", "0.0.0.0:*"])
	assert_eq(_fields(out[2])[0], "tcp")
	assert_eq(_fields(out[3])[0], "tcp")
	assert_string_contains(_out("ss -ln")[0], "Netid", "no -t or -u lists both")
	assert_false(_out("ss -tln")[0].contains("Netid"))
	assert_false(_out("ss -uln")[0].contains("Netid"))


func test_ss_connections_without_l_and_all_with_a() -> void:
	var established := _out("ss -tn")
	assert_eq(established.size(), 3, "header and the two connections, no listeners")
	assert_eq(_fields(established[1]), ["ESTAB", "0", "0", "10.20.0.50:51514", "10.20.0.10:22"])
	assert_eq(_fields(established[2])[0], "TIME-WAIT", "ss spells the state with a hyphen")
	var all := _out("ss -tan")
	assert_eq(all.size(), 5)
	assert_eq(_fields(all[1])[0], "LISTEN", "listeners first, then connections")
	assert_eq(_fields(all[3])[0], "ESTAB")


func test_ss_bare_shows_connections_of_both_kinds_with_netid_and_names() -> void:
	var out := _out("ss")
	assert_string_contains(out[0], "Netid State")
	assert_eq(_fields(out[1]), ["tcp", "ESTAB", "0", "0", "10.20.0.50:51514", "10.20.0.10:ssh"])


func test_ss_names_unless_n() -> void:
	var named := _out("ss -tl")
	assert_eq(_fields(named[1])[3], "0.0.0.0:ssh")
	assert_eq(_fields(named[2])[3], "127.0.0.1:postgresql")
	assert_eq(_fields(_out("ss -ul")[1])[3], "0.0.0.0:bootpc")
	assert_eq(_fields(_out("ss -tln")[1])[3], "0.0.0.0:22")


func test_ss_process_column_only_for_sockets_you_own() -> void:
	var out := _out("ss -tlnp")
	assert_true((out[0] as String).ends_with("Peer Address:PortProcess"), "the header runs into Process, as in the real tool")
	assert_false(out[1].contains("users:"), "sshd belongs to root")
	var re := RegEx.new()
	re.compile("users:\\(\\(\"postgres\",pid=[0-9]+,fd=4\\)\\)")
	assert_not_null(re.search(out[2]), out[2])
	assert_eq(_out("ss -tlnp"), _out("ss -tlnp"), "the same pid every time")


func test_ss_p_on_connections() -> void:
	var out := _out("ss -tnp")
	assert_string_contains(out[1], "users:((\"ssh\",pid=")
	assert_false(out[2].contains("users:"), "a TIME-WAIT socket has no process")


func test_ss_errors() -> void:
	assert_eq(_out("ss -s"), ["ss: option '-s' is not supported in this simulator"])
	assert_eq(_out("ss state established"), ["ss: filter expressions are not supported in this simulator"])
	assert_eq(_run("ss -z")["code"], 2)


func test_netstat_listeners_and_widths() -> void:
	var out := _out("netstat -tln")
	assert_eq(out[0], "Active Internet connections (only servers)")
	assert_eq(out[1], "Proto Recv-Q Send-Q Local Address           Foreign Address         State      ")
	assert_eq(out[2], "tcp        0      0 0.0.0.0:22              0.0.0.0:*               LISTEN     ")
	assert_eq(out[3], "tcp        0      0 127.0.0.1:5432          0.0.0.0:*               LISTEN     ")
	assert_eq(out.size(), 4)


func test_netstat_scope_titles_and_unix_section() -> void:
	assert_eq(_out("netstat -tn")[0], "Active Internet connections (w/o servers)")
	assert_eq(_out("netstat -tan")[0], "Active Internet connections (servers and established)")
	assert_eq(_out("netstat -tln")[0], "Active Internet connections (only servers)")
	var all := _out("netstat -an")
	assert_eq(all[all.size() - 2], "Active UNIX domain sockets (servers and established)")
	assert_eq(all[all.size() - 1], "Proto RefCnt Flags       Type       State         I-Node   Path")
	assert_false(_text("netstat -tan").contains("UNIX"), "-t or -u leaves the UNIX section out")
	assert_string_contains(_text("netstat"), "Active UNIX domain sockets (w/o servers)")
	assert_string_contains(_text("netstat -ln"), "Active UNIX domain sockets (only servers)")


func test_netstat_lists_tcp_before_udp() -> void:
	var out := _out("netstat -tuln")
	assert_eq(_fields(out[2])[0], "tcp")
	assert_eq(_fields(out[3])[0], "tcp")
	assert_eq(_fields(out[4]), ["udp", "0", "0", "0.0.0.0:68", "0.0.0.0:*"], "a listening udp socket has no state")


func test_netstat_connections_and_state_spelling() -> void:
	var out := _out("netstat -tn")
	assert_eq(_fields(out[2]), ["tcp", "0", "0", "10.20.0.50:51514", "10.20.0.10:22", "ESTABLISHED"])
	assert_eq(_fields(out[3])[5], "TIME_WAIT", "netstat spells the state with an underscore")


func test_netstat_resolves_names_unless_n() -> void:
	var out := _out("netstat -tl")
	assert_eq(_fields(out[2])[3], "0.0.0.0:ssh")
	assert_eq(_fields(out[3])[3], "localhost:postgresql")
	var conn := _out("netstat -t")
	assert_string_contains(conn[2], "analyst-ws.corp.local:5", "the local name, cut to the 23-character column")
	assert_string_contains(conn[2], "web-03.corp.local:ssh")


func test_netstat_p_prints_the_warning_and_only_your_processes() -> void:
	var out := _out("netstat -tlnp")
	assert_eq(out[0], "(Not all processes could be identified, non-owned process info")
	assert_eq(out[1], " will not be shown, you would have to be root to see it all.)")
	assert_string_contains(out[3], "PID/Program name")
	assert_string_contains(out[4], " -")
	assert_false(out[4].contains("sshd"))
	var re := RegEx.new()
	re.compile("LISTEN +[0-9]+/postgres +")
	assert_not_null(re.search(out[5]), out[5])


func test_netstat_errors() -> void:
	assert_eq(_out("netstat -r"), ["netstat: option '-r' is not supported in this simulator"])
	assert_eq(_out("netstat x"), ["netstat: no arguments are supported in this simulator"])


func test_the_loopback_mission_is_answered_by_ss() -> void:
	var pack := Pack.load_dir(REAL_PACK)
	var s := TerminalSession.new(pack.labs["lab-dmz-01"], pack.tool_docs, pack.concept_titles(), pack.items["lin-m-09"], Rules.load_default())
	var loop := "\n".join(s.run("ss -tln | grep 127.0.0.1", Support.T0)["out"])
	assert_string_contains(loop, "127.0.0.1:5432")
	assert_true(s.is_right("5432"))
	assert_false(s.is_right("22"))
	assert_string_contains("\n".join(s.run("netstat -tln | grep 127.0.0.1", Support.T0)["out"]), "127.0.0.1:5432")


func test_sockets_of_a_lab_without_any_are_just_a_header() -> void:
	var lab := SimLab.from_data(Support.demo_lab(), "t")
	var ctx := SimContext.new()
	ctx.lab = lab
	ctx.rng = SimNet.rng_for(1, "x")
	assert_eq(_shell.execute("ss -tln", ctx)["out"], ["State Recv-Q Send-Q Local Address:Port Peer Address:Port"], "no rows: the State column is as wide as its title")
	assert_eq(_shell.execute("netstat -tln", ctx)["out"].size(), 2)


func test_lab_validation_of_sockets() -> void:
	var errors := func(mutate: Callable) -> String:
		var d := Support.demo_lab()
		mutate.call(d)
		return "\n".join(SimLab.from_data(d, "t").errors)
	assert_string_contains(errors.call(func(d): d["you"]["ports"] = [{"port": 22, "bind": "everywhere"}]), "'bind' must be an address")
	assert_string_contains(errors.call(func(d): d["you"]["ports"] = [{"port": 22, "backlog": -1}]), "'backlog' must be a whole number")
	assert_string_contains(errors.call(func(d): d["you"]["connections"] = [{"local_port": 1}]), "every connection needs")
	assert_string_contains(errors.call(func(d): d["you"]["connections"] = [{"local_port": 5, "remote_ip": "10.20.0.1", "remote_port": 22, "state": "SORTA"}]), "unknown proto or state")
	assert_string_contains(errors.call(func(d): d["you"]["connections"] = [{"local_port": 0, "remote_ip": "10.20.0.1", "remote_port": 22}]), "local_port must be 1 to 65535")
	assert_string_contains(errors.call(func(d): d["you"]["connections"] = "none"), "you.connections must be an array")
	var ok := Support.demo_lab()
	ok["you"]["ports"] = [{"port": 22, "bind": "127.0.0.1", "process": "sshd", "owner": "root"}]
	ok["you"]["connections"] = [{"local_port": 5555, "remote_ip": "10.20.0.1", "remote_port": 22}]
	assert_true(SimLab.from_data(ok, "t").ok())


func _socket_lab(ports: Array) -> SimLab:
	var d := Support.demo_lab()
	d["you"]["ports"] = ports
	var lab := SimLab.from_data(d, "t")
	assert_true(lab.ok(), "\n".join(lab.errors))
	return lab


func _run_on(lab: SimLab, line: String) -> Array:
	var ctx := SimContext.new()
	ctx.lab = lab
	ctx.rng = SimNet.rng_for(1, line)
	return _shell.execute(line, ctx)["out"]


func test_only_open_ports_of_the_workstation_are_listening_sockets() -> void:
	var lab := _socket_lab([{"port": 22, "state": "open"}, {"port": 23, "state": "closed"}, {"port": 25, "state": "filtered"}])
	var out := _run_on(lab, "ss -tln")
	assert_eq(out.size(), 2)
	assert_string_contains(out[1], "0.0.0.0:22")


func test_netstat_puts_tcp_first_whatever_order_the_lab_declares() -> void:
	var lab := _socket_lab([{"port": 68, "proto": "udp"}, {"port": 22, "proto": "tcp"}])
	var out := _run_on(lab, "netstat -tuln")
	assert_eq(_fields(out[2])[0], "tcp")
	assert_eq(_fields(out[3])[0], "udp")
	var ss := _run_on(lab, "ss -tuln")
	assert_eq(_fields(ss[1])[0], "udp", "ss lists udp first, netstat tcp first (as captured)")
	assert_eq(_fields(ss[2])[0], "tcp")
