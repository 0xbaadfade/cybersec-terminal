extends GutTest
## Improvement plan phase 1: digits as answers, no Enter after a fully right
## mcq/multi answer, and a bare key answering a one-answer question.

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


## Pin the queue to the given item ids (all `new`, concept taken from the id) and
## start encounter 1, with the options in the order a, b, c, d.
func _start(item_ids: Array) -> void:
	if _router.current_round != null:
		_router.handle("leave")
	_router.handle("breach 1.1")
	var r := _router.current_round
	r.queue = []
	for id in item_ids:
		var concept: String = _router.pack.items[id]["concept_ids"][0]
		r.queue.append({"item": id, "concept": concept, "kind": "new"})
	r.index = 0
	r.start_encounter()
	r.order = ["a", "b", "c", "d"]


func test_a_right_answer_goes_straight_to_the_next_question() -> void:
	_start(["1.1.a-1", "1.1.b-1", "1.1.c-1"])
	var out := _router.handle("b")
	var text := _text(out)
	assert_string_contains(text, "CORRECT")
	assert_string_contains(text, "Explanation of 1.1.a-1.", "the explanation stays on screen")
	assert_string_contains(text, "ENCOUNTER 2/3")
	assert_false(text.contains("Press Enter to continue"))
	assert_eq(_router.mode, CommandRouter.Mode.ASK)
	assert_eq(_router.current_round.index, 1)


func test_a_wrong_answer_still_waits_for_enter() -> void:
	_start(["1.1.a-1", "1.1.b-1"])
	var text := _text(_router.handle("d"))
	assert_string_contains(text, "INCORRECT")
	assert_string_contains(text, "Press Enter to continue")
	assert_eq(_router.mode, CommandRouter.Mode.FEEDBACK)
	assert_eq(_router.current_round.index, 0)


func test_a_partial_multi_waits_and_a_full_multi_goes_on() -> void:
	_start(["1.1.a-2", "1.1.b-1"])
	var partial := _text(_router.handle("a"))
	assert_string_contains(partial, "PARTIAL")
	assert_eq(_router.mode, CommandRouter.Mode.FEEDBACK)
	_router.handle("")
	_start(["1.1.a-2", "1.1.b-1"])
	var full := _text(_router.handle("a c"))
	assert_string_contains(full, "ENCOUNTER 2/2")
	assert_eq(_router.mode, CommandRouter.Mode.ASK)


func test_the_last_encounter_waits_so_the_round_summary_is_read() -> void:
	_start(["1.1.a-1"])
	var text := _text(_router.handle("b"))
	assert_string_contains(text, "Press Enter to continue")
	assert_eq(_router.mode, CommandRouter.Mode.FEEDBACK)


func test_a_digit_answers_like_its_letter() -> void:
	_start(["1.1.a-1", "1.1.b-1"])
	var text := _text(_router.handle("2"))
	assert_string_contains(text, "CORRECT")
	assert_string_contains(text, "ENCOUNTER 2/2")


func test_the_setting_off_restores_the_enter() -> void:
	_router.rules.auto_advance_correct = false
	_start(["1.1.a-1", "1.1.b-1"])
	var text := _text(_router.handle("b"))
	assert_string_contains(text, "Press Enter to continue")
	assert_eq(_router.mode, CommandRouter.Mode.FEEDBACK)
	assert_string_contains(_text(_router.handle("")), "ENCOUNTER 2/2")


func test_a_field_exercise_next_is_not_started_without_a_pause() -> void:
	var dir := _dir.path_join("ev")
	Support.write_evidence_pack(dir, [Support.make_item("t-1", "1.1.a"), Support.evidence_item("ev-1", "1.1.b")])
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var router := CommandRouter.new(ProfileStore.new(_dir.path_join("saves2")), Pack.load_dir(dir),
			null, rng, func() -> int: return Support.T0)
	router.handle("new dana")
	router.handle("breach 1.1")
	var r := router.current_round
	r.queue = [{"item": "t-1", "concept": "1.1.a", "kind": "new"}, {"item": "ev-1", "concept": "1.1.b", "kind": "new"}]
	r.index = 0
	r.start_encounter()
	r.order = ["a", "b", "c", "d"]
	var text := _text(router.handle("b"))
	assert_string_contains(text, "Press Enter to continue")
	assert_eq(router.mode, CommandRouter.Mode.FEEDBACK)


func test_single_key_choices() -> void:
	assert_eq(_router.single_key_choices(), 0, "at the prompt there is no question")
	_start(["1.1.a-1"])
	assert_eq(_router.single_key_choices(), 4)
	_start(["1.1.a-2"])
	assert_eq(_router.single_key_choices(), 0, "a multi needs several keys and an Enter")
	_router.handle("a c")
	assert_eq(_router.single_key_choices(), 0, "feedback is not a question")


func test_rules_file_setting_is_validated() -> void:
	var path := _dir.path_join("rules.json")
	Support.write_json(path, {"auto_advance_correct": "yes"})
	assert_string_contains("\n".join(Rules.load_file(path).errors), "auto_advance_correct")
	Support.write_json(path, {"auto_advance_correct": false})
	assert_false(Rules.load_file(path).auto_advance_correct)
	assert_true(Rules.load_default().auto_advance_correct)
