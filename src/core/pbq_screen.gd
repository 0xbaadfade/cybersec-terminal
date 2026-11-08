class_name PbqScreen
extends RefCounted
## The text of the exam's performance-based questions (README "Student
## simplification Part 2 plan"): the working screen of an evidence hunt, a match
## and an order question, and the hands-on review on the result screen. Pure
## formatting over an ExamRun and its sessions.

const S_NORMAL := Lines.S_NORMAL
const S_DIM := Lines.S_DIM
const S_ACCENT := Lines.S_ACCENT
const S_ERROR := Lines.S_ERROR
const S_OK := Lines.S_OK
const WRAP_WIDTH := 92
const NAV_HINT := "next | prev (or Left, Right) | list | flag | submit | help"
const KIND_NAMES := {"evidence": "flag the weak lines", "match": "match", "order": "put in order"}


## The working screen of PBQ question `i` (everything under the exam header).
static func body(exam: ExamRun, i: int) -> Array:
	match exam.item_at(i)["type"]:
		"evidence":
			return _evidence(exam, i)
		"match":
			return _match(exam, i)
	return _order(exam, i)


## The one-line name shown in the header: "PBQ: match".
static func kind_label(item: Dictionary) -> String:
	return "PBQ: %s" % KIND_NAMES.get(item["type"], item["type"])


static func _l(text: String, style: String = S_NORMAL) -> Dictionary:
	return Lines.make(text, style)


static func _evidence(exam: ExamRun, i: int) -> Array:
	var it := exam.item_at(i)
	var s: EvidenceSession = exam.sessions[i]
	var art: Dictionary = it["artifact"]
	var out: Array = [
		_l(it["stem"]),
		_l("%s    FLAGS %d    lines %d-%d of %d" % [art["title"], s.flags.size(), s.top, s.last_visible(), s.lines.size()], S_DIM),
		_l("")]
	var wide := 0
	for n in range(s.top, s.last_visible() + 1):
		wide = maxi(wide, mini((s.lines[n - 1] as String).length(), 60))
	for n in range(s.top, s.last_visible() + 1):
		var text: String = s.lines[n - 1]
		var marker := ">" if n == s.cursor else ("*" if s.flags.has(n) else " ")
		var row := "%s %3d  %s" % [marker, n, text]
		if s.flags.has(n):
			row = "%s   [%s]" % [row.rpad(6 + wide), s.label_of(s.flags[n])]
		out.append(_l(row, S_OK if s.flags.has(n) else (S_ACCENT if n == s.cursor else S_NORMAL)))
	if s.pending > 0:
		out.append(_l(""))
		out.append(_l("Why is line %d a problem?   (press a number, or Esc to cancel)" % s.pending, S_ACCENT))
		for k in s.reasons.size():
			out.append(_l("  %d  %s" % [k + 1, s.reasons[k]["label"]]))
		out.append(_l("  %d  not a problem (remove the flag)" % s.clear_digit()))
		return out
	out.append(_l(""))
	out.append(_l("Up/Down move   Enter or f flag a line   f <n> [digit]   x unflag   go <n>", S_DIM))
	out.append(_l(NAV_HINT, S_DIM))
	return out


static func _match(exam: ExamRun, i: int) -> Array:
	var s: MatchSession = exam.sessions[i]
	var out: Array = [_l(exam.item_at(i)["stem"]), _l("")]
	for k in s.categories.size():
		out.append(_l("  %s  %s" % [char(65 + k), s.categories[k]["text"]], S_ACCENT))
	out.append(_l(""))
	for row in s.rows.size():
		var filed := s.filed_at(row)
		var mark := "[%s]" % (s.letter_of(filed) if filed != "" else " ")
		var text := "%s %d  %s  %s" % [">" if row == s.cursor else " ", row + 1, mark, s.pair_at(row)["text"]]
		out.append(_l(text, S_ACCENT if row == s.cursor else (S_OK if filed != "" else S_NORMAL)))
	out.append(_l(""))
	out.append(_l("%d of %d filed.   Up/Down choose a row, press %s to file it." % [s.filed_count(), s.rows.size(), s.keys_text()], S_DIM))
	out.append(_l("Enter cycles the row's category   x clears it   3 b files row 3 under B", S_DIM))
	out.append(_l(NAV_HINT, S_DIM))
	return out


static func _order(exam: ExamRun, i: int) -> Array:
	var s: OrderSession = exam.sessions[i]
	var out: Array = [_l(exam.item_at(i)["stem"]), _l("")]
	for pos in s.seq.size():
		var at := pos == s.cursor
		var marker := " "
		if at:
			marker = "^" if s.lifted else ">"
		out.append(_l("%s %d  %s" % [marker, pos + 1, s.step_at(pos)["text"]],
				S_OK if at and s.lifted else (S_ACCENT if at else S_NORMAL)))
	out.append(_l(""))
	if s.lifted:
		out.append(_l("Step lifted: Up/Down carry it, Enter sets it down.   Esc sets it down where it is.", S_ACCENT))
	else:
		out.append(_l("Up/Down choose a step, Enter lifts it.   m 4 1 moves step 4 to position 1.", S_DIM))
	out.append(_l(NAV_HINT, S_DIM))
	return out


