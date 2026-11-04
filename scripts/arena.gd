extends Node2D
## The arena: one ruined city block, laid out from layouts.gd. Builds its own collision and
## draws everything static in a single pass (redrawn only once).

const T := preload("res://scripts/tuning.gd")

const WALL := 40.0
const Layouts := preload("res://scripts/layouts.gd")

# The map this job runs on (layouts.gd). Set with setup() before the arena
# enters the tree; defaults to the Crossroads as drawn.
var layout: Dictionary = Layouts.build(Layouts.DEFAULT)
var player_start: Vector2
var buildings: Array = []      # Rect2
var props: Array = []          # [center, size, rotation, kind]
var roads: Array = []          # Rect2, drawn only
var checkpoints: Array = []    # Courier stops, Retrieve caches, Escort sites
var barrel_spots: Array = []
var spawn_points: Array[Vector2] = []

# --- P4 Outer Blocks map style (VISUAL_PLAN V5.5) -----------------------------
# Off by default until the owner approves it; captures turn it on. When on, an
# Outer Blocks layout (layouts.gd `district`) is baked whole-map from art/map/
# into a few chunk textures (map_art.gd); missing art keeps the code-drawn look.
# Purely visual: collision and layout data are untouched.
const MapArt := preload("res://scripts/map_art.gd")
const MapAmbient := preload("res://scripts/map_ambient.gd")
const STYLED_DISTRICTS := ["outer_blocks"]
static var outer_blocks_style := false
var _chunks: Array = []        # [[Rect2, Texture2D], ...] from MapArt.bake_chunks
var bake_ms := 0.0             # last bake, start to textures ready (perf captures)
var bake_main_ms := 0.0        # of which spent on the main thread (atlas reads, uploads)
var bake_peak_bytes := 0       # static memory peak above the pre-bake level
var bake_bytes := 0            # GPU bytes of the baked map
var bake_cached := false       # the last bake came from the cache (RESTART)
var _task := -1                # WorkerThreadPool task while baking
var _task_out: Array = []
var _bake_t0 := 0
var _mem0 := 0
# Last bake, keyed by layout + variation (seed_for) + texture mode; one entry,
# so RESTART of the same job skips the bake and memory stays bounded.
static var _cache_key := ""
static var _cache_chunks: Array = []


func _init() -> void:
	setup(layout)


func setup(l: Dictionary) -> void:
	layout = l
	player_start = l.start
	buildings = l.buildings
	props = l.props
	roads = l.roads
	checkpoints = l.checkpoints
	barrel_spots = l.barrel_spots
	spawn_points.clear()
	for p: Vector2 in l.spawn_points:
		spawn_points.append(p)


func _ready() -> void:
	z_index = -10
	var solid := StaticBody2D.new()
	solid.collision_layer = T.LAYER_WORLD
	solid.collision_mask = 0
	add_child(solid)
	var w := T.WORLD_SIZE
	# Boundary walls.
	_add_box(solid, Vector2(w.x * 0.5, WALL * 0.5), Vector2(w.x, WALL), 0.0)
	_add_box(solid, Vector2(w.x * 0.5, w.y - WALL * 0.5), Vector2(w.x, WALL), 0.0)
	_add_box(solid, Vector2(WALL * 0.5, w.y * 0.5), Vector2(WALL, w.y), 0.0)
	_add_box(solid, Vector2(w.x - WALL * 0.5, w.y * 0.5), Vector2(WALL, w.y), 0.0)
	for b: Rect2 in buildings:
		_add_box(solid, b.get_center(), b.size, 0.0)
	for p: Array in props:
		_add_box(solid, p[0], p[1], p[2])
	if outer_blocks_style and STYLED_DISTRICTS.has(str(layout.get("district", ""))):
		_setup_style()


func is_styled() -> bool:
	return not _chunks.is_empty()


func _setup_style() -> void:
	_bake_t0 = Time.get_ticks_usec()
	_mem0 = OS.get_static_memory_usage()
	var single := MapArt.max_texture_size() >= maxi(int(T.WORLD_SIZE.x), int(T.WORLD_SIZE.y))
	var data := MapArt.snapshot(self)
	var key := "%s:%d:%d:%s" % [str(layout.get("id", "")), MapArt.seed_for(data), hash(str(layout.get("surfaces", []))), str(single)]
	if key == _cache_key and not _cache_chunks.is_empty():
		bake_cached = true
		_use_chunks(_cache_chunks)
		bake_main_ms = (Time.get_ticks_usec() - _bake_t0) / 1000.0
		bake_ms = bake_main_ms
		return
	_cache_key = ""
	_cache_chunks = []   # drop the old map before baking the new one
	var src := MapArt.load_sources()   # main thread: texture reads
	if src.is_empty():
		return   # missing art: code-drawn look stays
	bake_main_ms = (Time.get_ticks_usec() - _bake_t0) / 1000.0
	_task_out = []
	var out := _task_out
	_task = WorkerThreadPool.add_task(func() -> void: out.append_array(MapArt.bake_images(data, src, single)), false, "map bake")
	set_meta("bake_key", key)
	set_process(true)


