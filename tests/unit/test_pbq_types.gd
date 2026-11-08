extends GutTest
## The match and order item types (README "Student simplification Part 2 plan"):
## validation, the two scorers, the two sessions, the evidence session's new
## input handler, and the pack's `exam.pbqs` setting.

const Support := preload("res://tests/unit/support.gd")

var _dirs: Array = []


func after_each() -> void:
	for d in _dirs:
		Support.remove_dir(d)
	_dirs.clear()


func _pack(items: Array, exam_block: Variant = null) -> Pack:
	var root := Support.make_dir()
	_dirs.append(root)
	Support.write_wide_pack(root, items)
	if exam_block != null:
		var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("pack.json")))
		meta["exam"] = exam_block
		Support.write_json(root.path_join("pack.json"), meta)
	return Pack.load_dir(root)


func _errors(pack: Pack) -> String:
	return "\n".join(pack.errors)


func _rng(seed_value: int = 3) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


# --- validation ---------------------------------------------------------------

func test_good_match_and_order_items_load_and_are_pbqs() -> void:
	var pack := _pack([Support.match_item("m-1", "1.1.a"), Support.order_item("o-1", "1.1.b")])
	assert_true(pack.ok(), _errors(pack))
	assert_eq(pack.items.size(), 2)
	assert_true(Pack.is_pbq(pack.items["m-1"]))
	assert_true(Pack.is_exam_pbq(pack.items["o-1"]))
	assert_false(pack.round_item(pack.items["m-1"]), "a round never serves a match")
	assert_false(pack.round_item(pack.items["o-1"]), "a round never serves an order")


func test_a_terminal_mission_is_a_pbq_but_not_an_exam_pbq() -> void:
	var t := {"type": "terminal"}
	assert_true(Pack.is_pbq(t))
	assert_false(Pack.is_exam_pbq(t))


func test_match_needs_stem_and_between_two_and_five_categories_but_not_an_overall_explain() -> void:
	var item := Support.match_item("m-1", "1.1.a")
	item.erase("explain")
	assert_false(_errors(_pack([item])).contains("explain"), "the item-level explain is optional")
	item = Support.match_item("m-1", "1.1.a")
	item["categories"] = [{"id": "x", "text": "Xray"}]
	assert_string_contains(_errors(_pack([item])), "'categories' must be an array of 2 to 5")
	item["categories"] = [{"id": "a", "text": "A"}, {"id": "b", "text": "B"}, {"id": "c", "text": "C"},
			{"id": "d", "text": "D"}, {"id": "e", "text": "E"}, {"id": "f", "text": "F"}]
	assert_string_contains(_errors(_pack([item])), "'categories' must be an array of 2 to 5")


func test_match_category_and_pair_rules() -> void:
	var item := Support.match_item("m-1", "1.1.a")
	item["categories"][1]["id"] = "x"
	assert_string_contains(_errors(_pack([item])), "duplicate category id 'x'")
	item = Support.match_item("m-1", "1.1.a")
	item["pairs"][0]["category"] = "nope"
	assert_string_contains(_errors(_pack([item])), "pair 'Case one' names unknown category 'nope'")
	item = Support.match_item("m-1", "1.1.a")
	item["pairs"][1].erase("explain")
	assert_string_contains(_errors(_pack([item])), "every pair needs a string text, a category id and an explain")
	item = Support.match_item("m-1", "1.1.a")
	item["pairs"].pop_back()
	item["pairs"].pop_back()
	assert_string_contains(_errors(_pack([item])), "'pairs' must be an array of 3 to 8")
	item = Support.match_item("m-1", "1.1.a")
	item["pairs"][1]["text"] = "Case one"
	assert_string_contains(_errors(_pack([item])), "duplicate pair text 'Case one'")
	item = Support.match_item("m-1", "1.1.a")
	item["pairs"][0]["text"] = "w".repeat(81)
	assert_string_contains(_errors(_pack([item])), "is longer than 80 characters")


