class_name Pack
extends RefCounted
## A certification content pack, loaded from a directory of JSON (README
## "Modular certification packs"). The engine knows nothing about any
## particular certification; everything it shows comes from here.
##
## load_dir() never throws: problems are collected in `errors` (the pack is
## unusable) and `warnings` (worth a look), so tools/validate_pack.gd and the
## tests can report all of them at once. Only items that pass validation end
## up in `items`.

const ITEM_TYPES: Array = ["mcq", "multi", "evidence", "terminal", "match", "order"]
## Performance-based items: an ordinary round never serves one (a skill pack's
## round may still serve a `terminal` mission, see round_item).
const PBQ_TYPES: Array = ["evidence", "terminal", "match", "order"]
## The PBQs the full exam may hold: none of them uses a command line.
const EXAM_PBQ_TYPES: Array = ["evidence", "match", "order"]
const MAX_CATEGORIES := 5
const MAX_PAIRS := 8
const MIN_STEPS := 3
const MAX_STEPS := 8
const MAX_ROW_TEXT := 80
const MAX_EXAM_PBQS := 10
const ARTIFACT_KINDS: Array = ["config", "log"]
const MAX_ARTIFACT_LINES := 60
const MAX_REASONS := 8
const MAX_REFERENCES := 8
const SOURCES: Array = ["hand", "ai"]
const MIN_ITEMS_PER_CONCEPT := 3

var dir := ""
var id := ""
var title := ""
var short := ""
var version := 0
var exam: Dictionary = {}
var domains: Array = []
var objectives: Array = []
var concepts: Dictionary = {}  # concept id -> {id, title, objective}
var items: Dictionary = {}  # item id -> item Dictionary (valid items only)
var ranks: Array = []  # optional [[name, xp], ...] replacing the engine's ladder
var rounds_include_labs := false  # a skill pack: terminal missions are served in rounds
var codex: Dictionary = {}  # concept id -> {definition, source, reviewed}
var evidence_reasons: Array = []  # [{key, label}] menu for evidence hunts
var artifacts: Dictionary = {}  # item id -> Array of the artifact's lines
var labs: Dictionary = {}  # lab id -> SimLab (valid labs only)
var tool_docs: Dictionary = {}  # tool name -> {summary, usage, flags, concepts, note}
var errors: Array = []
var warnings: Array = []
## Valid items with no `explain` (explanations are optional; the report notes how many).
var items_without_explain := 0

var _domain_ids: Dictionary = {}
var _objective_by_id: Dictionary = {}
var _by_concept: Dictionary = {}  # concept id -> Array of item ids


static func is_pbq(item: Dictionary) -> bool:
	return PBQ_TYPES.has(item["type"])


## A PBQ the full exam may hold (evidence, match, order).
static func is_exam_pbq(item: Dictionary) -> bool:
	return EXAM_PBQ_TYPES.has(item["type"])


## True when a round (not the exam) may serve `item`: an ordinary question, or a
## terminal mission in a pack that sets `rounds_include_labs`.
func round_item(item: Dictionary) -> bool:
	return not is_pbq(item) or (rounds_include_labs and item["type"] == "terminal")


static func load_dir(path: String) -> Pack:
	var pack := Pack.new()
	pack._load(path)
	return pack


func ok() -> bool:
	return errors.is_empty()


func objective(objective_id: String) -> Dictionary:
	return _objective_by_id.get(objective_id, {})


func domain_of_concept(concept_id: String) -> String:
	if not concepts.has(concept_id):
		return ""
	var obj: Dictionary = objective(concepts[concept_id]["objective"])
	return str(obj.get("domain", ""))


## concept id -> title, for the simulator's manual pages.
func concept_titles() -> Dictionary:
	var out: Dictionary = {}
	for cid in concepts:
		out[cid] = concepts[cid]["title"]
	return out


## The artifact lines of an evidence item (empty for any other item).
func artifact_lines(item_id: String) -> Array:
	return artifacts.get(item_id, [])


func items_for_concept(concept_id: String) -> Array:
	var out: Array = []
	for item_id in _by_concept.get(concept_id, []):
		out.append(items[item_id])
	return out


## Number of valid items, or just those in one domain.
func count_items(domain_id: String = "") -> int:
	if domain_id == "":
		return items.size()
	var n := 0
	for item in items.values():
		if domain_of_concept(item["concept_ids"][0]) == domain_id:
			n += 1
	return n


