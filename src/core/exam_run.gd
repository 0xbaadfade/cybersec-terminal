class_name ExamRun
extends RefCounted
## One exam simulation in progress (docs/improvement-plan.md, phase 5): a fixed
## list of mcq/multi questions, the learner's answers and flags, a clock, and
## the score at the end. It never touches a Profile; the router applies the
## result. No feedback is given while it runs.
##
## A full exam also holds PBQs (evidence, match, order; README "Student
## simplification Part 2 plan"). Each has a session in `sessions` (EvidenceSession,
## MatchSession or OrderSession) that is scored from its own state, and `answers[i]`
## then means "the learner touched this one".

var pack: Pack
var rules: Rules
var entries: Array = []  # {"item", "concept", "domain", "order": [option ids]}
var answers: Dictionary = {}  # question index -> picked option ids (a PBQ: its response)
var sessions: Dictionary = {}  # question index -> the session of a PBQ
var flags: Dictionary = {}  # question index -> true
var index := 0
var started_at := 0  # unix seconds
var minutes := 0  # 0 means untimed
## True for an exam asked for at the pack's standard length or more: only those are recorded (README "Skill tree Phase T2 plan").
var full := false


func _init(content_pack: Pack, picked: Array, rng: RandomNumberGenerator, start: int, limit_minutes: int,
		rules_in: Rules = null) -> void:
	pack = content_pack
	rules = rules_in if rules_in != null else Rules.load_default()
	started_at = start
	minutes = maxi(0, limit_minutes)
	for e in picked:
		var item: Dictionary = pack.items[e["item"]]
		var order: Array = []
		if Pack.is_exam_pbq(item):
			sessions[entries.size()] = _new_session(item, rng)
		else:
			for o in item["options"]:
				order.append(o["id"])
			for i in range(order.size() - 1, 0, -1):
				var j := rng.randi_range(0, i)
				var tmp: Variant = order[i]
				order[i] = order[j]
				order[j] = tmp
		var entry: Dictionary = e.duplicate()
		entry["order"] = order
		entries.append(entry)


func _new_session(item: Dictionary, rng: RandomNumberGenerator) -> Variant:
	match item["type"]:
		"evidence":
			return EvidenceSession.new(pack.artifact_lines(item["id"]), pack.evidence_reasons)
		"match":
			return MatchSession.new(item, rng)
	return OrderSession.new(item, rng)


func size() -> int:
	return entries.size()


func item_at(i: int) -> Dictionary:
	return pack.items[entries[i]["item"]]


## True when question `i` is a PBQ (it has a session instead of options).
func is_pbq_at(i: int) -> bool:
	return sessions.has(i)


func pbq_total() -> int:
	return sessions.size()


## The session of the current question, or null when it is an ordinary one.
func session() -> Variant:
	return sessions.get(index)


## Hand an input to the current PBQ (see the sessions' `handle`). Returns "" when
## it worked, else what to tell the learner; the answered state is kept in step.
func pbq_command(verb: String, rest: String) -> String:
	var s: Variant = sessions[index]
	var problem: String = s.handle(verb, rest)
	if s.has_answer():
		var response: Variant = s.response()
		answers[index] = response.duplicate(true)
	else:
		answers.erase(index)
	return problem


## True while the current question is an evidence hunt with its reason menu open.
func reason_pending() -> bool:
	return sessions.has(index) and sessions[index] is EvidenceSession and sessions[index].pending > 0


## Keys a single press can mean on the current question, 0 when it takes none.
func single_key_choices() -> int:
	if sessions.has(index):
		return sessions[index].single_key_choices()
	return entries[index]["order"].size() if item_at(index)["type"] == "mcq" else 0


## [{letter, id, text}] of question `i` in the order it is shown.
func options_at(i: int) -> Array:
	var by_id: Dictionary = {}
	for o in item_at(i)["options"]:
		by_id[o["id"]] = o
	var out: Array = []
	for k in entries[i]["order"].size():
		var oid: String = entries[i]["order"][k]
		out.append({"letter": char(97 + k), "id": oid, "text": by_id[oid]["text"]})
	return out


func parse(text: String) -> Dictionary:
	return Round.parse_picks(text, entries[index]["order"], item_at(index)["type"], "help lists the commands")


## Record (or replace) the answer to the current question.
func answer(picks: Array) -> void:
	answers[index] = picks.duplicate()


