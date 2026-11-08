class_name TrackCatalog
extends RefCounted
## The menu's list of tracks (README "Track menu plan"): certifications and
## skills in the order data/tracks.json gives them. A track is playable when
## its pack is on disk and valid, "soon" when no pack exists yet, and
## "unavailable" when a pack is named and present but broken (so a broken pack
## never disappears quietly).
##
## Optional skill-tree fields on a track (README "Skill tree plan"): `requires`
## (a list of {"track": id, "percent": 1-100} or {"track": id, "exam": true}), `price` (whole Cycles) and
## `kind: "stub"` (a node with no content that counts as complete). A catalog with
## none of them is a plain list, as before.
##
## load_file() never throws: problems collect in `errors`, as in Pack.

const DEFAULT_PATH := "res://data/tracks.json"
const DEFAULT_PACKS_DIR := "res://packs"
const PLAYABLE := "playable"
const SOON := "soon"
const UNAVAILABLE := "unavailable"

var sections: Array = []  # {id, title, tracks: [{id, title, pack, status, reason}]}
var packs: Dictionary = {}  # track id -> Pack, playable tracks only
var legacy_track := ""  # where a v1 save's progress belongs
var errors: Array = []

var _by_id: Dictionary = {}


## One section with one playable track: for code that only has a Pack.
static func single(content_pack: Pack) -> TrackCatalog:
	var c := TrackCatalog.new()
	var t := {"id": content_pack.id, "title": content_pack.title, "pack": content_pack.id, "status": PLAYABLE, "reason": "",
			"requires": [], "price": 0, "stub": false}
	c.sections.append({"id": "all", "title": "TRACKS", "tracks": [t]})
	c.packs[content_pack.id] = content_pack
	c._by_id[content_pack.id] = t
	c.legacy_track = content_pack.id
	return c


