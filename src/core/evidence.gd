class_name Evidence
extends RefCounted
## Scores an evidence hunt (README "Phase 3 plan"). Pure integers, so a perfect
## hunt is exactly 1.0: each real flaw is worth 100 points, `line_percent` for
## flagging its line and `reason_percent` for an accepted reason; every false
## flag costs `false_flag_percent * flaws` points; credit = points / (100 * flaws),
## floored at 0.


## Reasons that count as right for a flaw, the first one being the one shown.
static func accepted(flaw: Dictionary) -> Array:
	if flaw.has("reasons"):
		return flaw["reasons"]
	return [flaw["reason"]]


## `lines` are the artifact's lines (index 0 is line 1); `flags` maps a line
## number to the reason key the learner gave. Returns {credit, points, max,
## found, missed, false_flags, lines}. `lines` here holds one outcome per line
## that matters, in file order: {line, kind "found"|"missed"|"false", text,
## said, reason_ok, accepted, explain}.
static func score(item: Dictionary, lines: Array, flags: Dictionary, rules: Rules) -> Dictionary:
	var flaws: Array = item["flaws"]
	var decoys: Dictionary = {}
	for d in item.get("decoys", []):
		decoys[int(d["line"])] = d
	var by_line: Dictionary = {}
	for f in flaws:
		by_line[int(f["line"])] = f

	var points := 0
	var found := 0
	var false_flags := 0
	var outcomes: Array = []
	var numbers: Array = by_line.keys()
	for n in flags:
		if not by_line.has(int(n)):
			numbers.append(int(n))
	numbers.sort()
	for n in numbers:
		var text: String = (lines[n - 1] as String).strip_edges() if n >= 1 and n <= lines.size() else ""
		var said: String = str(flags.get(n, ""))
		if by_line.has(n):
			var flaw: Dictionary = by_line[n]
			if flags.has(n):
				var ok := accepted(flaw).has(said)
				points += rules.evidence_line_percent + (rules.evidence_reason_percent if ok else 0)
				found += 1
				outcomes.append({"line": n, "kind": "found", "text": text, "said": said, "reason_ok": ok,
						"accepted": accepted(flaw), "explain": flaw["explain"]})
			else:
				outcomes.append({"line": n, "kind": "missed", "text": text, "said": "", "reason_ok": false,
						"accepted": accepted(flaw), "explain": flaw["explain"]})
		else:
			false_flags += 1
			var why: String = decoys[n]["explain"] if decoys.has(n) else "This line is fine."
			outcomes.append({"line": n, "kind": "false", "text": text, "said": said, "reason_ok": false,
					"accepted": [], "explain": why})
	var total := 100 * flaws.size()
	points -= false_flags * rules.evidence_false_flag_percent * flaws.size()
	return {"credit": clampf(float(points) / float(total), 0.0, 1.0), "points": points, "max": total,
			"found": found, "missed": flaws.size() - found, "false_flags": false_flags, "lines": outcomes}
