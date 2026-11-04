extends "res://scripts/hostile.gd"
## A barrel (§14): a battlefield hazard at a fixed spot, its type rolled per
## job. Shoot it (20 HP) or ram it (any ram sets it off) and it blows,
## hitting everything in range, the player included, and setting off other
## barrels nearby.
##   explosive  60 damage and a strong shove
##   fire       25 fire damage, and the ground burns for 6 s (lights oil)
##   acid       20 damage and 80 acid buildup
##   slime      a 160 px slime pool for 10 s
##   boomer     fills the GOOPED bar of everything within 160 px
## The mission builds a few up front and places them; no allocation later.

const StatusBars := preload("res://scripts/status_bars.gd")
const RADIUS := 14.0
const COLORS := {"explosive": Color(0.85, 0.2, 0.15), "fire": Color(1.0, 0.55, 0.1), "acid": Color(0.55, 0.9, 0.2),
	"slime": Color(0.35, 0.8, 0.6), "boomer": Color(0.8, 0.8, 0.25)}

var kind := "explosive"
var hazards: Node2D        # GroundHazards
var fx: Node2D
var blasts := 0            # tests

var _shape: CollisionShape2D
var _query := PhysicsShapeQueryParameters2D.new()


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	var circle := CircleShape2D.new()
	circle.radius = RADIUS
	_shape = CollisionShape2D.new()
	_shape.shape = circle
	add_child(_shape)
	var reach := CircleShape2D.new()
	_query.shape = reach
	_query.collision_mask = T.LAYER_ZOMBIE | T.LAYER_VEHICLE | T.LAYER_ENEMY
	if not active:
		deactivate()


func place(at: Vector2, barrel_kind: String) -> void:
	kind = barrel_kind
	position = at
	hp = T.BARREL_HP
	active = true
	visible = true
	lock_priority = 0
	collision_layer = T.LAYER_ZOMBIE      # bullets and rigs hit it; zombies walk past
	collision_mask = 0
	if _shape != null:
		_shape.set_deferred("disabled", false)
	queue_redraw()


func deactivate() -> void:
	active = false
	visible = false
	collision_layer = 0
	if _shape != null:
		_shape.set_deferred("disabled", true)


## Barrels aren't lock targets.
func is_targetable() -> bool:
	return false


## Any ram sets it off; shots chip its 20 HP.
func take_hit(damage: float, _impulse: Vector2, cause := "shot", _dtype := "") -> void:
	if not active:
		return
	hp -= damage
	last_hit_cause = cause
	if cause == "rammed" or hp <= 0.0:
		explode()


func explode() -> void:
	if not active:
		return
	var at := global_position
	deactivate()   # first, so a chain can't set it off twice
	blasts += 1
	var reach := T.BARREL_BOOMER_RADIUS if kind == "boomer" else T.BARREL_RADIUS
	if fx != null:
		fx.call("blast", at, reach * 0.7)
	match kind:
		"slime":
			if hazards != null:
				hazards.call("add_slime", at, T.BARREL_SLIME_POOL)
			died.emit(at)
			return
		"fire":
			if hazards != null:
				hazards.call("add_fire", at, T.BARREL_RADIUS * 0.7, T.BARREL_FIRE_GROUND_TIME)
		"explosive":
			if hazards != null:
				hazards.call("ignite_oil", at, T.BARREL_RADIUS)
	(_query.shape as CircleShape2D).radius = reach
	_query.transform = Transform2D(0.0, at)
	for hit: Dictionary in get_world_2d().direct_space_state.intersect_shape(_query, 48):
		var body := hit.collider as Node2D
		if body == null or body == self or not body.has_method("take_hit"):
			continue
		var away := (body.global_position - at).normalized()
		match kind:
			"explosive":
				body.call("take_hit", T.BARREL_EXPLOSIVE_DAMAGE, away * T.BARREL_EXPLOSIVE_SHOVE, "blast", "")
			"fire":
				body.call("take_hit", T.BARREL_FIRE_DAMAGE, away * 300.0, "blast", "fire")
			"acid":
				body.call("take_hit", T.BARREL_ACID_DAMAGE, away * 300.0, "blast", "")
				if body.has_method("add_buildup"):
					body.call("add_buildup", StatusBars.ACID, T.BARREL_ACID_BUILDUP)
			"boomer":
				if body.has_method("fill_status"):
					body.call("fill_status", StatusBars.GOOP)
	died.emit(at)


func _draw() -> void:
	var c: Color = COLORS.get(kind, Color.WHITE)
	draw_circle(Vector2.ZERO, RADIUS, c.darkened(0.45))
	draw_circle(Vector2.ZERO, RADIUS - 3.0, c)
	draw_arc(Vector2.ZERO, RADIUS - 6.0, 0.0, TAU, 14, c.darkened(0.3), 2.0)
	draw_circle(Vector2.ZERO, 3.0, Color(0.1, 0.1, 0.1, 0.8))