## "ac" for a question answered with its first and third shown options, "" if blank.
## A PBQ is "PBQ" once touched.
func letters_at(i: int) -> String:
	if not answers.has(i):
		return ""
	if sessions.has(i):
		return "pbq"
	var letters: Array = []
	for oid in answers[i]:
		letters.append(char(97 + entries[i]["order"].find(oid)))
	letters.sort()
	return "".join(letters)


## Move to question number `n` (1-based). False when there is no such question.
func goto(n: int) -> bool:
	if n < 1 or n > size():
		return false
	index = n - 1
	return true


func toggle_flag() -> bool:
	if flags.has(index):
		flags.erase(index)
	else:
		flags[index] = true
	return flags.has(index)


func answered_count() -> int:
	return answers.size()


func flagged_numbers() -> Array:
	var out: Array = []
	for i in size():
		if flags.has(i):
			out.append(i + 1)
	return out


func blank_numbers() -> Array:
	var out: Array = []
	for i in size():
		if not answers.has(i):
			out.append(i + 1)
	return out


func deadline() -> int:
	return started_at + minutes * 60


## Seconds left at `now`, or -1 for an untimed exam.
func seconds_left(now: int) -> int:
	return -1 if minutes <= 0 else maxi(0, deadline() - now)


func expired(now: int) -> bool:
	return minutes > 0 and now >= deadline()


## Credit of question `i` (0 when blank).
func credit_at(i: int) -> float:
	if not answers.has(i):
		return 0.0
	if sessions.has(i):
		return float(pbq_score(i)["credit"])
	return Scoring.credit(item_at(i), answers[i])


## The scorer's full result for the PBQ at `i` (Evidence.score, Matching.score or
## Ordering.score); an untouched PBQ scores as blank.
func pbq_score(i: int) -> Dictionary:
	var it := item_at(i)
	var s: Variant = sessions[i]
	match it["type"]:
		"evidence":
			return Evidence.score(it, pack.artifact_lines(it["id"]), s.flags, rules)
		"match":
			return Matching.score(it, s.assign)
	return Ordering.score(it, s.seq if s.touched else [])


## The score: {questions, answered, blank, credit, percent, full, multi_total,
## multi_not_full, domains: [{id, title, weight, asked, credit, percent}],
## missed: [{concept, title, objective, count}]}. `percent` is credit earned over
## questions asked, rounded. A blank question counts as a miss.
func result() -> Dictionary:
	var n := size()
	var total := 0.0
	var full := 0
	var multi_total := 0
	var multi_not_full := 0
	var pbq_credit := 0.0
	var per_domain: Dictionary = {}
	var missed: Dictionary = {}
	for i in n:
		var c := credit_at(i)
		total += c
		if c >= 1.0:
			full += 1
		if sessions.has(i):
			pbq_credit += c
		if item_at(i)["type"] == "multi":
			multi_total += 1
			if c < 1.0:
				multi_not_full += 1
		var d: Dictionary = per_domain.get(entries[i]["domain"], {"asked": 0, "credit": 0.0})
		d["asked"] += 1
		d["credit"] += c
		per_domain[entries[i]["domain"]] = d
		if c < 1.0:
			missed[entries[i]["concept"]] = int(missed.get(entries[i]["concept"], 0)) + 1
	var domains: Array = []
	for dom in pack.domains:
		if not per_domain.has(dom["id"]):
			continue
		var d: Dictionary = per_domain[dom["id"]]
		domains.append({"id": dom["id"], "title": dom["title"], "weight": int(dom["weight"]), "asked": d["asked"],
				"credit": d["credit"], "percent": roundi(float(d["credit"]) * 100.0 / float(d["asked"]))})
	var missed_list: Array = []
	for cid in missed:
		missed_list.append({"concept": cid, "title": pack.concepts[cid]["title"],
				"objective": pack.concepts[cid]["objective"], "count": missed[cid]})
	missed_list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["concept"] < b["concept"] if a["count"] == b["count"] else a["count"] > b["count"])
	return {
		"questions": n, "answered": answers.size(), "blank": n - answers.size(), "credit": total,
		"percent": roundi(total * 100.0 / float(n)) if n > 0 else 0, "full": full,
		"multi_total": multi_total, "multi_not_full": multi_not_full,
		"pbqs": sessions.size(), "pbq_percent": roundi(pbq_credit * 100.0 / float(sessions.size())) if not sessions.is_empty() else 0,
		"domains": domains, "missed": missed_list,
	}
