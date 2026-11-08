class_name TermTheme
extends RefCounted
## Colour and type tokens for the terminal look (phosphor green, amber for
## emphasis). One place, so a second theme or a high-contrast option is a
## swap rather than a hunt.

const BG := Color("0a0f0c")
const TEXT := Color("4cf080")
const DIM := Color("2f9a57")
const ACCENT := Color("ffb000")
const ERROR := Color("ff5f5f")
const OK := Color("9bffb8")
const RULE := Color("1d3a28")
const SELECTION := Color(0.3, 0.94, 0.5, 0.25)

const FONT_PATH := "res://assets/fonts/DejaVuSansMono.ttf"
const FONT_SIZE := 18


static func style_color(style: String) -> Color:
	match style:
		CommandRouter.S_DIM:
			return DIM
		CommandRouter.S_ACCENT:
			return ACCENT
		CommandRouter.S_ERROR:
			return ERROR
		CommandRouter.S_OK:
			return OK
	return TEXT