func test_a_category_with_no_pair_is_allowed_as_a_decoy() -> void:
	var item := Support.match_item("m-1", "1.1.a")
	item["categories"].append({"id": "w", "text": "Whiskey"})
	var pack := _pack([item])
	assert_true(pack.ok(), _errors(pack))


func test_order_rules() -> void:
	var item := Support.order_item("o-1", "1.1.a")
	item["steps"] = item["steps"].slice(0, 2)
	assert_string_contains(_errors(_pack([item])), "'steps' must be an array of 3 to 8")
	item = Support.order_item("o-1", "1.1.a")
	item["steps"][2]["text"] = "Step first"
	assert_string_contains(_errors(_pack([item])), "duplicate step text 'Step first'")
	item = Support.order_item("o-1", "1.1.a")
	item["steps"][0].erase("explain")
	assert_string_contains(_errors(_pack([item])), "every step needs a string text and an explain")
	item = Support.order_item("o-1", "1.1.a")
	item["steps"][3]["text"] = "w".repeat(81)
	assert_string_contains(_errors(_pack([item])), "is longer than 80 characters")
	item = Support.order_item("o-1", "1.1.a")
	item.erase("stem")
	assert_string_contains(_errors(_pack([item])), "'stem' must be a non-empty string")


func test_exam_pbqs_must_be_a_whole_number_in_range() -> void:
	var block := {"questions": 20, "minutes": 20, "pbqs": 4}
	assert_eq(Pack.exam_problem(block), "")
	block["pbqs"] = -1
	assert_string_contains(Pack.exam_problem(block), "'pbqs' must be a whole number from 0 to 10")
	block["pbqs"] = 11
	assert_string_contains(Pack.exam_problem(block), "'pbqs'")
	block["pbqs"] = 2.5
	assert_string_contains(Pack.exam_problem(block), "'pbqs'")
	block["pbqs"] = "four"
	assert_string_contains(Pack.exam_problem(block), "'pbqs'")


func test_exam_pbq_count_defaults_to_zero_and_warns_when_the_pack_has_too_few() -> void:
	var none := _pack([Support.good_item()])
	assert_eq(none.exam_pbq_count(), 0)
	var few := _pack([Support.match_item("m-1", "1.1.a")], {"questions": 20, "minutes": 20, "pbqs": 4})
	assert_eq(few.exam_pbq_count(), 4)
	assert_string_contains("\n".join(few.warnings), "exam asks for 4 PBQs but the pack has only 1")
	assert_eq(few.pbq_counts(), {"evidence": 0, "match": 1, "order": 0})
	assert_string_contains(few.report(), "exam PBQs: 0 evidence, 1 match, 0 order (a full exam asks for 4)")


func test_lab_only_concepts_counts_match_and_order_as_pbq_only() -> void:
	var pack := _pack([Support.match_item("m-1", "1.1.a"), Support.good_item("t-1")])
	assert_eq(pack.lab_only_concepts(), [], "a mcq on the same concept keeps it servable")
	var only := _pack([Support.match_item("m-1", "1.1.a"), Support.order_item("o-1", "1.1.b")])
	assert_eq(only.lab_only_concepts(), ["1.1.a", "1.1.b"])


# --- Matching -----------------------------------------------------------------

func test_matching_all_right_is_exactly_one() -> void:
	var item := Support.match_item("m-1", "1.1.a")
	var r := Matching.score(item, {0: "x", 1: "y", 2: "z", 3: "x"})
	assert_eq(r["credit"], 1.0)
	assert_eq(r["right"], 4)
	assert_eq(r["total"], 4)
	assert_eq(r["rows"].size(), 4)
	assert_true(r["rows"][0]["ok"])


func test_matching_partial_blank_and_wrong() -> void:
	var item := Support.match_item("m-1", "1.1.a")
	assert_eq(Matching.score(item, {0: "x", 1: "y"})["credit"], 0.5, "blank rows are wrong")
	assert_eq(Matching.score(item, {0: "y", 1: "x", 2: "x", 3: "y"})["credit"], 0.0)
	assert_eq(Matching.score(item, {})["credit"], 0.0)
	var r := Matching.score(item, {0: "x", 1: "z"})
	assert_eq(r["rows"][1]["said"], "z")
	assert_eq(r["rows"][1]["correct"], "y")
	assert_false(r["rows"][1]["ok"])
	assert_eq(r["rows"][2]["said"], "")


