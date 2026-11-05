extends Node2D
## Every Mortar shell in flight lives in this one node: packed arrays, one
## draw pass, no per-shell nodes. Shells arc over buildings (walls don't stop
## them) and burst where they land: full damage at the center, half at the
## edge, to everything of the other side in the blast (zombies, rigs and
## barrels). It also draws the player's landing circle while they aim.

const T := preload("res://scripts/tuning.gd")
const BulletPool := preload("res://scripts/bullet_pool.gd")
const Mods := preload("res://scripts/mods.gd")

var fx: Node2D
var hazards: Node2D                 # GroundHazards: acid puddles
var blasts := 0                     # tests
var cluster_bomblets := 0           # tests
var etched := 0                     # Etch hits (tests)
var last_blast := Vector2.INF       # tests
var aim_at := Vector2.INF           # the player's landing circle (INF = hidden)
var aim_radius := 90.0
var aim_ammo := 0                   # shells left in the magazine (pips)
var aim_reloading := false

var _from := PackedVector2Array()
var _to := PackedVector2Array()
var _t := PackedFloat32Array()
var _flight := PackedFloat32Array()
var _dmg := PackedFloat32Array()
var _radius := PackedFloat32Array()
var _team := PackedByteArray()
var _dtype: Array[String] = []      # damage type each shell carries
var _extra: Array[Dictionary] = []  # fixed buildup / acid puddle (lobbers)
var _count := 0
var _query := PhysicsShapeQueryParameters2D.new()
var _shape := CircleShape2D.new()
var _aim_drawn := Vector2.INF


func _ready() -> void:
	z_index = 4
	_from.resize(T.SHELL_CAP)
	_to.resize(T.SHELL_CAP)
	_t.resize(T.SHELL_CAP)
	_flight.resize(T.SHELL_CAP)
	_dmg.resize(T.SHELL_CAP)
	_radius.resize(T.SHELL_CAP)
	_team.resize(T.SHELL_CAP)
	_dtype.resize(T.SHELL_CAP)
	_extra.resize(T.SHELL_CAP)
	_query.shape = _shape


## A shell from `from` landing at `to` after `flight` seconds. Returns false
## if the pool is full.
## `dtype` and `extra` (proposal 01 lobbers): "buildup_kind"/"buildup" add a
## fixed status amount to everything caught; "puddle_r"/"puddle_t" leave acid.
func launch(from: Vector2, to: Vector2, flight: float, damage: float, radius: float, team: int, dtype := "", extra := {}) -> bool:
	if _count >= T.SHELL_CAP:
		return false
	_from[_count] = from
	_to[_count] = to
	_t[_count] = 0.0
	_flight[_count] = maxf(flight, 0.1)
	_dmg[_count] = damage
	_radius[_count] = radius
	_team[_count] = team
	_dtype[_count] = dtype
	_extra[_count] = extra
	_count += 1
	return true


func active_count() -> int:
	return _count


func _physics_process(delta: float) -> void:
	var i := 0
	while i < _count:
		_t[i] += delta
		if _t[i] >= _flight[i]:
			_burst(i)
			_remove(i)
			continue
		i += 1
	if _count > 0 or aim_at != _aim_drawn:
		_aim_drawn = aim_at
		queue_redraw()
	elif aim_at != Vector2.INF:
		queue_redraw()


func _burst(i: int) -> void:
	if bool(_extra[i].get("cluster", false)):
		# Cluster Shell mod: 3 bomblets 70 px apart, 45 px blast, 40% damage each.
		var dir := (_to[i] - _from[i]).normalized()
		if dir == Vector2.ZERO:
			dir = Vector2.RIGHT
		var side := dir.orthogonal()
		var spots := [_to[i] + dir * Mods.CLUSTER_SPACING * 0.577,
			_to[i] - dir * Mods.CLUSTER_SPACING * 0.289 + side * Mods.CLUSTER_SPACING * 0.5,
			_to[i] - dir * Mods.CLUSTER_SPACING * 0.289 - side * Mods.CLUSTER_SPACING * 0.5]
		for at: Vector2 in spots:
			_blast(at, Mods.CLUSTER_BLAST, _dmg[i] * Mods.CLUSTER_DAMAGE, _team[i], _dtype[i], {})
		cluster_bomblets += Mods.CLUSTER_COUNT
		return
	_blast(_to[i], _radius[i], _dmg[i], _team[i], _dtype[i], _extra[i])


