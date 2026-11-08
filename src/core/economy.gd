class_name Economy
extends RefCounted
## The incremental layer (README "Incremental layer plan"): Cycles earned by
## answering and by nodes (met concepts) that run while the program is open.
## Stateless like Mastery: every function takes the profile.
##
## The wallet is the profile's, not a track's: nodes from every track earn into
## it, so what is bought with it (README "Skill tree plan") is one pool. It lives
## at the top of the profile data under "economy" and is created lazily. The
## once-a-day payout record is per track (`progress["paid"]`). Numbers read back
## from disk are floats, so reads go through int().
##
## Nothing here touches concepts, items or rounds: Cycles never cost mastery.


## The wallet dictionary, created on first use.
static func wallet(profile: Profile) -> Dictionary:
	if typeof(profile.data.get("economy")) != TYPE_DICTIONARY:
		profile.data["economy"] = {"cycles": 0.0, "earned": 0.0, "last_tick": 0}
	return profile.data["economy"]


static func has_wallet(profile: Profile) -> bool:
	return typeof(profile.data.get("economy")) == TYPE_DICTIONARY


static func cycles(profile: Profile) -> float:
	return float(profile.data.get("economy", {}).get("cycles", 0.0)) if has_wallet(profile) else 0.0


static func earned(profile: Profile) -> float:
	return float(profile.data.get("economy", {}).get("earned", 0.0)) if has_wallet(profile) else 0.0


## Put `amount` whole Cycles into the wallet (a bonus, not an answer or a node).
static func add(profile: Profile, amount: int) -> void:
	var w := wallet(profile)
	w["cycles"] = float(w.get("cycles", 0.0)) + amount
	w["earned"] = float(w.get("earned", 0.0)) + amount


## Take `amount` whole Cycles out of the wallet. False (nothing taken) when the
## wallet holds less.
static func spend(profile: Profile, amount: int) -> bool:
	if amount < 0 or floorf(cycles(profile)) < amount:
		return false
	wallet(profile)["cycles"] = float(wallet(profile)["cycles"]) - amount
	return true


## Cycles per minute one concept's node produces now, read from `profile`'s
## active track: 0 until the concept has been met, the box rate while it is not
## due, and `stale_percent` of that rate while it is due for review.
static func node_rate(profile: Profile, concept_id: String, today: int, rules: Rules) -> float:
	if Mastery.seen(profile, concept_id) == 0:
		return 0.0
	var rate: float = rules.eco_rate_by_box[clampi(Mastery.box(profile, concept_id), 0, Rules.MAX_BOX)]
	if Mastery.is_due(profile, concept_id, today):
		rate *= Perks.stale_percent(profile, rules) / 100.0
	return rate * Perks.node_multiplier(profile, rules)


## Output of the active track's pack.
static func track_rate(profile: Profile, pack: Pack, today: int, rules: Rules) -> float:
	var total := 0.0
	for cid in pack.concepts:
		total += node_rate(profile, cid, today, rules)
	return total


## Output of every track the learner has played. It reads the saved concept
## records, so no pack has to be loaded.
static func rate(profile: Profile, today: int, rules: Rules) -> float:
	var total := 0.0
	var tracks: Variant = profile.data.get("tracks")
	if typeof(tracks) != TYPE_DICTIONARY:
		return 0.0
	for id in tracks:
		var concepts: Variant = tracks[id].get("concepts") if typeof(tracks[id]) == TYPE_DICTIONARY else null
		if typeof(concepts) != TYPE_DICTIONARY:
			continue
		var view := profile.view(id)
		for cid in concepts:
			total += node_rate(view, cid, today, rules)
	return total


## {"online", "stale", "unbuilt"} over `concept_ids` (a pack, or one domain) of
## the active track.
static func counts(profile: Profile, concept_ids: Array, today: int) -> Dictionary:
	var out := {"online": 0, "stale": 0, "unbuilt": 0}
	for cid in concept_ids:
		if Mastery.seen(profile, cid) == 0:
			out["unbuilt"] += 1
		elif Mastery.is_due(profile, cid, today):
			out["stale"] += 1
		else:
			out["online"] += 1
	return out


## Start the clock at `now` without paying anything (the learner just logged
## in). A profile that has played nothing has nothing to pay and is left alone.
static func start(profile: Profile, now: int) -> void:
	if _played_nothing(profile):
		return
	wallet(profile)["last_tick"] = now


## Pay the nodes for the time since the last settle. A gap longer than
## `idle_cap_seconds` (the program was closed or the machine slept) is dropped,
## not paid: there is no offline progress. Returns the Cycles paid.
static func settle(profile: Profile, now: int, rules: Rules) -> float:
	if _played_nothing(profile):
		return 0.0
	var w := wallet(profile)
	var last := int(w.get("last_tick", 0))
	w["last_tick"] = now
	var gap := now - last
	if last == 0 or gap <= 0 or gap > rules.eco_idle_cap:
		return 0.0
	var gained := rate(profile, Mastery.day_of(now), rules) * gap / 60.0
	w["cycles"] = float(w.get("cycles", 0.0)) + gained
	w["earned"] = float(w.get("earned", 0.0)) + gained
	return gained


## Pay for one answer worth `xp`, in the active track. The first full-credit
## answer to a concept on a UTC day pays in full; later ones that day pay
## `repeat_percent`. A miss pays nothing, and partial credit pays its share
## without using up the day's full payment. Returns the whole Cycles paid.
static func award(profile: Profile, concept_id: String, xp: int, credit: float, today: int, rules: Rules) -> int:
	if xp <= 0 or credit <= 0.0:
		return 0
	var progress := profile.progress()
	if typeof(progress.get("paid")) != TYPE_DICTIONARY:
		progress["paid"] = {}
	var paid: Dictionary = progress["paid"]
	var fresh := int(paid.get(concept_id, -1)) != today
	var percent := 100 if fresh else Perks.repeat_percent(profile, rules)
	var gain := roundi(float(xp) * rules.eco_active_multiplier * Perks.yield_multiplier(profile, rules) * percent / 100.0)
	if credit >= 1.0:
		paid[concept_id] = today
	var w := wallet(profile)
	w["cycles"] = float(w.get("cycles", 0.0)) + gain
	w["earned"] = float(w.get("earned", 0.0)) + gain
	return gain


static func _played_nothing(profile: Profile) -> bool:
	var tracks: Variant = profile.data.get("tracks")
	return typeof(tracks) != TYPE_DICTIONARY or (tracks as Dictionary).is_empty()


# --- text ----------------------------------------------------------------

## 1240 -> "1,240".
static func format_int(n: int) -> String:
	var digits := str(absi(n))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.substr(digits.length() - 3) + out
		digits = digits.substr(0, digits.length() - 3)
	return ("-" if n < 0 else "") + digits + out


## "+80/min", or one decimal below 10 when the rate is not whole ("+1.5/min").
static func format_rate(per_min: float) -> String:
	if per_min >= 10.0 or is_equal_approx(per_min, roundf(per_min)):
		return "+%d/min" % roundi(per_min)
	return "+%.1f/min" % per_min


## "1,240 cycles (+80/min)": the wallet and the output of all tracks.
static func summary(profile: Profile, today: int, rules: Rules) -> String:
	return "%s cycles (%s)" % [format_int(floori(cycles(profile))), format_rate(rate(profile, today, rules))]
