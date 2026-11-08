extends GutTest

const Support := preload("res://tests/unit/support.gd")
const DAY := 86400

var rules: Rules
var p: Profile
var item: Dictionary
var today: int


func before_each() -> void:
	rules = Rules.load_default()
	p = Profile.fresh("sam", Support.T0)
	item = Support.make_item("i1", "1.1.a")
	today = Mastery.day_of(Support.T0)


func _apply(credit: float, day_offset: int = 0) -> void:
	Mastery.apply(p, item, credit, Support.T0 + day_offset * DAY, rules)


func test_unseen_until_answered() -> void:
	assert_eq(Mastery.tier(p, "1.1.a"), "unseen")
	assert_eq(Mastery.box(p, "1.1.a"), 0)
	assert_false(Mastery.is_due(p, "1.1.a", today), "an unseen concept is new, not due")


func test_box_climbs_with_intervals_and_tiers() -> void:
	var expect := [
		[1, 1, "seen"], [2, 2, "known"], [3, 4, "known"], [4, 8, "mastered"], [5, 16, "mastered"], [5, 16, "mastered"]]
	for step in expect:
		_apply(1.0)
		assert_eq(Mastery.box(p, "1.1.a"), step[0], "box")
		assert_eq(Mastery.due_day(p, "1.1.a"), today + step[1], "due day for box %d" % step[0])
		assert_eq(Mastery.tier(p, "1.1.a"), step[2])


func test_miss_drops_to_box_one_due_tomorrow() -> void:
	for i in 4:
		_apply(1.0)
	_apply(0.0)
	assert_eq(Mastery.box(p, "1.1.a"), 1)
	assert_eq(Mastery.due_day(p, "1.1.a"), today + 1)
	assert_eq(Mastery.tier(p, "1.1.a"), "seen")
	assert_eq(int(Mastery.record(p, "1.1.a")["misses"]), 1)


func test_partial_credit_holds_the_box() -> void:
	_apply(1.0)
	_apply(1.0)
	_apply(1.0)
	assert_eq(Mastery.box(p, "1.1.a"), 3)
	_apply(0.5)
	assert_eq(Mastery.box(p, "1.1.a"), 3, "partial credit neither promotes nor demotes")
	assert_eq(Mastery.due_day(p, "1.1.a"), today + 1)
	assert_eq(int(Mastery.record(p, "1.1.a")["misses"]), 1)


func test_first_answer_partial_is_seen_not_unseen() -> void:
	_apply(0.5)
	assert_eq(Mastery.tier(p, "1.1.a"), "seen")


func test_is_due() -> void:
	_apply(1.0)  # due tomorrow
	assert_false(Mastery.is_due(p, "1.1.a", today))
	assert_true(Mastery.is_due(p, "1.1.a", today + 1))
	assert_true(Mastery.is_due(p, "1.1.a", today + 5))


func test_every_concept_of_an_item_is_updated() -> void:
	item["concept_ids"] = ["1.1.a", "1.1.b"]
	_apply(1.0)
	assert_eq(Mastery.box(p, "1.1.a"), 1)
	assert_eq(Mastery.box(p, "1.1.b"), 1)


func test_item_record() -> void:
	_apply(1.0)
	_apply(0.0, 1)
	var rec := Mastery.item_record(p, "i1")
	assert_eq(int(rec["seen"]), 2)
	assert_eq(int(rec["correct"]), 1)
	assert_eq(int(rec["misses"]), 1)
	assert_eq(int(rec["last_day"]), today + 1)


func test_xp_totals_and_domains() -> void:
	Mastery.add_xp(p, "4", 30)
	Mastery.add_xp(p, "4", 5)
	Mastery.add_xp(p, "1", 10)
	assert_eq(Mastery.total_xp(p), 45)
	assert_eq(Mastery.domain_xp(p, "4"), 35)
	assert_eq(Mastery.domain_xp(p, "3"), 0)


func test_best_streak_only_goes_up() -> void:
	Mastery.note_streak(p, 4)
	Mastery.note_streak(p, 2)
	assert_eq(int(p.progress()["best_streak"]), 4)


func test_mastery_survives_a_save_and_load() -> void:
	var dir := Support.make_dir()
	var store := ProfileStore.new(dir)
	var q := store.create("eve")
	Mastery.apply(q, item, 1.0, Support.T0, rules)
	Mastery.apply(q, item, 1.0, Support.T0, rules)
	Mastery.add_xp(q, "1", 25)
	store.save(q)
	var back := store.load_profile("eve")
	assert_eq(Mastery.box(back, "1.1.a"), 2)
	assert_eq(Mastery.tier(back, "1.1.a"), "known")
	assert_eq(Mastery.total_xp(back), 25)
	assert_eq(Mastery.due_day(back, "1.1.a"), today + 2)
	Support.remove_dir(dir)
