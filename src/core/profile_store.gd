class_name ProfileStore
extends RefCounted
## Profiles on disk, one JSON file per user: <dir>/<username>.json.
##
## A save writes <username>.json.tmp and renames it over the real file, so a
## closed window or a crash leaves the previous complete save, never half of a
## new one. Failures return null/false and set `last_error`; nothing throws.

var dir := ""
var last_error := ""
## The track a v1 save (written before tracks existed) belongs to; set from the
## track catalog. Without it a v1 save cannot be placed and is not loaded.
var legacy_track := ""
## Where the v2 -> v3 table (old concept id -> topic id, per track) lives. Profile.from_dict explains what it is for.
var migration_path := "res://data/tag_migration.json"
var _migration: Dictionary = {}
var _migration_loaded := false


func _init(profiles_dir: String) -> void:
	dir = profiles_dir.trim_suffix("/")
	DirAccess.make_dir_recursive_absolute(dir)


func path_for(username: String) -> String:
	return dir.path_join("%s.json" % username)


func list() -> Array:
	var out: Array = []
	for f in DirAccess.get_files_at(dir):
		if (f as String).ends_with(".json"):
			out.append((f as String).trim_suffix(".json"))
	out.sort()
	return out


func exists(raw_name: String) -> bool:
	return FileAccess.file_exists(path_for(Profile.normalize(raw_name)))


func create(raw_name: String) -> Profile:
	last_error = Profile.username_problem(raw_name)
	if last_error != "":
		return null
	var name := Profile.normalize(raw_name)
	if exists(name):
		last_error = "'%s' already exists." % name
		return null
	var p := Profile.fresh(name, int(Time.get_unix_time_from_system()))
	return p if save(p) else null


## {track id: {old concept id: topic id}}, {} when the file is missing or damaged.
func migration() -> Dictionary:
	if not _migration_loaded:
		_migration_loaded = true
		if FileAccess.file_exists(migration_path):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(migration_path))
			if typeof(parsed) == TYPE_DICTIONARY:
				_migration = parsed
	return _migration


func load_profile(raw_name: String) -> Profile:
	last_error = ""
	var name := Profile.normalize(raw_name)
	if Profile.username_problem(name) != "" or not exists(name):
		last_error = "No such user '%s'." % name
		return null
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path_for(name))) != OK:
		last_error = "The save for '%s' is damaged (%s)." % [name, json.get_error_message()]
		return null
	var p := Profile.from_dict(json.data, legacy_track, migration())
	if p == null and typeof(json.data) == TYPE_DICTIONARY and int(json.data.get("version", 0)) <= 2 and migration().is_empty():
		last_error = "The save for '%s' is from an older version and needs %s to be upgraded; it was not changed." % [name, migration_path]
		return null
	if p == null or p.username != name:
		last_error = "The save for '%s' is not a profile this version can read." % name
		return null
	return p


func save(p: Profile) -> bool:
	last_error = ""
	var final_path := path_for(p.username)
	var tmp_path := final_path + ".tmp"
	# The first save of a migrated v1 or v2 profile keeps the old file beside it (<name>.v1.bak, <name>.v2.bak).
	if p.migrated_from > 0 and FileAccess.file_exists(final_path):
		var backup := "%s/%s.v%d.bak" % [dir, p.username, p.migrated_from]
		if not FileAccess.file_exists(backup) \
				and DirAccess.copy_absolute(ProjectSettings.globalize_path(final_path), ProjectSettings.globalize_path(backup)) != OK:
			last_error = "Cannot back up %s before upgrading it." % final_path
			return false
	var f := FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		last_error = "Cannot write %s (error %d)." % [tmp_path, FileAccess.get_open_error()]
		return false
	f.store_string(JSON.stringify(p.data, "\t", true))
	f.close()
	var err := DirAccess.rename_absolute(
			ProjectSettings.globalize_path(tmp_path), ProjectSettings.globalize_path(final_path))
	if err != OK:
		last_error = "Cannot replace %s (error %d)." % [final_path, err]
		return false
	p.migrated_from = 0
	return true
