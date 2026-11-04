extends SceneTree
## Enemy + armed-rig review shot at in-game scale (needs a display):
##   xvfb-run -s "-screen 0 1280x720x24" godot --path . -s res://tools/art/capture_enemies.gd -- out.png
## Row 1: live rigs - Outrider, Hunt elite Outrider, Bulwark (charging glow),
##        Gunner Rig, Scrapper, Scrapper Gunner.
## Row 2: Convoy cab + trailer, Patcher, Torcher and Sludger (sheets: no rig
##        scripts on this branch; Content owns those).
## Row 3: armed player rigs - Pintle, Mortar, Harpoon (live), plus the pending
##        ids (Rivet Gun, Flame Sprayer on the nose; Acid Lobber, Arc Projector
##        on the turret mount) placed on Scrap Frame sheets the same way the game does.

const DS := preload("res://scripts/directional_sprite.gd")
const Vehicle := preload("res://scripts/vehicle.gd")
const Loadout := preload("res://scripts/loadout.gd")
const Parts := preload("res://scripts/parts.gd")

var _out := "user://enemies.png"
var _frames := 0
var _world: Node2D


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	_build.call_deferred()


func _sheet(id: String, at: Vector2, heading: float) -> Sprite2D:
	var s: Sprite2D = DS.new()
	s.load_meta("res://art/sprites/%s.json" % id)
	s.heading = heading
	s.position = at
	_world.add_child(s)
	return s


func _on(hull: Sprite2D, id: String, point: String, heading: float) -> void:
	var w := _sheet(id, Vector2.ZERO, heading)
	w.position = hull.position + hull.point_offset(point) - w.point_offset("pivot")
	w.z_index = 1


func _live(path: String, at: Vector2, rot: float) -> Node2D:
	var r: Node2D = (load(path) as GDScript).new()
	_world.add_child(r)
	r.position = at
	r.rotation = rot
	r.set_physics_process(false)
	return r


func _player(weapons: Array, at: Vector2, rot: float) -> Node2D:
	var lo: Dictionary = Parts.STARTER_LOADOUT.duplicate(true)
	lo.weapons = weapons
	var v: Node2D = Vehicle.new()
	_world.add_child(v)
	v.apply_stats(Loadout.build(lo))
	v.position = at
	v.rotation = rot
	v.set_physics_process(false)
	return v


func _build() -> void:
	_world = Node2D.new()
	root.add_child(_world)
	var bg := ColorRect.new()
	bg.color = Color(0.105, 0.105, 0.115)
	bg.size = Vector2(4000, 4000)
	bg.position = Vector2(-2000, -2000)
	_world.add_child(bg)
	var cam := Camera2D.new()
	cam.zoom = Vector2(1.85, 1.85)
	cam.position = Vector2(270, 100)
	_world.add_child(cam)
	cam.make_current()
	var er := "res://scripts/enemy_rig.gd"
	_live(er, Vector2(0, 0), 2.6)
	var e := _live(er, Vector2(90, 0), 0.5)
	e.make_elite("Gold Tooth", 2.0, 1.5)
	var b := _live("res://scripts/bulwark_rig.gd", Vector2(195, 0), -2.7)
	b.mode = b.Mode.ATTACK
	b._update_art()
	_live("res://scripts/gunner_rig.gd", Vector2(305, 0), 0.4)
	_live("res://scripts/scrapper_rig.gd", Vector2(405, 0), -0.6)
	_live("res://scripts/scrapper_gunner_rig.gd", Vector2(495, 0), 2.9)
	var cv := _live("res://scripts/convoy_rig.gd", Vector2(75, 95), 0.25)
	var tr: Node2D = cv.get("trailer")
	if tr != null:
		tr.set_physics_process(false)
		tr.rotation = cv.rotation
		tr.global_position = cv.global_position - Vector2(88, 0).rotated(cv.rotation)
		tr._update_art()
	_live("res://scripts/patcher_rig.gd", Vector2(195, 95), -2.2)
	_sheet("torcher", Vector2(305, 95), 2.2)
	var sl := _sheet("sludger", Vector2(420, 95), -0.4)
	_on(sl, "acid_lobber", "turret_mount", 1.0)
	_player(["pintle_turret"], Vector2(0, 190), -0.5)
	_player(["mortar"], Vector2(95, 190), 0.9)
	_player(["harpoon"], Vector2(190, 190), -2.4)
	var row := {"rivet_gun": "nose_mount", "flame_sprayer": "nose_mount", "acid_lobber": "turret_mount", "arc_projector": "turret_mount"}
	var x := 285.0
	for id: String in row:
		var h := _sheet("scrap_frame", Vector2(x, 190), -0.5)
		_on(h, id, row[id], -0.5 if row[id] == "nose_mount" else 2.0)
		x += 95.0


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 20:
		root.get_texture().get_image().save_png(_out)
		print("saved ", _out)
		quit()
	return false
