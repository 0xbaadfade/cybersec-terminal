class_name CommandRouter
extends RefCounted
## The terminal's brain: takes a typed line, returns what to print. Headless,
## so login, map, rounds and the Codex are all testable without a window.
##
## Output is an Array of Lines ({"t", "s"}, or Lines.CLEAR); the view maps a
## style to a colour and knows nothing else. Arrow keys in the map reach us as
## the action strings "@up", "@down", "@enter", "@esc".
##
## Modes: LOGIN, MENU (the track menu; only when a catalog is given), HOME, MAP, ASK (an encounter is waiting for an answer),
## FEEDBACK (the answer is shown; Enter continues), TERMINAL (a lab shell: a mission,
## or free play) and EXAM (the exam simulation, which also holds the PBQs: evidence
## hunts, match and order questions).

const VERSION := "0.2"
const S_NORMAL := Lines.S_NORMAL
const S_DIM := Lines.S_DIM
const S_ACCENT := Lines.S_ACCENT
const S_ERROR := Lines.S_ERROR
const S_OK := Lines.S_OK

const DEBRIEF_WIDTH := 92
## The lengths the picker may offer; the Longer rounds perk decides how many of them are shown.
const SETUP_LENGTHS: Array = [5, 10, 20, 40, 100, 200]
const MAX_QUESTIONS := 200

enum Mode { LOGIN, HOME, MAP, ASK, FEEDBACK, TERMINAL, MENU, EXAM }

var store: ProfileStore
var pack: Pack  # the active track's pack; null at the login and menu screens
var catalog: TrackCatalog
var rules: Rules
var rng: RandomNumberGenerator
var clock: Callable  # () -> int unix seconds; tests inject a fixed one
var mode: Mode = Mode.LOGIN
var profile: Profile = null
var want_quit := false
var current_round: Round = null
var cursor := 0  # index into the map's selectable nodes

var menu_cursor := 0  # index into the menu's playable tracks
var _menu_enabled := false
var _base_ranks: Array = []  # the engine's ladder, for packs that bring none
var _rank_at_start := 0
var _free: TerminalSession = null  # the lab shell of free play (no round, no XP)
var _feedback: Array = []  # the last feedback screen, for redraws
var exam: ExamRun = null  # the exam simulation in progress (mode EXAM)
var _exam_pending := ""  # "submit", "leave" or "quit" while the exam waits for a yes
var _setup_at := 1  # index into _setup_rows(): the length chosen on the home screen (1 = 10 questions)
var _setup_feedback := true  # true: feedback after each question; false: only at the end (an exam run)
var _round_cycles := 0  # Cycles paid for answers in the round in progress
var _round_built: Dictionary = {}  # concept id -> true: met for the first time this round
var _round_stale: Dictionary = {}  # concept id -> true: was due when the round first asked it
var _round_restored: Dictionary = {}  # concept id -> true: a stale concept answered right this round
var _last_save := 0  # unix seconds of the last tick save


## With a `catalog`, login leads to the track menu and `content_pack` is
## ignored. Without one the router plays that one pack with no menu (the
## pack-level tests and tools).
func _init(profile_store: ProfileStore, content_pack: Pack, rules_in: Rules = null,
		rng_in: RandomNumberGenerator = null, clock_in: Callable = Callable(),
		catalog_in: TrackCatalog = null) -> void:
	store = profile_store
	rules = rules_in if rules_in != null else Rules.load_default()
	_base_ranks = rules.ranks.duplicate()
	_menu_enabled = catalog_in != null
	catalog = catalog_in if _menu_enabled else TrackCatalog.single(content_pack)
	if store.legacy_track == "":
		store.legacy_track = catalog.legacy_track
	if not _menu_enabled:
		_use_pack(content_pack.id)
	if rng_in != null:
		rng = rng_in
	else:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	clock = clock_in


func now() -> int:
	return int(clock.call()) if clock.is_valid() else int(Time.get_unix_time_from_system())


func prompt() -> String:
	match mode:
		Mode.ASK:
			return "answer>"
		Mode.FEEDBACK:
			return "continue>"
		Mode.MAP:
			return "map>"
		Mode.MENU:
			return "track>"
		Mode.EXAM:
			if _exam_pending != "":
				return "confirm>"
			return "why?>" if exam.reason_pending() else "exam>"
		Mode.TERMINAL:
			return _term().prompt()
		Mode.HOME:
			return "%s@%s>" % [profile.username, pack.id.get_slice("-", 0)]
	return "login>"


## Right-hand side of the title bar.
func status_line() -> String:
	if profile == null:
		return "not logged in"
	if pack == null:
		# The wallet is the learner's own, so it shows between tracks too once there is one.
		if Economy.has_wallet(profile):
			return "%s | %s" % [profile.username, Economy.summary(profile, Mastery.day_of(now()), rules)]
		return profile.username
	var xp := Mastery.total_xp(profile)
	var s := "%s | %s | %d XP | %s" % [profile.username, rules.rank_name(rules.rank_index(xp)), xp,
			Economy.summary(profile, Mastery.day_of(now()), rules)]
	if current_round != null and not current_round.trace_off:
		s += " | TRACE %d%%" % (current_round.trace * 100 / rules.trace_limit)
	if exam != null:
		s += " | EXAM %d/%d answered | TIME %s" % [exam.answered_count(), exam.size(), ExamScreen.clock_text(exam.seconds_left(now()))]
	return s


func title_line() -> String:
	if pack == null:
		return "CYBERSEC-TERMINAL v%s" % VERSION
	return "CYBERSEC-TERMINAL v%s  //  %s" % [VERSION, pack.short]


func banner() -> Array:
	# The title bar already shows the name and version, so the scrollback does not repeat it.
	var out: Array = []
	if pack != null:
		out.append(_l("%s  //  %d items loaded" % [pack.title, pack.items.size()], S_DIM))
	else:
		out.append(_l("%d of %d tracks ready" % [catalog.playable_ids().size(), catalog.all_tracks().size()], S_DIM))
	out.append(_l(""))
	out.append(_l("Identify yourself."))
	var users := store.list()
	if users.is_empty():
		out.append(_l("  No users yet. Type: new <name>", S_DIM))
	else:
		for i in users.size():
			out.append(_l("  %d  %s" % [i + 1, users[i]]))
		out.append(_l("  Pick a number or a name, or: new <name>", S_DIM))
	out.append(_l("  help for commands", S_DIM))
	return out


