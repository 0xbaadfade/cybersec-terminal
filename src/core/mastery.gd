class_name Mastery
extends RefCounted
## Per-topic mastery and XP, stored in the Profile (README "Mastery and scheduling" and "Shared bank plan"). Mastery is
## keyed by topic (`wireless.sae`) and shared by every track: answering SAE in one pack counts in the other. XP, rounds and
## streaks stay per track. A pack concept is read through its topics (`*_of`): its tier is the weakest of them.
## Stateless: every function takes the profile. Numbers read back from disk are floats, so reads go through int().

const TIER_UNSEEN := "unseen"
const TIER_SEEN := "seen"
const TIER_KNOWN := "known"
const TIER_MASTERED := "mastered"
## Weakest first: a concept is as strong as its weakest topic.
const TIER_ORDER: Array = [TIER_UNSEEN, TIER_SEEN, TIER_KNOWN, TIER_MASTERED]


static func day_of(now: int) -> int:
	return floori(now / 86400.0)


# --- one topic ------------------------------------------------------------

static func record(profile: Profile, topic: String) -> Dictionary:
	return profile.peek_topics().get(topic, {})


static func box(profile: Profile, topic: String) -> int:
	return int(record(profile, topic).get("box", 0))


static func seen(profile: Profile, topic: String) -> int:
	return int(record(profile, topic).get("seen", 0))


static func due_day(profile: Profile, topic: String) -> int:
	return int(record(profile, topic).get("due_day", 0))


static func tier(profile: Profile, topic: String) -> String:
	if seen(profile, topic) == 0:
		return TIER_UNSEEN
	var b := box(profile, topic)
	if b <= 1:
		return TIER_SEEN
	return TIER_KNOWN if b <= 3 else TIER_MASTERED


static func is_due(profile: Profile, topic: String, today: int) -> bool:
	return seen(profile, topic) > 0 and due_day(profile, topic) <= today


# --- a concept: its topics, weakest wins ----------------------------------------

## The lowest box among `topics` (0 when one is unseen or the list is empty).
static func box_of(profile: Profile, topics: Array) -> int:
	var out := -1
	for t in topics:
		out = box(profile, t) if out < 0 else mini(out, box(profile, t))
	return maxi(out, 0)


## The fewest answers given to any of `topics` (0 as soon as one is unseen).
static func seen_of(profile: Profile, topics: Array) -> int:
	var out := -1
	for t in topics:
		out = seen(profile, t) if out < 0 else mini(out, seen(profile, t))
	return maxi(out, 0)


## The earliest due day among the topics that have been seen (0 when none has).
static func due_day_of(profile: Profile, topics: Array) -> int:
	var out := -1
	for t in topics:
		if seen(profile, t) > 0:
			out = due_day(profile, t) if out < 0 else mini(out, due_day(profile, t))
	return maxi(out, 0)


## The weakest tier among `topics`.
static func tier_of(profile: Profile, topics: Array) -> String:
	var out := TIER_MASTERED
	for t in topics:
		if TIER_ORDER.find(tier(profile, t)) < TIER_ORDER.find(out):
			out = tier(profile, t)
	return out if not topics.is_empty() else TIER_UNSEEN


## True when any of `topics` has been seen and is due.
static func is_due_of(profile: Profile, topics: Array, today: int) -> bool:
	for t in topics:
		if is_due(profile, t, today):
			return true
	return false


## {"hits", "misses"} summed over `topics`.
static func totals_of(profile: Profile, topics: Array) -> Dictionary:
	var out := {"hits": 0, "misses": 0}
	for t in topics:
		out["hits"] += int(record(profile, t).get("hits", 0))
		out["misses"] += int(record(profile, t).get("misses", 0))
	return out


# --- items and answers ------------------------------------------------------

static func item_record(profile: Profile, item_id: String) -> Dictionary:
	return profile.peek_items().get(item_id, {})


## Apply one answer. credit 1: up a box, due after that box's interval.
## credit 0: back to box 1, due tomorrow. In between: box unchanged, due
## tomorrow. Every topic the item carries (`item["topics"]`) is updated.
static func apply(profile: Profile, item: Dictionary, credit: float, now: int, rules: Rules) -> void:
	var today := day_of(now)
	if profile.track != "":
		profile.progress()   # answering is playing: the active track gets its section, as before v3
	var topics := profile.topic_bucket()
	for tid in item.get("topics", []):
		var rec: Dictionary = topics.get(tid, {})
		var b := int(rec.get("box", 0))
		rec["seen"] = int(rec.get("seen", 0)) + 1
		if credit >= 1.0:
			b = mini(Rules.MAX_BOX, b + 1)
			rec["hits"] = int(rec.get("hits", 0)) + 1
			rec["due_day"] = today + rules.interval(b)
		else:
			rec["misses"] = int(rec.get("misses", 0)) + 1
			if credit <= 0.0:
				b = 1
			rec["due_day"] = today + maxi(1, rules.interval(1))
		rec["box"] = b
		rec["last_day"] = today
		topics[tid] = rec
	var items := profile.item_bucket()
	var irec: Dictionary = items.get(item["id"], {})
	irec["seen"] = int(irec.get("seen", 0)) + 1
	if credit >= 1.0:
		irec["correct"] = int(irec.get("correct", 0)) + 1
	else:
		irec["misses"] = int(irec.get("misses", 0)) + 1
	irec["last_day"] = today
	irec["last_credit"] = credit
	items[item["id"]] = irec


static func add_xp(profile: Profile, domain_id: String, amount: int) -> void:
	var xp := _bucket(profile, "xp")
	xp["total"] = int(xp.get("total", 0)) + amount
	xp[domain_id] = int(xp.get(domain_id, 0)) + amount


static func total_xp(profile: Profile) -> int:
	return int(profile.peek().get("xp", {}).get("total", 0))


static func domain_xp(profile: Profile, domain_id: String) -> int:
	return int(profile.peek().get("xp", {}).get(domain_id, 0))


static func note_streak(profile: Profile, streak: int) -> void:
	var progress := profile.progress()
	progress["best_streak"] = maxi(int(progress.get("best_streak", 0)), streak)


static func _bucket(profile: Profile, key: String) -> Dictionary:
	var progress := profile.progress()
	if typeof(progress.get(key)) != TYPE_DICTIONARY:
		progress[key] = {}
	return progress[key]
