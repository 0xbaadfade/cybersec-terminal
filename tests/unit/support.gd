extends RefCounted
## Shared helpers for the suite (not a test: GUT only runs test_*.gd).
## Everything goes in throwaway directories under user://.

static func make_dir() -> String:
	var path := "user://t_%d_%d" % [Time.get_ticks_usec(), randi()]
	DirAccess.make_dir_recursive_absolute(path)
	return path


static func remove_dir(path: String) -> void:
	for d in DirAccess.get_directories_at(path):
		remove_dir(path.path_join(d))
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path.path_join(f)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## Copies the real Security+ pack into `dest` without the practice-book items
## (`items/*-book.json`). The journey tests were written against the hand-made sample
## content (domain 4 only); they test the engine, not how much content the pack has.
static func copy_real_pack_without_book_items(dest: String) -> void:
	_copy_dir("res://packs/secplus-sy0-701", dest)


static func _copy_dir(src: String, dest: String) -> void:
	DirAccess.make_dir_recursive_absolute(dest)
	for d in DirAccess.get_directories_at(src):
		_copy_dir(src.path_join(d), dest.path_join(d))
	for f in DirAccess.get_files_at(src):
		if f.ends_with("-book.json") or f.ends_with(".uid") or f.ends_with(".import"):
			continue
		write_text(dest.path_join(f), FileAccess.get_file_as_string(src.path_join(f)))


