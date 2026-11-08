extends GutTest

const Support := preload("res://tests/unit/support.gd")

var rules: Rules


func before_each() -> void:
	rules = Rules.load_default()


func _mcq() -> Dictionary:
	return Support.make_item("m", "1.1.a", "mcq")


func _multi(difficulty: int = 1) -> Dictionary:
	return Support.make_item("x", "1.1.a", "multi", true, difficulty)


func test_mcq_credit() -> void:
	assert_eq(Scoring.credit(_mcq(), ["b"]), 1.0)
	assert_eq(Scoring.credit(_mcq(), ["a"]), 0.0)


func test_multi_credit_table() -> void:
	# answer is [a, c]
	var table := [
		[["a", "c"], 1.0],
		[["c", "a"], 1.0],
		[["a"], 0.5],
		[["c"], 0.5],
		[["a", "b"], 0.0],   # one right, one wrong: (1-1)/2
		[["b"], 0.0],
		[["b", "d"], 0.0],   # floored at zero, never negative
		[["a", "c", "d"], 0.5],
		[["a", "b", "c", "d"], 0.0],
		[[], 0.0],
	]
	for row in table:
		assert_eq(Scoring.credit(_multi(), row[0]), row[1], "picks %s" % [row[0]])


func test_streak_bonus() -> void:
	assert_eq(Scoring.streak_bonus(0, rules), 0.0)
	assert_eq(Scoring.streak_bonus(1, rules), 0.0, "the first correct answer has no bonus")
	assert_almost_eq(Scoring.streak_bonus(2, rules), 0.10, 0.0001)
	assert_almost_eq(Scoring.streak_bonus(6, rules), 0.50, 0.0001)
	assert_almost_eq(Scoring.streak_bonus(40, rules), 0.50, 0.0001, "capped")


func test_xp() -> void:
	assert_eq(Scoring.xp(_mcq(), 1.0, 1, rules), 10)
	assert_eq(Scoring.xp(_mcq(), 1.0, 2, rules), 11)
	assert_eq(Scoring.xp(_mcq(), 1.0, 20, rules), 15)
	assert_eq(Scoring.xp(_multi(2), 1.0, 1, rules), 15)
	assert_eq(Scoring.xp(_multi(3), 1.0, 1, rules), 20)
	assert_eq(Scoring.xp(_multi(2), 0.5, 1, rules), 8, "7.5 rounds up")
	assert_eq(Scoring.xp(_mcq(), 0.0, 5, rules), 0)


func test_partial_credit_gets_no_streak_bonus() -> void:
	assert_eq(Scoring.xp(_multi(3), 0.5, 9, rules), 10)


func test_trace_delta() -> void:
	assert_eq(Scoring.trace_delta(1.0, rules), -5)
	assert_eq(Scoring.trace_delta(0.0, rules), 20)
	assert_eq(Scoring.trace_delta(0.5, rules), 10)