## concept id -> number of valid items that cover it.
func coverage() -> Dictionary:
	var out: Dictionary = {}
	for cid in concepts:
		out[cid] = _by_concept.get(cid, []).size()
	return out


func coverage_gaps(minimum: int = MIN_ITEMS_PER_CONCEPT) -> Array:
	var gaps: Array = []
	var cov := coverage()
	for cid in cov:
		if cov[cid] < minimum:
			gaps.append(cid)
	return gaps


## Concepts that have items but only PBQs (labs, hunts, match, order), which rounds never serve.
func lab_only_concepts() -> Array:
	var out: Array = []
	for cid in concepts:
		var its: Array = items_for_concept(cid)
		if its.is_empty():
			continue
		var ordinary := false
		for it in its:
			if round_item(it):
				ordinary = true
				break
		if not ordinary:
			out.append(cid)
	return out


func stats() -> Dictionary:
	var s := {"domains": domains.size(), "objectives": objectives.size(),
			"concepts": concepts.size(), "items": items.size(),
			"ai": 0, "hand": 0, "reviewed": 0}
	for item in items.values():
		s[item["source"]] += 1
		if item["reviewed"]:
			s["reviewed"] += 1
	return s


func report() -> String:
	var lines: Array = []
	var s := stats()
	lines.append("pack %s  \"%s\"  v%d" % [id, title, version])
	lines.append("  %d domains, %d objectives, %d concepts, %d items (hand %d, ai %d, reviewed %d)" % [
			s["domains"], s["objectives"], s["concepts"], s["items"], s["hand"], s["ai"], s["reviewed"]])
	lines.append("  codex: %d of %d concepts have a definition" % [codex.size(), concepts.size()])
	var pbq := pbq_counts()
	if int(pbq["evidence"]) + int(pbq["match"]) + int(pbq["order"]) > 0:
		lines.append("  exam PBQs: %d evidence, %d match, %d order (a full exam asks for %d)" % [pbq["evidence"], pbq["match"], pbq["order"], exam_pbq_count()])
	if not labs.is_empty():
		lines.append("  labs: %d (%s)" % [labs.size(), ", ".join(labs.keys())])
	var gaps := coverage_gaps()
	if not gaps.is_empty():
		var cov := coverage()
		var parts: Array = []
		for cid in gaps:
			parts.append("%s(%d)" % [cid, cov[cid]])
		lines.append("  coverage: %d of %d concepts have fewer than %d items: %s" % [
				gaps.size(), concepts.size(), MIN_ITEMS_PER_CONCEPT, ", ".join(parts)])
	var lab_only := lab_only_concepts()
	if not lab_only.is_empty():
		lines.append("  warning: %d concept%s performance-based questions only, so no round asks about them: %s" % [
				lab_only.size(), " has" if lab_only.size() == 1 else "s have", ", ".join(lab_only)])
	if items_without_explain > 0:
		lines.append("  note: %d of %d items have no explanation (optional, but learners learn more with one)" % [
				items_without_explain, items.size()])
	for w in warnings:
		lines.append("  warning: %s" % w)
	for e in errors:
		lines.append("  ERROR: %s" % e)
	lines.append("  %s" % ("OK" if ok() else "FAILED (%d errors)" % errors.size()))
	return "\n".join(lines)


# --- loading -----------------------------------------------------------

func _load(path: String) -> void:
	dir = path.trim_suffix("/")
	var meta: Variant = _read_json(dir.path_join("pack.json"), "pack.json")
	if typeof(meta) != TYPE_DICTIONARY:
		if errors.is_empty():
			errors.append("pack.json: expected a JSON object")
		return
	_load_meta(meta)
	_load_labs()
	_load_items()
	_load_codex()
	_load_tools()
	_check_exam_pbqs()


## The number of PBQs a full exam asks for (0 when the pack sets none).
func exam_pbq_count() -> int:
	return int(exam.get("pbqs", 0)) if Pack.exam_problem(exam) == "" else 0


## Item ids of each exam PBQ type: {type -> count}.
func pbq_counts() -> Dictionary:
	var out: Dictionary = {}
	for t in EXAM_PBQ_TYPES:
		out[t] = 0
	for item in items.values():
		if is_exam_pbq(item):
			out[item["type"]] += 1
	return out


