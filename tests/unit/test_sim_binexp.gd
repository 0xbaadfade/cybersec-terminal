extends GutTest
## The binary-analysis tools (file, nm, strings, readelf, objdump, checksec)
## and SimLab's optional `binaries` field (README "Binary triage tools").

const Support := preload("res://tests/unit/support.gd")

var _shell := SimShell.new()


func _lab_data(mutate: Callable = Callable()) -> Dictionary:
	var data := Support.demo_lab()
	data["binaries"] = {
		"analyst-ws": {
			"sample": {
				"file_output": "ELF 64-bit LSB executable, x86-64, version 1 (SYSV), dynamically linked, interpreter /lib64/ld-linux-x86-64.so.2, not stripped",
				"canary": false, "nx": false, "pie": false, "relro": "none",
				"nm": ["0000000000401156 T vulnerable_copy", "000000000040119b T main"],
				"strings": ["You said: %s", "vulnerable_copy", "libc.so.6"],
				"readelf_h": ["  Type:  EXEC (Executable file)", "  Entry point address: 0x401070"],
				"readelf_l": ["  GNU_STACK  ...  RWE  0x10"],
				"readelf_d": ["  (RUNPATH)  not set"],
				"functions": {"vulnerable_copy": ["  401156:  push   rbp", "  40119a:  ret"]},
			},
		},
	}
	if mutate.is_valid():
		mutate.call(data)
	return data


func _lab(mutate: Callable = Callable()) -> SimLab:
	return SimLab.from_data(_lab_data(mutate), "labs/test.json")


func _ctx(lab: SimLab) -> SimContext:
	var ctx := SimContext.new()
	ctx.lab = lab
	ctx.rng = RandomNumberGenerator.new()
	ctx.tool_names = _shell.tool_names()
	return ctx


func _run(lab: SimLab, line: String) -> Array:
	return _shell.execute(line, _ctx(lab))["out"]


# --- SimLab loading ----------------------------------------------------------

func test_a_lab_with_binaries_loads_and_a_lab_with_none_is_unaffected() -> void:
	var lab := _lab()
	assert_true(lab.ok(), "\n".join(lab.errors))
	assert_eq(lab.binaries_for_you().keys(), ["sample"])
	var plain := SimLab.from_data(Support.demo_lab(), "labs/plain.json")
	assert_true(plain.ok(), "\n".join(plain.errors))
	assert_eq(plain.binaries_for_you(), {})


func test_a_binary_missing_a_required_field_is_rejected() -> void:
	var lab := _lab(func(d): d["binaries"]["analyst-ws"]["sample"].erase("relro"))
	assert_false(lab.ok())
	assert_string_contains("\n".join(lab.errors), "'relro' must be one of")


func test_binaries_for_an_unknown_host_is_an_error() -> void:
	var lab := _lab(func(d): d["binaries"] = {"ghost-host": {"x": {}}})
	assert_false(lab.ok())
	assert_string_contains("\n".join(lab.errors), "binaries for unknown host 'ghost-host'")


# --- the tools -----------------------------------------------------------------

func test_file_reports_the_stored_output() -> void:
	var lab := _lab()
	assert_eq(_run(lab, "file sample"), ["sample: ELF 64-bit LSB executable, x86-64, version 1 (SYSV), dynamically linked, interpreter /lib64/ld-linux-x86-64.so.2, not stripped"])
	assert_string_contains("\n".join(_run(lab, "file nope")), "No such file or directory")


func test_nm_lists_the_stored_symbol_table() -> void:
	var lab := _lab()
	assert_eq(_run(lab, "nm sample"), ["0000000000401156 T vulnerable_copy", "000000000040119b T main"])


func test_strings_filters_by_minimum_length() -> void:
	var lab := _lab()
	assert_eq(_run(lab, "strings sample"), ["You said: %s", "vulnerable_copy", "libc.so.6"])
	assert_eq(_run(lab, "strings -n 12 sample"), ["You said: %s", "vulnerable_copy"])


func test_readelf_needs_exactly_one_known_flag() -> void:
	var lab := _lab()
	assert_eq(_run(lab, "readelf -h sample"), ["  Type:  EXEC (Executable file)", "  Entry point address: 0x401070"])
	assert_eq(_run(lab, "readelf -l sample"), ["  GNU_STACK  ...  RWE  0x10"])
	assert_string_contains("\n".join(_run(lab, "readelf sample")), "Usage: readelf")
	assert_string_contains("\n".join(_run(lab, "readelf -h -l sample")), "Usage: readelf")


func test_objdump_requires_disassemble_and_intel_syntax() -> void:
	var lab := _lab()
	assert_eq(_run(lab, "objdump -d -M intel --disassemble=vulnerable_copy sample"),
			["  401156:  push   rbp", "  40119a:  ret"])
	assert_string_contains("\n".join(_run(lab, "objdump -d sample")), "this simulator only supports")
	assert_string_contains("\n".join(_run(lab, "objdump -d --disassemble=vulnerable_copy sample")), "not supported")


func test_checksec_composes_a_report_from_the_protection_fields() -> void:
	var lab := _lab()
	var out := _run(lab, "checksec sample")
	assert_string_contains("\n".join(out), "No RELRO")
	assert_string_contains("\n".join(out), "No canary found")
	assert_string_contains("\n".join(out), "NX disabled")
	assert_string_contains("\n".join(out), "No PIE")


func test_tools_the_lab_knows_nothing_about_still_run_cleanly() -> void:
	# A lab with no binaries (every existing lab) must not break on these new tools.
	var lab := SimLab.from_data(Support.demo_lab(), "labs/plain.json")
	assert_string_contains("\n".join(_run(lab, "file notes.txt")), "No such file or directory")
	assert_string_contains("\n".join(_run(lab, "checksec x")), "No such file")
