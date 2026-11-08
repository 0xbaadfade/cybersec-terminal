extends GutTest
## Profile v2 (per-track progress) and the lossless v1 -> v2 migration.

const Support := preload("res://tests/unit/support.gd")
const LEGACY := "sec"

var _dir := ""
var _store: ProfileStore


func before_each() -> void:
	_dir = Support.make_dir()
	_store = ProfileStore.new(_dir)
	_store.legacy_track = LEGACY


func after_each() -> void:
	Support.remove_dir(_dir)


func _v1() -> Dictionary:
	return {
		"version": 1, "username": "sam", "created": 100, "last_seen": 200, "sessions": 4,
		"xp": {"total": 130, "4": 130},
		"concepts": {"4.1.baselines": {"box": 3, "seen": 5, "hits": 4, "misses": 1, "last_day": 9, "due_day": 13}},
		"items": {"i-1": {"seen": 5, "correct": 4, "misses": 1, "last_day": 9, "last_credit": 1.0}},
		"rounds": [{"day": 9, "xp": 60}],
		"best_streak": 6, "unlock_all": true, "note_from_instructor": "keep me",
	}


## JSON turns every number into a float on the way back; compare after the same trip.
func _json(v: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(v))


func test_a_fresh_profile_is_v2_with_no_tracks() -> void:
	var p := Profile.fresh("sam", 5)
	assert_eq(int(p.data["version"]), 2)
	assert_eq(p.data["tracks"], {})
	assert_false(p.has_track("sec"))


func test_peek_never_creates_but_progress_does() -> void:
	var p := Profile.fresh("sam", 5)
	p.track = "sec"
	assert_eq(p.peek(), {})
	assert_false(p.has_track("sec"))
	p.progress()["xp"]["total"] = 7
	assert_true(p.has_track("sec"))
	assert_eq(int(p.peek()["xp"]["total"]), 7)


func test_tracks_do_not_share_progress() -> void:
	var p := Profile.fresh("sam", 5)
	p.track = "a"
	Mastery.add_xp(p, "1", 50)
	p.track = "b"
	assert_eq(Mastery.total_xp(p), 0)
	Mastery.add_xp(p, "1", 5)
	assert_eq(Mastery.total_xp(p.view("a")), 50)
	assert_eq(Mastery.total_xp(p.view("b")), 5)


func test_view_reads_another_track_without_switching() -> void:
	var p := Profile.fresh("sam", 5)
	p.track = "a"
	Mastery.add_xp(p, "1", 9)
	var v := p.view("b")
	assert_eq(p.track, "a")
	assert_eq(v.track, "b")
	assert_eq(Mastery.total_xp(v), 0)
	assert_false(p.has_track("b"), "reading a view creates nothing")


func test_v1_dictionary_moves_progress_under_the_legacy_track_and_loses_nothing() -> void:
	var old := _v1()
	var p := Profile.from_dict(old.duplicate(true), LEGACY)
	assert_not_null(p)
	assert_eq(p.migrated_from, 1)
	assert_eq(int(p.data["version"]), 2)
	var prog := p.progress_for(LEGACY)
	for k in ["xp", "concepts", "items", "rounds", "best_streak", "unlock_all"]:
		assert_eq(prog[k], old[k], "progress key %s kept" % k)
		assert_false(p.data.has(k), "%s is no longer at the top" % k)
	for k in ["username", "created", "last_seen", "sessions", "note_from_instructor"]:
		assert_eq(p.data[k], old[k], "account key %s kept" % k)


func test_v1_without_a_legacy_track_is_not_loaded() -> void:
	assert_null(Profile.from_dict(_v1(), ""))


func test_v1_missing_progress_keys_get_empty_defaults() -> void:
	var bare := {"version": 1, "username": "sam", "created": 1, "last_seen": 1, "sessions": 1}
	var p := Profile.from_dict(bare, LEGACY)
	assert_eq(p.progress_for(LEGACY)["xp"], {})
	assert_eq(p.progress_for(LEGACY)["rounds"], [])


