class_name Codex
extends RefCounted
## The Codex: every concept with its tier, and one concept in detail. The
## only place tiers are shown (README "The Codex").

const STYLE_BY_TIER := {
	Mastery.TIER_UNSEEN: Lines.S_DIM,
	Mastery.TIER_SEEN: Lines.S_NORMAL,
	Mastery.TIER_KNOWN: Lines.S_OK,
	Mastery.TIER_MASTERED: Lines.S_ACCENT,
}


## Concept id for a 1-based number, an exact id, or a unique id prefix; "" if
## nothing (or more than one concept) matches.
static func resolve(pack: Pack, key: String) -> String:
	var ids: Array = pack.concepts.keys()
	var k := key.strip_edges().to_lower()
	if k.is_valid_int() and int(k) >= 1 and int(k) <= ids.size():
		return ids[int(k) - 1]
	if pack.concepts.has(k):
		return k
	var hits: Array = ids.filter(func(cid: String) -> bool: return cid.begins_with(k))
	return hits[0] if hits.size() == 1 and k != "" else ""


static func list_lines(pack: Pack, profile: Profile) -> Array:
	var out: Array = []
	var met := 0
	for cid in pack.concepts:
		if Mastery.seen_of(profile, pack.topics_of(cid)) > 0:
			met += 1
	out.append(_l("CODEX  //  %d concepts, %d met.  codex <number or id> for detail" % [pack.concepts.size(), met], Lines.S_ACCENT))
	var ids: Array = pack.concepts.keys()
	for d in pack.domains:
		var header_done := false
		for i in ids.size():
			var cid: String = ids[i]
			if pack.domain_of_concept(cid) != d["id"]:
				continue
			if not header_done:
				out.append(_l(""))
				out.append(_l("%s  %s" % [d["id"], d["title"]]))
				header_done = true
			var rec := Mastery.totals_of(profile, pack.topics_of(cid))
			var tier := Mastery.tier_of(profile, pack.topics_of(cid))
			out.append(_l("  %2d  %s %s %s hits %d  misses %d" % [
					i + 1, cid.rpad(22), (pack.concepts[cid]["title"] as String).rpad(46), tier.rpad(9),
					int(rec.get("hits", 0)), int(rec.get("misses", 0))], STYLE_BY_TIER[tier]))
	return out


static func detail_lines(pack: Pack, profile: Profile, key: String, today: int) -> Array:
	var cid := resolve(pack, key)
	if cid == "":
		return [_l("No single concept matches '%s'. Type codex for the list." % key, Lines.S_ERROR)]
	var out: Array = []
	var topics := pack.topics_of(cid)
	var tier := Mastery.tier_of(profile, topics)
	out.append(_l("%s  //  %s" % [cid, pack.concepts[cid]["title"]], Lines.S_ACCENT))
	if tier == Mastery.TIER_UNSEEN:
		out.append(_l("tier: unseen", Lines.S_DIM))
	else:
		var due := Mastery.due_day_of(profile, topics)
		out.append(_l("tier: %s (box %d)   next review: %s" % [tier, Mastery.box_of(profile, topics),
				"due now" if due <= today else Time.get_date_string_from_unix_time(due * 86400)]))
	out.append(_l(""))
	var entry: Dictionary = pack.codex.get(cid, {})
	out.append(_l(entry.get("definition", "(no definition written yet)"), Lines.S_NORMAL if entry.has("definition") else Lines.S_DIM))
	var missed: Array = []
	for it in pack.items_for_concept(cid):
		if int(Mastery.item_record(profile, it["id"]).get("misses", 0)) > 0:
			missed.append(it)
	if not missed.is_empty():
		out.append(_l(""))
		out.append(_l("Questions you have missed:"))
		for it in missed:
			var stem: String = it["stem"]
			out.append(_l("  %s  %s" % [it["id"], stem if stem.length() <= 80 else stem.substr(0, 79) + "…"], Lines.S_DIM))
	return out


static func _l(text: String, style: String = Lines.S_NORMAL) -> Dictionary:
	return Lines.make(text, style)
