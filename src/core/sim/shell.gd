class_name SimShell
extends RefCounted
## The simulated shell: tokenises a line, runs each pipeline stage through its
## tool, and returns the text. It supports quotes, backslash escapes and `|`.
## Everything else a real shell does (; && || & redirection, variables,
## globbing) is refused with a clear message instead of being half-done.

const UNSUPPORTED: Array = ["&&", "||", ">>", ";", "&", ">", "<"]

var tools: Dictionary = {}  # name -> SimTool (a Linux workstation)
var win_tools: Dictionary = {}  # name -> SimTool (a Windows workstation)
var kali_tools: Dictionary = {}  # name -> SimTool (a Kali analysis workstation: wireless tools plus file tools)
var builtins: Dictionary = {}  # name -> SimTool (help, tool, history)


func _init() -> void:
	for t in [SimPing.new(), SimNmap.new(), SimSs.new(), SimNetstat.new(), SimDig.new(), SimNslookup.new(),
			SimCurl.new(), SimIp.new(), SimGrep.new(), SimHead.new(), SimTail.new(), SimWc.new(), SimCat.new(),
			SimLs.new(), SimFile.new(), SimNm.new(), SimStrings.new(), SimReadelf.new(), SimObjdump.new(),
			SimChecksec.new()]:
		tools[t.tool_name()] = t
	for t in [SimWinPing.new(), SimIpconfig.new(), SimWinNslookup.new(), SimWinNetstat.new(), SimFindstr.new(),
			SimType.new(), SimHostname.new(), tools["curl"]]:
		win_tools[t.tool_name()] = t
	for t in [SimAirodump.new(), SimAircrack.new(), SimTshark.new(), tools["cat"], tools["ls"], tools["grep"],
			tools["head"], tools["tail"], tools["wc"]]:
		kali_tools[t.tool_name()] = t
	for t in [SimHelp.new(), SimToolDoc.new(), SimHistory.new()]:
		builtins[t.tool_name()] = t


## Names the learner can type, tools first, in a stable order.
func tool_names() -> Array:
	return tool_names_for("linux")


func tool_names_for(os_name: String) -> Array:
	var names: Array = _roster(os_name).keys()
	names.sort()
	return names


## The tools a workstation of this OS offers.
func _roster(os_name: String) -> Dictionary:
	if os_name == "windows":
		return win_tools
	if os_name == "kali":
		return kali_tools
	return tools


## {"stages": [[token, ...], ...], "error": ""}. An empty line is zero stages.
## `windows` follows cmd: only double quotes quote, a backslash is an ordinary
## character (paths) and ; is not an operator.
static func tokenize(line: String, windows: bool = false) -> Dictionary:
	var stages: Array = []
	var tokens: Array = []
	var cur := ""
	var has_cur := false
	var quote := ""
	var i := 0
	while i < line.length():
		var ch := line[i]
		if quote == "'":
			if ch == "'":
				quote = ""
			else:
				cur += ch
		elif quote == "\"":
			if ch == "\"":
				quote = ""
			elif ch == "\\" and not windows and i + 1 < line.length() and "\"\\".contains(line[i + 1]):
				i += 1
				cur += line[i]
			else:
				cur += ch
		elif (ch == "'" and not windows) or ch == "\"":
			quote = ch
			has_cur = true
		elif ch == "\\" and not windows and i + 1 < line.length():
			i += 1
			cur += line[i]
			has_cur = true
		elif ch == " " or ch == "\t":
			if has_cur:
				tokens.append(cur)
				cur = ""
				has_cur = false
		else:
			var op := _operator_at(line, i, windows)
			if op == "|":
				if has_cur:
					tokens.append(cur)
					cur = ""
					has_cur = false
				if tokens.is_empty():
					return {"stages": [], "error": _syntax_error(windows, "bash: syntax error near unexpected token `|'")}
				stages.append(tokens)
				tokens = []
			elif op != "":
				return {"stages": [], "error": "shell: %s is not supported in this simulator" % op}
			else:
				cur += ch
				has_cur = true
			i += maxi(op.length(), 1) - 1
		i += 1
	if quote != "":
		return {"stages": [], "error": _syntax_error(windows, "bash: unexpected EOF while looking for matching `%s'" % quote)}
	if has_cur:
		tokens.append(cur)
	if not tokens.is_empty():
		stages.append(tokens)
	elif not stages.is_empty():
		return {"stages": [], "error": _syntax_error(windows, "bash: syntax error: unexpected end of line after `|'")}
	return {"stages": stages, "error": ""}


## "|" for a pipe, an UNSUPPORTED operator, or "" for an ordinary character.
static func _syntax_error(windows: bool, bash_text: String) -> String:
	return "The syntax of the command is incorrect." if windows else bash_text


static func _operator_at(line: String, i: int, windows: bool = false) -> String:
	if line.substr(i, 2) == "||":
		return "||"
	if line[i] == "|":
		return "|"
	for op in UNSUPPORTED:
		if windows and op == ";":
			continue
		if line.substr(i, op.length()) == op:
			return op
	return ""


## {"out": Array of lines, "code": exit code of the last stage}.
func execute(line: String, ctx: SimContext) -> Dictionary:
	var os_name: String = ctx.lab.you.get("os", "linux") if ctx.lab != null else "linux"
	var windows: bool = os_name == "windows"
	var parsed := tokenize(line, windows)
	if parsed["error"] != "":
		return {"out": [parsed["error"]], "code": 2}
	var stages: Array = parsed["stages"]
	var stdin: Array = []
	var code := 0
	for n in stages.size():
		var argv: Array = stages[n]
		var name: String = argv[0]
		var tool: SimTool = builtins.get(name, _roster(os_name).get(name))
		if tool == null:
			if windows:
				stdin = ["'%s' is not recognized as an internal or external command," % name, "operable program or batch file."]
				code = 9009
			else:
				stdin = ["bash: %s: command not found" % name]
				code = 127
			continue
		ctx.tty = n == stages.size() - 1
		var res := tool.run(argv.slice(1), ctx, stdin)
		stdin = res["out"]
		code = res["code"]
	return {"out": stdin, "code": code}
