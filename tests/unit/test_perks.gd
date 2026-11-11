extends GutTest
## Skill tree Phase T3 (README "Skill tree Phase T3 plan"): the perks block in
## rules.json, buying levels with Cycles, each perk's effect, and the shop and
## round-length cap through the router.

const Support := preload("res://tests/unit/support.gd")

var _dir := ""
var _rules: Rules
var _profile: Profile
var _router: CommandRouter
var _now := Support.T0
var _today := Mastery.day_of(Support.T0)


func before_each() -> void:
	_rules = Rules.load_default()
	_profile = Profile.fresh("dana", Support.T0)
	_profile.track = "wide"


func after_each() -> void:
	if _dir != "":
		Support.remove_dir(_dir)
	_dir = ""


## Put `n` Cycles in the wallet.
func _fund(n: int) -> void:
	Economy.add(_profile, n)


func _text(lines: Array) -> String:
	return "\n".join(lines.map(func(l): return l.get("t", "")))


# --- the rules block ---------------------------------------------------------------------

func test_the_shipped_perks_load_clean() -> void:
	assert_eq(_rules.errors, [])
	assert_eq(_rules.perks.map(func(p): return p["id"]),
			["round_length", "exam_time", "answer_yield", "node_output", "stale_floor", "repeat_payout"])
	assert_eq(Perks.perk(_rules, "round_length")["max_level"], 3)
	assert_eq(Perks.perk(_rules, "answer_yield")["max_level"], 10)


func test_bad_perks_are_reported_and_left_out() -> void:
	var good := {"id": "g", "title": "G", "kind": "yield", "per_level": 5, "max_level": 2, "base_cost": 10, "growth": 1.5}
	var r := Rules.new()
	r._apply({"perks": [good,
			{"id": "g", "title": "again", "kind": "yield", "per_level": 5, "max_level": 2, "base_cost": 10, "growth": 1.5},
			{"id": "k", "title": "K", "kind": "nonsense", "base_cost": 10, "growth": 2},
			{"id": "c", "title": "C", "kind": "yield", "per_level": 5, "max_level": 2, "base_cost": 0, "growth": 2},
			{"id": "w", "title": "W", "kind": "yield", "per_level": 5, "max_level": 2, "base_cost": 10, "growth": 0.5},
			{"id": "m", "title": "M", "kind": "max_questions", "base": 20, "levels": [10], "base_cost": 10, "growth": 2},
			{"id": "m2", "title": "M", "kind": "max_questions", "base": 20, "levels": [40, 300], "base_cost": 10, "growth": 2},
			"junk"]})
	assert_eq(r.perks.size(), 1)
	assert_eq(r.perks[0]["id"], "g")
	var perk_errors := r.errors.filter(func(e: String) -> bool: return e.begins_with("perks:"))
	assert_eq(perk_errors.size(), 7, str(perk_errors))


func test_a_rules_file_without_perks_changes_nothing() -> void:
	var r := Rules.new()
	r._apply({})
	assert_eq(r.perks, [])
	assert_eq(Perks.max_questions(_profile, r), Perks.HARD_MAX_QUESTIONS)
	assert_eq(Perks.exam_minutes(_profile, r, 30), 30)
	assert_eq(Perks.yield_multiplier(_profile, r), 1.0)


# --- buying --------------------------------------------------------------------------------

func test_cost_rises_by_the_growth_factor() -> void:
	assert_eq(Perks.next_cost(_profile, _rules, "round_length"), 150)
	_fund(10000)
	Perks.buy(_profile, _rules, "round_length")
	assert_eq(Perks.next_cost(_profile, _rules, "round_length"), 375)
	Perks.buy(_profile, _rules, "round_length")
	assert_eq(Perks.next_cost(_profile, _rules, "round_length"), 938)


func test_buy_takes_the_price_and_raises_the_level() -> void:
	_fund(200)
	assert_eq(Perks.buy(_profile, _rules, "round_length"), "")
	assert_eq(Perks.level(_profile, "round_length"), 1)
	assert_eq(Economy.cycles(_profile), 50.0)


func test_buy_refuses_when_short_and_takes_nothing() -> void:
	_fund(100)
	var err := Perks.buy(_profile, _rules, "round_length")
	assert_string_contains(err, "costs 150 cycles; you have 100")
	assert_eq(Perks.level(_profile, "round_length"), 0)
	assert_eq(Economy.cycles(_profile), 100.0)
	assert_false(_profile.data.has("perks"))


