extends Node
## Autoload: loads the track catalog and, through it, every content pack.
## All certification content comes through here; nothing else reads packs/.

var catalog: TrackCatalog


func _ready() -> void:
	catalog = TrackCatalog.load_file()
	for e in catalog.errors:
		push_error(e)
