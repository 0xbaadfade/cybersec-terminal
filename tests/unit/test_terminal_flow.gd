extends GutTest
## The terminal item: validation, the session's tries and credit, a mission
## and free play through the router (a mission is served in a skill pack's round), the shipped lab.

const Support := preload("res://tests/unit/support.gd")
const REAL_PACK := "res://packs/linux-cli"
const WINDOWS_PACK := "res://packs/windows-cli"

var _dir := ""
var _profiles := ""
var _now := Support.T0
var _router: CommandRouter


func before_each() -> void:
	_dir = Support.make_dir()
	_profiles = Support.make_dir()
	_now = Support.T0


func after_each() -> void:
	Support.remove_dir(_dir)
	Support.remove_dir(_profiles)


func _text(lines: Array) -> String:
	return "\n".join(lines.map(func(l): return l.get("t", "")))


func _pack(items: Array, lab: Dictionary = {}, skill: bool = false) -> Pack:
	Support.write_lab_pack(_dir, items, lab)
	if skill:
		var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_dir.path_join("pack.json")))
		meta["rounds_include_labs"] = true
		Support.write_json(_dir.path_join("pack.json"), meta)
	return Pack.load_dir(_dir)


## Concept a: mcq + terminal item; b and c: an mcq each. A skill pack (its rounds may
## hold a mission) unless `skill` is false.
func _start(items: Array = [], skill: bool = true) -> void:
	if items.is_empty():
		items = [Support.make_item("a-m", "1.1.a"), Support.terminal_item("a-t", "1.1.a"),
				Support.make_item("b-m", "1.1.b"), Support.make_item("c-m", "1.1.c")]
	var pack := _pack(items, {}, skill)
	assert_true(pack.ok(), "\n".join(pack.errors))
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	_router = CommandRouter.new(ProfileStore.new(_profiles), pack, null, rng, func() -> int: return _now)
	_router.handle("new dana")


## Starts a typed round on 1.1 and puts the demo mission first (alone in the queue).
func _to_lab() -> void:
	_router.handle("breach 1.1")
	var r := _router.current_round
	r.queue = [{"item": "a-t", "concept": "1.1.a", "kind": "new"}]
	r.index = 0
	r.start_encounter()
	_router._enter_encounter()


# --- validation ------------------------------------------------------------

func test_a_good_terminal_item_and_its_lab_load() -> void:
	var pack := _pack([Support.terminal_item("t-1", "1.1.a")])
	assert_true(pack.ok(), "\n".join(pack.errors))
	assert_eq(pack.items.size(), 1)
	assert_true(pack.labs.has("lab-a"))
	assert_true(pack.tool_docs.has("ping"))
	assert_true(Pack.is_pbq(pack.items["t-1"]))


func test_terminal_item_checks() -> void:
	var errors := func(changes: Dictionary) -> String:
		var item := Support.terminal_item("t-1", "1.1.a")
		item.merge(changes, true)
		return "\n".join(_pack([item]).errors)
	assert_string_contains(errors.call({"lab": "lab-zzz"}), "unknown lab 'lab-zzz'")
	assert_string_contains(errors.call({"answer": {"accept": []}}), "'answer' needs a non-empty 'accept' array")
	assert_string_contains(errors.call({"answer": "10.20.0.30"}), "'answer' needs a non-empty 'accept' array")
	assert_string_contains(errors.call({"answer": {"accept": [5]}}), "non-empty string")
	assert_string_contains(errors.call({"answer": {"accept": ["  "]}}), "non-empty string")
	assert_eq(errors.call({"explain": ""}), "", "an empty explanation is allowed: explain is optional")
	assert_string_contains(errors.call({"explain": 7}), "'explain' must be text")


func test_a_broken_lab_is_reported_and_its_items_are_rejected() -> void:
	var lab := Support.demo_lab()
	lab["hosts"][2]["ip"] = "10.99.0.1"
	var pack := _pack([Support.terminal_item("t-1", "1.1.a")], lab)
	assert_string_contains("\n".join(pack.errors), "labs/lab-a.json: host 10.99.0.1 is outside")
	assert_string_contains("\n".join(pack.errors), "unknown lab 'lab-a'")
	assert_eq(pack.items.size(), 0)


