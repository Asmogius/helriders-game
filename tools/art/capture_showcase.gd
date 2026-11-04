extends SceneTree
## Art review shot (needs a display):
##   xvfb-run -s "-screen 0 1280x720x24" godot --path . -s res://tools/art/capture_showcase.gd -- out.png
## Left to right: starter Scrap Frame, a two-turret Bulwark Frame with part
## marks, an Outrider, and a Scrap Frame mid-wreck.

const Vehicle := preload("res://scripts/vehicle.gd")
const EnemyRig := preload("res://scripts/enemy_rig.gd")
const Loadout := preload("res://scripts/loadout.gd")
const Parts := preload("res://scripts/parts.gd")
const FX := preload("res://scripts/fx.gd")

var _out := "user://showcase.png"
var _frames := 0
var _world: Node2D
var _wreck: Node2D


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	_build.call_deferred()


func _rig(lo: Dictionary, at: Vector2, rot: float) -> Node2D:
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
	cam.zoom = Vector2(2.6, 2.6)
	cam.position = Vector2(180, 0)
	_world.add_child(cam)
	cam.make_current()
	_rig(Parts.STARTER_LOADOUT, Vector2(0, -40), -0.6)
	var lo: Dictionary = Parts.STARTER_LOADOUT.duplicate(true)
	lo.chassis = "bulwark_frame"
	lo.weapons = ["pintle_turret", "pintle_turret"]
	lo.drive = "off_road_tires"
	lo.armor_front = "riot_plating"
	lo.utility = ["mine_dropper"]
	var b := _rig(lo, Vector2(120, 40), 0.35)
	b._turrets[0].rotation = -0.8
	b._turrets[1].rotation = 2.4
	b.look.internal = ["roll_cage"]
	var e: Node2D = EnemyRig.new()
	_world.add_child(e)
	e.position = Vector2(250, -40)
	e.rotation = 2.6
	e.set_physics_process(false)
	_wreck = _rig(Parts.STARTER_LOADOUT, Vector2(370, 30), -2.0)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 30 and _wreck != null:
		_wreck._wreck()
	if _frames == 42:
		root.get_texture().get_image().save_png(_out)
		print("saved ", _out)
		quit()
	return false
