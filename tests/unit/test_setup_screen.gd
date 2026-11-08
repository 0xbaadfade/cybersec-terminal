extends GutTest
## Student simplification, Part 1: the track's home is a length picker (README
## "Student simplification plan"): Enter starts the highlighted length, a typed
## number starts that many questions, quick rounds have no Trace, `help` is short.

const Support := preload("res://tests/unit/support.gd")

var _dir := ""
var _router: CommandRouter


## Concepts a, b, c (node 1.1) and f (node 2.1) are open for a new learner; five
## items each, so 20 questions are available. `exam` adds the pack's exam block.
func _start(exam: bool = false) -> void:
	_dir = Support.make_dir()
	var items: Array = []
	for c in ["1.1.a", "1.1.b", "1.1.c", "1.2.d", "1.2.e", "2.1.f"]:
		for i in range(5):
			items.append(Support.make_item("%s-%d" % [c, i], c, "mcq", i % 2 == 0))
	Support.write_wide_pack(_dir.path_join("pack"), items)
	if exam:
		var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_dir.path_join("pack/pack.json")))
		meta["exam"] = {"questions": 12, "minutes": 10}
		Support.write_json(_dir.path_join("pack/pack.json"), meta)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	_router = CommandRouter.new(ProfileStore.new(_dir.path_join("saves")), Pack.load_dir(_dir.path_join("pack")),
			null, rng, func() -> int: return Support.T0)
	_router.handle("new dana")


func after_each() -> void:
	if _dir != "":
		Support.remove_dir(_dir)
	_dir = ""


func _text(lines: Array) -> String:
	var out: Array = []
	for l in lines:
		out.append(l.get("t", ""))
	return "\n".join(out)


func _right(round_: Round) -> String:
	return round_.letter_of(round_.item()["answer"][0])


func _wrong(round_: Round) -> String:
	for id in round_.order:
		if not round_.item()["answer"].has(id):
			return round_.letter_of(id)
	return "a"


# --- the picker ------------------------------------------------------------------

func test_arrival_shows_the_picker_with_ten_highlighted() -> void:
	_start()
	var text := _text(_router._arrival_lines(true))
	assert_string_contains(text, "How many questions?")
	assert_string_contains(text, " 5    [10]    20 ")
	assert_string_contains(text, "Enter starts.")


func test_left_and_right_move_the_highlight_and_wrap() -> void:
	_start()
	assert_string_contains(_text(_router.handle("@right")), "[20]")
	assert_string_contains(_text(_router.handle("@right")), "[5]")
	assert_string_contains(_text(_router.handle("@left")), "[20]")
	assert_string_contains(_text(_router.handle("@left")), "[10]")


func test_enter_starts_the_highlighted_length() -> void:
	_start()
	_router.handle("@left")
	var out := _router.handle("")
	assert_eq(_router.current_round.queue.size(), 5)
	assert_string_contains(_text(out), "5 questions")
	assert_eq(_router.mode, CommandRouter.Mode.ASK)


func test_the_default_is_ten_questions() -> void:
	_start()
	_router.handle("")
	assert_eq(_router.current_round.queue.size(), 10)


func test_a_typed_number_starts_exactly_that_many() -> void:
	_start()
	var out := _router.handle("7")
	assert_eq(_router.current_round.queue.size(), 7)
	assert_string_contains(_text(out), "7 questions")
	assert_string_contains(_text(out), "QUESTION 1/7")


func test_one_question_is_singular() -> void:
	_start()
	var out := _router.handle("1")
	assert_string_contains(_text(out), "1 question\n")
	assert_eq(_router.current_round.queue.size(), 1)


func test_more_than_the_pack_has_gives_a_shorter_round_and_says_so() -> void:
	_start()
	_router.profile.data["perks"] = {"round_length": 2}  # Longer rounds level 2 lifts the typed cap to 100
	var out := _router.handle("50")
	assert_eq(_router.current_round.queue.size(), 20)
	assert_string_contains(_text(out), "Only 20 are available right now, so this round is shorter than the 50 you asked for.")


func test_a_huge_number_is_refused_and_nothing_starts() -> void:
	_start()
	var out := _router.handle("500")
	assert_string_contains(_text(out), "At most 200 questions at a time.")
	assert_eq(_router.mode, CommandRouter.Mode.HOME)
	assert_null(_router.current_round)


func test_a_quick_round_asks_distinct_items() -> void:
	_start()
	_router.handle("20")
	var seen: Dictionary = {}
	for e in _router.current_round.queue:
		assert_false(seen.has(e["item"]), "no item twice: %s" % e["item"])
		seen[e["item"]] = true


# --- quick rounds have no Trace ----------------------------------------------------

func test_a_quick_round_has_no_trace_meter_or_traced_ending() -> void:
	_start()
	_router.handle("12")
	assert_false(_router.status_line().contains("TRACE"))
	for i in range(7):  # seven misses would be 140% Trace in a breach round
		var out := _router.handle(_wrong(_router.current_round))
		assert_false(_text(out).contains("TRACE"), "no Trace text after a miss")
		assert_ne(_router.current_round.outcome, "traced")
		_router.handle("")
	assert_eq(_router.current_round.trace, 0)
	assert_false(_router.status_line().contains("TRACE"))


func test_a_breach_round_still_has_trace() -> void:
	_start()
	_router.handle("breach 1.1")
	assert_string_contains(_router.status_line(), "TRACE")
	assert_string_contains(_text(_router.handle(_wrong(_router.current_round))), "TRACE")