static func load_file(path: String = DEFAULT_PATH, packs_dir: String = DEFAULT_PACKS_DIR) -> TrackCatalog:
	var c := TrackCatalog.new()
	if not FileAccess.file_exists(path):
		c.errors.append("%s: file not found" % path)
		return c
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		c.errors.append("%s line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return c
	if typeof(json.data) != TYPE_DICTIONARY:
		c.errors.append("%s: expected a JSON object" % path)
		return c
	c._build(json.data, packs_dir)
	return c


func pack_for(track_id: String) -> Pack:
	return packs.get(track_id)


func track(track_id: String) -> Dictionary:
	return _by_id.get(track_id, {})


## Every track in menu order (the numbers on screen).
func all_tracks() -> Array:
	var out: Array = []
	for s in sections:
		out.append_array(s["tracks"])
	return out


func playable_ids() -> Array:
	var out: Array = []
	for t in all_tracks():
		if t["status"] == PLAYABLE:
			out.append(t["id"])
	return out


func ok() -> bool:
	return errors.is_empty()


func _build(data: Dictionary, packs_dir: String) -> void:
	var section_list: Variant = data.get("sections")
	if typeof(section_list) != TYPE_ARRAY or (section_list as Array).is_empty():
		errors.append("tracks.json: 'sections' must be a non-empty array")
		return
	var section_ids: Dictionary = {}
	for s in section_list:
		if typeof(s) != TYPE_DICTIONARY or not _text(s.get("id")) or not _text(s.get("title")) \
				or typeof(s.get("tracks")) != TYPE_ARRAY:
			errors.append("tracks.json: every section needs 'id', 'title' and a 'tracks' array")
			continue
		if section_ids.has(s["id"]):
			errors.append("tracks.json: duplicate section id '%s'" % s["id"])
			continue
		section_ids[s["id"]] = true
		var section := {"id": s["id"], "title": s["title"], "tracks": []}
		for raw in s["tracks"]:
			var t := _track(raw, section["id"], packs_dir)
			if not t.is_empty():
				section["tracks"].append(t)
		sections.append(section)
	_check_tree()
	if data.has("legacy_track"):
		var legacy: Variant = data["legacy_track"]
		if typeof(legacy) != TYPE_STRING or not _by_id.has(legacy):
			errors.append("tracks.json: 'legacy_track' must name a track id")
		else:
			legacy_track = legacy


## One track entry as the menu uses it, or {} (with an error) when unusable.
func _track(raw: Variant, section_id: String, packs_dir: String) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY or not _text(raw.get("id")) or not _text(raw.get("title")):
		errors.append("tracks.json: section '%s': every track needs 'id' and 'title'" % section_id)
		return {}
	var id: String = raw["id"]
	if not _slug(id):
		errors.append("tracks.json: track id '%s' must be lowercase letters, digits and '-'" % id)
		return {}
	if _by_id.has(id):
		errors.append("tracks.json: duplicate track id '%s'" % id)
		return {}
	var t := {"id": id, "title": raw["title"], "pack": "", "status": SOON, "reason": "",
			"requires": [], "price": 0, "stub": false}
	if not _tree_fields(raw, t):
		return {}
	if raw.has("pack"):
		if not _text(raw["pack"]):
			errors.append("tracks.json: track '%s': 'pack' must be a folder name" % id)
			return {}
		t["pack"] = raw["pack"]
		_resolve(t, packs_dir)
	_by_id[id] = t
	return t


## Copy the optional tree fields of `raw` into `t`; false (with an error) when one is malformed.
## The names in `requires` are checked later, once every track is known.
func _tree_fields(raw: Dictionary, t: Dictionary) -> bool:
	var id: String = t["id"]
	if raw.has("kind"):
		if raw["kind"] != "stub":
			errors.append("tracks.json: track '%s': 'kind' can only be \"stub\"" % id)
			return false
		if raw.has("pack"):
			errors.append("tracks.json: track '%s': a stub has no pack" % id)
			return false
		t["stub"] = true
	if raw.has("price"):
		var price: Variant = raw["price"]
		if not (typeof(price) in [TYPE_INT, TYPE_FLOAT]) or price != floorf(price) or price < 0:
			errors.append("tracks.json: track '%s': 'price' must be a whole number >= 0" % id)
			return false
		t["price"] = int(price)
	if raw.has("requires"):
		if typeof(raw["requires"]) != TYPE_ARRAY:
			errors.append("tracks.json: track '%s': 'requires' must be a list" % id)
			return false
		for r in raw["requires"]:
			var bad := "tracks.json: track '%s': each requirement is {\"track\": id, \"percent\": 1 to 100} or {\"track\": id, \"exam\": true}" % id
			if typeof(r) != TYPE_DICTIONARY or not _text(r.get("track")) or r.has("percent") == r.has("exam"):
				errors.append(bad)
				return false
			if r.has("exam"):
				if r["exam"] != true:
					errors.append(bad)
					return false
				t["requires"].append({"track": r["track"], "exam": true})
				continue
			var pct: Variant = r["percent"]
			if not (typeof(pct) in [TYPE_INT, TYPE_FLOAT]) or pct != floorf(pct) or pct < 1 or pct > 100:
				errors.append(bad)
				return false
			t["requires"].append({"track": r["track"], "percent": int(pct)})
	return true


## True when any track carries a tree field.
func has_tree() -> bool:
	for t in all_tracks():
		if t["stub"] or t["price"] > 0 or not (t["requires"] as Array).is_empty():
			return true
	return false


## Every requirement names another track, and no chain of requirements loops back.
func _check_tree() -> void:
	for t in all_tracks():
		for r in t["requires"]:
			if not _by_id.has(r["track"]):
				errors.append("tracks.json: track '%s' requires unknown track '%s'" % [t["id"], r["track"]])
			elif r["track"] == t["id"]:
				errors.append("tracks.json: track '%s' requires itself" % t["id"])
			elif r.has("exam"):
				# A track with no pack yet is not checked, so a planned track can still be named.
				var target: Dictionary = _by_id[r["track"]]
				if target["stub"]:
					errors.append("tracks.json: track '%s' requires the exam of stub '%s'" % [t["id"], r["track"]])
				elif packs.has(r["track"]) and Exams.pass_percent(packs[r["track"]]) == 0:
					errors.append("tracks.json: track '%s' requires the exam of '%s', whose pack gives no pass_percent" % [t["id"], r["track"]])
	for t in all_tracks():
		var seen: Dictionary = {}
		var stack: Array = [t["id"]]
		while not stack.is_empty():
			var at: String = stack.pop_back()
			for r in _by_id.get(at, {}).get("requires", []):
				if r["track"] == t["id"] and at != t["id"]:
					errors.append("tracks.json: track '%s' is part of a requirement loop" % t["id"])
					stack.clear()
					break
				if _by_id.has(r["track"]) and not seen.has(r["track"]):
					seen[r["track"]] = true
					stack.append(r["track"])


func _resolve(t: Dictionary, packs_dir: String) -> void:
	var dir := packs_dir.path_join(t["pack"])
	if not DirAccess.dir_exists_absolute(dir):
		return  # named but not written yet: the same as no pack
	var p := Pack.load_dir(dir)
	if not p.ok():
		t["status"] = UNAVAILABLE
		t["reason"] = "pack %s has %d error%s" % [t["pack"], p.errors.size(), "" if p.errors.size() == 1 else "s"]
	elif p.id != t["id"]:
		t["status"] = UNAVAILABLE
		t["reason"] = "pack id '%s' does not match track id '%s'" % [p.id, t["id"]]
	else:
		t["status"] = PLAYABLE
		packs[t["id"]] = p
	if t["status"] == UNAVAILABLE:
		errors.append("tracks.json: track '%s': %s" % [t["id"], t["reason"]])


## Lowercase letters, digits and '-', starting with a letter or digit.
static func _slug(id: String) -> bool:
	if id == "" or id[0] == "-":
		return false
	for ch in id:
		if not ((ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == "-"):
			return false
	return true


static func _text(v: Variant) -> bool:
	return typeof(v) == TYPE_STRING and (v as String).strip_edges() != ""