func test_duplicate_lab_ids_and_bad_tool_pages() -> void:
	var pack := _pack([Support.terminal_item("t-1", "1.1.a")])
	Support.write_json(_dir.path_join("labs/lab-b.json"), Support.demo_lab("lab-a"))
	assert_string_contains("\n".join(Pack.load_dir(_dir).errors), "duplicate lab id 'lab-a'")
	Support.remove_dir(_dir.path_join("labs"))
	Support.write_json(_dir.path_join("tools.json"), {
		"ping": {"summary": ""}, "grep": {"summary": "x", "concepts": ["9.9.z"]},
		"head": {"summary": "x", "flags": [["-n"]]}, "cat": {"summary": "fine"}})
	var errs := "\n".join(Pack.load_dir(_dir).errors)
	assert_string_contains(errs, "'ping' needs a non-empty 'summary'")
	assert_string_contains(errs, "'grep' names unknown concept '9.9.z'")
	assert_string_contains(errs, "'head' flags must be [flag, meaning] pairs")
	assert_false(errs.contains("'cat'"))
	assert_true(pack.ok())


func test_rules_terminal_block() -> void:
	var r := Rules.load_default()
	assert_eq([r.terminal_second_try_percent, r.terminal_xp_multiplier], [50, 2])
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/rules.json"))
	d["terminal"] = {"second_try_percent": 150, "xp_multiplier": 3}
	Support.write_json(_dir.path_join("rules.json"), d)
	var bad := Rules.load_file(_dir.path_join("rules.json"))
	assert_string_contains("\n".join(bad.errors), "second_try_percent must be 0 to 100")
	assert_eq(bad.terminal_second_try_percent, 50)
	assert_eq(bad.terminal_xp_multiplier, 3)
	d.erase("terminal")
	Support.write_json(_dir.path_join("rules.json"), d)
	assert_eq(Rules.load_file(_dir.path_join("rules.json")).errors, [], "the block is optional")


# --- the session ---------------------------------------------------------

func _session(mission: bool = true) -> TerminalSession:
	var lab := SimLab.from_data(Support.demo_lab(), "t")
	return TerminalSession.new(lab, Support.demo_tools(), {"1.1.a": "Alpha"},
			Support.terminal_item("t-1", "1.1.a") if mission else {}, Rules.load_default())


func test_prompt_names_the_user_and_the_host() -> void:
	assert_eq(_session().prompt(), "analyst@analyst-ws$")


func test_answers_ignore_case_and_surrounding_space() -> void:
	var s := _session()
	for ok in ["10.20.0.30", "  10.20.0.30 ", "PRINTER-01", "Printer-01"]:
		assert_true(s.is_right(ok), ok)
	for bad in ["10.20.0.3", "printer", "10.20.0.30 and more", ""]:
		assert_false(s.is_right(bad), bad)


func test_credit_by_try() -> void:
	var first := _session()
	assert_eq(first.answer("printer-01"), {"correct": true, "done": true, "tries_left": 1})
	assert_eq(first.credit(), 1.0)
	var second := _session()
	assert_eq(second.answer("web-03"), {"correct": false, "done": false, "tries_left": 1})
	assert_eq(second.credit(), 0.0, "nothing yet")
	assert_eq(second.answer("printer-01"), {"correct": true, "done": true, "tries_left": 0})
	assert_eq(second.credit(), 0.5)
	var none := _session()
	none.answer("a")
	assert_eq(none.answer("b"), {"correct": false, "done": true, "tries_left": 0})
	assert_eq(none.credit(), 0.0)
	assert_eq(none.given, ["a", "b"])


func test_the_share_for_a_second_try_comes_from_rules() -> void:
	var lab := SimLab.from_data(Support.demo_lab(), "t")
	var rules := Rules.load_default()
	rules.terminal_second_try_percent = 25
	var s := TerminalSession.new(lab, {}, {}, Support.terminal_item("t-1", "1.1.a"), rules)
	s.answer("x")
	s.answer("printer-01")
	assert_eq(s.credit(), 0.25)


func test_running_commands_records_history_and_runs_the_shell() -> void:
	var s := _session()
	var r := s.run("ping -c 1 10.20.0.10", _now)
	assert_eq(r["code"], 0)
	assert_string_contains("\n".join(r["out"]), "1 packets transmitted, 1 received")
	s.run("ls", _now)
	assert_eq(s.history, ["ping -c 1 10.20.0.10", "ls"])
	assert_string_contains("\n".join(s.run("help", _now)["out"]), "answer <text> submits (2 tries)")
	assert_string_contains("\n".join(_session(false).run("help", _now)["out"]), "free play")


# --- a mission through the router ---------------------------------------------

func test_a_round_never_holds_the_lab_in_an_ordinary_pack() -> void:
	_start([], false)
	_router.handle("breach 1.1")
	var queue: Array = _router.current_round.queue
	assert_eq(queue.size(), 3)
	assert_eq(queue.filter(func(e): return e["item"] == "a-t").size(), 0)
	assert_eq(_router.mode, CommandRouter.Mode.ASK)


