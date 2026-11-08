extends GutTest
## An evidence hunt as the exam holds it (README "Student simplification Part 2
## plan"): the screen, the keys, the reason menu, and the review after submit.
## Hunts are no longer practised anywhere else; rounds never hold one.

const Support := preload("res://tests/unit/support.gd")

var _dir := ""
var _router: CommandRouter
var _now := Support.T0


## A 6-question exam whose one PBQ is the demo hunt (`ev-0`, three flaws on lines 3, 4, 5;
## decoy on line 2).
func _start(artifact: String = "", item_changes: Dictionary = {}) -> void:
	_now = Support.T0
	_dir = Support.make_dir()
	var root := _dir.path_join("pack")
	Support.write_exam_pbq_pack(root, 6, 1, 8, 1)
	if artifact != "":
		Support.write_text(root.path_join("artifacts/demo.txt"), artifact)
	if not item_changes.is_empty():
		var items: Array = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("items/all.json")))
		for it in items:
			if it["id"] == "ev-0":
				it.merge(item_changes, true)
		Support.write_json(root.path_join("items/all.json"), items)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	_router = CommandRouter.new(ProfileStore.new(_dir.path_join("saves")), Pack.load_dir(root), null, rng,
			func() -> int: return _now)
	_router.handle("new dana")
	_router.handle("exam")
	assert_eq(_router.exam.item_at(0)["id"], "ev-0")


func after_each() -> void:
	Support.remove_dir(_dir)


func _text(lines: Array) -> String:
	return "\n".join(lines.map(func(l): return l.get("t", "")))


func _flags() -> Dictionary:
	return _router.exam.session().flags


func test_rounds_never_hold_a_hunt() -> void:
	_start()
	_router.handle("leave")
	_router.handle("yes")
	for node in ["1.1", "1.2", "2.1"]:
		_router.handle("breach %s" % node)
		if _router.current_round == null:
			continue
		for e in _router.current_round.queue:
			assert_ne(_router.pack.items[e["item"]]["type"], "evidence")
		_router.handle("leave")


func test_hunt_screen_shows_stem_title_lines_and_cursor() -> void:
	_start()
	assert_eq(_router.mode, CommandRouter.Mode.EXAM)
	assert_eq(_router.prompt(), "exam>")
	var text := _text(_router.handle("clear"))
	assert_string_contains(text, "EXAM  //  question 1 of 6")
	assert_string_contains(text, "PBQ: flag the weak lines")
	assert_string_contains(text, "Flag what weakens ev-0.")
	assert_string_contains(text, "demo: config")
	assert_string_contains(text, "FLAGS 0")
	assert_string_contains(text, "lines 1-6 of 6")
	assert_string_contains(text, ">   1  # demo config")
	assert_string_contains(text, "    3  RootLogin yes")


func test_up_down_move_the_cursor_and_redraw_in_place() -> void:
	_start()
	var down := _router.handle("@down")
	assert_eq(down[0], Lines.CLEAR)
	assert_string_contains(_text(down), ">   2  Port 22")
	_router.handle("@down")
	assert_string_contains(_text(_router.handle("@up")), ">   2  Port 22")
	for k in 9:
		_router.handle("@down")
	assert_string_contains(_text(_router.handle("@down")), ">   6  Debug off")
	for k in 9:
		_router.handle("@up")
	assert_string_contains(_text(_router.handle("@up")), ">   1  # demo config")


func test_enter_flags_the_cursor_line_and_a_digit_picks_the_reason() -> void:
	_start()
	_router.handle("@down")
	_router.handle("@down")
	var menu := _text(_router.handle(""))
	assert_eq(_router.prompt(), "why?>")
	assert_string_contains(menu, "Why is line 3 a problem?")
	assert_string_contains(menu, "  1  weak authentication")
	assert_string_contains(menu, "  4  weak or missing encryption")
	assert_string_contains(menu, "  5  not a problem (remove the flag)")
	var after := _text(_router.handle("2"))
	assert_eq(_router.prompt(), "exam>")
	assert_string_contains(after, "FLAGS 1")
	assert_string_contains(after, "[excess privilege]")
	assert_eq(_flags(), {3: "excess-privilege"})


func test_esc_and_blank_cancel_the_menu_and_the_last_digit_clears_a_flag() -> void:
	_start()
	_router.handle("f 4")
	_router.handle("@esc")
	assert_eq(_flags(), {})
	_router.handle("f 4")
	_router.handle("")
	assert_eq(_flags(), {})
	assert_eq(_router.prompt(), "exam>")
	_router.handle("f 4 1")
	assert_eq(_flags(), {4: "weak-auth"})
	_router.handle("f 4")
	_router.handle("5")
	assert_eq(_flags(), {})


func test_junk_in_the_menu_and_bad_flag_commands_change_nothing() -> void:
	_start()
	_router.handle("f 3")
	assert_string_contains(_text(_router.handle("zzz")), "Pick 1-5, or Esc to cancel.")
	assert_eq(_router.prompt(), "why?>")
	_router.handle("@esc")
	for bad in ["f 99", "f 0", "f x", "f 3 9", "f 1 2 3", "go z"]:
		var out := _text(_router.handle(bad))
		assert_ne(out, "", bad)
		assert_eq(_router.prompt(), "exam>", bad)
	assert_eq(_flags(), {})


