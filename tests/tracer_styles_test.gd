extends SceneTree
## V4.3: per-weapon tracer looks are distinct, fall back sanely, and are visual only.

const TS := preload("res://scripts/tracer_styles.gd")
const BulletPool := preload("res://scripts/bullet_pool.gd")
const Parts := preload("res://scripts/parts.gd")
const Loadout := preload("res://scripts/loadout.gd")
const Vehicle := preload("res://scripts/vehicle.gd")
const LISTED := ["pintle_turret", "burst_turret", "gunner_rig", "hood_guns", "outrider_twin_guns", "convoy_nose", "rivet_gun", "harpoon",
		"heavy_mg_turret", "scattergun_turret", "flame_sprayer", "arc_projector", "convoy_turret", "scrapper"]
const STAT_KEYS := ["damage", "bullet_damage", "range", "bullet_speed", "speed", "fire_rate", "pellets", "spread_deg", "pierce"]
var fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		printerr("FAIL: ", msg)


func _init() -> void:
	_run.call_deferred()


func _key(s: Dictionary) -> String:
	return "%s|%s|%.2f|%.2f|%d" % [s.glow, s.core, s.length, s.width, s.dash]


func _run() -> void:
	# Each listed weapon resolves its own style; looks are distinct where they should be.
	var seen := {}
	for id: String in LISTED:
		var i := TS.index_for(id, false)
		check(i >= 2 or id == "pintle_turret", id + ": has an entry")
		var s := TS.style_for(id)
		for k in ["glow", "core", "length", "width", "dash"]:
			check(s.has(k), id + ": style has " + k)
		for k: String in STAT_KEYS:
			check(not s.has(k), id + ": style carries no stat (" + k + ")")
		seen[id] = _key(s)
	# Distinct: every listed id except the nose-gun twins (same guns, same look)
	var groups := {}
	for id: String in seen:
		groups[seen[id]] = groups.get(seen[id], []) + [id]
	for k: String in groups:
		var ids: Array = groups[k]
		check(ids.size() == 1 or ids == ["hood_guns", "outrider_twin_guns"], "distinct looks: %s share one" % str(ids))
	check(seen.pintle_turret == _key(TS.DEFAULT), "pintle keeps today's look (the default)")
	# Fallback
	check(TS.style_for("no_such_gun", false) == TS.DEFAULT, "unknown player gun -> player default")
	check(TS.style_for("no_such_gun", true) == TS.DEFAULT_ENEMY, "unknown enemy gun -> enemy default")
	check(TS.style_for("", true) == TS.DEFAULT_ENEMY, "no id -> enemy default")
	# Enemy styles stay in the enemy-red family (no player orange/cyan glow)
	for id in ["gunner_rig", "convoy_nose", "convoy_turret", "scrapper"]:
		check(TS.style_for(id).glow == TS.T.COL_ENEMY, id + ": enemy red glow")
	# Visual only: a styled bullet flies exactly like an unstyled one.
	var bp: Node2D = BulletPool.new()
	root.add_child(bp)
	bp.fire(Vector2.ZERO, Vector2(900, 0), 12.0, BulletPool.TEAM_PLAYER)
	bp.next_style = TS.index_for("rivet_gun", false)
	bp.fire(Vector2.ZERO, Vector2(900, 0), 12.0, BulletPool.TEAM_PLAYER)
	check(bp._vel[0] == bp._vel[1] and bp._dmg[0] == bp._dmg[1] and bp._life[0] == bp._life[1], "style changes no bullet numbers")
	check(bp.style_of(1) == TS.style_for("rivet_gun") and bp.style_of(0) == TS.DEFAULT, "bullets remember their style")
	bp.next_style = -1
	bp.fire(Vector2.ZERO, Vector2(900, 0), 12.0, BulletPool.TEAM_ENEMY)
	check(bp.style_of(2) == TS.DEFAULT_ENEMY, "team default when no style is set")
	# Weapon stat sheets are untouched by the style table (built stats equal the Parts data).
	for id in ["pintle_turret", "rivet_gun", "burst_turret", "harpoon"]:
		var lo: Dictionary = Parts.STARTER_LOADOUT.duplicate(true)
		lo.weapons = [id]
		var st: Dictionary = Loadout.build(lo)
		var w: Dictionary = (st.weapons as Array)[0]
		var p: Dictionary = Parts.get_part(id)
		check(is_equal_approx(float(w.fire_rate), float(p.fire_rate)) and is_equal_approx(float(w.bullet_speed), float(p.bullet_speed)), id + ": fire rate and speed unchanged")
	# A rig shooting tags its bullets with its weapon's style and then clears it.
	var v: Node2D = Vehicle.new()
	root.add_child(v)
	var lo2: Dictionary = Parts.STARTER_LOADOUT.duplicate(true)
	lo2.weapons = ["rivet_gun"]
	v.apply_stats(Loadout.build(lo2))
	v.bullets = bp
	var before: int = bp._count
	v._shoot(v.gun_stats[0], Vector2.ZERO, Vector2.RIGHT)
	check(bp._count > before and bp.style_of(bp._count - 1) == TS.style_for("rivet_gun"), "rivet gun shots carry the rivet look")
	check(bp.next_style == -1, "the style is cleared after the shot")
	print("TRACER STYLES TEST ", "PASSED" if fails == 0 else "FAILED (%d)" % fails)
	quit(1 if fails else 0)
