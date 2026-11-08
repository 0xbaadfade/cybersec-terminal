class_name Matching
extends RefCounted
## Scores a match question (README "Student simplification Part 2 plan"): each
## pair has exactly one right category, an unfiled pair counts as wrong, and
## credit = pairs filed correctly / pairs. There is no penalty for a wrong
## guess, so exactly 1.0 means every pair is in its right place.


## `assign` maps a pair's index in item["pairs"] to the category id the learner
## chose. Returns {credit, right, total, rows}; `rows` has one entry per pair in
## authored order: {index, text, said, correct, ok, explain}.
static func score(item: Dictionary, assign: Dictionary) -> Dictionary:
	var pairs: Array = item["pairs"]
	var right := 0
	var rows: Array = []
	for i in pairs.size():
		var said: String = str(assign.get(i, ""))
		var ok: bool = said == pairs[i]["category"]
		if ok:
			right += 1
		rows.append({"index": i, "text": pairs[i]["text"], "said": said, "correct": pairs[i]["category"],
				"ok": ok, "explain": pairs[i]["explain"]})
	return {"credit": float(right) / float(pairs.size()), "right": right, "total": pairs.size(), "rows": rows}


## The text of category `id` in `item` (the id itself if it is unknown).
static func category_text(item: Dictionary, id: String) -> String:
	for c in item["categories"]:
		if c["id"] == id:
			return c["text"]
	return id
