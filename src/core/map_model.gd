class_name MapModel
extends RefCounted
## The node map (README "The map"): which objectives can be breached, how far
## through each the learner is, and the screen lines. No tier names appear.

const BAR_CELLS := 8
const TITLE_MAX := 52

var pack: Pack
var profile: Profile
var rules: Rules
var _nodes: Array = []
var _by_id: Dictionary = {}


func _init(content_pack: Pack, p: Profile, rules_in: Rules) -> void:
	pack = content_pack
	profile = p
	rules = rules_in
	_build()


## Every objective in pack order:
## {id, title, domain, concepts (servable), total, known, started, state, gate}
## state is "empty" (nothing to serve), "open" or "locked"; gate is the
## objective that must be cleared first when locked.
func nodes() -> Array:
	return _nodes


func node(id: String) -> Dictionary:
	return _by_id.get(id, {})


## Content-bearing nodes in map order (the cursor moves over these).
func selectable() -> Array:
	var out: Array = []
	for n in _nodes:
		if n["state"] != "empty":
			out.append(n["id"])
	return out


func open_ids() -> Array:
	var out: Array = []
	for n in _nodes:
		if n["state"] == "open":
			out.append(n["id"])
	return out


## The earliest open node that still has unmet or unfinished concepts, or "".
func first_unfinished() -> String:
	for n in _nodes:
		if n["state"] == "open" and (n["known"] < n["total"]):
			return n["id"]
	return ""


func screen(cursor_id: String) -> Array:
	var out: Array = []
	out.append(_line("MAP  //  up/down to move, Enter to breach, Esc to leave", Lines.S_ACCENT))
	out.append(_line("NEW not started   [#####...] n/m concepts solid   LOCKED needs the node before it", Lines.S_DIM))
	for d in pack.domains:
		out.append(_line(""))
		out.append(_line("SECTOR %s  %s  (%d%% of the exam)" % [d["id"], d["title"], int(d["weight"])]))
		var hidden := 0
		var run: Array = []  # locked nodes not under the cursor, waiting to be shown as one line
		for n in _nodes:
			if n["domain"] != d["id"]:
				continue
			if n["state"] == "empty":
				hidden += 1
				continue
			if n["state"] == "locked" and n["id"] != cursor_id:
				run.append(n)
				continue
			_flush_locked(out, run)
			out.append(_node_line(n, n["id"] == cursor_id))
		_flush_locked(out, run)
		if hidden > 0:
			out.append(_line("      %d objectives with no content yet" % hidden, Lines.S_DIM))
	var sel: Dictionary = _by_id.get(cursor_id, {})
	if not sel.is_empty():
		out.append(_line(""))
		out.append(_line("%s  %s" % [sel["id"], sel["title"]], Lines.S_ACCENT))
	return out


## One dim line for a run of locked nodes: their ids, and what unlocks the first.
func _flush_locked(out: Array, run: Array) -> void:
	if run.is_empty():
		return
	var first: Dictionary = run[0]
	var last: Dictionary = run[run.size() - 1]
	var ids: String = first["id"] if run.size() == 1 else "%s - %s" % [first["id"], last["id"]]
	var gate: Dictionary = _by_id.get(first["gate"], {})
	while not gate.is_empty() and gate["state"] == "locked":  # point at the node the learner can work on
		gate = _by_id.get(gate["gate"], {})
	var text := "      %s  locked" % (ids as String).rpad(9)
	if not gate.is_empty():
		text += " until %s is %s solid (%d of %d concepts solid)" % [
				gate["id"], _fraction_word(), gate["known"], gate["total"]]
	out.append(_line(text, Lines.S_DIM))
	run.clear()


func _fraction_word() -> String:
	if is_equal_approx(rules.unlock_fraction, 0.5):
		return "half"
	return "%d%%" % roundi(rules.unlock_fraction * 100.0)


func _node_line(n: Dictionary, selected: bool) -> Dictionary:
	var title: String = n["title"]
	if title.length() > TITLE_MAX:
		title = title.substr(0, TITLE_MAX - 1) + "…"
	var status: String
	if n["state"] == "locked":
		status = "LOCKED"
	elif not n["started"]:
		status = "NEW"
	else:
		var filled := roundi(float(BAR_CELLS) * float(n["known"]) / float(n["total"]))
		status = "[%s%s] %d/%d" % ["█".repeat(filled), "░".repeat(BAR_CELLS - filled), n["known"], n["total"]]
	var text := "%s %s %s  %s" % [">" if selected else " ", (n["id"] as String).rpad(4), title.rpad(TITLE_MAX), status]
	var style := Lines.S_DIM if n["state"] == "locked" else Lines.S_NORMAL
	return _line(text, Lines.S_ACCENT if selected else style)


func _build() -> void:
	var unlock_all: bool = bool(profile.peek().get("unlock_all", false))
	var prev_by_domain: Dictionary = {}  # domain id -> previous content node
	for o in pack.objectives:
		var cids: Array = []
		for cid in pack.concepts:
			if pack.concepts[cid]["objective"] == o["id"] and Scheduler.servable(pack, cid):
				cids.append(cid)
		var known := 0
		var started := false
		for cid in cids:
			if Mastery.box(profile, cid) >= 2:
				known += 1
			if Mastery.seen(profile, cid) > 0:
				started = true
		var n := {"id": o["id"], "title": o["title"], "domain": o["domain"], "concepts": cids,
				"total": cids.size(), "known": known, "started": started, "state": "empty", "gate": ""}
		if not cids.is_empty():
			var prev: Dictionary = prev_by_domain.get(o["domain"], {})
			if unlock_all or prev.is_empty() or float(prev["known"]) / float(prev["total"]) >= rules.unlock_fraction:
				n["state"] = "open"
			else:
				n["state"] = "locked"
				n["gate"] = prev["id"]
			prev_by_domain[o["domain"]] = n
		_nodes.append(n)
		_by_id[o["id"]] = n


static func _line(text: String, style: String = Lines.S_NORMAL) -> Dictionary:
	return Lines.make(text, style)
