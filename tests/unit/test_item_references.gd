extends GutTest
## Optional `explain` and `references` on items: the validator, the display lines, and where they are shown
## (answer feedback, the terminal debrief shares the same helpers, the exam review).

const Support := preload("res://tests/unit/support.gd")

var _dirs: Array = []
var _now := Support.T0


func after_each() -> void:
	for d in _dirs:
		Support.remove_dir(d)
	_dirs.clear()


func _pack_with(items: Array) -> Pack:
	var root := Support.make_dir()
	_dirs.append(root)
	Support.write_pack(root, items)
	return Pack.load_dir(root)


func _item_with(changes: Dictionary) -> Dictionary:
	var item := Support.good_item()
	item.merge(changes, true)
	return item


func _errors_text(pack: Pack) -> String:
	return "\n".join(pack.errors)


func _text(lines: Array) -> String:
	return "\n".join(lines.map(func(l): return l.get("t", "")))


# --- the validator ---------------------------------------------------------------------------

func test_text_and_object_references_are_accepted() -> void:
	var refs := ["NIST SP 800-63B, 5.1.1", {"title": "RFC 9110"}, {"title": "OWASP", "url": "https://owasp.org/"},
			{"title": "Plain http", "url": "http://example.com/x"}]
	var pack := _pack_with([_item_with({"references": refs})])
	assert_true(pack.ok(), _errors_text(pack))
	assert_eq(pack.items.size(), 1)


func test_an_empty_references_list_is_fine() -> void:
	var pack := _pack_with([_item_with({"references": []})])
	assert_true(pack.ok(), _errors_text(pack))


func test_references_must_be_a_list() -> void:
	var pack := _pack_with([_item_with({"references": "NIST"})])
	assert_string_contains(_errors_text(pack), "'references' must be a list")
	assert_eq(pack.items.size(), 0)


func test_too_many_references_are_rejected() -> void:
	var refs: Array = []
	for i in Pack.MAX_REFERENCES + 1:
		refs.append("source %d" % i)
	var pack := _pack_with([_item_with({"references": refs})])
	assert_string_contains(_errors_text(pack), "at most %d entries" % Pack.MAX_REFERENCES)


func test_bad_reference_entries_are_rejected() -> void:
	var cases := {
		"empty line": ["  "],
		"object without a title": [{"url": "https://example.com"}],
		"object with an empty title": [{"title": ""}],
		"url that is not http(s)": [{"title": "x", "url": "javascript:alert(1)"}],
		"url that is not text": [{"title": "x", "url": 5}],
		"entry that is a number": [7],
	}
	for name in cases:
		var pack := _pack_with([_item_with({"references": cases[name]})])
		assert_false(pack.ok(), name)
		assert_eq(pack.items.size(), 0, "%s: the item must not be served" % name)


func test_empty_explain_counts_as_none() -> void:
	var pack := _pack_with([_item_with({"explain": "   "}), _item_with({"id": "t-2"})])
	assert_true(pack.ok(), _errors_text(pack))
	assert_eq(pack.items_without_explain, 1)
	assert_eq(Pack.explain_of(pack.items["t-1"]), "")
	assert_eq(Pack.explain_of(pack.items["t-2"]), "Because b.")


# --- the display lines -----------------------------------------------------------------------

func test_reference_lines_show_a_header_then_one_row_each() -> void:
	var item := _item_with({"references": ["A book", {"title": "A page", "url": "https://example.com/p"}, {"title": "No link"}]})
	assert_eq(Pack.reference_lines(item), ["References:", "  - A book", "  - A page (https://example.com/p)", "  - No link"])


func test_reference_lines_are_empty_without_references_and_skip_bad_entries() -> void:
	assert_eq(Pack.reference_lines(Support.good_item()), [])
	assert_eq(Pack.reference_lines(_item_with({"references": []})), [])
	assert_eq(Pack.reference_lines(_item_with({"references": [5, {"url": "https://x.example"}]})), [],
			"nothing usable means no header either")
	assert_eq(Pack.reference_lines(_item_with({"references": [5, "kept"]})), ["References:", "  - kept"])


# --- shown to the learner --------------------------------------------------------------------

func _router_for(items: Array) -> CommandRouter:
	var root := Support.make_dir()
	_dirs.append(root)
	Support.write_wide_pack(root, items)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var store := ProfileStore.new(root.path_join("saves"))
	var router := CommandRouter.new(store, Pack.load_dir(root), null, rng, func() -> int: return _now)
	router.handle("new dana")
	return router


func _answer(router: CommandRouter, correct: bool) -> String:
	var answer: Array = router.current_round.item()["answer"]
	var letters := ""
	for o in router.current_round.options():
		if answer.has(o["id"]) == correct:
			letters += o["letter"]
	return _text(router.handle(letters if correct else letters[0]))


func _mcq(item_id: String, changes: Dictionary) -> Dictionary:
	var item := Support.make_item(item_id, "1.1.a")
	item.merge(changes, true)
	return item


func test_feedback_shows_the_explanation_then_the_references() -> void:
	var item := _mcq("r-1", {"references": ["NIST SP 800-63B"]})
	var router := _router_for([item])
	router.handle("breach 1.1")
	var text := _answer(router, true)
	assert_string_contains(text, "Explanation of r-1.")
	assert_string_contains(text, "References:")
	assert_string_contains(text, "  - NIST SP 800-63B")
	assert_true(text.find("Explanation of r-1.") < text.find("References:"), "references come after the explanation")


func test_an_item_with_no_explanation_still_gives_feedback_and_its_references() -> void:
	var item := _mcq("r-2", {"references": [{"title": "RFC 9110", "url": "https://www.rfc-editor.org/rfc/rfc9110"}]})
	item.erase("explain")
	var router := _router_for([item])
	router.handle("breach 1.1")
	var text := _answer(router, false)
	assert_string_contains(text, "A is wrong: Alpha is wrong.", "the per-option why still shows")
	assert_string_contains(text, "  - RFC 9110 (https://www.rfc-editor.org/rfc/rfc9110)")
	assert_false(text.contains("Explanation of"), "no explanation was written")


func test_an_item_with_neither_shows_no_references_block() -> void:
	var item := _mcq("r-3", {})
	item.erase("explain")
	var router := _router_for([item])
	router.handle("breach 1.1")
	var text := _answer(router, true)
	assert_false(text.contains("References:"))
	assert_true(text.length() > 0)


func test_the_exam_review_shows_references_and_copes_with_no_explanation() -> void:
	var root := Support.make_dir()
	_dirs.append(root)
	Support.write_exam_pbq_pack(root, 20, 4, 8, 3)
	var path := root.path_join("items/all.json")
	var items: Array = JSON.parse_string(FileAccess.get_file_as_string(path))
	for it in items:
		if Pack.PBQ_TYPES.has(it["type"]):
			it.erase("explain")
			it["references"] = ["Source for %s" % it["id"]]
	Support.write_json(path, items)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var router := CommandRouter.new(ProfileStore.new(root.path_join("saves")), Pack.load_dir(root), null, rng,
			func() -> int: return _now)
	router.handle("new dana")
	router.handle("exam")
	var text := _text(PbqScreen.review(router.exam))
	assert_string_contains(text, "Hands-on questions: what each one was after")
	assert_string_contains(text, "References:")
	assert_string_contains(text, "Source for ")