func test_unknown_versions_and_bad_tracks_are_refused() -> void:
	var v3 := _v1()
	v3["version"] = 3
	v3["tracks"] = {}
	assert_null(Profile.from_dict(v3, LEGACY))
	assert_null(Profile.from_dict({"version": 2, "username": "sam"}, LEGACY))
	assert_null(Profile.from_dict({"version": 2, "username": "sam", "tracks": []}, LEGACY))
	assert_null(Profile.from_dict({"version": 2, "username": "sam", "tracks": {"a": 5}}, LEGACY))
	assert_null(Profile.from_dict({"version": "2", "username": "sam", "tracks": {}}, LEGACY))


func test_loading_a_v1_file_does_not_touch_it_and_the_first_save_keeps_a_copy() -> void:
	Support.write_json(_store.path_for("sam"), _v1())
	var before := FileAccess.get_file_as_string(_store.path_for("sam"))
	var p := _store.load_profile("sam")
	assert_not_null(p)
	assert_eq(FileAccess.get_file_as_string(_store.path_for("sam")), before, "a read rewrites nothing")
	assert_false(FileAccess.file_exists(_dir.path_join("sam.v1.bak")))
	assert_true(_store.save(p))
	assert_eq(FileAccess.get_file_as_string(_dir.path_join("sam.v1.bak")), before, "the old file is kept as it was")
	assert_eq(int(JSON.parse_string(FileAccess.get_file_as_string(_store.path_for("sam")))["version"]), 2)
	assert_eq(_store.list(), ["sam"], "the backup is not a user")


func test_a_later_save_does_not_replace_the_backup() -> void:
	Support.write_json(_store.path_for("sam"), _v1())
	var original := FileAccess.get_file_as_string(_store.path_for("sam"))
	var p := _store.load_profile("sam")
	_store.save(p)
	Mastery.add_xp(p.view(LEGACY), "4", 10)
	_store.save(p)
	var again := _store.load_profile("sam")
	assert_eq(again.migrated_from, 0, "a v2 file is not migrated again")
	_store.save(again)
	assert_eq(FileAccess.get_file_as_string(_dir.path_join("sam.v1.bak")), original)


func test_progress_survives_load_save_load_exactly() -> void:
	var old := _v1()
	Support.write_json(_store.path_for("sam"), old)
	var p := _store.load_profile("sam")
	_store.save(p)
	var back := _store.load_profile("sam")
	for k in ["xp", "concepts", "items", "rounds", "best_streak", "unlock_all"]:
		assert_eq(_json(back.progress_for(LEGACY)[k]), _json(old[k]), k)
	assert_eq(back.data["note_from_instructor"], "keep me")


func test_answers_after_migration_match_answers_on_the_same_state_before() -> void:
	var rules := Rules.load_default()
	var item := Support.make_item("i-2", "4.1.baselines")
	item["concept_ids"] = ["4.1.baselines"]
	var migrated := Profile.from_dict(_v1(), LEGACY)
	migrated.track = LEGACY
	Mastery.apply(migrated, item, 1.0, Support.T0, rules)
	var expect := Profile.fresh("sam", 1)
	expect.track = LEGACY
	var p1 := _v1()
	for k in ["xp", "concepts", "items", "rounds", "best_streak", "unlock_all"]:
		expect.progress()[k] = p1[k]
	Mastery.apply(expect, item, 1.0, Support.T0, rules)
	assert_eq(migrated.progress(), expect.progress())


func test_a_store_without_the_legacy_track_says_it_cannot_read_a_v1_save() -> void:
	var bare := ProfileStore.new(_dir)
	Support.write_json(bare.path_for("sam"), _v1())
	assert_null(bare.load_profile("sam"))
	assert_string_contains(bare.last_error, "not a profile this version can read")
	assert_eq(FileAccess.get_file_as_string(bare.path_for("sam")), JSON.stringify(_v1(), "\t"), "and left it alone")


func test_an_existing_backup_is_never_overwritten() -> void:
	Support.write_text(_dir.path_join("sam.v1.bak"), "OLDER BACKUP")
	Support.write_json(_store.path_for("sam"), _v1())
	var p := _store.load_profile("sam")
	assert_true(_store.save(p))
	assert_eq(FileAccess.get_file_as_string(_dir.path_join("sam.v1.bak")), "OLDER BACKUP")
