extends GutTest
## The track menu: MenuModel on its own, then the router's MENU mode.

const Support := preload("res://tests/unit/support.gd")

var _dir := ""
var _packs := ""
var _profiles := ""
var _router: CommandRouter


func before_each() -> void:
	_dir = Support.make_dir()
	_packs = _dir.path_join("packs")
	_profiles = _dir.path_join("profiles")
	_pack("alpha", "ALPHA")
	_pack("beta", "BETA", [["Newbie", 0], ["Wizard", 50]])
	Support.write_json(_dir.path_join("tracks.json"), {"legacy_track": "alpha", "sections": [
		{"id": "cert", "title": "CERTIFICATIONS", "tracks": [
			{"id": "alpha", "title": "Alpha Cert", "pack": "alpha"},
			{"id": "gamma", "title": "Gamma Cert"}]},
		{"id": "skill", "title": "SKILLS", "tracks": [
			{"id": "beta", "title": "Beta Skill", "pack": "beta"},
			{"id": "delta", "title": "Delta Skill"}]}]})
	_router = _make_router()


func after_each() -> void:
	Support.remove_dir(_dir)


func _make_router() -> CommandRouter:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var catalog := TrackCatalog.load_file(_dir.path_join("tracks.json"), _packs)
	return CommandRouter.new(ProfileStore.new(_profiles), null, null, rng, func() -> int: return Support.T0, catalog)


func _pack(id: String, short: String, ranks: Array = []) -> void:
	var items := [Support.make_item("%s-1" % id, "1.1.a"), Support.make_item("%s-2" % id, "1.1.b")]
	Support.write_pack(_packs.path_join(id), items)
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_packs.path_join(id).path_join("pack.json")))
	meta["id"] = id
	meta["short"] = short
	if not ranks.is_empty():
		meta["ranks"] = ranks
	Support.write_json(_packs.path_join(id).path_join("pack.json"), meta)


func _text(lines: Array) -> String:
	return "\n".join(lines.map(func(l): return l.get("t", "")))


func _styles(lines: Array) -> Array:
	return lines.map(func(l): return l.get("s", ""))


func _login() -> Array:
	return _router.handle("new dana")


## Breach 1.1 and answer the first encounter correctly; leaves the router at FEEDBACK.
func _score_once() -> void:
	_router.handle("breach 1.1")
	var r := _router.current_round
	_router.handle(r.letter_of(r.item()["answer"][0]))


func _menu_model() -> MenuModel:
	return _router._menu()


# --- the screen --------------------------------------------------------

func test_screen_has_sections_numbers_and_coming_soon() -> void:
	_login()
	var text := _text(_menu_model().screen("alpha"))
	assert_string_contains(text, "CERTIFICATIONS")
	assert_string_contains(text, "SKILLS")
	assert_string_contains(text, ">  1  Alpha Cert")
	assert_string_contains(text, "   2  Gamma Cert")
	assert_string_contains(text, "coming soon")
	assert_string_contains(text, "   4  Delta Skill")
	assert_true(text.find("CERTIFICATIONS") < text.find("Alpha Cert") and text.find("Alpha Cert") < text.find("SKILLS"))


func test_numbers_run_across_sections_in_catalog_order() -> void:
	_login()
	var m := _menu_model()
	assert_eq([m.resolve("1"), m.resolve("2"), m.resolve("3"), m.resolve("4")], ["alpha", "gamma", "beta", "delta"])
	assert_eq(m.resolve("0"), "")
	assert_eq(m.resolve("5"), "")
	assert_eq(m.resolve("-1"), "")


func test_resolve_accepts_ids_and_titles_in_any_case() -> void:
	_login()
	var m := _menu_model()
	assert_eq(m.resolve("beta"), "beta")
	assert_eq(m.resolve("  Beta Skill "), "beta")
	assert_eq(m.resolve("ALPHA CERT"), "alpha")
	assert_eq(m.resolve("nothing"), "")


func test_greyed_rows_are_dim_and_playable_rows_are_not() -> void:
	_login()
	var lines := _menu_model().screen("alpha")
	for l in lines:
		if "Gamma" in l["t"] or "Delta" in l["t"]:
			assert_eq(l["s"], Lines.S_DIM)
		if "Beta Skill" in l["t"]:
			assert_eq(l["s"], Lines.S_NORMAL)


