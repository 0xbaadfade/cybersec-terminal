extends GutTest
## The incremental layer, Phase 1, through the router: the status bar, the
## per-answer and round-end lines, the passive tick (no offline gain), saving,
## and the `grid` screen.

const Support := preload("res://tests/unit/support.gd")

var _dir := ""
var _router: CommandRouter
var _store: ProfileStore
var _t := Support.T0


func _start() -> void:
	_dir = Support.make_dir()
	var items: Array = []
	for c in ["1.1.a", "1.1.b", "1.1.c", "1.2.d", "1.2.e", "2.1.f"]:
		for i in range(5):
			items.append(Support.make_item("%s-%d" % [c, i], c, "mcq", i % 2 == 0))
	Support.write_wide_pack(_dir.path_join("pack"), items)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	_store = ProfileStore.new(_dir.path_join("saves"))
	_router = CommandRouter.new(_store, Pack.load_dir(_dir.path_join("pack")),
			null, rng, func() -> int: return _t)
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


func _right(r: Round) -> String:
	return r.letter_of(r.item()["answer"][0])


func _wrong(r: Round) -> String:
	for id in r.order:
		if not r.item()["answer"].has(id):
			return r.letter_of(id)
	return "a"


## Start an n-question round and answer every question right; returns all output.
func _play_right(n: int) -> String:
	var out: Array = _router.handle(str(n))
	while _router.current_round != null:
		out.append_array(_router.handle(_right(_router.current_round)))
		if _router.mode == CommandRouter.Mode.FEEDBACK:
			out.append_array(_router.handle(""))
	return _text(out)


func _cycles() -> float:
	return Economy.cycles(_router.profile)


# --- shown --------------------------------------------------------------------------

func test_the_arrival_line_and_status_bar_show_cycles() -> void:
	_start()
	assert_string_contains(_text(_router._arrival_lines(true)), "0 cycles (+0/min)")
	assert_string_contains(_router.status_line(), "0 cycles (+0/min)")


func test_a_right_answer_shows_the_cycles_it_paid() -> void:
	_start()
	_router.handle("5")
	var out := _text(_router.handle(_right(_router.current_round)))
	assert_string_contains(out, "+10 XP   +10 cycles")
	assert_eq(_cycles(), 10.0)
	assert_string_contains(_router.status_line(), "10 cycles")


func test_a_miss_pays_no_cycles() -> void:
	_start()
	_router.handle("5")
	var out := _text(_router.handle(_wrong(_router.current_round)))
	assert_false(out.contains("cycles"), out)
	assert_eq(_cycles(), 0.0)


func test_the_round_end_reports_cycles_and_nodes_built() -> void:
	_start()
	var text := _play_right(5)
	assert_string_contains(text, "ROUND COMPLETE")
	assert_string_contains(text, "nodes built")
	assert_string_contains(text, "(grid shows your nodes)")
	assert_gt(_cycles(), 0.0)


func test_a_stale_concept_answered_right_is_reported_brought_back_online() -> void:
	_start()
	_play_right(5)
	_t += 20 * 86400  # every concept is due again
	var text := _play_right(5)
	assert_string_contains(text, "brought back online")


# --- the tick ---------------------------------------------------------------------------

func test_nodes_pay_out_on_tick() -> void:
	_start()
	_play_right(5)
	var rate := Economy.rate(_router.profile, Mastery.day_of(_t), _router.rules)
	assert_gt(rate, 0.0)
	_router.tick()  # settle up to now
	var before := _cycles()
	_t += 60
	_router.tick()
	assert_almost_eq(_cycles() - before, rate, 0.001)


func test_time_away_is_not_paid() -> void:
	_start()
	_play_right(5)
	_router.tick()
	var before := _cycles()
	_t += 3600
	_router.tick()
	assert_eq(_cycles(), before)


func test_commands_settle_too() -> void:
	_start()
	_play_right(5)
	_router.tick()
	var before := _cycles()
	_t += 30
	_router.handle("status")
	assert_gt(_cycles(), before)


func test_passive_cycles_are_saved_after_save_every_seconds() -> void:
	_start()
	_play_right(5)
	_router.tick()
	_t += 60
	_router.tick()
	var back := _store.load_profile("dana")
	back.track = "wide"
	assert_almost_eq(Economy.cycles(back), _cycles(), 0.01)


func test_looking_at_a_track_creates_no_progress() -> void:
	_start()
	_router.handle("help")
	_router.handle("grid")
	_t += 30
	_router.tick()
	assert_false(_router.profile.has_track("wide"))


# --- grid ---------------------------------------------------------------------------------

func test_grid_overview_lists_domains() -> void:
	_start()
	_play_right(5)
	var text := _text(_router.handle("grid"))
	assert_string_contains(text, "GRID  //  WIDE")
	assert_string_contains(text, "Cycles")
	assert_string_contains(text, "online")
	assert_string_contains(text, "One")
	assert_string_contains(text, "Two")


func test_grid_domain_lists_built_nodes_and_counts_the_rest() -> void:
	_start()
	_play_right(5)
	var text := _text(_router.handle("grid 1"))
	assert_string_contains(text, "GRID  //  1  One")
	assert_string_contains(text, "online")
	assert_string_contains(text, "box 1")


func test_grid_marks_stale_nodes() -> void:
	_start()
	_play_right(5)
	_t += 20 * 86400
	assert_string_contains(_text(_router.handle("grid 1")), "STALE")


func test_grid_with_an_unknown_domain_says_so() -> void:
	_start()
	assert_string_contains(_text(_router.handle("grid 9")), "No domain '9'")


func test_grid_is_in_both_help_lists() -> void:
	_start()
	assert_string_contains(_text(_router.handle("help")), "grid")
	assert_string_contains(_text(_router.handle("help all")), "grid [domain]")
