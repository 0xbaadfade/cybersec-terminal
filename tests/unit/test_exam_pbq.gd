extends GutTest
## Part 2 of the student simplification: PBQs (evidence, match, order) inside the
## full exam. Scheduler.exam_pbqs / exam_pick, ExamRun with sessions, and the
## whole thing through the router: placement, keys, scoring, mastery, the result.

const Support := preload("res://tests/unit/support.gd")

var _dir := ""
var _router: CommandRouter
var _store: ProfileStore
var _pack: Pack
var _now := Support.T0


## A 20-question full exam that asks for `pbqs` PBQs; 48 ordinary items, 3 PBQs of each type.
func _build(questions: int = 20, pbqs: int = 4, per_type: int = 3) -> void:
	_now = Support.T0
	_dir = Support.make_dir()
	var root := _dir.path_join("pack")
	Support.write_exam_pbq_pack(root, questions, pbqs, 8, per_type)
	_pack = Pack.load_dir(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	_store = ProfileStore.new(_dir.path_join("saves"))
	_router = CommandRouter.new(_store, _pack, null, rng, func() -> int: return _now)
	_router.handle("new dana")


func after_each() -> void:
	Support.remove_dir(_dir)


func _text(lines: Array) -> String:
	var out: Array = []
	for l in lines:
		out.append(l.get("t", ""))
	return "\n".join(out)


func _exam() -> ExamRun:
	return _router.exam


func _rng(seed_value: int = 7) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


func _types() -> Array:
	var out: Array = []
	for i in _exam().size():
		out.append(_exam().item_at(i)["type"])
	return out


## Solve the PBQ on screen perfectly through typed commands.
func _solve_here() -> void:
	var e := _exam()
	var s: Variant = e.session()
	match e.item_at(e.index)["type"]:
		"evidence":
			_router.handle("f 3 2")
			_router.handle("f 4 1")
			_router.handle("f 5 4")
		"match":
			for row in s.rows.size():
				_router.handle("%d %s" % [row + 1, s.letter_of(s.pair_at(row)["category"]).to_lower()])
		"order":
			for target in s.seq.size():
				var at: int = s.seq.find(target)
				_router.handle("m %d %d" % [at + 1, target + 1])


func _solve_all_pbqs() -> void:
	for i in _exam().pbq_total():
		_router.handle("goto %d" % (i + 1))
		_solve_here()


func _right() -> String:
	var e := _exam()
	return "".join(e.item_at(e.index)["answer"].map(func(id): return char(97 + e.entries[e.index]["order"].find(id))))


func _answer_ordinary_right() -> void:
	for i in range(_exam().pbq_total(), _exam().size()):
		_router.handle("goto %d" % (i + 1))
		_router.handle(_right())


func _submit() -> String:
	_router.handle("submit")
	return _text(_router.handle("yes"))


# --- Scheduler.exam_pbqs / exam_pick -------------------------------------------

func _profile() -> Profile:
	var p := Profile.fresh("dana", Support.T0)
	p.track = _pack.id
	return p


func test_four_pbqs_are_one_of_each_type_plus_a_random_one() -> void:
	_build()
	for seed_value in range(1, 21):
		var got := Scheduler.exam_pbqs(_pack, _profile(), 4, _rng(seed_value))
		assert_eq(got.size(), 4, "seed %d" % seed_value)
		var counts := {"evidence": 0, "match": 0, "order": 0}
		for e in got:
			counts[_pack.items[e["item"]]["type"]] += 1
		var values := counts.values()
		values.sort()
		assert_eq(values, [1, 1, 2], "seed %d: %s" % [seed_value, counts])


func test_the_extra_pbq_type_varies_with_the_seed() -> void:
	_build()
	var extras: Dictionary = {}
	for seed_value in range(1, 40):
		var counts := {"evidence": 0, "match": 0, "order": 0}
		for e in Scheduler.exam_pbqs(_pack, _profile(), 4, _rng(seed_value)):
			counts[_pack.items[e["item"]]["type"]] += 1
		for t in counts:
			if counts[t] == 2:
				extras[t] = true
	assert_eq(extras.size(), 3, "every type gets to be the extra one")


func test_fewer_than_three_pbqs_take_one_of_distinct_types() -> void:
	_build()
	var two := Scheduler.exam_pbqs(_pack, _profile(), 2, _rng())
	assert_eq(two.size(), 2)
	assert_ne(_pack.items[two[0]["item"]]["type"], _pack.items[two[1]["item"]]["type"])
	assert_eq(Scheduler.exam_pbqs(_pack, _profile(), 0, _rng()), [])


func test_a_pool_smaller_than_the_count_gives_fewer() -> void:
	_build(20, 4, 1)  # one PBQ of each type
	assert_eq(Scheduler.exam_pbqs(_pack, _profile(), 4, _rng()).size(), 3)
	assert_eq(Scheduler.exam_pbqs(_pack, _profile(), 9, _rng()).size(), 3)


func test_entries_carry_item_concept_and_domain() -> void:
	_build()
	for e in Scheduler.exam_pbqs(_pack, _profile(), 4, _rng()):
		var it: Dictionary = _pack.items[e["item"]]
		assert_eq(e["concept"], it["concept_ids"][0])
		assert_eq(e["domain"], _pack.domain_of_concept(e["concept"]))


func test_no_two_pbqs_share_a_concept_when_the_pool_allows() -> void:
	_build()
	for seed_value in range(1, 21):
		var seen: Dictionary = {}
		for e in Scheduler.exam_pbqs(_pack, _profile(), 4, _rng(seed_value)):
			seen[e["concept"]] = true
		assert_gte(seen.size(), 3, "seed %d" % seed_value)


func test_items_this_learner_has_not_met_come_first() -> void:
	_build()
	var p := _profile()
	for id in ["ev-0", "ev-1", "mt-0", "mt-1", "or-0", "or-1"]:
		Mastery.apply(p, _pack.items[id], 1.0, Support.T0, Rules.load_default())
	for seed_value in range(1, 11):
		for e in Scheduler.exam_pbqs(_pack, p, 3, _rng(seed_value)):
			assert_true(e["item"].ends_with("2"), "seed %d picked %s although unmet ones exist" % [seed_value, e["item"]])


func test_the_least_recently_met_comes_before_the_more_recent() -> void:
	_build()
	var p := _profile()
	var rules := Rules.load_default()
	for id in ["ev-0", "ev-1", "ev-2"]:
		Mastery.apply(p, _pack.items[id], 1.0, Support.T0 + 86400 * (id.right(1).to_int() + 1), rules)
	var first := Scheduler.exam_pbqs(_pack, p, 3, _rng()).filter(func(e): return e["item"].begins_with("ev"))
	assert_eq(first[0]["item"], "ev-0", "seen longest ago")


func test_exam_pick_with_pbqs_puts_them_first_and_still_adds_up_to_n() -> void:
	_build()
	var picked := Scheduler.exam_pick(_pack, _profile(), 20, _rng(), 4)
	assert_eq(picked.size(), 20)
	for i in 4:
		assert_true(Pack.is_exam_pbq(_pack.items[picked[i]["item"]]), "question %d is a PBQ" % (i + 1))
	for i in range(4, 20):
		assert_false(Pack.is_pbq(_pack.items[picked[i]["item"]]), "question %d is ordinary" % (i + 1))
	var seen: Dictionary = {}
	for e in picked:
		assert_false(seen.has(e["item"]), "no repeats")
		seen[e["item"]] = true


func test_pbqs_take_their_places_out_of_their_own_domains_share() -> void:
	_build()
	for seed_value in range(1, 11):
		var picked := Scheduler.exam_pick(_pack, _profile(), 20, _rng(seed_value), 4)
		var per := {"1": 0, "2": 0}
		for e in picked:
			per[e["domain"]] += 1
		assert_eq(per, {"1": 12, "2": 8}, "seed %d: the weights' share of 20 is kept, PBQs included" % seed_value)


func test_exam_pick_without_pbqs_is_what_it_was() -> void:
	_build()
	var a := Scheduler.exam_pick(_pack, _profile(), 20, _rng(3))
	var b := Scheduler.exam_pick(_pack, _profile(), 20, _rng(3), 0)
	assert_eq(a, b)
	for e in a:
		assert_false(Pack.is_pbq(_pack.items[e["item"]]))


func test_pbq_count_cannot_exceed_n() -> void:
	_build()
	var picked := Scheduler.exam_pick(_pack, _profile(), 2, _rng(), 4)
	assert_eq(picked.size(), 2)


# --- ExamRun with sessions -------------------------------------------------------

func test_an_exam_run_gives_each_pbq_a_session_and_ordinary_questions_options() -> void:
	_build()
	var picked := Scheduler.exam_pick(_pack, _profile(), 20, _rng(), 4)
	var run := ExamRun.new(_pack, picked, _rng(), Support.T0, 20)
	assert_eq(run.pbq_total(), 4)
	for i in run.size():
		assert_eq(run.is_pbq_at(i), i < 4)
		if i < 4:
			assert_eq(run.entries[i]["order"], [])
		else:
			assert_eq(run.entries[i]["order"].size(), 4)
	assert_true(run.sessions[0] is EvidenceSession or run.sessions[0] is MatchSession or run.sessions[0] is OrderSession)


func test_an_untouched_pbq_is_blank_and_scores_zero_even_an_order_question() -> void:
	_build()
	var picked := Scheduler.exam_pick(_pack, _profile(), 20, _rng(), 4)
	var run := ExamRun.new(_pack, picked, _rng(), Support.T0, 20)
	for i in 4:
		assert_false(run.answers.has(i))
		assert_eq(run.credit_at(i), 0.0)
		assert_eq(run.pbq_score(i)["credit"], 0.0)
	assert_eq(run.blank_numbers().size(), 20)


func test_pbq_command_marks_the_question_answered_and_unmarks_it_when_emptied() -> void:
	_build()
	var picked := Scheduler.exam_pick(_pack, _profile(), 20, _rng(), 4)
	var run := ExamRun.new(_pack, picked, _rng(), Support.T0, 20)
	var i := 0
	while run.item_at(i)["type"] != "match":
		i += 1
	run.goto(i + 1)
	assert_eq(run.pbq_command("a", ""), "")
	assert_true(run.answers.has(i))
	assert_eq(run.letters_at(i), "pbq")
	assert_eq(run.answered_count(), 1)
	run.pbq_command("@up", "")
	assert_eq(run.pbq_command("x", ""), "")
	assert_false(run.answers.has(i), "clearing the only filed row makes it blank again")


# --- through the router: the full exam -------------------------------------------

func test_the_full_exam_opens_with_pbqs_and_the_rest_are_ordinary() -> void:
	_build()
	var text := _text(_router.handle("exam"))
	assert_string_contains(text, "20 questions")
	assert_string_contains(text, "Questions 1 to 4 are hands-on")
	assert_string_contains(text, "none use the command line")
	var types := _types()
	for i in 4:
		assert_true(["evidence", "match", "order"].has(types[i]))
	for i in range(4, 20):
		assert_true(["mcq", "multi"].has(types[i]))
	assert_eq(_exam().pbq_total(), 4)


func test_shorter_exams_have_no_pbqs_and_the_full_length_or_more_do() -> void:
	_build()
	_router.handle("exam 10")
	assert_eq(_exam().pbq_total(), 0)
	assert_false(_text(_router.handle("leave")).contains("hands-on"))
	_router.handle("yes")
	_router.handle("exam 19")
	assert_eq(_exam().pbq_total(), 0)
	_router.handle("leave")
	_router.handle("yes")
	_router.handle("exam 20")
	assert_eq(_exam().pbq_total(), 4)
	_router.handle("leave")
	_router.handle("yes")
	_router.handle("exam 30")
	assert_eq(_exam().pbq_total(), 4)
	assert_eq(_exam().size(), 30)


func test_a_pack_that_sets_no_pbqs_has_none_even_in_a_full_exam() -> void:
	_build(20, 0)
	_router.handle("exam")
	assert_eq(_exam().pbq_total(), 0)
	assert_eq(_exam().size(), 20)


func test_the_picker_row_and_a_typed_full_length_start_the_pbq_exam() -> void:
	_build()
	_router.handle("@right")  # 10 to 20
	var screen := _text(_router.handle("@right"))
	assert_string_contains(screen, "Full exam (20)")
	assert_string_contains(screen, "It includes 4 hands-on questions (flag lines, match, put in order). None of them use the command line.")
	_router.handle("")
	assert_eq(_router.mode, CommandRouter.Mode.EXAM)
	assert_eq(_exam().pbq_total(), 4)
	_router.handle("leave")
	_router.handle("yes")
	_router.handle("f")  # feedback only at the end
	_router.handle("20")
	assert_eq(_exam().pbq_total(), 4, "a typed full length is the full exam")


func test_the_other_picker_rows_do_not_mention_hands_on_questions() -> void:
	_build()
	assert_false(_text(_router.handle("@left")).contains("hands-on"))


func test_the_exam_screen_names_the_pbq_kind_and_never_the_concept() -> void:
	_build()
	_router.handle("exam")
	var text := _text(_router.handle("goto 1"))
	assert_string_contains(text, "EXAM  //  question 1 of 20")
	assert_string_contains(text, "PBQ: ")
	assert_false(text.contains("1.1."), "an exam never names the concept")


func test_status_bar_and_prompt_in_a_pbq() -> void:
	_build()
	_router.handle("exam")
	assert_eq(_router.prompt(), "exam>")
	assert_true(_router.pbq_active())
	assert_string_contains(_router.status_line(), "EXAM 0/20 answered")
	_router.handle("goto 20")
	assert_false(_router.pbq_active())


func _go_to_type(t: String) -> void:
	for i in _exam().size():
		if _exam().item_at(i)["type"] == t:
			_router.handle("goto %d" % (i + 1))
			return
	fail_test("no %s question in this exam" % t)


# --- evidence in the exam -----------------------------------------------------------

func test_evidence_enter_flags_the_cursor_line_and_a_digit_picks_the_reason() -> void:
	_build()
	_router.handle("exam")
	_go_to_type("evidence")
	_router.handle("@down")
	_router.handle("@down")
	var menu := _text(_router.handle(""))
	assert_string_contains(menu, "Why is line 3 a problem?")
	assert_eq(_router.prompt(), "why?>")
	assert_eq(_router.single_key_choices(), 5)
	var after := _text(_router.handle("2"))
	assert_string_contains(after, "RootLogin yes")
	assert_string_contains(after, "[excess privilege]")
	assert_eq(_router.prompt(), "exam>")
	assert_eq(_router.single_key_choices(), 0)
	assert_eq(_exam().answered_count(), 1)


func test_evidence_f_x_go_and_esc_work_and_bad_input_is_explained() -> void:
	_build()
	_router.handle("exam")
	_go_to_type("evidence")
	_router.handle("f 4 1")
	assert_eq(_exam().session().flags, {4: "weak-auth"})
	assert_string_contains(_text(_router.handle("f 99")), "Line 99 is not in the file")
	_router.handle("f 2")
	assert_eq(_router.prompt(), "why?>")
	assert_string_contains(_text(_router.handle("9")), "Pick 1-5")
	_router.handle("@esc")
	assert_eq(_router.prompt(), "exam>")
	assert_false(_exam().session().flags.has(2))
	_router.handle("x 4")
	assert_eq(_exam().answered_count(), 0, "no flags: blank again")
	assert_string_contains(_text(_router.handle("go 5")), ">   5")


func test_flag_means_the_exams_review_flag_not_a_line_flag() -> void:
	_build()
	_router.handle("exam")
	_go_to_type("evidence")
	var text := _text(_router.handle("flag"))
	assert_string_contains(text, "FLAGGED")
	assert_true(_exam().session().flags.is_empty())
	assert_true(_exam().flags.has(_exam().index))


func test_with_the_reason_menu_open_next_is_refused_but_list_and_submit_still_work() -> void:
	_build()
	_router.handle("exam")
	_go_to_type("evidence")
	var at := _exam().index
	_router.handle("")
	assert_string_contains(_text(_router.handle("next")), "Pick 1-5")
	assert_eq(_exam().index, at)
	assert_string_contains(_text(_router.handle("list")), "question list")
	assert_string_contains(_text(_router.handle("submit")), "Submit now?")


# --- match in the exam ---------------------------------------------------------------

func test_match_a_bare_letter_files_the_row_and_the_view_may_send_it() -> void:
	_build()
	_router.handle("exam")
	_go_to_type("match")
	assert_eq(_router.single_key_choices(), 3)
	var s: MatchSession = _exam().session()
	var text := _text(_router.handle("b"))
	assert_string_contains(text, "[B]")
	assert_eq(s.filed_at(0), "y")
	assert_eq(s.cursor, 1)
	assert_string_contains(text, "1 of 4 filed")
	_router.handle("@down")
	_router.handle("")
	assert_eq(s.filed_at(2), "x", "Enter cycles to A")
	_router.handle("2 c")
	assert_eq(s.filed_at(1), "z")
	assert_string_contains(_text(_router.handle("q")), "A-C (or 1-3)")


# --- order in the exam ----------------------------------------------------------------

func test_order_lift_carry_set_down_and_move() -> void:
	_build()
	_router.handle("exam")
	_go_to_type("order")
	assert_eq(_router.single_key_choices(), 0)
	var s: OrderSession = _exam().session()
	var first: int = s.seq[0]
	var lifted := _text(_router.handle(""))
	assert_string_contains(lifted, "Step lifted")
	_router.handle("@down")
	assert_eq(s.seq[1], first)
	var down := _text(_router.handle(""))
	assert_false(down.contains("Step lifted"))
	assert_eq(_exam().answered_count(), 1)
	_router.handle("m 4 1")
	assert_eq(s.cursor, 0)
	assert_string_contains(_text(_router.handle("m 9 9")), "Usage: m")


# --- moving between questions ---------------------------------------------------------

func test_next_prev_goto_and_left_right_move_between_questions_from_a_pbq() -> void:
	_build()
	_router.handle("exam")
	assert_eq(_exam().index, 0)
	_router.handle("next")
	assert_eq(_exam().index, 1)
	_router.handle("@right")
	assert_eq(_exam().index, 2)
	_router.handle("@left")
	assert_eq(_exam().index, 1)
	_router.handle("prev")
	assert_eq(_exam().index, 0)
	assert_string_contains(_text(_router.handle("@left")), "first question")
	_router.handle("goto 7")
	assert_eq(_exam().index, 6)
	assert_eq(_router.handle("").size() > 0, true, "Enter on an ordinary question still moves on")
	assert_eq(_exam().index, 7)
	_router.handle("goto 20")
	assert_string_contains(_text(_router.handle("@right")), "last question")


func test_a_blank_enter_on_a_pbq_does_not_move_on() -> void:
	_build()
	_router.handle("exam")
	_go_to_type("match")
	var at := _exam().index
	_router.handle("")
	assert_eq(_exam().index, at)


func test_help_on_a_pbq_explains_its_keys_and_the_exam_words() -> void:
	_build()
	_router.handle("exam")
	_go_to_type("match")
	var text := _text(_router.handle("help"))
	assert_string_contains(text, "category letter")
	assert_string_contains(text, "submit ends the exam")
	_go_to_type("order")
	assert_string_contains(_text(_router.handle("help")), "Enter lifts it")
	_go_to_type("evidence")
	assert_string_contains(_text(_router.handle("help")), "flags the line")


func test_the_list_grid_shows_pbq_for_a_touched_pbq() -> void:
	_build()
	_router.handle("exam")
	_go_to_type("match")
	_router.handle("a")
	var text := _text(_router.handle("list"))
	assert_string_contains(text, "PBQ")
	assert_string_contains(text, "1 answered, 19 blank")


# --- submitting -------------------------------------------------------------------------

func test_a_perfect_exam_scores_one_hundred_percent_with_every_pbq_in_full() -> void:
	_build()
	_router.handle("exam")
	_solve_all_pbqs()
	_answer_ordinary_right()
	for i in 4:
		assert_eq(_exam().credit_at(i), 1.0, "PBQ %d" % (i + 1))
	var text := _submit()
	assert_string_contains(text, "Credit earned: 100%")
	assert_string_contains(text, "Hands-on questions: 4 asked, credit 100%.")
	assert_string_contains(text, "Hands-on questions: what each one was after")
	assert_string_contains(text, "100%")
	assert_false(text.contains("WRONG"))
	assert_eq(_router.mode, CommandRouter.Mode.HOME)


func test_untouched_pbqs_are_missed_and_the_review_teaches_them() -> void:
	_build()
	_router.handle("exam")
	_answer_ordinary_right()
	var run := _exam()
	var kinds := _types().slice(0, 4)
	var text := _submit()
	assert_string_contains(text, "Hands-on questions: 4 asked, credit 0%.")
	assert_string_contains(text, "(not attempted)")
	if kinds.has("evidence"):
		assert_string_contains(text, "MISSED  line 3  RootLogin yes")
		assert_string_contains(text, "Root login is excess privilege.")
	if kinds.has("match"):
		assert_string_contains(text, "WRONG   Case one")
		assert_string_contains(text, "you: (left blank)   right: Xray")
	if kinds.has("order"):
		assert_string_contains(text, "The right order")
		assert_string_contains(text, "(not placed)")
	assert_string_contains(text, "Overall lesson of")
	assert_eq(run.pbq_total(), 4)


func test_a_partly_right_match_and_a_swapped_order_show_what_was_wrong() -> void:
	_build()
	_router.handle("exam")
	_go_to_type("match")
	var s: MatchSession = _exam().session()
	for row in s.rows.size():
		var cat: String = s.pair_at(row)["category"]
		var put: String = cat if row > 0 else ("z" if cat != "z" else "x")
		_router.handle("%d %s" % [row + 1, s.letter_of(put).to_lower()])
	var wrong_text: String = s.pair_at(0)["text"]
	var mi := _exam().index
	assert_almost_eq(_exam().credit_at(mi), 0.75, 0.0001)
	_go_to_type("order")
	var o: OrderSession = _exam().session()
	_router.handle("m 1 1")
	for target in o.seq.size():
		_router.handle("m %d %d" % [o.seq.find(target) + 1, target + 1])
	_router.handle("m 1 2")
	var oi := _exam().index
	assert_almost_eq(_exam().credit_at(oi), 4.0 / 6.0, 0.0001)
	var text := _submit()
	assert_string_contains(text, wrong_text)
	assert_string_contains(text, "(you put it 2nd)")


func test_mastery_is_applied_once_to_every_pbq_concept_and_the_log_counts_them() -> void:
	_build()
	_router.handle("exam")
	_solve_all_pbqs()
	var ids: Array = []
	for i in 4:
		ids.append(_exam().item_at(i)["id"])
	_submit()
	var again := _store.load_profile("dana")
	again.track = _router.profile.track
	for id in ids:
		assert_eq(int(Mastery.item_record(again, id).get("seen", 0)), 1, id)
		assert_eq(int(Mastery.item_record(again, id).get("correct", 0)), 1, id)
	var rounds := again.rounds()
	assert_eq(rounds.size(), 1)
	assert_eq(rounds[0]["node"], "exam")
	assert_eq(int(rounds[0]["pbqs"]), 4)
	assert_eq(int(rounds[0]["answered"]), 4)
	assert_eq(Mastery.total_xp(again), 0, "an exam gives no XP, PBQs included")


func test_a_botched_pbq_comes_back_for_review_tomorrow() -> void:
	_build()
	_router.handle("exam")
	_go_to_type("match")
	var cid: String = _exam().entries[_exam().index]["concept"]
	var s: MatchSession = _exam().session()
	for row in s.rows.size():
		var cat: String = s.pair_at(row)["category"]
		_router.handle("%d %s" % [row + 1, "b" if cat != "y" else "c"])
	_submit()
	var again := _store.load_profile("dana")
	again.track = _router.profile.track
	assert_eq(Mastery.box(again, Support.topic_of(cid)), 1)
	assert_true(Mastery.is_due(again, Support.topic_of(cid), Mastery.day_of(_now) + 1))


func test_leaving_the_exam_changes_nothing_even_after_pbq_work() -> void:
	_build()
	_router.handle("exam")
	_solve_all_pbqs()
	_router.handle("leave")
	_router.handle("yes")
	var again := _store.load_profile("dana")
	again.track = _router.profile.track
	assert_eq(again.rounds().size(), 0)
	assert_eq(again.progress().get("items", {}).size(), 0)


func test_the_clock_submits_pbq_work_as_it_stood() -> void:
	_build()
	_router.handle("exam")
	_solve_all_pbqs()
	_now += 21 * 60
	var text := _text(_router.tick())
	assert_string_contains(text, "TIME IS UP")
	assert_string_contains(text, "Hands-on questions: 4 asked, credit 100%.")
	var again := _store.load_profile("dana")
	again.track = _router.profile.track
	assert_eq(again.rounds()[0]["outcome"], "timeout")


func test_an_exam_with_one_touched_pbq_logs_one_answer() -> void:
	_build()
	_router.handle("exam")
	_go_to_type("match")
	_router.handle("a")
	_submit()
	var again := _store.load_profile("dana")
	again.track = _router.profile.track
	assert_eq(int(again.rounds()[0]["answered"]), 1)
