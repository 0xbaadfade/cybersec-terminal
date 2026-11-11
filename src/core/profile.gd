class_name Profile
extends RefCounted
## One learner's saved state (README "Profiles and the instructor view").
## Plain data: ProfileStore does the file work, nothing here touches disk.
##
## v3 (README "Shared bank plan", "Saved progress: profile v3"): mastery is the learner's, not a track's. The top level
## holds `topics` (per-topic box, seen, due day: shared by every track) and `items` (per-item answers, shared too); each
## track keeps only its XP, round log, best streak, `unlock_all`, exam record and daily payment record. v2 kept `concepts`
## and `items` per track under pack-local concept ids; from_dict() converts them with data/tag_migration.json.

const VERSION := 3
## Rounds kept in a track's log; older ones are dropped.
const ROUND_LOG_MAX := 100
## What a v1 file kept at the top level and v2 keeps per track.
const PROGRESS_KEYS: Array = ["xp", "concepts", "items", "rounds", "best_streak", "unlock_all"]
## What v3 keeps per track; `concepts` and `items` moved to the top level.
const V2_ONLY_KEYS: Array = ["concepts", "items"]
const NAME_MIN := 2
const NAME_MAX := 20
## Words the login prompt treats as commands, so they cannot be user names.
const RESERVED: Array = ["new", "help", "quit", "exit", "logout", "list", "clear"]

var username := ""
var data: Dictionary = {}
## The track whose progress progress() reads and writes ("" until one is chosen).
var track := ""
## 1 or 2 when this profile was read from a v1 or v2 file and has not been saved since.
var migrated_from := 0


## "" when the name is allowed, otherwise a sentence saying why not.
static func username_problem(raw: String) -> String:
	var s := raw.strip_edges().to_lower()
	if s.length() < NAME_MIN or s.length() > NAME_MAX:
		return "A user name is %d-%d characters." % [NAME_MIN, NAME_MAX]
	var outside := RegEx.new()
	outside.compile("[^a-z0-9_-]")
	if s[0] < "a" or s[0] > "z" or outside.search(s) != null:
		return "Use letters, digits, '-' and '_', starting with a letter."
	if RESERVED.has(s):
		return "'%s' is a command word; pick another name." % s
	return ""


static func normalize(raw: String) -> String:
	return raw.strip_edges().to_lower()


static func fresh(name: String, now: int) -> Profile:
	var p := Profile.new()
	p.username = name
	p.data = {
		"version": VERSION,
		"username": name,
		"created": now,
		"last_seen": now,
		"sessions": 1,
		"topics": {},
		"items": {},
		"tracks": {},
	}
	return p


## null when the dictionary is not a profile this build can read. A v1 file
## (one track's progress at the top level) is moved under `legacy_track` in
## memory, and a v2 file's per-track concept records are folded into shared topic
## records with `migration` ({track id: {old concept id: topic id}}, from
## data/tag_migration.json); the file itself is not touched until the next save.
## Nothing is dropped: records the table cannot place are kept under `unmapped`.
static func from_dict(d: Variant, legacy_track: String = "", migration: Dictionary = {}) -> Profile:
	if typeof(d) != TYPE_DICTIONARY:
		return null
	if typeof(d.get("username")) != TYPE_STRING or username_problem(d["username"]) != "":
		return null
	if typeof(d.get("version")) not in [TYPE_INT, TYPE_FLOAT]:
		return null
	var version := int(d["version"])
	var p := Profile.new()
	p.username = d["username"]
	var data: Dictionary = d
	if version == 1:
		if legacy_track == "":
			return null
		data = _migrate_v1(d, legacy_track)
		version = 2
		p.migrated_from = 1
	if version == 2:
		if typeof(data.get("tracks")) != TYPE_DICTIONARY or migration.is_empty():
			return null
		for id in data["tracks"]:
			if typeof(data["tracks"][id]) != TYPE_DICTIONARY:
				return null
		data = _migrate_v2(data, migration)
		if p.migrated_from == 0:
			p.migrated_from = 2
		version = 3
	if version != VERSION or typeof(data.get("tracks")) != TYPE_DICTIONARY:
		return null
	for id in data["tracks"]:
		if typeof(data["tracks"][id]) != TYPE_DICTIONARY:
			return null
	p.data = data
	return p


## v1 -> v2 without losing a key: progress fields go under the track, anything
## else stays where it was.
static func _migrate_v1(old: Dictionary, legacy_track: String) -> Dictionary:
	var out: Dictionary = {}
	var progress: Dictionary = {"xp": {}, "concepts": {}, "items": {}, "rounds": []}
	for k in old:
		if PROGRESS_KEYS.has(k):
			progress[k] = old[k]
		else:
			out[k] = old[k]
	out["version"] = 2
	out["tracks"] = {legacy_track: progress}
	return out