func _blast(at: Vector2, r: float, damage: float, team: int, dtype: String, extra: Dictionary) -> void:
	blasts += 1
	last_blast = at
	if fx != null:
		fx.call("blast", at, r)
	if dtype != "acid" and not extra.has("puddle_r") and not extra.has("buildup_kind"):   # acid and goop shells have their own
		var music := get_node_or_null("/root/MusicManager")
		if music != null:
			music.call("play_combat", "explosion")
	_shape.radius = r
	_query.transform = Transform2D(0.0, at)
	_query.collision_mask = T.LAYER_ZOMBIE | (T.LAYER_ENEMY if team == BulletPool.TEAM_PLAYER else T.LAYER_VEHICLE)
	for hit: Dictionary in get_world_2d().direct_space_state.intersect_shape(_query, 48):
		var body := hit.collider as Node2D
		if body == null or not body.has_method("take_hit"):
			continue
		var away := body.global_position - at
		var falloff := lerpf(1.0, T.MORTAR_EDGE_DAMAGE, clampf(away.length() / r, 0.0, 1.0))
		var dmg := damage * falloff
		# Etch mod (Acid Lobber): CORRODED rigs take +20% while they have armor.
		if bool(extra.get("etch", false)) and body.has_method("is_status") and bool(body.call("is_status", 2)) \
				and float(body.call("_armor_total")) > 0.0:
			dmg *= 1.0 + Mods.ETCH_ARMOR
			etched += 1
		body.call("take_hit", dmg, away.normalized() * 300.0, "blast", dtype)
		if extra.has("buildup_kind") and body.has_method("add_buildup"):
			body.call("add_buildup", int(extra.buildup_kind), float(extra.buildup))
	if dtype == "acid" or extra.has("puddle_r"):
		var music := get_node_or_null("/root/MusicManager")
		if music != null:
			music.play_sfx("acid_impact")
	if extra.has("puddle_r") and hazards != null:
		hazards.call("add_acid", at, float(extra.puddle_r), float(extra.puddle_t), team)


func _remove(i: int) -> void:
	_count -= 1
	for k in range(i, _count):
		_from[k] = _from[k + 1]
		_to[k] = _to[k + 1]
		_t[k] = _t[k + 1]
		_flight[k] = _flight[k + 1]
		_dmg[k] = _dmg[k + 1]
		_radius[k] = _radius[k + 1]
		_team[k] = _team[k + 1]
		_dtype[k] = _dtype[k + 1]
		_extra[k] = _extra[k + 1]


func _draw() -> void:
	for i in _count:
		var k := _t[i] / _flight[i]
		var ground := _from[i].lerp(_to[i], k)
		var height := sin(k * PI) * 160.0
		var hostile := _team[i] != BulletPool.TEAM_PLAYER
		# Where it will land, so you can get out of the way.
		draw_arc(_to[i], _radius[i], 0.0, TAU, 32, Color(1.0, 0.35, 0.2, 0.25 + 0.5 * k) if hostile else Color(1.0, 0.75, 0.3, 0.2 + 0.3 * k), 2.0)
		draw_circle(ground, 6.0, Color(0.0, 0.0, 0.0, 0.35))   # its shadow
		var shell := ground + Vector2(0.0, -height)
		draw_circle(shell, 5.0 + height * 0.02, Color(0.22, 0.22, 0.2))
		draw_circle(shell, 2.5, Color(1.0, 0.7, 0.3))
	if aim_at != Vector2.INF:
		var col := Color(1.0, 0.75, 0.3, 0.55 if not aim_reloading else 0.25)
		draw_arc(aim_at, aim_radius, 0.0, TAU, 40, col, 2.5)
		draw_line(aim_at + Vector2(-10, 0), aim_at + Vector2(10, 0), col, 2.0)
		draw_line(aim_at + Vector2(0, -10), aim_at + Vector2(0, 10), col, 2.0)
		for n in aim_ammo:
			draw_circle(aim_at + Vector2(-10.0 + 10.0 * n, aim_radius + 12.0), 3.5, col)