## True while the background bake runs (the code-drawn look shows meanwhile).
func is_baking() -> bool:
	return _task >= 0


## Blocks until a running bake finishes (tests and captures).
func finish_bake() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_bake_done()


func _process(_delta: float) -> void:
	if _task < 0:
		set_process(false)
		return
	if WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_bake_done()


func _exit_tree() -> void:
	if _task >= 0:   # never leave a worker writing into a freed arena
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


func _bake_done() -> void:
	set_process(false)
	bake_peak_bytes = maxi(0, int(OS.get_static_memory_peak_usage()) - _mem0)
	var t1 := Time.get_ticks_usec()
	var chunks: Array = []
	for c: Array in _task_out:
		chunks.append([c[0], ImageTexture.create_from_image(c[1])])
	_task_out = []   # free the images
	bake_main_ms += (Time.get_ticks_usec() - t1) / 1000.0
	bake_ms = (Time.get_ticks_usec() - _bake_t0) / 1000.0
	if chunks.is_empty():
		return
	_cache_key = str(get_meta("bake_key", ""))
	_cache_chunks = chunks
	_use_chunks(chunks)


func _use_chunks(chunks: Array) -> void:
	_chunks = chunks
	bake_bytes = MapArt.chunk_bytes(_chunks)
	queue_redraw()
	var profile := get_node_or_null("/root/Profile")
	var low := profile != null and profile.has_method("quality") and float(profile.quality().fx) < 0.5
	if not low:
		var motes := MapAmbient.new()
		motes.z_index = 5
		motes.setup(Rect2(Vector2.ZERO, T.WORLD_SIZE), 160)
		add_child(motes)


func _add_box(body: StaticBody2D, center: Vector2, size: Vector2, rot: float) -> void:
	var rect := RectangleShape2D.new()
	rect.size = size
	var shape := CollisionShape2D.new()
	shape.shape = rect
	shape.position = center
	shape.rotation = rot
	body.add_child(shape)


func _draw() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	var w := T.WORLD_SIZE
	if not _chunks.is_empty():
		# Baked Outer Blocks look: ground, buildings and decor, one draw per chunk.
		for c: Array in _chunks:
			draw_texture_rect(c[1], c[0], false, T.COL_OB_GRADE)
		_draw_props_and_wall(w)
		return
	draw_rect(Rect2(Vector2.ZERO, w), T.COL_CONCRETE)

	# Patchy lots so the concrete isn't flat.
	for i in 70:
		var tone := Color(1, 1, 1, 0.018) if i % 2 == 0 else Color(0, 0, 0, 0.05)
		draw_rect(Rect2(rng.randf_range(0, w.x), rng.randf_range(0, w.y), rng.randf_range(80, 320), rng.randf_range(60, 240)), tone)

	# Roads with curbs and broken centre dashes, along their long side.
	var curb := Color(0.24, 0.235, 0.225)
	for r: Rect2 in roads:
		draw_rect(r, T.COL_ROAD)
		if r.size.x >= r.size.y:
			draw_rect(Rect2(r.position.x, r.position.y - 6, r.size.x, 6), curb)
			draw_rect(Rect2(r.position.x, r.end.y, r.size.x, 6), curb)
			var mid := r.get_center().y
			var x := r.position.x + 20.0
			while x < r.end.x:
				if rng.randf() > 0.2:
					draw_rect(Rect2(x, mid - 3, 46, 6), T.COL_ROAD_LINE)
				x += 92.0
		else:
			draw_rect(Rect2(r.position.x - 6, r.position.y, 6, r.size.y), curb)
			draw_rect(Rect2(r.end.x, r.position.y, 6, r.size.y), curb)
			var mid := r.get_center().x
			var y := r.position.y + 20.0
			while y < r.end.y:
				if rng.randf() > 0.2:
					draw_rect(Rect2(mid - 3, y, 6, 46), T.COL_ROAD_LINE)
				y += 92.0

	# Cracks and rubble.
	for i in 160:
		var from := Vector2(rng.randf_range(0, w.x), rng.randf_range(0, w.y))
		var to := from + Vector2.RIGHT.rotated(rng.randf() * TAU) * rng.randf_range(20, 90)
		draw_line(from, to, Color(0, 0, 0, 0.3), 2.0)
	for i in 260:
		var s := rng.randf_range(3, 9)
		var c := Color(0.3, 0.29, 0.27) if i % 3 != 0 else T.COL_RUST.darkened(0.35)
		draw_rect(Rect2(rng.randf_range(0, w.x), rng.randf_range(0, w.y), s, s), c)

	# Buildings: drop shadow for fake height, then walls and roof.
	for b: Rect2 in buildings:
		draw_rect(Rect2(b.position + Vector2(16, 16), b.size), Color(0, 0, 0, 0.38))
	for b: Rect2 in buildings:
		_draw_building(b, rng)

	_draw_props_and_wall(w)


