extends GutTest

const Support := preload("res://tests/unit/support.gd")
const DAY := 86400

var dir := ""
var pack: Pack
var rules: Rules
var p: Profile
var rng: RandomNumberGenerator


func before_each() -> void:
	dir = Support.make_dir()
	Support.write_wide_pack(dir)
	pack = Pack.load_dir(dir)
	rules = Rules.load_default()
	p = Profile.fresh("sam", Support.T0)
	rng = RandomNumberGenerator.new()
	rng.seed = 1


func after_each() -> void:
	Support.remove_dir(dir)


func _pick(due_scope: Array, new_scope: Array, day_offset: int = 0) -> Array:
	return Scheduler.pick(pack, p, due_scope, new_scope, rules, Support.T0 + day_offset * DAY, rng)


func _concepts(entries: Array) -> Array:
	var out: Array = entries.map(func(e): return e["concept"])
	out.sort()
	return out


## The first entry of each concept, in round order: the round with the second-item top-up removed.
func _first_of_each(entries: Array) -> Array:
	var seen: Dictionary = {}
	var out: Array = []
	for e in entries:
		if not seen.has(e["concept"]):
			seen[e["concept"]] = true
			out.append(e)
	return out


func _see(concept: String, box: int, due_offset: int) -> void:
	p.progress()["concepts"][concept] = {"box": box, "seen": 1, "hits": 1, "misses": 0,
			"last_day": 19990, "due_day": Mastery.day_of(Support.T0) + due_offset}


func test_pack_fixture_is_valid() -> void:
	assert_true(pack.ok(), "\n".join(pack.errors))
	assert_eq(pack.items.size(), 12)


func test_fresh_learner_gets_new_concepts_from_the_node() -> void:
	var entries := _first_of_each(_pick(["1.1"], ["1.1"]))
	assert_eq(_concepts(entries), ["1.1.a", "1.1.b", "1.1.c"])
	for e in entries:
		assert_eq(e["kind"], "new")


func test_one_item_per_concept_and_reviewed_first() -> void:
	for e in _first_of_each(_pick(["1.1", "1.2"], ["1.1", "1.2"])):
		assert_true(e["item"].ends_with("-1"), "%s should be the reviewed item" % e["item"])
	var seen: Dictionary = {}
	for e in _pick(["1.1", "1.2"], ["1.1", "1.2"]):
		assert_false(seen.has(e["item"]))
		seen[e["item"]] = true


func test_due_concepts_come_first_then_new() -> void:
	_see("1.2.d", 1, 0)  # due today
	var entries := _first_of_each(_pick(["1.1", "1.2"], ["1.1"]))
	var kinds: Dictionary = {}
	for e in entries:
		kinds[e["concept"]] = e["kind"]
	assert_eq(kinds["1.2.d"], "review")
	assert_eq(kinds["1.1.a"], "new")
	assert_false(kinds.has("1.2.e"), "unseen concept outside the new scope is not picked")


func test_due_review_beats_new_when_the_round_is_full() -> void:
	rules.round_size = 2
	_see("1.2.d", 1, 0)
	_see("1.2.e", 1, 0)
	var entries := _pick(["1.1", "1.2"], ["1.1"])
	assert_eq(_concepts(entries), ["1.2.d", "1.2.e"])


func test_lowest_box_is_reviewed_first() -> void:
	rules.round_size = 1
	_see("1.1.a", 4, 0)
	_see("1.1.b", 1, 0)
	_see("1.1.c", 2, 0)
	assert_eq(_pick(["1.1"], [])[0]["concept"], "1.1.b")


func test_not_yet_due_is_only_a_practice_top_up() -> void:
	_see("1.2.d", 3, 5)  # due in five days
	var entries := _pick(["1.1", "1.2"], ["1.1"])
	var by: Dictionary = {}
	for e in entries:
		by[e["concept"]] = e["kind"]
	assert_eq(by["1.2.d"], "practice")
	var none := _pick(["1.2"], [])
	assert_eq(none.size(), 1)
	assert_eq(none[0]["kind"], "practice")


func test_due_after_enough_days_pass() -> void:
	_see("1.2.d", 3, 5)
	assert_eq(_pick(["1.2"], [], 5)[0]["kind"], "review")
	assert_eq(_pick(["1.2"], [], 4)[0]["kind"], "practice")


