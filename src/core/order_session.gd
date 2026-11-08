class_name OrderSession
extends RefCounted
## The learner's state in an order question: the steps in the order they are
## shown (a seeded shuffle that never starts on the right order), a cursor, and
## whether a step is lifted (Up/Down then carry it). Headless.

var item: Dictionary
var seq: Array = []  # step indexes (into item["steps"]) in display order
var cursor := 0
var lifted := false
var touched := false  # the learner has moved something


func _init(order_item: Dictionary, rng: RandomNumberGenerator) -> void:
	item = order_item
	var n: int = order_item["steps"].size()
	for i in n:
		seq.append(i)
	for attempt in 20:
		for i in range(n - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp: int = seq[i]
			seq[i] = seq[j]
			seq[j] = tmp
		if not _is_right_order():
			return
	seq.append(seq.pop_front())  # a rotation is never the identity for n >= 2


func _is_right_order() -> bool:
	for i in seq.size():
		if seq[i] != i:
			return false
	return true


func step_at(position: int) -> Dictionary:
	return item["steps"][seq[position]]


func has_answer() -> bool:
	return touched


func response() -> Array:
	return seq


## Order questions take no one-key answers (arrows and Enter).
func single_key_choices() -> int:
	return 0


## Run one input: Up/Down, Enter (lift or set down), Esc, or `m <from> <to>`.
## Returns "" when it worked, otherwise what to tell the learner.
func handle(verb: String, rest: String) -> String:
	match verb:
		"@up", "@down":
			var to := cursor + (-1 if verb == "@up" else 1)
			if to < 0 or to >= seq.size():
				return ""
			if lifted:
				_swap(cursor, to)
			cursor = to
			return ""
		"":
			lifted = not lifted
			return ""
		"@esc":
			lifted = false
			return ""
		"m", "move":
			var parts := rest.split(" ", false)
			if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
				var a := int(parts[0]) - 1
				var b := int(parts[1]) - 1
				if a >= 0 and a < seq.size() and b >= 0 and b < seq.size():
					var s: int = seq[a]
					seq.remove_at(a)
					seq.insert(b, s)
					cursor = b
					lifted = false
					touched = touched or a != b
					return ""
			return "Usage: m <from> <to>, positions 1-%d (m 4 1 moves step 4 to the top)." % seq.size()
	return "Up/Down choose a step, Enter lifts it, Up/Down carry it, Enter sets it down. m 4 1 moves step 4 to position 1."


func _swap(a: int, b: int) -> void:
	var tmp: int = seq[a]
	seq[a] = seq[b]
	seq[b] = tmp
	touched = true
