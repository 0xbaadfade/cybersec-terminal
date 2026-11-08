class_name Exams
extends RefCounted
## What is remembered about a track's exam (README "Skill tree Phase T2 plan"):
## the best credit percent, the number of tries, and whether it has been passed.
## Stateless like Mastery: every function takes the profile, which reads and writes
## the active track's `progress["exams"]`. Only full-length exams are recorded.
##
## "Passed" needs a percentage pass mark (`pass_percent` in the pack's exam block).
## A pack with a scaled `pass_score` records its best percent but is never passed.


static func state(profile: Profile) -> Dictionary:
	var s: Variant = profile.peek().get("exams")
	return s if typeof(s) == TYPE_DICTIONARY else {}


static func attempts(profile: Profile) -> int:
	return int(state(profile).get("attempts", 0))


## The best percent so far, or -1 when no full exam has been recorded.
static func best_percent(profile: Profile) -> int:
	return int(state(profile).get("best_percent", -1))


static func passed(profile: Profile) -> bool:
	return state(profile).get("passed", false) == true


## The pack's percentage pass mark, or 0 when it states none (or a scaled one).
static func pass_percent(pack: Pack) -> int:
	return int(pack.exam.get("pass_percent", 0)) if pack.exam.has("pass_percent") and Pack.exam_problem(pack.exam) == "" else 0


## Record a finished exam. Nothing is written unless it was `full`. Returns
## {"recorded", "previous_best" (-1 if none), "new_best", "passed" (this exam
## reached the mark), "first_pass" (the first time the track was passed)}.
static func record(profile: Profile, pack: Pack, percent: int, now: int, full: bool) -> Dictionary:
	var out := {"recorded": false, "previous_best": best_percent(profile), "new_best": false, "passed": false, "first_pass": false}
	if not full:
		return out
	var progress := profile.progress()
	if typeof(progress.get("exams")) != TYPE_DICTIONARY:
		progress["exams"] = {}
	var s: Dictionary = progress["exams"]
	var need := pass_percent(pack)
	var was_passed: bool = s.get("passed", false) == true
	out["recorded"] = true
	out["new_best"] = percent > int(out["previous_best"])
	out["passed"] = need > 0 and percent >= need
	out["first_pass"] = out["passed"] and not was_passed
	s["attempts"] = int(s.get("attempts", 0)) + 1
	s["last_at"] = now
	if out["new_best"]:
		s["best_percent"] = percent
	if out["first_pass"]:
		s["passed"] = true
		s["passed_at"] = now
	return out