func _check_exam_pbqs() -> void:
	var want := exam_pbq_count()
	if want == 0:
		return
	var have := 0
	for n in pbq_counts().values():
		have += int(n)
	if have < want:
		warnings.append("exam asks for %d PBQs but the pack has only %d evidence, match and order items" % [want, have])


func _read_json(path: String, label: String) -> Variant:
	if not FileAccess.file_exists(path):
		errors.append("%s: file not found" % label)
		return null
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		errors.append("%s line %d: %s" % [label, json.get_error_line(), json.get_error_message()])
		return null
	return json.data


static func _text(v: Variant) -> bool:
	return typeof(v) == TYPE_STRING and (v as String).strip_edges() != ""


## The item's explanation, or "" when it has none (explanations are optional).
static func explain_of(item: Dictionary) -> String:
	var e: Variant = item.get("explain")
	return (e as String).strip_edges() if typeof(e) == TYPE_STRING else ""


## An item's `references` as display lines: "References:" then "  - Title (url)" per entry; [] when it has none.
## An entry is a text line or {title, url}; entries that are not valid are skipped (the validator reports them).
static func reference_lines(item: Dictionary) -> Array:
	var refs: Variant = item.get("references")
	var rows: Array = []
	if typeof(refs) != TYPE_ARRAY:
		return rows
	for r in refs:
		if typeof(r) == TYPE_STRING and _text(r):
			rows.append("  - %s" % (r as String).strip_edges())
		elif typeof(r) == TYPE_DICTIONARY and _text(r.get("title")):
			var row := "  - %s" % (r["title"] as String).strip_edges()
			if _text(r.get("url")):
				row += " (%s)" % (r["url"] as String).strip_edges()
			rows.append(row)
	if rows.is_empty():
		return rows
	rows.push_front("References:")
	return rows


## Appends to `problems` what is wrong with an item's optional `references`: a list of at most MAX_REFERENCES
## entries, each a non-empty text line or {title, url?} where title is text and url, if given, is http(s).
static func _validate_references(item: Dictionary, problems: Array) -> void:
	if not item.has("references"):
		return
	var refs: Variant = item["references"]
	if typeof(refs) != TYPE_ARRAY or (refs as Array).size() > MAX_REFERENCES:
		problems.append("'references' must be a list of at most %d entries" % MAX_REFERENCES)
		return
	for r in refs:
		if typeof(r) == TYPE_STRING:
			if not _text(r):
				problems.append("a reference must not be an empty line")
		elif typeof(r) == TYPE_DICTIONARY:
			if not _text(r.get("title")):
				problems.append("a reference given as an object needs a text 'title'")
			if r.has("url"):
				var url: Variant = r["url"]
				if typeof(url) != TYPE_STRING or not ((url as String).begins_with("http://") or (url as String).begins_with("https://")):
					problems.append("a reference 'url' must be text starting with http:// or https://")
		else:
			problems.append("each reference must be a text line or {title, url}")


## What is wrong with an `exam` block, or "". The pass mark is either a percentage
## (`pass_percent`) or a scaled score (`pass_score` inside `score_range`: Security+ is
## 750 on 100 to 900, which is not 75%). A pack may give at most one of the two.
static func exam_problem(exam: Dictionary) -> String:
	if exam.has("pbqs") and (not _whole(exam["pbqs"]) or int(exam["pbqs"]) < 0 or int(exam["pbqs"]) > MAX_EXAM_PBQS):
		return "'pbqs' must be a whole number from 0 to %d" % MAX_EXAM_PBQS
	if exam.has("pass_percent") and exam.has("pass_score"):
		return "give 'pass_percent' or 'pass_score', not both"
	if exam.has("pass_percent"):
		var pct: Variant = exam["pass_percent"]
		if not _whole(pct) or int(pct) < 1 or int(pct) > 100:
			return "'pass_percent' must be a whole number from 1 to 100"
	if exam.has("pass_score") or exam.has("score_range"):
		var range_v: Variant = exam.get("score_range")
		if typeof(range_v) != TYPE_ARRAY or (range_v as Array).size() != 2 \
				or not _whole(range_v[0]) or not _whole(range_v[1]) or int(range_v[0]) >= int(range_v[1]):
			return "'score_range' must be [low, high] whole numbers with low < high"
		var score: Variant = exam.get("pass_score")
		if not _whole(score) or int(score) < int(range_v[0]) or int(score) > int(range_v[1]):
			return "'pass_score' must be a whole number inside 'score_range'"
	return ""


