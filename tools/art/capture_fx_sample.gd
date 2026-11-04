extends SceneTree
## V4 style sample capture (needs a display; not headless):
##   xvfb-run -s "-screen 0 1280x720x24" godot --path . -s res://tools/art/capture_fx_sample.gd -- out.png [before]
## In the mission scene: three explosions set off a few frames apart (so one
## shot shows the flash, the fireball + shockwave, and the debris + smoke
## column + scorch stages) and tracers from the player (orange) and an enemy
## direction (enemy red). "before" turns the atlas off: the code-drawn look.

const BulletPool := preload("res://scripts/bullet_pool.gd")

var _frames := 0
var _out := "user://fx_sample.png"
var _before := false
var _m: Node


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	_before = args.size() > 1 and args[1] == "before"
	change_scene_to_file.call_deferred("res://scenes/mission.tscn")


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 40:
		_m = current_scene
		_m.set("auto_spawn_specials", false)
		if _before:
			_m.fx.glow = null
			_m.bullets._tracer_tried = true
			_m.bullets._tracer = null
			_m.bullets.material = null
		var cam := root.get_camera_2d()
		if cam != null:
			cam.zoom = Vector2(2.4, 2.4)
	if _m == null:
		return false
	var v: Node2D = _m.vehicle
	v.set_physics_process(false)
	var p := v.global_position
	if _frames == 60:
		_m.fx.explosion(p + Vector2(-150, -60), Vector2.ZERO)
	if _frames == 84:
		_m.fx.explosion(p + Vector2(150, -55), Vector2(80, 0))
	if _frames == 96:
		_m.fx.explosion(p + Vector2(10, 95), Vector2.ZERO)
	if _frames >= 86 and _frames % 3 == 0:
		_m.bullets.fire(p + Vector2(30, -10), Vector2(900, -120).rotated(randf_range(-0.05, 0.05)), 0.0, BulletPool.TEAM_PLAYER)
		_m.bullets.fire(p + Vector2(260, 120), Vector2(-850, -330).rotated(randf_range(-0.05, 0.05)), 0.0, BulletPool.TEAM_ENEMY)
	if _frames == 101:
		root.get_texture().get_image().save_png(_out)
		print("saved ", _out)
		quit()
	return false
