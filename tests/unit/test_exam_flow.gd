extends GutTest
## Improvement plan phase 5: the `exam` command end to end through the router:
## no feedback, navigation, flags, the submit/leave confirmations, the clock,
## the result screen, and what the exam does (and does not) change in a profile.

const Support := preload("res://tests/unit/support.gd")

var _dir := ""
var _router: CommandRouter
var _store: ProfileStore
var _now := Support.T0


## 20 questions in 30 minutes; 48 items (8 per concept, alternating mcq/multi).
func _build(exam_block: Variant = {"questions": 20, "minutes": 30, "pass_score": 750, "score_range": [100, 900]}) -> void:
	_now = Support.T0
	_dir = Support.make_dir()
	var items: Array = []
	for c in ["1.1.a", "1.1.b", "1.1.c", "1.2.d", "1.2.e", "2.1.f"]:
		for k in 8:
			items.append(Support.make_item("%s-%d" % [c, k], c, "mcq" if k % 2 == 0 else "multi", true))
	var root := _dir.path_join("pack")
	Support.write_wide_pack(root, items)
	if exam_block != null:
		var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("pack.json")))
		meta["exam"] = exam_block
		Support.write_json(root.path_join("pack.json"), meta)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	_store = ProfileStore.new(_dir.path_join("saves"))
	_router = CommandRouter.new(_store, Pack.load_dir(root), null, rng, func() -> int: return _now)
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


## The letters that make the current question fully right (`wrong` = a letter set that is not).
func _right() -> String:
	var e := _exam()
	return "".join(e.item_at(e.index)["answer"].map(func(id): return char(97 + e.entries[e.index]["order"].find(id))))


func _wrong() -> String:
	var e := _exam()
	for id in e.entries[e.index]["order"]:
		if not e.item_at(e.index)["answer"].has(id):
			return char(97 + e.entries[e.index]["order"].find(id))
	return "a"


## Answer every question: `right` of them fully right, the rest wrong; then go home via submit.
func _answer_all(right: int) -> void:
	for i in _exam().size():
		_router.handle("goto %d" % (i + 1))
		_router.handle(_right() if i < right else _wrong())


func _submit() -> String:
	_router.handle("submit")
	return _text(_router.handle("yes"))


func _log() -> Array:
	var again := _store.load_profile("dana")
	again.track = _router.profile.track
	return again.rounds()


# --- starting ----------------------------------------------------------

func test_a_pack_without_an_exam_block_says_so() -> void:
	_build(null)
	assert_string_contains(_text(_router.handle("exam")), "no exam")
	assert_eq(_router.mode, CommandRouter.Mode.HOME)
	assert_string_contains(_text(_router.handle("exam 10")), "no exam")


func test_a_bad_count_is_refused() -> void:
	_build()
	for bad in ["abc", "0", "-5", "2.5"]:
		assert_string_contains(_text(_router.handle("exam " + bad)), "exam [n]")
		assert_eq(_router.mode, CommandRouter.Mode.HOME)


func test_exam_starts_with_the_packs_numbers_and_scales_the_time() -> void:
	_build()
	var text := _text(_router.handle("exam"))
	assert_eq(_router.mode, CommandRouter.Mode.EXAM)
	assert_eq(_exam().size(), 20)
	assert_eq(_exam().minutes, 30)
	assert_string_contains(text, "20 questions, 30 minutes")
	assert_string_contains(text, "question 1 of 20")
	_router.handle("yes")  # not a pending question: just a bad answer, harmless
	_router.handle("leave")
	_router.handle("yes")
	_router.handle("exam 10")
	assert_eq(_exam().minutes, 15)
	_router.handle("leave")
	_router.handle("yes")
	_router.handle("exam 7")
	assert_eq(_exam().minutes, 11, "10.5 minutes round up")


