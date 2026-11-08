extends GutTest
## Improvement plan phase 3: every finished round is written to the track's
## round log (profile progress "rounds"), capped at Profile.ROUND_LOG_MAX.

const Support := preload("res://tests/unit/support.gd")

var _dir := ""
var _router: CommandRouter
var _store: ProfileStore
var _now := Support.T0


func before_each() -> void:
	_now = Support.T0
	_dir = Support.make_dir()
	Support.write_wide_pack(_dir.path_join("pack"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	_store = ProfileStore.new(_dir.path_join("saves"))
	_router = CommandRouter.new(_store, Pack.load_dir(_dir.path_join("pack")),
			null, rng, func() -> int: return _now)
	_router.handle("new dana")


func after_each() -> void:
	Support.remove_dir(_dir)


## Start a round on `node` pinned to these items.
func _start(item_ids: Array, node: String = "1.1") -> void:
	_router.handle("breach %s" % node)
	var r := _router.current_round
	r.queue = []
	for id in item_ids:
		var concept: String = _router.pack.items[id]["concept_ids"][0]
		r.queue.append({"item": id, "concept": concept, "kind": "new"})
	r.index = 0
	r.start_encounter()


## The fully right answer for the current item (options are reshuffled at each new encounter).
func _right() -> String:
	var r := _router.current_round
	return "".join(r.item()["answer"].map(func(id): return r.letter_of(id)))


## A single wrong option (never fully right, whatever the item type).
func _wrong() -> String:
	var r := _router.current_round
	for id in r.order:
		if not r.item()["answer"].has(id):
			return r.letter_of(id)
	return "a"


func _log() -> Array:
	return _router.profile.rounds()


func test_a_completed_round_is_logged_with_its_numbers() -> void:
	_start(["1.1.a-1", "1.1.b-1"])
	_router.handle(_right())
	_now += 90
	_router.handle(_right())
	_router.handle("")  # the last question waits for Enter
	assert_null(_router.current_round)
	assert_eq(_log().size(), 1)
	var e: Dictionary = _log()[0]
	assert_eq(e["at"], Support.T0)
	assert_eq(e["node"], "1.1")
	assert_eq(e["outcome"], "complete")
	assert_eq([e["answered"], e["full"], e["best_streak"]], [2, 2, 2])
	assert_eq(e["trace_peak"], 0)
	assert_eq(e["seconds"], 90)
	assert_gt(e["xp"], 0)
	assert_eq(e["xp"], Mastery.total_xp(_router.profile), "the logged XP is the round's XP")


func test_trace_peak_is_the_highest_point_not_the_last() -> void:
	_start(["1.1.a-1", "1.1.b-1", "1.1.c-1"])
	_router.handle(_wrong())  # wrong: Trace +20, and the concept comes back later
	_router.handle("")
	var guard := 0
	while _router.current_round != null and guard < 20:  # right answers: Trace -5 each
		_router.handle("" if _router.mode == CommandRouter.Mode.FEEDBACK else _right())
		guard += 1
	var e: Dictionary = _log()[0]
	assert_eq(e["trace_peak"], 20)
	assert_eq(e["outcome"], "complete")


func test_a_traced_round_is_logged() -> void:
	_start(["1.1.a-1", "1.1.b-1", "1.1.c-1", "1.2.d-1", "1.2.e-1"])
	var guard := 0
	while _router.current_round != null and guard < 40:
		_router.handle(_wrong())
		_router.handle("")
		guard += 1
	assert_eq(_log().size(), 1)
	assert_eq(_log()[0]["outcome"], "traced")
	assert_gte(_log()[0]["trace_peak"], _router.rules.trace_limit)
	assert_eq(_log()[0]["full"], 0)


func test_a_round_left_early_is_logged() -> void:
	_start(["1.1.a-1", "1.1.b-1"])
	_router.handle(_right())
	_router.handle("leave")
	assert_eq(_log().size(), 1)
	assert_eq(_log()[0]["outcome"], "left")
	assert_eq(_log()[0]["answered"], 1)


func test_a_round_with_no_answers_is_not_logged() -> void:
	_start(["1.1.a-1"])
	_router.handle("leave")
	assert_eq(_log().size(), 0)


func test_review_rounds_log_an_empty_node_and_rounds_pile_up_in_order() -> void:
	_start(["1.1.a-1"])
	_router.handle(_right())
	_router.handle("")
	_now += 10
	_router.handle("breach")
	var r := _router.current_round
	r.queue = [{"item": "1.1.b-1", "concept": "1.1.b", "kind": "new"}]
	r.index = 0
	r.start_encounter()
	_router.handle(_right())
	_router.handle("")
	assert_eq(_log().size(), 2)
	assert_eq(_log()[0]["node"], "1.1")
	assert_eq(_log()[1]["node"], "")
	assert_eq(_log()[1]["at"], Support.T0 + 10)


func test_the_log_survives_a_save_and_load() -> void:
	_start(["1.1.a-1", "1.1.b-1"])
	_router.handle(_right())
	_router.handle(_right())
	_router.handle("")
	var again := _store.load_profile("dana")
	again.track = _router.profile.track
	var e: Dictionary = again.rounds()[0]
	assert_eq([int(e["answered"]), int(e["full"]), String(e["outcome"]), String(e["node"])], [2, 2, "complete", "1.1"])
	assert_eq(int(e["xp"]), Mastery.total_xp(again))


func test_the_log_keeps_only_the_last_hundred() -> void:
	var p := Profile.fresh("sam", Support.T0)
	for i in range(Profile.ROUND_LOG_MAX + 5):
		p.log_round({"at": i})
	assert_eq(p.rounds().size(), Profile.ROUND_LOG_MAX)
	assert_eq(p.rounds()[0]["at"], 5, "the oldest five were dropped")
	assert_eq(p.rounds()[Profile.ROUND_LOG_MAX - 1]["at"], Profile.ROUND_LOG_MAX + 4)


func test_a_profile_without_a_rounds_list_gets_one() -> void:
	var p := Profile.fresh("sam", Support.T0)
	p.progress().erase("rounds")
	assert_eq(p.rounds(), [])
	p.log_round({"at": 1})
	assert_eq(p.rounds().size(), 1)
