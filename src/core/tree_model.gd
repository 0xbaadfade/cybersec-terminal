class_name TreeModel
extends RefCounted
## The skill tree (README "Skill tree plan"): tracks as nodes, `requires` as
## edges. Works out each node's state, draws the tree, and opens (buys) nodes
## with Cycles. Reads the profile; the only thing it writes is the opened set at
## `profile.data["tree"]["opened"]` and the wallet, in `open()`.
##
## A track is played only when its state is OPEN. Tracks the learner already has
## progress in are OPEN without paying (nothing already played can lock), and
## `profile.data["unlock_all"] = true` opens every playable track (the
## instructor override).

const OPEN := "open"
const AVAILABLE := "available"  # requirements met, price not yet paid
const LOCKED := "locked"
const SOON := "soon"
const COMPLETE := "complete"  # a stub node: counts as 100% for everyone
const UNAVAILABLE := "unavailable"

const TITLE_WIDTH := 30

var catalog: TrackCatalog
var profile: Profile
var rules: Rules
var today := 0

var _order: Array = []


func _init(cat: TrackCatalog, p: Profile, rules_in: Rules, today_in: int) -> void:
	catalog = cat
	profile = p
	rules = rules_in
	today = today_in
	_build_order()


# --- the graph -------------------------------------------------------------

## Track ids in the order the tree is drawn (and numbered): a node, then its
## children, in catalog order. A node hangs under its first requirement.
func order() -> Array:
	return _order


func parent_of(id: String) -> String:
	var reqs: Array = catalog.track(id).get("requires", [])
	return reqs[0]["track"] if not reqs.is_empty() else ""


func children_of(id: String) -> Array:
	var out: Array = []
	for t in catalog.all_tracks():
		if parent_of(t["id"]) == id:
			out.append(t["id"])
	return out


func _build_order() -> void:
	_order = []
	for t in catalog.all_tracks():
		if parent_of(t["id"]) == "":
			_visit(t["id"])
	for t in catalog.all_tracks():  # anything unreachable (a bad catalog) still shows
		if not _order.has(t["id"]):
			_order.append(t["id"])


func _visit(id: String) -> void:
	_order.append(id)
	for child in children_of(id):
		_visit(child)


# --- figures and states -------------------------------------------------------

## Whole percent of the track's concepts at `known` or better (the measure a
## requirement uses): 100 for a stub, 0 for a track with no pack or no progress.
func progress(id: String) -> int:
	var t := catalog.track(id)
	if t.is_empty():
		return 0
	if t["stub"]:
		return 100
	var pack := catalog.pack_for(id)
	if pack == null or pack.concepts.is_empty() or not profile.has_track(id):
		return 0
	var view := profile.view(id)
	var known := 0
	for cid in pack.concepts:
		var tier := Mastery.tier(view, cid)
		if tier == Mastery.TIER_KNOWN or tier == Mastery.TIER_MASTERED:
			known += 1
	return known * 100 / pack.concepts.size()


## True when the track's exam has been passed (see Exams).
func exam_passed(id: String) -> bool:
	return profile.has_track(id) and Exams.passed(profile.view(id))


## The requirements of `id` that are not met yet, as {"track", "percent", "have", "exam"}
## (`exam` true for an "exam passed" requirement, which has no percent).
func unmet(id: String) -> Array:
	var out: Array = []
	for r in catalog.track(id).get("requires", []):
		if r.has("exam"):
			if not exam_passed(r["track"]):
				out.append({"track": r["track"], "percent": 0, "have": 0, "exam": true})
			continue
		var have := progress(r["track"])
		if have < r["percent"]:
			out.append({"track": r["track"], "percent": r["percent"], "have": have, "exam": false})
	return out


func price(id: String) -> int:
	return int(catalog.track(id).get("price", 0))


func is_opened(id: String) -> bool:
	var tree: Variant = profile.data.get("tree")
	if typeof(tree) == TYPE_DICTIONARY and typeof(tree.get("opened")) == TYPE_DICTIONARY and tree["opened"].has(id):
		return true
	return profile.has_track(id)


func unlock_all() -> bool:
	return profile.data.get("unlock_all", false) == true


func state(id: String) -> String:
	var t := catalog.track(id)
	if t.is_empty():
		return UNAVAILABLE
	if t["stub"]:
		return COMPLETE
	if t["status"] == TrackCatalog.UNAVAILABLE:
		return UNAVAILABLE
	if t["status"] == TrackCatalog.SOON:
		return SOON
	if unlock_all() or is_opened(id):
		return OPEN
	if not unmet(id).is_empty():
		return LOCKED
	return OPEN if price(id) == 0 else AVAILABLE


## Track ids the arrows may visit: the playable ones that are OPEN.
func selectable() -> Array:
	var out: Array = []
	for id in _order:
		if state(id) == OPEN:
			out.append(id)
	return out


