extends SceneTree
## Regression repro (run by map_style_test.gd as a child process): turn the map
## style on, add a baking arena and quit on frame 2 while the bake still runs.
## Must exit 0; it used to abort (exit 134) because nothing waited on the bake.

const Arena := preload("res://scripts/arena.gd")
const Layouts := preload("res://scripts/layouts.gd")

var _frame := 0


func _initialize() -> void:
	_start.call_deferred()   # root joins the tree after _initialize


func _start() -> void:
	Arena.set_outer_blocks_style(true)
	var a := Arena.new()
	a.setup(Layouts.build("lots", 4))
	root.add_child(a)
	print("baking=", a.is_baking())


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 2:
		quit(0)
	return false
