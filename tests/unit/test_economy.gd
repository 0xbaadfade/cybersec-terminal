extends GutTest
## The incremental layer, Phase 1 (README "Incremental layer plan"): nodes and
## their rates, stale decay, answer payout with the daily-repeat rule, passive
## settling with no offline gain, and the number formats.

const Support := preload("res://tests/unit/support.gd")

var _dir := ""
var _pack: Pack
var _rules: Rules
var _profile: Profile
var _today := Mastery.day_of(Support.T0)


func before_each() -> void:
	_dir = Support.make_dir()
	Support.write_wide_pack(_dir.path_join("pack"))
	_pack = Pack.load_dir(_dir.path_join("pack"))
	_rules = Rules.load_default()
	_profile = Profile.fresh("dana", Support.T0)
	_profile.track = _pack.id


func after_each() -> void:
	Support.remove_dir(_dir)


## Answer `concept` fully right `times` times at `now`.
func _learn(concept: String, times: int, now: int = Support.T0) -> void:
	for i in range(times):
		Mastery.apply(_profile, Support.make_item("x-%s" % concept, concept), 1.0, now, _rules)


# --- rules -----------------------------------------------------------------------

func test_default_rules_carry_the_economy_block() -> void:
	assert_eq(_rules.errors, [])
	assert_eq(_rules.eco_rate_by_box, [0.0, 1.0, 2.0, 4.0, 8.0, 15.0])
	assert_eq(_rules.eco_repeat_percent, 25)
	assert_eq(_rules.eco_stale_percent, 25)
	assert_eq(_rules.eco_idle_cap, 300)


func test_a_bad_economy_block_is_reported_and_keeps_defaults() -> void:
	var r := Rules.new()
	r._apply({"economy": {"rate_per_min_by_box": [1, 2], "stale_percent": 150, "idle_cap_seconds": 0}})
	assert_gt(r.errors.size(), 2)
	assert_eq(r.eco_rate_by_box.size(), 6)
	assert_eq(r.eco_stale_percent, 100)
	assert_eq(r.eco_idle_cap, 300)


# --- nodes -------------------------------------------------------------------------

func test_an_unmet_concept_has_no_node() -> void:
	assert_eq(Economy.node_rate(_profile, "1.1.a", _today, _rules), 0.0)


func test_node_rate_follows_the_box() -> void:
	_learn("1.1.a", 1)
	assert_eq(Economy.node_rate(_profile, "1.1.a", _today, _rules), 1.0)
	_learn("1.1.a", 2)  # box 3
	assert_eq(Economy.node_rate(_profile, "1.1.a", _today, _rules), 4.0)
	_learn("1.1.a", 5)  # capped at box 5
	assert_eq(Economy.node_rate(_profile, "1.1.a", _today, _rules), 15.0)


func test_a_due_concept_is_stale_and_earns_a_quarter() -> void:
	_learn("1.1.a", 3)  # box 3, next review in 4 days
	assert_eq(Economy.node_rate(_profile, "1.1.a", _today, _rules), 4.0)
	assert_eq(Economy.node_rate(_profile, "1.1.a", _today + 4, _rules), 1.0)


func test_total_rate_and_counts() -> void:
	_learn("1.1.a", 2)  # 2/min
	_learn("1.1.b", 3)  # 4/min
	_learn("2.1.f", 1)  # 1/min, will be stale tomorrow
	assert_eq(Economy.track_rate(_profile, _pack, _today, _rules), 7.0)
	assert_eq(Economy.rate(_profile, _today, _rules), 7.0)
	var c := Economy.counts(_profile, _pack.concepts.keys(), _today)
	assert_eq(c, {"online": 3, "stale": 0, "unbuilt": 3})
	var later := Economy.counts(_profile, _pack.concepts.keys(), _today + 1)
	assert_eq(later, {"online": 2, "stale": 1, "unbuilt": 3})


# --- settling ----------------------------------------------------------------------

func test_settle_pays_the_rate_for_the_elapsed_time() -> void:
	_learn("1.1.b", 3)  # 4/min
	Economy.start(_profile, Support.T0)
	var gained := Economy.settle(_profile, Support.T0 + 30, _rules)
	assert_almost_eq(gained, 2.0, 0.0001)
	assert_almost_eq(Economy.cycles(_profile), 2.0, 0.0001)
	assert_almost_eq(Economy.earned(_profile), 2.0, 0.0001)


func test_the_first_settle_only_starts_the_clock() -> void:
	_learn("1.1.b", 3)
	assert_eq(Economy.settle(_profile, Support.T0 + 60, _rules), 0.0)
	assert_almost_eq(Economy.settle(_profile, Support.T0 + 120, _rules), 4.0, 0.0001)


func test_a_gap_over_the_idle_cap_is_not_paid() -> void:
	_learn("1.1.b", 3)
	Economy.start(_profile, Support.T0)
	assert_eq(Economy.settle(_profile, Support.T0 + 301, _rules), 0.0)
	assert_eq(Economy.cycles(_profile), 0.0)
	# the clock restarted at the late settle, so the next minute is paid
	assert_almost_eq(Economy.settle(_profile, Support.T0 + 361, _rules), 4.0, 0.0001)


