class_name SimContext
extends RefCounted
## What a tool is handed when it runs: the lab, a generator seeded for this
## exact command, and the shell's own state. Tools never see anything else.

var lab: SimLab
var rng: RandomNumberGenerator
var now := 0  # unix seconds, for tools that print a date
var tty := true  # false when the output is being piped (ls prints one per line)
var tool_docs: Dictionary = {}  # tool name -> {summary, usage, flags, concepts, note}
var concept_titles: Dictionary = {}  # concept id -> title
var history: Array = []
var extra_help: Array = []  # mission lines the shell's help appends
var tool_names: Array = []  # what this shell offers
