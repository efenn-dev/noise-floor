extends "res://test/base_test.gd"
## The build line play.bat writes to version.txt shows on the title screen and in the session log
## header. Tests point GameSession.version_path at a file of their own, never the real version.txt.

const VERSION := "user://test_version.txt"
const LOG := "user://test_version_log.txt"


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func test_title_and_log_show_the_build() -> void:
	GameSession.version_path = VERSION
	DirAccess.remove_absolute(VERSION)
	eq(GameSession.version_line(), "dev build", "no version file: a dev build")
	_write(VERSION, "\ufeffabc1234 P1: Playtest fixes (car prompts)\r\n")
	eq(GameSession.version_line(), "abc1234 P1: Playtest fixes (car prompts)", "one clean line, even with a BOM and CRLF")

	var menus := Menus.new()
	tree.root.add_child(menus)
	menus.show_title(false)
	eq(menus.version_text(), "abc1234 P1: Playtest fixes (car prompts)", "the title screen shows the build")
	menus.queue_free()

	var sim := SimWorld.new(10.0)
	var slog := SessionLog.new()
	slog.path_override = LOG
	slog.setup(sim)
	check("Build: abc1234 P1: Playtest fixes (car prompts)" in slog.lines(), "the session log header has the build")
	eq(slog.write(), LOG, "the log is written")
	var f := FileAccess.open(LOG, FileAccess.READ)
	check(f != null and "Build: abc1234 P1" in f.get_as_text(), "and it's in the file")
	if f != null:
		f.close()
	slog.free()

	_write(VERSION, "")
	eq(GameSession.version_line(), "dev build", "an empty file: a dev build")
	DirAccess.remove_absolute(VERSION)
	DirAccess.remove_absolute(LOG)
	GameSession.version_path = GameSession.VERSION_PATH
	await tree.process_frame