func test_max_new_and_round_size_caps() -> void:
	rules.max_new = 2
	assert_eq(_first_of_each(_pick(["1.1"], ["1.1"])).size(), 2)
	rules.max_new = 5
	rules.round_size = 1
	assert_eq(_pick(["1.1"], ["1.1"]).size(), 1)


func test_empty_or_unserved_nodes_give_nothing() -> void:
	assert_eq(_pick(["1.3"], ["1.3"]), [])
	assert_eq(_pick([], []), [])


func test_same_seed_same_round() -> void:
	var a := _pick(["1.1", "1.2"], ["1.1", "1.2"])
	rng.seed = 1
	var b := _pick(["1.1", "1.2"], ["1.1", "1.2"])
	assert_eq(a, b)


func test_the_round_is_shuffled_not_in_pack_order() -> void:
	var orders: Dictionary = {}
	for s in range(1, 12):
		rng.seed = s
		orders[str(_pick(["1.1", "1.2"], ["1.1", "1.2"]).map(func(e): return e["concept"]))] = true
	assert_gt(orders.size(), 1, "different seeds give different orders")


func test_least_recently_served_item_rotates_in() -> void:
	var dir2 := Support.make_dir()
	Support.write_wide_pack(dir2, [
		Support.make_item("x-1", "1.1.a", "mcq", true), Support.make_item("x-2", "1.1.a", "mcq", true)])
	pack = Pack.load_dir(dir2)
	var first: String = _pick(["1.1"], ["1.1"])[0]["item"]
	Mastery.apply(p, pack.items[first], 1.0, Support.T0, rules)
	var second: String = _pick(["1.1"], [], 3)[0]["item"]
	assert_ne(first, second, "the other reviewed item is served next")
	Mastery.apply(p, pack.items[second], 1.0, Support.T0 + 3 * DAY, rules)
	assert_eq(_pick(["1.1"], [], 9)[0]["item"], first, "and then they alternate")
	Support.remove_dir(dir2)


func test_unreviewed_only_concept_still_served() -> void:
	var dir2 := Support.make_dir()
	Support.write_wide_pack(dir2, [Support.make_item("u-1", "1.1.a", "mcq", false)])
	pack = Pack.load_dir(dir2)
	assert_eq(_pick(["1.1"], ["1.1"])[0]["item"], "u-1")
	Support.remove_dir(dir2)


func test_due_concepts_helper_matches_pick() -> void:
	_see("1.2.d", 1, 0)
	_see("1.2.e", 1, 3)
	var today := Mastery.day_of(Support.T0)
	assert_eq(Scheduler.due_concepts(pack, p, ["1.2"], today), ["1.2.d"])
	assert_eq(Scheduler.due_concepts(pack, p, ["1.2"], today + 3).size(), 2)


# --- second items for a short round -----------------------------------

func _reload(items: Array, evidence: bool = false) -> void:
	Support.remove_dir(dir)
	dir = Support.make_dir()
	if evidence:
		Support.write_evidence_pack(dir, items)
	else:
		Support.write_wide_pack(dir, items)
	pack = Pack.load_dir(dir)
	assert_true(pack.ok(), "\n".join(pack.errors))


func test_a_fresh_round_is_filled_with_second_items() -> void:
	var entries := _pick(["1.1", "1.2"], ["1.1", "1.2"])
	assert_eq(_first_of_each(entries).size(), 5, "five new concepts, the cap")
	assert_eq(entries.size(), rules.round_size, "topped up to the round size")


func test_second_items_differ_come_after_every_first_and_are_practice() -> void:
	var entries := _pick(["1.1", "1.2"], ["1.1", "1.2"])
	var firsts := _first_of_each(entries)
	var last_first := -1
	for e in firsts:
		last_first = maxi(last_first, entries.find(e))
		assert_eq(e["kind"], "new")
	var by_concept: Dictionary = {}
	for i in entries.size():
		var e: Dictionary = entries[i]
		by_concept[e["concept"]] = by_concept.get(e["concept"], []) + [e]
		if not firsts.has(e):
			assert_gt(i, last_first, "a repeat never comes before every concept has been met once")
			assert_eq(e["kind"], "practice")
	for cid in by_concept:
		assert_lte(by_concept[cid].size(), 2, "at most one extra per concept")
		if by_concept[cid].size() == 2:
			assert_ne(by_concept[cid][0]["item"], by_concept[cid][1]["item"])