func test_a_clock_that_goes_backwards_pays_nothing() -> void:
	_learn("1.1.b", 3)
	Economy.start(_profile, Support.T0 + 100)
	assert_eq(Economy.settle(_profile, Support.T0, _rules), 0.0)


func test_a_profile_that_has_played_nothing_gets_no_wallet() -> void:
	var fresh := Profile.fresh("sam", Support.T0)
	Economy.start(fresh, Support.T0)
	assert_eq(Economy.settle(fresh, Support.T0 + 60, _rules), 0.0)
	assert_false(Economy.has_wallet(fresh))
	assert_false(fresh.has_track(_pack.id))


# --- one wallet for every track -----------------------------------------------------

func test_output_adds_up_every_track_played() -> void:
	_learn("1.1.b", 3)  # 4/min in track "wide"
	_profile.track = "other"
	_learn("2.1.f", 2)  # 2/min in track "other"
	_profile.track = _pack.id
	assert_eq(Economy.track_rate(_profile, _pack, _today, _rules), 4.0)
	assert_eq(Economy.rate(_profile, _today, _rules), 6.0)


func test_settle_pays_into_one_wallet_whichever_track_is_active() -> void:
	_learn("1.1.b", 3)  # 4/min
	_profile.track = ""
	Economy.start(_profile, Support.T0)
	assert_almost_eq(Economy.settle(_profile, Support.T0 + 60, _rules), 4.0, 0.0001)
	assert_almost_eq(Economy.cycles(_profile), 4.0, 0.0001)


func test_spend_takes_whole_cycles_and_refuses_when_short() -> void:
	Economy.award(_profile, "1.1.a", 100, 1.0, _today, _rules)
	assert_false(Economy.spend(_profile, 101))
	assert_eq(Economy.cycles(_profile), 100.0, "a refused spend takes nothing")
	assert_true(Economy.spend(_profile, 40))
	assert_eq(Economy.cycles(_profile), 60.0)
	assert_false(Economy.spend(_profile, -5))


# --- payout for answers ------------------------------------------------------------

func test_the_first_right_answer_of_the_day_pays_in_full() -> void:
	assert_eq(Economy.award(_profile, "1.1.a", 12, 1.0, _today, _rules), 12)
	assert_eq(Economy.cycles(_profile), 12.0)


func test_a_repeat_the_same_day_pays_a_quarter() -> void:
	Economy.award(_profile, "1.1.a", 12, 1.0, _today, _rules)
	assert_eq(Economy.award(_profile, "1.1.a", 12, 1.0, _today, _rules), 3)
	assert_eq(Economy.award(_profile, "1.1.b", 12, 1.0, _today, _rules), 12, "another concept is fresh")


func test_the_next_day_pays_in_full_again() -> void:
	Economy.award(_profile, "1.1.a", 12, 1.0, _today, _rules)
	assert_eq(Economy.award(_profile, "1.1.a", 12, 1.0, _today + 1, _rules), 12)


func test_a_miss_pays_nothing_and_partial_credit_does_not_use_up_the_day() -> void:
	assert_eq(Economy.award(_profile, "1.1.a", 0, 0.0, _today, _rules), 0)
	assert_eq(Economy.award(_profile, "1.1.a", 7, 0.5, _today, _rules), 7)
	assert_eq(Economy.award(_profile, "1.1.a", 12, 1.0, _today, _rules), 12, "partial left the day unpaid")


func test_the_active_multiplier_scales_the_payout() -> void:
	_rules.eco_active_multiplier = 2.0
	assert_eq(Economy.award(_profile, "1.1.a", 10, 1.0, _today, _rules), 20)


func test_paid_days_survive_a_save_round_trip() -> void:
	Economy.award(_profile, "1.1.a", 12, 1.0, _today, _rules)
	var back: Profile = Profile.from_dict(JSON.parse_string(JSON.stringify(_profile.data)))
	back.track = _pack.id
	assert_eq(Economy.award(back, "1.1.a", 12, 1.0, _today, _rules), 3, "the day came back as a float")


# --- text ----------------------------------------------------------------------------

func test_format_int() -> void:
	assert_eq(Economy.format_int(0), "0")
	assert_eq(Economy.format_int(999), "999")
	assert_eq(Economy.format_int(1240), "1,240")
	assert_eq(Economy.format_int(1234567), "1,234,567")


func test_format_rate() -> void:
	assert_eq(Economy.format_rate(0.0), "+0/min")
	assert_eq(Economy.format_rate(80.0), "+80/min")
	assert_eq(Economy.format_rate(1.5), "+1.5/min")
	assert_eq(Economy.format_rate(12.4), "+12/min")


func test_summary_reads_balance_and_rate() -> void:
	_learn("1.1.b", 3)
	Economy.award(_profile, "1.1.b", 1500, 1.0, _today, _rules)
	assert_eq(Economy.summary(_profile, _today, _rules), "1,500 cycles (+4/min)")