func test_a_skill_packs_round_can_hold_the_mission() -> void:
	_start()
	var found := false
	for k in 12:
		_router.handle("breach 1.1")
		for e in _router.current_round.queue:
			found = found or e["item"] == "a-t"
		_router.handle("leave")
		if found:
			break
	assert_true(found, "a mission is served by a skill pack's round")


func test_the_mission_screen_and_prompt() -> void:
	_start()
	_to_lab()
	assert_eq(_router.mode, CommandRouter.Mode.TERMINAL)
	assert_eq(_router.prompt(), "analyst@analyst-ws$")
	var text := _text(_router.handle("clear"))
	assert_string_contains(text, "TERMINAL LAB 1/1  //  1.1")
	assert_string_contains(text, "Which host drops ping? (a-t)")
	assert_string_contains(text, "Demo lab   (you are analyst@analyst-ws)")
	assert_string_contains(text, "answer <text> submits (2 tries). leave ends the round.")


func test_commands_run_in_the_lab() -> void:
	_start()
	_to_lab()
	var out := _text(_router.handle("ping -c 1 web-03"))
	assert_string_contains(out, "PING web-03.corp.local (10.20.0.10)")
	assert_string_contains(_text(_router.handle("cat notes.txt | grep -i icmp")), "Printer: ICMP is disabled.")
	assert_string_contains(_text(_router.handle("wibble")), "bash: wibble: command not found")
	assert_eq(_router.mode, CommandRouter.Mode.TERMINAL)
	assert_eq(_router.handle(""), [], "a blank line does nothing")


func test_the_status_bar_has_the_trace_meter_in_a_typed_round_but_not_a_sized_one() -> void:
	_start()
	_to_lab()
	assert_string_contains(_router.status_line(), "TRACE 0%")
	_router.handle("leave")
	_router.handle("5")
	assert_false(_router.status_line().contains("TRACE"))


func test_a_right_answer_shows_the_lesson_and_counts() -> void:
	_start()
	_to_lab()
	_router.handle("ping -c 1 10.20.0.30")
	var text := _text(_router.handle("answer printer-01"))
	assert_eq(_router.mode, CommandRouter.Mode.FEEDBACK)
	assert_string_contains(text, "CORRECT   +20 XP")
	assert_string_contains(text, "Your answer: printer-01   (right on try 1)")
	assert_string_contains(text, "The answer: 10.20.0.30   (also accepted: printer-01)")
	assert_string_contains(text, "printer-01 drops ICMP (a-t).")
	assert_string_contains(text, "You ran 1 command:")
	assert_string_contains(text, "  $ ping -c 1 10.20.0.30")
	assert_false(text.contains("practice"))
	assert_false(text.contains("comes back in"))
	assert_eq(Mastery.total_xp(_router.profile), 20)
	assert_eq(Mastery.box(_router.profile, "1.1.a"), 1)
	assert_eq(Mastery.seen(_router.profile, "1.1.a"), 1)


func test_a_wrong_first_answer_keeps_the_lab_open_and_a_second_is_partial() -> void:
	_start()
	_to_lab()
	var nope := _text(_router.handle("answer web-03"))
	assert_string_contains(nope, "Not quite. You have 1 try left.")
	assert_false(nope.contains("10.20.0.30"), "the answer is not revealed")
	assert_eq(_router.mode, CommandRouter.Mode.TERMINAL)
	var text := _text(_router.handle("answer 10.20.0.30"))
	assert_string_contains(text, "PARTIAL   +10 XP")
	assert_string_contains(text, "(right on try 2)")
	assert_eq(Mastery.total_xp(_router.profile), 10)
	assert_string_contains(text, "comes back in")


func test_two_wrong_answers_end_it_and_reveal_the_answer() -> void:
	_start()
	_to_lab()
	_router.handle("answer one")
	var text := _text(_router.handle("answer two"))
	assert_string_contains(text, "INCORRECT   +0 XP")
	assert_string_contains(text, "Your answer: one, two   (not accepted)")
	assert_string_contains(text, "The answer: 10.20.0.30")
	assert_string_contains(text, "You ran no commands.")
	assert_eq(Mastery.box(_router.profile, "1.1.a"), 1, "a miss puts the concept back in box 1")
	assert_eq(_router.current_round.queue.size(), 2, "a retry is queued")
	assert_string_contains(text, "comes back in")
	_router.handle("")
	assert_eq(_router.mode, CommandRouter.Mode.ASK, "the retry is an ordinary question")


