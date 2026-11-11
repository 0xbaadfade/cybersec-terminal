class_name TagRegistry
extends RefCounted
## data/tags.json: the one list of tags an item may carry (README "Shared bank plan").
##   {"areas": {"wireless": "..."}, "renamed": {"old.id": "new.id"},
##    "tags": [{"id": "wireless.sae", "title": "...", "kind": "topic"}, ...]}
## kind: topic (what an item teaches, `<area>.<topic>`; mastery is tracked per topic), pack (which pack an item is for),
## flag (says something about the item, such as `public`).

const DEFAULT_PATH := "res://data/tags.json"
const KINDS: Array = ["topic", "pack", "flag"]
const MAX_TAGS := 8
const MAX_TOPICS := 3

var areas: Dictionary = {}
var renamed: Dictionary = {}
var kinds: Dictionary = {}  # tag id -> kind
var titles: Dictionary = {}  # tag id -> title
var errors: Array = []


static func load_file(path: String = DEFAULT_PATH) -> TagRegistry:
	var reg := TagRegistry.new()
	reg._load(path)
	return reg


func ok() -> bool:
	return errors.is_empty()


func has(tag: String) -> bool:
	return kinds.has(tag)


func kind_of(tag: String) -> String:
	return str(kinds.get(tag, ""))


## `tag`, followed through the `renamed` table to its current id.
func current(tag: String) -> String:
	var seen := 0
	while renamed.has(tag) and seen < 20:
		tag = str(renamed[tag])
		seen += 1
	return tag


## A tag id of any kind: lowercase letters and digits, joined by . : _ or -.
static func well_formed(tag: String) -> bool:
	return _words(tag, ".:_-")


## A topic id: `<area>.<topic>`, the topic in lowercase words joined by hyphens.
static func topic_well_formed(tag: String) -> bool:
	var parts := tag.split(".")
	return parts.size() == 2 and _words(parts[0], "") and _words(parts[1], "-")


## Words of [a-z0-9] joined by single separators from `seps` (none at either end, none doubled).
static func _words(text: String, seps: String) -> bool:
	if text == "":
		return false
	var prev_sep := true  # a separator may not come first
	for c in text:
		if seps.contains(c):
			if prev_sep:
				return false
			prev_sep = true
		elif (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			prev_sep = false
		else:
			return false
	return not prev_sep


func _load(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		errors.append("%s: cannot open the tag registry" % path)
		return
	var json := JSON.new()
	if json.parse(f.get_as_text()) != OK:
		errors.append("%s: line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return
	var data: Variant = json.data
	if typeof(data) != TYPE_DICTIONARY or typeof(data.get("tags")) != TYPE_ARRAY:
		errors.append("%s: expected an object with a 'tags' array" % path)
		return
	var area_v: Variant = data.get("areas", {})
	areas = area_v if typeof(area_v) == TYPE_DICTIONARY else {}
	for entry in data["tags"]:
		if typeof(entry) != TYPE_DICTIONARY or typeof(entry.get("id")) != TYPE_STRING \
				or typeof(entry.get("title")) != TYPE_STRING or not KINDS.has(entry.get("kind")):
			errors.append("tags.json: each tag needs a string id, a string title and a kind (%s)" % ", ".join(KINDS))
			continue
		var tag: String = entry["id"]
		if kinds.has(tag):
			errors.append("tags.json: duplicate tag '%s'" % tag)
			continue
		if entry["kind"] == "topic":
			if not topic_well_formed(tag):
				errors.append("tags.json: bad topic id '%s' (want <area>.<topic>, lowercase)" % tag)
				continue
			if not areas.has(tag.get_slice(".", 0)):
				errors.append("tags.json: topic '%s' is in the unknown area '%s'" % [tag, tag.get_slice(".", 0)])
				continue
		elif not well_formed(tag) or tag.contains("."):
			errors.append("tags.json: bad %s tag '%s' (lowercase letters, digits and hyphens)" % [entry["kind"], tag])
			continue
		kinds[tag] = entry["kind"]
		titles[tag] = entry["title"]
	var renamed_v: Variant = data.get("renamed", {})
	if typeof(renamed_v) != TYPE_DICTIONARY:
		errors.append("tags.json: 'renamed' must be an object")
		return
	renamed = renamed_v
	for old in renamed:
		if not kinds.has(current(old)):
			errors.append("tags.json: renamed '%s' ends at '%s', which is not a tag" % [old, current(old)])