func test_a_short_pack_gives_a_shorter_exam_and_says_so() -> void:
	_build({"questions": 100, "minutes": 100, "pass_percent": 70})
	var text := _text(_router.handle("exam"))
	assert_eq(_exam().size(), 48)
	assert_string_contains(text, "only 48 usable questions")
	assert_eq(_exam().minutes, 48, "time follows the questions actually asked")


func test_the_help_lists_exam() -> void:
	_build()
	assert_string_contains(_text(_router.handle("help all")), "exam [n]")


func test_exam_starts_from_the_map_too() -> void:
	_build()
	_router.handle("map")
	_router.handle("exam 5")
	assert_eq(_router.mode, CommandRouter.Mode.EXAM)


func test_the_prompt_and_status_bar_show_the_exam_and_the_clock() -> void:
	_build()
	_router.handle("exam")
	assert_eq(_router.prompt(), "exam>")
	assert_string_contains(_router.status_line(), "EXAM 0/20 answered")
	assert_string_contains(_router.status_line(), "TIME 30:00")
	_now += 61
	assert_string_contains(_router.status_line(), "TIME 28:59")
	_router.handle(_right())
	assert_string_contains(_router.status_line(), "EXAM 1/20 answered")


# --- answering and moving ----------------------------------------------

func test_an_answer_gives_no_feedback_and_is_kept() -> void:
	_build()
	_router.handle("exam")
	var text := _text(_router.handle(_wrong()))
	for word in ["CORRECT", "INCORRECT", "Explanation of", "XP", "TRACE", "Concept:", "Correct:"]:
		assert_false(text.contains(word), word)
	assert_string_contains(text, "Your answer: ")
	assert_eq(_exam().answered_count(), 1)


func test_a_question_names_neither_its_objective_nor_its_concept() -> void:
	_build()
	var text := _text(_router.handle("exam"))
	assert_false(text.contains("Concept"))
	assert_false(text.contains("1.1"), "no objective number")


func test_a_second_answer_replaces_the_first_and_marks_the_chosen_option() -> void:
	_build()
	_router.handle("exam")
	_router.handle(_wrong())
	var text := _text(_router.handle(_right()))
	assert_eq(_exam().answered_count(), 1)
	var want := Array(_right().split(""))
	want.sort()
	assert_eq(_exam().letters_at(0), "".join(want), "the right answer replaced the wrong one")
	assert_string_contains(text, "> ")


func test_a_bad_answer_is_refused_and_costs_nothing() -> void:
	_build()
	_router.handle("exam")
	var text := _text(_router.handle("zz"))
	assert_string_contains(text, "help lists the commands")
	assert_eq(_exam().answered_count(), 0)


func test_enter_and_next_move_on_and_prev_goes_back() -> void:
	_build()
	_router.handle("exam")
	assert_string_contains(_text(_router.handle("")), "question 2 of 20")
	assert_string_contains(_text(_router.handle("next")), "question 3 of 20")
	assert_string_contains(_text(_router.handle("prev")), "question 2 of 20")
	_router.handle("prev")
	assert_string_contains(_text(_router.handle("prev")), "first question")
	assert_eq(_exam().index, 0)


func test_the_last_question_does_not_wrap() -> void:
	_build()
	_router.handle("exam")
	_router.handle("goto 20")
	assert_string_contains(_text(_router.handle("next")), "last question")
	assert_eq(_exam().index, 19)


func test_goto() -> void:
	_build()
	_router.handle("exam")
	assert_string_contains(_text(_router.handle("goto 12")), "question 12 of 20")
	assert_string_contains(_text(_router.handle("goto 99")), "no question 99")
	assert_string_contains(_text(_router.handle("goto x")), "goto N")
	assert_eq(_exam().index, 11)