## The help lines for the PBQ on screen.
static func help(exam: ExamRun, i: int) -> Array:
	match exam.item_at(i)["type"]:
		"evidence":
			return [_l("Up/Down move the cursor. Enter (or f) flags the line, then press the number of the reason; f <n> <digit> does both.", S_DIM),
					_l("x unflags a line, go <n> jumps. Finding the line and naming the reason both earn credit; flagging a fine line costs.", S_DIM)]
		"match":
			return [_l("Up/Down choose a row, then press its category letter (A, B, C ...) or digit. Enter cycles the row's category; x clears it.", S_DIM),
					_l("3 b files row 3 under B. Rows left blank count as wrong.", S_DIM)]
	return [_l("Up/Down choose a step. Enter lifts it, Up/Down carry it, Enter sets it down. m 4 1 moves step 4 to position 1.", S_DIM),
			_l("Credit depends on how many pairs of steps are in the right order, so a small slip costs a little.", S_DIM)]


# --- the review on the result screen --------------------------------------------

## One block per PBQ: its credit, and for anything not perfect what was missed
## with the authored explanations. Empty when the exam held no PBQs.
static func review(exam: ExamRun) -> Array:
	var out: Array = []
	if exam.pbq_total() == 0:
		return out
	out.append(_l("Hands-on questions: what each one was after", S_ACCENT))
	for i in exam.size():
		if not exam.is_pbq_at(i):
			continue
		var it := exam.item_at(i)
		var sc := exam.pbq_score(i)
		var credit: float = sc["credit"]
		var touched := exam.answers.has(i)
		var head := "  Q%d  %s   %d%%%s" % [i + 1, kind_label(it), roundi(credit * 100.0), "" if touched else "   (not attempted)"]
		out.append(_l(""))
		out.append(_l(head, S_OK if credit >= 1.0 else (S_ACCENT if credit > 0.0 else S_ERROR)))
		out.append(_l("      " + _short(it["stem"], 84), S_DIM))
		if credit >= 1.0:
			continue
		match it["type"]:
			"evidence":
				out.append_array(_evidence_review(exam.sessions[i], sc))
			"match":
				out.append_array(_match_review(it, sc))
			_:
				out.append_array(_order_review(sc))
		out.append(_l(""))
		var explain := Pack.explain_of(it)
		if explain != "":
			for row in wrap_text(explain, WRAP_WIDTH):
				out.append(_l("      " + row, S_DIM))
		for line in Pack.reference_lines(it):
			for row in wrap_text(line, WRAP_WIDTH):
				out.append(_l("      " + row, S_DIM))
	return out


static func _evidence_review(s: EvidenceSession, sc: Dictionary) -> Array:
	var out: Array = [_l("      %d of %d flaws found, %d false flag%s." % [
			sc["found"], sc["found"] + sc["missed"], sc["false_flags"], "" if sc["false_flags"] == 1 else "s"], S_DIM)]
	for o in sc["lines"]:
		if o["kind"] == "found" and o["reason_ok"]:
			continue
		var head := "      %-6s  line %d  %s" % [str(o["kind"]).to_upper(), o["line"], o["text"]]
		var style := S_ERROR
		if o["kind"] == "found":
			head += "   you said: %s  (it is: %s)" % [s.label_of(o["said"]), _reasons(s, o["accepted"])]
			style = S_ACCENT
		elif o["kind"] == "missed":
			head += "   (%s)" % _reasons(s, o["accepted"])
		out.append(_l(head, style))
		for row in wrap_text(o["explain"], WRAP_WIDTH - 4):
			out.append(_l("              %s" % row))
	return out


static func _match_review(item: Dictionary, sc: Dictionary) -> Array:
	var out: Array = [_l("      %d of %d filed correctly." % [sc["right"], sc["total"]], S_DIM)]
	for r in sc["rows"]:
		if r["ok"]:
			continue
		var you: String = Matching.category_text(item, r["said"]) if r["said"] != "" else "(left blank)"
		out.append(_l("      WRONG   %s" % r["text"], S_ERROR))
		out.append(_l("              you: %s   right: %s" % [you, Matching.category_text(item, r["correct"])]))
		for row in wrap_text(r["explain"], WRAP_WIDTH - 4):
			out.append(_l("              %s" % row, S_DIM))
	return out


static func _order_review(sc: Dictionary) -> Array:
	var out: Array = [_l("      The right order (with where you put each step):", S_DIM)]
	for r in sc["rows"]:
		var put := "" if r["ok"] else ("   (you put it %s)" % _ordinal(r["position"]) if r["position"] > 0 else "   (not placed)")
		out.append(_l("      %d  %s%s" % [r["index"] + 1, r["text"], put], S_OK if r["ok"] else S_ERROR))
		for row in wrap_text(r["explain"], WRAP_WIDTH - 4):
			out.append(_l("              %s" % row, S_DIM))
	return out


static func _reasons(s: EvidenceSession, keys: Array) -> String:
	var labels: Array = []
	for k in keys:
		labels.append(s.label_of(k))
	return " or ".join(labels)


static func _ordinal(n: int) -> String:
	var suffix := "th"
	if n % 100 < 11 or n % 100 > 13:
		suffix = {1: "st", 2: "nd", 3: "rd"}.get(n % 10, "th")
	return "%d%s" % [n, suffix]


static func _short(text: String, width: int) -> String:
	return text if text.length() <= width else text.substr(0, width - 3) + "..."


## Greedy word wrap, so an indented paragraph stays indented on screen.
static func wrap_text(text: String, width: int) -> Array:
	var rows: Array = []
	var row := ""
	for word in text.split(" ", false):
		if row != "" and row.length() + 1 + word.length() > width:
			rows.append(row)
			row = word
		else:
			row = word if row == "" else row + " " + word
	if row != "":
		rows.append(row)
	return rows
