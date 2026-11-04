extends SceneTree
## V2 style sample: the Workshop bay room and the reusable room fade hook.

const Room := preload("res://scripts/garage_room.gd")
const Workshop := preload("res://scripts/workshop_room.gd")
var fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		printerr("FAIL: ", msg)


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var r: Control = Room.new()
	root.add_child(r)
	var got: Array = []
	r.faded.connect(func(o: bool) -> void: got.append(o))
	r.set_open(true, true)
	check(r.visible and r.is_open() and is_equal_approx(r.modulate.a, 1.0), "snap open")
	r.set_open(false)
	for i in 30:
		await process_frame
	check(not r.visible and got.back() == false, "fade out hides the room and signals")
	r.set_open(true)
	for i in 30:
		await process_frame
	check(r.visible and is_equal_approx(r.modulate.a, 1.0) and got.back() == true, "fade in")
	var w: Control = Workshop.new()
	root.add_child(w)
	w.size = Vector2(1280, 720)
	check(w.room_id == "GARAGE", "workshop is the GARAGE room")
	check(w.mouse_filter == Control.MOUSE_FILTER_IGNORE, "room never eats touches")
	if w.has_art():
		w._layout()
		check(is_equal_approx(w.px(), 720.0 / 212.0), "room shown at the rig preview scale")
		check(w.lift_point() == Vector2(640, 290), "lift under the rig preview")
	print("GARAGE ROOM TEST ", "PASSED" if fails == 0 else "FAILED (%d)" % fails)
	quit(1 if fails else 0)