func handle(line: String) -> Array:
	_settle()
	var text := line.strip_edges()
	if mode == Mode.EXAM and exam.expired(now()):
		return _exam_submit(true)
	if text == "":
		match mode:
			Mode.EXAM:
				return _exam_command("", "", "")
			Mode.FEEDBACK:
				return _continue()
			Mode.MAP:
				return _map_enter()
			Mode.MENU:
				return _menu_enter()
			Mode.HOME:
				return _setup_start(0)
		return []
	var parts := text.split(" ", false, 1)
	var verb := parts[0].to_lower()
	var rest := parts[1].strip_edges() if parts.size() > 1 else ""
	if verb == "exit" and mode == Mode.TERMINAL:
		return _terminal_exit()
	if mode == Mode.EXAM and (verb == "quit" or verb == "exit"):
		return _exam_command(verb, rest, text) if _exam_pending != "" else _exam_ask("quit")
	if verb == "quit" or verb == "exit":
		return _quit()
	if verb == "clear":
		return _redraw()
	match mode:
		Mode.LOGIN:
			return _login_command(verb, rest, text)
		Mode.ASK:
			return _ask_command(verb, text)
		Mode.FEEDBACK:
			return _feedback_command(verb)
		Mode.MAP:
			return _map_command(verb, rest)
		Mode.MENU:
			return _menu_command(verb, text)
		Mode.TERMINAL:
			return _terminal_command(text, verb, rest)
		Mode.EXAM:
			return _exam_command(verb, rest, text)
	return _home_command(verb, rest)


# --- login -------------------------------------------------------------

func _login_command(verb: String, rest: String, text: String) -> Array:
	match verb:
		"help":
			return [
				_l("login commands", S_ACCENT),
				_l("  <name> | <number>   log in as an existing user"),
				_l("  new <name>          create a user and log in"),
				_l("  list                show users"),
				_l("  quit                leave"),
			]
		"list":
			return banner()
		"new":
			if rest == "":
				return [_l("Usage: new <name>", S_ERROR)]
			var created := store.create(rest)
			if created == null:
				return [_l(store.last_error, S_ERROR)]
			return _enter(created, true)
	var users := store.list()
	if text.is_valid_int() and int(text) >= 1 and int(text) <= users.size():
		return _log_in(users[int(text) - 1])
	if Profile.username_problem(text) != "":
		return [_l("Unknown command or invalid name: '%s'. Type help." % text, S_ERROR)]
	if not store.exists(text):
		return [_l("No such user '%s'. To create it: new %s" % [text, Profile.normalize(text)], S_ERROR)]
	return _log_in(Profile.normalize(text))


func _log_in(name: String) -> Array:
	var p := store.load_profile(name)
	if p == null:
		return [_l(store.last_error, S_ERROR)]
	p.touch(now())
	store.save(p)
	return _enter(p, false)


func _enter(p: Profile, is_new: bool) -> Array:
	profile = p
	Economy.start(profile, now())
	var out: Array = []
	out.append(_l(("Account created. Welcome, %s." if is_new else "Welcome back, %s.") % p.username, S_OK))
	if not is_new:
		out.append(_l("Last seen %s." % _when(int(p.data.get("last_seen", 0))), S_DIM))
	if _menu_enabled:
		mode = Mode.MENU
		menu_cursor = 0
		return out + _menu().screen(_menu_selected())
	mode = Mode.HOME
	profile.track = pack.id
	_setup_reset()
	return out + _arrival_lines(is_new)


## The lines that follow choosing a track (or logging in with only one): one
## progress line, then the setup screen. Nothing else is offered.
func _arrival_lines(is_new: bool) -> Array:
	var due := 0 if is_new else _due_count()
	var xp := Mastery.total_xp(profile)
	var parts: Array = [rules.rank_name(rules.rank_index(xp)), "%d XP" % xp,
			Economy.summary(profile, Mastery.day_of(now()), rules)]
	if due > 0:
		parts.append("%d due for review" % due)
	return [_l(" | ".join(parts), S_ACCENT), _l("")] + _setup_lines()


# --- setup screen (the track's home) -------------------------------------

## The length choices up to the learner's cap (5, 10, 20 to begin with), and the pack's full exam when it has one.
func _setup_rows() -> Array:
	var rows: Array = []
	var cap := Perks.max_questions(profile, rules)
	for n in SETUP_LENGTHS:
		if n <= cap or rows.size() < 2:
			rows.append({"n": n, "exam": false, "label": str(n)})
	var questions := int(pack.exam.get("questions", 0)) if pack != null else 0
	if questions > 0:
		rows.append({"n": questions, "exam": true, "label": "Full exam (%d)" % questions})
	return rows


func _has_exam() -> bool:
	return pack != null and int(pack.exam.get("questions", 0)) > 0


func _setup_lines() -> Array:
	var rows := _setup_rows()
	_setup_at = clampi(_setup_at, 0, rows.size() - 1)
	var cells: Array = []
	for i in rows.size():
		cells.append(("[%s]" if i == _setup_at else " %s ") % rows[i]["label"])
	var out: Array = [_l("How many questions?", S_ACCENT), _l("  " + "   ".join(cells))]
	out.append(_l("Enter starts. Left and Right change the length, or type a number.", S_DIM))
	if rows[_setup_at]["exam"]:
		out.append(_l("The full exam is timed and gives no feedback until you submit.", S_DIM))
		var hands_on := pack.exam_pbq_count()
		if hands_on > 0:
			out.append(_l("It includes %d hands-on questions (flag lines, match, put in order). None of them use the command line." % hands_on, S_DIM))
		out.append(_l(_exam_record_text(), S_DIM))
	elif _has_exam():
		out.append(_l("Feedback: %s   (type f to change)" % ("after each question" if _setup_feedback else "only at the end"), S_DIM))
	return out


## "Pass at 70%. Your best: 64% in 2 tries." for the Full exam row of the setup screen.
func _exam_record_text() -> String:
	var bits: Array = []
	var mark := pack.pass_text()
	if mark != "":
		bits.append(mark.substr(0, 1).to_upper() + mark.substr(1) + ".")
	var tries := Exams.attempts(profile)
	if tries > 0:
		bits.append("Your best: %d%% in %d %s.%s" % [Exams.best_percent(profile), tries, "try" if tries == 1 else "tries",
				"  Passed." if Exams.passed(profile) else ""])
	else:
		bits.append("Not taken yet.")
	return " ".join(bits)


func _setup_screen() -> Array:
	return [Lines.CLEAR] + _setup_lines()


func _setup_reset() -> void:
	_setup_at = 1
	_setup_feedback = true


## `n` > 0 is a typed number of questions; 0 means the highlighted choice.
func _setup_start(n: int) -> Array:
	var rows := _setup_rows()
	var row: Dictionary = rows[clampi(_setup_at, 0, rows.size() - 1)]
	if n <= 0 and row["exam"]:
		return _start_exam("")
	var count: int = n if n > 0 else int(row["n"])
	if count > MAX_QUESTIONS:
		return [_l("At most %d questions at a time." % MAX_QUESTIONS, S_ERROR)]
	var cap := Perks.max_questions(profile, rules)
	if count > cap:
		return [_l("Your rounds go up to %d questions. The Longer rounds perk raises that: type perks." % cap, S_ERROR)]
	if not _setup_feedback and _has_exam():
		return _start_exam(str(count))
	return _start_sized_round(count)