func test_an_unavailable_track_is_shown_in_error_style_and_cannot_be_chosen() -> void:
	Support.write_text(_packs.path_join("broken/pack.json"), "{ nope")
	Support.write_json(_dir.path_join("tracks.json"), {"sections": [{"id": "s", "title": "S", "tracks": [
		{"id": "alpha", "title": "Alpha Cert", "pack": "alpha"}, {"id": "broken", "title": "Broken One", "pack": "broken"}]}]})
	_router = _make_router()
	_login()
	var shown := _menu_model().screen("alpha").filter(func(l): return "Broken One" in l["t"])
	assert_eq(shown[0]["s"], Lines.S_ERROR)
	assert_string_contains(shown[0]["t"], "unavailable")
	var out := _router.handle("2")
	assert_eq(_styles(out)[0], CommandRouter.S_ERROR)
	assert_string_contains(_text(out), "unavailable")
	assert_eq(_router.mode, CommandRouter.Mode.MENU)


func test_a_menu_with_nothing_playable_says_so() -> void:
	Support.write_json(_dir.path_join("tracks.json"), {"sections": [{"id": "s", "title": "S", "tracks": [{"id": "x", "title": "X"}]}]})
	_router = _make_router()
	_login()
	assert_string_contains(_text(_menu_model().screen("")), "No track has content yet")
	var out := _router.handle("@enter")
	assert_eq(_styles(out)[0], CommandRouter.S_ERROR)
	assert_eq(_router.mode, CommandRouter.Mode.MENU)
	_router.handle("@down")
	_router.handle("@up")


func test_progress_text_is_new_until_the_track_is_played_then_shows_rank_xp_and_due() -> void:
	_login()
	assert_eq(_menu_model().progress_text("alpha"), "new")
	_router.handle("1")
	_score_once()
	_router.handle("leave")
	_router.handle("menu")
	var t := _menu_model().progress_text("alpha")
	assert_string_contains(t, "XP")
	assert_string_contains(t, "Script Kiddie")
	assert_eq(_menu_model().progress_text("beta"), "new", "playing one track does not start the other")


func test_a_pack_ladder_names_the_rank_in_the_menu_and_the_engine_ladder_is_the_fallback() -> void:
	_login()
	_router.handle("3")
	_score_once()
	_router.handle("leave")
	_router.handle("menu")
	assert_string_contains(_menu_model().progress_text("beta"), "Newbie")
	_router.handle("1")
	assert_string_contains(_router.status_line(), "Script Kiddie")


# --- the router --------------------------------------------------------

func test_login_lands_on_the_menu_not_home() -> void:
	var out := _login()
	assert_eq(_router.mode, CommandRouter.Mode.MENU)
	assert_eq(_router.prompt(), "track>")
	assert_null(_router.pack)
	assert_string_contains(_text(out), "Account created")
	assert_string_contains(_text(out), "Alpha Cert")
	assert_eq(_router.title_line(), "CYBERSEC-TERMINAL v%s" % CommandRouter.VERSION)
	assert_eq(_router.status_line(), "dana")


func test_banner_counts_ready_tracks_without_a_pack() -> void:
	assert_string_contains(_text(_router.banner()), "2 of 4 tracks ready")


func test_banner_does_not_repeat_the_title_bar() -> void:
	assert_false(_text(_router.banner()).contains("CYBERSEC-TERMINAL"))


func test_choosing_a_number_enters_that_track() -> void:
	_login()
	var out := _router.handle("3")
	assert_eq(_router.mode, CommandRouter.Mode.HOME)
	assert_eq(_router.pack.id, "beta")
	assert_eq(_router.profile.track, "beta")
	assert_eq(_router.prompt(), "dana@beta>")
	assert_eq(_router.title_line(), "CYBERSEC-TERMINAL v%s  //  BETA" % CommandRouter.VERSION)
	assert_eq(out[0], Lines.CLEAR)
	assert_string_contains(_text(out), "Beta Skill")


func test_choosing_by_name_works() -> void:
	_login()
	_router.handle("Alpha Cert")
	assert_eq(_router.pack.id, "alpha")


func test_enter_and_arrows_choose_among_playable_tracks_only() -> void:
	_login()
	var first := _text(_router.handle("@down"))
	assert_string_contains(first, ">  3  Beta Skill", "the arrow skips the greyed rows")
	assert_string_contains(_text(_router.handle("@down")), ">  3  Beta Skill", "and stops at the last playable one")
	_router.handle("@up")
	_router.handle("@up")
	_router.handle("@up")
	assert_string_contains(_text(_router.handle("@up")), ">  1  Alpha Cert")
	_router.handle("@down")
	_router.handle("")
	assert_eq(_router.pack.id, "beta", "a blank line chooses the highlighted track")


func test_at_enter_chooses_the_highlighted_track() -> void:
	_login()
	_router.handle("@enter")
	assert_eq(_router.pack.id, "alpha")


