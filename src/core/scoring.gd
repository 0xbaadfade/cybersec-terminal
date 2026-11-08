class_name Scoring
extends RefCounted
## Pure scoring functions (README "Answering and scoring").

## 1.0 for exactly the right answer. For a multi, partial credit:
## (right picks - wrong picks) / number of correct answers, floored at 0.
## An mcq is the same formula with one correct answer.
static func credit(item: Dictionary, picks: Array) -> float:
	var answer: Array = item["answer"]
	var right := 0
	for p in picks:
		if answer.has(p):
			right += 1
	var wrong := picks.size() - right
	return clampf(float(right - wrong) / float(answer.size()), 0.0, 1.0)


## Bonus fraction for a streak of `streak` consecutive full-credit answers
## (this answer included): none for the first, `step` for each one after.
static func streak_bonus(streak: int, rules: Rules) -> float:
	return minf(rules.streak_cap, rules.streak_step * maxf(0.0, float(streak - 1)))


static func xp(item: Dictionary, credit_value: float, streak: int, rules: Rules) -> int:
	var base: int = int(rules.xp_per_difficulty[clampi(int(item["difficulty"]) - 1, 0, 2)])
	if item["type"] == "evidence":
		base *= rules.evidence_xp_multiplier
	elif item["type"] == "terminal":
		base *= rules.terminal_xp_multiplier
	var bonus := streak_bonus(streak, rules) if credit_value >= 1.0 else 0.0
	return roundi(float(base) * credit_value * (1.0 + bonus))


## Change to the Trace meter for an answer: relief when fully correct,
## otherwise a share of `trace_miss` proportional to the credit lost.
static func trace_delta(credit_value: float, rules: Rules) -> int:
	if credit_value >= 1.0:
		return -rules.trace_relief
	return roundi(float(rules.trace_miss) * (1.0 - credit_value))
