class_name Ordering
extends RefCounted
## Scores an order question (README "Student simplification Part 2 plan").
## For every pair of steps the learner's order either agrees with the right
## order or not: credit = (agreeing - disagreeing) / all pairs, floored at 0.
## Exactly 1.0 only for the perfect order; the exact reverse earns 0.


## `seq` is the learner's order as step indexes into item["steps"] (which is
## written in the right order). Returns {credit, agree, disagree, pairs, rows};
## `rows` follows the RIGHT order: {index, text, explain, position, ok}, where
## `position` is where the learner put that step (1-based) and `ok` is true when
## it is the same as its right position.
static func score(item: Dictionary, seq: Array) -> Dictionary:
	var steps: Array = item["steps"]
	var n := steps.size()
	var pos: Dictionary = {}
	for k in seq.size():
		pos[int(seq[k])] = k
	var agree := 0
	var disagree := 0
	for a in n:
		for b in range(a + 1, n):
			if not pos.has(a) or not pos.has(b):
				disagree += 1
			elif int(pos[a]) < int(pos[b]):
				agree += 1
			else:
				disagree += 1
	var total := n * (n - 1) / 2
	var rows: Array = []
	for i in n:
		var where: int = int(pos[i]) + 1 if pos.has(i) else 0
		rows.append({"index": i, "text": steps[i]["text"], "explain": steps[i]["explain"],
				"position": where, "ok": where == i + 1})
	return {"credit": clampf(float(agree - disagree) / float(total), 0.0, 1.0),
			"agree": agree, "disagree": disagree, "pairs": total, "rows": rows}
