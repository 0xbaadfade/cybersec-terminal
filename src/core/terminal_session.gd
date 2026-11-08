class_name TerminalSession
extends RefCounted
## One learner at one lab's shell: the typed history, and for a mission the
## answer tries and the credit they earn. Headless; the router prints what
## run() returns.

var lab: SimLab
var shell := SimShell.new()
var mission: Dictionary = {}  # the terminal item, or {} in free play
var history: Array = []
var tries := 0  # answers given
var solved_on := 0  # the try that was right, 0 while unsolved
var given: Array = []  # what was typed after `answer`
var max_tries := 2
var second_try_credit := 0.5

var _tool_docs: Dictionary
var _concept_titles: Dictionary


func _init(lab_in: SimLab, tool_docs: Dictionary, concept_titles: Dictionary, mission_item: Dictionary = {},
		rules: Rules = null) -> void:
	lab = lab_in
	mission = mission_item
	_tool_docs = tool_docs
	_concept_titles = concept_titles
	if rules != null:
		second_try_credit = float(rules.terminal_second_try_percent) / 100.0


func is_mission() -> bool:
	return not mission.is_empty()


## `analyst@analyst-ws` plus the dollar sign.
func prompt() -> String:
	if lab.you["os"] == "windows":
		return "C:\\Users\\%s>" % lab.you["user"]
	return "%s@%s%s" % [lab.you["user"], lab.you["name"], char(36)]


## Run one typed line: {"out": Array of text lines, "code": exit code}.
func run(line: String, now: int) -> Dictionary:
	history.append(line)
	var ctx := SimContext.new()
	ctx.lab = lab
	ctx.rng = SimNet.rng_for(lab.seed_value, line)
	ctx.now = now
	ctx.tool_docs = _tool_docs
	ctx.concept_titles = _concept_titles
	ctx.history = history
	ctx.tool_names = shell.tool_names_for(lab.you["os"])
	if is_mission():
		ctx.extra_help = ["mission: answer <text> submits (%d tries)   leave ends the round" % max_tries]
	else:
		ctx.extra_help = ["free play: exit returns to the prompt; there is no question and no XP"]
	return shell.execute(line, ctx)


## Does `text` match an accepted answer (case-insensitive, trimmed)?
func is_right(text: String) -> bool:
	var want := text.strip_edges().to_lower()
	for a in mission["answer"]["accept"]:
		if (a as String).strip_edges().to_lower() == want:
			return true
	return false


## Record one answer: {"correct", "done" (no more tries), "tries_left"}.
func answer(text: String) -> Dictionary:
	tries += 1
	given.append(text.strip_edges())
	var right := is_right(text)
	if right:
		solved_on = tries
	return {"correct": right, "done": right or tries >= max_tries, "tries_left": maxi(0, max_tries - tries)}


## 1.0 on the first try, `second_try_credit` on the second, otherwise 0.
func credit() -> float:
	if solved_on == 1:
		return 1.0
	if solved_on == 2:
		return second_try_credit
	return 0.0