func _setup_command(verb: String) -> Array:
	var rows := _setup_rows()
	match verb:
		"@left", "@right":
			_setup_at = posmod(_setup_at + (-1 if verb == "@left" else 1), rows.size())
			return _setup_screen()
		"f", "feedback":
			if not _has_exam():
				return [_l("This track always shows feedback after each question.", S_DIM)]
			_setup_feedback = not _setup_feedback
			return _setup_screen()
	return []


# --- track menu ----------------------------------------------------------

func _menu() -> MenuModel:
	return MenuModel.new(catalog, profile, rules, _base_ranks, Mastery.day_of(now()))


func _menu_selected() -> String:
	var ids := _menu().selectable()
	if ids.is_empty():
		return ""
	menu_cursor = clampi(menu_cursor, 0, ids.size() - 1)
	return ids[menu_cursor]


func _menu_screen() -> Array:
	return [Lines.CLEAR] + _menu().screen(_menu_selected())


func _menu_command(verb: String, text: String) -> Array:
	match verb:
		"@up", "@down":
			menu_cursor += -1 if verb == "@up" else 1
			return _menu_screen()
		"@enter":
			return _menu_enter()
		"@esc":
			return []
		"help":
			var help: Array = [_l("tracks: arrows move, Enter chooses; or type a number or a name.", S_DIM)]
			if _menu().tree != null:
				help.append(_l("open <number> unlocks a track that shows a price (paid in cycles).", S_DIM))
			help.append(_l("perks is the shop: buy <number> spends cycles on an upgrade.", S_DIM))
			help.append(_l("logout switches user. quit leaves. Your progress is kept per track.", S_DIM))
			return help
		"menu", "tracks":
			return _menu_screen()
		"open":
			return _menu_open(text.substr(4).strip_edges())
		"perks":
			return _perks_screen()
		"buy":
			return _buy(text.substr(3).strip_edges())
		"logout":
			return _logout()
	var id := _menu().resolve(text)
	if id == "":
		return [_l("No such track '%s'. Type a number from the list." % text, S_ERROR)]
	return _choose_track(id)


## The perks shop (README "Skill tree Phase T3 plan").
func _perks_screen() -> Array:
	return [Lines.CLEAR] + PerksScreen.lines(profile, rules, Mastery.day_of(now()))


## `buy <number or id>`: pay for the next level of a perk.
func _buy(arg: String) -> Array:
	if arg == "":
		return [_l("Type buy and a perk number from the perks list.", S_DIM)]
	var id := Perks.resolve(rules, arg)
	if id == "":
		return [_l("No such perk '%s'. Type perks for the list." % arg, S_ERROR)]
	var err := Perks.buy(profile, rules, id)
	if err != "":
		return [_l(err, S_ERROR)]
	var out: Array = []
	if not store.save(profile):
		out.append(_l("Could not save your progress: %s" % store.last_error, S_ERROR))
	var title: String = Perks.perk(rules, id)["title"]
	return _perks_screen() + [_l(""), _l("%s is now level %d." % [title, Perks.level(profile, id)], S_OK)] + out


## `open <n>`: pay for a track the tree shows as ready to open.
func _menu_open(arg: String) -> Array:
	var m := _menu()
	if m.tree == null:
		return [_l("No track here has to be unlocked.", S_DIM)]
	if arg == "":
		return [_l("Type open and a track number, for a track that shows a price.", S_DIM)]
	var id := m.resolve(arg)
	if id == "":
		return [_l("No such track '%s'. Type a number from the list." % arg, S_ERROR)]
	var err := m.tree.open(id, now())
	if err != "":
		return [_l(err, S_ERROR)]
	var out: Array = []
	if not store.save(profile):
		out.append(_l("Could not save your progress: %s" % store.last_error, S_ERROR))
	return [Lines.CLEAR] + _menu().screen(id) + [_l(""), _l("Opened %s." % catalog.track(id)["title"], S_OK)] + out


func _menu_enter() -> Array:
	var id := _menu_selected()
	if id == "":
		return [_l("There is no playable track yet.", S_ERROR)]
	return _choose_track(id)


func _choose_track(id: String) -> Array:
	var t := catalog.track(id)
	match t["status"]:
		TrackCatalog.SOON:
			return [_l("%s is coming soon; it has no content yet." % t["title"], S_DIM)]
		TrackCatalog.UNAVAILABLE:
			return [_l("%s is unavailable: %s." % [t["title"], t["reason"]], S_ERROR)]
	var tree := _menu().tree
	if tree != null and tree.state(id) != TreeModel.OPEN:
		return [_l(tree.explain(id), S_ERROR if tree.state(id) == TreeModel.LOCKED else S_DIM)]
	_activate(id)
	return [Lines.CLEAR, _l(t["title"], S_ACCENT)] + _arrival_lines(not profile.has_track(id))


## Make `id`'s pack the one being played, with its own rank ladder.
func _activate(id: String) -> void:
	_use_pack(id)
	profile.track = id
	mode = Mode.HOME
	cursor = 0
	_free = null
	_setup_reset()


func _use_pack(id: String) -> void:
	pack = catalog.pack_for(id)
	rules.ranks = pack.ranks if not pack.ranks.is_empty() else _base_ranks


func _leave_track() -> Array:
	store.save(profile)  # passive Cycles since the last save
	pack = null
	profile.track = ""
	mode = Mode.MENU
	menu_cursor = 0
	return _menu_screen()


func _logout() -> Array:
	store.save(profile)
	profile = null
	if _menu_enabled:
		pack = null
	mode = Mode.LOGIN
	return [_l("Logged out.", S_DIM), _l("")] + banner()


# --- home --------------------------------------------------------------

func _home_command(verb: String, rest: String) -> Array:
	if rest == "" and verb.is_valid_int():
		return _setup_start(int(verb))
	if verb in ["@left", "@right", "f", "feedback"]:
		return _setup_command(verb)
	match verb:
		"help":
			if rest != "all":
				return [
					_l("Press Enter to start, or type how many questions you want (for example 15).", S_DIM),
					_l("  status   your rank and XP"),
					_l("  grid     your nodes and the cycles they earn"),
					_l("  perks    spend cycles on upgrades"),
					_l("  menu     choose another track"),
					_l("  logout   switch user"),
					_l("  quit     leave"),
					_l("help all lists every command.", S_DIM),
				]
			return [
				_l("commands", S_ACCENT),
				_l("  map            the objective map (arrows and Enter)"),
				_l("  breach [node]  start a round; no node = a review round"),
				_l("  exam [n]       a timed exam simulation, no feedback until you submit"),
				_l("  codex [n|id]   the concepts you have met, or one in detail"),
				_l("  lab [id]       a lab to explore freely: use the tools, no question, no XP"),
				_l("  grid [domain]  your nodes: cycles earned, which are stale (due for review)"),
				_l("  perks          the shop: buy <number> spends cycles on an upgrade"),
				_l("  status         rank, XP, what is due"),
				_l("  pack           the loaded certification pack"),
				_l("  menu           choose another track"),
				_l("  logout         switch user"),
				_l("  clear          clear the screen"),
				_l("  quit           leave"),
			]
		"status", "whoami":
			return _status()
		"pack":
			return _pack_summary()
		"map":
			return _open_map()
		"breach":
			return _start_round(rest)
		"lab":
			return _start_lab(rest)
		"exam":
			return _start_exam(rest)
		"grid":
			return GridScreen.lines(pack, profile, rules, Mastery.day_of(now()), rest)
		"perks":
			return _perks_screen()
		"buy":
			return _buy(rest)
		"codex":
			if rest == "":
				return Codex.list_lines(pack, profile)
			return Codex.detail_lines(pack, profile, rest, Mastery.day_of(now()))
		"menu", "tracks":
			if not _menu_enabled:
				return [_l("There is only one track.", S_DIM)]
			return _leave_track()
		"logout":
			return _logout()
	return [_l("Unknown command '%s'. Type help." % verb, S_ERROR)]


