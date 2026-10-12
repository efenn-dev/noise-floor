extends RefCounted
## Base for headless tests. Test files extend this by path:
##   extends "res://test/base_test.gd"
## and define methods named test_*; test/run_tests.gd finds and runs them.

var passed := 0
var failed := 0
var failures: PackedStringArray = []


func check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		failures.append(label)


func eq(actual: Variant, expected: Variant, label: String) -> void:
	check(actual == expected, "%s (got %s, expected %s)" % [label, actual, expected])


func near(actual: float, expected: float, label: String, tolerance: float = 0.001) -> void:
	check(absf(actual - expected) <= tolerance, "%s (got %s, expected %s)" % [label, actual, expected])