func test_flag_toggles_and_list_shows_the_state() -> void:
	_build()
	_router.handle("exam")
	_router.handle(_right())
	assert_string_contains(_text(_router.handle("flag")), "FLAGGED")
	_router.handle("goto 3")
	_router.handle("flag")
	var listing := _text(_router.handle("list"))
	assert_string_contains(listing, "1 answered, 19 blank, 2 flagged")
	assert_string_contains(listing, "Flagged: 1 3")
	assert_string_contains(listing, "Blank: 2 3 4")
	assert_false(_text(_router.handle("goto 1")).is_empty())
	assert_false(_text(_router.handle("flag")).contains("FLAGGED"), "a second flag clears it")


func test_one_key_answers_only_on_a_one_answer_question() -> void:
	_build()
	_router.handle("exam")
	for i in _exam().size():
		_router.handle("goto %d" % (i + 1))
		var multi: bool = _exam().item_at(i)["type"] == "multi"
		assert_eq(_router.single_key_choices(), 0 if multi else 4, "question %d" % (i + 1))
	_router.handle("goto 1")
	_router.handle("submit")
	assert_eq(_router.single_key_choices(), 0, "nothing is a one-key answer while a yes is awaited")
	assert_eq(_router.prompt(), "confirm>")


func test_clear_redraws_the_current_question() -> void:
	_build()
	_router.handle("exam")
	_router.handle("goto 4")
	var out := _router.handle("clear")
	assert_eq(out[0], Lines.CLEAR)
	assert_string_contains(_text(out), "question 4 of 20")


# --- submit, leave, quit -----------------------------------------------

func test_submit_asks_first_and_anything_but_yes_goes_back() -> void:
	_build()
	_router.handle("exam")
	_router.handle(_right())
	var ask := _text(_router.handle("submit"))
	assert_string_contains(ask, "1 answered, 19 blank")
	assert_eq(_router.mode, CommandRouter.Mode.EXAM)
	var back := _text(_router.handle("no"))
	assert_string_contains(back, "Back to the exam")
	assert_eq(_router.mode, CommandRouter.Mode.EXAM)
	assert_eq(_router.prompt(), "exam>")
	assert_eq(_exam().answered_count(), 1)


func test_submit_twice_confirms() -> void:
	_build()
	_router.handle("exam")
	_router.handle(_right())
	_router.handle("submit")
	assert_string_contains(_text(_router.handle("submit")), "EXAM SUBMITTED")
	assert_eq(_router.mode, CommandRouter.Mode.HOME)


func test_a_perfect_exam() -> void:
	_build()
	_router.handle("exam")
	_answer_all(20)
	var text := _submit()
	assert_string_contains(text, "EXAM SUBMITTED")
	assert_string_contains(text, "20 questions: 20 answered, 0 left blank")
	assert_string_contains(text, "Credit earned: 100%   (20 of 20 fully correct)")
	assert_string_contains(text, "By domain")
	assert_false(text.contains("Concepts you missed"))
	assert_eq(_router.mode, CommandRouter.Mode.HOME)
	assert_null(_router.exam)


func test_the_result_has_a_per_domain_table_the_missed_concepts_and_the_multi_count() -> void:
	_build()
	_router.handle("exam")
	_answer_all(10)
	var text := _submit()
	assert_string_contains(text, "Credit earned: 50%")
	assert_string_contains(text, "  1  One")
	assert_string_contains(text, "  2  Two")
	assert_string_contains(text, "Concepts you missed")
	assert_string_contains(text, "1.1")  # a missed concept is listed under its objective
	assert_string_contains(text, "Multi-answer questions: ")
	assert_string_contains(text, "partial credit is counted")


func test_a_scaled_pass_mark_gets_no_verdict_and_no_invented_score() -> void:
	_build()
	_router.handle("exam")
	_answer_all(20)
	var text := _submit()
	assert_string_contains(text, "pass at 750 on a 100 to 900 scale")
	assert_string_contains(text, "not published")
	assert_string_contains(text, "cannot say whether you would pass")
	assert_false(text.contains("above it") or text.contains("below it"))


