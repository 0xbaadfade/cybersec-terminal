extends GutTest
## The simulated shell: tokenising, pipes, the pipe-stage tools and builtins.

const Support := preload("res://tests/unit/support.gd")

var _shell: SimShell
var _ctx: SimContext


func before_each() -> void:
	_shell = SimShell.new()
	_ctx = SimContext.new()
	_ctx.lab = SimLab.from_data(Support.demo_lab(), "t")
	_ctx.rng = SimNet.rng_for(1, "t")
	_ctx.tool_docs = Support.demo_tools()
	_ctx.concept_titles = {"1.1.a": "Alpha"}
	_ctx.tool_names = _shell.tool_names()


func _run(line: String) -> Dictionary:
	_ctx.history.append(line)
	return _shell.execute(line, _ctx)


func _out(line: String) -> Array:
	return _run(line)["out"]


func _stages(line: String) -> Array:
	return SimShell.tokenize(line)["stages"]


# --- tokenising ----------------------------------------------------------

func test_plain_words_and_extra_spaces() -> void:
	assert_eq(_stages("  ping   -c 1  web-03 "), [["ping", "-c", "1", "web-03"]])
	assert_eq(_stages(""), [])
	assert_eq(_stages("   "), [])


func test_quotes_keep_spaces_and_operators() -> void:
	assert_eq(_stages("grep 'hello world' f"), [["grep", "hello world", "f"]])
	assert_eq(_stages("grep \"a | b\" f"), [["grep", "a | b", "f"]])
	assert_eq(_stages("echo 'a;b' \"c>d\""), [["echo", "a;b", "c>d"]])
	assert_eq(_stages("grep a\"b c\"d"), [["grep", "ab cd"]])


func test_escapes() -> void:
	assert_eq(_stages("grep a\\ b"), [["grep", "a b"]])
	assert_eq(_stages("grep \"say \\\"hi\\\"\""), [["grep", "say \"hi\""]])
	assert_eq(_stages("grep 'a\\b'"), [["grep", "a\\b"]], "no escapes inside single quotes")


func test_an_empty_quoted_argument_is_kept() -> void:
	assert_eq(_stages("grep \"\" f"), [["grep", "", "f"]])


func test_pipes_split_stages() -> void:
	assert_eq(_stages("cat a | grep b|wc -l"), [["cat", "a"], ["grep", "b"], ["wc", "-l"]])


func test_unsupported_operators_are_refused_by_name() -> void:
	for op in [";", "&&", "||", "&", ">", ">>", "<"]:
		var parsed := SimShell.tokenize("ping a %s ping b" % op)
		assert_eq(parsed["error"], "shell: %s is not supported in this simulator" % op, op)
		assert_eq(parsed["stages"], [])


func test_syntax_errors() -> void:
	assert_string_contains(SimShell.tokenize("grep 'x")["error"], "unexpected EOF")
	assert_string_contains(SimShell.tokenize("grep \"x")["error"], "unexpected EOF")
	assert_string_contains(SimShell.tokenize("| grep x")["error"], "syntax error")
	assert_string_contains(SimShell.tokenize("ls |")["error"], "syntax error")
	assert_string_contains(SimShell.tokenize("ls | | wc")["error"], "syntax error")


# --- execution -----------------------------------------------------------

func test_unknown_command_is_bash_style() -> void:
	var r := _run("nmapp 10.0.0.1")
	assert_eq(r["out"], ["bash: nmapp: command not found"])
	assert_eq(r["code"], 127)


func test_an_empty_line_prints_nothing() -> void:
	assert_eq(_out(""), [])


func test_shell_errors_come_back_as_output() -> void:
	assert_eq(_out("ls > x"), ["shell: > is not supported in this simulator"])


func test_cat_and_ls_read_only_the_learners_files() -> void:
	assert_eq(_out("cat scope.txt"), ["Authorised scope only."])
	assert_eq(_out("ls"), ["notes.txt  scope.txt"], "a row on a terminal")
	assert_eq(_out("ls | cat"), ["notes.txt", "scope.txt"], "one per line when piped")
	assert_eq(_out("ls -1"), ["notes.txt", "scope.txt"])
	var r := _run("cat nope.txt")
	assert_eq(r["out"], ["cat: nope.txt: No such file or directory"])
	assert_eq(r["code"], 1)
	assert_eq(_out("ls nope"), ["ls: cannot access 'nope': No such file or directory"])
	assert_eq(_out("ls scope.txt"), ["scope.txt"])
	assert_eq(_out("cat -n scope.txt"), ["     1\tAuthorised scope only."])


