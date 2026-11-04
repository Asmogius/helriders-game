extends RefCounted
## One shot for capture_all.gd. Each shot is its own file in tools/art/captures/
## named `<NNN>_<shot>.gd`; capture_all finds them by listing that folder and runs
## them in file-name order (the number), so adding a shot never touches capture_all.gd.
##
## A step overrides `run(cap)` to set the screen up; `cap` is the capture_all
## SceneTree (shared `garage`, `strip`, `profile`, and helpers `show_tab()`,
## `new_strip()`). The PNG is saved `wait()` frames later as `<shot>.png`, then
## `after(cap)` runs: undo anything global the shot changed (input mode...).

const UI := preload("res://scripts/ui_theme.gd")
const T := preload("res://scripts/tuning.gd")

const SETTLE := 12   # default frames to wait before the shot

var shot := ""   # set by capture_all from the file name (without the number)


func run(_cap: SceneTree) -> void:
	pass


func wait() -> int:
	return SETTLE


func after(_cap: SceneTree) -> void:
	pass
