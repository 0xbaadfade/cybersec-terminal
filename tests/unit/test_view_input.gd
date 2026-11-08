extends GutTest
## The prompt must keep accepting typing after Enter: Godot's LineEdit leaves
## edit mode on submit unless told not to, and the learner then has to click it
## before every line (found by hand, 2026-11-05).

const Support := preload("res://tests/unit/support.gd")

var _dir := ""
var _main: Control
var _input: LineEdit


func before_each() -> void:
	_dir = Support.make_dir()
	Game.configure(_dir)
	_main = load("res://src/view/main.tscn").instantiate()
	add_child_autofree(_main)
	await get_tree().process_frame
	_input = _main.get("_input")


func after_each() -> void:
	Support.remove_dir(_dir)


func _key(keycode: Key, unicode: int = 0) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.unicode = unicode
	ev.pressed = true
	get_viewport().push_input(ev)


func test_prompt_is_editing_at_start() -> void:
	assert_true(_input.has_focus())
	assert_true(_input.is_editing())


func test_typing_still_works_after_enter() -> void:
	_input.text = "help"
	_key(KEY_ENTER)
	await get_tree().process_frame
	assert_eq(_input.text, "", "the line was submitted")
	assert_true(_input.is_editing(), "the prompt stays in edit mode")
	_key(KEY_X, "x".unicode_at(0))
	_key(KEY_Y, "y".unicode_at(0))
	await get_tree().process_frame
	assert_eq(_input.text, "xy")
