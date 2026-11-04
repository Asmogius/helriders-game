extends SceneTree
## Headless test for the Patcher (§14) and its shield parts: the Capacitor
## Bank and Flux Coil numbers, the Patcher's odds and Comms text, hooking an
## ally after its wind-up and repairing it, the cable dragging it along, the
## hook popping on a big hit and on you ramming the cable, reviving a wreck
## (and starting over when hit), a revived rig paying its loot once, its own
## salvage, and waiting for an ally before it rolls in.
##
## Run:  godot --headless --fixed-fps 60 --path . -s res://tests/patcher_test.gd

const Mission := preload("res://scripts/mission.gd")
const Missions := preload("res://scripts/missions.gd")
const PatcherRig := preload("res://scripts/patcher_rig.gd")
const GunnerRig := preload("res://scripts/gunner_rig.gd")
const Parts := preload("res://scripts/parts.gd")
const Loadout := preload("res://scripts/loadout.gd")
const T := preload("res://scripts/tuning.gd")

const SPOT := Vector2(1600, 1200)   # open ground at the player start

var main: Mission
var frame := 0
var step := 0
var failures: Array[String] = []
var p: PatcherRig
var g: GunnerRig
var mark := {}


func _initialize() -> void:
	seed(20261104)
	var profile: Node = root.get_node("Profile")
	profile.set("persist", false)
	profile.call("new_game")
	_check_parts()
	_check_tables()
	_start(Missions.make("clear", 3, 7))


func _start(spec: Dictionary) -> void:
	if main != null:
		main.queue_free()
	main = (load("res://scenes/mission.tscn") as PackedScene).instantiate() as Mission
	main.mission_override = spec
	main.auto_spawn_specials = false
	main.always_drop_schematic = true
	root.add_child(main)
	frame = 0


