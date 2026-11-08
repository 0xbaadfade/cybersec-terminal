extends GutTest
## Scoring and session state of the evidence hunt (README "Phase 3 plan").

const Support := preload("res://tests/unit/support.gd")

var _rules: Rules
var _item: Dictionary
var _lines: Array


func before_each() -> void:
	_rules = Rules.load_default()
	_item = Support.evidence_item("e-1", "1.1.a")
	_lines = Array(Support.DEMO_ARTIFACT.split("\n"))
	_lines.pop_back()


func _score(flags: Dictionary) -> Dictionary:
	return Evidence.score(_item, _lines, flags, _rules)


func _all_right() -> Dictionary:
	return {3: "excess-privilege", 4: "weak-auth", 5: "weak-crypto"}


func test_default_rules_carry_the_evidence_block() -> void:
	assert_eq(_rules.errors, [])
	assert_eq([_rules.evidence_line_percent, _rules.evidence_reason_percent,
			_rules.evidence_false_flag_percent, _rules.evidence_xp_multiplier], [70, 30, 15, 2])


func test_everything_found_and_right_is_exactly_one() -> void:
	var r := _score(_all_right())
	assert_eq(r["credit"], 1.0)
	assert_eq(r["points"], 300)
	assert_eq(r["found"], 3)
	assert_eq(r["missed"], 0)
	assert_eq(r["false_flags"], 0)


func test_each_wrong_reason_loses_thirty() -> void:
	for line in [3, 4, 5]:
		var flags := _all_right()
		flags[line] = "exposure" if line != 5 else "weak-auth"
		var r := _score(flags)
		assert_eq(r["points"], 270, "line %d" % line)
		assert_lt(r["credit"], 1.0)


func test_each_missed_line_loses_its_hundred() -> void:
	for line in [3, 4, 5]:
		var flags := _all_right()
		flags.erase(line)
		var r := _score(flags)
		assert_eq(r["points"], 200, "line %d" % line)
		assert_eq(r["missed"], 1)
		assert_almost_eq(r["credit"], 2.0 / 3.0, 0.0001)


func test_alternative_reasons_are_all_accepted() -> void:
	var flags := _all_right()
	flags[5] = "exposure"
	assert_eq(_score(flags)["credit"], 1.0)


func test_false_flag_costs_fifteen_per_flaw_and_a_decoy_counts() -> void:
	var generic := _all_right()
	generic[6] = "weak-auth"
	var r := _score(generic)
	assert_eq(r["points"], 300 - 45)
	assert_eq(r["false_flags"], 1)
	var decoy := _all_right()
	decoy[2] = "weak-auth"
	assert_eq(_score(decoy)["points"], 255)


func test_credit_never_goes_below_zero() -> void:
	# Three false flags and no flaw found: -135 points, floored at credit 0.
	var r := _score({1: "weak-auth", 2: "weak-auth", 6: "exposure"})
	assert_eq(r["points"], -135)
	assert_eq(r["credit"], 0.0)


func test_no_flags_is_zero_with_everything_missed() -> void:
	var r := _score({})
	assert_eq(r["credit"], 0.0)
	assert_eq(r["missed"], 3)


func test_integer_maths_is_exact_for_one_to_five_flaws() -> void:
	for n in range(1, 6):
		var item := _item.duplicate(true)
		var flaws: Array = []
		var lines: Array = []
		for i in range(1, n + 3):
			lines.append("line %d" % i)
		for i in n:
			flaws.append({"line": i + 1, "match": "line", "reason": "weak-auth", "explain": "x"})
		item["flaws"] = flaws
		item["decoys"] = []
		var flags: Dictionary = {}
		for i in n:
			flags[i + 1] = "weak-auth"
		assert_eq(Evidence.score(item, lines, flags, _rules)["credit"], 1.0, "n=%d" % n)
		flags[n + 1] = "weak-auth"
		var r := Evidence.score(item, lines, flags, _rules)
		assert_eq(r["points"], 85 * n, "n=%d one false flag" % n)
		assert_almost_eq(r["credit"], 0.85, 0.0001)


