extends SceneTree
## Every part listed in the missing-part-art pass resolves to voxel art:
## chassis sheets (raider, hauler), the display-only engine block layer (one
## per engine, one shared engine_mount point), slag plating, the scattergun and
## heavy MG turrets, distinct hood / Outrider twin gun sheets, and the four
## utility layers. Display only: stats from Loadout.build are untouched.

const DS := preload("res://scripts/directional_sprite.gd")
const Vehicle := preload("res://scripts/vehicle.gd")
const Loadout := preload("res://scripts/loadout.gd")
const Parts := preload("res://scripts/parts.gd")

const CHASSIS := ["scrap_frame", "bulwark_frame", "courier_frame", "raider_frame", "hauler_frame"]
const ENGINES := ["junk_v6", "turbo_four", "patched_v8", "diesel_block"]
const UTILITY := ["oil_slick", "spike_strip", "goop_launcher", "nitro_bottle"]
var fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		printerr("FAIL: ", msg)


func _init() -> void:
	_run.call_deferred()


func _rig(changes: Dictionary) -> Node2D:
	var lo: Dictionary = Parts.STARTER_LOADOUT.duplicate(true)
	lo.merge(changes, true)
	var v: Node2D = Vehicle.new()
	root.add_child(v)
	v.apply_stats(Loadout.build(lo))
	return v


func _meta(id: String) -> Dictionary:
	var s: Sprite2D = DS.new()
	var ok: bool = s.load_meta("res://art/sprites/%s.json" % id)
	var m: Dictionary = s.meta if ok else {}
	s.free()
	return m


func _run() -> void:
	# Every listed id is a real part on main.
	for id: String in ["raider_frame", "hauler_frame", "slag_plating", "scattergun_turret", "heavy_mg_turret", "hood_guns", "outrider_twin_guns"] + ENGINES + UTILITY:
		check(not Parts.get_part(id).is_empty(), id + ": is a part")
	# Chassis frames: own sheet, hull art, two hardpoint mount points.
	for id: String in ["raider_frame", "hauler_frame"]:
		check(Vehicle.art_path(id) != "", id + ": has a sheet")
		var m := _meta(id)
		check(m.get("directions", 0) == 32 and float(m.get("tilt_deg", 0)) == 30.0, id + ": 32 headings at 30 deg")
		for p in ["mount_a", "mount_b", "turret_mount", "nose_mount", "engine_mount", "ground_centre"]:
			check((m.get("points", {}) as Dictionary).has(p), id + ": point " + p)
		var v := _rig({"chassis": id})
		check(v._hull_art != null and String(v._hull_art.meta_path).ends_with(id + ".json"), id + ": rig wears it")
		v.queue_free()
	# Engines: a layer per engine on every chassis, slot "engine", one shared mount point.
	for c: String in CHASSIS:
		var m := _meta(c)
		check((m.get("points", {}) as Dictionary).has("engine_mount"), c + ": engine_mount")
		var keys := {}
		for e: String in ENGINES:
			var lid := "engine:" + e
			var L: Dictionary = (m.get("layers", {}) as Dictionary).get(lid, {})
			check(L.get("slot", "") == "engine", c + ": " + lid + " is an engine-slot layer")
			keys[str(L.get("sheet", ""))] = true
		check(keys.size() == ENGINES.size(), c + ": engine sheets are distinct")
	for e: String in ENGINES:
		var v := _rig({"engine": e})
		check(v.art_layers().has("engine:" + e), e + ": shown as a layer")
		v.queue_free()
	# Slag plating front armor.
	var s := _rig({"armor_front": "slag_plating"})
	check(s.art_layers().has("armor:slag_plating"), "slag_plating: own armor layer")
	s.queue_free()
	# Turrets.
	for id: String in ["scattergun_turret", "heavy_mg_turret"]:
		var t := _rig({"weapons": [id]})
		check(t._turret != null and t._turret.art != null and String(t._turret.art.meta_path).ends_with(id + ".json"), id + ": turret art")
		var tm := _meta(id)
		check((tm.get("points", {}) as Dictionary).has("pivot") and (tm.get("points", {}) as Dictionary).has("muzzle"), id + ": pivot and muzzle")
		t.queue_free()
	# Fixed guns: own sheets on the nose mount, distinct from each other, no stock layer.
	for id: String in ["hood_guns", "outrider_twin_guns"]:
		var f := _rig({"weapons": [id]})
		check(f._fixed_art.size() == 1 and f._fixed_art[0].get_meta("weapon") == id, id + ": fixed gun art")
		check(not f.art_layers().has("nose_guns"), id + ": replaces the stock nose guns")
		f.queue_free()
	check(_meta("hood_guns").get("frame_w") != _meta("outrider_twin_guns").get("frame_w") or _meta("hood_guns").get("chunks") != _meta("outrider_twin_guns").get("chunks"), "hood and twin guns differ")
	# Utility layers.
	for u: String in UTILITY:
		var v := _rig({"utility": [u]})
		check(v.art_layers().has(u), u + ": utility layer")
		v.queue_free()
	# The engine id rides in the display-only `look` dict.
	var built: Dictionary = Loadout.build(Parts.STARTER_LOADOUT.duplicate(true))
	check(str((built.look as Dictionary).get("engine", "")) == "junk_v6", "look carries the engine id")
	print("MISSING PART ART TEST ", "PASSED" if fails == 0 else "FAILED (%d)" % fails)
	quit(1 if fails else 0)
