extends Node
## Quickplay QP6: Endless wave director. Composes ZombieDirector (does not
## subclass it) and reads ENDLESS_* via endless_tuning (Content PR #91 when
## merged; defensive fallbacks otherwise). Campaign missions never add this.

const EndlessTuning := preload("res://scripts/quickplay/endless_tuning.gd")
const SpawnerRuntime := preload("res://scripts/quickplay/spawner_runtime.gd")

signal wave_started(wave: int)
signal wave_cleared(wave: int)
signal intermission_started(wave: int)
signal run_stopped(wave: int, score: int)

enum Phase { IDLE, WAVE, INTERMISSION }

var zombies: Node2D = null       # ZombieDirector
var mission: Node = null
var player: Node2D = null
var spawners: SpawnerRuntime = null   # optional Sandbox placeables; Endless drives director

var wave := 0
var score := 0
var phase: int = Phase.IDLE
var time_left := 0.0
var running := false

## Tests may override ENDLESS_* names without touching tuning.gd.
var debug_overrides := {}

var _rigs_spawned_this_wave := 0


func start() -> void:
	running = true
	wave = 0
	score = 0
	phase = Phase.INTERMISSION
	time_left = 0.0
	_begin_next_wave()


func stop() -> void:
	running = false
	phase = Phase.IDLE
	run_stopped.emit(wave, score)


func _physics_process(delta: float) -> void:
	if running:
		tick(delta)


func tick(delta: float) -> void:
	if not running or phase == Phase.IDLE:
		return
	time_left -= delta
	if phase == Phase.WAVE:
		_refill_budget()
		if time_left <= 0.0:
			_clear_wave()
	elif phase == Phase.INTERMISSION:
		if time_left <= 0.0:
			_begin_next_wave()


func add_kill_score(is_rig := false) -> void:
	if is_rig:
		score += int(_v("ENDLESS_SCORE_PER_RIG", 100))
	else:
		score += int(_v("ENDLESS_SCORE_PER_KILL", 10))


# --- Pure helpers (Maps/UI/tests) ------------------------------------------------

static func zombie_cap_for_wave(n: int, overrides: Dictionary = {}) -> int:
	var base := int(EndlessTuning.get_value("ENDLESS_ZOMBIES_BASE", overrides))
	var per := int(EndlessTuning.get_value("ENDLESS_ZOMBIES_PER_WAVE", overrides))
	var cap := int(EndlessTuning.get_value("ENDLESS_ZOMBIES_CAP", overrides))
	return clampi(base + per * maxi(n - 1, 0), 1, cap)


static func ramp_for_wave(n: int, overrides: Dictionary = {}) -> float:
	var start := float(EndlessTuning.get_value("ENDLESS_RAMP_START", overrides))
	var step := float(EndlessTuning.get_value("ENDLESS_RAMP_STEP", overrides))
	var mn := float(EndlessTuning.get_value("ENDLESS_RAMP_MIN", overrides))
	return maxf(start - step * float(maxi(n - 1, 0)), mn)


## Last mix row with first_wave <= n; shamblers fill the remaining share.
static func mix_for_wave(n: int, overrides: Dictionary = {}) -> Dictionary:
	var rows: Array = EndlessTuning.get_value("ENDLESS_MIX_BY_WAVE", overrides) as Array
	var chosen: Dictionary = {}
	for row: Variant in rows:
		if not row is Array or (row as Array).size() < 2:
			continue
		var first := int((row as Array)[0])
		if first <= n:
			var raw: Variant = (row as Array)[1]
			if raw is Dictionary:
				chosen = (raw as Dictionary).duplicate()
	var special := 0.0
	for k: Variant in chosen:
		special += float(chosen[k])
	chosen["shambler"] = maxf(1.0 - special, 0.0)
	return chosen