func test_a_coming_soon_track_says_so_and_stays_on_the_menu() -> void:
	_login()
	var out := _router.handle("2")
	assert_string_contains(_text(out), "coming soon")
	assert_eq(_router.mode, CommandRouter.Mode.MENU)
	assert_null(_router.pack)
	assert_eq(_router.profile.track, "")


func test_a_bad_number_or_name_is_an_error() -> void:
	_login()
	assert_eq(_styles(_router.handle("9"))[0], CommandRouter.S_ERROR)
	assert_eq(_styles(_router.handle("zzz"))[0], CommandRouter.S_ERROR)
	assert_eq(_router.mode, CommandRouter.Mode.MENU)


func test_menu_help_and_esc_and_clear() -> void:
	_login()
	assert_string_contains(_text(_router.handle("help")), "arrows move")
	assert_eq(_router.handle("@esc"), [])
	var redraw := _router.handle("clear")
	assert_eq(redraw[0], Lines.CLEAR)
	assert_string_contains(_text(redraw), "Alpha Cert")


func test_menu_command_returns_from_home_and_the_pack_is_dropped() -> void:
	_login()
	_router.handle("1")
	var out := _router.handle("menu")
	assert_eq(_router.mode, CommandRouter.Mode.MENU)
	assert_null(_router.pack)
	assert_eq(_router.profile.track, "")
	assert_string_contains(_text(out), "Beta Skill")


func test_menu_returns_from_the_map_and_after_a_finished_round() -> void:
	_login()
	_router.handle("1")
	_router.handle("map")
	assert_eq(_router.mode, CommandRouter.Mode.MAP)
	_router.handle("menu")
	assert_eq(_router.mode, CommandRouter.Mode.MENU)
	_router.handle("1")
	_score_once()
	_router.handle("leave")
	assert_eq(_router.mode, CommandRouter.Mode.HOME)
	_router.handle("menu")
	assert_eq(_router.mode, CommandRouter.Mode.MENU)


func test_menu_is_not_a_way_out_of_an_encounter() -> void:
	_login()
	_router.handle("1")
	_router.handle("breach 1.1")
	assert_eq(_router.mode, CommandRouter.Mode.ASK)
	var out := _router.handle("menu")
	assert_eq(_styles(out)[0], CommandRouter.S_ERROR)
	assert_eq(_router.mode, CommandRouter.Mode.ASK)
	assert_not_null(_router.current_round)
	assert_eq(_router.pack.id, "alpha")


func test_each_track_keeps_its_own_xp_and_switching_back_finds_it() -> void:
	_login()
	_router.handle("1")
	_score_once()
	var alpha_xp := Mastery.total_xp(_router.profile)
	assert_gt(alpha_xp, 0)
	_router.handle("leave")
	_router.handle("menu")
	_router.handle("3")
	assert_eq(Mastery.total_xp(_router.profile), 0, "beta starts clean")
	assert_string_contains(_router.status_line(), "0 XP")
	_router.handle("menu")
	_router.handle("1")
	assert_eq(Mastery.total_xp(_router.profile), alpha_xp, "alpha kept its XP")
	assert_string_contains(_router.status_line(), "%d XP" % alpha_xp)


func test_progress_is_saved_under_the_track_and_never_under_an_empty_id() -> void:
	_login()
	_router.handle("1")
	_score_once()
	_router.handle("leave")
	_router.handle("menu")
	_router.handle("@down")
	_router.handle("3")
	_router.handle("menu")
	_router.handle("logout")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_profiles.path_join("dana.json")))
	assert_eq(int(saved["version"]), 3)
	assert_eq(saved["tracks"].keys(), ["alpha"], "only a played track has a section; beta and '' have none")
	assert_gt(int(saved["tracks"]["alpha"]["xp"]["total"]), 0)


func test_logout_from_the_menu_returns_to_login_and_a_second_user_starts_clean() -> void:
	_login()
	_router.handle("1")
	_score_once()
	_router.handle("leave")
	_router.handle("menu")
	var out := _router.handle("logout")
	assert_eq(_router.mode, CommandRouter.Mode.LOGIN)
	assert_null(_router.pack)
	assert_string_contains(_text(out), "Logged out")
	_router.handle("new sam")
	assert_eq(_router.mode, CommandRouter.Mode.MENU)
	assert_eq(_menu_model().progress_text("alpha"), "new")


func test_logout_from_home_also_goes_via_login_then_the_menu() -> void:
	_login()
	_router.handle("1")
	_router.handle("logout")
	assert_eq(_router.mode, CommandRouter.Mode.LOGIN)
	assert_null(_router.pack)
	_router.handle("dana")
	assert_eq(_router.mode, CommandRouter.Mode.MENU)


