class_name GridScreen
extends RefCounted
## The `grid` screen: the learner's nodes, one per concept met (README
## "Incremental layer plan"). `grid` summarises by domain; `grid <domain id>`
## lists that domain's nodes. Pure text, no state.


static func lines(pack: Pack, profile: Profile, rules: Rules, today: int, key: String = "") -> Array:
	if key.strip_edges() != "":
		return _domain_lines(pack, profile, rules, today, key.strip_edges())
	return _overview_lines(pack, profile, rules, today)


static func _overview_lines(pack: Pack, profile: Profile, rules: Rules, today: int) -> Array:
	var total := Economy.counts(profile, pack.concepts.keys(), today)
	var out: Array = [_l("GRID  //  %s" % pack.short, Lines.S_ACCENT)]
	out.append(_l("Cycles   %s   (earned in all: %s)" % [Economy.format_int(floori(Economy.cycles(profile))),
			Economy.format_int(floori(Economy.earned(profile)))]))
	out.append(_l("Output   %s here, %s in all" % [Economy.format_rate(Economy.track_rate(profile, pack, today, rules)),
			Economy.format_rate(Economy.rate(profile, today, rules))]))
	out.append(_l("Nodes    %d online, %d stale, %d not built yet" % [total["online"], total["stale"], total["unbuilt"]]))
	out.append(_l(""))
	for d in pack.domains:
		var ids := _domain_concepts(pack, d["id"])
		if ids.is_empty():
			continue
		var c := Economy.counts(profile, ids, today)
		var rate := 0.0
		for cid in ids:
			rate += Economy.node_rate(profile, cid, today, rules)
		out.append(_l("  %s  %s %3d online %3d stale %3d unbuilt   %s" % [(d["id"] as String).rpad(3),
				_fit(d["title"], 34).rpad(34), c["online"], c["stale"], c["unbuilt"], Economy.format_rate(rate)],
				Lines.S_ERROR if c["stale"] > 0 else Lines.S_NORMAL))
	out.append(_l(""))
	out.append(_l("Answering a concept builds its node. The better you know it, the more it earns.", Lines.S_DIM))
	out.append(_l("A stale node (due for review) earns %d%% until you answer it again. grid <domain> lists nodes." % Perks.stale_percent(profile, rules), Lines.S_DIM))
	return out


static func _domain_lines(pack: Pack, profile: Profile, rules: Rules, today: int, key: String) -> Array:
	var domain := {}
	for d in pack.domains:
		if (d["id"] as String).to_lower() == key.to_lower():
			domain = d
	if domain.is_empty():
		return [_l("No domain '%s'. Type grid for the list." % key, Lines.S_ERROR)]
	var out: Array = [_l("GRID  //  %s  %s" % [domain["id"], domain["title"]], Lines.S_ACCENT)]
	var unbuilt := 0
	for cid in _domain_concepts(pack, domain["id"]):
		if Mastery.seen(profile, cid) == 0:
			unbuilt += 1
			continue
		var stale := Mastery.is_due(profile, cid, today)
		out.append(_l("  %s %s box %d  %s  %s" % [_fit(cid, 22).rpad(22), _fit(pack.concepts[cid]["title"], 44).rpad(44),
				Mastery.box(profile, cid), Economy.format_rate(Economy.node_rate(profile, cid, today, rules)).rpad(9),
				"STALE" if stale else "online"], Lines.S_ERROR if stale else Lines.S_OK))
	if out.size() == 1:
		out.append(_l("No nodes here yet. Answer a question from this domain to build one.", Lines.S_DIM))
	if unbuilt > 0:
		out.append(_l("%d more not built yet." % unbuilt, Lines.S_DIM))
	return out


static func _domain_concepts(pack: Pack, domain_id: String) -> Array:
	var ids: Array = []
	for cid in pack.concepts:
		if pack.domain_of_concept(cid) == domain_id:
			ids.append(cid)
	return ids


static func _fit(text: String, width: int) -> String:
	return text if text.length() <= width else text.substr(0, width - 1) + "…"


static func _l(text: String, style: String = Lines.S_NORMAL) -> Dictionary:
	return Lines.make(text, style)
