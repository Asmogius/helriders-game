extends RefCounted
## Coarse walkability grid over the arena so zombies and hunters can path
## around buildings instead of piling up behind them. Built once per mission.
## Uses Godot's native AStarGrid2D, so each path query is a cheap C++ call.

const T := preload("res://scripts/tuning.gd")
const Arena := preload("res://scripts/arena.gd")

const CELL := 40.0
const CLEARANCE := 14.0   # keep paths this far off walls (about a zombie's radius)

var astar := AStarGrid2D.new()
var _ray := PhysicsRayQueryParameters2D.new()


func _init() -> void:
	var cells := Vector2i(ceili(T.WORLD_SIZE.x / CELL), ceili(T.WORLD_SIZE.y / CELL))
	astar.region = Rect2i(Vector2i.ZERO, cells)
	astar.cell_size = Vector2(CELL, CELL)
	astar.offset = Vector2(CELL, CELL) * 0.5
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()
	for y in cells.y:
		for x in cells.x:
			if _blocked((Vector2(x, y) + Vector2(0.5, 0.5)) * CELL):
				astar.set_point_solid(Vector2i(x, y), true)
	_ray.collision_mask = T.LAYER_WORLD


func _blocked(p: Vector2) -> bool:
	var wall := Arena.WALL + CLEARANCE
	if p.x < wall or p.y < wall or p.x > T.WORLD_SIZE.x - wall or p.y > T.WORLD_SIZE.y - wall:
		return true
	for b: Rect2 in Arena.BUILDINGS:
		if b.grow(CLEARANCE).has_point(p):
			return true
	for prop: Array in Arena.PROPS:
		var center: Vector2 = prop[0]
		var size: Vector2 = prop[1]
		var local := (p - center).rotated(-float(prop[2]))
		var half := size * 0.5 + Vector2(CLEARANCE, CLEARANCE)
		if absf(local.x) <= half.x and absf(local.y) <= half.y:
			return true
	return false


func cell_of(p: Vector2) -> Vector2i:
	var size := astar.region.size
	return Vector2i(clampi(int(p.x / CELL), 0, size.x - 1), clampi(int(p.y / CELL), 0, size.y - 1))


func can_see(space: PhysicsDirectSpaceState2D, from: Vector2, to: Vector2) -> bool:
	_ray.from = from
	_ray.to = to
	return space.intersect_ray(_ray).is_empty()


## Where to walk next on the way from `from` to `to`. Returns `to` itself when
## there's a clear line or no path; otherwise a point a couple of cells ahead.
func next_waypoint(space: PhysicsDirectSpaceState2D, from: Vector2, to: Vector2) -> Vector2:
	if can_see(space, from, to):
		return to
	var a := _nearest_open(cell_of(from))
	if a.x < 0:
		return to
	var path := astar.get_point_path(a, cell_of(to), true)
	if path.size() < 2:
		return to
	return path[mini(2, path.size() - 1)]


## Hugging a wall can put you in a cell marked solid; start from the closest
## open cell around it instead. Returns (-1, -1) if there isn't one nearby.
func _nearest_open(cell: Vector2i) -> Vector2i:
	if not astar.is_point_solid(cell):
		return cell
	for r in range(1, 3):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var c := cell + Vector2i(dx, dy)
				if astar.region.has_point(c) and not astar.is_point_solid(c):
					return c
	return Vector2i(-1, -1)
