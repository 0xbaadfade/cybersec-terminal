class_name Rules
extends RefCounted
## Engine tunables, loaded from data/rules.json (README "Phase 2 plan").
## These are engine defaults, not pack content; a pack may replace `ranks`.
## Problems are collected in `errors` and the field keeps a usable default.

const DEFAULT_PATH := "res://data/rules.json"
const MAX_BOX := 5
## What a perk can do (README "Skill tree Phase T3 plan").
const PERK_KINDS: Array = ["max_questions", "exam_minutes", "yield", "node_output", "stale_floor", "repeat_payout"]

var round_size := 9
var max_new := 5
var xp_per_difficulty: Array = [10, 15, 20]
var streak_step := 0.10
var streak_cap := 0.50
var trace_miss := 20
var trace_relief := 5
var trace_limit := 100
var box_days: Array = [0, 1, 2, 4, 8, 16]
var requeue_min := 3
var requeue_max := 6
var unlock_fraction := 0.5
var auto_advance_correct := true
var evidence_line_percent := 70
var evidence_reason_percent := 30
var evidence_false_flag_percent := 15
var evidence_xp_multiplier := 2
var terminal_second_try_percent := 50
var terminal_xp_multiplier := 2
## The incremental layer (README "Incremental layer plan").
var eco_active_multiplier := 1.0
var eco_repeat_percent := 25
var eco_rate_by_box: Array = [0.0, 1.0, 2.0, 4.0, 8.0, 15.0]  # Cycles per minute per node
var eco_stale_percent := 25
var eco_idle_cap := 300
var eco_save_every := 30
var eco_exam_pass_cycles := 250  # paid once per track, on its first passed exam
## The shop: normalised perks {id, title, kind, max_level, base_cost, growth, per_level, base, levels}.
var perks: Array = []
var ranks: Array = [["Operator", 0]]
var errors: Array = []


static func load_default() -> Rules:
	return load_file(DEFAULT_PATH)