func test_a_concept_with_one_item_gets_no_second_question() -> void:
	_reload([Support.make_item("a-1", "1.1.a"), Support.make_item("b-1", "1.1.b"),
			Support.make_item("b-2", "1.1.b", "multi", false)])
	var entries := _pick(["1.1"], ["1.1"])
	var count: Dictionary = {}
	for e in entries:
		count[e["concept"]] = count.get(e["concept"], 0) + 1
	assert_eq(count, {"1.1.a": 1, "1.1.b": 2})


func test_a_full_round_gets_no_extras() -> void:
	rules.round_size = 3
	var entries := _pick(["1.1"], ["1.1"])
	assert_eq(entries.size(), 3)
	for e in entries:
		assert_eq(e["kind"], "new")


func test_extras_stop_at_the_round_size() -> void:
	rules.round_size = 4
	assert_eq(_pick(["1.1"], ["1.1"]).size(), 4, "three firsts and one second")


func test_only_new_concepts_are_doubled() -> void:
	_see("1.2.d", 1, 0)
	var entries := _pick(["1.2"], [])
	assert_eq(entries.size(), 1, "a review is asked once, and nothing else is new")
	_see("1.2.e", 1, 4)
	assert_eq(_pick(["1.2"], []).size(), 2, "a practice top-up is asked once")


func test_second_items_are_deterministic_for_a_seed() -> void:
	var a := _pick(["1.1", "1.2"], ["1.1", "1.2"])
	rng.seed = 1
	assert_eq(_pick(["1.1", "1.2"], ["1.1", "1.2"]), a)


func test_a_round_never_holds_a_lab_or_hunt() -> void:
	_reload([Support.make_item("a-1", "1.1.a"), Support.make_item("a-2", "1.1.a", "multi", false),
			Support.evidence_item("a-ev", "1.1.a"),
			Support.make_item("b-1", "1.1.b"), Support.make_item("b-2", "1.1.b", "multi", false)], true)
	for seed_value in 12:
		rng.seed = seed_value
		var ids: Array = _pick(["1.1"], ["1.1"]).map(func(e): return e["item"])
		assert_false(ids.has("a-ev"), "seed %d" % seed_value)
		assert_eq(ids.size(), 4, "a and b are each asked twice, with ordinary items only")


func test_a_concept_with_only_a_hunt_is_not_servable() -> void:
	_reload([Support.evidence_item("a-ev", "1.1.a"), Support.make_item("b-1", "1.1.b")], true)
	assert_false(Scheduler.servable(pack, "1.1.a"))
	assert_true(Scheduler.servable(pack, "1.1.b"))
	var ids: Array = _pick(["1.1"], ["1.1"]).map(func(e): return e["concept"])
	assert_eq(ids, ["1.1.b"])


# --- sized rounds (the home screen's quick round) --------------------------------------

func _many(per_concept: int) -> void:
	var items: Array = []
	for c in ["1.1.a", "1.1.b", "1.1.c", "1.2.d", "1.2.e", "2.1.f"]:
		for i in range(per_concept):
			items.append(Support.make_item("%s-%d" % [c, i], c, "mcq", i % 2 == 0))
	_reload(items, false)


func _sized(n: int, due_scope: Array = ["1.1", "2.1"]) -> Array:
	return Scheduler.pick(pack, p, due_scope, due_scope, rules, Support.T0, rng, n)


func test_a_sized_round_has_exactly_that_many_entries() -> void:
	_many(5)
	for n in [1, 5, 10, 17, 20]:
		assert_eq(_sized(n).size(), n, "size %d" % n)


func test_a_sized_round_never_repeats_an_item() -> void:
	_many(5)
	var seen: Dictionary = {}
	for e in _sized(20):
		assert_false(seen.has(e["item"]), e["item"])
		seen[e["item"]] = true


func test_a_sized_round_is_short_when_the_scope_runs_out() -> void:
	_many(5)  # four open concepts, five items each
	assert_eq(_sized(30).size(), 20)


func test_a_sized_round_does_not_reach_into_locked_nodes() -> void:
	_many(5)
	var concepts: Array = _sized(30).map(func(e): return e["concept"])
	assert_false(concepts.has("1.2.d") or concepts.has("1.2.e"), "node 1.2 is outside the given scope")


func _new_count(entries: Array) -> int:
	return entries.filter(func(e): return e["kind"] == "new").size()