func test_returning_user_sees_progress_on_the_menu_at_login() -> void:
	_login()
	_router.handle("1")
	_score_once()
	_router.handle("leave")
	_router.handle("logout")
	var out := _router.handle("dana")
	assert_string_contains(_text(out), "Welcome back")
	assert_string_contains(_text(out), "XP")


func test_choosing_a_played_track_mentions_what_is_due() -> void:
	var later := Support.T0 + 3 * 86400
	_login()
	_router.handle("1")
	_score_once()
	_router.handle("leave")
	_router.handle("menu")
	_router.clock = func() -> int: return later
	var out := _router.handle("1")
	assert_string_contains(_text(out), "1 due for review")


func test_help_at_home_lists_menu_and_quit_saves_from_the_menu() -> void:
	_login()
	_router.handle("1")
	assert_string_contains(_text(_router.handle("help")), "menu")
	_router.handle("menu")
	_router.handle("quit")
	assert_true(_router.want_quit)
	assert_true(FileAccess.file_exists(_profiles.path_join("dana.json")))


func test_a_v1_save_opens_straight_into_the_legacy_track_with_its_progress() -> void:
	var old := {"version": 1, "username": "old", "created": 1, "last_seen": 1, "sessions": 3,
			"xp": {"total": 40, "1": 40}, "concepts": {}, "items": {}, "rounds": [], "best_streak": 2}
	Support.write_json(_profiles.path_join("old.json"), old)
	_router = _make_router()
	_router.handle("old")
	assert_eq(_router.mode, CommandRouter.Mode.MENU)
	assert_string_contains(_menu_model().progress_text("alpha"), "40 XP")
	_router.handle("1")
	assert_eq(Mastery.total_xp(_router.profile), 40)
	assert_string_contains(_text(_router.handle("status")), "best streak  2")
	assert_true(FileAccess.file_exists(_profiles.path_join("old.v1.bak")))


# --- one pack, no catalog ------------------------------------------------

func test_without_a_catalog_there_is_no_menu_and_menu_says_so() -> void:
	var router := CommandRouter.new(ProfileStore.new(_profiles), Pack.load_dir(_packs.path_join("alpha")))
	router.handle("new lee")
	assert_eq(router.mode, CommandRouter.Mode.HOME)
	assert_eq(router.pack.id, "alpha")
	assert_eq(router.profile.track, "alpha")
	assert_string_contains(_text(router.handle("menu")), "only one track")
	assert_eq(router.mode, CommandRouter.Mode.HOME)
	router.handle("logout")
	assert_eq(router.pack.id, "alpha", "a single-pack router keeps its pack across logout")


# --- arrival summary ---------------------------------------------------

func test_a_new_learner_arrives_with_a_progress_line_and_the_length_picker() -> void:
	_login()
	var text := _text(_router.handle("1"))
	assert_string_contains(text, "Script Kiddie | 0 XP")
	assert_string_contains(text, "How many questions?")
	assert_string_contains(text, "[10]")
	assert_string_contains(text, "Enter starts.")
	assert_false(text.contains(" due"), "nothing can be due for a new learner")
	assert_false(text.contains("breach"), "the home screen does not name the old commands")


func test_the_progress_line_ends_with_the_due_count() -> void:
	var later := Support.T0 + 3 * 86400
	_login()
	_router.handle("1")
	_score_once()
	_router.handle("leave")
	_router.handle("menu")
	_router.clock = func() -> int: return later
	var lines := _router.handle("1")
	var summary := ""
	for l in lines:
		if (l.get("t", "") as String).contains(" due for review"):
			summary = l["t"]
	assert_true(summary.begins_with("Script Kiddie | "), summary)
	assert_true(summary.ends_with(" | 1 due for review"), summary)


func test_a_returning_learner_with_nothing_due_sees_no_due_count() -> void:
	_login()
	_router.handle("1")
	_score_once()
	_router.handle("leave")
	_router.handle("menu")
	var text := _text(_router.handle("1"))
	assert_false(text.contains(" due for review"), text)
	assert_string_contains(text, "How many questions?")


func test_the_progress_line_xp_grows_after_scoring() -> void:
	_login()
	var before := _router.handle("1")
	_router.handle("leave")
	_score_once()
	_router.handle("leave")
	_router.handle("menu")
	var after := _router.handle("1")
	var re := RegEx.create_from_string("(\\d+) XP")
	var a := re.search(_text(before))
	var b := re.search(_text(after))
	assert_not_null(a)
	assert_not_null(b)
	assert_gt(int(b.get_string(1)), int(a.get_string(1)))
