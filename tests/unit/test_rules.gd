extends GutTest

const Support := preload("res://tests/unit/support.gd")


func test_default_rules_load_clean() -> void:
	var r := Rules.load_default()
	assert_eq(r.errors, [])
	assert_eq(r.round_size, 9)
	assert_eq(r.box_days, [0, 1, 2, 4, 8, 16])
	assert_eq(r.ranks.size(), 7)


func test_interval_by_box_and_clamped() -> void:
	var r := Rules.load_default()
	assert_eq([r.interval(0), r.interval(1), r.interval(2), r.interval(3), r.interval(4), r.interval(5)],
			[0, 1, 2, 4, 8, 16])
	assert_eq(r.interval(99), 16)
	assert_eq(r.interval(-3), 0)


func test_rank_boundaries() -> void:
	var r := Rules.load_default()
	assert_eq(r.rank_index(0), 0)
	assert_eq(r.rank_index(99), 0)
	assert_eq(r.rank_index(100), 1)
	assert_eq(r.rank_index(3999), 5)
	assert_eq(r.rank_index(4000), 6)
	assert_eq(r.rank_index(1000000), 6)
	assert_eq(r.rank_name(0), "Script Kiddie")
	assert_eq(r.rank_name(6), "Root")


func test_xp_to_next() -> void:
	var r := Rules.load_default()
	assert_eq(r.xp_to_next(0), 100)
	assert_eq(r.xp_to_next(95), 5)
	assert_eq(r.xp_to_next(100), 200)
	assert_eq(r.xp_to_next(4000), -1)


func test_ranks_problem() -> void:
	assert_eq(Rules.ranks_problem([["A", 0], ["B", 10]]), "")
	assert_ne(Rules.ranks_problem([]), "")
	assert_ne(Rules.ranks_problem("x"), "")
	assert_ne(Rules.ranks_problem([["A", 5], ["B", 10]]), "", "must start at 0")
	assert_ne(Rules.ranks_problem([["A", 0], ["B", 10], ["C", 10]]), "", "strictly increasing")
	assert_ne(Rules.ranks_problem([["", 0]]), "")
	assert_ne(Rules.ranks_problem([["A", 0, 1]]), "")


func test_bad_rules_file_reports_each_problem_and_keeps_defaults() -> void:
	var dir := Support.make_dir()
	Support.write_json(dir.path_join("rules.json"), {
		"round_size": 0, "trace": {"limit": 0}, "ranks": [["A", 3]], "requeue_gap": [6, 3]})
	var r := Rules.load_file(dir.path_join("rules.json"))
	var text := "\n".join(r.errors)
	for needle in ["round_size", "limit", "first rank", "requeue_gap", "xp_per_difficulty"]:
		assert_string_contains(text, needle)
	assert_eq(r.round_size, 9, "a bad value falls back to the default")
	Support.remove_dir(dir)


func test_missing_rules_file_is_an_error_not_a_crash() -> void:
	var r := Rules.load_file("res://data/does_not_exist.json")
	assert_eq(r.errors.size(), 1)
	assert_eq(r.rank_name(r.rank_index(50)), "Operator")