func test_a_percentage_pass_mark_is_compared() -> void:
	_build({"questions": 20, "minutes": 30, "pass_percent": 70})
	_router.handle("exam")
	_answer_all(20)
	assert_string_contains(_submit(), "Pass mark 70%: you earned 100%, above it")
	_router.handle("exam")
	_answer_all(0)
	assert_string_contains(_submit(), "below it")


func test_a_score_exactly_on_the_percentage_pass_mark_is_above_it() -> void:
	_build({"questions": 20, "minutes": 30, "pass_percent": 50})
	_router.handle("exam")
	_answer_all(10)
	assert_string_contains(_submit(), "Pass mark 50%: you earned 50%, above it")


func test_one_question_and_one_minute_are_singular() -> void:
	assert_eq(ExamScreen.plural(1, "question"), "1 question")
	assert_eq(ExamScreen.plural(0, "question"), "0 questions")
	assert_eq(ExamScreen.plural(20, "minute"), "20 minutes")
	_build({"questions": 90, "minutes": 90})
	var text := _text(_router.handle("exam 1"))
	assert_string_contains(text, "1 question, 1 minute.")
	_router.handle(_right())
	assert_string_contains(_submit(), "1 question: 1 answered, 0 left blank")


func test_clock_text() -> void:
	assert_eq(ExamScreen.clock_text(-1), "untimed")
	assert_eq(ExamScreen.clock_text(0), "0:00")
	assert_eq(ExamScreen.clock_text(59), "0:59")
	assert_eq(ExamScreen.clock_text(600), "10:00")
	assert_eq(ExamScreen.clock_text(3599), "59:59")
	assert_eq(ExamScreen.clock_text(3600), "1:00:00")
	assert_eq(ExamScreen.clock_text(5400), "1:30:00")


func test_leave_asks_and_yes_discards_without_touching_the_profile() -> void:
	_build()
	_router.handle("exam")
	_answer_all(20)
	var before := JSON.stringify(_router.profile.data)
	var ask := _text(_router.handle("leave"))
	assert_string_contains(ask, "Leave the exam?")
	assert_eq(_router.mode, CommandRouter.Mode.EXAM)
	_router.handle("yes")
	assert_eq(_router.mode, CommandRouter.Mode.HOME)
	assert_null(_router.exam)
	assert_eq(JSON.stringify(_router.profile.data), before, "nothing was applied or logged")
	assert_eq(_log().size(), 0)


func test_quit_asks_and_no_continues_but_yes_quits() -> void:
	_build()
	_router.handle("exam")
	assert_string_contains(_text(_router.handle("quit")), "Leave the exam?")
	assert_false(_router.want_quit)
	_router.handle("no")
	assert_false(_router.want_quit)
	assert_eq(_router.mode, CommandRouter.Mode.EXAM)
	_router.handle("exit")
	_router.handle("yes")
	assert_true(_router.want_quit)
	assert_null(_router.exam)


func test_quit_twice_confirms() -> void:
	_build()
	_router.handle("exam")
	_router.handle("quit")
	_router.handle("quit")
	assert_true(_router.want_quit)


# --- what the exam changes ---------------------------------------------

func test_submit_applies_mastery_for_answered_questions_only_and_gives_no_xp() -> void:
	_build()
	_router.handle("exam")
	var ids: Array = []
	for i in _exam().size():
		ids.append(_exam().entries[i]["item"])
	for i in 5:
		_router.handle("goto %d" % (i + 1))
		_router.handle(_right() if i < 3 else _wrong())
	_submit()
	var p := _router.profile
	for i in 5:
		var rec := Mastery.item_record(p, ids[i])
		assert_eq(int(rec.get("seen", 0)), 1, "question %d answered" % (i + 1))
		assert_eq(int(rec.get("correct", 0)), 1 if i < 3 else 0)
	for i in range(5, 20):
		assert_eq(int(Mastery.item_record(p, ids[i]).get("seen", 0)), 0, "blank question %d left alone" % (i + 1))
	assert_eq(Mastery.total_xp(p), 0)
	var concept: String = _router.pack.items[ids[3]]["concept_ids"][0]
	assert_gt(int(Mastery.record(p, concept)["misses"]), 0, "a miss is recorded")
	assert_true(Mastery.is_due(p, concept, Mastery.day_of(_now) + 1), "and the concept comes due tomorrow")


