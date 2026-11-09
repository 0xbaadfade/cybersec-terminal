class_name Scheduler
extends RefCounted
## Chooses the items for a round (README "Round selection"). Headless and
## deterministic for a given RandomNumberGenerator seed and clock.
##
## Returns entries {"item", "concept", "kind"}; kind is "review" (was due),
## "new" (never seen) or "practice" (a top-up, not yet due).
##
## Short round: when the due, new and practice picks do not fill `round_size`
## (a learner who has seen nothing), each new concept is asked a second time
## with a different item, after every concept has been met once. A concept with
## one item gets no second question.
##
## Performance-based items (Pack.PBQ_TYPES) are never picked for a round: evidence,
## match and order questions appear only in the full exam (exam_pbqs). The one
## exception is a skill pack (`rounds_include_labs`), whose rounds may hold
## terminal missions (Pack.round_item).
##
## Sized round (`size` > 0, from the setup screen): exactly that many entries
## when the pack has them. Review, new and practice come first as above (new
## concepts may reach half the size); what is still missing is filled with
## second items, then with further items of every concept in scope, in
## spaced-repetition order.

## Exam simulation (`exam_pick`): a full exam first holds a few PBQs (`exam_pbqs`),
## then mcq and multi items from every node, open or
## locked, with the domains' share of questions following their weights
## (largest remainder). Concepts are drawn round-robin so one idea does not
## fill a domain, an item appears at most once, and a domain that runs out of
## items hands its shortfall to the heaviest domains that still have some.

const KIND_ORDER := {"review": 0, "practice": 1, "new": 2}


## A concept a round can ask about: it has an ordinary (non-PBQ) item.
static func servable(pack: Pack, concept_id: String) -> bool:
	for item in pack.items_for_concept(concept_id):
		if pack.round_item(item):
			return true
	return false


## Concepts in `scope` (objective ids) that have items, in pack order.
static func scope_concepts(pack: Pack, scope: Array) -> Array:
	var out: Array = []
	for cid in pack.concepts:
		if scope.has(pack.concepts[cid]["objective"]) and servable(pack, cid):
			out.append(cid)
	return out


static func due_concepts(pack: Pack, profile: Profile, scope: Array, today: int) -> Array:
	var due: Array = []
	for cid in scope_concepts(pack, scope):
		if Mastery.is_due(profile, cid, today):
			due.append(cid)
	due.sort_custom(func(a: String, b: String) -> bool: return _by_box_then_due(profile, a, b))
	return due


static func pick(pack: Pack, profile: Profile, due_scope: Array, new_scope: Array,
		rules: Rules, now: int, rng: RandomNumberGenerator, size: int = -1) -> Array:
	var today := Mastery.day_of(now)
	var round_size := size if size > 0 else rules.round_size
	var max_new := maxi(rules.max_new, round_size / 2) if size > 0 else rules.max_new
	var chosen: Array = []  # [concept id, kind]
	var taken: Dictionary = {}

	for cid in due_concepts(pack, profile, due_scope, today):
		if chosen.size() >= round_size:
			break
		chosen.append([cid, "review"])
		taken[cid] = true

	var new_count := 0
	for objective_id in new_scope:
		for cid in scope_concepts(pack, [objective_id]):
			if chosen.size() >= round_size or new_count >= max_new:
				break
			if Mastery.seen(profile, cid) == 0 and not taken.has(cid):
				chosen.append([cid, "new"])
				taken[cid] = true
				new_count += 1

	if chosen.size() < round_size:
		var rest: Array = []
		for cid in scope_concepts(pack, due_scope):
			if not taken.has(cid) and Mastery.seen(profile, cid) > 0:
				rest.append(cid)
		rest.sort_custom(func(a: String, b: String) -> bool: return _by_box_then_due(profile, a, b))
		for cid in rest:
			if chosen.size() >= round_size:
				break
			chosen.append([cid, "practice"])
			taken[cid] = true

	var entries: Array = []
	var used_items: Dictionary = {}
	var served: Dictionary = {}  # concept id -> true once its first item is in
	for pair in chosen:
		var item_id := _choose_item(pack, profile, pair[0], used_items, rng)
		if item_id != "":
			used_items[item_id] = true
			served[pair[0]] = true
			entries.append({"item": item_id, "concept": pair[0], "kind": pair[1]})
	_shuffle(entries, rng)
	var short := round_size - entries.size()
	var seconds: Array = []
	for pair in chosen:
		if seconds.size() >= short:
			break
		if pair[1] != "new" or not served.has(pair[0]):
			continue
		var second_id := _choose_item(pack, profile, pair[0], used_items, rng)
		if second_id != "":
			used_items[second_id] = true
			seconds.append({"item": second_id, "concept": pair[0], "kind": "practice"})
	_shuffle(seconds, rng)
	entries.append_array(seconds)
	if size > 0 and entries.size() < size:
		entries.append_array(_fill(pack, profile, due_scope, size - entries.size(), used_items, rng))
	return entries