static func rig_count_for_wave(n: int, overrides: Dictionary = {}) -> int:
	var first := int(EndlessTuning.get_value("ENDLESS_RIG_FIRST_WAVE", overrides))
	var every := int(EndlessTuning.get_value("ENDLESS_RIG_EVERY", overrides))
	var step := int(EndlessTuning.get_value("ENDLESS_RIG_COUNT_STEP", overrides))
	var mx := int(EndlessTuning.get_value("ENDLESS_RIG_MAX", overrides))
	if n < first or every <= 0:
		return 0
	if (n - first) % every != 0:
		return 0
	var rig_waves := 1 + int((n - first) / every)
	return clampi(1 + int((rig_waves - 1) / maxi(step, 1)), 1, mx)


static func rig_pool_for_wave(n: int, overrides: Dictionary = {}) -> Array:
	var rows: Array = EndlessTuning.get_value("ENDLESS_RIG_POOL_BY_WAVE", overrides) as Array
	var pool: Array = ["scrapper"]
	for row: Variant in rows:
		if not row is Array or (row as Array).size() < 2:
			continue
		var first := int((row as Array)[0])
		if first <= n and (row as Array)[1] is Array:
			pool = ((row as Array)[1] as Array).duplicate()
	return pool


# --- Internals -------------------------------------------------------------------

func _v(name: String, fallback: Variant) -> Variant:
	var v: Variant = EndlessTuning.get_value(name, debug_overrides)
	return fallback if v == null else v


func _begin_next_wave() -> void:
	wave += 1
	phase = Phase.WAVE
	time_left = float(_v("ENDLESS_WAVE_SECONDS", 60.0))
	_rigs_spawned_this_wave = 0
	_apply_director()
	_spawn_wave_rigs()
	if spawners != null and not spawners._started:
		spawners.player = player
		spawners.zombies = zombies
		spawners.mission = mission
		spawners.start()
	wave_started.emit(wave)


func _clear_wave() -> void:
	score += int(_v("ENDLESS_SCORE_PER_WAVE", 250)) * wave
	wave_cleared.emit(wave)
	phase = Phase.INTERMISSION
	time_left = float(_v("ENDLESS_INTERMISSION_SECONDS", 10.0))
	intermission_started.emit(wave)
	if zombies != null:
		zombies.set("spawn_budget", 0)


func _apply_director() -> void:
	if zombies == null:
		return
	var cap := zombie_cap_for_wave(wave, debug_overrides)
	zombies.set("cap", cap)
	zombies.set("ramp_seconds", ramp_for_wave(wave, debug_overrides))
	zombies.set("start_count", mini(cap, 8))
	zombies.set("spawn_budget", 1000000)
	zombies.set("mix", mix_for_wave(wave, debug_overrides))
	# Prefer spawner positions when Sandbox placeables exist.
	if spawners != null and spawners.spawner_count() > 0:
		var pts: Array[Vector2] = spawners.zombie_spawn_points()
		if not pts.is_empty():
			zombies.set("spawn_points", pts)


func _refill_budget() -> void:
	# Survive-style: director already respawns while budget > 0 and under cap.
	pass


func _spawn_wave_rigs() -> void:
	if mission == null or zombies == null:
		return
	var count := rig_count_for_wave(wave, debug_overrides)
	if count <= 0:
		return
	var pool := rig_pool_for_wave(wave, debug_overrides)
	if pool.is_empty():
		return
	for i in count:
		var kind := str(pool[i % pool.size()])
		var at: Vector2 = zombies.call("pick_spawn_point")
		if _spawn_one_rig(kind, at):
			_rigs_spawned_this_wave += 1


func _spawn_one_rig(kind: String, at: Vector2) -> bool:
	var node: Variant = null
	match kind:
		"outrider":
			node = mission.call("spawn_outrider", at)
		"bulwark":
			node = mission.call("spawn_bulwark", at)
		"gunner":
			node = mission.call("spawn_gunner", at)
		"scrapper":
			node = mission.call("spawn_scrapper", at)
		"torcher":
			node = mission.call("spawn_torcher", at)
		"sludger":
			node = mission.call("spawn_sludger", at)
		"patcher":
			node = mission.call("spawn_patcher", at)
		"convoy":
			node = mission.call("spawn_convoy", at)
		_:
			return false
	return node != null
