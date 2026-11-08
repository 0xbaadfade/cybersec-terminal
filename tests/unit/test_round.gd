extends GutTest

const Support := preload("res://tests/unit/support.gd")

var dir := ""
var pack: Pack
var rules: Rules
var rng: RandomNumberGenerator


func before_each() -> void:
	dir = Support.make_dir()
	Support.write_wide_pack(dir)
	pack = Pack.load_dir(dir)
	rules = Rules.load_default()
	rng = RandomNumberGenerator.new()
	rng.seed = 3


func after_each() -> void:
	Support.remove_dir(dir)


func _entry(item_id: String, concept: String, kind: String = "new") -> Dictionary:
	return {"item": item_id, "concept": concept, "kind": kind}


## Fixed option order a,b,c,d so the answers are predictable.
func _round(entries: Array) -> Round:
	var r := Round.new(pack, rules, entries, rng)
	r.start_encounter()
	r.order = ["a", "b", "c", "d"]
	return r


func _many(n: int) -> Array:
	var concepts := ["1.1.a", "1.1.b", "1.1.c", "1.2.d", "1.2.e", "2.1.f"]
	var out: Array = []
	for i in n:
		out.append(_entry("%s-1" % concepts[i % 6], concepts[i % 6]))
	return out


func test_options_are_shuffled_with_letters() -> void:
	var r := Round.new(pack, rules, [_entry("1.1.a-1", "1.1.a")], rng)
	r.start_encounter()
	var opts := r.options()
	assert_eq(opts.size(), 4)
	assert_eq(opts.map(func(o): return o["letter"]), ["a", "b", "c", "d"])
	var ids := opts.map(func(o): return o["id"])
	ids.sort()
	assert_eq(ids, ["a", "b", "c", "d"])
	assert_eq(r.letter_of(opts[2]["id"]), "c")


func test_shuffle_differs_across_seeds() -> void:
	var seen: Dictionary = {}
	for s in range(1, 20):
		rng.seed = s
		var r := Round.new(pack, rules, [_entry("1.1.a-1", "1.1.a")], rng)
		r.start_encounter()
		seen[str(r.order)] = true
	assert_gt(seen.size(), 3)


func test_parse_mcq() -> void:
	var r := _round([_entry("1.1.a-1", "1.1.a")])
	assert_eq(r.parse("b"), {"ok": true, "picks": ["b"]})
	assert_eq(r.parse("  C "), {"ok": true, "picks": ["c"]})
	for bad in ["", "e", "ab", "a b", "5", "0", "12", "bb", "yes"]:
		assert_false(r.parse(bad)["ok"], "'%s' should not be an answer" % bad)


func test_parse_accepts_digits_as_letters() -> void:
	var r := _round([_entry("1.1.a-1", "1.1.a")])
	assert_eq(r.parse("1"), {"ok": true, "picks": ["a"]})
	assert_eq(r.parse(" 4 "), {"ok": true, "picks": ["d"]})
	assert_false(r.parse("5")["ok"], "only as many digits as options")
	assert_string_contains(r.parse("")["error"], "1-4")
	var m := _round([_entry("1.1.a-2", "1.1.a")])
	assert_eq(m.parse("1 3"), {"ok": true, "picks": ["a", "c"]})
	assert_eq(m.parse("13"), {"ok": true, "picks": ["a", "c"]})
	assert_eq(m.parse("a 3"), {"ok": true, "picks": ["a", "c"]}, "letters and digits mix")
	assert_false(m.parse("1 a")["ok"], "the same option twice, whichever way it is written")


func test_parse_multi() -> void:
	var r := _round([_entry("1.1.a-2", "1.1.a")])
	assert_eq(r.item()["type"], "multi")
	assert_eq(r.parse("a c"), {"ok": true, "picks": ["a", "c"]})
	assert_eq(r.parse("a,c"), {"ok": true, "picks": ["a", "c"]})
	assert_eq(r.parse("AC"), {"ok": true, "picks": ["a", "c"]})
	assert_eq(r.parse("b")["picks"], ["b"], "a single pick is a legal multi answer")
	assert_false(r.parse("aa")["ok"])
	assert_false(r.parse("a e")["ok"])


func test_parse_follows_the_shuffled_order() -> void:
	var r := _round([_entry("1.1.a-1", "1.1.a")])
	r.order = ["d", "c", "b", "a"]
	assert_eq(r.parse("a")["picks"], ["d"], "letter a is whatever is displayed first")
	assert_eq(r.options()[0]["text"], "Delta")


func test_correct_answer() -> void:
	var r := _round([_entry("1.1.a-1", "1.1.a"), _entry("1.1.b-1", "1.1.b")])
	var res := r.submit(["b"])
	assert_eq(res["credit"], 1.0)
	assert_eq(res["xp"], 10)
	assert_eq(res["streak"], 1)
	assert_eq(res["requeue_gap"], 0)
	assert_eq(r.trace, 0, "relief cannot go below zero")
	assert_eq(r.full, 1)