func test_matching_category_text() -> void:
	var item := Support.match_item("m-1", "1.1.a")
	assert_eq(Matching.category_text(item, "y"), "Yankee")
	assert_eq(Matching.category_text(item, "q"), "q")


# --- Ordering -----------------------------------------------------------------

func test_ordering_perfect_is_exactly_one() -> void:
	var item := Support.order_item("o-1", "1.1.a")
	var r := Ordering.score(item, [0, 1, 2, 3])
	assert_eq(r["credit"], 1.0)
	assert_eq(r["agree"], 6)
	assert_eq(r["pairs"], 6)
	assert_true(r["rows"][2]["ok"])


func test_ordering_one_neighbour_swap_loses_a_third_of_the_pairs_net() -> void:
	var item := Support.order_item("o-1", "1.1.a")
	var r := Ordering.score(item, [1, 0, 2, 3])
	assert_eq(r["agree"], 5)
	assert_eq(r["disagree"], 1)
	assert_almost_eq(r["credit"], 4.0 / 6.0, 0.0001)
	assert_false(r["rows"][0]["ok"])
	assert_eq(r["rows"][0]["position"], 2)
	assert_true(r["rows"][3]["ok"])


func test_ordering_five_steps_one_swap_is_point_eight() -> void:
	var item := Support.order_item("o-1", "1.1.a")
	item["steps"].append({"text": "Step fifth", "explain": "Fifth."})
	assert_almost_eq(Ordering.score(item, [0, 1, 3, 2, 4])["credit"], 0.8, 0.0001)


func test_ordering_reverse_and_worse_floor_at_zero() -> void:
	var item := Support.order_item("o-1", "1.1.a")
	assert_eq(Ordering.score(item, [3, 2, 1, 0])["credit"], 0.0)
	assert_almost_eq(Ordering.score(item, [1, 0, 3, 2])["credit"], 2.0 / 6.0, 0.0001, "4 agree, 2 disagree")
	assert_eq(Ordering.score(item, [3, 2, 0, 1])["credit"], 0.0, "net negative agreement is floored")


# --- MatchSession -------------------------------------------------------------

func _msession(seed_value: int = 3) -> MatchSession:
	return MatchSession.new(Support.match_item("m-1", "1.1.a"), _rng(seed_value))


func test_match_rows_are_a_shuffle_of_all_pairs() -> void:
	var s := _msession()
	var sorted_rows := s.rows.duplicate()
	sorted_rows.sort()
	assert_eq(sorted_rows, [0, 1, 2, 3])
	assert_false(s.has_answer())
	assert_eq(s.single_key_choices(), 3)


func test_match_a_letter_files_the_cursor_row_and_moves_down() -> void:
	var s := _msession()
	assert_eq(s.handle("b", ""), "")
	assert_eq(s.filed_at(0), "y")
	assert_eq(s.cursor, 1)
	assert_eq(s.handle("3", ""), "", "a digit is the same as a letter: 3 is C")
	assert_eq(s.filed_at(1), "z")
	assert_true(s.has_answer())
	assert_eq(s.filed_count(), 2)


func test_match_the_cursor_stops_at_the_last_row_and_arrows_clamp() -> void:
	var s := _msession()
	for k in 6:
		s.handle("@down", "")
	assert_eq(s.cursor, 3)
	s.handle("a", "")
	assert_eq(s.cursor, 3)
	for k in 6:
		s.handle("@up", "")
	assert_eq(s.cursor, 0)


func test_match_enter_cycles_through_the_categories_and_back_to_blank() -> void:
	var s := _msession()
	var seen: Array = []
	for k in 5:
		s.handle("", "")
		seen.append(s.filed_at(0))
	assert_eq(seen, ["x", "y", "z", "", "x"])
	assert_eq(s.cursor, 0, "Enter does not move the cursor")


