extends SceneTree
## ./run.sh validate-pack [DIR]
## Loads a content pack (or every pack under res://packs/) and prints a report.
## With no argument it also checks data/tracks.json. Exit code 1 if any pack or the catalog has errors; coverage gaps are warnings only.


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var dirs: Array = []
	if args.size() > 0 and args[0] != "":
		dirs.append(args[0])
	else:
		for d in DirAccess.get_directories_at("res://packs"):
			dirs.append("res://packs/%s" % d)
	if dirs.is_empty():
		print("no packs found")
		quit(1)
		return
	var failed := 0
	for d in dirs:
		var pack := Pack.load_dir(d)
		print(pack.report())
		if not pack.ok():
			failed += 1
	if args.is_empty() or args[0] == "":
		var catalog := TrackCatalog.load_file()
		var ready := catalog.playable_ids().size()
		print("tracks: %d listed, %d playable" % [catalog.all_tracks().size(), ready])
		for e in catalog.errors:
			print("  ERROR %s" % e)
		if not catalog.ok():
			failed += 1
	quit(1 if failed > 0 else 0)