func _process(_delta: float) -> bool:
	frame += 1
	var rig := main.vehicle
	match step:
		0:  # Hooks a Gunner Rig after its wind-up, and repairs it
			if frame == 3:
				main.zombies.spawn_budget = 0
				main.zombies.clear_all()
				for b in main.barrels:
					b.deactivate()
				rig.armor_max = 100000.0
				rig.armor = rig.armor_max
				_park(SPOT)
				g = main.spawn_gunner(SPOT + Vector2(700, 0)) as GunnerRig
				p = main.spawn_patcher(SPOT + Vector2(700, 300)) as PatcherRig
				_check(p != null and p == main.patcher, "spawn_patcher sends in a Patcher")
			if frame == 3 + 60:
				_check(not p.is_hooked() and p.wind_left < T.PATCHER_REHOOK, "it winds the hook up first (%.1f s left)" % p.wind_left)
			if frame == 3 + 240:
				_check(p.is_hooked() and p.hooked_to == g, "after the wind-up its cable is on the Gunner Rig")
				g.facing_armor[3] = 0.0
				mark.rear = g.facing_armor[3]
				mark.max_d = 0.0
			if frame > 3 + 240 and frame < 3 + 360:
				mark.max_d = maxf(float(mark.max_d), p.global_position.distance_to(g.global_position))
			if frame == 3 + 360:
				var got := g.facing_armor[3] - float(mark.rear)
				_check(absf(got - T.PATCHER_REPAIR * 2.0) < 3.0, "it repairs the most damaged facing at 12/s (+%.1f in 2 s)" % got)
				_check(float(mark.max_d) < T.PATCHER_CABLE + 25.0, "the cable holds it within 400 px (%.0f px at most)" % float(mark.max_d))
				_next()
		1:  # The ally drags it
			if frame == 1:
				g.player = null   # the Gunner stops driving itself...
				mark.p0 = p.global_position
				mark.max_d = 0.0
			if frame > 1 and frame <= 61:
				var away := (g.global_position - p.global_position).normalized()
				g.global_position += away * 5.0   # ...and is hauled away at 300 px/s
				mark.max_d = maxf(float(mark.max_d), p.global_position.distance_to(g.global_position))
			if frame == 62:
				var moved := p.global_position.distance_to(mark.p0)
				_check(p.is_hooked() and float(mark.max_d) < T.PATCHER_CABLE + 15.0 and moved > 150.0,
					"the ally drags it along on the cable (moved %.0f px, cable %.0f px at most)" % [moved, float(mark.max_d)])
				g.player = rig
				_next()
		2:  # Pops on a big hit, winds up again
			if frame == 1:
				g.take_damage(g.armor_max * 0.2)
			if frame == 3:
				_check(not p.is_hooked() and p.pops == 1, "a big hit on the ally pops the hook")
			if frame == 60:
				_check(not p.is_hooked(), "no hook for the wind-up")
			if frame == 360:
				_check(p.is_hooked(), "it hooks back on after the 3 s wind-up")
				_next()
		3:  # You ram the cable
			if frame == 1:
				g.player = null
				p.player = null
				g.velocity = Vector2.ZERO
				p.velocity = Vector2.ZERO
				g.global_position = SPOT + Vector2(150, -350)
				p.global_position = SPOT + Vector2(-150, -350)
				rig.global_position = SPOT + Vector2(0, 200)
			if frame == 3:
				var mid := (p.global_position + g.global_position) * 0.5
				var across := (g.global_position - p.global_position).orthogonal().normalized()
				rig.global_position = mid - across * 8.0
				rig.rotation = across.angle()
				rig.velocity = across * 600.0
				p.player = rig
				mark.pops = p.pops
			if frame == 6:
				_check(p.pops == int(mark.pops) + 1 and not p.is_hooked(), "ramming the cable at speed cuts it")
				g.player = rig
				_park(SPOT)
				_next()
		4:  # No ally alive: it revives the wreck
			if frame == 1:
				mark.kills = main.kills
				mark.scrap = main.scrap
				mark.pickups = main.pickups.get_child_count()
				g.global_position = SPOT + Vector2(900, 400)
				g.velocity = Vector2.ZERO
				g.take_damage(100000.0)
			if frame == 3:
				_check(g.is_wrecked and main.kills == int(mark.kills) + 1 and main.pickups.get_child_count() == int(mark.pickups) + 1, "wrecked, the Gunner Rig counts and drops its crate")
				mark.scrap_paid = main.scrap
			if frame > 3 and p.reviving == g and p.revive_left < T.PATCHER_REVIVE_TIME - 1.5 and not mark.has("hit"):
				mark.hit = true
				p.take_damage(1.0)
				_check(is_equal_approx(p.revive_left, T.PATCHER_REVIVE_TIME), "hitting it while it works starts the revive over")
			if frame > 3 and not g.is_wrecked and not mark.has("back_hp"):
				mark.back_hp = g.hp
				mark.back_front = g.facing_armor[0]
			if frame == 900:
				_check(p.revives == 1 and not g.is_wrecked, "it brings the wreck back")
				_check(absf(float(mark.get("back_hp", 0.0)) - g.hp_max * T.PATCHER_REVIVE_TO) < 1.0 and absf(float(mark.get("back_front", 0.0)) - g.facing_max[0] * T.PATCHER_REVIVE_TO) < 1.0,
					"at 10%% of HP and armor (%.0f/%.0f HP)" % [float(mark.get("back_hp", 0.0)), g.hp_max])
				_check(main.kills == int(mark.kills) and main.pickups.get_child_count() == int(mark.pickups), "its kill is undone and its crate goes back into it")
				mark.scrap_now = main.scrap
				g.take_damage(100000.0)
			if frame == 902:
				_check(main.kills == int(mark.kills) + 1 and is_equal_approx(main.scrap, float(mark.scrap_now)), "wrecked again: it counts, but pays no more scrap")
				_check(main.pickups.get_child_count() == int(mark.pickups) + 1, "the same crate drops again, no second one")
				_next()
		5:  # The Patcher's own salvage
			if frame == 1:
				mark.scrap = main.scrap
				mark.pickups = main.pickups.get_child_count()
				p.take_damage(100000.0)
			if frame == 3:
				var mult := main.profile.salvage_mult() * float(rig.crew_mod("scrap")) * float(rig.crew_mod("rig_scrap"))
				_check(is_equal_approx(main.scrap - float(mark.scrap), T.PATCHER_SCRAP * mult), "the Patcher pays %d scrap" % T.PATCHER_SCRAP)
				var drop: Node = main.pickups.get_child(main.pickups.get_child_count() - 1)
				var part: Dictionary = drop.get("part")
				_check(Parts.DROP_POOLS.patcher.has(str(part.get("id", ""))), "it drops a schematic from its pool (%s)" % str(part.get("name", "")))
				_start(Missions.make("clear", 4, _patcher_seed("clear", 4)))
				main.auto_spawn_specials = true
				_next()
		6:  # A Patcher job: it waits for an ally
			if frame == 3:
				main.zombies.spawn_budget = 0
				main.zombies.clear_all()
				main.vehicle.armor_max = 100000.0
				main.vehicle.armor = 100000.0
				_check(main.use_patcher, "the Comms roll and the mission agree on a Patcher")
			if frame == 60:
				_check(not main.patcher.is_inside_tree(), "no Patcher before another rig is in the fight")
				main.spawn_gunner(SPOT + Vector2(0, -900))
			if frame == 63:
				_check(main.patcher.is_inside_tree(), "it rolls in alongside the rig")
				_finish()
	return false


