class_name Profile
extends RefCounted
## One learner's saved state (README "Profiles and the instructor view").
## Plain data: ProfileStore does the file work, nothing here touches disk.

const VERSION := 2
## Rounds kept in a track's log; older ones are dropped.
const ROUND_LOG_MAX := 100
## What a v1 file kept at the top level and v2 keeps per track.
const PROGRESS_KEYS: Array = ["xp", "concepts", "items", "rounds", "best_streak", "unlock_all"]
const NAME_MIN := 2
const NAME_MAX := 20
## Words the login prompt treats as commands, so they cannot be user names.
const RESERVED: Array = ["new", "help", "quit", "exit", "logout", "list", "clear"]

var username := ""
var data: Dictionary = {}
## The track whose progress progress() reads and writes ("" until one is chosen).
var track := ""
## 1 when this profile was read from a v1 file and has not been saved since.
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
		"tracks": {},
	}
	return p


## null when the dictionary is not a profile this build can read. A v1 file
## (one track's progress at the top level) is moved under `legacy_track` in
## memory; the file itself is not touched until the next save.
static func from_dict(d: Variant, legacy_track: String = "") -> Profile:
	if typeof(d) != TYPE_DICTIONARY:
		return null
	if typeof(d.get("username")) != TYPE_STRING or username_problem(d["username"]) != "":
		return null
	if typeof(d.get("version")) not in [TYPE_INT, TYPE_FLOAT]:
		return null
	var version := int(d["version"])
	var p := Profile.new()
	p.username = d["username"]
	if version == 1:
		if legacy_track == "":
			return null
		p.data = _migrate_v1(d, legacy_track)
		p.migrated_from = 1
		return p
	if version != VERSION or typeof(d.get("tracks")) != TYPE_DICTIONARY:
		return null
	for id in d["tracks"]:
		if typeof(d["tracks"][id]) != TYPE_DICTIONARY:
			return null
	p.data = d
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
	out["version"] = VERSION
	out["tracks"] = {legacy_track: progress}
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
		tracks[track_id] = {"xp": {}, "concepts": {}, "items": {}, "rounds": []}
	return tracks[track_id]


func progress() -> Dictionary:
	return progress_for(track)


## The active track's progress, or {} when it has none yet; never creates.
func peek() -> Dictionary:
	return data["tracks"][track] if has_track(track) else {}


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
