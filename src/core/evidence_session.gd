class_name EvidenceSession
extends RefCounted
## The learner's state while hunting through one artifact: the cursor, the
## scrolling window, the flags and the reason menu. Headless; the router turns
## it into Lines. Line numbers are 1-based, as in the file.

const WINDOW := 15

var lines: Array = []  # artifact lines, index 0 is line 1
var reasons: Array = []  # [{key, label}] from the pack
var cursor := 1
var top := 1  # first visible line
var flags: Dictionary = {}  # line number -> reason key
var pending := 0  # line waiting for a reason (the menu is open), 0 if none


func _init(artifact_lines: Array, reason_menu: Array) -> void:
	lines = artifact_lines
	reasons = reason_menu


## Menu digit that clears a flag: one past the last reason.
func clear_digit() -> int:
	return reasons.size() + 1


func in_range(n: int) -> bool:
	return n >= 1 and n <= lines.size()


func move(delta: int) -> void:
	go(cursor + delta)


## Jump to a line, clamping to the file.
func go(n: int) -> void:
	cursor = clampi(n, 1, maxi(1, lines.size()))
	if cursor < top:
		top = cursor
	elif cursor >= top + WINDOW:
		top = cursor - WINDOW + 1
	top = clampi(top, 1, maxi(1, lines.size() - WINDOW + 1))


func last_visible() -> int:
	return mini(lines.size(), top + WINDOW - 1)


## Open the reason menu for line `n`. False when it is not a line.
func begin_flag(n: int) -> bool:
	if not in_range(n):
		return false
	go(n)
	pending = n
	return true


## Answer the open menu. A reason digit sets the flag, the clear digit removes
## it. False when no menu is open or the digit is not on it.
func choose(digit: int) -> bool:
	if pending == 0 or digit < 1 or digit > clear_digit():
		return false
	if digit == clear_digit():
		flags.erase(pending)
	else:
		flags[pending] = reasons[digit - 1]["key"]
	pending = 0
	return true


func cancel() -> void:
	pending = 0


func unflag(n: int) -> bool:
	return flags.erase(n)


func label_of(key: String) -> String:
	for r in reasons:
		if r["key"] == key:
			return r["label"]
	return key


# --- input (used inside the exam; the same keys the old field exercise had) ---

func has_answer() -> bool:
	return not flags.is_empty()


func response() -> Dictionary:
	return flags


## The reason menu's digits are single keys while it is open; otherwise none.
func single_key_choices() -> int:
	return clear_digit() if pending > 0 else 0


## Run one input: Up/Down, Enter or `f [line] [digit]` (flag, then pick a reason),
## `x [line]`, `go <line>`, a digit or Esc at the reason menu. Returns "" when it
## worked, otherwise what to tell the learner.
func handle(verb: String, rest: String) -> String:
	if pending > 0:
		if verb == "@esc" or verb == "esc" or verb == "cancel" or verb == "":
			cancel()
			return ""
		if verb.is_valid_int() and rest == "" and choose(int(verb)):
			return ""
		return "Pick 1-%d, or Esc to cancel." % clear_digit()
	match verb:
		"@up", "@down":
			move(-1 if verb == "@up" else 1)
			return ""
		"@esc":
			return ""
		"":
			begin_flag(cursor)
			return ""
		"go":
			if not rest.is_valid_int():
				return "Usage: go <line number>"
			go(int(rest))
			return ""
		"f":
			var parts := rest.split(" ", false)
			if parts.size() > 2 or (parts.size() > 0 and not parts[0].is_valid_int()) \
					or (parts.size() == 2 and not parts[1].is_valid_int()):
				return "Usage: f [line] [reason digit]"
			var n := int(parts[0]) if parts.size() > 0 else cursor
			if not begin_flag(n):
				return "Line %d is not in the file (1-%d)." % [n, lines.size()]
			if parts.size() == 2 and not choose(int(parts[1])):
				cancel()
				return "Reason %s is not on the menu (1-%d)." % [parts[1], clear_digit()]
			return ""
		"x", "unflag":
			if rest != "" and not rest.is_valid_int():
				return "Usage: x [line]"
			var line := int(rest) if rest != "" else cursor
			if not unflag(line):
				return "Line %d is not flagged." % line
			return ""
	return "Up/Down move, Enter or f flags a line (then pick a reason), x unflags, go <n> jumps."