## The track a typed number (its row in the tree), id or title points at, or "".
func resolve(text: String) -> String:
	var t := text.strip_edges().to_lower()
	if t.is_valid_int():
		var n := int(t)
		return _order[n - 1] if n >= 1 and n <= _order.size() else ""
	for id in _order:
		if id == t or (catalog.track(id)["title"] as String).to_lower() == t:
			return id
	return ""


## One sentence on why `id` cannot be played yet, or "" when it can.
func explain(id: String) -> String:
	var title: String = catalog.track(id)["title"]
	match state(id):
		LOCKED:
			var parts: Array = []
			for u in unmet(id):
				var need: String = catalog.track(u["track"])["title"]
				parts.append("the %s exam passed" % need if u["exam"] else "%s at %d%% (now %d%%)" % [need, u["percent"], u["have"]])
			return "%s is locked. It needs %s." % [title, ", ".join(parts)]
		AVAILABLE:
			return "%s is not open yet. It costs %s cycles (you have %s): type open %d." % [title,
					Economy.format_int(price(id)), Economy.format_int(floori(Economy.cycles(profile))), _order.find(id) + 1]
		SOON:
			return "%s is coming soon; it has no content yet." % title
		COMPLETE:
			return "%s has no content yet; it counts as complete for now." % title
		UNAVAILABLE:
			return "%s is unavailable: %s." % [title, catalog.track(id).get("reason", "")]
	return ""


## Pay for `id` and record it as opened. "" on success, otherwise why not.
func open(id: String, now: int) -> String:
	match state(id):
		AVAILABLE:
			pass
		OPEN:
			return "%s is already open." % catalog.track(id)["title"]
		_:
			return explain(id)
	if not Economy.spend(profile, price(id)):
		return "%s costs %s cycles; you have %s." % [catalog.track(id)["title"], Economy.format_int(price(id)),
				Economy.format_int(floori(Economy.cycles(profile)))]
	if typeof(profile.data.get("tree")) != TYPE_DICTIONARY:
		profile.data["tree"] = {}
	if typeof(profile.data["tree"].get("opened")) != TYPE_DICTIONARY:
		profile.data["tree"]["opened"] = {}
	profile.data["tree"]["opened"][id] = now
	return ""


# --- the screen -----------------------------------------------------------------

func lines(selected_id: String) -> Array:
	var out: Array = [Lines.make("SKILL TREE  //  %s" % Economy.summary(profile, today, rules), Lines.S_ACCENT),
			Lines.make("Up/down choose, Enter plays, open <number> unlocks, or type a number.", Lines.S_DIM), Lines.make("")]
	for id in _order:
		out.append(_row(id, id == selected_id))
	if selectable().is_empty():
		out.append(Lines.make(""))
		out.append(Lines.make("No track is open yet.", Lines.S_ERROR))
	return out


func _row(id: String, selected: bool) -> Dictionary:
	var t := catalog.track(id)
	var title: String = _indent(id) + (t["title"] as String)
	if title.length() > TITLE_WIDTH + 6:
		title = title.substr(0, TITLE_WIDTH + 5) + "…"
	var head := "%s %2d  %s" % [">" if selected else " ", _order.find(id) + 1, title.rpad(TITLE_WIDTH + 6)]
	var st := state(id)
	var style := Lines.S_NORMAL
	var tail := ""
	match st:
		COMPLETE:
			tail = "complete"
			style = Lines.S_DIM
		OPEN:
			tail = "open %4d%%" % progress(id) if profile.has_track(id) else "open     new"
			if exam_passed(id):
				tail += "  exam passed"
		AVAILABLE:
			tail = "%s cycles  (open %d)" % [Economy.format_int(price(id)), _order.find(id) + 1]
			style = Lines.S_OK
		LOCKED:
			var parts: Array = []
			for u in unmet(id):
				parts.append("exam passed on %d" % (_order.find(u["track"]) + 1) if u["exam"]
						else "%d at %d%% (now %d%%)" % [_order.find(u["track"]) + 1, u["percent"], u["have"]])
			tail = "locked: needs " + ", ".join(parts)
			style = Lines.S_DIM
		SOON:
			tail = "coming soon"
			style = Lines.S_DIM
		UNAVAILABLE:
			tail = "unavailable (%s)" % t.get("reason", "")
			style = Lines.S_ERROR
	if selected and st == OPEN:
		style = Lines.S_ACCENT
	return Lines.make("%s %s" % [head, tail], style)


## The branch drawing in front of a title: nothing for a root, otherwise a
## connector per level ("│  " while the parent has more children, "   " after
## its last), then "├─ " or "└─ " for the node itself.
func _indent(id: String) -> String:
	var parent := parent_of(id)
	if parent == "":
		return ""
	var siblings := children_of(parent)
	var mine := ("└─ " if siblings.back() == id else "├─ ")
	var ancestors := ""
	var up := parent
	while parent_of(up) != "":
		var grand := parent_of(up)
		ancestors = ("   " if children_of(grand).back() == up else "│  ") + ancestors
		up = grand
	return ancestors + mine
