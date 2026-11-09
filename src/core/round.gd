class_name Round
extends RefCounted
## One round in progress: the queue, the shuffled options of the current
## encounter, the Trace meter, the streak, the requeue rule (README "Answering
## and scoring"). It scores answers but never touches a Profile; the router
## applies the result to the profile and saves.

var pack: Pack
var rules: Rules
var rng: RandomNumberGenerator
var node_id := ""  # "" for a review round
var queue: Array = []  # entries {"item", "concept", "kind"}
var index := 0
var trace := 0
var streak := 0
var best_streak := 0
var trace_peak := 0  # highest Trace reached during the round
var started_at := 0  # unix time, set by the router
var xp := 0
var full := 0  # fully correct answers
var answered := 0
var outcome := ""  # "" while running, else "complete", "traced" or "left"
var order: Array = []  # option ids of the current encounter, in display order
var requeued: Dictionary = {}  # concept id -> true
var terminal: TerminalSession = null  # the lab shell, for a terminal encounter
## A round the learner sized on the setup screen: no Trace meter and no TRACED
## ending (they asked for n questions and get n). XP, streak and spacing as usual.
var trace_off := false


func _init(content_pack: Pack, rules_in: Rules, entries: Array, rng_in: RandomNumberGenerator,
		node: String = "") -> void:
	pack = content_pack
	rules = rules_in
	queue = entries.duplicate(true)
	rng = rng_in
	node_id = node


func current() -> Dictionary:
	return queue[index]


func item() -> Dictionary:
	return pack.items[queue[index]["item"]]


func is_over() -> bool:
	return outcome != ""


func is_terminal() -> bool:
	return item()["type"] == "terminal"


## Shuffle the current item's options (stable until the next encounter). A
## terminal mission has no options: it opens a lab shell.
func start_encounter() -> void:
	order = []
	terminal = null
	if is_terminal():
		var it := item()
		terminal = TerminalSession.new(pack.labs[it["lab"]], pack.tool_docs, pack.concept_titles(), it, rules)
		return
	for o in item()["options"]:
		order.append(o["id"])
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = order[i]
		order[i] = order[j]
		order[j] = tmp


## [{letter, id, text}] in display order; letters are lower case a, b, c...
func options() -> Array:
	var by_id: Dictionary = {}
	for o in item()["options"]:
		by_id[o["id"]] = o
	var out: Array = []
	for i in order.size():
		out.append({"letter": char(97 + i), "id": order[i], "text": by_id[order[i]]["text"]})
	return out


func letter_of(option_id: String) -> String:
	return char(97 + order.find(option_id))


## Turn typed text ("c", "a d", "a,d", "AD") into picked option ids.
## {"ok": true, "picks": [...]} or {"ok": false, "error": "..."}. Invalid
## input is not an answer and costs nothing.
func parse(text: String) -> Dictionary:
	return Round.parse_picks(text, order, item()["type"])


## The parser behind parse(), for anything that shows options in `order` (an
## exam question too). `hint` ends the "not an answer" message.
static func parse_picks(text: String, order: Array, item_type: String,
		hint: String = "leave to end the round") -> Dictionary:
	var letters := ""
	for ch in text.to_lower():
		if ch == " " or ch == ",":
			continue
		# 1 is a, 2 is b ...: the same answer from the number row.
		letters += char(96 + int(ch)) if ch >= "1" and ch <= "9" else ch
	var n := order.size()
	var last := char(96 + n)
	if letters == "":
		return {"ok": false, "error": "Type your answer as letters a-%s (or digits 1-%d)." % [last, n]}
	var picks: Array = []
	for ch in letters:
		var idx: int = ch.unicode_at(0) - 97
		if idx < 0 or idx >= n:
			return {"ok": false, "error": "That is not an answer. Type letters a-%s, or %s." % [last, hint]}
		if picks.has(order[idx]):
			return {"ok": false, "error": "You listed '%s' twice." % ch}
		picks.append(order[idx])
	if item_type == "mcq" and picks.size() != 1:
		return {"ok": false, "error": "Choose exactly one letter (a-%s)." % last}
	return {"ok": true, "picks": picks}


## Score an answer and update the round. Returns everything the screen needs:
## credit, xp, trace_delta, streak, traced, picks (option ids chosen), correct
## (option ids), wrong (picked wrong options as {id, text, why}), requeue_gap
## (0 if none).
func submit(picks: Array) -> Dictionary:
	var it := item()
	var res := _record(Scoring.credit(it, picks))
	var wrong: Array = []
	for o in it["options"]:
		if picks.has(o["id"]) and not it["answer"].has(o["id"]):
			wrong.append({"id": o["id"], "text": o["text"], "why": o.get("why", "")})
	res["picks"] = picks.duplicate()
	res["correct"] = it["answer"].duplicate()
	res["wrong"] = wrong
	return res


## Score the lab mission from its session: 1.0 for a right answer on the first
## try, a reduced share on the second, otherwise 0.
func submit_terminal() -> Dictionary:
	var t := terminal
	var res := _record(t.credit())
	res["terminal"] = {"given": t.given.duplicate(), "tries": t.tries, "solved_on": t.solved_on,
			"accept": t.mission["answer"]["accept"], "commands": t.history.duplicate()}
	return res


## Streak, XP, Trace, requeue and outcome for an answer worth `credit`.
func _record(credit: float) -> Dictionary:
	var entry := current()
	var it := item()
	if credit >= 1.0:
		streak += 1
		full += 1
	else:
		streak = 0
	best_streak = maxi(best_streak, streak)
	var gained := Scoring.xp(it, credit, streak, rules)
	xp += gained
	var delta := 0 if trace_off else Scoring.trace_delta(credit, rules)
	trace = maxi(0, trace + delta)
	trace_peak = maxi(trace_peak, trace)
	answered += 1
	var gap := 0
	if credit < 1.0 and not requeued.has(entry["concept"]):
		gap = _requeue(entry)
	var traced := trace >= rules.trace_limit
	if traced:
		outcome = "traced"
	return {"credit": credit, "xp": gained, "trace_delta": delta, "streak": streak,
			"traced": traced, "requeue_gap": gap, "item": it, "concept": entry["concept"]}


## Move on. False when the round has ended.
func advance() -> bool:
	if outcome != "":
		return false
	index += 1
	if index >= queue.size():
		outcome = "complete"
		return false
	start_encounter()
	return true


func leave() -> void:
	if outcome == "":
		outcome = "left"


## Put a missed concept back in the queue `requeue_gap` encounters ahead, as a
## different item of the same concept when there is one. Returns the real gap.
func _requeue(entry: Dictionary) -> int:
	requeued[entry["concept"]] = true
	var queued: Dictionary = {}
	for e in queue:
		queued[e["item"]] = true
	var choices: Array = []
	for it in pack.items_for_concept(entry["concept"]):
		if not queued.has(it["id"]) and pack.round_item(it):
			choices.append(it)
	choices.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if Pack.review_rank(a) != Pack.review_rank(b):
			return Pack.review_rank(a) < Pack.review_rank(b)
		return a["id"] < b["id"])
	var item_id: String = choices[0]["id"] if not choices.is_empty() else entry["item"]
	var gap := rng.randi_range(rules.requeue_min, rules.requeue_max)
	var pos := mini(index + gap, queue.size())
	queue.insert(pos, {"item": item_id, "concept": entry["concept"], "kind": "retry"})
	return pos - index
