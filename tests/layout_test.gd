extends SceneTree
## Shared layout grid (ui_theme.gd): safe_rect stays inside the viewport,
## snap rounds to GRID, bottom_bar has the agreed sizes.
##
## Run:  godot --headless --fixed-fps 60 --path . -s res://tests/layout_test.gd

const UI := preload("res://scripts/ui_theme.gd")

var failures: Array[String] = []
var screen: Control
var bar: HBoxContainer
var frame := 0


func _initialize() -> void:
	var profile: Node = root.get_node("Profile")
	profile.persist = false   # never touch a real save
	profile.new_game()
	screen = Control.new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(screen)
	bar = UI.bottom_bar(screen)
	for t: String in ["BACK", "DEPLOY"]:
		var b := Button.new()
		b.text = t
		bar.add_child(b)


func _process(_delta: float) -> bool:
	frame += 1
	if frame < 3:
		return false
	var vp: Rect2 = screen.get_viewport().get_visible_rect()
	var r := UI.safe_rect(screen)
	_check(vp.encloses(r), "safe_rect %s inside viewport %s" % [r, vp])
	_check(r.position.x >= vp.position.x + UI.MARGIN and r.end.y <= vp.end.y - UI.MARGIN, "safe_rect keeps MARGIN")
	_check(is_equal_approx(UI.snap(13.0), 16.0) and is_equal_approx(UI.snap(11.9), 8.0), "snap rounds to GRID")
	for v: float in [UI.MARGIN, UI.BAR_H, UI.MIN_TOUCH]:
		_check(is_equal_approx(fmod(v, UI.GRID), 0.0), "%s is a multiple of GRID" % v)
	var br := bar.get_global_rect()
	_check(is_equal_approx(br.size.y, UI.BAR_H), "bottom_bar is BAR_H tall (%s)" % br.size.y)
	_check(is_equal_approx(br.end.y, r.end.y) and r.encloses(br), "bottom_bar sits at the bottom of safe_rect")
	_check(bar.get_theme_constant("separation") == int(UI.GAP), "bottom_bar uses GAP")
	var second := UI.bottom_bar(screen)
	_check(second.theme == bar.theme and bar.theme == UI.shared_theme(), "bottom_bar reuses one cached theme")
	for c: Node in bar.get_children():
		_check((c as Button).size.y >= UI.MIN_TOUCH, "button at least MIN_TOUCH tall")
	if failures.is_empty():
		print("LAYOUT TEST PASSED")
		quit(0)
	else:
		print("LAYOUT TEST FAILED: %s" % ", ".join(failures))
		quit(1)
	return true


func _check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + what)
	if not ok:
		failures.append(what)