func test_answer_needs_text() -> void:
	_start()
	_to_lab()
	assert_string_contains(_text(_router.handle("answer")), "Usage: answer <text>")
	assert_eq(_router.mode, CommandRouter.Mode.TERMINAL)


func test_leave_and_exit_end_the_round() -> void:
	_start()
	_to_lab()
	assert_string_contains(_text(_router.handle("leave")), "ROUND ENDED EARLY")
	assert_eq(_router.mode, CommandRouter.Mode.HOME)
	_to_lab()
	assert_string_contains(_text(_router.handle("exit")), "ROUND ENDED EARLY")
	assert_eq(_router.mode, CommandRouter.Mode.HOME)
	assert_false(_router.want_quit, "exit leaves the lab, not the game")
	assert_eq(Mastery.total_xp(_router.profile), 0)


func test_quit_still_quits_from_a_lab() -> void:
	_start()
	_to_lab()
	_router.handle("quit")
	assert_true(_router.want_quit)


func test_clear_redraws_the_banner_not_the_history() -> void:
	_start()
	_to_lab()
	_router.handle("ls")
	var out := _router.handle("clear")
	assert_eq(out[0], Lines.CLEAR)
	assert_string_contains(_text(out), "TERMINAL LAB")
	assert_false(_text(out).contains("notes.txt"))


func test_a_mission_result_is_saved_and_logged() -> void:
	_start()
	_to_lab()
	_router.handle("answer printer-01")
	_router.handle("")
	var saved := ProfileStore.new(_profiles).load_profile("dana")
	saved.track = "ev"
	assert_true(saved.progress()["items"].has("a-t"))
	assert_eq(Mastery.total_xp(saved), 20)
	assert_eq(saved.rounds().size(), 1, "a round-log entry")
	assert_eq(int(saved.rounds()[0]["answered"]), 1)


func test_the_same_commands_print_the_same_text_each_time() -> void:
	_start()
	_to_lab()
	var a := _text(_router.handle("ping -c 3 web-03"))
	var b := _text(_router.handle("ping -c 3 web-03"))
	assert_eq(a, b)


# --- free play ------------------------------------------------------------------

func test_lab_lists_and_opens_free_play() -> void:
	_start()
	assert_string_contains(_text(_router.handle("lab")), "lab-a")
	assert_string_contains(_text(_router.handle("lab")), "Demo lab")
	var out := _router.handle("lab lab-a")
	assert_eq(_router.mode, CommandRouter.Mode.TERMINAL)
	assert_eq(_router.prompt(), "analyst@analyst-ws$")
	assert_string_contains(_text(out), "TERMINAL LAB  //  free play")
	assert_string_contains(_text(out), "Free play awards no XP.")
	assert_string_contains(_text(_router.handle("ping -c 1 web-03")), "1 received")
	assert_null(_router.current_round)


func test_free_play_has_no_question_and_exit_returns_home_without_xp() -> void:
	_start()
	_router.handle("lab lab-a")
	assert_string_contains(_text(_router.handle("answer 10.20.0.30")), "There is no question in free play")
	assert_eq(_router.mode, CommandRouter.Mode.TERMINAL)
	assert_string_contains(_text(_router.handle("leave")), "Left the lab")
	assert_eq(_router.mode, CommandRouter.Mode.HOME)
	assert_eq(Mastery.total_xp(_router.profile), 0)
	assert_eq(_router.prompt(), "dana@ev>")


func test_free_play_from_the_map_and_errors() -> void:
	_start()
	_router.handle("map")
	_router.handle("lab lab-a")
	assert_eq(_router.mode, CommandRouter.Mode.TERMINAL)
	_router.handle("exit")
	assert_string_contains(_text(_router.handle("lab nope")), "No such lab 'nope'")
	assert_eq(_router.mode, CommandRouter.Mode.HOME)


func test_a_pack_without_labs_says_so() -> void:
	var pack := Pack.load_dir(_dir)
	Support.write_evidence_pack(_dir, [Support.make_item("a-m", "1.1.a")])
	pack = Pack.load_dir(_dir)
	var rng := RandomNumberGenerator.new()
	var r := CommandRouter.new(ProfileStore.new(_profiles), pack, null, rng, func() -> int: return _now)
	r.handle("new dana")
	assert_string_contains(_text(r.handle("lab")), "This pack has no labs.")


# --- the labs command is gone -------------------------------------------------------