func _status() -> Array:
	var xp := Mastery.total_xp(profile)
	var idx := rules.rank_index(xp)
	var to_next := rules.xp_to_next(xp)
	var out: Array = [
		_l("user         %s" % profile.username, S_ACCENT),
		_l("rank         %s" % rules.rank_name(idx)),
		_l("xp           %d%s" % [xp, "" if to_next < 0 else "  (%d to %s)" % [to_next, rules.rank_name(idx + 1)]]),
	]
	for d in pack.domains:
		out.append(_l("  domain %s   %4d xp   %s" % [d["id"], Mastery.domain_xp(profile, d["id"]), d["title"]], S_DIM))
	var met := 0
	for cid in pack.concepts:
		if Mastery.seen_of(profile, pack.topics_of(cid)) > 0:
			met += 1
	out.append(_l("concepts met %d of %d" % [met, pack.concepts.size()]))
	out.append(_l("due today    %d" % _due_count()))
	out.append(_l("best streak  %d" % int(profile.peek().get("best_streak", 0))))
	out.append(_l("sessions     %d   member since %s" % [int(profile.data["sessions"]), _when(int(profile.data["created"]))], S_DIM))
	return out


func _pack_summary() -> Array:
	var out: Array = []
	out.append(_l(pack.title, S_ACCENT))
	var exam := pack.exam
	if not exam.is_empty():
		var pass_text := pack.pass_text()
		out.append(_l("exam: %d questions, %d minutes%s" % [
				int(exam.get("questions", 0)), int(exam.get("minutes", 0)), ", " + pass_text if pass_text != "" else ""], S_DIM))
	out.append(_l(""))
	for d in pack.domains:
		out.append(_l("  %s  %-44s %3d%%   %2d items" % [
				d["id"], d["title"], int(d["weight"]), pack.count_items(d["id"])]))
	var s := pack.stats()
	out.append(_l(""))
	out.append(_l("%d items (%d reviewed by a person, %d by AI)" % [s["items"], s["human"], s["ai"]], S_DIM))
	return out


## Concepts due today across every node the learner can breach.
func _due_count() -> int:
	return Scheduler.due_concepts(pack, profile, _map().open_ids(), Mastery.day_of(now())).size()


# --- map ---------------------------------------------------------------

func _map() -> MapModel:
	return MapModel.new(pack, profile, rules)


func _open_map() -> Array:
	mode = Mode.MAP
	return [Lines.CLEAR] + _map_screen()


func _map_screen() -> Array:
	var m := _map()
	var ids := m.selectable()
	cursor = clampi(cursor, 0, maxi(0, ids.size() - 1))
	return m.screen(ids[cursor] if not ids.is_empty() else "")


func _map_command(verb: String, rest: String) -> Array:
	match verb:
		"@up", "@down":
			cursor += -1 if verb == "@up" else 1
			return [Lines.CLEAR] + _map_screen()
		"@enter":
			return _map_enter()
		"@esc", "esc", "back", "leave":
			mode = Mode.HOME
			return [Lines.CLEAR, _l("Back at the prompt. Type help for commands.", S_DIM)]
		"map":
			return [Lines.CLEAR] + _map_screen()
		"breach":
			return _start_round(rest)
		"help":
			return [_l("map: arrows move, Enter breaches, Esc leaves; or type breach <node>, codex, status.", S_DIM)]
	return _home_command(verb, rest)


func _map_enter() -> Array:
	var ids := _map().selectable()
	if ids.is_empty():
		return [_l("There is nothing to breach yet.", S_ERROR)]
	return _start_round(ids[clampi(cursor, 0, ids.size() - 1)])


# --- rounds ------------------------------------------------------------

## `node_id` "" is a review round across every open node.
func _start_round(node_id: String) -> Array:
	var m := _map()
	var entries: Array
	var target := node_id.strip_edges()
	if target == "":
		var fresh := m.first_unfinished()
		entries = Scheduler.pick(pack, profile, m.open_ids(), [fresh] if fresh != "" else [], rules, now(), rng)
	else:
		var n := m.node(target)
		if n.is_empty():
			return [_l("No such node '%s'. Type map to see them." % target, S_ERROR)]
		if n["state"] == "empty":
			return [_l("%s has no content yet." % target, S_ERROR)]
		if n["state"] == "locked":
			return [_l("%s is locked. Get at least half of %s's concepts solid first." % [target, n["gate"]], S_ERROR)]
		entries = Scheduler.pick(pack, profile, [target], [target], rules, now(), rng)
	if entries.is_empty():
		return [_l("Nothing to practise there yet.", S_ERROR)]
	var kinds := {"review": 0, "new": 0, "practice": 0}
	for e in entries:
		kinds[e["kind"]] += 1
	var title := "BREACH %s" % target if target != "" else "BREACH  //  review round"
	var head: Array = [Lines.CLEAR, _l(title, S_ACCENT),
			_l("%d encounters: %d to review, %d new, %d practice." % [entries.size(), kinds["review"], kinds["new"], kinds["practice"]], S_DIM),
			_l("TRACE [%s] 0%%" % "░".repeat(10), S_DIM)]
	return head + _begin_round(entries, target, false)


## The home screen's quick round: exactly `n` questions when the pack has them,
## across every open node, with no Trace meter (the learner chose the length).
func _start_sized_round(n: int) -> Array:
	var m := _map()
	var open := m.open_ids()
	var fresh := m.first_unfinished()
	var new_scope: Array = [fresh] if fresh != "" else []
	for id in open:
		if id != fresh:
			new_scope.append(id)
	var entries := Scheduler.pick(pack, profile, open, new_scope, rules, now(), rng, n)
	if entries.is_empty():
		return [_l("There are no questions to ask yet.", S_ERROR)]
	var out: Array = [Lines.CLEAR, _l(ExamScreen.plural(entries.size(), "question"), S_ACCENT)]
	if entries.size() < n:
		out.append(_l("Only %d are available right now, so this round is shorter than the %d you asked for." % [entries.size(), n], S_DIM))
	return out + _begin_round(entries, "", true)