func test_buy_refuses_at_the_top_level_and_for_an_unknown_perk() -> void:
	_fund(100000)
	for i in range(3):
		assert_eq(Perks.buy(_profile, _rules, "exam_time"), "")
	assert_string_contains(Perks.buy(_profile, _rules, "exam_time"), "top level")
	assert_eq(Perks.next_cost(_profile, _rules, "exam_time"), -1)
	assert_string_contains(Perks.buy(_profile, _rules, "nope"), "no perk")


func test_resolve_takes_a_number_or_an_id() -> void:
	assert_eq(Perks.resolve(_rules, "2"), "exam_time")
	assert_eq(Perks.resolve(_rules, "node_output"), "node_output")
	assert_eq(Perks.resolve(_rules, "0"), "")
	assert_eq(Perks.resolve(_rules, "99"), "")
	assert_eq(Perks.resolve(_rules, "what"), "")


# --- effects --------------------------------------------------------------------------------

func _give(id: String, lvl: int) -> void:
	if typeof(_profile.data.get("perks")) != TYPE_DICTIONARY:
		_profile.data["perks"] = {}
	_profile.data["perks"][id] = lvl


func test_round_length_steps_through_its_levels() -> void:
	assert_eq(Perks.max_questions(_profile, _rules), 20)
	for pair in [[1, 40], [2, 100], [3, 200]]:
		_give("round_length", pair[0])
		assert_eq(Perks.max_questions(_profile, _rules), pair[1])


func test_exam_time_adds_ten_percent_a_level_rounded_up() -> void:
	assert_eq(Perks.exam_minutes(_profile, _rules, 30), 30)
	_give("exam_time", 1)
	assert_eq(Perks.exam_minutes(_profile, _rules, 30), 33)
	_give("exam_time", 3)
	assert_eq(Perks.exam_minutes(_profile, _rules, 30), 39)
	assert_eq(Perks.exam_minutes(_profile, _rules, 25), 33, "32.5 rounds up")
	assert_eq(Perks.exam_minutes(_profile, _rules, 0), 0, "untimed stays untimed")


func test_answer_yield_scales_what_an_answer_pays() -> void:
	assert_eq(Economy.award(_profile, "a", 10, 1.0, _today, _rules), 10)
	_give("answer_yield", 5)  # +50%
	assert_eq(Economy.award(_profile, "b", 10, 1.0, _today, _rules), 15)


func test_node_output_scales_every_node() -> void:
	for i in range(2):
		Mastery.apply(_profile, Support.make_item("x", "1.1.a"), 1.0, Support.T0, _rules)  # box 2 = 2/min
	assert_eq(Economy.node_rate(_profile, [Support.topic_of("1.1.a")], _today, _rules), 2.0)
	_give("node_output", 5)
	assert_eq(Economy.node_rate(_profile, [Support.topic_of("1.1.a")], _today, _rules), 3.0)


func test_stale_floor_raises_a_stale_nodes_share() -> void:
	for i in range(3):
		Mastery.apply(_profile, Support.make_item("x", "1.1.a"), 1.0, Support.T0, _rules)  # box 3 = 4/min, due in 4 days
	assert_eq(Economy.node_rate(_profile, [Support.topic_of("1.1.a")], _today + 4, _rules), 1.0)
	_give("stale_floor", 3)  # 25% + 30 points = 55%
	assert_almost_eq(Economy.node_rate(_profile, [Support.topic_of("1.1.a")], _today + 4, _rules), 2.2, 0.0001)


func test_repeat_payout_raises_the_same_day_share() -> void:
	Economy.award(_profile, "a", 100, 1.0, _today, _rules)
	assert_eq(Economy.award(_profile, "a", 100, 1.0, _today, _rules), 25)
	_give("repeat_payout", 3)
	assert_eq(Economy.award(_profile, "a", 100, 1.0, _today, _rules), 55)


func test_perks_never_exceed_a_whole() -> void:
	_give("stale_floor", 30)
	_give("repeat_payout", 30)
	assert_eq(Perks.stale_percent(_profile, _rules), 100)
	assert_eq(Perks.repeat_percent(_profile, _rules), 100)


func test_perks_leave_xp_and_scoring_alone() -> void:
	var item := Support.make_item("x", "1.1.a")
	var before := Scoring.xp(item, 1.0, 3, _rules)
	_give("answer_yield", 10)
	_give("node_output", 10)
	assert_eq(Scoring.xp(item, 1.0, 3, _rules), before)


# --- through the router ------------------------------------------------------------------------