## The pass mark as a learner reads it, or "" when the pack states none.
func pass_text() -> String:
	if exam.has("pass_score") and exam_problem(exam) == "":
		return "pass at %d on a %d to %d scale" % [int(exam["pass_score"]), int(exam["score_range"][0]), int(exam["score_range"][1])]
	if exam.has("pass_percent") and exam_problem(exam) == "":
		return "pass at %d%%" % int(exam["pass_percent"])
	return ""


static func _whole(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or (typeof(v) == TYPE_FLOAT and v == floorf(v))


func _load_meta(meta: Dictionary) -> void:
	for key in ["id", "title", "short"]:
		if not _text(meta.get(key)):
			errors.append("pack.json: '%s' must be a non-empty string" % key)
	id = str(meta.get("id", ""))
	title = str(meta.get("title", ""))
	short = str(meta.get("short", ""))
	if not _whole(meta.get("version")) or int(meta.get("version", 0)) < 1:
		errors.append("pack.json: 'version' must be a whole number >= 1")
	else:
		version = int(meta["version"])
	var exam_v: Variant = meta.get("exam", {})
	exam = exam_v if typeof(exam_v) == TYPE_DICTIONARY else {}
	var exam_problem := Pack.exam_problem(exam)
	if exam_problem != "":
		errors.append("pack.json: exam: %s" % exam_problem)
	if meta.has("rounds_include_labs"):
		if typeof(meta["rounds_include_labs"]) == TYPE_BOOL:
			rounds_include_labs = meta["rounds_include_labs"]
		else:
			errors.append("pack.json: 'rounds_include_labs' must be true or false")
	if meta.has("ranks"):
		var rank_problem := Rules.ranks_problem(meta["ranks"])
		if rank_problem != "":
			errors.append("pack.json: %s" % rank_problem)
		else:
			ranks = meta["ranks"]

	if meta.has("evidence_reasons"):
		_load_evidence_reasons(meta["evidence_reasons"])

	var weight_total := 0
	var domain_list: Variant = meta.get("domains")
	if typeof(domain_list) != TYPE_ARRAY or (domain_list as Array).is_empty():
		errors.append("pack.json: 'domains' must be a non-empty array")
		domain_list = []
	for d in domain_list:
		if typeof(d) != TYPE_DICTIONARY or not _text(d.get("id")) or not _text(d.get("title")) or not _whole(d.get("weight")):
			errors.append("pack.json: each domain needs a string id, a string title and a whole weight")
			continue
		if _domain_ids.has(d["id"]):
			errors.append("pack.json: duplicate domain id '%s'" % d["id"])
			continue
		_domain_ids[d["id"]] = true
		domains.append(d)
		weight_total += int(d["weight"])
	if not domains.is_empty() and weight_total != 100:
		warnings.append("domain weights add up to %d, not 100" % weight_total)

	var objective_list: Variant = meta.get("objectives")
	if typeof(objective_list) != TYPE_ARRAY or (objective_list as Array).is_empty():
		errors.append("pack.json: 'objectives' must be a non-empty array")
		objective_list = []
	for o in objective_list:
		_load_objective(o)


func _load_evidence_reasons(list: Variant) -> void:
	if typeof(list) != TYPE_ARRAY or (list as Array).is_empty() or (list as Array).size() > MAX_REASONS:
		errors.append("pack.json: 'evidence_reasons' must be an array of 1 to %d {key, label}" % MAX_REASONS)
		return
	var keys: Dictionary = {}
	var loaded: Array = []
	for r in list:
		if typeof(r) != TYPE_DICTIONARY or not _text(r.get("key")) or not _text(r.get("label")):
			errors.append("pack.json: each evidence reason needs a string key and label")
			return
		if keys.has(r["key"]):
			errors.append("pack.json: duplicate evidence reason key '%s'" % r["key"])
			return
		keys[r["key"]] = true
		loaded.append({"key": r["key"], "label": r["label"]})
	evidence_reasons = loaded


func _load_objective(o: Variant) -> void:
	if typeof(o) != TYPE_DICTIONARY or not _text(o.get("id")) or not _text(o.get("title")):
		errors.append("pack.json: each objective needs a string id and a string title")
		return
	var oid: String = o["id"]
	if _objective_by_id.has(oid):
		errors.append("pack.json: duplicate objective id '%s'" % oid)
		return
	if not _domain_ids.has(o.get("domain")):
		errors.append("pack.json: objective %s names unknown domain '%s'" % [oid, o.get("domain")])
		return
	_objective_by_id[oid] = o
	objectives.append(o)
	var concept_list: Variant = o.get("concepts", [])
	if typeof(concept_list) != TYPE_ARRAY:
		errors.append("pack.json: objective %s: 'concepts' must be an array" % oid)
		return
	for c in concept_list:
		if typeof(c) != TYPE_DICTIONARY or not _text(c.get("id")) or not _text(c.get("title")):
			errors.append("pack.json: objective %s has a concept without a string id and title" % oid)
			continue
		var cid: String = c["id"]
		if not cid.begins_with(oid + "."):
			errors.append("pack.json: concept '%s' must start with its objective id '%s.'" % [cid, oid])
			continue
		if concepts.has(cid):
			errors.append("pack.json: duplicate concept id '%s'" % cid)
			continue
		concepts[cid] = {"id": cid, "title": c["title"], "objective": oid}


func _load_items() -> void:
	var items_dir := dir.path_join("items")
	if DirAccess.open(items_dir) == null:
		warnings.append("no items/ directory")
		return
	var names: Array = Array(DirAccess.get_files_at(items_dir))
	names.sort()
	for file_name in names:
		if not (file_name as String).ends_with(".json"):
			continue
		var label := "items/%s" % file_name
		var data: Variant = _read_json(items_dir.path_join(file_name), label)
		if data == null:
			continue
		if typeof(data) != TYPE_ARRAY:
			errors.append("%s: expected an array of items" % label)
			continue
		for item in data:
			if _validate_item(item, label):
				items[item["id"]] = item
				if explain_of(item) == "":
					items_without_explain += 1
				for cid in item["concept_ids"]:
					if not _by_concept.has(cid):
						_by_concept[cid] = []
					_by_concept[cid].append(item["id"])


## labs/*.json, one lab per file. A lab with problems is reported and not used.
func _load_labs() -> void:
	var labs_dir := dir.path_join("labs")
	if DirAccess.open(labs_dir) == null:
		return
	var names: Array = Array(DirAccess.get_files_at(labs_dir))
	names.sort()
	for file_name in names:
		if not (file_name as String).ends_with(".json"):
			continue
		var label := "labs/%s" % file_name
		var data: Variant = _read_json(labs_dir.path_join(file_name), label)
		if data == null:
			continue
		var lab := SimLab.from_data(data, label)
		errors.append_array(lab.errors)
		if not lab.ok():
			continue
		if labs.has(lab.id):
			errors.append("%s: duplicate lab id '%s'" % [label, lab.id])
			continue
		labs[lab.id] = lab


## tools.json: the manual pages `tool <name>` shows, with their Security+ links.
func _load_tools() -> void:
	var path := dir.path_join("tools.json")
	if not FileAccess.file_exists(path):
		return
	var data: Variant = _read_json(path, "tools.json")
	if data == null:
		return
	if typeof(data) != TYPE_DICTIONARY:
		errors.append("tools.json: expected an object keyed by tool name")
		return
	for tool_name in data:
		var d: Variant = data[tool_name]
		if typeof(d) != TYPE_DICTIONARY or not _text(d.get("summary")):
			errors.append("tools.json: '%s' needs a non-empty 'summary'" % tool_name)
			continue
		var bad := false
		for f in d.get("flags", []):
			if typeof(f) != TYPE_ARRAY or (f as Array).size() != 2 or not _text(f[0]) or not _text(f[1]):
				errors.append("tools.json: '%s' flags must be [flag, meaning] pairs" % tool_name)
				bad = true
				break
		for cid in d.get("concepts", []):
			if not concepts.has(cid):
				errors.append("tools.json: '%s' names unknown concept '%s'" % [tool_name, cid])
				bad = true
		if d.has("windows"):  # the page as a Windows workstation shows it
			var w: Variant = d["windows"]
			if typeof(w) != TYPE_DICTIONARY:
				errors.append("tools.json: '%s' windows must be an object of replacement fields" % tool_name)
				bad = true
			else:
				for f in w.get("flags", []):
					if typeof(f) != TYPE_ARRAY or (f as Array).size() != 2 or not _text(f[0]) or not _text(f[1]):
						errors.append("tools.json: '%s' windows flags must be [flag, meaning] pairs" % tool_name)
						bad = true
						break
		if not bad:
			tool_docs[tool_name] = d


func _load_codex() -> void:
	var path := dir.path_join("codex.json")
	if not FileAccess.file_exists(path):
		return
	var data: Variant = _read_json(path, "codex.json")
	if data == null:
		return
	if typeof(data) != TYPE_DICTIONARY:
		errors.append("codex.json: expected an object keyed by concept id")
		return
	for cid in data:
		var entry: Variant = data[cid]
		if not concepts.has(cid):
			errors.append("codex.json: unknown concept id '%s'" % cid)
		elif typeof(entry) != TYPE_DICTIONARY or not _text(entry.get("definition")):
			errors.append("codex.json: '%s' needs a non-empty 'definition'" % cid)
		else:
			codex[cid] = entry


## Appends to `errors` and returns false when the item is not usable.
func _validate_item(item: Variant, label: String) -> bool:
	if typeof(item) != TYPE_DICTIONARY:
		errors.append("%s: every entry must be an object" % label)
		return false
	var item_id: String = str(item.get("id", "")) if _text(item.get("id")) else ""
	var where := "%s %s" % [label, item_id if item_id != "" else "(no id)"]
	var problems: Array = []
	if item_id == "":
		problems.append("'id' must be a non-empty string")
	elif items.has(item_id):
		problems.append("duplicate item id")
	var item_type: String = str(item.get("type", ""))
	if not ITEM_TYPES.has(item_type):
		problems.append("unsupported type '%s' (known: %s)" % [item_type, ", ".join(ITEM_TYPES)])
	var cids: Variant = item.get("concept_ids")
	if typeof(cids) != TYPE_ARRAY or (cids as Array).is_empty():
		problems.append("'concept_ids' must be a non-empty array")
	else:
		for cid in cids:
			if not concepts.has(cid):
				problems.append("unknown concept id '%s'" % cid)
	if not _whole(item.get("difficulty")) or int(item.get("difficulty", 0)) < 1 or int(item.get("difficulty", 0)) > 3:
		problems.append("'difficulty' must be 1, 2 or 3")
	if not SOURCES.has(item.get("source")):
		problems.append("'source' must be one of %s" % ", ".join(SOURCES))
	if typeof(item.get("reviewed")) != TYPE_BOOL:
		problems.append("'reviewed' must be true or false")
	if not _text(item.get("stem")):
		problems.append("'stem' must be a non-empty string")
	if item.has("explain") and typeof(item["explain"]) != TYPE_STRING:
		problems.append("'explain' must be text")
	_validate_references(item, problems)
	if item_type == "mcq" or item_type == "multi":
		_validate_choices(item, item_type, problems)
		_validate_show(item, problems)
	elif item_type == "evidence":
		_validate_evidence(item, item_id, problems)
	elif item_type == "terminal":
		_validate_terminal(item, problems)
	elif item_type == "match":
		_validate_match(item, problems)
	elif item_type == "order":
		_validate_order(item, problems)
	for p in problems:
		errors.append("%s: %s" % [where, p])
	return problems.is_empty()


## An optional `show: {lab, command}` prints a lab command's output under the
## stem, so a question can ask about output the emulators really produce.
func _validate_show(item: Dictionary, problems: Array) -> void:
	if not item.has("show"):
		return
	var show: Variant = item["show"]
	if typeof(show) != TYPE_DICTIONARY or not _text(show.get("command")):
		problems.append("'show' must be an object with a 'lab' and a 'command'")
	elif not labs.has(show.get("lab")):
		problems.append("'show' names unknown lab '%s'" % show.get("lab", ""))


## A terminal item names a lab and the answers that count; the learner finds
## the answer by using the lab's tools.
func _validate_terminal(item: Dictionary, problems: Array) -> void:
	if not labs.has(item.get("lab")):
		problems.append("unknown lab '%s'" % item.get("lab", ""))
	var answer: Variant = item.get("answer")
	var accept: Variant = answer.get("accept") if typeof(answer) == TYPE_DICTIONARY else null
	if typeof(accept) != TYPE_ARRAY or (accept as Array).is_empty():
		problems.append("'answer' needs a non-empty 'accept' array")
		return
	for a in accept:
		if not _text(a):
			problems.append("every accepted answer must be a non-empty string")
			return


## A match item files `pairs` (text, category, explain) under `categories` (id, text).
func _validate_match(item: Dictionary, problems: Array) -> void:
	var cats: Variant = item.get("categories")
	var ids: Dictionary = {}
	if typeof(cats) != TYPE_ARRAY or (cats as Array).size() < 2 or (cats as Array).size() > MAX_CATEGORIES:
		problems.append("'categories' must be an array of 2 to %d {id, text}" % MAX_CATEGORIES)
	else:
		for c in cats:
			if typeof(c) != TYPE_DICTIONARY or not _text(c.get("id")) or not _text(c.get("text")):
				problems.append("every category needs a string id and text")
			elif ids.has(c["id"]):
				problems.append("duplicate category id '%s'" % c["id"])
			else:
				ids[c["id"]] = true
				if (c["text"] as String).length() > MAX_ROW_TEXT:
					problems.append("category '%s' text is longer than %d characters" % [c["id"], MAX_ROW_TEXT])
	var pairs: Variant = item.get("pairs")
	if typeof(pairs) != TYPE_ARRAY or (pairs as Array).size() < 3 or (pairs as Array).size() > MAX_PAIRS:
		problems.append("'pairs' must be an array of 3 to %d {text, category, explain}" % MAX_PAIRS)
		return
	var texts: Dictionary = {}
	for pr in pairs:
		if typeof(pr) != TYPE_DICTIONARY or not _text(pr.get("text")) or not _text(pr.get("category")) or not _text(pr.get("explain")):
			problems.append("every pair needs a string text, a category id and an explain")
			continue
		if not ids.is_empty() and not ids.has(pr["category"]):
			problems.append("pair '%s' names unknown category '%s'" % [pr["text"], pr["category"]])
		if (pr["text"] as String).length() > MAX_ROW_TEXT:
			problems.append("pair '%s...' is longer than %d characters" % [(pr["text"] as String).substr(0, 20), MAX_ROW_TEXT])
		if texts.has(pr["text"]):
			problems.append("duplicate pair text '%s'" % pr["text"])
		texts[pr["text"]] = true


## An order item lists `steps` (text, explain) already in the correct order.
func _validate_order(item: Dictionary, problems: Array) -> void:
	var steps: Variant = item.get("steps")
	if typeof(steps) != TYPE_ARRAY or (steps as Array).size() < MIN_STEPS or (steps as Array).size() > MAX_STEPS:
		problems.append("'steps' must be an array of %d to %d {text, explain}, in the correct order" % [MIN_STEPS, MAX_STEPS])
		return
	var texts: Dictionary = {}
	for st in steps:
		if typeof(st) != TYPE_DICTIONARY or not _text(st.get("text")) or not _text(st.get("explain")):
			problems.append("every step needs a string text and an explain")
			continue
		if (st["text"] as String).length() > MAX_ROW_TEXT:
			problems.append("step '%s...' is longer than %d characters" % [(st["text"] as String).substr(0, 20), MAX_ROW_TEXT])
		if texts.has(st["text"]):
			problems.append("duplicate step text '%s'" % st["text"])
		texts[st["text"]] = true


func _reason_keys() -> Array:
	var keys: Array = []
	for r in evidence_reasons:
		keys.append(r["key"])
	return keys


## An evidence item points at a text artifact and lists the flawed lines
## (`flaws`) and the lines that only look wrong (`decoys`). `match` text must
## sit on the named line so editing the artifact cannot silently shift answers.
func _validate_evidence(item: Dictionary, item_id: String, problems: Array) -> void:
	if evidence_reasons.is_empty():
		problems.append("evidence items need 'evidence_reasons' in pack.json")
	var art: Variant = item.get("artifact")
	var lines: Array = []
	if typeof(art) != TYPE_DICTIONARY or not _text(art.get("file")) or not _text(art.get("title")):
		problems.append("'artifact' needs a string file and title")
	elif not ARTIFACT_KINDS.has(art.get("kind")):
		problems.append("artifact 'kind' must be one of %s" % ", ".join(ARTIFACT_KINDS))
	else:
		var file: String = art["file"]
		var path := dir.path_join(file)
		if file.begins_with("/") or file.contains(".."):
			problems.append("artifact file must be a relative path inside the pack")
		elif not FileAccess.file_exists(path):
			problems.append("artifact file '%s' not found" % file)
		else:
			lines = Array(FileAccess.get_file_as_string(path).replace("\r", "").split("\n"))
			if not lines.is_empty() and lines[-1] == "":
				lines.pop_back()
			if lines.size() > MAX_ARTIFACT_LINES:
				problems.append("artifact '%s' has %d lines (limit %d)" % [file, lines.size(), MAX_ARTIFACT_LINES])
				lines = []
	var flaws: Variant = item.get("flaws")
	if typeof(flaws) != TYPE_ARRAY or (flaws as Array).is_empty():
		problems.append("'flaws' must be a non-empty array")
		flaws = []
	var seen: Dictionary = {}
	for f in flaws:
		_validate_marked_line(f, "flaw", lines, seen, problems)
		if typeof(f) != TYPE_DICTIONARY:
			continue
		var accepted: Variant = f.get("reasons", null)
		if f.has("reasons") == f.has("reason"):
			problems.append("flaw on line %s needs exactly one of 'reason' or 'reasons'" % f.get("line"))
		elif f.has("reason"):
			accepted = [f["reason"]]
		if typeof(accepted) != TYPE_ARRAY or (accepted as Array).is_empty():
			if f.has("reasons"):
				problems.append("flaw on line %s: 'reasons' must be a non-empty array" % f.get("line"))
			continue
		for key in accepted:
			if not _reason_keys().has(key):
				problems.append("flaw on line %s: unknown reason '%s'" % [f.get("line"), key])
	var decoys: Variant = item.get("decoys", [])
	if typeof(decoys) != TYPE_ARRAY:
		problems.append("'decoys' must be an array")
		decoys = []
	for d in decoys:
		_validate_marked_line(d, "decoy", lines, seen, problems)
	if not lines.is_empty() and typeof(art) == TYPE_DICTIONARY:
		artifacts[item_id] = lines


## Shared checks for a flaw or decoy entry; `seen` catches a line named twice
## (also a flaw and a decoy on the same line).
func _validate_marked_line(e: Variant, what: String, lines: Array, seen: Dictionary, problems: Array) -> void:
	if typeof(e) != TYPE_DICTIONARY or not _whole(e.get("line")) or not _text(e.get("match")) or not _text(e.get("explain")):
		problems.append("every %s needs a whole 'line', a string 'match' and an 'explain'" % what)
		return
	var n := int(e["line"])
	if seen.has(n):
		problems.append("line %d is named by more than one flaw or decoy" % n)
	seen[n] = true
	if lines.is_empty():
		return
	if n < 1 or n > lines.size():
		problems.append("%s line %d is outside the artifact (1-%d)" % [what, n, lines.size()])
	elif not (lines[n - 1] as String).contains(e["match"]):
		problems.append("%s line %d does not contain '%s'" % [what, n, e["match"]])


func _validate_choices(item: Dictionary, item_type: String, problems: Array) -> void:
	var options: Variant = item.get("options")
	var option_ids: Dictionary = {}
	if typeof(options) != TYPE_ARRAY or (options as Array).size() < 3:
		problems.append("'options' must be an array of at least 3")
	else:
		for o in options:
			if typeof(o) != TYPE_DICTIONARY or not _text(o.get("id")) or not _text(o.get("text")):
				problems.append("every option needs a string id and text")
			elif option_ids.has(o["id"]):
				problems.append("duplicate option id '%s'" % o["id"])
			else:
				option_ids[o["id"]] = true
				if o.has("why") and not _text(o["why"]):
					problems.append("option '%s': 'why' must be a non-empty string when present" % o["id"])
	var answer: Variant = item.get("answer")
	if typeof(answer) != TYPE_ARRAY:
		problems.append("'answer' must be an array of option ids")
		return
	var seen: Dictionary = {}
	for a in answer:
		if not option_ids.has(a):
			problems.append("answer '%s' is not an option id" % a)
		elif seen.has(a):
			problems.append("answer '%s' listed twice" % a)
		seen[a] = true
	if item_type == "mcq" and answer.size() != 1:
		problems.append("an mcq needs exactly one answer")
	if item_type == "multi" and (answer.size() < 2 or answer.size() >= option_ids.size()):
		problems.append("a multi needs at least two answers and at least one wrong option")