func test_streak_bonus_and_reset() -> void:
	var r := _round(_many(4))
	var gained: Array = []
	for i in 3:
		gained.append(r.submit(["b"])["xp"])
		r.advance()
		r.order = ["a", "b", "c", "d"]
	assert_eq(gained, [10, 11, 12])
	r.submit(["a"])
	assert_eq(r.streak, 0)
	assert_eq(r.best_streak, 3)


func test_wrong_answer_raises_trace_requeues_and_reports_why() -> void:
	var r := _round(_many(3))
	var res := r.submit(["a"])
	assert_eq(res["credit"], 0.0)
	assert_eq(res["xp"], 0)
	assert_eq(r.trace, 20)
	assert_eq(res["wrong"], [{"id": "a", "text": "Alpha", "why": "Alpha is wrong."}])
	assert_eq(res["correct"], ["b"])
	assert_between(res["requeue_gap"], 1, 6)
	assert_eq(r.queue.size(), 4)
	assert_eq(r.queue[r.index + res["requeue_gap"]]["kind"], "retry")
	assert_eq(r.queue[r.index + res["requeue_gap"]]["concept"], "1.1.a")


func test_requeue_prefers_a_different_item_of_the_concept() -> void:
	var r := _round([_entry("1.1.a-1", "1.1.a")])
	r.submit(["a"])
	assert_eq(r.queue.size(), 2)
	assert_eq(r.queue[1]["item"], "1.1.a-2", "the other item, not the same one again")


func test_requeue_gap_is_clamped_to_the_end() -> void:
	rules.requeue_min = 6
	rules.requeue_max = 6
	var r := _round(_many(2))
	var res := r.submit(["a"])
	assert_eq(res["requeue_gap"], 2, "only two slots remain, so it lands at the end")
	assert_eq(r.queue.size(), 3)


func test_requeue_gap_is_in_range() -> void:
	for s in range(1, 30):
		rng.seed = s
		var r := _round(_many(9))
		var gap: int = r.submit(["a"])["requeue_gap"]
		assert_between(gap, rules.requeue_min, rules.requeue_max, "seed %d" % s)


func test_a_concept_is_requeued_only_once_per_round() -> void:
	var r := _round([_entry("1.1.a-1", "1.1.a")])
	r.submit(["a"])
	assert_eq(r.queue.size(), 2)
	assert_true(r.advance())
	r.order = ["a", "b", "c", "d"]
	var res := r.submit(["a"])
	assert_eq(res["requeue_gap"], 0, "second miss on the same concept adds nothing")
	assert_eq(r.queue.size(), 2)


func test_partial_credit_on_a_multi() -> void:
	var r := _round([_entry("1.1.a-2", "1.1.a")])
	var res := r.submit(["a"])
	assert_eq(res["credit"], 0.5)
	assert_eq(res["trace_delta"], 10)
	assert_eq(r.trace, 10)
	assert_eq(r.streak, 0)
	assert_gt(res["requeue_gap"], 0, "less than full credit is requeued")
	assert_eq(res["wrong"], [])


func test_trace_relief_on_a_correct_answer() -> void:
	var r := _round(_many(4))
	r.submit(["a"])
	r.advance()
	r.order = ["a", "b", "c", "d"]
	r.submit(["b"])
	assert_eq(r.trace, 15)


func test_traced_round_keeps_the_xp_already_earned() -> void:
	var r := _round(_many(9))
	r.submit(["b"])  # 10 XP, trace stays at its floor of 0
	for i in 5:
		r.advance()
		r.order = ["a", "b", "c", "d"]
		var res := r.submit(["d"])
		assert_eq(res["traced"], i == 4, "traced only on the fifth miss")
	assert_eq(r.trace, 100)
	assert_eq(r.outcome, "traced")
	assert_eq(r.xp, 10, "a traced round loses nothing")


func test_trace_limit_ends_the_round() -> void:
	var r := _round(_many(9))
	var traced := false
	for i in 5:
		r.order = ["a", "b", "c", "d"]
		traced = r.submit(["d"])["traced"]
		if not traced:
			r.advance()
	assert_true(traced)
	assert_eq(r.outcome, "traced")
	assert_false(r.advance(), "a traced round does not continue")
	assert_eq(r.trace, 100)


func test_completing_the_queue() -> void:
	var r := _round(_many(2))
	r.submit(["b"])
	assert_true(r.advance())
	r.order = ["a", "b", "c", "d"]
	r.submit(["b"])
	assert_false(r.advance())
	assert_eq(r.outcome, "complete")
	assert_true(r.is_over())


func test_leave_only_sets_left_while_running() -> void:
	var r := _round(_many(2))
	r.leave()
	assert_eq(r.outcome, "left")
	var t := _round(_many(9))
	for i in 5:
		t.order = ["a", "b", "c", "d"]
		t.submit(["d"])
		t.advance()
	t.leave()
	assert_eq(t.outcome, "traced", "leave does not rewrite how a round ended")
