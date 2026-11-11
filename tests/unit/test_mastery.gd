extends GutTest

const Support := preload("res://tests/unit/support.gd")
const DAY := 86400
## The fixture topic of concept 1.1.a (Support.make_item tags and derives it).
const TA := "t.1-1-a"
const TB := "t.1-1-b"

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
	assert_eq(Mastery.tier(p, TA), "unseen")
	assert_eq(Mastery.box(p, TA), 0)
	assert_false(Mastery.is_due(p, TA, today), "an unseen topic is new, not due")


func test_box_climbs_with_intervals_and_tiers() -> void:
	var expect := [
		[1, 1, "seen"], [2, 2, "known"], [3, 4, "known"], [4, 8, "mastered"], [5, 16, "mastered"], [5, 16, "mastered"]]
	for step in expect:
		_apply(1.0)
		assert_eq(Mastery.box(p, TA), step[0], "box")
		assert_eq(Mastery.due_day(p, TA), today + step[1], "due day for box %d" % step[0])
		assert_eq(Mastery.tier(p, TA), step[2])


func test_miss_drops_to_box_one_due_tomorrow() -> void:
	for i in 4:
		_apply(1.0)
	_apply(0.0)
	assert_eq(Mastery.box(p, TA), 1)
	assert_eq(Mastery.due_day(p, TA), today + 1)
	assert_eq(Mastery.tier(p, TA), "seen")
	assert_eq(int(Mastery.record(p, TA)["misses"]), 1)


func test_partial_credit_holds_the_box() -> void:
	_apply(1.0)
	_apply(1.0)
	_apply(1.0)
	assert_eq(Mastery.box(p, TA), 3)
	_apply(0.5)
	assert_eq(Mastery.box(p, TA), 3, "partial credit neither promotes nor demotes")
	assert_eq(Mastery.due_day(p, TA), today + 1)
	assert_eq(int(Mastery.record(p, TA)["misses"]), 1)


func test_first_answer_partial_is_seen_not_unseen() -> void:
	_apply(0.5)
	assert_eq(Mastery.tier(p, TA), "seen")


func test_is_due() -> void:
	_apply(1.0)  # due tomorrow
	assert_false(Mastery.is_due(p, TA, today))
	assert_true(Mastery.is_due(p, TA, today + 1))
	assert_true(Mastery.is_due(p, TA, today + 5))


func test_every_topic_of_an_item_is_updated() -> void:
	item["topics"] = [TA, TB]
	_apply(1.0)
	assert_eq(Mastery.box(p, TA), 1)
	assert_eq(Mastery.box(p, TB), 1)


func test_a_concept_is_as_strong_as_its_weakest_topic() -> void:
	var both := [TA, TB]
	assert_eq(Mastery.tier_of(p, both), "unseen", "nothing seen yet")
	for i in 3:
		_apply(1.0)   # TA reaches box 3 (known); TB is never answered
	assert_eq(Mastery.tier(p, TA), "known")
	assert_eq(Mastery.tier_of(p, both), "unseen", "one unseen topic holds the concept at unseen")
	assert_eq(Mastery.seen_of(p, both), 0)
	assert_eq(Mastery.box_of(p, both), 0)
	assert_eq(Mastery.tier_of(p, [TA]), "known")
	item["topics"] = [TB]
	_apply(1.0)   # TB: box 1 (seen)
	assert_eq(Mastery.tier_of(p, both), "seen", "the lower of known and seen")
	assert_eq(Mastery.box_of(p, both), 1)
	assert_eq(Mastery.seen_of(p, both), 1, "the fewest answers of any topic")
	assert_eq(Mastery.tier_of(p, []), "unseen", "a concept with no topics has nothing to show")


func test_a_concept_is_due_when_any_topic_is_and_ranks_by_its_earliest_due_day() -> void:
	_apply(1.0)   # TA: box 1, due tomorrow
	item["topics"] = [TB]
	_apply(1.0)
	_apply(1.0, 1)   # TB: box 2, due in 2 days from day 1 = day 3
	assert_true(Mastery.is_due_of(p, [TA, TB], today + 1), "TA is due on day 1")
	assert_false(Mastery.is_due_of(p, [TB], today + 1))
	assert_eq(Mastery.due_day_of(p, [TA, TB]), today + 1)
	assert_eq(Mastery.due_day_of(p, [Support.topic_of("9.9.z")]), 0, "an unseen topic has no due day")


func test_mastery_is_the_learners_not_a_tracks() -> void:
	p.track = "one"
	_apply(1.0)
	p.track = "two"
	assert_eq(Mastery.box(p, TA), 1, "another track reads the same topic record")
	_apply(1.0)
	assert_eq(Mastery.box(p, TA), 2)
	assert_eq(int(Mastery.item_record(p, "i1")["seen"]), 2, "item answers are shared too")
	assert_false(p.has_track("one") and p.peek().has("concepts"), "no per-track concept records any more")


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
	assert_eq(Mastery.box(back, TA), 2)
	assert_eq(Mastery.tier(back, TA), "known")
	assert_eq(Mastery.total_xp(back), 25)
	assert_eq(Mastery.due_day(back, TA), today + 2)
	Support.remove_dir(dir)
