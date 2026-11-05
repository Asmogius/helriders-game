extends SceneTree
## Ebbtide plan phase 2 sample (needs a display; not headless):
##   xvfb-run -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 --path . -s res://tools/art/capture_night_sample.gd -- out.png [day|512b11]
## A hex (no hash) grades toward that night average instead of COL_NIGHT_WORLD.
## The fight with a few Shamblers, a Tank, an enemy Bulwark (red lights) and an
## explosion. Night: NightGrade on rigs, zombies and fx (Art's part). The map
## gets the same grade as a plain modulate here ONLY as a preview of Maps'
## part (Maps bakes/grades the chunks). The HUD is never graded.

const NightGrade := preload("res://scripts/night_grade.gd")

var _frames := 0
var _out := "user://night_sample.png"
var _day := false
var _hex := ""
var _m: Node


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	if args.size() > 1 and args[1] == "day":
		_day = true
	elif args.size() > 1:
		_hex = args[1]
	change_scene_to_file.call_deferred("res://scenes/mission.tscn")


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 40:
		_m = current_scene
		_m.set("auto_spawn_specials", false)
		var cam := root.get_camera_2d()
		if cam != null:
			cam.zoom = Vector2(2.2, 2.2)
		var p: Vector2 = _m.vehicle.global_position
		_m.vehicle.set_physics_process(false)
		for i in 7:
			_m.zombies.spawn_at(p + Vector2(130, 0).rotated(i * 0.5 + 2.2) * (1.0 if i % 2 == 0 else 0.8), "shambler")
		_m.zombies.spawn_at(p + Vector2(-190, 90), "tank")
		var b: Node2D = _m.spawn_bulwark(p + Vector2(190, 40))
		if b != null:
			b.set_physics_process(false)
	if _frames == 60:
		var g := Color.WHITE if _day else (_grade())
		_m.fx.set_night(g)
		NightGrade.apply_rig(_m.vehicle, g)
		for r in _m.rigs.get_children():
			NightGrade.apply_rig(r, g)
		for z in _m.zombies.get_children():
			if z is CanvasItem:
				NightGrade.apply_zombie(z, g)
		_m.arena.modulate = g   # preview only: Maps owns the map grade
		_m.fx.explosion(_m.vehicle.global_position + Vector2(60, -70), Vector2.ZERO)
	if _frames == 66:
		root.get_texture().get_image().save_png(_out)
		print("saved ", _out)
		quit()
	return false


func _grade() -> Color:
	if _hex == "":
		return NightGrade.world_grade()
	return NightGrade.grade_for(Color.html(_hex))