func test_the_new_cap_scales_with_the_size() -> void:
	_many(5)
	var scope := ["1.1", "1.2", "2.1"]  # six concepts, none met
	assert_eq(rules.max_new, 5)
	assert_eq(_new_count(Scheduler.pick(pack, p, scope, scope, rules, Support.T0, rng, 6)), 5, "size 6 keeps the usual cap")
	assert_eq(_new_count(Scheduler.pick(pack, p, scope, scope, rules, Support.T0, rng, 12)), 6, "size 12 allows half the size, 6")
	assert_eq(_new_count(Scheduler.pick(pack, p, scope, scope, rules, Support.T0, rng)), 5, "no size: the rules cap")


func test_without_a_size_the_round_is_the_rules_size() -> void:
	_many(5)
	var entries := _pick(["1.1", "2.1"], ["1.1", "2.1"])
	assert_lte(entries.size(), rules.round_size)


func test_the_fill_serves_the_weakest_concepts_first() -> void:
	_many(5)
	_see("1.1.a", 4, 5)  # strong, not due
	_see("1.1.b", 1, 5)  # weak, not due
	var counts: Dictionary = {}
	var entries := Scheduler.pick(pack, p, ["1.1", "2.1"], ["1.1", "2.1"], rules, Support.T0, rng, 9)
	assert_eq(entries.size(), 9)
	for e in entries:
		counts[e["concept"]] = int(counts.get(e["concept"], 0)) + 1
	assert_eq(counts["1.1.a"], 1, "the strong concept is asked least")
	assert_eq(counts["1.1.b"], 2, "the weak one is asked more")
	assert_eq(counts["1.1.c"], 3, "new concepts are asked most")
	assert_eq(counts["2.1.f"], 3)


func test_reviews_still_come_first_in_a_sized_round() -> void:
	_many(5)
	_see("1.1.b", 1, -1)
	var entries := _sized(6)
	var reviews: Array = entries.filter(func(e): return e["kind"] == "review")
	assert_eq(reviews.size(), 1)
	assert_eq(reviews[0]["concept"], "1.1.b")


# --- skill packs: rounds may hold terminal missions ----------------------------------

func _lab_pack(include_labs: Variant) -> void:
	Support.remove_dir(dir)
	dir = Support.make_dir()
	Support.write_lab_pack(dir, [Support.make_item("a-1", "1.1.a"), Support.terminal_item("a-t", "1.1.a"),
			Support.terminal_item("b-t", "1.1.b")])
	if include_labs != null:
		var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("pack.json")))
		meta["rounds_include_labs"] = include_labs
		Support.write_json(dir.path_join("pack.json"), meta)
	pack = Pack.load_dir(dir)


func test_a_normal_pack_never_serves_a_terminal_mission_in_a_round() -> void:
	_lab_pack(null)
	assert_false(pack.rounds_include_labs)
	assert_true(Scheduler.servable(pack, "1.1.a"))
	assert_false(Scheduler.servable(pack, "1.1.b"), "a concept with only a mission has nothing to ask")
	var ids: Array = _pick(["1.1"], ["1.1"]).map(func(e): return e["item"])
	assert_false(ids.has("a-t") or ids.has("b-t"))


func test_a_skill_pack_serves_terminal_missions_in_rounds() -> void:
	_lab_pack(true)
	assert_true(pack.ok(), "\n".join(pack.errors))
	assert_true(Scheduler.servable(pack, "1.1.b"))
	var ids: Array = _sized(3, ["1.1"]).map(func(e): return e["item"])
	assert_true(ids.has("b-t"), "the only item of 1.1.b is a mission")


func test_a_skill_pack_still_keeps_hunts_out_of_rounds() -> void:
	_lab_pack(true)
	assert_true(pack.round_item(pack.items["a-t"]))
	assert_false(pack.round_item(Support.evidence_item("ev", "1.1.a")))


func test_the_exam_never_draws_a_terminal_mission_even_in_a_skill_pack() -> void:
	_lab_pack(true)
	var ids: Array = Scheduler.exam_pick(pack, p, 10, rng).map(func(e): return e["item"])
	assert_false(ids.has("a-t") or ids.has("b-t"))


func test_rounds_include_labs_must_be_true_or_false() -> void:
	_lab_pack("yes")
	assert_false(pack.ok())
	assert_string_contains("\n".join(pack.errors), "rounds_include_labs")
