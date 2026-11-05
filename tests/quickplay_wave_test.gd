extends SceneTree
## Quickplay QP6: wave_director math + short Endless run using debug overrides.
## Defensive ENDLESS_* reads (PR #91 not required).
##
## Run: godot --headless --fixed-fps 60 --path . -s res://tests/quickplay_wave_test.gd

const Mission := preload("res://scripts/mission.gd")
const Missions := preload("res://scripts/missions.gd")
const WaveDirector := preload("res://scripts/quickplay/wave_director.gd")
const EndlessTuning := preload("res://scripts/quickplay/endless_tuning.gd")
const ProfileScript := preload("res://scripts/profile.gd")
const T := preload("res://scripts/tuning.gd")

var main: Mission
var waves: WaveDirector
var frame := 0
var step := 0
var failures: Array[String] = []
var started_waves: Array[int] = []


func _initialize() -> void:
	seed(99)
	var profile: ProfileScript = root.get_node("Profile")
	profile.persist = false
	profile.new_game()
	_check_math()
	main = (load("res://scenes/mission.tscn") as PackedScene).instantiate() as Mission
	main.mission_override = Missions.make("survive", 1, 3)
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
				waves = WaveDirector.new()
				main.add_child(waves)
				waves.zombies = main.zombies
				waves.mission = main
				waves.player = main.vehicle
				waves.debug_overrides = {
					"ENDLESS_WAVE_SECONDS": 0.4,
					"ENDLESS_INTERMISSION_SECONDS": 0.2,
					"ENDLESS_ZOMBIES_BASE": 6,
					"ENDLESS_ZOMBIES_PER_WAVE": 2,
					"ENDLESS_ZOMBIES_CAP": 10,
					"ENDLESS_RAMP_START": 1.0,
					"ENDLESS_RAMP_STEP": 0.0,
					"ENDLESS_RAMP_MIN": 1.0,
					"ENDLESS_RIG_FIRST_WAVE": 2,
					"ENDLESS_RIG_EVERY": 1,
					"ENDLESS_RIG_COUNT_STEP": 99,
					"ENDLESS_RIG_MAX": 1,
					"ENDLESS_RIG_POOL_BY_WAVE": [[1, ["scrapper"]]],
					"ENDLESS_SCORE_PER_WAVE": 10,
				}
				waves.wave_started.connect(func(w): started_waves.append(w))
				waves.start()
				_check(waves.wave == 1 and waves.phase == WaveDirector.Phase.WAVE, "start opens wave 1")
				_check(int(main.zombies.cap) == 6, "wave 1 sets zombie cap from ENDLESS_*")
				_next()
		1:
			if frame == 1:
				# Drive the director faster than wall clock.
				for i in 20:
					waves.tick(0.1)
			if frame == 3:
				_check(started_waves.has(2), "intermission advances to wave 2 (%s)" % str(started_waves))
				_check(waves.wave >= 2, "wave index advanced")
				var expect_cap := WaveDirector.zombie_cap_for_wave(waves.wave, waves.debug_overrides)
				_check(int(main.zombies.cap) == expect_cap, "live cap matches wave %d formula (%d)" % [waves.wave, expect_cap])
				# Campaign path: a fresh mission without WaveDirector still works — already running.
				_check(main.zombies != null and main.state == main.State.RUNNING, "campaign-style mission still running")
				_finish()
	return false


func _check_math() -> void:
	_check(WaveDirector.zombie_cap_for_wave(1) == 12, "cap wave 1 = BASE")
	_check(WaveDirector.zombie_cap_for_wave(5) == mini(12 + 2 * 4, 28), "cap scales then clamps")
	var mix1 := WaveDirector.mix_for_wave(1)
	_check(is_equal_approx(float(mix1.get("shambler", -1)), 1.0), "wave 1 mix is all shamblers")
	var mix5 := WaveDirector.mix_for_wave(5)
	_check(float(mix5.get("slimer", 0)) > 0.0 and float(mix5.get("shambler", 0)) > 0.0, "wave 5 has specials + shambler fill")
	_check(WaveDirector.rig_count_for_wave(1) == 0, "no rigs before FIRST_WAVE")
	_check(WaveDirector.rig_count_for_wave(3) == 1, "first rig wave count 1")
	_check(WaveDirector.rig_pool_for_wave(5).has("outrider"), "pool row picks last <= n")
	# Defensive path works whether or not #91 is merged.
	_check(float(EndlessTuning.get_value("ENDLESS_WAVE_SECONDS")) > 0.0, "ENDLESS_WAVE_SECONDS readable")
	print("  INFO  ENDLESS_* from Content PR #91 present=%s" % EndlessTuning.has_content_constants())


func _next() -> void:
	step += 1
	frame = 0


func _finish() -> void:
	if waves != null:
		waves.stop()
		waves.queue_free()
	if main != null:
		main.queue_free()
	main = null
	if failures.is_empty():
		print("QUICKPLAY WAVE TEST PASSED")
		quit(0)
	else:
		print("QUICKPLAY WAVE TEST FAILED: %s" % ", ".join(failures))
		quit(1)


func _check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + what)
	if not ok:
		failures.append(what)
