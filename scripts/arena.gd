extends Node2D
## Outer Blocks test arena: one ruined city block. Builds its own collision and
## draws everything static in a single pass (redrawn only once).

const T := preload("res://scripts/tuning.gd")

const WALL := 40.0
const PLAYER_START := Vector2(1600, 1200)

# Building footprints (x, y, w, h).
const BUILDINGS := [
	Rect2(180, 180, 420, 300),
	Rect2(900, 160, 520, 340),
	Rect2(1700, 220, 380, 280),
	Rect2(2400, 160, 560, 360),
	Rect2(160, 900, 300, 560),
	Rect2(2780, 860, 260, 600),
	Rect2(180, 1880, 420, 340),
	Rect2(1000, 1900, 440, 320),
	Rect2(1720, 1880, 360, 360),
	Rect2(2480, 1900, 520, 320),
]

# Props: [center, size, rotation, kind]  kind 0 = car wreck, 1 = barrier, 2 = crates
const PROPS := [
	[Vector2(1240, 980), Vector2(110, 54), 0.35, 0],
	[Vector2(1980, 1420), Vector2(110, 54), -0.4, 0],
	[Vector2(1080, 1360), Vector2(150, 36), 0.0, 1],
	[Vector2(2160, 960), Vector2(150, 36), 1.2, 1],
	[Vector2(1600, 860), Vector2(64, 64), 0.2, 2],
	[Vector2(1420, 1480), Vector2(64, 64), -0.1, 2],
	[Vector2(2500, 1250), Vector2(110, 54), 1.4, 0],
	[Vector2(760, 1150), Vector2(110, 54), -1.2, 0],
	[Vector2(1900, 700), Vector2(150, 36), 0.0, 1],
	[Vector2(1000, 1720), Vector2(110, 54), 0.1, 0],
]

# Roads as [start, end] bands along y (horizontal) or x (vertical).
const ROADS_H := [Vector2(620, 820), Vector2(1600, 1800)]
const ROADS_V := [Vector2(640, 860), Vector2(2120, 2360)]

# Courier checkpoints: open road and lots, clear of buildings and props.
const CHECKPOINTS := [
	Vector2(150, 720), Vector2(750, 720), Vector2(1450, 720), Vector2(2240, 720), Vector2(3050, 720),
	Vector2(150, 1700), Vector2(750, 1700), Vector2(1550, 1700), Vector2(2240, 1700), Vector2(3050, 1700),
	Vector2(750, 170), Vector2(750, 1400), Vector2(750, 2260),
	Vector2(2240, 170), Vector2(2240, 1250), Vector2(2240, 2260),
	Vector2(1350, 1250), Vector2(1950, 1150),
]

var spawn_points: Array[Vector2] = [
	Vector2(60, 720), Vector2(60, 1700), Vector2(3140, 720), Vector2(3140, 1700),
	Vector2(750, 60), Vector2(820, 2340), Vector2(2240, 60), Vector2(2240, 2340),
	Vector2(1560, 80), Vector2(1580, 2330), Vector2(100, 1200), Vector2(3110, 1200),
]


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
	for b: Rect2 in BUILDINGS:
		_add_box(solid, b.get_center(), b.size, 0.0)
	for p: Array in PROPS:
		_add_box(solid, p[0], p[1], p[2])


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
	draw_rect(Rect2(Vector2.ZERO, w), T.COL_CONCRETE)

	# Patchy lots so the concrete isn't flat.
	for i in 70:
		var tone := Color(1, 1, 1, 0.018) if i % 2 == 0 else Color(0, 0, 0, 0.05)
		draw_rect(Rect2(rng.randf_range(0, w.x), rng.randf_range(0, w.y), rng.randf_range(80, 320), rng.randf_range(60, 240)), tone)

	# Roads with curbs and broken centre dashes.
	for r: Vector2 in ROADS_H:
		draw_rect(Rect2(0, r.x, w.x, r.y - r.x), T.COL_ROAD)
		draw_rect(Rect2(0, r.x - 6, w.x, 6), Color(0.24, 0.235, 0.225))
		draw_rect(Rect2(0, r.y, w.x, 6), Color(0.24, 0.235, 0.225))
		var mid := (r.x + r.y) * 0.5
		var x := 20.0
		while x < w.x:
			if rng.randf() > 0.2:
				draw_rect(Rect2(x, mid - 3, 46, 6), T.COL_ROAD_LINE)
			x += 92.0
	for r: Vector2 in ROADS_V:
		draw_rect(Rect2(r.x, 0, r.y - r.x, w.y), T.COL_ROAD)
		draw_rect(Rect2(r.x - 6, 0, 6, w.y), Color(0.24, 0.235, 0.225))
		draw_rect(Rect2(r.y, 0, 6, w.y), Color(0.24, 0.235, 0.225))
		var mid := (r.x + r.y) * 0.5
		var y := 20.0
		while y < w.y:
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
	for b: Rect2 in BUILDINGS:
		draw_rect(Rect2(b.position + Vector2(16, 16), b.size), Color(0, 0, 0, 0.38))
	for b: Rect2 in BUILDINGS:
		_draw_building(b, rng)

	for p: Array in PROPS:
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
