extends SceneTree
## Headless checks for the HD-2D look prototype. Does not boot a fight.
##   godot --headless --path . -s res://tests/looktest_test.gd

const Look := preload("res://scripts/look_stack.gd")

var fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		printerr("FAIL: ", msg)


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var grade := load("res://scripts/look_grade.gdshader")
	check(grade is Shader, "grade shader loads")
	var emis := load("res://scripts/look_emissive.gdshader")
	check(emis is Shader, "emissive shader loads")
	var src := FileAccess.get_file_as_string("res://scripts/look_stack.gd")
	check(not src.contains("sprites_hd"), "look stack does not use HD 2px sheets")
	check(not src.contains("Occluder2D"), "no shadow occluders")
	var sheet := FileAccess.get_file_as_string("res://art/sprites/scrap_frame.json")
	check(sheet.contains("\"px_per_voxel\": 1"), "rig sheets stay 1 px/voxel")
	check(sheet.contains("\"tilt_deg\": 45.0"), "fight art is the 45 deg camera")

	var world := Node2D.new()
	var cam := Camera2D.new()
	cam.name = "camera"
	world.add_child(cam)
	var rig := Node2D.new()
	rig.name = "vehicle"
	rig.position = Vector2(100, 100)
	world.add_child(rig)
	root.add_child(world)

	var stack := Look.new()
	stack.low_end = true
	stack.dof_requested = true
	stack.fire_at = Vector2(140, 120)
	stack.muzzle_at = Vector2(180, 80)
	world.add_child(stack)
	stack.attach(world)
	check(stack.night_is_cool(), "night ambient is cool, not brown #512b11")
	stack.set_mode("night")
	var night := stack.ambient_color()
	var brown := Color8(0x51, 0x2b, 0x11)
	var gap := absf(night.r - brown.r) + absf(night.g - brown.g) + absf(night.b - brown.b)
	check(gap > 0.35, "night ambient is far from #512b11 (got %s)" % night)
	check(stack.POOL_SIZE == 8, "flash pool is 8")
	check(stack.light_cap() == 3, "low preset caps lights at 3")
	check(stack.effective_dof() == false, "DoF stays off on the low preset even if requested")
	stack.set_low_end(false)
	stack.set_dof(true)
	check(stack.light_cap() == 4, "high preset caps lights at 4")
	check(stack.effective_dof(), "DoF can turn on when not low-end")
	stack.set_mode("night")
	stack.set_enabled(true)
	stack.set_practicals(true)
	stack._apply()
	check(stack.active_light_count() <= 4, "night high uses at most 4 lights (got %d)" % stack.active_light_count())
	check(stack.active_light_count() >= 3, "night high turns the practicals on (got %d)" % stack.active_light_count())
	stack.set_practicals(false)
	stack._apply()
	check(stack.active_light_count() == 0, "grade-only night has no point lights")
	stack.set_low_end(true)
	stack.set_mode("day")
	stack.set_practicals(true)
	stack._apply()
	check(stack.active_light_count() <= 3, "low day stays within the mobile cap (got %d)" % stack.active_light_count())
	check(stack.effective_dof() == false, "switching to low clears DoF")
	check(world.get_node_or_null("LookHeadStandin") != null, "low-end headlight stand-in exists")

	if fails == 0:
		print("LOOKTEST TEST PASSED")
		quit()
	else:
		printerr("LOOKTEST TEST FAILED (%d)" % fails)
		quit(1)