## Create the round for `entries`, start its first encounter and show it.
func _begin_round(entries: Array, target: String, quick: bool) -> Array:
	current_round = Round.new(pack, rules, entries, rng, target)
	current_round.trace_off = quick
	current_round.start_encounter()
	current_round.started_at = now()
	_round_cycles = 0
	_round_built = {}
	_round_stale = {}
	_round_restored = {}
	_rank_at_start = rules.rank_index(Mastery.total_xp(profile))
	return _enter_encounter()


## Switch to the mode the current encounter needs and show it.
func _enter_encounter() -> Array:
	mode = Mode.TERMINAL if current_round.is_terminal() else Mode.ASK
	return _encounter_lines()


func _encounter_lines() -> Array:
	var r := current_round
	if r.is_terminal():
		return _terminal_banner()
	var entry := r.current()
	var it := r.item()
	var kind: String = {"new": "NEW", "review": "REVIEW", "retry": "RETRY", "practice": "PRACTICE"}.get(entry["kind"], "")
	var out: Array = [_l(""),
			_l("%s %d/%d  //  %s  //  %s" % ["QUESTION" if r.trace_off else "ENCOUNTER", r.index + 1, r.queue.size(), pack.concepts[entry["concept"]]["objective"], kind], S_ACCENT),
			_l(it["stem"]), _l("")]
	if it.has("show"):
		out.append_array(show_lines(it["show"]))
		out.append(_l(""))
	for o in r.options():
		out.append(_l("  %s  %s" % [(o["letter"] as String).to_upper(), o["text"]]))
	out.append(_l(""))
	var last := char(96 + r.order.size()).to_upper()
	if it["type"] == "multi":
		out.append(_l("Choose ALL that apply. Type letters or digits, e.g. a d or 1 4, then Enter.   (leave ends the round)", S_DIM))
	else:
		out.append(_l("Choose ONE. Press a letter A-%s or a digit 1-%d.   (leave ends the round)" % [last, r.order.size()], S_DIM))
	return out


## The lab command a question shows, as a learner would see it typed: the prompt,
## the command and what the emulator prints.
func show_lines(show: Dictionary) -> Array:
	var session := TerminalSession.new(pack.labs[show["lab"]], pack.tool_docs, pack.concept_titles(), {}, rules)
	var res := session.run(show["command"], now())
	var out: Array = [_l("%s %s" % [session.prompt(), show["command"]], S_DIM)]
	for line in res["out"]:
		out.append(_l(line))
	return out


func _ask_command(verb: String, text: String) -> Array:
	if verb == "leave":
		return _finish()
	if verb == "help":
		return [_l("Type the letter(s) of your answer. leave ends the round (progress is kept).", S_DIM)]
	var parsed := current_round.parse(text)
	if not parsed["ok"]:
		return [_l(parsed["error"], S_ERROR)]
	return _answer(parsed["picks"])


func _answer(picks: Array) -> Array:
	return _commit(current_round.submit(picks))


## Apply a scored answer (from either item kind) to the profile and show it.
func _commit(res: Dictionary) -> Array:
	var r := current_round
	var entry := r.current()
	var out: Array = []
	var cid: String = entry["concept"]
	var today := Mastery.day_of(now())
	var was_stale := Mastery.is_due_of(profile, pack.topics_of(cid), today)
	if Mastery.seen_of(profile, pack.topics_of(cid)) == 0:
		_round_built[cid] = true
	if was_stale:
		_round_stale[cid] = true
	if res["credit"] >= 1.0 and _round_stale.has(cid):
		_round_restored[cid] = true
	Mastery.apply(profile, res["item"], res["credit"], now(), rules)
	Mastery.add_xp(profile, pack.domain_of_concept(cid), res["xp"])
	res["cycles"] = Economy.award(profile, cid, res["xp"], res["credit"], today, rules)
	_round_cycles += res["cycles"]
	Mastery.note_streak(profile, r.best_streak)
	if not store.save(profile):
		out.append(_l("Could not save your progress: %s" % store.last_error, S_ERROR))
	if _auto_advances(res):
		# A fully right mcq/multi answer: show the feedback, then go straight on.
		out.append_array(_feedback_lines(res, false))
		r.advance()
		_feedback = []
		return out + _enter_encounter()
	_feedback = out + _feedback_lines(res)
	mode = Mode.FEEDBACK
	return _feedback.duplicate()


## True when a scored answer needs no Enter before the next question: setting
## on, a fully right mcq/multi answer, the round still running, and the next
## encounter another mcq/multi (a lab mission starts after a pause).
func _auto_advances(res: Dictionary) -> bool:
	var r := current_round
	if not rules.auto_advance_correct or res.has("terminal"):
		return false
	if res["credit"] < 1.0 or r.outcome != "" or r.index + 1 >= r.queue.size():
		return false
	return not Pack.is_pbq(pack.items[r.queue[r.index + 1]["item"]])


## True while an exam PBQ is on screen: the view then sends the arrow keys (and Esc)
## as actions, and Left/Right move between questions.
func pbq_active() -> bool:
	return mode == Mode.EXAM and exam != null and exam.is_pbq_at(exam.index)


## How many options a single keypress can pick from: the option count while an
## mcq is on screen, otherwise 0. The view uses it to submit a bare letter or
## digit with no Enter.
func single_key_choices() -> int:
	if mode == Mode.EXAM:
		if exam == null or _exam_pending != "":
			return 0
		return exam.single_key_choices()
	if mode != Mode.ASK or current_round == null or current_round.is_over():
		return 0
	if current_round.item()["type"] != "mcq":
		return 0
	return current_round.order.size()


func _feedback_lines(res: Dictionary, wait: bool = true) -> Array:
	var r := current_round
	var credit: float = res["credit"]
	var label := "CORRECT" if credit >= 1.0 else ("PARTIAL" if credit > 0.0 else "INCORRECT")
	var style := S_OK if credit >= 1.0 else (S_ACCENT if credit > 0.0 else S_ERROR)
	var head := "%s   +%d XP" % [label, res["xp"]]
	if res.get("cycles", 0) > 0:
		head += "   +%d cycles" % res["cycles"]
	if res["streak"] > 1:
		head += "   streak x%d" % res["streak"]
	var out: Array = [_l(""), _l(head, style)]
	if not r.trace_off:
		out.append(_l(_trace_line(), S_DIM))
	out.append(_l(""))
	out.append(_l("Concept: %s" % pack.concepts[res["concept"]]["title"], S_DIM))
	if res.has("terminal"):
		return out + _terminal_debrief(res)
	if credit < 1.0:
		out.append_array(_comparison_lines(res))
		out.append(_l(""))
	var explain := Pack.explain_of(res["item"])
	if explain != "":
		out.append(_l(explain))
	for w in res["wrong"]:
		if w["why"] != "":
			out.append(_l("  %s is wrong: %s" % [r.letter_of(w["id"]).to_upper(), w["why"]], S_DIM))
	out.append_array(_reference_lines(res["item"]))
	return out + _feedback_tail(res, wait)


