class_name Lines
extends RefCounted
## The shape of terminal output: {"t": text, "s": style}, plus the one
## command line {"cmd": "clear"} that asks the view to wipe the screen.

const S_NORMAL := "n"
const S_DIM := "d"
const S_ACCENT := "a"
const S_ERROR := "e"
const S_OK := "o"

const CLEAR := {"cmd": "clear"}


static func make(text: String, style: String = S_NORMAL) -> Dictionary:
	return {"t": text, "s": style}
