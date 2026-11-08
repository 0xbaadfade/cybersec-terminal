class_name PerksScreen
extends RefCounted
## The `perks` screen: the wallet and one row per perk (README "Skill tree Phase
## T3 plan"). Pure text.


static func lines(profile: Profile, rules: Rules, today: int) -> Array:
	var out: Array = [Lines.make("PERKS  //  %s" % Economy.summary(profile, today, rules), Lines.S_ACCENT)]
	if rules.perks.is_empty():
		out.append(Lines.make("There are no perks yet.", Lines.S_DIM))
		return out
	out.append(Lines.make(""))
	var wallet := floori(Economy.cycles(profile))
	for i in rules.perks.size():
		var p: Dictionary = rules.perks[i]
		var have := Perks.level(profile, p["id"])
		var price := Perks.next_cost(profile, rules, p["id"])
		var now := Perks.effect_text(rules, p["id"], have)
		var tail := "maxed" if price < 0 else "next %s cycles" % Economy.format_int(price)
		var style := Lines.S_OK if price >= 0 and price <= wallet else Lines.S_DIM
		out.append(Lines.make("  %2d  %s %s  %s %s" % [i + 1, (p["title"] as String).rpad(16), ("%d/%d" % [have, p["max_level"]]).rpad(5),
				("(" + now + ")").rpad(38), tail], style))
	out.append(Lines.make(""))
	out.append(Lines.make("buy <number> buys the next level. Bright rows are ones you can afford now.", Lines.S_DIM))
	return out