func test_grep_options() -> void:
	assert_eq(_out("cat notes.txt | grep ICMP"), ["Printer: ICMP is disabled."])
	assert_eq(_out("cat notes.txt | grep icmp"), [], "case matters")
	assert_eq(_out("cat notes.txt | grep -i icmp"), ["Printer: ICMP is disabled."])
	assert_eq(_out("cat notes.txt | grep -v web"), ["Printer: ICMP is disabled.", "scope 10.20.0.0/24"])
	assert_eq(_out("cat notes.txt | grep -c 0"), ["2"])
	assert_eq(_out("cat notes.txt | grep -n scope"), ["3:scope 10.20.0.0/24"])
	assert_eq(_out("cat notes.txt | grep -E 'web|ICMP'"), ["Web tier: web-03, printer-01.", "Printer: ICMP is disabled."])
	assert_eq(_out("cat notes.txt | grep 'web|ICMP'"), [], "a plain | is literal without -E")
	assert_eq(_out("grep ICMP notes.txt"), ["Printer: ICMP is disabled."], "a file operand")
	assert_eq(_out("grep -c e notes.txt scope.txt"), ["notes.txt:3", "scope.txt:1"])


func test_grep_exit_codes_and_errors() -> void:
	assert_eq(_run("cat notes.txt | grep zzz")["code"], 1)
	assert_eq(_run("cat notes.txt | grep web")["code"], 0)
	assert_eq(_out("grep"), ["Usage: grep [OPTION]... PATTERNS [FILE]..."])
	assert_eq(_out("grep x nope.txt"), ["grep: nope.txt: No such file or directory"])
	for bad in ["-E '('", "-E 'a)'", "'[abc'", "-E 'a{2'", "'a\\'"]:
		assert_eq(_out("cat notes.txt | grep %s" % bad), ["grep: Invalid regular expression"], bad)
	assert_eq(_out("cat notes.txt | grep '('"), [], "a plain paren is literal in basic mode")
	assert_eq(_out("cat notes.txt | grep '\\('"), ["grep: Invalid regular expression"], "\\( opens a group in basic mode")
	assert_eq(_out("cat notes.txt | grep '[A-Z]CMP'"), ["Printer: ICMP is disabled."], "character classes work")


func test_head_tail_wc() -> void:
	assert_eq(_out("cat notes.txt | head -n 1"), ["Web tier: web-03, printer-01."])
	assert_eq(_out("cat notes.txt | head -1"), ["Web tier: web-03, printer-01."])
	assert_eq(_out("cat notes.txt | tail -n 1"), ["scope 10.20.0.0/24"])
	assert_eq(_out("cat notes.txt | tail -2"), ["Printer: ICMP is disabled.", "scope 10.20.0.0/24"])
	assert_eq(_out("cat notes.txt | head -n 0"), [])
	assert_eq(_out("cat notes.txt | wc -l"), ["3"])
	assert_eq(_out("head -n 1 scope.txt"), ["Authorised scope only."])
	assert_eq(_out("cat notes.txt | wc -w"), ["10"])
	assert_eq(_out("cat scope.txt | wc -c"), ["23"])
	assert_eq(_out("wc -l notes.txt"), ["3 notes.txt"])
	assert_eq(_out("cat scope.txt | wc"), ["      1       3      23"])
	assert_string_contains(_out("head -n x notes.txt")[0], "invalid number of lines")
	assert_string_contains(_out("tail nope.txt")[0], "cannot open")


func test_unsupported_flags_say_so_and_never_invent_output() -> void:
	for cmd in ["grep -z x", "head -q f", "tail -f f", "wc -m", "cat -A f", "ls -l", "ping -f x"]:
		var r := _run(cmd)
		assert_eq(r["code"], 2, cmd)
		assert_string_contains(r["out"][0], "is not supported in this simulator")
		assert_eq(r["out"].size(), 1, cmd)


func test_pipeline_with_a_failing_first_stage_still_filters_its_message() -> void:
	assert_eq(_out("nope | grep command"), ["bash: nope: command not found"])


func test_longer_pipelines() -> void:
	assert_eq(_out("cat notes.txt | grep -v web | head -n 1 | wc -l"), ["1"])


# --- builtins ------------------------------------------------------------

func test_help_lists_the_tools_and_shell() -> void:
	var text := "\n".join(_out("help"))
	assert_string_contains(text, "ping")
	assert_string_contains(text, "grep")
	assert_string_contains(text, "tool <name>")
	assert_string_contains("\n".join(_out("help | grep pipes")), "pipes:")


func test_tool_shows_the_page_and_the_exam_link() -> void:
	var text := "\n".join(_out("tool ping"))
	assert_string_contains(text, "ping - Send ICMP echo requests.")
	assert_string_contains(text, "usage: ping [-c N] <host>")
	assert_string_contains(text, "-c N")
	assert_string_contains(text, "Concept: Alpha")
	assert_string_contains(text, "No reply is not proof of down.")
	assert_string_contains("\n".join(_out("tool")), "tool <name> shows one in full.")
	var missing := _run("tool wibble")
	assert_eq(missing["out"], ["tool: no manual entry for 'wibble'"])
	assert_eq(missing["code"], 1)


func test_history_numbers_the_lines_typed() -> void:
	_run("ls")
	_run("cat scope.txt")
	var out := _out("history")
	assert_eq(out[0], "    1  ls")
	assert_eq(out[1], "    2  cat scope.txt")
	assert_eq(out[2], "    3  history")