## What the learner chose against what was right, shown before the explanation.
## One answer: "You chose" and "Correct" on a line each. Several answers: the
## chosen options (wrong ones in the error colour), then the ones missed.
func _comparison_lines(res: Dictionary) -> Array:
	var chosen: Array = []
	var missed: Array = []
	var right: Array = []
	for o in current_round.options():
		var row := "%s  %s" % [(o["letter"] as String).to_upper(), o["text"]]
		var is_right: bool = res["correct"].has(o["id"])
		if is_right:
			right.append(row)
		if res["picks"].has(o["id"]):
			chosen.append({"row": row, "right": is_right})
		elif is_right:
			missed.append(row)
	var out: Array = []
	if current_round.item()["type"] != "multi":
		out.append(_l("You chose: %s" % chosen[0]["row"], S_ERROR))
		out.append(_l("Correct:   %s" % right[0], S_OK))
		return out
	out.append(_l("You chose:", S_NORMAL))
	for c in chosen:
		out.append(_l("  " + c["row"], S_OK if c["right"] else S_ERROR))
	if not missed.is_empty():
		out.append(_l("Missed:", S_NORMAL))
		for row in missed:
			out.append(_l("  " + row, S_ACCENT))
	return out


## The lines every feedback screen ends with.
func _feedback_tail(res: Dictionary, wait: bool = true) -> Array:
	var out: Array = []
	if res["requeue_gap"] > 0:
		out.append(_l("This concept comes back in %d %s." % [res["requeue_gap"], "questions" if current_round.trace_off else "encounters"], S_ACCENT))
	if res["traced"]:
		out.append(_l("TRACE LIMIT REACHED. The round ends here; everything you earned is kept.", S_ERROR))
	if wait:
		out.append(_l(""))
		out.append(_l("Press Enter to continue.", S_DIM))
	return out


func _feedback_command(verb: String) -> Array:
	if verb == "leave":
		return _finish()
	if verb == "next" or verb == "continue":
		return _continue()
	return [_l("Press Enter to continue, or type leave to end the round.", S_DIM)]


func _continue() -> Array:
	var r := current_round
	if r.outcome == "traced" or not r.advance():
		return _finish()
	return _enter_encounter()


func _finish() -> Array:
	var r := current_round
	r.leave()
	var logged := ""
	if r.answered > 0:
		profile.log_round({"at": r.started_at, "node": r.node_id, "outcome": r.outcome, "answered": r.answered,
				"full": r.full, "xp": r.xp, "trace_peak": r.trace_peak,
				"best_streak": r.best_streak, "seconds": maxi(0, now() - r.started_at)})
		if not store.save(profile):
			logged = "Could not save your progress: %s" % store.last_error
	var heading: String = {"complete": "ROUND COMPLETE", "traced": "TRACED", "left": "ROUND ENDED EARLY"}[r.outcome]
	var out: Array = [_l(""), _l(heading, S_ERROR if r.outcome == "traced" else S_ACCENT)]
	if logged != "":
		out.append(_l(logged, S_ERROR))
	if r.answered == 0:
		out.append(_l("No answers this round.", S_DIM))
	else:
		out.append(_l("%d of %d fully correct   +%d XP   best streak %d" % [r.full, r.answered, r.xp, r.best_streak]))
	var xp := Mastery.total_xp(profile)
	var idx := rules.rank_index(xp)
	if idx > _rank_at_start:
		out.append(_l("RANK UP: %s -> %s" % [rules.rank_name(_rank_at_start), rules.rank_name(idx)], S_OK))
	var to_next := rules.xp_to_next(xp)
	out.append(_l("%s, %d XP%s" % [rules.rank_name(idx), xp, "" if to_next < 0 else ", %d to %s" % [to_next, rules.rank_name(idx + 1)]], S_DIM))
	if r.answered > 0:
		var made: Array = []
		if _round_built.size() > 0:
			made.append("%d node%s built" % [_round_built.size(), "" if _round_built.size() == 1 else "s"])
		if _round_restored.size() > 0:
			made.append("%d brought back online" % _round_restored.size())
		out.append(_l("+%s cycles%s" % [Economy.format_int(_round_cycles), "   " + ", ".join(made) if not made.is_empty() else ""], S_OK))
		out.append(_l("%s   (grid shows your nodes)" % Economy.summary(profile, Mastery.day_of(now()), rules), S_DIM))
	var tomorrow := Scheduler.due_concepts(pack, profile, _map().open_ids(), Mastery.day_of(now()) + 1).size()
	if tomorrow > 0:
		out.append(_l("%d concept%s will be due for review by tomorrow." % [tomorrow, "" if tomorrow == 1 else "s"], S_DIM))
	current_round = null
	_feedback = []
	mode = Mode.HOME
	return out + [_l("")] + _setup_lines()


func _trace_line() -> String:
	var r := current_round
	var cells := clampi(r.trace * 10 / rules.trace_limit, 0, 10)
	return "TRACE [%s%s] %d%%" % ["█".repeat(cells), "░".repeat(10 - cells), r.trace * 100 / rules.trace_limit]


# --- exam simulation ---------------------------------------------------

## `exam` alone is the pack's standard exam; `exam 20` a shorter one. The time
## allowed scales with the number of questions actually asked.
func _start_exam(rest: String) -> Array:
	var block := pack.exam
	var standard := int(block.get("questions", 0))
	var n := standard
	if rest != "":
		if not rest.is_valid_int() or int(rest) < 1:
			return [_l("exam [n]: n is how many questions, for example: exam 20", S_ERROR)]
		n = int(rest)
	if block.is_empty() or n < 1:
		return [_l("This pack has no exam.", S_ERROR)]
	var hands_on := pack.exam_pbq_count() if standard > 0 and n >= standard else 0
	var picked := Scheduler.exam_pick(pack, profile, n, rng, hands_on)
	if picked.is_empty():
		return [_l("There are no questions to build an exam from yet.", S_ERROR)]
	var minutes := 0
	if standard > 0 and int(block.get("minutes", 0)) > 0:
		minutes = Perks.exam_minutes(profile, rules, (picked.size() * int(block["minutes"]) + standard - 1) / standard)
	exam = ExamRun.new(pack, picked, rng, now(), minutes, rules)
	exam.full = standard > 0 and n >= standard
	mode = Mode.EXAM
	var out: Array = [Lines.CLEAR, _l("EXAM SIMULATION", S_ACCENT),
			_l("%s, %s." % [ExamScreen.plural(picked.size(), "question"), ExamScreen.plural(minutes, "minute") if minutes > 0 else "no time limit"])]
	if picked.size() < n:
		out.append(_l("The pack has only %d usable questions, so this exam is shorter than the %d asked for." % [picked.size(), n], S_ERROR))
	if exam.pbq_total() > 0:
		out.append(_l("Questions 1 to %d are hands-on (flag lines, match, put in order); none use the command line. There, Enter acts on the highlighted row and next moves on." % exam.pbq_total(), S_ACCENT))
	out.append(_l("Questions are mixed across the domains by their exam weights, locked nodes included. No feedback until you submit.", S_DIM))
	out.append(_l("Mastery is updated when you submit; leaving changes nothing. No XP and no Trace.", S_DIM))
	if not exam.full:
		out.append(_l("This is shorter than the full exam (%d), so its result will not be recorded." % standard, S_DIM))
	out.append(_l(""))
	return out + _exam_screen()


