extends Node
## Renders the terminal after a scripted session to a PNG, so the look can be
## checked without a window (./run.sh capture).
##
##   ./run.sh capture out.png --lines "new dana;status;pack"
##
## --lines  semicolon-separated lines, typed in order. "<enter>" is a blank
##          line (continue), "<up>"/"<down>"/"<esc>" are the map's keys.
## --seed   seed for shuffles and picks (default 1), so captures are repeatable
## --now    unix time for the clock (default: now)
## It uses a throwaway profiles directory and never touches real saves.


func _args() -> Dictionary:
	var out: Dictionary = {}
	var raw := OS.get_cmdline_user_args()
	var i := 0
	while i < raw.size():
		if (raw[i] as String).begins_with("--") and i + 1 < raw.size():
			out[(raw[i] as String).substr(2)] = raw[i + 1]
			i += 1
		i += 1
	return out


func _ready() -> void:
	var a := _args()
	var tmp := "user://capture_%d" % Time.get_ticks_usec()
	Game.configure(tmp)
	Game.router.rng.seed = int(a.get("seed", 1))
	if a.has("now"):
		var fixed := int(a["now"])
		Game.router.clock = func() -> int: return fixed
	var main: Control = load("res://src/view/main.tscn").instantiate()
	add_child(main)
	var keys := {"<enter>": "", "<up>": "@up", "<down>": "@down", "<esc>": "@esc"}
	for line in (a.get("lines", "") as String).split(";", false):
		main.run_line(keys.get(line, line))
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var out: String = a.get("out", "/tmp/capture.png")
	img.save_png(out)
	print("captured %s (%dx%d)" % [out, img.get_width(), img.get_height()])
	for f in DirAccess.get_files_at(tmp):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp.path_join(f)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
	get_tree().quit()
