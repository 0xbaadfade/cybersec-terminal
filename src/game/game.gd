extends Node
## Autoload: owns the profile store and the command router. The view calls
## submit() with whatever the learner typed; it never reaches into src/core
## state to change it.
##
## `--profiles-dir DIR` (after `--`) redirects saves, for captures and tests.

const DEFAULT_PROFILES := "user://profiles"

var store: ProfileStore
var router: CommandRouter


func _ready() -> void:
	configure(_arg("--profiles-dir", DEFAULT_PROFILES))


## (Re)build the store and router over a profiles directory.
func configure(profiles_dir: String) -> void:
	store = ProfileStore.new(profiles_dir)
	router = CommandRouter.new(store, null, null, null, Callable(), Data.catalog)


func submit(line: String) -> Array:
	return router.handle(line)


static func _arg(flag: String, fallback: String) -> String:
	var args := OS.get_cmdline_user_args()
	var i := args.find(flag)
	return args[i + 1] if i != -1 and i + 1 < args.size() else fallback