func _start_router() -> void:
	_dir = Support.make_dir()
	var items: Array = []
	for c in ["1.1.a", "1.1.b", "1.1.c", "1.2.d", "1.2.e", "2.1.f"]:
		for i in range(8):
			items.append(Support.make_item("%s-%d" % [c, i], c, "mcq", i % 2 == 0))
	var root := _dir.path_join("pack")
	Support.write_wide_pack(root, items)
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("pack.json")))
	meta["exam"] = {"questions": 12, "minutes": 10, "pass_percent": 70}
	Support.write_json(root.path_join("pack.json"), meta)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	_router = CommandRouter.new(ProfileStore.new(_dir.path_join("saves")), Pack.load_dir(root), null, rng, func() -> int: return _now)
	_router.handle("new dana")


func test_the_shop_lists_every_perk_with_its_price() -> void:
	_start_router()
	var text := _text(_router.handle("perks"))
	assert_string_contains(text, "PERKS  //  0 cycles")
	assert_string_contains(text, "Longer rounds")
	assert_string_contains(text, "typed rounds up to 20 questions")
	assert_string_contains(text, "next 150 cycles")
	assert_string_contains(text, "buy <number>")


func test_the_shop_dims_what_you_cannot_afford() -> void:
	_start_router()
	Economy.add(_router.profile, 150)  # exactly Longer rounds (150), not Exam time (200)
	var rows: Array = _router.handle("perks").filter(func(l): return (l.get("t", "") as String).begins_with("  ") and (l.get("t", "") as String).contains("next "))
	assert_eq(rows[0]["s"], Lines.S_OK, "affordable")
	assert_eq(rows[1]["s"], Lines.S_DIM, "too dear")
	var cols: Array = rows.map(func(l): return (l["t"] as String).find("next "))
	assert_eq(cols.min(), cols.max(), "the price column lines up whatever the max level")


func test_buy_through_the_router_spends_saves_and_redraws() -> void:
	_start_router()
	Economy.add(_router.profile, 300)
	_router.profile.data["tree"] = {}  # any track-less state is fine
	var out := _text(_router.handle("buy 1"))
	assert_string_contains(out, "Longer rounds is now level 1.")
	assert_string_contains(out, "up to 40 questions")
	assert_eq(Economy.cycles(_router.profile), 150.0)
	var back := ProfileStore.new(_dir.path_join("saves")).load_profile("dana")
	assert_eq(Perks.level(back, "round_length"), 1)


func test_buy_errors_are_plain() -> void:
	_start_router()
	assert_string_contains(_text(_router.handle("buy")), "Type buy and a perk number")
	assert_string_contains(_text(_router.handle("buy 99")), "No such perk")
	assert_string_contains(_text(_router.handle("buy 1")), "costs 150 cycles")


func test_the_picker_offers_only_lengths_up_to_the_cap() -> void:
	_start_router()
	var text := _text(_router._setup_lines())
	assert_string_contains(text, " 5    [10]    20 ")
	assert_false(text.contains("40"))
	_set_router_perk("round_length", 2)  # cap 100
	text = _text(_router._setup_lines())
	assert_string_contains(text, "40")
	assert_string_contains(text, "100")
	assert_false(text.contains("200"))


func _set_router_perk(id: String, lvl: int) -> void:
	if typeof(_router.profile.data.get("perks")) != TYPE_DICTIONARY:
		_router.profile.data["perks"] = {}
	_router.profile.data["perks"][id] = lvl


func test_a_typed_number_over_the_cap_points_at_the_perk() -> void:
	_start_router()
	var out := _text(_router.handle("30"))
	assert_string_contains(out, "Your rounds go up to 20 questions")
	assert_string_contains(out, "type perks")
	assert_eq(_router.mode, CommandRouter.Mode.HOME, "no round started")
	_set_router_perk("round_length", 1)
	_router.handle("30")
	assert_eq(_router.mode, CommandRouter.Mode.ASK, "40 allows 30")


func test_the_exam_clock_gets_the_time_perk() -> void:
	_start_router()
	_router.handle("exam")
	assert_eq(_router.exam.minutes, 10)
	_router.handle("submit")
	_router.handle("yes")
	_set_router_perk("exam_time", 2)  # +20%
	_router.handle("exam")
	assert_eq(_router.exam.minutes, 12)


func test_perks_and_buy_are_in_the_help_lists() -> void:
	_start_router()
	assert_string_contains(_text(_router.handle("help")), "perks")
	assert_string_contains(_text(_router.handle("help all")), "perks          the shop")
