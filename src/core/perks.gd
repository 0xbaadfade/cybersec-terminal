class_name Perks
extends RefCounted
## The perks shop (README "Skill tree Phase T3 plan"). The perks are data in
## rules.json (`Rules.perks`); the levels bought belong to the profile at
## `profile.data["perks"]` = {id: level}, created lazily. Stateless like Mastery.
##
## The effect readers return a neutral value when the rules define no perk of that
## kind, so an older rules file behaves as before. Perks change Cycles, the cap on
## typed rounds and exam minutes, and nothing about scoring, XP or mastery.

## The ceiling on a typed round when no perk sets one (the old fixed limit).
const HARD_MAX_QUESTIONS := 200


static func perk(rules: Rules, id: String) -> Dictionary:
	for p in rules.perks:
		if p["id"] == id:
			return p
	return {}


## The perk a typed number (1-based, as the shop lists them) or an id points at, or "".
static func resolve(rules: Rules, text: String) -> String:
	var t := text.strip_edges().to_lower()
	if t.is_valid_int():
		var n := int(t)
		return rules.perks[n - 1]["id"] if n >= 1 and n <= rules.perks.size() else ""
	return t if not perk(rules, t).is_empty() else ""


static func level(profile: Profile, id: String) -> int:
	var owned: Variant = profile.data.get("perks")
	return int(owned.get(id, 0)) if typeof(owned) == TYPE_DICTIONARY else 0


## Price of the next level of `id`, or -1 when it is at its top level (or unknown).
static func next_cost(profile: Profile, rules: Rules, id: String) -> int:
	var p := perk(rules, id)
	var have := level(profile, id)
	if p.is_empty() or have >= int(p["max_level"]):
		return -1
	return roundi(float(p["base_cost"]) * pow(float(p["growth"]), have))


## Buy one level. "" on success, otherwise why not (nothing is taken then).
static func buy(profile: Profile, rules: Rules, id: String) -> String:
	var p := perk(rules, id)
	if p.is_empty():
		return "There is no perk '%s'." % id
	var price := next_cost(profile, rules, id)
	if price < 0:
		return "%s is already at its top level." % p["title"]
	if not Economy.spend(profile, price):
		return "%s level %d costs %s cycles; you have %s." % [p["title"], level(profile, id) + 1,
				Economy.format_int(price), Economy.format_int(floori(Economy.cycles(profile)))]
	if typeof(profile.data.get("perks")) != TYPE_DICTIONARY:
		profile.data["perks"] = {}
	profile.data["perks"][id] = level(profile, id) + 1
	return ""


# --- effects ---------------------------------------------------------------

## Level owned of the first perk of `kind`, or -1 when the rules have none.
static func _kind_level(profile: Profile, rules: Rules, kind: String) -> int:
	for p in rules.perks:
		if p["kind"] == kind:
			return level(profile, p["id"])
	return -1


static func _per_level(rules: Rules, kind: String) -> int:
	for p in rules.perks:
		if p["kind"] == kind:
			return int(p["per_level"])
	return 0


## The most questions a typed round may have.
static func max_questions(profile: Profile, rules: Rules) -> int:
	for p in rules.perks:
		if p["kind"] == "max_questions":
			var have := clampi(level(profile, p["id"]), 0, (p["levels"] as Array).size())
			return int(p["base"]) if have == 0 else int(p["levels"][have - 1])
	return HARD_MAX_QUESTIONS


## `minutes` of a timed exam with the time perk applied, rounded up.
static func exam_minutes(profile: Profile, rules: Rules, minutes: int) -> int:
	var have := _kind_level(profile, rules, "exam_minutes")
	if have <= 0 or minutes <= 0:
		return minutes
	return ceili(float(minutes) * (100 + _per_level(rules, "exam_minutes") * have) / 100.0)


## Factor on the Cycles an answer pays.
static func yield_multiplier(profile: Profile, rules: Rules) -> float:
	return 1.0 + maxi(0, _kind_level(profile, rules, "yield")) * _per_level(rules, "yield") / 100.0


## Factor on every node's output.
static func node_multiplier(profile: Profile, rules: Rules) -> float:
	return 1.0 + maxi(0, _kind_level(profile, rules, "node_output")) * _per_level(rules, "node_output") / 100.0


## A stale node's share of its output, in percent.
static func stale_percent(profile: Profile, rules: Rules) -> int:
	return mini(100, rules.eco_stale_percent + maxi(0, _kind_level(profile, rules, "stale_floor")) * _per_level(rules, "stale_floor"))


## What an answer pays when its concept was already paid in full today, in percent.
static func repeat_percent(profile: Profile, rules: Rules) -> int:
	return mini(100, rules.eco_repeat_percent + maxi(0, _kind_level(profile, rules, "repeat_payout")) * _per_level(rules, "repeat_payout"))


## One line saying what the perk does at `at_level` ("up to 40 questions", "+20% cycles per answer").
static func effect_text(rules: Rules, id: String, at_level: int) -> String:
	var p := perk(rules, id)
	if p.is_empty():
		return ""
	var n := int(p["per_level"]) * at_level
	match p["kind"]:
		"max_questions":
			return "typed rounds up to %d questions" % (int(p["base"]) if at_level == 0 else int(p["levels"][at_level - 1]))
		"exam_minutes":
			return "+%d%% exam minutes" % n
		"yield":
			return "+%d%% cycles per answer" % n
		"node_output":
			return "+%d%% cycles from nodes" % n
		"stale_floor":
			return "stale nodes earn %d%%" % mini(100, rules.eco_stale_percent + n)
		"repeat_payout":
			return "same-day repeats pay %d%%" % mini(100, rules.eco_repeat_percent + n)
	return ""
