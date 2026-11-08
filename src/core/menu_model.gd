class_name MenuModel
extends RefCounted
## The track menu (README "Track menu plan"): the rows, which can be chosen,
## and the screen lines. Tracks are numbered in catalog order across sections;
## the arrows only visit playable ones, but a typed number reaches any of them
## so a greyed row can say why it is not ready.

const TITLE_WIDTH := 34

var catalog: TrackCatalog
var profile: Profile
var rules: Rules
var base_ranks: Array  # the engine's ladder, for packs that bring none
var today := 0
## The skill tree, when the catalog has one (README "Skill tree plan"); null for a plain list.
var tree: TreeModel = null


func _init(cat: TrackCatalog, p: Profile, rules_in: Rules, base_ranks_in: Array, today_in: int) -> void:
	catalog = cat
	profile = p
	rules = rules_in
	base_ranks = base_ranks_in
	today = today_in
	if catalog.has_tree():
		tree = TreeModel.new(catalog, profile, rules, today)


## Track ids the arrows move over.
func selectable() -> Array:
	return tree.selectable() if tree != null else catalog.playable_ids()


## The track a typed number, id or title points at, or "".
func resolve(text: String) -> String:
	if tree != null:
		return tree.resolve(text)
	var all := catalog.all_tracks()
	var t := text.strip_edges().to_lower()
	if t.is_valid_int():
		var n := int(t)
		return all[n - 1]["id"] if n >= 1 and n <= all.size() else ""
	for track in all:
		if track["id"] == t or (track["title"] as String).to_lower() == t:
			return track["id"]
	return ""


func screen(selected_id: String) -> Array:
	if tree != null:
		return tree.lines(selected_id)
	var out: Array = [Lines.make("TRACKS  //  up/down to move, Enter to choose, or type a number", Lines.S_ACCENT)]
	var n := 0
	for s in catalog.sections:
		out.append(Lines.make(""))
		out.append(Lines.make(s["title"]))
		for t in s["tracks"]:
			n += 1
			out.append(_row(n, t, t["id"] == selected_id))
	if selectable().is_empty():
		out.append(Lines.make(""))
		out.append(Lines.make("No track has content yet.", Lines.S_ERROR))
	return out


func _row(number: int, t: Dictionary, selected: bool) -> Dictionary:
	var title: String = t["title"]
	if title.length() > TITLE_WIDTH:
		title = title.substr(0, TITLE_WIDTH - 1) + "…"
	var head := "%s %2d  %s" % [">" if selected else " ", number, title.rpad(TITLE_WIDTH)]
	if t["status"] == TrackCatalog.SOON:
		return Lines.make("%s coming soon" % head, Lines.S_DIM)
	if t["status"] == TrackCatalog.UNAVAILABLE:
		return Lines.make("%s unavailable (%s)" % [head, t["reason"]], Lines.S_ERROR)
	return Lines.make("%s %s" % [head, progress_text(t["id"])], Lines.S_ACCENT if selected else Lines.S_NORMAL)


## "Net Runner   420 XP   9 due", or "new" for a track never played.
func progress_text(track_id: String) -> String:
	if not profile.has_track(track_id):
		return "new"
	var pack := catalog.pack_for(track_id)
	var view := profile.view(track_id)
	var ladder: Array = pack.ranks if not pack.ranks.is_empty() else base_ranks
	var xp := Mastery.total_xp(view)
	var open := MapModel.new(pack, view, rules).open_ids()
	var due := Scheduler.due_concepts(pack, view, open, today).size()
	return "%-13s %5d XP   %d due" % [Rules.ladder_name(ladder, Rules.ladder_index(ladder, xp)), xp, due]