static func load_file(path: String) -> Rules:
	var r := Rules.new()
	if not FileAccess.file_exists(path):
		r.errors.append("%s: file not found" % path)
		return r
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		r.errors.append("%s line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return r
	if typeof(json.data) != TYPE_DICTIONARY:
		r.errors.append("%s: expected a JSON object" % path)
		return r
	r._apply(json.data)
	return r


func interval(box: int) -> int:
	return int(box_days[clampi(box, 0, box_days.size() - 1)])


func rank_index(xp: int) -> int:
	return ladder_index(ranks, xp)


func rank_name(idx: int) -> String:
	return ladder_name(ranks, idx)


## The same lookups over any ladder, for reading another track's rank.
static func ladder_index(ladder: Array, xp: int) -> int:
	var idx := 0
	for i in ladder.size():
		if xp >= int(ladder[i][1]):
			idx = i
	return idx


static func ladder_name(ladder: Array, idx: int) -> String:
	return str(ladder[clampi(idx, 0, ladder.size() - 1)][0])


## XP still needed for the next rank, or -1 at the top rank.
func xp_to_next(xp: int) -> int:
	var idx := rank_index(xp)
	return -1 if idx >= ranks.size() - 1 else int(ranks[idx + 1][1]) - xp


## "" when `list` is a usable rank ladder, otherwise why not.
static func ranks_problem(list: Variant) -> String:
	if typeof(list) != TYPE_ARRAY or (list as Array).is_empty():
		return "'ranks' must be a non-empty array of [name, xp]"
	var last := -1
	for r in list:
		if typeof(r) != TYPE_ARRAY or (r as Array).size() != 2 or typeof(r[0]) != TYPE_STRING \
				or (r[0] as String).strip_edges() == "" or not _whole(r[1]):
			return "each rank must be [name, xp] with a whole xp"
		if int(r[1]) <= last:
			return "rank xp must be strictly increasing"
		last = int(r[1])
	if int((list as Array)[0][1]) != 0:
		return "the first rank must start at 0 xp"
	return ""


static func _whole(v: Variant) -> bool:
	return (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) and v == floorf(v) and v >= 0


func _apply(d: Dictionary) -> void:
	round_size = _int(d, "round_size", 1, round_size)
	max_new = _int(d, "max_new_concepts_per_round", 0, max_new)
	streak_step = _num(d, "streak_bonus_per_step", streak_step)
	streak_cap = _num(d, "streak_bonus_cap", streak_cap)
	unlock_fraction = _num(d, "unlock_known_fraction", unlock_fraction)
	if d.has("auto_advance_correct"):
		if typeof(d["auto_advance_correct"]) == TYPE_BOOL:
			auto_advance_correct = d["auto_advance_correct"]
		else:
			errors.append("'auto_advance_correct' must be true or false")
	var t: Variant = d.get("trace")
	if typeof(t) != TYPE_DICTIONARY:
		errors.append("'trace' must be an object")
	else:
		trace_miss = _int(t, "miss_full", 0, trace_miss)
		trace_relief = _int(t, "relief_on_correct", 0, trace_relief)
		trace_limit = _int(t, "limit", 1, trace_limit)
	_apply_evidence(d.get("evidence"))
	_apply_terminal(d.get("terminal"))
	_apply_economy(d.get("economy"))
	_apply_perks(d.get("perks"))
	xp_per_difficulty = _int_list(d, "xp_per_difficulty", 3, xp_per_difficulty)
	box_days = _int_list(d, "box_interval_days", MAX_BOX + 1, box_days)
	var gap := _int_list(d, "requeue_gap", 2, [requeue_min, requeue_max])
	requeue_min = int(gap[0])
	requeue_max = int(gap[1])
	if requeue_min < 1 or requeue_min > requeue_max:
		errors.append("'requeue_gap' must be [min, max] with 1 <= min <= max")
		requeue_min = 3
		requeue_max = 6
	var problem := ranks_problem(d.get("ranks"))
	if problem != "":
		errors.append(problem)
	else:
		ranks = d["ranks"]


## The block is optional (older rules files lack it); when present it must be
## whole and the line and reason shares must make one flaw worth 100.
func _apply_evidence(e: Variant) -> void:
	if e == null:
		return
	if typeof(e) != TYPE_DICTIONARY:
		errors.append("'evidence' must be an object")
		return
	var line := _int(e, "line_percent", 0, evidence_line_percent)
	var reason := _int(e, "reason_percent", 0, evidence_reason_percent)
	if line + reason != 100:
		errors.append("evidence: line_percent + reason_percent must be 100")
	else:
		evidence_line_percent = line
		evidence_reason_percent = reason
	evidence_false_flag_percent = _int(e, "false_flag_percent", 0, evidence_false_flag_percent)
	evidence_xp_multiplier = _int(e, "xp_multiplier", 1, evidence_xp_multiplier)


## Optional like `evidence`: the share of credit for a right answer on the
## second try (0 to 100) and the XP multiplier for a lab mission.
func _apply_terminal(t: Variant) -> void:
	if t == null:
		return
	if typeof(t) != TYPE_DICTIONARY:
		errors.append("'terminal' must be an object")
		return
	var share := _int(t, "second_try_percent", 0, terminal_second_try_percent)
	if share > 100:
		errors.append("terminal: second_try_percent must be 0 to 100")
	else:
		terminal_second_try_percent = share
	terminal_xp_multiplier = _int(t, "xp_multiplier", 1, terminal_xp_multiplier)


## Optional like `evidence`: a list of perks. A bad perk is reported and left out.
func _apply_perks(list: Variant) -> void:
	if list == null:
		return
	if typeof(list) != TYPE_ARRAY:
		errors.append("'perks' must be a list")
		return
	var seen: Dictionary = {}
	for raw in list:
		var problem := _perk_problem(raw, seen)
		if problem != "":
			errors.append("perks: %s" % problem)
			continue
		var perk: Dictionary = {"id": raw["id"], "title": raw["title"], "kind": raw["kind"],
				"base_cost": int(raw["base_cost"]), "growth": float(raw["growth"]), "per_level": 0, "base": 0, "levels": []}
		if raw["kind"] == "max_questions":
			perk["base"] = int(raw["base"])
			perk["levels"] = (raw["levels"] as Array).map(func(x: Variant) -> int: return int(x))
			perk["max_level"] = (perk["levels"] as Array).size()
		else:
			perk["per_level"] = int(raw["per_level"])
			perk["max_level"] = int(raw["max_level"])
		seen[raw["id"]] = true
		perks.append(perk)


## "" when `raw` is a usable perk, otherwise why not. `seen` holds the ids already taken.
func _perk_problem(raw: Variant, seen: Dictionary) -> String:
	if typeof(raw) != TYPE_DICTIONARY:
		return "each perk must be an object"
	var id: Variant = raw.get("id")
	if typeof(id) != TYPE_STRING or (id as String).strip_edges() == "":
		return "each perk needs an 'id'"
	if seen.has(id):
		return "'%s' is listed twice" % id
	if typeof(raw.get("title")) != TYPE_STRING or (raw["title"] as String).strip_edges() == "":
		return "'%s' needs a 'title'" % id
	if not PERK_KINDS.has(raw.get("kind")):
		return "'%s': 'kind' must be one of %s" % [id, ", ".join(PERK_KINDS)]
	if not _whole(raw.get("base_cost")) or raw["base_cost"] < 1:
		return "'%s': 'base_cost' must be a whole number >= 1" % id
	var growth: Variant = raw.get("growth")
	if not (typeof(growth) == TYPE_INT or typeof(growth) == TYPE_FLOAT) or growth < 1.0:
		return "'%s': 'growth' must be a number >= 1" % id
	if raw["kind"] == "max_questions":
		var levels: Variant = raw.get("levels")
		if not _whole(raw.get("base")) or raw["base"] < 1:
			return "'%s': 'base' must be a whole number >= 1" % id
		if typeof(levels) != TYPE_ARRAY or (levels as Array).is_empty():
			return "'%s': 'levels' must be a non-empty list" % id
		var last: int = int(raw["base"])
		for x in levels:
			if not _whole(x) or int(x) <= last or int(x) > 200:
				return "'%s': 'levels' must be whole numbers increasing from 'base' and at most 200" % id
			last = int(x)
		return ""
	if not _whole(raw.get("per_level")) or raw["per_level"] < 1:
		return "'%s': 'per_level' must be a whole number >= 1" % id
	if not _whole(raw.get("max_level")) or raw["max_level"] < 1:
		return "'%s': 'max_level' must be a whole number >= 1" % id
	return ""


## Optional like `evidence`. Percentages are 0 to 100; the rate list has one entry per box.
func _apply_economy(e: Variant) -> void:
	if e == null:
		return
	if typeof(e) != TYPE_DICTIONARY:
		errors.append("'economy' must be an object")
		return
	eco_active_multiplier = _num(e, "active_multiplier", eco_active_multiplier)
	eco_repeat_percent = _int(e, "repeat_percent", 0, eco_repeat_percent)
	eco_stale_percent = _int(e, "stale_percent", 0, eco_stale_percent)
	if eco_repeat_percent > 100 or eco_stale_percent > 100:
		errors.append("economy: repeat_percent and stale_percent must be 0 to 100")
		eco_repeat_percent = mini(eco_repeat_percent, 100)
		eco_stale_percent = mini(eco_stale_percent, 100)
	eco_idle_cap = _int(e, "idle_cap_seconds", 1, eco_idle_cap)
	eco_save_every = _int(e, "save_every_seconds", 1, eco_save_every)
	eco_exam_pass_cycles = _int(e, "exam_pass_cycles", 0, eco_exam_pass_cycles)
	var rates: Variant = e.get("rate_per_min_by_box")
	var ok: bool = typeof(rates) == TYPE_ARRAY and (rates as Array).size() == MAX_BOX + 1
	if ok:
		for x in rates:
			if not ((typeof(x) == TYPE_INT or typeof(x) == TYPE_FLOAT) and x >= 0):
				ok = false
	if ok:
		eco_rate_by_box = (rates as Array).map(func(x: Variant) -> float: return float(x))
	else:
		errors.append("economy: 'rate_per_min_by_box' must be %d numbers >= 0" % (MAX_BOX + 1))


func _int(d: Dictionary, key: String, minimum: int, fallback: int) -> int:
	var v: Variant = d.get(key)
	if not (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) or v != floorf(v) or v < minimum:
		errors.append("'%s' must be a whole number >= %d" % [key, minimum])
		return fallback
	return int(v)


func _num(d: Dictionary, key: String, fallback: float) -> float:
	var v: Variant = d.get(key)
	if not (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) or v < 0:
		errors.append("'%s' must be a number >= 0" % key)
		return fallback
	return float(v)


func _int_list(d: Dictionary, key: String, length: int, fallback: Array) -> Array:
	var v: Variant = d.get(key)
	if typeof(v) != TYPE_ARRAY or (v as Array).size() != length:
		errors.append("'%s' must be an array of %d whole numbers" % [key, length])
		return fallback
	var out: Array = []
	for x in v:
		if not _whole(x):
			errors.append("'%s' must contain only whole numbers >= 0" % key)
			return fallback
		out.append(int(x))
	return out