func test_match_x_clears_the_cursor_row_or_a_named_row() -> void:
	var s := _msession()
	s.handle("a", "")
	s.handle("b", "")
	s.handle("c", "")
	assert_eq(s.filed_count(), 3)
	assert_eq(s.handle("x", "1"), "")
	assert_eq(s.filed_at(0), "")
	assert_eq(s.cursor, 0)
	assert_eq(s.handle("x", ""), "")
	assert_eq(s.filed_count(), 2, "x on an already blank row changes nothing")
	assert_ne(s.handle("x", "9"), "")
	assert_ne(s.handle("x", "two"), "")


func test_match_row_then_category_files_that_row() -> void:
	var s := _msession()
	assert_eq(s.handle("3", "b"), "")
	assert_eq(s.filed_at(2), "y")
	assert_eq(s.cursor, 2)
	assert_eq(s.handle("2", "3"), "")
	assert_eq(s.filed_at(1), "z")
	assert_ne(s.handle("9", "a"), "", "no such row")
	assert_ne(s.handle("1", "q"), "", "no such category")


func test_match_other_input_is_explained_and_changes_nothing() -> void:
	var s := _msession()
	var msg := s.handle("q", "")
	assert_string_contains(msg, "A-C (or 1-3)")
	assert_string_contains(s.handle("d", ""), "A-C", "D is not a category here")
	assert_eq(s.filed_count(), 0)


func test_match_response_scores_through_matching() -> void:
	var s := _msession()
	for row in s.rows.size():
		var right: String = s.pair_at(row)["category"]
		s.handle(str(row + 1), s.letter_of(right).to_lower())
	var r := Matching.score(s.item, s.response())
	assert_eq(r["credit"], 1.0)
	assert_eq(s.letter_of("y"), "B")
	assert_eq(s.letter_of("q"), "")


# --- OrderSession -------------------------------------------------------------

func _osession(seed_value: int = 3) -> OrderSession:
	return OrderSession.new(Support.order_item("o-1", "1.1.a"), _rng(seed_value))


func test_order_never_starts_on_the_right_order() -> void:
	for seed_value in 60:
		var s := _osession(seed_value)
		assert_ne(s.seq, [0, 1, 2, 3], "seed %d" % seed_value)
		var sorted_seq := s.seq.duplicate()
		sorted_seq.sort()
		assert_eq(sorted_seq, [0, 1, 2, 3])


func test_order_a_two_step_item_is_also_never_in_order() -> void:
	var item := Support.order_item("o-1", "1.1.a")
	item["steps"] = item["steps"].slice(0, 2)
	for seed_value in 30:
		assert_eq(OrderSession.new(item, _rng(seed_value)).seq, [1, 0])


func test_order_arrows_move_the_cursor_until_a_step_is_lifted() -> void:
	var s := _osession()
	var before := s.seq.duplicate()
	s.handle("@down", "")
	s.handle("@down", "")
	assert_eq(s.cursor, 2)
	assert_eq(s.seq, before, "moving the cursor moves nothing")
	assert_false(s.has_answer())
	s.handle("@up", "")
	s.handle("@up", "")
	s.handle("@up", "")
	assert_eq(s.cursor, 0)


func test_order_lift_carry_and_set_down() -> void:
	var s := _osession()
	var first: int = s.seq[0]
	var second: int = s.seq[1]
	assert_eq(s.handle("", ""), "")
	assert_true(s.lifted)
	s.handle("@down", "")
	assert_eq(s.cursor, 1)
	assert_eq(s.seq[1], first)
	assert_eq(s.seq[0], second)
	assert_true(s.has_answer())
	s.handle("", "")
	assert_false(s.lifted)
	s.handle("@down", "")
	assert_eq(s.seq[1], first, "set down: the step stays where it was put")
	assert_eq(s.cursor, 2)


func test_order_carrying_past_either_end_does_nothing_and_esc_sets_down() -> void:
	var s := _osession()
	s.handle("", "")
	var before := s.seq.duplicate()
	s.handle("@up", "")
	assert_eq(s.seq, before)
	assert_false(s.has_answer())
	s.handle("@esc", "")
	assert_false(s.lifted)


