class_name ExamScreen
extends RefCounted
## The text of the exam simulation: a question, the question list and the
## result. Pure formatting over an ExamRun; the router decides when to show it.

const S_NORMAL := Lines.S_NORMAL
const S_DIM := Lines.S_DIM
const S_ACCENT := Lines.S_ACCENT
const S_ERROR := Lines.S_ERROR
const S_OK := Lines.S_OK
const GRID_COLUMNS := 8
const MISSED_SHOWN := 10
const TITLE_WIDTH := 42  # the longest domain title of a pack plus a space


## m:ss, or h:mm:ss from an hour up. "untimed" for -1.
static func clock_text(seconds: int) -> String:
	if seconds < 0:
		return "untimed"
	if seconds >= 3600:
		return "%d:%02d:%02d" % [seconds / 3600, (seconds % 3600) / 60, seconds % 60]
	return "%d:%02d" % [seconds / 60, seconds % 60]


## "1 question", "20 questions".
static func plural(n: int, noun: String) -> String:
	return "%d %s%s" % [n, noun, "" if n == 1 else "s"]


## Question `exam.index`; `shown` is the output of a `show` command, if the
## item has one. The objective and concept are never named (the real exam
## does not).
static func question(exam: ExamRun, now: int, shown: Array = []) -> Array:
	var i := exam.index
	var it := exam.item_at(i)
	var head := "EXAM  //  question %d of %d  //  %s left" % [i + 1, exam.size(), clock_text(exam.seconds_left(now))]
	if exam.is_pbq_at(i):
		head += "  //  " + PbqScreen.kind_label(it)
	if exam.flags.has(i):
		head += "  //  FLAGGED"
	if exam.is_pbq_at(i):
		return [Lines.make(head, S_ACCENT)] + PbqScreen.body(exam, i)
	var out: Array = [Lines.make(head, S_ACCENT), Lines.make(it["stem"]), Lines.make("")]
	out.append_array(shown)
	if not shown.is_empty():
		out.append(Lines.make(""))
	var picked: Array = exam.answers.get(i, [])
	for o in exam.options_at(i):
		var mark := ">" if picked.has(o["id"]) else " "
		out.append(Lines.make("%s %s  %s" % [mark, (o["letter"] as String).to_upper(), o["text"]], S_ACCENT if mark == ">" else S_NORMAL))
	out.append(Lines.make(""))
	var last := char(64 + exam.options_at(i).size())
	if it["type"] == "multi":
		out.append(Lines.make("Choose ALL that apply: letters or digits, e.g. a d, then Enter.", S_DIM))
	else:
		out.append(Lines.make("Choose ONE: a letter A-%s or a digit, no Enter needed." % last, S_DIM))
	out.append(Lines.make(("Your answer: %s" % exam.letters_at(i).to_upper()) if exam.answers.has(i) else "Not answered yet.", S_DIM))
	out.append(Lines.make("Enter or next | prev | goto N | flag | list | submit | help", S_DIM))
	return out


## The grid of every question: its answer, or - when blank, with * if flagged.
static func listing(exam: ExamRun) -> Array:
	var out: Array = [Lines.make("EXAM  //  question list", S_ACCENT)]
	var row := ""
	for i in exam.size():
		var cell := exam.letters_at(i).to_upper() if exam.answers.has(i) else "-"
		row += "%3d %-4s" % [i + 1, cell + ("*" if exam.flags.has(i) else "")]
		if (i + 1) % GRID_COLUMNS == 0 or i == exam.size() - 1:
			out.append(Lines.make(row))
			row = ""
	out.append(Lines.make(""))
	out.append(Lines.make("%d answered, %d blank, %d flagged (*)" % [
			exam.answered_count(), exam.size() - exam.answered_count(), exam.flags.size()], S_DIM))
	var blank := exam.blank_numbers()
	if not blank.is_empty():
		out.append(Lines.make("Blank: %s" % _numbers(blank), S_DIM))
	if not exam.flags.is_empty():
		out.append(Lines.make("Flagged: %s" % _numbers(exam.flagged_numbers()), S_DIM))
	out.append(Lines.make("goto N jumps to a question; submit ends the exam.", S_DIM))
	return out


static func _numbers(nums: Array) -> String:
	var parts: Array = []
	for n in nums:
		parts.append(str(n))
	return " ".join(parts)


## The result screen. `used` is seconds spent; `timed_out` when the clock ended it.
static func result(exam: ExamRun, res: Dictionary, used: int, timed_out: bool, pass_text: String) -> Array:
	var pack := exam.pack
	var out: Array = [Lines.make(""), Lines.make("TIME IS UP  //  EXAM SUBMITTED AS IT STOOD" if timed_out else "EXAM SUBMITTED", S_ERROR if timed_out else S_ACCENT)]
	var timing := "time used %s" % clock_text(used)
	if exam.minutes > 0:
		timing += " of %s" % clock_text(exam.minutes * 60)
	out.append(Lines.make("%s: %d answered, %d left blank (counted as missed).   %s" % [
			plural(res["questions"], "question"), res["answered"], res["blank"], timing], S_DIM))
	out.append(Lines.make("Credit earned: %d%%   (%d of %d fully correct)" % [res["percent"], res["full"], res["questions"]], S_OK))
	if res["pbqs"] > 0:
		out.append(Lines.make("Hands-on questions: %d asked, credit %d%%." % [res["pbqs"], res["pbq_percent"]], S_DIM))
	if res["multi_total"] > 0:
		out.append(Lines.make("Multi-answer questions: %d asked, %d not fully right (partial credit is counted)." % [
				res["multi_total"], res["multi_not_full"]], S_DIM))
	out.append(Lines.make(""))
	out.append(Lines.make("%-*s%5s%8s%9s" % [TITLE_WIDTH + 5, "By domain", "asked", "weight", "credit"], S_ACCENT))
	for d in res["domains"]:
		out.append(Lines.make("  %s  %-*s%5d    %3d%%     %3d%%" % [d["id"], TITLE_WIDTH, d["title"], d["asked"], d["weight"], d["percent"]]))
	out.append(Lines.make(""))
	out.append_array(_pass_lines(pack.exam, res["percent"], pass_text))
	if not res["missed"].is_empty():
		out.append(Lines.make(""))
		out.append(Lines.make("Concepts you missed (they come back for review tomorrow):", S_ACCENT))
		var shown := 0
		for m in res["missed"]:
			if shown >= MISSED_SHOWN:
				out.append(Lines.make("  ... and %d more" % (res["missed"].size() - MISSED_SHOWN), S_DIM))
				break
			out.append(Lines.make("  %-5s %-46s x%d" % [m["objective"], m["title"], m["count"]]))
			shown += 1
	if res["pbqs"] > 0:
		out.append(Lines.make(""))
		out.append_array(PbqScreen.review(exam))
	return out


## The pass line. A percentage pass mark is compared; a scaled one is only
## named, because the raw-to-scaled conversion is not published.
static func _pass_lines(exam_block: Dictionary, percent: int, pass_text: String) -> Array:
	if exam_block.has("pass_percent"):
		var need := int(exam_block["pass_percent"])
		return [Lines.make("Pass mark %d%%: you earned %d%%, %s." % [need, percent, "above it" if percent >= need else "below it"],
				S_OK if percent >= need else S_ERROR)]
	if exam_block.has("pass_score"):
		return [Lines.make("The real exam is %s." % pass_text, S_NORMAL),
				Lines.make("That scale is not a percentage and the way answers become a scaled score is not published, so this simulation", S_DIM),
				Lines.make("shows a plain percent and cannot say whether you would pass.", S_DIM)]
	return []
