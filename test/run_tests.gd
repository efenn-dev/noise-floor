extends SceneTree
## Zero-dependency headless test runner.
## Runs every test/test_*.gd. Each file extends "res://test/base_test.gd" and defines test_* methods.
## Use tools/test.sh (it refreshes the class cache first and fails on script errors).
## A test may `await` (e.g. `await tree.physics_frame`) to run real physics; `tree` is set on every suite.
## Output stays compact on purpose: one line per file, plus one line per failure.

const TEST_DIR := "res://test/"


func _initialize() -> void:
	var total_passed := 0
	var total_failed := 0
	var files := Array(DirAccess.get_files_at(TEST_DIR))
	files.sort()
	for file: String in files:
		if not (file.begins_with("test_") and file.ends_with(".gd")):
			continue
		var script: GDScript = load(TEST_DIR + file)
		if script == null or not script.can_instantiate():
			print("FAIL  %s did not load (parse error?)" % file)
			total_failed += 1
			continue
		var suite = script.new()
		suite.tree = self
		var seen := {}
		var file_failed := 0
		for method: Dictionary in script.get_script_method_list():
			var method_name: String = method["name"]
			if not method_name.begins_with("test_") or seen.has(method_name):
				continue
			seen[method_name] = true
			var checks_before: int = suite.passed + suite.failed
			var failures_before: int = suite.failures.size()
			await suite.call(method_name)
			if suite.passed + suite.failed == checks_before:
				suite.failed += 1
				suite.failures.append("%s made no checks (crashed early?)" % method_name)
			for i in range(failures_before, suite.failures.size()):
				print("FAIL  %s :: %s :: %s" % [file, method_name, suite.failures[i]])
				file_failed += 1
		print("%s  %s  (%d checks)" % ["ok  " if file_failed == 0 else "FAIL", file, suite.passed + suite.failed])
		total_passed += suite.passed
		total_failed += suite.failed
	print("\n%d passed, %d failed" % [total_passed, total_failed])
	Surfaces.clear_cache()
	SoundView.clear_cache()
	quit(1 if total_failed > 0 else 0)
