extends GutTest

const Support := preload("res://tests/unit/support.gd")

var _dir := ""
var _store: ProfileStore


func before_each() -> void:
	_dir = Support.make_dir()
	_store = ProfileStore.new(_dir)


func after_each() -> void:
	Support.remove_dir(_dir)


func test_username_rules() -> void:
	assert_eq(Profile.username_problem("dana"), "")
	assert_eq(Profile.username_problem("Dana_2-x"), "", "case is folded, not rejected")
	for bad in ["", "a", "x".repeat(21), "1abc", "has space", "../etc", "a/b", "dot.name", "née"]:
		assert_ne(Profile.username_problem(bad), "", "should reject '%s'" % bad)


func test_command_words_are_reserved() -> void:
	for word in Profile.RESERVED:
		assert_ne(Profile.username_problem(word), "", word)


func test_create_then_list_and_load() -> void:
	var p := _store.create("Dana")
	assert_not_null(p)
	assert_eq(p.username, "dana")
	assert_eq(_store.list(), ["dana"])
	assert_true(_store.exists("DANA"))
	var loaded := _store.load_profile("dana")
	assert_not_null(loaded)
	assert_eq(int(loaded.data["created"]), int(p.data["created"]))


func test_create_rejects_duplicates_and_bad_names() -> void:
	assert_not_null(_store.create("dana"))
	assert_null(_store.create("Dana"))
	assert_string_contains(_store.last_error, "already exists")
	assert_null(_store.create("../evil"))
	assert_eq(_store.list(), ["dana"])


func test_save_round_trips_progress() -> void:
	var p := _store.create("sam")
	p.progress()["xp"]["4"] = 120
	p.progress()["concepts"]["4.1.baselines"] = {"box": 2, "misses": 1}
	assert_true(_store.save(p))
	var back := _store.load_profile("sam")
	assert_eq(int(back.progress()["xp"]["4"]), 120)
	assert_eq(int(back.progress()["concepts"]["4.1.baselines"]["box"]), 2)


func test_save_replaces_and_leaves_no_temp_file() -> void:
	var p := _store.create("sam")
	p.data["sessions"] = 7
	assert_true(_store.save(p))
	assert_true(_store.save(p), "a second save over an existing file works")
	assert_eq(int(_store.load_profile("sam").data["sessions"]), 7)
	for f in DirAccess.get_files_at(_dir):
		assert_false((f as String).ends_with(".tmp"), "stray %s" % f)


func test_corrupt_save_is_reported_not_thrown() -> void:
	_store.create("sam")
	Support.write_text(_store.path_for("sam"), "{ not json")
	assert_null(_store.load_profile("sam"))
	assert_string_contains(_store.last_error, "damaged")


func test_save_from_a_newer_version_is_refused() -> void:
	_store.create("sam")
	Support.write_json(_store.path_for("sam"), {"version": 99, "username": "sam"})
	assert_null(_store.load_profile("sam"))
	assert_string_contains(_store.last_error, "not a profile this version")


func test_save_for_a_different_user_is_refused() -> void:
	_store.create("sam")
	var other := Profile.fresh("eve", 0)
	Support.write_json(_store.path_for("sam"), other.data)
	assert_null(_store.load_profile("sam"), "file name and username must agree")


func test_missing_user() -> void:
	assert_null(_store.load_profile("nobody"))
	assert_string_contains(_store.last_error, "No such user")


func test_touch_counts_sessions() -> void:
	var p := Profile.fresh("sam", 100)
	p.touch(200)
	assert_eq(int(p.data["sessions"]), 2)
	assert_eq(int(p.data["last_seen"]), 200)