func test_x_removes_a_flag() -> void:
	_start()
	_router.handle("f 4 1")
	_router.handle("f 5 4")
	_router.handle("x 4")
	assert_eq(_flags(), {5: "weak-crypto"})
	assert_string_contains(_text(_router.handle("x 4")), "Line 4 is not flagged.")
	_router.handle("go 5")
	_router.handle("x")
	assert_eq(_flags(), {})


func test_a_perfect_hunt_is_full_credit_and_the_review_just_says_so() -> void:
	_start()
	_router.handle("f 3 2")
	_router.handle("f 4 1")
	_router.handle("f 5 4")
	assert_eq(_router.exam.credit_at(0), 1.0)
	_router.handle("submit")
	var text := _text(_router.handle("yes"))
	assert_string_contains(text, "Q1  PBQ: flag the weak lines   100%")
	assert_false(text.contains("MISSED"))
	assert_false(text.contains("FALSE "))
	assert_false(text.contains("Overall lesson of ev-0"), "a perfect PBQ gets no lesson block, only its line")
	assert_false(text.contains("flaws found"))
	assert_eq(_router.mode, CommandRouter.Mode.HOME)


func test_a_partial_hunt_shows_found_missed_and_false_blocks_in_file_order() -> void:
	_start()
	_router.handle("f 2 1")  # decoy
	_router.handle("f 3 1")  # right line, wrong reason: 70
	_router.handle("f 4 1")  # right line, right reason: 100
	_router.handle("f 6 1")  # plain false flag
	# 170 points less two false flags (90) is 80 of 300.
	assert_almost_eq(_router.exam.credit_at(0), 80.0 / 300.0, 0.0001)
	_router.handle("submit")
	var text := _text(_router.handle("yes"))
	assert_string_contains(text, "Q1  PBQ: flag the weak lines   27%")
	assert_string_contains(text, "2 of 3 flaws found, 2 false flags.")
	assert_string_contains(text, "FALSE   line 2  Port 22")
	assert_string_contains(text, "The default port is fine.")
	assert_string_contains(text, "FOUND   line 3  RootLogin yes   you said: weak authentication  (it is: excess privilege)")
	assert_string_contains(text, "Root login is excess privilege.")
	assert_false(text.contains("line 4  Auth weak"), "a line found with the right reason is not repeated")
	assert_string_contains(text, "MISSED  line 5  Cipher des   (weak or missing encryption or needless exposure)")
	assert_string_contains(text, "FALSE   line 6  Debug off")
	assert_string_contains(text, "This line is fine.")
	assert_lt(text.find("line 2"), text.find("line 3"))
	assert_lt(text.find("line 3"), text.find("line 5"))
	assert_lt(text.find("line 5"), text.find("line 6"))
	assert_string_contains(text, "Overall lesson of ev-0.")


func test_a_hunt_changes_nothing_until_submit_and_leave_discards_it() -> void:
	_start()
	_router.handle("f 4 1")
	var store := ProfileStore.new(_dir.path_join("saves"))
	var mid := store.load_profile("dana")
	mid.track = _router.profile.track
	assert_false(mid.progress().get("items", {}).has("ev-0"))
	_router.handle("leave")
	_router.handle("yes")
	var after := store.load_profile("dana")
	after.track = _router.profile.track
	assert_eq(after.rounds().size(), 0)
	assert_false(after.progress().get("items", {}).has("ev-0"))


func test_a_hunts_result_is_saved_and_the_concept_comes_back_when_missed() -> void:
	_start()
	_router.handle("f 6 1")
	_router.handle("submit")
	_router.handle("yes")
	var saved := ProfileStore.new(_dir.path_join("saves")).load_profile("dana")
	saved.track = _router.profile.track
	assert_true(saved.progress()["items"].has("ev-0"))
	assert_eq(Mastery.box(saved, "1.1.a"), 1)
	assert_eq(Mastery.total_xp(saved), 0, "an exam gives no XP")
	assert_eq(saved.rounds().size(), 1)
	assert_eq(int(saved.rounds()[0]["pbqs"]), 1)


func test_clear_redraws_the_hunt_and_the_menu() -> void:
	_start()
	_router.handle("f 4 1")
	var hunt := _router.handle("clear")
	assert_eq(hunt[0], Lines.CLEAR)
	assert_string_contains(_text(hunt), "[weak authentication]")
	_router.handle("f 3")
	var menu := _text(_router.handle("clear"))
	assert_string_contains(menu, "EXAM  //  question 1 of 6")
	assert_string_contains(menu, "Why is line 3 a problem?")


func test_long_artifact_scrolls_a_fifteen_line_window() -> void:
	var text := "\n".join(range(1, 31).map(func(i): return "RootLogin yes %d" % i)) + "\n"
	_start(text, {"flaws": [{"line": 20, "match": "RootLogin", "reason": "weak-auth", "explain": "x"}], "decoys": []})
	assert_string_contains(_text(_router.handle("clear")), "lines 1-15 of 30")
	var out := _text(_router.handle("go 20"))
	assert_string_contains(out, "lines 6-20 of 30")
	assert_string_contains(out, ">  20  RootLogin yes 20")
	assert_false(out.contains("RootLogin yes 5\n"))
