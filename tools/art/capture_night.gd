extends SceneTree
## Day and night of the same Outer Blocks job, for the night-tint review.
## Needs a display (not --headless):
##   xvfb-run -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 --path . -s res://tools/art/capture_night.gd -- docs/captures/night
## Writes day_play.png, night_play.png (close, with a tracer and a blast),
## day_map.png, night_map.png (styled bake) and night_fallback.png (code-drawn).
## The night shots force the flag on this one job so the pair differs only by
## the world multiply. FX, tracers and the rig stay unmodulated.

const Missions := preload("res://scripts/missions.gd")
const T := preload("res://scripts/tuning.gd")
const Arena := preload("res://scripts/arena.gd")
const BulletPool := preload("res://scripts/bullet_pool.gd")

var _out := "docs/captures/night"
var _queue: Array[Dictionary] = []
var _mission: Node = null
var _shot: Dictionary = {}
var _phase := 0
var _frames := 0


func _init() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("capture_night: needs a display. Run it under xvfb-run, without --headless.")
		quit(2)
		return
	for a: String in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			_out = a
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	var profile := root.get_node_or_null("Profile")
	if profile != null:
		profile.persist = false
		profile.new_game()
	# Same job both times. Night is forced so the pictures differ only by the grade.
	var day := Missions.make("clear", 3, 4242)
	day["layout"] = "lots"
	day["night"] = false
	var night := day.duplicate(true)
	night["night"] = true
	_queue = [
		{"spec": day, "style": true, "map": false, "fx": true, "file": "day_play.png"},
		{"spec": night, "style": true, "map": false, "fx": true, "file": "night_play.png"},
		{"spec": day, "style": true, "map": true, "fx": false, "file": "day_map.png"},
		{"spec": night, "style": true, "map": true, "fx": false, "file": "night_map.png"},
		{"spec": night, "style": false, "map": true, "fx": true, "file": "night_fallback.png"},
	]
	_next.call_deferred()


func _next() -> void:
	if _mission != null:
		_mission.free()
		_mission = null
	if _queue.is_empty():
		quit()
		return
	_shot = _queue.pop_front()
	Arena.set_outer_blocks_style(bool(_shot.style))
	var mission := (load("res://scenes/mission.tscn") as PackedScene).instantiate()
	mission.set("auto_spawn_specials", false)
	mission.set("mission_override", _shot.spec)
	root.add_child(mission)
	current_scene = mission
	_mission = mission
	_phase = 0
	_frames = 0


func _process(_delta: float) -> bool:
	if _mission == null:
		return false
	_frames += 1
	var arena: Node = _mission.get("arena")
	if _phase == 0:
		if arena.has_method("is_baking") and bool(arena.call("is_baking")):
			if _frames > 30:
				arena.call("finish_bake")
			return false
		if bool(_mission.get("loading_map")):
			return false
		_dress()
		_phase = 1
		_frames = 0
		return false
	if _phase == 1 and _frames >= 10:
		var path := ProjectSettings.globalize_path(_out).path_join(str(_shot.file))
		var tex := root.get_texture()
		var img: Image = tex.get_image() if tex != null else null
		if img == null or img.is_empty():
			printerr("capture_night: no image")
			quit(2)
			return false
		img.save_png(path)
		print("saved ", path)
		_next.call_deferred()
	return false


## Park the camera, hide the HUD, and (on the close shots) pop a tracer,
## a blast and one zombie so the unmodulated lights read against the world.
func _dress() -> void:
	var hud: Node = _mission.get("hud")
	if hud != null:
		hud.set("visible", false)
	var cam := root.get_camera_2d()
	if cam != null:
		cam.set_physics_process(false)
		cam.set_process(false)
		cam.position_smoothing_enabled = false
		cam.limit_left = -100000
		cam.limit_top = -100000
		cam.limit_right = 100000
		cam.limit_bottom = 100000
		cam.offset = Vector2.ZERO
		var vehicle: Node2D = _mission.get("vehicle")
		if bool(_shot.map):
			var view := root.get_visible_rect().size
			var z := minf(view.x / T.WORLD_SIZE.x, view.y / T.WORLD_SIZE.y)
			cam.zoom = Vector2(z, z)
			cam.global_position = T.WORLD_SIZE * 0.5
		elif vehicle != null:
			cam.zoom = Vector2(1.15, 1.15)
			cam.global_position = vehicle.global_position
	if not bool(_shot.fx):
		return
	var rig: Node2D = _mission.get("vehicle")
	if rig == null:
		return
	var at := rig.global_position
	var bullets: Node = _mission.get("bullets")
	if bullets != null and bullets.has_method("fire"):
		bullets.call("fire", at + Vector2(30, -10), Vector2(720, -80), 1.0, BulletPool.TEAM_PLAYER)
		bullets.call("fire", at + Vector2(-20, 16), Vector2(-640, 120), 1.0, BulletPool.TEAM_ENEMY)
	var fx: Node = _mission.get("fx")
	if fx != null:
		if fx.has_method("explosion"):
			fx.call("explosion", at + Vector2(150, -30), Vector2.ZERO)
		if fx.has_method("flame"):
			fx.call("flame", at + Vector2(70, 36))
		if fx.has_method("sparks"):
			fx.call("sparks", at + Vector2(46, 8), Vector2.RIGHT)
	var zombies: Node = _mission.get("zombies")
	if zombies != null and zombies.has_method("spawn_at"):
		zombies.call("spawn_at", at + Vector2(130, 90), "shambler")
