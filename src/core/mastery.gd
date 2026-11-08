class_name Mastery
extends RefCounted
## Per-concept mastery and XP, stored in the Profile (README "Mastery and
## scheduling"). Stateless: every function takes the profile. Numbers read
## back from disk are floats, so reads go through int().

const TIER_UNSEEN := "unseen"
const TIER_SEEN := "seen"
const TIER_KNOWN := "known"
const TIER_MASTERED := "mastered"


static func day_of(now: int) -> int:
	return floori(now / 86400.0)


static func record(profile: Profile, concept_id: String) -> Dictionary:
	return profile.peek().get("concepts", {}).get(concept_id, {})


static func box(profile: Profile, concept_id: String) -> int:
	return int(record(profile, concept_id).get("box", 0))


static func seen(profile: Profile, concept_id: String) -> int:
	return int(record(profile, concept_id).get("seen", 0))


static func due_day(profile: Profile, concept_id: String) -> int:
	return int(record(profile, concept_id).get("due_day", 0))


static func tier(profile: Profile, concept_id: String) -> String:
	if seen(profile, concept_id) == 0:
		return TIER_UNSEEN
	var b := box(profile, concept_id)
	if b <= 1:
		return TIER_SEEN
	return TIER_KNOWN if b <= 3 else TIER_MASTERED


static func is_due(profile: Profile, concept_id: String, today: int) -> bool:
	return seen(profile, concept_id) > 0 and due_day(profile, concept_id) <= today


static func item_record(profile: Profile, item_id: String) -> Dictionary:
	return profile.peek().get("items", {}).get(item_id, {})


## Apply one answer. credit 1: up a box, due after that box's interval.
## credit 0: back to box 1, due tomorrow. In between: box unchanged, due
## tomorrow. Every concept the item lists is updated.
static func apply(profile: Profile, item: Dictionary, credit: float, now: int, rules: Rules) -> void:
	var today := day_of(now)
	var concepts := _bucket(profile, "concepts")
	for cid in item["concept_ids"]:
		var rec: Dictionary = concepts.get(cid, {})
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
		concepts[cid] = rec
	var items := _bucket(profile, "items")
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