func _draw_props_and_wall(w: Vector2) -> void:
	for p: Array in props:
		_draw_prop(p[0], p[1], p[2], p[3])

	# Perimeter wall.
	var wall_col := Color(0.2, 0.19, 0.18)
	draw_rect(Rect2(0, 0, w.x, WALL), wall_col)
	draw_rect(Rect2(0, w.y - WALL, w.x, WALL), wall_col)
	draw_rect(Rect2(0, 0, WALL, w.y), wall_col)
	draw_rect(Rect2(w.x - WALL, 0, WALL, w.y), wall_col)


func _draw_building(b: Rect2, rng: RandomNumberGenerator) -> void:
	draw_rect(b, T.COL_BUILDING)
	var roof := b.grow(-10)
	draw_rect(roof, T.COL_ROOF)
	# Roof clutter: vents and AC units.
	for i in rng.randi_range(3, 7):
		var s := Vector2(rng.randf_range(18, 46), rng.randf_range(18, 46))
		var p := Vector2(rng.randf_range(roof.position.x + 8, roof.end.x - s.x - 8), rng.randf_range(roof.position.y + 8, roof.end.y - s.y - 8))
		draw_rect(Rect2(p, s), T.COL_BUILDING.darkened(0.2))
		draw_rect(Rect2(p + Vector2(3, 3), s - Vector2(6, 6)), T.COL_ROOF.lightened(0.06))
	# Rust streaks down one edge.
	for i in 4:
		var x := rng.randf_range(b.position.x + 10, b.end.x - 20)
		draw_rect(Rect2(x, b.end.y - 26, rng.randf_range(6, 14), 22), Color(T.COL_RUST, 0.55))
	# A practical light strip on one face: cyan or orange.
	var accent := T.COL_CYAN if rng.randf() < 0.5 else T.COL_ORANGE
	match rng.randi_range(0, 3):
		0: draw_rect(Rect2(b.position.x + 12, b.position.y, b.size.x - 24, 3), accent)
		1: draw_rect(Rect2(b.position.x + 12, b.end.y - 3, b.size.x - 24, 3), accent)
		2: draw_rect(Rect2(b.position.x, b.position.y + 12, 3, b.size.y - 24), accent)
		_: draw_rect(Rect2(b.end.x - 3, b.position.y + 12, 3, b.size.y - 24), accent)


func _draw_prop(center: Vector2, size: Vector2, rot: float, kind: int) -> void:
	draw_set_transform(center + Vector2(8, 8), rot, Vector2.ONE)
	draw_rect(Rect2(-size * 0.5, size), Color(0, 0, 0, 0.35))
	draw_set_transform(center, rot, Vector2.ONE)
	var half := size * 0.5
	match kind:
		0:  # Burnt-out car.
			draw_rect(Rect2(-half, size), T.COL_RUST.darkened(0.15))
			draw_rect(Rect2(-half.x + 22, -half.y + 6, size.x - 44, size.y - 12), Color(0.1, 0.09, 0.08))
			draw_rect(Rect2(-half.x + 4, -half.y + 4, 14, size.y - 8), T.COL_RUST.darkened(0.4))
		1:  # Concrete barrier with hazard stripes.
			draw_rect(Rect2(-half, size), Color(0.42, 0.41, 0.38))
			var x := -half.x + 6
			while x < half.x - 10:
				draw_rect(Rect2(x, -half.y + 4, 10, size.y - 8), T.COL_ORANGE.darkened(0.2))
				x += 24
		_:  # Crate stack.
			draw_rect(Rect2(-half, size), Color(0.36, 0.27, 0.17))
			draw_rect(Rect2(-half + Vector2(4, 4), half - Vector2(6, 6)), Color(0.42, 0.32, 0.2))
			draw_rect(Rect2(Vector2(2, 2), half - Vector2(6, 6)), Color(0.42, 0.32, 0.2))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