func _exam_screen() -> Array:
	var it := exam.item_at(exam.index)
	return ExamScreen.question(exam, now(), show_lines(it["show"]) if it.has("show") else [])


## Words the exam keeps for itself on a PBQ question; every other input goes to the PBQ.
const EXAM_WORDS: Array = ["next", "n", "prev", "previous", "p", "goto", "flag", "list", "submit", "leave", "help", "@left", "@right"]


func _exam_command(verb: String, rest: String, text: String) -> Array:
	if _exam_pending != "":
		return _exam_resolve(verb)
	if exam.is_pbq_at(exam.index):
		var open_menu := exam.reason_pending()
		var keeps := EXAM_WORDS.has(verb) and not (open_menu and verb != "submit" and verb != "leave" and verb != "list" and verb != "help")
		if not keeps:
			var problem := exam.pbq_command(verb, rest)
			if problem != "":
				return [_l(problem, S_ERROR)]
			return [Lines.CLEAR] + _exam_screen()
	match verb:
		"@right":
			return _exam_go(exam.index + 2, "That was the last question. list shows what is blank or flagged; submit ends the exam.")
		"@left":
			return _exam_go(exam.index, "This is the first question.")
		"", "next", "n":
			return _exam_go(exam.index + 2, "That was the last question. list shows what is blank or flagged; submit ends the exam.")
		"prev", "previous", "p":
			return _exam_go(exam.index, "This is the first question.")
		"goto":
			if not rest.is_valid_int():
				return [_l("goto N, where N is a question number from 1 to %d." % exam.size(), S_ERROR)]
			return _exam_go(int(rest), "There is no question %s. The exam has %d." % [rest, exam.size()])
		"flag":
			exam.toggle_flag()
			return [Lines.CLEAR] + _exam_screen()
		"list":
			return [Lines.CLEAR] + ExamScreen.listing(exam)
		"submit":
			return _exam_ask("submit")
		"leave":
			return _exam_ask("leave")
		"help":
			if exam.is_pbq_at(exam.index):
				return PbqScreen.help(exam, exam.index) + [
						_l("next, prev, goto N move between questions; flag marks one for review; list shows every question's state;", S_DIM),
						_l("submit ends the exam; leave discards it. clear redraws.", S_DIM)]
			return [_l("Answer with a letter or digit (a multi: several, then Enter). next or Enter, prev, goto N move; flag marks a question;", S_DIM),
					_l("list shows every question's state; submit ends the exam; leave discards it. clear redraws.", S_DIM)]
	var parsed := exam.parse(text)
	if not parsed["ok"]:
		return [_l(parsed["error"], S_ERROR)]
	exam.answer(parsed["picks"])
	return [Lines.CLEAR] + _exam_screen()


## Show question number `n` (1-based), or `refusal` if there is none.
func _exam_go(n: int, refusal: String) -> Array:
	if not exam.goto(n):
		return [_l(refusal, S_DIM)]
	return [Lines.CLEAR] + _exam_screen()


func _exam_ask(what: String) -> Array:
	_exam_pending = what
	if what == "submit":
		var flagged := exam.flags.size()
		return [_l(""), _l("Submit now? %d answered, %d blank%s." % [exam.answered_count(), exam.size() - exam.answered_count(),
				", %d flagged" % flagged if flagged > 0 else ""], S_ACCENT),
				_l("Type yes to submit; anything else goes back to the exam.", S_DIM)]
	return [_l(""), _l("Leave the exam? Nothing you answered will count and your progress is not changed.", S_ACCENT),
			_l("Type yes to leave; anything else goes back to the exam.", S_DIM)]


func _exam_resolve(verb: String) -> Array:
	var what := _exam_pending
	_exam_pending = ""
	var same := verb == what or (what == "quit" and verb == "exit")
	if verb == "yes" or verb == "y" or same:
		if what == "submit":
			return _exam_submit(false)
		exam = null
		mode = Mode.HOME
		if what == "quit":
			return _quit()
		return [Lines.CLEAR, _l("Exam discarded. Nothing was changed. Back at the prompt.", S_DIM)]
	return [Lines.CLEAR, _l("Back to the exam.", S_DIM)] + _exam_screen()


## Score the exam, apply mastery for the answered questions, log it, go home.
## No XP, no Trace; blank questions are not applied (the learner never met them).
func _exam_submit(timed_out: bool) -> Array:
	var e := exam
	var res := e.result()
	var used := maxi(0, now() - e.started_at)
	if e.minutes > 0:
		used = mini(used, e.minutes * 60)
	var problem := ""
	var rec := {}
	if e.answered_count() > 0:
		for i in e.size():
			if e.answers.has(i):
				Mastery.apply(profile, e.item_at(i), e.credit_at(i), now(), rules)
		profile.log_round({"at": e.started_at, "node": "exam", "outcome": "timeout" if timed_out else "complete",
				"answered": res["answered"], "full": res["full"], "xp": 0, "trace_peak": 0, "best_streak": 0,
				"seconds": used, "questions": res["questions"], "percent": res["percent"], "pbqs": res["pbqs"]})
		rec = Exams.record(profile, pack, res["percent"], now(), e.full)
		if rec["first_pass"]:
			Economy.add(profile, rules.eco_exam_pass_cycles)
		if not store.save(profile):
			problem = "Could not save your progress: %s" % store.last_error
	var out: Array = [Lines.CLEAR] + ExamScreen.result(e, res, used, timed_out, pack.pass_text())
	out.append_array(_exam_record_lines(e, rec))
	if problem != "":
		out.append(_l(problem, S_ERROR))
	out.append(_l(""))
	exam = null
	_exam_pending = ""
	mode = Mode.HOME
	return out + _setup_lines()


## What the result screen adds about the track's record (README "Skill tree Phase T2 plan").
func _exam_record_lines(e: ExamRun, rec: Dictionary) -> Array:
	if e.answered_count() == 0:
		return []
	if not rec.get("recorded", false):
		return [_l(""), _l("This was shorter than the full exam, so the result is not recorded.", S_DIM)]
	var tries := Exams.attempts(profile)
	var out: Array = [_l(""), _l("Recorded. Best on this track: %d%% in %d %s.%s" % [Exams.best_percent(profile), tries,
			"try" if tries == 1 else "tries", "  New best!" if rec["new_best"] and rec["previous_best"] >= 0 else ""], S_ACCENT)]
	if rec["first_pass"]:
		out.append(_l("PASSED for the first time: +%s cycles." % Economy.format_int(rules.eco_exam_pass_cycles), S_OK))
	elif rec["passed"]:
		out.append(_l("Passed again.", S_DIM))
	return out