func test_labs_is_no_longer_a_command_and_nothing_nudges_toward_it() -> void:
	_start()
	assert_string_contains(_text(_router.handle("labs")), "Unknown command 'labs'")
	assert_string_contains(_text(_router.handle("labs 1")), "Unknown command 'labs'")
	assert_eq(_router.mode, CommandRouter.Mode.HOME)
	var all := _text(_router.handle("help all"))
	assert_false(all.contains("labs "), "help all does not list it")
	assert_string_contains(all, "lab [id]")
	for screen in [_router.handle("help"), _router.handle("status"), _router.handle("map"), _router.handle("breach 1.1")]:
		assert_false(_text(screen).to_lower().contains("labs"), "no nudge")


# --- the shipped lab ------------------------------------------------------------------

func test_the_shipped_pack_validates_with_its_lab_and_tool_pages() -> void:
	var pack := Pack.load_dir(REAL_PACK)
	assert_true(pack.ok(), "\n".join(pack.errors))
	assert_true(pack.labs.has("lab-dmz-01"))
	assert_eq(pack.labs["lab-dmz-01"].hosts.size(), 6)
	for t in ["ping", "nmap", "ss", "netstat", "dig", "nslookup", "curl", "ip", "grep", "head", "tail", "wc", "cat", "ls"]:
		assert_true(pack.tool_docs.has(t), t)
	var shell := SimShell.new()
	for t in shell.tool_names():
		assert_true(pack.tool_docs.has(t), "every tool the shell offers has a manual page: %s" % t)
	assert_eq(pack.items["lin-m-01"]["lab"], "lab-dmz-01")
	assert_false(pack.items["lin-m-01"]["reviewed"])


func test_the_shipped_mission_can_be_solved_with_the_tools_it_has() -> void:
	var pack := Pack.load_dir(REAL_PACK)
	var it: Dictionary = pack.items["lin-m-01"]
	var s := TerminalSession.new(pack.labs["lab-dmz-01"], pack.tool_docs, pack.concept_titles(), it, Rules.load_default())
	for ip in ["10.20.0.10", "10.20.0.11"]:
		assert_string_contains("\n".join(s.run("ping -c 2 %s" % ip, _now)["out"]), "2 received, 0% packet loss")
	assert_string_contains("\n".join(s.run("ping -c 2 10.20.0.30", _now)["out"]), "0 received, 100% packet loss")
	assert_string_contains("\n".join(s.run("cat notes.txt", _now)["out"]), "ICMP is disabled")
	assert_true(s.answer("printer-01")["correct"])
	assert_eq(s.credit(), 1.0)


func test_free_play_works_on_the_shipped_lab() -> void:
	var rng := RandomNumberGenerator.new()
	var r := CommandRouter.new(ProfileStore.new(_profiles), Pack.load_dir(REAL_PACK), null, rng, func() -> int: return _now)
	r.handle("new dana")
	r.handle("lab lab-dmz-01")
	assert_eq(r.mode, CommandRouter.Mode.TERMINAL)
	assert_string_contains(_text(r.handle("ls")), "notes.txt  scope.txt")
	assert_string_contains(_text(r.handle("tool ping")), "Concept: Ping and reachability")
	assert_string_contains(_text(r.handle("ping -c 1 www.corp.local")), "PING web-03.corp.local (10.20.0.10)")


func test_all_shipped_linux_missions_are_terminal_items_on_the_linux_lab() -> void:
	var pack := Pack.load_dir(REAL_PACK)
	var ids: Array = pack.items.keys().filter(func(k): return pack.items[k]["type"] == "terminal")
	ids.sort()
	assert_eq(ids, ["lin-m-01", "lin-m-02", "lin-m-03", "lin-m-04", "lin-m-05", "lin-m-06", "lin-m-07", "lin-m-08",
			"lin-m-09", "lin-m-10"])
	for id in ids:
		assert_eq(pack.items[id]["lab"], "lab-dmz-01", id)
		assert_false(pack.items[id]["reviewed"], id)
		assert_eq(pack.items[id]["source"], "ai", id)


func test_all_shipped_windows_missions_are_terminal_items_on_the_office_lab() -> void:
	var pack := Pack.load_dir(WINDOWS_PACK)
	assert_true(pack.ok(), "\n".join(pack.errors))
	var ids: Array = pack.items.keys().filter(func(k): return pack.items[k]["type"] == "terminal")
	ids.sort()
	assert_eq(ids, ["win-m-01", "win-m-02", "win-m-03", "win-m-04", "win-m-05"])
	for id in ids:
		assert_eq(pack.items[id]["lab"], "lab-office-01", id)
		assert_false(pack.items[id]["reviewed"], id)
		assert_eq(pack.items[id]["source"], "ai", id)