func test_quick_rounds_say_question_and_breach_says_encounter() -> void:
	_start()
	assert_string_contains(_text(_router.handle("5")), "QUESTION 1/5")
	_router.handle("leave")
	assert_string_contains(_text(_router.handle("breach 1.1")), "ENCOUNTER 1/")


func test_a_missed_question_comes_back_so_the_round_can_run_longer() -> void:
	_start()
	_router.handle("10")
	_router.handle(_wrong(_router.current_round))
	assert_gt(_router.current_round.queue.size(), 10, "the retry is added, nothing is dropped")


# --- after a round -----------------------------------------------------------------

func test_ending_a_round_returns_to_the_picker_and_enter_plays_again() -> void:
	_start()
	_router.handle("5")
	var out := _router.handle("leave")
	var text := _text(out)
	assert_string_contains(text, "ROUND ENDED EARLY")
	assert_string_contains(text, "How many questions?")
	assert_false(text.contains("breach"), "no old command names on the result screen")
	assert_eq(_router.mode, CommandRouter.Mode.HOME)
	_router.handle("")
	assert_eq(_router.mode, CommandRouter.Mode.ASK)


func test_a_finished_round_shows_the_result_then_the_picker() -> void:
	_start()
	_router.handle("3")
	var out: Array = []
	for i in range(10):
		if _router.mode == CommandRouter.Mode.HOME:
			break
		out = _router.handle(_right(_router.current_round) if _router.mode == CommandRouter.Mode.ASK else "")
	assert_eq(_router.mode, CommandRouter.Mode.HOME)
	var text := _text(out)
	assert_string_contains(text, "ROUND COMPLETE")
	assert_string_contains(text, "3 of 3 fully correct")
	assert_string_contains(text, "How many questions?")


# --- feedback and the exam row -----------------------------------------------------

func test_without_an_exam_block_there_is_no_exam_row_and_f_says_feedback_stays() -> void:
	_start()
	var text := _text(_router._arrival_lines(true))
	assert_false(text.contains("Full exam"))
	assert_false(text.contains("Feedback:"))
	assert_string_contains(_text(_router.handle("f")), "always shows feedback")


func test_a_pack_with_an_exam_gets_a_full_exam_row() -> void:
	_start(true)
	var text := _text(_router._arrival_lines(true))
	assert_string_contains(text, "Full exam (12)")
	assert_string_contains(text, "Feedback: after each question")


func test_the_full_exam_row_starts_the_exam() -> void:
	_start(true)
	_router.handle("@right")  # 10 -> 20
	_router.handle("@right")  # 20 -> the exam row
	var out := _router.handle("")
	assert_eq(_router.mode, CommandRouter.Mode.EXAM)
	assert_eq(_router.exam.size(), 12)
	assert_string_contains(_text(out), "EXAM SIMULATION")


func test_the_exam_row_says_it_is_timed_and_has_no_feedback() -> void:
	_start(true)
	_router.handle("@right")
	var text := _text(_router.handle("@right"))
	assert_string_contains(text, "[Full exam (12)]")
	assert_string_contains(text, "timed")
	assert_false(text.contains("Feedback:"))


func test_f_switches_a_length_to_an_exam_run_with_feedback_at_the_end() -> void:
	_start(true)
	assert_string_contains(_text(_router.handle("f")), "only at the end")
	_router.handle("5")
	assert_eq(_router.mode, CommandRouter.Mode.EXAM)
	assert_eq(_router.exam.size(), 5)


func test_f_switches_back() -> void:
	_start(true)
	_router.handle("f")
	assert_string_contains(_text(_router.handle("feedback")), "after each question")
	_router.handle("5")
	assert_eq(_router.mode, CommandRouter.Mode.ASK)


func test_an_exam_result_returns_to_the_picker() -> void:
	_start(true)
	_router.handle("f")
	_router.handle("3")
	_router.handle("submit")
	var out := _router.handle("yes")
	var text := _text(out)
	assert_string_contains(text, "How many questions?")
	assert_false(text.contains("breach"))
	assert_eq(_router.mode, CommandRouter.Mode.HOME)


# --- the quiet help -----------------------------------------------------------------

func test_help_lists_only_what_a_student_needs() -> void:
	_start()
	var text := _text(_router.handle("help"))
	for word in ["map", "breach", "codex", "labs", "exam", "pack"]:
		assert_false(text.contains("  %s " % word), "short help leaves out the %s command" % word)
	for word in ["status", "menu", "logout", "quit", "help all"]:
		assert_string_contains(text, word)


func test_help_all_lists_every_command() -> void:
	_start()
	var text := _text(_router.handle("help all"))
	for word in ["map", "breach", "codex", "lab ", "exam", "pack", "status", "menu", "logout", "quit"]:
		assert_string_contains(text, word)


func test_the_hidden_commands_still_work_when_typed() -> void:
	_start()
	assert_string_contains(_text(_router.handle("map")), "MAP")
	_router.handle("esc")
	assert_string_contains(_text(_router.handle("status")), "rank")
	assert_gt(_router.handle("codex").size(), 0)
	assert_string_contains(_text(_router.handle("pack")), "Wide Pack")


func test_unknown_words_are_still_refused() -> void:
	_start()
	assert_string_contains(_text(_router.handle("frobnicate")), "Unknown command")
