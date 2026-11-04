extends SceneTree
## Headless check of the content art (Courier Frame, enemy rigs, weapons):
## lookup by id, mount/pivot/muzzle points, the Hunt elite trim layer, fixed
## gun art on the nose mount, the Shock Pulse emitter layer, sheets for ids that
## aren't in the game yet, and no player/UI accent colours on enemy hulls.

const DS := preload("res://scripts/directional_sprite.gd")
const Vehicle := preload("res://scripts/vehicle.gd")
const EnemyRig := preload("res://scripts/enemy_rig.gd")
const Loadout := preload("res://scripts/loadout.gd")
const Parts := preload("res://scripts/parts.gd")
var fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		printerr("FAIL: ", msg)


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_courier()
	_check_elite()
	_check_weapons_in_game()
	_check_pending_ids()
	_check_enemy_palette()
	_check_enemy_rigs()
	_check_weapon_scale()
	_check_windup()
	print("art_content_test: ", "PASS" if fails == 0 else "%d FAILURES" % fails)
	quit(1 if fails else 0)


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


func _check_courier() -> void:
	var v := _rig({"chassis": "courier_frame"})
	check(v._hull_art != null and String(v._hull_art.meta_path).ends_with("courier_frame.json"), "courier: hull art")
	if v._hull_art == null:
		return
	check(v.art_layers().has("drive:street_wheels") and v.art_layers().has("armor:scrap_plating"), "courier: stock part layers")
	check(v._turret != null and v._turret.art != null, "courier: turret art")
	v.rotation = 0.4
	v._update_art()
	var want: Vector2 = v.global_position + v._hull_art.point_offset("turret_mount")
	var got: Vector2 = v._turret.art.global_position + v._turret.art.point_offset("pivot")
	check(got.distance_to(want) < 0.01, "courier: turret on the cargo-roof mount")
	v.queue_free()


func _check_elite() -> void:
	var plain: Node2D = EnemyRig.new()
	root.add_child(plain)
	check(plain._hull_art != null, "outrider: hull art")
	check(not plain.art_layers().has("elite_trim"), "plain outrider: no trim")
	var e: Node2D = EnemyRig.new()
	root.add_child(e)
	e.make_elite("Test Target", 2.0, 1.5)
	check(e.art_layers().has("elite_trim"), "elite: gold trim layer")
	e.rotation = 11 * TAU / 32.0
	e._update_art()
	check(e._layer_sprites.has("elite_trim") and e._layer_sprites.elite_trim.frame == 11, "elite: trim on the hull frame")
	plain.queue_free()
	e.queue_free()


func _check_weapons_in_game() -> void:
	var m := _rig({"weapons": ["mortar"]})
	check(m._turret != null and m._turret.art != null and String(m._turret.art.meta_path).ends_with("mortar.json"), "mortar: turret art")
	m.queue_free()
	var h := _rig({"weapons": ["harpoon"]})
	check(h._fixed_art.size() == 1 and h._fixed_art[0].get_meta("weapon") == "harpoon", "harpoon: fixed gun art")
	check(not h.art_layers().has("nose_guns"), "harpoon: replaces the stock nose guns")
	if h._fixed_art.size() == 1:
		for i in [0, 7, 19]:
			h.rotation = i * TAU / 32.0
			h._update_art()
			var a: Sprite2D = h._fixed_art[0]
			check(a.frame == i, "harpoon: frame follows the hull at %d" % i)
			var want: Vector2 = h.global_position + h._hull_art.point_offset("nose_mount")
			check((a.global_position + a.point_offset("pivot")).distance_to(want) < 0.01, "harpoon: on nose_mount at %d" % i)
	h.queue_free()
	var o := _rig({"weapons": ["outrider_twin_guns"]})
	check(o.art_layers().has("nose_guns"), "fixed gun without art keeps the stock nose guns")
	o.queue_free()
	var p := _rig({"utility": ["shock_pulse"]})
	check(p.art_layers().has("shock_emitter"), "shock pulse: emitter layer")
	p.queue_free()