## Further items for a sized round that review, new and practice left short:
## one unused item per concept per pass, concepts in spaced-repetition order
## (weakest and longest-unseen first), until `count` are found or none are left.
static func _fill(pack: Pack, profile: Profile, scope: Array, count: int, used: Dictionary,
		rng: RandomNumberGenerator) -> Array:
	var pool: Array = scope_concepts(pack, scope)
	pool.sort_custom(func(a: String, b: String) -> bool: return _by_box_then_due(profile, a, b))
	var out: Array = []
	var progressed := true
	while out.size() < count and progressed:
		progressed = false
		for cid in pool:
			if out.size() >= count:
				break
			var id := _choose_item(pack, profile, cid, used, rng)
			if id == "":
				continue
			used[id] = true
			out.append({"item": id, "concept": cid, "kind": "practice"})
			progressed = true
	_shuffle(out, rng)
	return out


static func _by_box_then_due(profile: Profile, a: String, b: String) -> bool:
	var ba := Mastery.box(profile, a)
	var bb := Mastery.box(profile, b)
	if ba != bb:
		return ba < bb
	var da := Mastery.due_day(profile, a)
	var db := Mastery.due_day(profile, b)
	if da != db:
		return da < db
	return a < b


## How many of `n` exam questions each domain gets: the weights' share, with
## the leftover questions going to the largest remainders (ties: pack order).
## {domain id -> count}.
static func exam_quotas(pack: Pack, n: int) -> Dictionary:
	var total := 0.0
	for d in pack.domains:
		total += float(d["weight"])
	var quotas: Dictionary = {}
	var rems: Array = []
	var given := 0
	for i in pack.domains.size():
		var d: Dictionary = pack.domains[i]
		var exact := float(n) / pack.domains.size() if total <= 0.0 else float(n) * float(d["weight"]) / total
		quotas[d["id"]] = int(floor(exact))
		given += int(quotas[d["id"]])
		rems.append({"id": d["id"], "rem": exact - floor(exact), "i": i})
	rems.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["i"] < b["i"] if is_equal_approx(a["rem"], b["rem"]) else a["rem"] > b["rem"])
	for k in range(n - given):
		quotas[rems[k % rems.size()]["id"]] += 1
	return quotas


## Up to `n` exam entries {"item", "concept", "domain"}, mixed across domains.
## Fewer than `n` come back only when the pack has fewer usable items.
## `pbq_count` > 0 puts that many PBQs (see exam_pbqs) FIRST, in a shuffled
## order; they count toward `n`, and each takes one place from its own domain's
## quota (from the heaviest domain when its own has none left). The rest are
## ordinary questions, mixed.
static func exam_pick(pack: Pack, profile: Profile, n: int, rng: RandomNumberGenerator,
		pbq_count: int = 0) -> Array:
	var pbqs: Array = exam_pbqs(pack, profile, mini(pbq_count, n), rng) if pbq_count > 0 else []
	var quotas := exam_quotas(pack, n)
	for e in pbqs:
		if int(quotas.get(e["domain"], 0)) > 0:
			quotas[e["domain"]] -= 1
		else:
			var heaviest := ""
			for d in pack.domains:
				if int(quotas[d["id"]]) > 0 and (heaviest == "" or float(d["weight"]) > _weight_of(pack, heaviest)):
					heaviest = d["id"]
			if heaviest != "":
				quotas[heaviest] -= 1
	var pools: Dictionary = {}  # domain id -> concept ids with an ordinary item
	for d in pack.domains:
		pools[d["id"]] = []
	for cid in pack.concepts:
		var did := pack.domain_of_concept(cid)
		if not pools.has(did):
			continue
		for item in pack.items_for_concept(cid):
			if not Pack.is_pbq(item):
				pools[did].append(cid)
				break
	var used: Dictionary = {}
	for e in pbqs:
		used[e["item"]] = true
	var entries: Array = []
	var short := 0
	for d in pack.domains:
		_shuffle(pools[d["id"]], rng)
		var got := _exam_draw(pack, profile, pools[d["id"]], d["id"], quotas[d["id"]], used, rng)
		entries.append_array(got)
		short += int(quotas[d["id"]]) - got.size()
	if short > 0:
		var heaviest: Array = pack.domains.duplicate()
		heaviest.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["weight"]) > float(b["weight"]))
		for d in heaviest:
			if short <= 0:
				break
			var more := _exam_draw(pack, profile, pools[d["id"]], d["id"], short, used, rng)
			entries.append_array(more)
			short -= more.size()
	_shuffle(entries, rng)
	return pbqs + entries


