extends Control
## The terminal screen: a title bar, a scrolling log, and a prompt line. It
## only displays what Game.submit() returns; every typed line is an action
## string handed to the router (README: the view adds no game logic). On a
## one-answer question a bare letter or digit is sent as the answer. In the
## map and the track menu the arrow keys become the actions "@up" and
## "@down"; at the home screen Left and Right become "@left" and "@right"; in the map Esc becomes "@esc". A one-second
## timer calls router.tick(): the nodes pay out, and an exam clock moves. On an exam PBQ (router.pbq_active())
## Up and Down, Esc and Left/Right (previous and next question) become actions too.

const WEB_SAVE_NOTE := "Playing in a browser: your progress is saved in this browser, on this computer."
const WEB_QUIT_NOTE := "Saved. A web page cannot close itself: close this tab when you are done."

var _log: RichTextLabel
var _input: LineEdit
var _prompt: Label
var _title: Label
var _status: Label
var _history: Array = []
var _history_at := 0


func _ready() -> void:
	_build()
	var ticker := Timer.new()
	ticker.wait_time = 1.0
	ticker.timeout.connect(_on_tick)
	add_child(ticker)
	ticker.start()
	_print_lines(Game.router.banner())
	if OS.has_feature("web"):
		_print_line({"t": WEB_SAVE_NOTE, "s": CommandRouter.S_DIM})
	_refresh_chrome()
	_input.grab_focus()


## Echo a line as if it had been typed, then run it. The capture tool uses
## this too, so what it renders is what typing would have produced.
func run_line(line: String) -> void:
	# Blank lines (Enter to continue) and @-actions are not echoed.
	if line.strip_edges() != "" and not line.begins_with("@"):
		_print_line({"t": "%s %s" % [Game.router.prompt(), line], "s": CommandRouter.S_DIM})
	_print_lines(Game.submit(line))
	_refresh_chrome()
	if Game.router.want_quit and is_inside_tree():
		if OS.has_feature("web"):
			# A browser tab cannot be closed from inside the page; the router has already saved.
			Game.router.want_quit = false
			_print_line({"t": WEB_QUIT_NOTE, "s": CommandRouter.S_DIM})
		else:
			get_tree().quit()


## Once a second: the nodes pay out (the cycles in the status bar move), the
## clock moves during an exam, and an idle exam ends at its deadline.
func _on_tick() -> void:
	_print_lines(Game.router.tick())
	_refresh_chrome()


func _build() -> void:
	var font: Font = load(TermTheme.FONT_PATH)

	var bg := ColorRect.new()
	bg.color = TermTheme.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	var bar := HBoxContainer.new()
	column.add_child(bar)
	_title = _label(font, TermTheme.ACCENT)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(_title)
	_status = _label(font, TermTheme.DIM)
	bar.add_child(_status)

	var rule := ColorRect.new()
	rule.color = TermTheme.RULE
	rule.custom_minimum_size = Vector2(0, 2)
	column.add_child(rule)

	_log = RichTextLabel.new()
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.scroll_following = true
	_log.selection_enabled = true
	_log.focus_mode = Control.FOCUS_NONE
	_log.add_theme_font_override("normal_font", font)
	_log.add_theme_font_size_override("normal_font_size", TermTheme.FONT_SIZE)
	_log.add_theme_color_override("default_color", TermTheme.TEXT)
	_log.add_theme_color_override("selection_color", TermTheme.SELECTION)
	column.add_child(_log)
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = TermTheme.RULE
	_log.get_v_scroll_bar().add_theme_stylebox_override("grabber", grabber)
	_log.get_v_scroll_bar().add_theme_stylebox_override("grabber_highlight", grabber)
	_log.get_v_scroll_bar().add_theme_stylebox_override("grabber_pressed", grabber)
	_log.get_v_scroll_bar().add_theme_stylebox_override("scroll", StyleBoxEmpty.new())

	var entry := HBoxContainer.new()
	entry.add_theme_constant_override("separation", 10)
	column.add_child(entry)
	_prompt = _label(font, TermTheme.ACCENT)
	entry.add_child(_prompt)
	_input = LineEdit.new()
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.caret_blink = true
	# Without this, Enter leaves edit mode (focus stays, typing is ignored)
	# and the learner has to click the prompt before every line.
	_input.keep_editing_on_text_submit = true
	_input.add_theme_font_override("font", font)
	_input.add_theme_font_size_override("font_size", TermTheme.FONT_SIZE)
	for key in ["font_color", "font_selected_color", "caret_color"]:
		_input.add_theme_color_override(key, TermTheme.TEXT)
	_input.add_theme_color_override("selection_color", TermTheme.SELECTION)
	for state in ["normal", "focus", "read_only"]:
		_input.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	_input.text_submitted.connect(_on_submitted)
	_input.gui_input.connect(_on_input_key)
	entry.add_child(_input)

	gui_input.connect(_on_root_input)