## Sheets for ids from the unmerged content branch, keyed by those ids.
func _check_pending_ids() -> void:
	for id in ["torcher", "sludger", "rivet_gun", "flame_sprayer", "acid_lobber", "arc_projector", "harpoon", "mortar"]:
		check(Vehicle.art_path(id) != "", id + ": art found by id")
	for id in ["torcher", "sludger"]:
		var m := _meta(id)
		check((m.get("layers", {}) as Dictionary).has("elite_trim"), id + ": elite trim layer")
	var t := _meta("torcher")
	check((t.chunks as Dictionary).has("fuel_tank"), "torcher: fuel tank is its own wreck chunk")
	check((t.points as Dictionary).has("weak_spot") and (t.points as Dictionary).has("muzzle"), "torcher: weak spot and muzzle points")
	var s := _meta("sludger")
	check((s.points as Dictionary).has("turret_mount"), "sludger: turret mount")
	for id in ["mortar", "acid_lobber", "arc_projector", "harpoon", "rivet_gun", "flame_sprayer"]:
		var w := _meta(id)
		check((w.points as Dictionary).has("pivot") and (w.points as Dictionary).has("muzzle"), id + ": pivot and muzzle")
		check((w.points.pivot as Array).size() == 32, id + ": 32 headings")
	check(Vehicle.art_path("no_such_thing") == "", "unknown id has no art")


## Enemy hulls and trims never use cyan, push orange, shield blue or truck green.
func _check_enemy_palette() -> void:
	var forbidden := [Color8(64, 209, 224), Color8(237, 122, 43), Color8(140, 191, 255), Color8(115, 217, 128)]
	for id in ["outrider", "torcher", "sludger", "bulwark", "gunner", "scrapper", "scrapper_gunner", "convoy", "patcher", "convoy_trailer", "gunner_rig", "scrapper_turret", "convoy_turret"]:
		var m := _meta(id)
		var sheets: Array = [m.get("composite", m.sheet)]
		if (m.get("layers", {}) as Dictionary).has("elite_trim"):
			sheets.append(m.layers.elite_trim.sheet)
		if (m.get("layers", {}) as Dictionary).has("charge_glow"):
			sheets.append(m.layers.charge_glow.sheet)
		for sh in sheets:
			var img: Image = (load("res://art/sprites/" + String(sh)) as Texture2D).get_image()
			var hits := 0
			for y in img.get_height():
				for x in img.get_width():
					var c := img.get_pixel(x, y)
					if c.a > 0.5:
						for f: Color in forbidden:
							if absf(c.r - f.r) < 0.02 and absf(c.g - f.g) < 0.02 and absf(c.b - f.b) < 0.02:
								hits += 1
			check(hits == 0, "%s: %s has %d accent-colour pixels" % [id, sh, hits])


## Every enemy rig script: its own hull sheet (same body size, collision
## untouched), ground-centred frames, wreck chunks, the elite trim, turret art.
const RIGS := {
	"bulwark": ["res://scripts/bulwark_rig.gd", Vector2(84, 46), ""],
	"gunner": ["res://scripts/gunner_rig.gd", Vector2(74, 40), "gunner_rig.json"],
	"scrapper": ["res://scripts/scrapper_rig.gd", Vector2(62, 32), ""],
	"scrapper_gunner": ["res://scripts/scrapper_gunner_rig.gd", Vector2(64, 34), "scrapper_turret.json"],
	"convoy": ["res://scripts/convoy_rig.gd", Vector2(96, 46), ""],
	"patcher": ["res://scripts/patcher_rig.gd", Vector2(66, 34), ""],
	"convoy_trailer": ["res://scripts/convoy_trailer.gd", Vector2(70, 40), "convoy_turret.json"],
}