static func _weight_of(pack: Pack, domain_id: String) -> float:
	for d in pack.domains:
		if d["id"] == domain_id:
			return float(d["weight"])
	return 0.0


## `count` PBQ entries {"item", "concept", "domain"} for a full exam: one of each
## type in Pack.EXAM_PBQ_TYPES that the pack has, then more of a random type that
## still has items, until `count` (or no items are left). Within a type the item
## this learner met least recently comes first (never met first, then fewest
## times, then a seeded random tie-break); an item whose concept is already in the
## exam is skipped while another is available. The result is shuffled.
static func exam_pbqs(pack: Pack, profile: Profile, count: int, rng: RandomNumberGenerator) -> Array:
	var pools: Dictionary = {}  # type -> candidate items, best first
	for t in Pack.EXAM_PBQ_TYPES:
		var cands: Array = []
		for item in pack.items.values():
			if item["type"] != t:
				continue
			var rec := Mastery.item_record(profile, item["id"])
			cands.append({"item": item, "last": int(rec.get("last_day", -1)) if int(rec.get("seen", 0)) > 0 else -1,
					"seen": int(rec.get("seen", 0)), "jitter": rng.randf()})
		cands.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
			for k in ["last", "seen", "jitter"]:
				if x[k] != y[k]:
					return x[k] < y[k]
			return x["item"]["id"] < y["item"]["id"])
		pools[t] = cands
	var slots: Array = []  # the type of each PBQ
	for t in Pack.EXAM_PBQ_TYPES:
		if not pools[t].is_empty() and slots.size() < count:
			slots.append(t)
	while slots.size() < count:
		var left: Array = []
		for t in Pack.EXAM_PBQ_TYPES:
			if pools[t].size() > slots.count(t):
				left.append(t)
		if left.is_empty():
			break
		slots.append(left[rng.randi_range(0, left.size() - 1)])
	var out: Array = []
	var concepts: Dictionary = {}
	for t in slots:
		var pick := 0
		for k in pools[t].size():
			if not concepts.has(pools[t][k]["item"]["concept_ids"][0]):
				pick = k
				break
		var item: Dictionary = pools[t][pick]["item"]
		pools[t].remove_at(pick)
		var cid: String = item["concept_ids"][0]
		concepts[cid] = true
		out.append({"item": item["id"], "concept": cid, "domain": pack.domain_of_concept(cid)})
	_shuffle(out, rng)
	return out


## Round-robin over `pool`, one unused ordinary item per concept per pass.
static func _exam_draw(pack: Pack, profile: Profile, pool: Array, domain_id: String, count: int,
		used: Dictionary, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var progressed := true
	while out.size() < count and progressed:
		progressed = false
		for cid in pool:
			if out.size() >= count:
				break
			var id := _choose_item(pack, profile, cid, used, rng, true)
			if id == "":
				continue
			used[id] = true
			out.append({"item": id, "concept": cid, "domain": domain_id})
			progressed = true
	return out


## Human-reviewed, then AI-reviewed, then unreviewed, then the item served longest ago (never served
## first), then fewest times served, then a seeded random tie-break. Never a
## performance-based item, except a terminal mission for a skill pack's round
## (`ordinary_only` keeps the exam to ordinary questions).
static func _choose_item(pack: Pack, profile: Profile, concept_id: String,
		used: Dictionary, rng: RandomNumberGenerator, ordinary_only: bool = false) -> String:
	var cands: Array = []
	for item in pack.items_for_concept(concept_id):
		if used.has(item["id"]) or (Pack.is_pbq(item) if ordinary_only else not pack.round_item(item)):
			continue
		var rec := Mastery.item_record(profile, item["id"])
		cands.append({
			"id": item["id"],
			"unreviewed": Pack.review_rank(item),
			"last": int(rec.get("last_day", -1)) if int(rec.get("seen", 0)) > 0 else -1,
			"seen": int(rec.get("seen", 0)),
			"jitter": rng.randf(),
		})
	if cands.is_empty():
		return ""
	cands.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		for k in ["unreviewed", "last", "seen", "jitter"]:
			if x[k] != y[k]:
				return x[k] < y[k]
		return x["id"] < y["id"])
	return cands[0]["id"]


static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
