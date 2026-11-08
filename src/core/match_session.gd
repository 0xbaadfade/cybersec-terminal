class_name MatchSession
extends RefCounted
## The learner's state in a match question: the rows in the order shown (a
## seeded shuffle of the item's pairs), a cursor, and what each row was filed
## under. Headless; PbqScreen turns it into Lines.

var item: Dictionary
var categories: Array = []  # [{id, text}] in authored order, lettered A, B, C
var rows: Array = []  # pair indexes in display order
var assign: Dictionary = {}  # pair index -> category id
var cursor := 0  # display row


func _init(match_item: Dictionary, rng: RandomNumberGenerator) -> void:
	item = match_item
	categories = match_item["categories"]
	for i in match_item["pairs"].size():
		rows.append(i)
	for i in range(rows.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: int = rows[i]
		rows[i] = rows[j]
		rows[j] = tmp


func pair_at(row: int) -> Dictionary:
	return item["pairs"][rows[row]]


## The category id filed for display row `row`, or "".
func filed_at(row: int) -> String:
	return str(assign.get(rows[row], ""))


func letter_of(category_id: String) -> String:
	for k in categories.size():
		if categories[k]["id"] == category_id:
			return char(65 + k)
	return ""


func has_answer() -> bool:
	return not assign.is_empty()


func response() -> Dictionary:
	return assign


## How many keys a single press can mean here (letters A.. or digits 1..).
func single_key_choices() -> int:
	return categories.size()


func filed_count() -> int:
	return assign.size()


## Run one input: an arrow action, Enter (""), a category key, `x [row]` or
## `<row> <category>`. Returns "" when it worked, otherwise what to tell the learner.
func handle(verb: String, rest: String) -> String:
	match verb:
		"@up":
			cursor = maxi(0, cursor - 1)
			return ""
		"@down":
			cursor = mini(rows.size() - 1, cursor + 1)
			return ""
		"@esc":
			return ""
		"":  # Enter: blank, then each category in turn, then blank again
			var at := _index_of(filed_at(cursor))
			_file(cursor, "" if at + 1 >= categories.size() else categories[at + 1]["id"])
			return ""
		"x", "unfile":
			var row := cursor
			if rest != "":
				if not rest.is_valid_int() or int(rest) < 1 or int(rest) > rows.size():
					return "Usage: x [row number 1-%d]" % rows.size()
				row = int(rest) - 1
			_file(row, "")
			cursor = row
			return ""
	if rest == "":
		var k := category_key(verb)
		if k >= 0:
			_file(cursor, categories[k]["id"])
			cursor = mini(rows.size() - 1, cursor + 1)
			return ""
	elif verb.is_valid_int():
		var r := int(verb) - 1
		var k2 := category_key(rest)
		if r >= 0 and r < rows.size() and k2 >= 0:
			_file(r, categories[k2]["id"])
			cursor = r
			return ""
	return "Up/Down choose a row, then press %s to file it. x clears a row; 3 b files row 3 under B." % keys_text()


## Category index for a typed key (a letter or a digit), or -1.
func category_key(token: String) -> int:
	var t := token.to_lower()
	if t.length() != 1:
		return -1
	var k := -1
	if t >= "a" and t <= "z":
		k = t.unicode_at(0) - 97
	elif t >= "1" and t <= "9":
		k = int(t) - 1
	return k if k >= 0 and k < categories.size() else -1


func keys_text() -> String:
	return "A-%s (or 1-%d)" % [char(64 + categories.size()), categories.size()]


func _index_of(category_id: String) -> int:
	for k in categories.size():
		if categories[k]["id"] == category_id:
			return k
	return -1


func _file(row: int, category_id: String) -> void:
	if category_id == "":
		assign.erase(rows[row])
	else:
		assign[rows[row]] = category_id
