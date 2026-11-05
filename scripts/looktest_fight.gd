extends Node
## Staged fight for the HD-2D look test. No gameplay changes: it boots a normal
## mission, poses a Bulwark and a few zombies, then freezes them so day/night
## before/after shots are the same frame.
##
##   godot --path . res://scenes/looktest_fight.tscn
## Captures: tools/art/capture_looktest.gd

const MissionScene := preload("res://scenes/mission.tscn")
const Missions := preload("res://scripts/missions.gd")
const Arena := preload("res://scripts/arena.gd")
const LookStack := preload("res://scripts/look_stack.gd")

# Open ground just east of the Crossroads west block, so a 45° wall sits in frame.
const PLAYER_AT := Vector2(640, 1260)
const PLAYER_ROT := 0.62
const ENEMY_AT := Vector2(980, 1460)
const ENEMY_ROT := 2.55
const FIRE_AT := Vector2(520, 1410)
const CAM_AT := Vector2(740, 1360)
const CAM_ZOOM := 1.32
const ZOMBIES: Array[Vector2] = [
	Vector2(760, 1400), Vector2(860, 1500), Vector2(700, 1520), Vector2(920, 1340),
]

var mission: Node2D
var stack: Node
var posed := false
var _phase := "boot"
var _frames := 0
var _enemy: Node2D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var profile := get_node("/root/Profile")
	profile.persist = false
	profile.new_game()
	Arena.set_outer_blocks_style(true)
	var spec: Dictionary = Missions.make("clear", 2, 7)
	spec["layout"] = "crossroads"
	var node := MissionScene.instantiate()
	node.set("mission_override", spec)
	node.set("auto_spawn_specials", false)
	mission = node
	get_tree().root.add_child(node)
	get_tree().current_scene = node


func _process(_delta: float) -> void:
	if mission == null or posed:
		return
	_frames += 1
	if _phase == "boot":
		var arena: Node = mission.get("arena")
		if arena == null:
			return
		if arena.has_method("is_baking") and arena.is_baking():
			arena.finish_bake()
		_pose()
		_phase = "art"
		_frames = 0
		return
	if _phase == "art":
		if _frames < 3:
			return
		_freeze_actors()
		var fx: Node = mission.get("fx")
		if fx != null and fx.has_method("explosion"):
			fx.call("explosion", FIRE_AT, Vector2.ZERO)
			for i in 6:
				fx.call("flame", FIRE_AT + Vector2(randf_range(-18.0, 18.0), randf_range(-10.0, 8.0)))
		_phase = "bloom"
		_frames = 0
		return
	if _phase == "bloom":
		if _frames < 16:
			return
		var fx: Node = mission.get("fx")
		if fx != null:
			fx.set_process(false)
		_attach_stack()
		posed = true
		print("LOOKTEST POSED lights-ready")


func _pose() -> void:
	var vehicle: Node2D = mission.get("vehicle")
	vehicle.global_position = PLAYER_AT
	vehicle.rotation = PLAYER_ROT
	vehicle.set("velocity", Vector2.ZERO)
	vehicle.set_physics_process(false)
	_enemy = mission.call("spawn_bulwark", ENEMY_AT)
	if _enemy != null:
		_enemy.global_position = ENEMY_AT
		_enemy.rotation = ENEMY_ROT
		_enemy.set("velocity", Vector2.ZERO)
		_enemy.set_physics_process(false)
	var director: Node = mission.get("zombies")
	if director != null:
		director.set_physics_process(false)
		for z in director.call("active_zombies"):
			(z as Node).set_physics_process(false)
		var i := 0
		for at: Vector2 in ZOMBIES:
			var kind := "brute" if i == 2 else "shambler"
			var z := director.call("spawn_at", at, kind) as Node2D
			if z != null:
				z.rotation = (PLAYER_AT - at).angle()
				z.set_physics_process(false)
				z.queue_redraw()
			i += 1
	var cam: Camera2D = mission.get("camera")
	if cam != null:
		cam.set_physics_process(false)
		cam.position_smoothing_enabled = false
		cam.offset = Vector2.ZERO
		cam.zoom = Vector2(CAM_ZOOM, CAM_ZOOM)
		cam.global_position = CAM_AT
	var hud: Node = mission.get("hud")
	if hud != null:
		hud.visible = false
	# Keep the mission from spawning or driving, but leave child _process
	# (vehicle art, fx) running until the freeze below.
	mission.set_physics_process(false)
	mission.set_process(false)


func _freeze_actors() -> void:
	var vehicle: Node2D = mission.get("vehicle")
	if vehicle != null:
		vehicle.set_process(false)
	if _enemy != null:
		_enemy.set_process(false)
	var director: Node = mission.get("zombies")
	if director != null:
		director.set_process(false)
		for z in director.call("active_zombies"):
			(z as Node).set_process(false)


func _attach_stack() -> void:
	var stack_node := LookStack.new()
	stack_node.name = "LookStack"
	stack = stack_node
	# Flags before it enters the tree. The grade stays hidden until a shot asks for it.
	stack_node.enabled = false
	stack_node.fire_at = FIRE_AT
	stack_node.muzzle_at = _muzzle_at()
	mission.add_child(stack_node)
	stack_node.attach(mission)
	stack_node.set_enabled(false)


func _muzzle_at() -> Vector2:
	if _enemy == null:
		return ENEMY_AT
	var sc := absf(_enemy.global_scale.x)
	var hull: Object = _enemy.get("_hull_art")
	if hull != null and hull.has_method("point_offset"):
		var meta: Dictionary = hull.get("meta")
		var points: Dictionary = meta.get("points", {})
		if points.has("nose_mount"):
			return _enemy.global_position + hull.call("point_offset", "nose_mount") * sc + Vector2.RIGHT.rotated(_enemy.global_rotation) * 10.0
	return _enemy.global_position + Vector2.RIGHT.rotated(_enemy.global_rotation) * 36.0