static func write_text(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


static func write_json(path: String, data: Variant) -> void:
	write_text(path, JSON.stringify(data, "\t"))


## A minimal valid pack in `root`, with `items` as items/test.json.
static func write_pack(root: String, items: Array) -> void:
	write_json(root.path_join("pack.json"), {
		"id": "test", "title": "Test Pack", "short": "TEST", "version": 1,
		"domains": [{"id": "1", "title": "One", "weight": 100}],
		"objectives": [{"id": "1.1", "domain": "1", "title": "First",
				"concepts": [{"id": "1.1.a", "title": "Alpha"}, {"id": "1.1.b", "title": "Beta"}]}],
	})
	write_json(root.path_join("items/test.json"), items)


static func good_item(item_id: String = "t-1") -> Dictionary:
	return {
		"id": item_id, "type": "mcq", "concept_ids": ["1.1.a"], "difficulty": 1,
		"reviewed_by": "human", "stem": "Pick b.",
		"options": [{"id": "a", "text": "A"}, {"id": "b", "text": "B"}, {"id": "c", "text": "C"}],
		"answer": ["b"], "explain": "Because b.",
	}


## An item with options a-d. mcq answers ["b"]; multi answers ["a", "c"].
static func make_item(item_id: String, concept: String, type: String = "mcq",
		reviewed: bool = true, difficulty: int = 1) -> Dictionary:
	var item := {
		"id": item_id, "type": type, "concept_ids": [concept], "difficulty": difficulty,
		"stem": "Stem of %s." % item_id,
		"options": [{"id": "a", "text": "Alpha", "why": "Alpha is wrong."}, {"id": "b", "text": "Bravo"},
				{"id": "c", "text": "Charlie"}, {"id": "d", "text": "Delta"}],
		"answer": ["b"] if type == "mcq" else ["a", "c"],
		"explain": "Explanation of %s." % item_id,
	}
	if reviewed:
		item["reviewed_by"] = "human"
	return item


## Two domains; 1.1 has concepts a,b,c; 1.2 has d,e; 1.3 has none; 2.1 has f.
## Two items per concept (one reviewed by a person, one not reviewed) unless `items` is given.
static func write_wide_pack(root: String, items: Array = []) -> void:
	write_json(root.path_join("pack.json"), {
		"id": "wide", "title": "Wide Pack", "short": "WIDE", "version": 1,
		"domains": [{"id": "1", "title": "One", "weight": 60}, {"id": "2", "title": "Two", "weight": 40}],
		"objectives": [
			{"id": "1.1", "domain": "1", "title": "First", "concepts": [
				{"id": "1.1.a", "title": "Alpha"}, {"id": "1.1.b", "title": "Beta"}, {"id": "1.1.c", "title": "Gamma"}]},
			{"id": "1.2", "domain": "1", "title": "Second", "concepts": [
				{"id": "1.2.d", "title": "Delta"}, {"id": "1.2.e", "title": "Epsilon"}]},
			{"id": "1.3", "domain": "1", "title": "Third, empty"},
			{"id": "2.1", "domain": "2", "title": "Other domain", "concepts": [{"id": "2.1.f", "title": "Zeta"}]},
		],
	})
	if items.is_empty():
		for c in ["1.1.a", "1.1.b", "1.1.c", "1.2.d", "1.2.e", "2.1.f"]:
			items.append(make_item("%s-1" % c, c, "mcq", true))
			items.append(make_item("%s-2" % c, c, "multi", false))
	write_json(root.path_join("items/all.json"), items)


const DEMO_ARTIFACT := "# demo config\nPort 22\nRootLogin yes\nAuth weak\nCipher des\nDebug off\n"
const REASONS: Array = [
	{"key": "weak-auth", "label": "weak authentication"},
	{"key": "excess-privilege", "label": "excess privilege"},
	{"key": "exposure", "label": "needless exposure"},
	{"key": "weak-crypto", "label": "weak or missing encryption"},
]


## An evidence item over DEMO_ARTIFACT: line 3 excess-privilege, line 4
## weak-auth, line 5 weak-crypto (exposure also accepted); line 2 is a decoy.
static func evidence_item(item_id: String, concept: String, difficulty: int = 1) -> Dictionary:
	return {
		"id": item_id, "type": "evidence", "concept_ids": [concept], "difficulty": difficulty,
		"stem": "Flag what weakens %s." % item_id,
		"artifact": {"file": "artifacts/demo.txt", "kind": "config", "title": "demo: config"},
		"flaws": [
			{"line": 3, "match": "RootLogin yes", "reason": "excess-privilege", "explain": "Root login is excess privilege."},
			{"line": 4, "match": "Auth weak", "reason": "weak-auth", "explain": "Weak auth is guessable."},
			{"line": 5, "match": "Cipher des", "reasons": ["weak-crypto", "exposure"], "explain": "DES is broken."},
		],
		"decoys": [{"line": 2, "match": "Port 22", "explain": "The default port is fine."}],
		"explain": "Overall lesson of %s." % item_id,
	}


## A pack with concepts a, b, c under 1.1, the evidence reason menu, the demo
## artifact at artifacts/demo.txt, and `items` as items/all.json. `meta` entries
## replace pack.json keys (a null value removes the key).
static func write_evidence_pack(root: String, items: Array, artifact_text: String = DEMO_ARTIFACT,
		meta: Dictionary = {}) -> void:
	var pack_json := {
		"id": "ev", "title": "Evidence Pack", "short": "EV", "version": 1,
		"domains": [{"id": "1", "title": "One", "weight": 100}],
		"objectives": [{"id": "1.1", "domain": "1", "title": "First", "concepts": [
			{"id": "1.1.a", "title": "Alpha"}, {"id": "1.1.b", "title": "Beta"}, {"id": "1.1.c", "title": "Gamma"}]}],
		"evidence_reasons": REASONS,
	}
	for k in meta:
		if meta[k] == null:
			pack_json.erase(k)
		else:
			pack_json[k] = meta[k]
	write_json(root.path_join("pack.json"), pack_json)
	write_json(root.path_join("items/all.json"), items)
	write_text(root.path_join("artifacts/demo.txt"), artifact_text)


## A small lab: you (analyst-ws .50), a router .1 (os network), web-03 .10,
## and printer .30 which drops ping. Domain corp.local; alias www -> web-03.
static func demo_lab(lab_id: String = "lab-a") -> Dictionary:
	return {
		"id": lab_id, "title": "Demo lab", "seed": 7,
		"you": {"ip": "10.20.0.50", "name": "analyst-ws", "os": "linux", "user": "analyst"},
		"network": {"cidr": "10.20.0.0/24", "gateway": "10.20.0.1", "dns": "10.20.0.2", "domain": "corp.local"},
		"hosts": [
			{"ip": "10.20.0.1", "name": "fw-01", "os": "network", "latency_ms": 0.3,
					"ports": [{"port": 22, "proto": "tcp", "state": "open", "service": "ssh"}]},
			{"ip": "10.20.0.2", "name": "dns-01", "os": "linux", "latency_ms": 0.4},
			{"ip": "10.20.0.10", "name": "web-03", "os": "linux", "latency_ms": 0.4,
					"ports": [{"port": 23, "proto": "tcp", "state": "open", "service": "telnet"}]},
			{"ip": "10.20.0.30", "name": "printer-01", "os": "network", "latency_ms": 1.8, "icmp": false},
		],
		"dns": [{"name": "www.corp.local", "a": "10.20.0.10"}],
		"files": {"analyst-ws": {"notes.txt": "Web tier: web-03, printer-01.\nPrinter: ICMP is disabled.\nscope 10.20.0.0/24\n",
				"scope.txt": "Authorised scope only.\n"}},
	}


static func demo_tools() -> Dictionary:
	return {
		"ping": {"summary": "Send ICMP echo requests.", "usage": "ping [-c N] <host>",
				"flags": [["-c N", "stop after N"]], "concepts": ["1.1.a"], "note": "No reply is not proof of down."},
		"grep": {"summary": "Filter lines."},
	}


## A pack with concepts a, b, c under 1.1, the demo lab at labs/lab-a.json,
## tools.json, and `items` as items/all.json.
static func write_lab_pack(root: String, items: Array, lab: Dictionary = {}) -> void:
	write_evidence_pack(root, items)
	write_json(root.path_join("labs/lab-a.json"), lab if not lab.is_empty() else demo_lab())
	write_json(root.path_join("tools.json"), demo_tools())


## A terminal item on the demo lab; the answer is the printer.
static func terminal_item(item_id: String, concept: String, difficulty: int = 1) -> Dictionary:
	return {
		"id": item_id, "type": "terminal", "concept_ids": [concept], "difficulty": difficulty,
		"stem": "Which host drops ping? (%s)" % item_id,
		"lab": "lab-a", "answer": {"accept": ["10.20.0.30", "printer-01"]},
		"explain": "printer-01 drops ICMP (%s)." % item_id,
	}


## A match item: categories x, y, z; four pairs (one x, two y, three z, four x).
static func match_item(item_id: String, concept: String, difficulty: int = 1) -> Dictionary:
	return {
		"id": item_id, "type": "match", "concept_ids": [concept], "difficulty": difficulty,
		"stem": "Match each case (%s)." % item_id,
		"categories": [{"id": "x", "text": "Xray"}, {"id": "y", "text": "Yankee"}, {"id": "z", "text": "Zulu"}],
		"pairs": [
			{"text": "Case one", "category": "x", "explain": "One is an Xray."},
			{"text": "Case two", "category": "y", "explain": "Two is a Yankee."},
			{"text": "Case three", "category": "z", "explain": "Three is a Zulu."},
			{"text": "Case four", "category": "x", "explain": "Four is an Xray."},
		],
		"explain": "Overall lesson of %s." % item_id,
	}


## An order item: four steps, written in the right order.
static func order_item(item_id: String, concept: String, difficulty: int = 1) -> Dictionary:
	return {
		"id": item_id, "type": "order", "concept_ids": [concept], "difficulty": difficulty,
		"stem": "Put these in order (%s)." % item_id,
		"steps": [
			{"text": "Step first", "explain": "First comes first."},
			{"text": "Step second", "explain": "Second follows."},
			{"text": "Step third", "explain": "Third follows."},
			{"text": "Step fourth", "explain": "Fourth is last."},
		],
		"explain": "Overall lesson of %s." % item_id,
	}


## The wide pack (two domains, concepts a b c d e f) with the evidence reason
## menu and demo artifact, a full exam of `questions` that asks for `pbqs` PBQs,
## `per_concept` ordinary items per concept and `per_type` PBQ items of each type
## (evidence on a/d/f, match on b/e/a, order on c/f/b).
static func write_exam_pbq_pack(root: String, questions: int = 20, pbqs: int = 4, per_concept: int = 8,
		per_type: int = 3) -> void:
	var items: Array = []
	for c in ["1.1.a", "1.1.b", "1.1.c", "1.2.d", "1.2.e", "2.1.f"]:
		for k in per_concept:
			items.append(make_item("%s-%d" % [c, k], c, "mcq" if k % 2 == 0 else "multi", true))
	var ev := ["1.1.a", "1.2.d", "2.1.f"]
	var mt := ["1.1.b", "1.2.e", "1.1.a"]
	var od := ["1.1.c", "2.1.f", "1.1.b"]
	for k in per_type:
		items.append(evidence_item("ev-%d" % k, ev[k % 3], 2))
		items.append(match_item("mt-%d" % k, mt[k % 3], 2))
		items.append(order_item("or-%d" % k, od[k % 3], 2))
	write_wide_pack(root, items)
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("pack.json")))
	meta["exam"] = {"questions": questions, "minutes": questions, "pass_score": 750, "score_range": [100, 900], "pbqs": pbqs}
	meta["evidence_reasons"] = REASONS
	write_json(root.path_join("pack.json"), meta)
	write_text(root.path_join("artifacts/demo.txt"), DEMO_ARTIFACT)


## A fixed clock for tests: midnight UTC of day 20000.
const T0 := 1728000000
