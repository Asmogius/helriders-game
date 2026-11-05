extends SceneTree
## Quickplay QP6: spawner_runtime triggers + 24-cap.
##
## Run: godot --headless --fixed-fps 60 --path . -s res://tests/quickplay_spawner_test.gd

const Mission := preload("res://scripts/mission.gd")
const Missions := preload("res://scripts/missions.gd")
const SpawnerRuntime := preload("res://scripts/quickplay/spawner_runtime.gd")
const LevelData := preload("res://scripts/quickplay/level_data.gd")
const ProfileScript := preload("res://scripts/profile.gd")

const SPOT := Vector2(1600, 1200)

var main: Mission
var spawners: SpawnerRuntime
var frame := 0
var step := 0
var failures: Array[String] = []
var cleared: Array[String] = []
var spawned := 0


func _initialize() -> void:
	seed(42)
	var profile: ProfileScript = root.get_node("Profile")
	profile.persist = false
	profile.new_game()
	main = (load("res://scenes/mission.tscn") as PackedScene).instantiate() as Mission
	main.mission_override = Missions.make("clear", 1, 11)
	main.auto_spawn_specials = false
	root.add_child(main)


func _process(_delta: float) -> bool:
	if main == null:
		return false
	frame += 1
	match step:
		0:
			if frame == 5:
				main.zombies.spawn_budget = 0
				main.zombies.clear_all()
				main.vehicle.armor_max = 100000.0
				main.vehicle.armor = main.vehicle.armor_max
				main.vehicle.global_position = SPOT
				_check_cap()
				_setup_chain()
				_next()
		1:  # level_start fires immediately
			if frame == 2:
				spawners._tick(0.0)
				_check(spawned >= 1, "level_start spawner emits on first tick")
				_check(main.zombies.active_count() >= 1, "zombie director received spawn_at")
				_next()
		2:  # finish z1 (count 2) → arms z2 via spawner_cleared
			if frame == 1:
				# Drain remaining for z1
				for i in 8:
					spawners._tick(10.0)
			if frame == 3:
				_check(cleared.has("z1"), "z1 clears after count")
				_check(spawned >= 3, "z2 (spawner_cleared) armed and emitted after z1")
				_next()
		3:  # player_radius
			if frame == 1:
				main.vehicle.global_position = SPOT + Vector2(2000, 0)  # far from radius spawner
				spawners.setup_from_placeables([{
					"id": "spawner_zombie", "key": "near", "pos": [SPOT.x + 80.0, SPOT.y],
					"rot": 0.0, "snap": true,
					"data": {"enemy": "shambler", "count": 1, "rate": 1.0, "trigger": "player_radius", "radius": 120.0, "source_spawner": ""},
				}])
				spawners.player = main.vehicle
				spawners.zombies = main.zombies
				spawners.mission = main
				spawned = 0
				cleared.clear()
				spawners.start()
				spawners._tick(0.0)
				_check(spawned == 0, "player_radius silent while far")
				main.vehicle.global_position = SPOT + Vector2(80, 0)
				spawners._tick(0.0)
				_check(spawned == 1, "player_radius fires when inside")
				_finish()
	return false


func _check_cap() -> void:
	var many: Array = []
	for i in 30:
		many.append({
			"id": "spawner_zombie", "key": "s%d" % i, "pos": [100.0 + i, 100.0],
			"rot": 0.0, "snap": true,
			"data": {"enemy": "shambler", "count": 1, "rate": 2.5, "trigger": "level_start", "radius": 100.0, "source_spawner": ""},
		})
	var s := SpawnerRuntime.new()
	s.setup_from_placeables(many)
	_check(s.spawner_count() == LevelData.MAX_SPAWNERS, "setup caps at 24 spawners (%d)" % s.spawner_count())
	s.free()


func _setup_chain() -> void:
	spawners = SpawnerRuntime.new()
	main.add_child(spawners)
	spawners.zombies = main.zombies
	spawners.mission = main
	spawners.player = main.vehicle
	spawners.unit_spawned.connect(func(_k, _a, _f): spawned += 1)
	spawners.spawner_cleared.connect(func(k): cleared.append(k))
	spawners.setup_from_placeables([
		{
			"id": "spawner_zombie", "key": "z1", "pos": [SPOT.x + 200.0, SPOT.y],
			"rot": 0.0, "snap": true,
			"data": {"enemy": "shambler", "count": 2, "rate": 0.5, "trigger": "level_start", "radius": 100.0, "source_spawner": ""},
		},
		{
			"id": "spawner_zombie", "key": "z2", "pos": [SPOT.x + 260.0, SPOT.y],
			"rot": 0.0, "snap": true,
			"data": {"enemy": "brute", "count": 1, "rate": 0.5, "trigger": "spawner_cleared", "radius": 100.0, "source_spawner": "z1"},
		},
	])
	spawners.start()


func _next() -> void:
	step += 1
	frame = 0


func _finish() -> void:
	if spawners != null:
		spawners.zombies = null
		spawners.mission = null
		spawners.player = null
		spawners.free()
		spawners = null
	if main != null:
		main.free()
		main = null
	if failures.is_empty():
		print("QUICKPLAY SPAWNER TEST PASSED")
		quit(0)
	else:
		print("QUICKPLAY SPAWNER TEST FAILED: %s" % ", ".join(failures))
		quit(1)


func _check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + what)
	if not ok:
		failures.append(what)