func _check_parts() -> void:
	var cap := Parts.get_part("capacitor_bank")
	_check(cap.rarity == "Uncommon" and int(cap.cost) == 110 and float(cap.power) == 35.0 and float(cap.weight) == 5.0
		and float(cap.shield) == 75.0 and float(cap.shield_delay) == 4.0 and float(cap.shield_refill) == 6.0,
		"Capacitor Bank: 110 scrap, 35 power, 5 weight, 75 shield, 4 s delay, ~6 s refill")
	var flux := Parts.get_part("flux_coil")
	_check(flux.rarity == "Uncommon" and int(flux.cost) == 110 and float(flux.power) == 30.0 and float(flux.weight) == 5.0
		and float(flux.shield) == 45.0 and float(flux.shield_delay) == 2.5 and float(flux.shield_refill) == 1.0,
		"Flux Coil: 110 scrap, 30 power, 5 weight, 45 shield, 2.5 s delay, ~1 s refill")
	var build: Dictionary = Parts.STARTER_LOADOUT.duplicate(true)
	build.internal = ["junk_emitter", "capacitor_bank"]
	_check(float(Loadout.build(build).shield) == 75.0, "the strongest shield fitted counts")
	_check(Parts.DROP_POOLS.patcher == ["capacitor_bank", "flux_coil", "emergency_patch", "structural_bracing"], "the Patcher's drop pool")


func _check_tables() -> void:
	for type: String in ["clear", "survive", "courier", "hunt"]:
		_check(not Missions.has_patcher(Missions.make(type, 2, 11)), "%s 2 skulls: no Patcher" % type)
	# Odds rise with skulls: count over many seeds.
	var last := 0.0
	for skulls in range(3, 7):
		var n := 0
		for i in 400:
			if Missions.has_patcher(Missions.make("hunt", skulls, i * 7919)):
				n += 1
		var share := n / 400.0
		var want := float(T.PATCHER_CHANCE[skulls - 1])
		_check(absf(share - want) < 0.08 and share > last, "Hunt %d skulls: a Patcher in about %d%% of jobs (%d%%)" % [skulls, roundi(want * 100.0), roundi(share * 100.0)])
		last = share
	var with := Missions.make("clear", 4, _patcher_seed("clear", 4))
	_check(Missions.threats_text(with).contains("1 Patcher"), "Comms names the Patcher")


## A seed whose job brings a Patcher.
func _patcher_seed(type: String, skulls: int) -> int:
	for i in 1000:
		if Missions.has_patcher(Missions.make(type, skulls, 100 + i)):
			return 100 + i
	return 0


func _park(at: Vector2) -> void:
	var rig := main.vehicle
	rig.global_position = at
	rig.velocity = Vector2.ZERO
	rig.rotation = PI / 2.0
	main.hud.left_stick.output = Vector2.ZERO
	main.hud.right_stick.output = Vector2.ZERO


func _next() -> void:
	frame = 0
	step += 1


func _check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + what)
	if not ok:
		failures.append(what)


func _finish() -> void:
	if failures.is_empty():
		print("PATCHER TEST PASSED")
		quit(0)
	else:
		print("PATCHER TEST FAILED: %s" % ", ".join(failures))
		quit(1)
