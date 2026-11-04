extends SceneTree
## Content art review shot (needs a display):
##   xvfb-run -s "-screen 0 1280x720x24" godot --path . -s res://tools/art/capture_content.gd -- out.png
## Top row: Courier Frame (player rig), Torcher, Sludger with its Acid Lobber,
## and a Hunt elite Outrider. Bottom row: the weapons lineup.
## The Torcher and Sludger have no rig scripts on this branch, so they are
## shown as plain sheets (with their elite trim) rather than live rigs.

const DS := preload("res://scripts/directional_sprite.gd")
const Vehicle := preload("res://scripts/vehicle.gd")
const EnemyRig := preload("res://scripts/enemy_rig.gd")
const Loadout := preload("res://scripts/loadout.gd")
const Parts := preload("res://scripts/parts.gd")

var _out := "user://content.png"
var _frames := 0
var _world: Node2D


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	_build.call_deferred()


func _sheet(id: String, at: Vector2, heading: float, layers: Array = []) -> Sprite2D:
	var s: Sprite2D = DS.new()
	s.load_meta("res://art/sprites/%s.json" % id)
	s.heading = heading
	s.position = at
	_world.add_child(s)
	for l in layers:
		var ls := Sprite2D.new()
		ls.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		ls.texture = load("res://art/sprites/" + String(s.meta.layers[l].sheet))
		ls.hframes = s.hframes
		ls.vframes = s.vframes
		ls.frame = s.frame
		s.add_child(ls)
	return s


func _build() -> void:
	_world = Node2D.new()
	root.add_child(_world)
	var bg := ColorRect.new()
	bg.color = Color(0.105, 0.105, 0.115)
	bg.size = Vector2(4000, 4000)
	bg.position = Vector2(-2000, -2000)
	_world.add_child(bg)
	var cam := Camera2D.new()
	cam.zoom = Vector2(2.7, 2.7)
	cam.position = Vector2(170, 20)
	_world.add_child(cam)
	cam.make_current()
	var lo: Dictionary = Parts.STARTER_LOADOUT.duplicate(true)
	lo.chassis = "courier_frame"
	lo.utility = ["shock_pulse"]
	var c: Node2D = Vehicle.new()
	_world.add_child(c)
	c.apply_stats(Loadout.build(lo))
	c.position = Vector2(0, -30)
	c.rotation = -0.5
	c.set_physics_process(false)
	_sheet("torcher", Vector2(95, -30), -2.6)
	var sl := _sheet("sludger", Vector2(200, -30), -0.4)
	var lob := _sheet("acid_lobber", Vector2.ZERO, 0.9)
	lob.position = sl.position + sl.point_offset("turret_mount") - lob.point_offset("pivot")
	lob.z_index = 1
	var e: Node2D = EnemyRig.new()
	_world.add_child(e)
	e.make_elite("Gold Tooth", 2.0, 1.5)
	e.position = Vector2(320, -30)
	e.rotation = 2.5
	e.set_physics_process(false)
	var ids := ["harpoon", "mortar", "rivet_gun", "flame_sprayer", "acid_lobber", "arc_projector", "pintle_turret"]
	for i in ids.size():
		_sheet(ids[i], Vector2(-10 + i * 55, 75), -0.55)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 20:
		root.get_texture().get_image().save_png(_out)
		print("saved ", _out)
		quit()
	return false