## v2 -> v3. Each track's concept records become topic records through `migration`; where several records land on one
## topic (a concept merged with another, or the same topic reached from two tracks) they are combined: the higher box,
## the answers added up, the earlier due day, the later last day. Item records are combined the same way. A concept the
## table does not know is kept under `unmapped[track][concept id]`, never dropped.
static func _migrate_v2(old: Dictionary, migration: Dictionary) -> Dictionary:
	var out: Dictionary = old.duplicate(true)
	var topics: Dictionary = {}
	var items: Dictionary = {}
	var unmapped: Dictionary = {}
	var tracks: Dictionary = out["tracks"]
	for id in tracks:
		var track: Dictionary = tracks[id]
		var table: Variant = migration.get(id, {})
		var concepts: Variant = track.get("concepts", {})
		if typeof(concepts) == TYPE_DICTIONARY:
			for cid in concepts:
				var to: Variant = table.get(cid) if typeof(table) == TYPE_DICTIONARY else null
				if typeof(to) != TYPE_STRING or typeof(concepts[cid]) != TYPE_DICTIONARY:
					if not unmapped.has(id):
						unmapped[id] = {}
					unmapped[id][cid] = concepts[cid]
					continue
				topics[to] = _merge_topic(topics.get(to, {}), concepts[cid])
		var track_items: Variant = track.get("items", {})
		if typeof(track_items) == TYPE_DICTIONARY:
			for iid in track_items:
				if typeof(track_items[iid]) == TYPE_DICTIONARY:
					items[iid] = _merge_item(items.get(iid, {}), track_items[iid])
		for k in V2_ONLY_KEYS:
			track.erase(k)
	out["topics"] = topics
	out["items"] = items
	if not unmapped.is_empty():
		out["unmapped"] = unmapped
	out["version"] = VERSION
	return out


static func _merge_topic(a: Dictionary, b: Dictionary) -> Dictionary:
	if a.is_empty():
		return b.duplicate(true)
	var out: Dictionary = a.duplicate(true)
	out["box"] = maxi(int(a.get("box", 0)), int(b.get("box", 0)))
	for k in ["seen", "hits", "misses"]:
		out[k] = int(a.get(k, 0)) + int(b.get(k, 0))
	# Only a record that was seen has a meaningful due day.
	var a_seen := int(a.get("seen", 0)) > 0
	var b_seen := int(b.get("seen", 0)) > 0
	if a_seen and b_seen:
		out["due_day"] = mini(int(a.get("due_day", 0)), int(b.get("due_day", 0)))
	elif b_seen:
		out["due_day"] = int(b.get("due_day", 0))
	out["last_day"] = maxi(int(a.get("last_day", 0)), int(b.get("last_day", 0)))
	return out


static func _merge_item(a: Dictionary, b: Dictionary) -> Dictionary:
	if a.is_empty():
		return b.duplicate(true)
	var out: Dictionary = a.duplicate(true)
	for k in ["seen", "correct", "misses"]:
		if a.has(k) or b.has(k):
			out[k] = int(a.get(k, 0)) + int(b.get(k, 0))
	if int(b.get("last_day", -1)) > int(a.get("last_day", -1)):
		out["last_day"] = b["last_day"]
		if b.has("last_credit"):
			out["last_credit"] = b["last_credit"]
	return out


## A second view of the same saved data on another track, for reading one
## track's numbers (the menu) without switching the learner's own.
func view(track_id: String) -> Profile:
	var v := Profile.new()
	v.username = username
	v.data = data
	v.track = track_id
	return v


func has_track(track_id: String) -> bool:
	return typeof(data.get("tracks")) == TYPE_DICTIONARY and typeof(data["tracks"].get(track_id)) == TYPE_DICTIONARY


## Progress of `track_id`, created empty on first write. Reads that must not
## create anything use peek().
func progress_for(track_id: String) -> Dictionary:
	if typeof(data.get("tracks")) != TYPE_DICTIONARY:
		data["tracks"] = {}
	var tracks: Dictionary = data["tracks"]
	if typeof(tracks.get(track_id)) != TYPE_DICTIONARY:
		tracks[track_id] = {"xp": {}, "rounds": []}
	return tracks[track_id]


func progress() -> Dictionary:
	return progress_for(track)


## The active track's progress, or {} when it has none yet; never creates.
func peek() -> Dictionary:
	return data["tracks"][track] if has_track(track) else {}


## The learner's per-topic mastery, created on first write (shared by every track).
func topic_bucket() -> Dictionary:
	if typeof(data.get("topics")) != TYPE_DICTIONARY:
		data["topics"] = {}
	return data["topics"]


## The learner's per-item answers, created on first write (shared by every track).
func item_bucket() -> Dictionary:
	if typeof(data.get("items")) != TYPE_DICTIONARY:
		data["items"] = {}
	return data["items"]


## Reads that must not create anything.
func peek_topics() -> Dictionary:
	return data["topics"] if typeof(data.get("topics")) == TYPE_DICTIONARY else {}


func peek_items() -> Dictionary:
	return data["items"] if typeof(data.get("items")) == TYPE_DICTIONARY else {}


## The active track's round log, oldest first.
func rounds() -> Array:
	var log: Variant = progress().get("rounds")
	if typeof(log) != TYPE_ARRAY:
		progress()["rounds"] = []
	return progress()["rounds"]


func log_round(entry: Dictionary) -> void:
	var log := rounds()
	log.append(entry)
	while log.size() > ROUND_LOG_MAX:
		log.pop_front()


func touch(now: int) -> void:
	data["last_seen"] = now
	data["sessions"] = int(data.get("sessions", 0)) + 1