func test_order_m_moves_a_step_to_a_position() -> void:
	var s := _osession()
	var fourth: int = s.seq[3]
	assert_eq(s.handle("m", "4 1"), "")
	assert_eq(s.seq[0], fourth)
	assert_eq(s.cursor, 0)
	assert_true(s.has_answer())
	assert_ne(s.handle("m", "9 1"), "")
	assert_ne(s.handle("m", "1"), "")
	assert_ne(s.handle("m", "a b"), "")
	assert_ne(s.handle("zzz", ""), "")


func test_order_m_to_the_same_place_is_not_an_answer() -> void:
	var s := _osession()
	assert_eq(s.handle("m", "2 2"), "")
	assert_false(s.has_answer())


func test_order_response_scores_perfect_after_sorting_it_by_hand() -> void:
	var s := _osession()
	for target in 4:
		var at: int = s.seq.find(target)
		s.handle("m", "%d %d" % [at + 1, target + 1])
	assert_eq(s.seq, [0, 1, 2, 3])
	assert_eq(Ordering.score(s.item, s.response())["credit"], 1.0)


# --- EvidenceSession input ------------------------------------------------------

func _esession() -> EvidenceSession:
	var lines: Array = Array(Support.DEMO_ARTIFACT.split("\n"))
	lines.pop_back()
	return EvidenceSession.new(lines, Support.REASONS)


func test_evidence_enter_opens_the_menu_and_a_digit_flags() -> void:
	var s := _esession()
	s.handle("@down", "")
	s.handle("@down", "")
	assert_eq(s.cursor, 3)
	assert_eq(s.handle("", ""), "")
	assert_eq(s.pending, 3)
	assert_eq(s.single_key_choices(), 5, "the reason digits (4 reasons and the clear digit) are single keys")
	assert_eq(s.handle("2", ""), "")
	assert_eq(s.flags, {3: "excess-privilege"})
	assert_eq(s.pending, 0)
	assert_true(s.has_answer())
	assert_eq(s.single_key_choices(), 0)


func test_evidence_menu_cancel_wrong_digit_and_clear() -> void:
	var s := _esession()
	s.handle("", "")
	assert_eq(s.handle("@esc", ""), "")
	assert_eq(s.pending, 0)
	s.handle("", "")
	assert_eq(s.handle("", ""), "", "Enter at the menu cancels it")
	assert_eq(s.pending, 0)
	assert_eq(s.flags.size(), 0)
	s.handle("f", "2 1")
	assert_eq(s.flags, {2: "weak-auth"})
	s.handle("f", "2")
	assert_string_contains(s.handle("9", ""), "Pick 1-5")
	assert_eq(s.pending, 2, "the menu stays open after a bad digit")
	assert_eq(s.handle("5", ""), "", "the clear digit removes the flag")
	assert_false(s.flags.has(2))


func test_evidence_f_with_a_line_and_digit_and_bad_input() -> void:
	var s := _esession()
	assert_eq(s.handle("f", "4 3"), "")
	assert_eq(s.flags, {4: "exposure"})
	assert_string_contains(s.handle("f", "99"), "Line 99 is not in the file (1-6)")
	assert_string_contains(s.handle("f", "x"), "Usage: f")
	assert_string_contains(s.handle("f", "1 2 3"), "Usage: f")
	assert_string_contains(s.handle("f", "3 9"), "Reason 9 is not on the menu (1-5)")
	assert_eq(s.pending, 0, "a rejected digit leaves no menu open")
	assert_false(s.flags.has(3))


func test_evidence_x_go_and_unknown_input() -> void:
	var s := _esession()
	s.handle("f", "3 1")
	assert_eq(s.handle("x", "3"), "")
	assert_false(s.flags.has(3))
	assert_string_contains(s.handle("x", "3"), "Line 3 is not flagged")
	assert_string_contains(s.handle("x", "q"), "Usage: x")
	assert_eq(s.handle("go", "5"), "")
	assert_eq(s.cursor, 5)
	assert_string_contains(s.handle("go", "z"), "Usage: go")
	assert_ne(s.handle("zzz", ""), "")
