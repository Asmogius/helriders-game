extends SceneTree
## V6.5 + Ebbtide transitions.
## - Crew-card level-up flash (once per level, reset on new game).
## - Garage → fight deploy: push-in + charcoal fade fires on DEPLOY, lands in
##   the fight scene, and is a no-op when UITransitions is disabled.
##
## Run:  godot --headless --fixed-fps 60 --path . -s res://tests/transitions_test.gd

const Crew := preload("res://scripts/crew.gd")
const CrewCard := preload("res://scripts/crew_card.gd")
const Garage := preload("res://scripts/garage.gd")
const UITransitions := preload("res://scripts/ui_transitions.gd")

var failures: Array[String] = []
var profile: Node
var garage: Garage
var frame := 0
var phase := 0   # 0 flash checks, 1 deploy enabled, 2 deploy disabled


func _check(ok: bool, what: String) -> void:
	if ok:
		print("  PASS  ", what)
	else:
		failures.append(what)
		print("FAIL: ", what)


func _card(m: Dictionary) -> CrewCard:
	var c := CrewCard.new()
	c.member = m
	root.add_child(c)
	return c


func _initialize() -> void:
	profile = root.get_node("Profile")
	profile.persist = false
	profile.new_game()


func _process(_delta: float) -> bool:
	frame += 1
	if phase == 0 and frame == 2:
		_run_flash_checks()
		_setup_deploy_enabled()
		phase = 1
		frame = 0
		return false
	if phase == 1:
		# Transition totals ≈ 0.4 s → ~24 frames at 60 fps; give it 40.
		if frame == 1:
			_check(garage.has_meta(UITransitions.DEPLOY_META), "deploy transition marks the garage busy")
			_check(garage.get_node_or_null("DeployTransition") != null, "deploy transition mounts a fade layer")
		if frame == 40:
			var mission := current_scene
			_check(mission != null and mission.name == "Mission", "deploy transition ends in the fight scene")
			_setup_deploy_disabled()
			phase = 2
			frame = 0
		return false
	if phase == 2:
		if frame == 1:
			_check(garage.get_node_or_null("DeployTransition") == null, "disabled: no DeployTransition layer")
		if frame == 8:
			var mission := current_scene
			_check(mission != null and mission.name == "Mission", "disabled: deploy still reaches the fight scene")
			_finish()
		return false
	return false


func _run_flash_checks() -> void:
	UITransitions.set_enabled(true)
	var m: Dictionary = profile.crew[0]
	m.xp = 0.0
	var first := _card(m)
	_check(not first.flashed, "first card for a member doesn't flash")
	var again := _card(m)
	_check(not again.flashed, "same level shown again doesn't flash")
	m.xp = float(Crew.xp_for_level(Crew.level(m) + 1))
	var up := _card(m)
	_check(Crew.level(m) == 2 and up.flashed, "a card after a level-up flashes")
	var after := _card(m)
	_check(not after.flashed, "the flash plays once per level-up")
	var old_id := int(m.id)
	m.xp = 0.0
	_card(m)
	profile.new_game()
	var fresh: Dictionary = profile.crew[0]
	_check(int(fresh.id) == old_id, "new game reuses the member id (the case the reset covers)")
	fresh.xp = float(Crew.xp_for_level(2))
	_check(not _card(fresh).flashed, "new game: no flash carried over from the last game")
	fresh.xp = float(Crew.xp_for_level(3))
	_check(_card(fresh).flashed, "new game: a real level-up still flashes")
	for c in root.get_children():
		if c is CrewCard:
			c.queue_free()


func _ready_garage() -> void:
	# Fresh profile + garage with a job and a deployable crew/rig.
	if garage != null and is_instance_valid(garage):
		garage.free()
		garage = null
	profile.persist = false
	profile.new_game()
	profile.ensure_board()
	profile.choose_mission(0)
	_check(profile.has_mission() and profile.deploy_block() == "", "setup: mission ready and deploy unblocked")
	garage = (load("res://scenes/garage.tscn") as PackedScene).instantiate() as Garage
	garage.auto_resume = false
	root.add_child(garage)


func _setup_deploy_enabled() -> void:
	UITransitions.set_enabled(true)
	_ready_garage()
	garage.deploy()


func _setup_deploy_disabled() -> void:
	# Back to a garage (mission scene replaced current_scene; garage was freed).
	UITransitions.set_enabled(false)
	_ready_garage()
	garage.deploy()
	# Re-enable for anything that runs after this test process exits.
	# (set false stays until we flip it; flip back at finish so other suites
	# aren't poisoned if they share the Engine meta in-process — they don't.)


func _finish() -> void:
	UITransitions.set_enabled(true)   # leave the switch clear for other suites
	if failures.is_empty():
		print("TRANSITIONS TEST PASSED")
		quit(0)
	else:
		print("TRANSITIONS TEST FAILED: ", failures.size())
		quit(1)
