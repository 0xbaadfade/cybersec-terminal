extends GutTest
## Improvement plan phase 4: a miss shows what was chosen against what was right
## first, then the explanation, then the per-option why lines.

const Support := preload("res://tests/unit/support.gd")

var _dir := ""
var _router: CommandRouter


func before_each() -> void:
	_dir = Support.make_dir()
	Support.write_wide_pack(_dir.path_join("pack"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	_router = CommandRouter.new(ProfileStore.new(_dir.path_join("saves")), Pack.load_dir(_dir.path_join("pack")),
			null, rng, func() -> int: return Support.T0)
	_router.handle("new dana")


func after_each() -> void:
	Support.remove_dir(_dir)


func _text(lines: Array) -> String:
	var out: Array = []
	for l in lines:
		out.append(l.get("t", ""))
	return "\n".join(out)


func _style_of(lines: Array, prefix: String) -> String:
	for l in lines:
		if (l.get("t", "") as String).begins_with(prefix):
			return l.get("s", "")
	return "missing"


## Pin the queue to one item (answers: mcq b, multi a and c) with options in the
## order a, b, c, d, and a following item so a right answer does not end the round.
func _start(item_id: String) -> void:
	_router.handle("breach 1.1")
	var r := _router.current_round
	r.queue = []
	for id in [item_id, "1.1.b-1"]:
		r.queue.append({"item": id, "concept": _router.pack.items[id]["concept_ids"][0], "kind": "new"})
	r.index = 0
	r.start_encounter()
	r.order = ["a", "b", "c", "d"]


func test_a_wrong_mcq_shows_chose_and_correct_before_the_explanation() -> void:
	_start("1.1.a-1")
	var out := _router.handle("d")
	var text := _text(out)
	assert_string_contains(text, "You chose: D  Delta\nCorrect:   B  Bravo")
	assert_lt(text.find("Correct:   B"), text.find("Explanation of 1.1.a-1."), "comparison first")
	assert_string_contains(text, "Correct:   B  Bravo\n\nExplanation of 1.1.a-1.", "a blank line separates them")
	assert_eq(_style_of(out, "You chose:"), Lines.S_ERROR)
	assert_eq(_style_of(out, "Correct:"), Lines.S_OK)


func test_why_lines_come_after_the_explanation_and_only_where_a_pack_has_them() -> void:
	_start("1.1.a-1")
	var text := _text(_router.handle("a"))
	assert_gt(text.find("A is wrong: Alpha is wrong."), text.find("Explanation of 1.1.a-1."))
	_router.handle("")
	_router.handle("leave")
	_start("1.1.a-1")
	var bare := _text(_router.handle("d"))
	assert_false(bare.contains("is wrong"), "Delta carries no why, so no filler line")


func test_a_right_answer_keeps_the_short_form() -> void:
	_start("1.1.a-1")
	var text := _text(_router.handle("b"))
	assert_string_contains(text, "CORRECT")
	assert_string_contains(text, "Explanation of 1.1.a-1.")
	assert_false(text.contains("You chose"))
	assert_false(text.contains("Correct:"))


func test_a_partial_multi_lists_what_was_chosen_and_what_was_missed() -> void:
	_start("1.1.a-2")
	var out := _router.handle("a d")
	var text := _text(out)
	assert_string_contains(text, "You chose:\n  A  Alpha\n  D  Delta\nMissed:\n  C  Charlie")
	assert_lt(text.find("Missed:"), text.find("Explanation of 1.1.a-2."))
	assert_eq(_style_of(out, "  A  Alpha"), Lines.S_OK, "a right pick")
	assert_eq(_style_of(out, "  D  Delta"), Lines.S_ERROR, "an extra pick")
	assert_eq(_style_of(out, "  C  Charlie"), Lines.S_ACCENT, "a missed option")


func test_a_multi_with_only_an_extra_pick_has_no_missed_list() -> void:
	_start("1.1.a-2")
	var text := _text(_router.handle("a b c"))
	assert_string_contains(text, "You chose:\n  A  Alpha\n  B  Bravo\n  C  Charlie")
	assert_false(text.contains("Missed:"))


func test_a_multi_with_only_a_missed_option_has_no_wrong_pick() -> void:
	_start("1.1.a-2")
	var out := _router.handle("a")
	assert_string_contains(_text(out), "Missed:\n  C  Charlie")
	assert_eq(_style_of(out, "  A  Alpha"), Lines.S_OK)


func test_the_letters_follow_the_reshuffled_order() -> void:
	_start("1.1.a-1")
	_router.current_round.order = ["d", "c", "b", "a"]
	var text := _text(_router.handle("a"))
	assert_string_contains(text, "You chose: A  Delta\nCorrect:   C  Bravo")


func test_the_comparison_survives_a_clear() -> void:
	_start("1.1.a-1")
	_router.handle("d")
	var again := _text(_router.handle("clear"))
	assert_string_contains(again, "You chose: D  Delta\nCorrect:   B  Bravo")
	assert_string_contains(again, "Press Enter to continue")