func _check_enemy_rigs() -> void:
	for id: String in RIGS:
		var spec: Array = RIGS[id]
		var r: Node2D = (load(spec[0]) as GDScript).new()
		root.add_child(r)
		check(r._hull_art != null and String(r._hull_art.meta_path).ends_with("/%s.json" % id), id + ": hull art by id")
		check(Vector2(r.body_len, r.body_wid) == spec[1], id + ": body size unchanged")
		var shapes := r.find_children("*", "CollisionShape2D", false, false)
		if shapes.size() > 0:
			var cap := (shapes[0] as CollisionShape2D).shape as CapsuleShape2D
			if cap != null:
				check(is_equal_approx(cap.height, spec[1].x) or cap.height <= spec[1].x, id + ": collision from body size")
		var m := _meta(id)
		check((m.get("chunks", {}) as Dictionary).size() >= 3, id + ": wreck chunks")
		var gc: Array = m.points.ground_centre[5]
		check(Vector2(gc[0], gc[1]) == Vector2.ZERO, id + ": frames centred on the ground footprint")
		if id != "convoy_trailer":
			check((m.layers as Dictionary).has("elite_trim"), id + ": elite trim layer")
			r.elite_name = "Test"   # make_elite is Outrider-stats only; the trim keys off is_elite()
			check(r.art_layers().has("elite_trim"), id + ": elite shows the trim")
			r._update_art()
			check(r._layer_sprites.has("elite_trim"), id + ": trim sprite built")
			r.elite_name = ""
		if spec[2] != "" and r.has_method("has_weapon") and r.has_weapon():
			var tu: Node2D = null
			for t in r._turrets:
				if t != null:
					tu = t
			check(tu != null and tu.art != null and String(tu.art.meta_path).ends_with(spec[2]), id + ": turret art " + spec[2])
			if tu != null and tu.art != null:
				r._update_art()
				var want: Vector2 = r.global_position + r._hull_art.point_offset("turret_mount")
				check((tu.art.global_position + tu.art.point_offset("pivot")).distance_to(want) < 0.01, id + ": turret on its mount")
		if id == "bulwark":
			r.mode = r.Mode.ATTACK
			check(not r.art_layers().has("windup_glow"), "bulwark without the wind-up interface: no glow, no errors")
		if id == "patcher":
			check((m.points as Dictionary).has("winch"), "patcher: winch point for the tow cable")
		r.queue_free()


## Weapon sheets at in-game scale (1 px per voxel, like the hulls): the turret
## ring is ~21 px across and the muzzle sits where the code-drawn barrel ended.
func _check_weapon_scale() -> void:
	var want := {"pintle_turret": 30.5, "burst_turret": 34.0, "gunner_rig": 34.0}
	for id: String in want:
		var m := _meta(id)
		var piv: Array = m.points.pivot[0]
		var muz: Array = m.points.muzzle[0]
		var d := Vector2(muz[0] - piv[0], muz[1] - piv[1]).length()
		check(absf(d - want[id]) <= 1.5, "%s: muzzle %.1f px from pivot (want %.1f)" % [id, d, want[id]])
	for id in ["mortar", "acid_lobber", "arc_projector", "harpoon", "rivet_gun", "flame_sprayer", "scrapper_turret", "convoy_turret"]:
		var m := _meta(id)
		var fw: float = m.frame_w
		check(fw >= 12 and fw <= 96, "%s: frame %d px wide, at hull scale" % [id, fw])


## Pre-ram wind-up glow, through a stub that has the interface Content will add.
func _check_windup() -> void:
	var b: Node2D = (load("res://tests/stubs/bulwark_windup_stub.gd") as GDScript).new()
	root.add_child(b)
	b._update_art()
	check(not b._layer_sprites.has("windup_glow"), "windup: idle, no glow")
	b.stub_winding = true
	var alphas: Array[float] = []
	for p in [0.0, 0.5, 1.0]:
		b.stub_progress = p
		b._update_art()
		check(b._layer_sprites.has("windup_glow") and b._layer_sprites.windup_glow.visible, "windup: glow at %.1f" % p)
		alphas.append(b._layer_sprites.windup_glow.modulate.a)
	check(alphas[0] >= 0.2 and alphas[2] >= 0.69, "windup: faint at 0, strong at 1 (a=%.2f / %.2f)" % [alphas[0], alphas[2]])
	b.stub_progress = 0.0
	var lo := 1.0
	var hi := 0.0
	for i in 60:   # sample a pulse at progress 0 -> min/max differ
		b._windup_t0 -= 0.02
		var a: float = b.art_layer_modulate("windup_glow").a
		lo = minf(lo, a)
		hi = maxf(hi, a)
	check(hi - lo > 0.15, "windup: glow pulses")
	b.stub_progress = 2.0
	check(is_equal_approx(b.art_windup_progress(), 1.0), "windup: progress clamped to 0..1")
	b.emit_signal("windup_started")
	check(absf(b._windup_t0 - Time.get_ticks_msec() * 0.001) < 0.1, "windup: windup_started restarts the pulse")
	b.stub_winding = false
	b._update_art()
	check(not b._layer_sprites.has("windup_glow"), "windup: glow gone after the ram")
	b.free()