func _label(font: Font, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", TermTheme.FONT_SIZE)
	l.add_theme_color_override("font_color", color)
	return l


func _refresh_chrome() -> void:
	_title.text = Game.router.title_line()
	_status.text = Game.router.status_line()
	_prompt.text = Game.router.prompt()


func _print_lines(lines: Array) -> void:
	for l in lines:
		_print_line(l)


func _print_line(l: Dictionary) -> void:
	if l.get("cmd", "") == "clear":
		_log.clear()
		return
	_log.push_color(TermTheme.style_color(l["s"]))
	_log.add_text(l["t"])
	_log.pop()
	_log.newline()


func _on_submitted(text: String) -> void:
	_input.clear()
	if text.strip_edges() != "":
		_history.append(text)
	_history_at = _history.size()
	run_line(text)
	_input.grab_focus()


func _on_input_key(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	var mode: CommandRouter.Mode = Game.router.mode
	if _single_key_answer(event):
		_input.accept_event()
		return
	var pbq := Game.router.pbq_active()
	var arrows := mode == CommandRouter.Mode.MAP or mode == CommandRouter.Mode.MENU or pbq
	match event.keycode:
		KEY_UP:
			if arrows:
				run_line("@up")
			else:
				_recall(-1)
		KEY_DOWN:
			if arrows:
				run_line("@down")
			else:
				_recall(1)
		KEY_LEFT, KEY_RIGHT:
			# The home screen's length picker, or between questions of an exam PBQ;
			# a typed line keeps its caret keys.
			if (mode != CommandRouter.Mode.HOME and not pbq) or _input.text != "":
				return
			run_line("@left" if event.keycode == KEY_LEFT else "@right")
		KEY_ESCAPE:
			if mode != CommandRouter.Mode.MAP and not pbq:
				return
			run_line("@esc")
		KEY_PAGEUP:
			_log.get_v_scroll_bar().value -= _log.size.y * 0.8
		KEY_PAGEDOWN:
			_log.get_v_scroll_bar().value += _log.size.y * 0.8
		_:
			return
	_input.accept_event()


## On a one-answer question a bare letter or digit at an empty prompt is the
## answer: no Enter. The router says how many options there are.
func _single_key_answer(event: InputEventKey) -> bool:
	var n := Game.router.single_key_choices()
	if n == 0 or _input.text != "" or event.ctrl_pressed or event.alt_pressed or event.meta_pressed:
		return false
	var key := char(event.unicode).to_lower() if event.unicode > 0 else ""
	if key == "" or key.length() != 1:
		return false
	var idx := -1
	if key >= "a" and key <= "z":
		idx = key.unicode_at(0) - 97
	elif key >= "1" and key <= "9":
		idx = int(key) - 1
	if idx < 0 or idx >= n:
		return false
	run_line(key)
	return true


func _recall(step: int) -> void:
	if _history.is_empty():
		return
	_history_at = clampi(_history_at + step, 0, _history.size())
	_input.text = _history[_history_at] if _history_at < _history.size() else ""
	_input.caret_column = _input.text.length()


## Clicking anywhere in the window returns focus to the prompt.
func _on_root_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_input.grab_focus()
