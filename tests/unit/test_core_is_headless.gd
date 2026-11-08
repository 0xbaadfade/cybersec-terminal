extends GutTest
## src/core/ must stay constructible with no scene tree: RefCounted only, no
## Node, no view. This is what lets the suite (and later the labs' emulators)
## run headless and fast. Autoloads must be Nodes, so they live in src/game/.

const CORE_DIR := "res://src/core"

const FORBIDDEN := {
	"extends Node": "src/core must be RefCounted-only; a Node belongs in src/game/ or src/view/",
	"get_node(": "src/core must not reach into a scene tree",
	"$": "src/core must not use the $NodePath shorthand",
	"func _process(": "src/core must not have a frame callback",
	"func _physics_process(": "src/core must not have a frame callback",
	"src/view": "src/core must not depend on the view layer",
}


func _gdscript_files(dir_path: String) -> Array:
	var found: Array = []
	var dir := DirAccess.open(dir_path)
	assert_not_null(dir, "could not open %s" % dir_path)
	if dir == null:
		return found
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var full := "%s/%s" % [dir_path, name]
		if dir.current_is_dir():
			found.append_array(_gdscript_files(full))
		elif name.ends_with(".gd"):
			found.append(full)
		name = dir.get_next()
	dir.list_dir_end()
	return found


## Comments are stripped so the rule is about code, not prose.
func _code_lines(path: String) -> Array:
	var out: Array = []
	for raw in FileAccess.get_file_as_string(path).split("\n"):
		var line: String = raw
		var hash_at := line.find("#")
		if hash_at != -1:
			line = line.substr(0, hash_at)
		if line.strip_edges() != "":
			out.append(line)
	return out


func test_core_has_scripts() -> void:
	assert_gt(_gdscript_files(CORE_DIR).size(), 0)


func test_core_is_headless() -> void:
	var violations: Array = []
	for path in _gdscript_files(CORE_DIR):
		for line in _code_lines(path):
			for needle in FORBIDDEN:
				if line.contains(needle):
					violations.append("%s: '%s' -- %s" % [path, needle, FORBIDDEN[needle]])
	assert_eq(violations, [], "src/core must stay headless")