func test_the_attempt_is_logged_and_survives_a_save_and_load() -> void:
	_build()
	_router.handle("exam")
	_now += 600
	_answer_all(20)
	_submit()
	var log := _log()
	assert_eq(log.size(), 1)
	assert_eq(log[0]["node"], "exam")
	assert_eq(log[0]["outcome"], "complete")
	assert_eq(int(log[0]["answered"]), 20)
	assert_eq(int(log[0]["full"]), 20)
	assert_eq(int(log[0]["questions"]), 20)
	assert_eq(int(log[0]["percent"]), 100)
	assert_eq(int(log[0]["xp"]), 0)
	assert_eq(int(log[0]["seconds"]), 600)
	assert_eq(int(log[0]["at"]), Support.T0)


func test_submitting_with_no_answers_logs_nothing() -> void:
	_build()
	_router.handle("exam")
	var text := _submit()
	assert_string_contains(text, "0 answered, 20 left blank")
	assert_string_contains(text, "Credit earned: 0%")
	assert_eq(_log().size(), 0)


# --- the clock ---------------------------------------------------------

func test_input_after_the_deadline_submits_the_exam_as_it_stood() -> void:
	_build()
	_router.handle("exam")
	_router.handle(_right())
	_now += 30 * 60 + 500
	var text := _text(_router.handle(_right()))
	assert_string_contains(text, "TIME IS UP")
	assert_string_contains(text, "1 answered, 19 left blank")
	assert_eq(_router.mode, CommandRouter.Mode.HOME)
	assert_eq(_log()[0]["outcome"], "timeout")
	assert_eq(int(_log()[0]["seconds"]), 1800, "time used is capped at the limit")
	assert_eq(int(_log()[0]["answered"]), 1, "the late keystroke was not counted")


func test_tick_ends_an_idle_exam_at_the_deadline_and_not_before() -> void:
	_build()
	_router.handle("exam")
	_router.handle(_right())
	_now += 30 * 60 - 1
	assert_eq(_router.tick(), [])
	assert_eq(_router.mode, CommandRouter.Mode.EXAM)
	_now += 1
	var text := _text(_router.tick())
	assert_string_contains(text, "TIME IS UP")
	assert_eq(_router.mode, CommandRouter.Mode.HOME)
	assert_eq(_router.tick(), [], "nothing to do once it is over")


func test_the_deadline_wins_over_a_pending_confirmation() -> void:
	_build()
	_router.handle("exam")
	_router.handle(_right())
	_router.handle("leave")
	_now += 30 * 60
	assert_string_contains(_text(_router.handle("yes")), "TIME IS UP")
	assert_eq(_log().size(), 1, "the answers counted: time ran out, the learner did not leave")


func test_tick_outside_an_exam_does_nothing() -> void:
	_build()
	assert_eq(_router.tick(), [])
	_router.handle("breach 1.1")
	_now += 99999
	assert_eq(_router.tick(), [])
	assert_eq(_router.mode, CommandRouter.Mode.ASK)


func test_a_pack_with_questions_but_no_minutes_is_untimed() -> void:
	_build({"questions": 10})
	_router.handle("exam")
	assert_eq(_exam().minutes, 0)
	assert_string_contains(_router.status_line(), "TIME untimed")
	_now += 999999
	assert_eq(_router.tick(), [])
	assert_eq(_router.mode, CommandRouter.Mode.EXAM)