func test_outcomes_are_in_file_order_with_the_right_kinds() -> void:
	var r := _score({6: "exposure", 4: "exposure", 2: "weak-auth"})
	var got: Array = r["lines"].map(func(o): return "%d:%s" % [o["line"], o["kind"]])
	assert_eq(got, ["2:false", "3:missed", "4:found", "5:missed", "6:false"])
	assert_false(r["lines"][2]["reason_ok"])
	assert_eq(r["lines"][0]["explain"], "The default port is fine.")
	assert_eq(r["lines"][4]["explain"], "This line is fine.")
	assert_eq(r["lines"][3]["accepted"], ["weak-crypto", "exposure"])


func test_evidence_xp_is_doubled_and_scaled_by_credit() -> void:
	var it := Support.evidence_item("e-xp", "1.1.a", 2)
	assert_eq(Scoring.xp(it, 1.0, 1, _rules), 30)
	assert_eq(Scoring.xp(it, 0.5, 1, _rules), 15)
	assert_eq(Scoring.xp(Support.make_item("m", "1.1.a", "mcq", true, 2), 1.0, 1, _rules), 15)


func test_rules_reject_a_split_that_is_not_one_hundred() -> void:
	var dir := Support.make_dir()
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/rules.json"))
	d["evidence"] = {"line_percent": 60, "reason_percent": 30, "false_flag_percent": 15, "xp_multiplier": 2}
	Support.write_json(dir.path_join("rules.json"), d)
	var r := Rules.load_file(dir.path_join("rules.json"))
	assert_string_contains("\n".join(r.errors), "must be 100")
	assert_eq(r.evidence_line_percent, 70, "the default is kept")
	d.erase("evidence")
	Support.write_json(dir.path_join("rules.json"), d)
	assert_eq(Rules.load_file(dir.path_join("rules.json")).errors, [], "the block is optional")
	Support.remove_dir(dir)


# --- session -------------------------------------------------------------

func _session(line_count: int = 40) -> EvidenceSession:
	var lines: Array = []
	for i in line_count:
		lines.append("line %d" % (i + 1))
	return EvidenceSession.new(lines, Support.REASONS)


func test_cursor_clamps_at_both_ends() -> void:
	var s := _session()
	s.move(-5)
	assert_eq(s.cursor, 1)
	s.go(999)
	assert_eq(s.cursor, 40)
	s.go(-4)
	assert_eq(s.cursor, 1)


func test_window_follows_the_cursor() -> void:
	var s := _session()
	assert_eq([s.top, s.last_visible()], [1, 15])
	s.go(15)
	assert_eq(s.top, 1)
	s.move(1)
	assert_eq([s.top, s.last_visible()], [2, 16])
	s.go(40)
	assert_eq([s.top, s.last_visible()], [26, 40])
	s.go(10)
	assert_eq(s.top, 10, "scrolling back up puts the cursor at the top edge")
	var short := _session(6)
	short.go(6)
	assert_eq([short.top, short.last_visible()], [1, 6])


func test_flag_opens_the_menu_and_a_digit_sets_the_reason() -> void:
	var s := _session()
	assert_true(s.begin_flag(8))
	assert_eq([s.pending, s.cursor], [8, 8])
	assert_true(s.choose(2))
	assert_eq(s.flags, {8: "excess-privilege"})
	assert_eq(s.pending, 0)


func test_clear_digit_removes_the_flag_and_esc_cancels() -> void:
	var s := _session()
	s.begin_flag(8)
	s.choose(1)
	assert_eq(s.clear_digit(), 5)
	s.begin_flag(8)
	assert_true(s.choose(5))
	assert_eq(s.flags, {})
	s.begin_flag(9)
	s.cancel()
	assert_eq(s.pending, 0)
	assert_eq(s.flags, {})


func test_bad_lines_and_digits_change_nothing() -> void:
	var s := _session()
	assert_false(s.begin_flag(0))
	assert_false(s.begin_flag(41))
	assert_false(s.choose(1), "no menu is open")
	s.begin_flag(3)
	assert_false(s.choose(0))
	assert_false(s.choose(6))
	assert_eq(s.pending, 3, "the menu stays open after a bad digit")
	assert_eq(s.flags, {})


func test_reflagging_changes_the_reason_and_unflag_removes_it() -> void:
	var s := _session()
	s.begin_flag(4)
	s.choose(1)
	s.begin_flag(4)
	s.choose(3)
	assert_eq(s.flags, {4: "exposure"})
	assert_true(s.unflag(4))
	assert_false(s.unflag(4))