## Called by the view once a second while an exam runs: an idle exam still ends
## at its deadline. Empty when there is nothing to report.
## Pay the nodes for the time since the last settle (see Economy.settle), from
## every track the learner has played. Returns the Cycles paid.
func _settle() -> float:
	if profile == null:
		return 0.0
	return Economy.settle(profile, now(), rules)


func tick() -> Array:
	if _settle() > 0.0 and now() - _last_save >= rules.eco_save_every:
		_last_save = now()
		store.save(profile)
	if mode == Mode.EXAM and exam != null and exam.expired(now()):
		return _exam_submit(true)
	return []


# --- terminal labs -------------------------------------------------------

## The session of the encounter in progress, or of free play.
func _term() -> TerminalSession:
	if current_round != null and current_round.terminal != null:
		return current_round.terminal
	return _free


func _terminal_banner() -> Array:
	var t := _term()
	var who := "you are %s@%s" % [t.lab.you["user"], t.lab.you["name"]]
	if not t.is_mission():
		return [_l("TERMINAL LAB  //  free play", S_ACCENT),
				_l("%s   (%s)" % [t.lab.title, who]),
				_l("help lists the tools. exit returns to the prompt. Free play awards no XP.", S_DIM)]
	var r := current_round
	var where: String = pack.concepts[r.current()["concept"]]["objective"]
	var head := "TERMINAL LAB %d/%d  //  %s" % [r.index + 1, r.queue.size(), where]
	return [_l(head, S_ACCENT),
			_l(t.mission["stem"]),
			_l("%s   (%s)" % [t.lab.title, who], S_DIM),
			_l("help lists the tools. answer <text> submits (%d tries). leave ends the %s." % [
					t.max_tries, "round"], S_DIM),
			_l("")]


## `lab` alone lists the labs; `lab <id>` opens one for free play.
func _start_lab(id: String) -> Array:
	if pack.labs.is_empty():
		return [_l("This pack has no labs.", S_ERROR)]
	if id == "":
		var out: Array = []
		for lab_id in pack.labs:
			out.append(_l("  %-14s %s" % [lab_id, pack.labs[lab_id].title]))
		out.append(_l("lab <id> opens one.", S_DIM))
		return out
	if not pack.labs.has(id):
		return [_l("No such lab '%s'. Type lab to list them." % id, S_ERROR)]
	_free = TerminalSession.new(pack.labs[id], pack.tool_docs, pack.concept_titles(), {}, rules)
	mode = Mode.TERMINAL
	return [Lines.CLEAR] + _terminal_banner()


func _terminal_command(text: String, verb: String, rest: String) -> Array:
	if verb == "answer":
		return _terminal_answer(rest)
	if verb == "leave":
		return _terminal_exit()
	var res := _term().run(text, now())
	var out: Array = []
	for line in res["out"]:
		out.append(_l(line))
	return out


## In a mission this ends the round like `leave` anywhere else; in free play it
## returns to the prompt.
func _terminal_exit() -> Array:
	if current_round != null:
		return _finish()
	_free = null
	mode = Mode.HOME
	return [Lines.CLEAR, _l("Left the lab. Type help for commands.", S_DIM)]


func _terminal_answer(text: String) -> Array:
	var t := _term()
	if not t.is_mission():
		return [_l("There is no question in free play. exit leaves the lab.", S_ERROR)]
	if text == "":
		return [_l("Usage: answer <text>", S_ERROR)]
	var r := t.answer(text)
	if r["done"]:
		return _commit(current_round.submit_terminal())
	return [_l("Not quite. You have %d %s left. Keep exploring, then answer again." % [
			r["tries_left"], "try" if r["tries_left"] == 1 else "tries"], S_ACCENT)]


## The answer, the lesson, and the commands that were typed, so the efficient
## route is visible.
func _terminal_debrief(res: Dictionary) -> Array:
	var t: Dictionary = res["terminal"]
	var accept: Array = t["accept"]
	var out: Array = []
	if t["solved_on"] > 0:
		out.append(_l("Your answer: %s   (right on try %d)" % [t["given"][t["solved_on"] - 1], t["solved_on"]]))
	else:
		out.append(_l("Your answer: %s   (not accepted)" % ", ".join(t["given"])))
	var also := accept.slice(1)
	out.append(_l("The answer: %s%s" % [accept[0], ("   (also accepted: %s)" % ", ".join(also)) if not also.is_empty() else ""]))
	out.append(_l(""))
	var explain := Pack.explain_of(res["item"])
	if explain != "":
		out.append(_l(explain))
	out.append_array(_reference_lines(res["item"]))
	var cmds: Array = t["commands"]
	if cmds.is_empty():
		out.append(_l("You ran no commands.", S_DIM))
	else:
		out.append(_l(""))
		out.append(_l("You ran %d command%s:" % [cmds.size(), "" if cmds.size() == 1 else "s"], S_DIM))
		for i in mini(cmds.size(), 12):
			out.append(_l("  %s %s" % [char(36), cmds[i]], S_DIM))
		if cmds.size() > 12:
			out.append(_l("  ... and %d more" % (cmds.size() - 12), S_DIM))
	return out + _feedback_tail(res)


# --- shared ------------------------------------------------------------

## What the screen should show right now, after a `clear`.
func _redraw() -> Array:
	match mode:
		Mode.LOGIN:
			return [Lines.CLEAR] + banner()
		Mode.MAP:
			return [Lines.CLEAR] + _map_screen()
		Mode.MENU:
			return _menu_screen()
		Mode.ASK:
			return [Lines.CLEAR] + _encounter_lines()
		Mode.TERMINAL:
			return [Lines.CLEAR] + _terminal_banner()
		Mode.EXAM:
			return [Lines.CLEAR] + _exam_screen()
		Mode.FEEDBACK:
			return [Lines.CLEAR] + _feedback
	return [Lines.CLEAR]


## The item's optional references as dim lines, with a blank line before them; [] when it has none.
func _reference_lines(item: Dictionary) -> Array:
	var rows := Pack.reference_lines(item)
	if rows.is_empty():
		return rows
	var out: Array = [_l("")]
	for row in rows:
		out.append(_l(row, S_DIM))
	return out


func _quit() -> Array:
	if profile != null:
		store.save(profile)
	want_quit = true
	return [_l("Goodbye.", S_DIM)]


static func _l(text: String, style: String = S_NORMAL) -> Dictionary:
	return Lines.make(text, style)


static func _when(unix: int) -> String:
	return Time.get_datetime_string_from_unix_time(unix).replace("T", " ") + " UTC"
