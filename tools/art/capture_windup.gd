extends SceneTree
## Bulwark pre-ram wind-up glow review shot (needs a display):
##   xvfb-run -s "-screen 0 1280x720x24" godot --path . -s res://tools/art/capture_windup.gd -- out.png
## Left to right: idle (no wind-up), then windup_progress 0, 0.5, 1 through the
## test stub; top row heading 0 (nose right), bottom row a 3/4 view.

var _out := "user://windup.png"
var _frames := 0
var _rigs: Array = []


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	_build.call_deferred()


func _build() -> void:
	var w := Node2D.new()
	root.add_child(w)
	var bg := ColorRect.new()
	bg.color = Color(0.105, 0.105, 0.115)
	bg.size = Vector2(4000, 4000)
	bg.position = Vector2(-2000, -2000)
	w.add_child(bg)
	var cam := Camera2D.new()
	cam.zoom = Vector2(3.0, 3.0)
	cam.position = Vector2(165, 45)
	w.add_child(cam)
	cam.make_current()
	var stub := load("res://tests/stubs/bulwark_windup_stub.gd") as GDScript
	for row in 2:
		for i in 4:
			var b: Node2D = stub.new()
			w.add_child(b)
			b.position = Vector2(i * 110, row * 90)
			b.rotation = 0.0 if row == 0 else -2.5
			b.set_physics_process(false)
			b.stub_winding = i > 0
			b.stub_progress = [0.0, 0.0, 0.5, 1.0][i]
			b._windup_t0 = Time.get_ticks_msec() * 0.001 - 0.25   # pulse near its peak
			_rigs.append(b)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 20:
		root.get_texture().get_image().save_png(_out)
		print("saved ", _out)
		quit()
	return false
