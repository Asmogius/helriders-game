extends SceneTree
## V4.3 tracer lineup (needs a display):
##   xvfb-run -s "-screen 0 1280x720x24" godot --path . -s res://tools/art/capture_tracers.gd -- out.png
## In the mission scene, one row per weapon style (tracer_styles.gd), streams
## of bullets left to right, labelled; the Harpoon row shows its spear flash.

const TS := preload("res://scripts/tracer_styles.gd")
const BulletPool := preload("res://scripts/bullet_pool.gd")
const Vehicle := preload("res://scripts/vehicle.gd")
const ROWS := ["pintle_turret", "burst_turret", "heavy_mg_turret", "scattergun_turret", "hood_guns", "rivet_gun",
		"flame_sprayer", "arc_projector", "harpoon", "gunner_rig", "convoy_nose", "convoy_turret", "scrapper", "(enemy default)"]

var _frames := 0
var _out := "user://tracers.png"
var _m: Node
var _origin := Vector2.ZERO


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	change_scene_to_file.call_deferred("res://scenes/mission.tscn")


func _row_y(r: int) -> float:
	return -195.0 + r * 30.0


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 40:
		_m = current_scene
		_m.set("auto_spawn_specials", false)
		_m.vehicle.set_physics_process(false)
		_origin = _m.vehicle.global_position + Vector2(-260, 0)
		_m.vehicle.visible = false
		var cam := root.get_camera_2d()
		if cam != null:
			cam.zoom = Vector2(1.8, 1.8)
		var hud: Object = _m.get("hud")
		if hud != null:
			hud.set("visible", false)
		for r in ROWS.size():
			var l := Label.new()
			l.text = ROWS[r]
			l.add_theme_font_size_override("font_size", 11)
			l.position = _origin + Vector2(-130, _row_y(r) - 9)
			_m.add_child(l)
	if _m == null:
		return false
	if _frames >= 60 and _frames % 4 == 0:
		for r in ROWS.size():
			var id: String = ROWS[r]
			if id == "harpoon":
				continue
			var enemy := id in ["gunner_rig", "convoy_nose", "convoy_turret", "scrapper", "(enemy default)"]
			_m.bullets.next_style = TS.index_for(id, enemy)
			_m.bullets.fire(_origin + Vector2(0, _row_y(r)), Vector2(700, 0), 0.0, BulletPool.TEAM_ENEMY if enemy else BulletPool.TEAM_PLAYER)
		_m.bullets.next_style = -1
	if _frames == 94:
		var cl: Node2D = Vehicle.CableLine.new()   # the Harpoon's own drawer, outside the hidden rig
		_m.add_child(cl)
		cl.flash(_origin + Vector2(0, _row_y(8)), _origin + Vector2(330, _row_y(8)))
	if _frames == 98:
		root.get_texture().get_image().save_png(_out)
		print("saved ", _out)
		quit()
	return false
