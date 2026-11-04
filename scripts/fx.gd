extends Node2D
## Cheap voxel-square particles for sparks, gore, flames and the wreck blast.
## One node, packed arrays, one draw pass. Hard cap keeps low-end phones safe.

const T := preload("res://scripts/tuning.gd")
const MAX_PARTICLES := 320

var density := 1.0      # share of particles drawn (quality preset)
var _skip := 0.0

var _pos := PackedVector2Array()
var _vel := PackedVector2Array()
var _life := PackedFloat32Array()
var _max_life := PackedFloat32Array()
var _size := PackedFloat32Array()
var _drag := PackedFloat32Array()
var _col := PackedColorArray()
var _count := 0

# --- V4 style sample (P2): atlas sprites for the explosion. Missing atlas ->
# the square particles below stay the whole look (fallback). -----------------
const FxGlow := preload("res://scripts/fx_glow.gd")
const ArtAtlas := preload("res://scripts/art_atlas.gd")   # P0 atlas loader
const ATLAS_BASE := "res://art/fx/fx_atlas"
var atlas: RefCounted
var glow: Node2D       # additive: flash, fireball, shockwave
var smoke: Node2D      # normal blend: smoke column, debris chips
var decals: Node2D     # under the rigs: scorch


func _ready() -> void:
	_pos.resize(MAX_PARTICLES)
	_vel.resize(MAX_PARTICLES)
	_life.resize(MAX_PARTICLES)
	_max_life.resize(MAX_PARTICLES)
	_size.resize(MAX_PARTICLES)
	_drag.resize(MAX_PARTICLES)
	_col.resize(MAX_PARTICLES)
	atlas = ArtAtlas.load_atlas(ATLAS_BASE)
	if not atlas.ok():
		atlas = null
	if atlas != null:
		decals = FxGlow.new()
		decals.setup(atlas, false)
		decals.z_index = -1          # scorch under rigs and zombies
		add_child(decals)
		smoke = FxGlow.new()
		smoke.setup(atlas, false)
		add_child(smoke)
		glow = FxGlow.new()
		glow.setup(atlas, true)
		add_child(glow)


func emit(at: Vector2, velocity: Vector2, life: float, size: float, color: Color, drag := 3.0) -> void:
	if _count >= MAX_PARTICLES:
		return
	if density < 1.0:
		# Lower quality presets draw a share of the particles.
		_skip += density
		if _skip < 1.0:
			return
		_skip -= 1.0
	_pos[_count] = at
	_vel[_count] = velocity
	_life[_count] = life
	_max_life[_count] = life
	_size[_count] = size
	_drag[_count] = drag
	_col[_count] = color
	_count += 1


func sparks(at: Vector2, normal: Vector2) -> void:
	for i in 4:
		var dir := normal.rotated(randf_range(-1.0, 1.0))
		emit(at, dir * randf_range(180.0, 420.0), randf_range(0.12, 0.25), 3.0, T.COL_ORANGE.lightened(0.3), 6.0)


## A hit blunted by heavy armor: grey, shorter sparks.
func deflect(at: Vector2, normal: Vector2) -> void:
	for i in 4:
		var dir := normal.rotated(randf_range(-1.2, 1.2))
		emit(at, dir * randf_range(120.0, 300.0), randf_range(0.1, 0.2), 3.0, Color(0.78, 0.78, 0.76), 7.0)


func gore(at: Vector2, direction: Vector2) -> void:
	for i in 9:
		var dir := direction.rotated(randf_range(-1.2, 1.2)) if direction != Vector2.ZERO else Vector2.RIGHT.rotated(randf() * TAU)
		var color := T.COL_ZOMBIE if i % 3 == 0 else T.COL_BLOOD
		emit(at, dir * randf_range(60.0, 260.0), randf_range(0.3, 0.6), randf_range(4.0, 7.0), color, 5.0)


func flame(at: Vector2) -> void:
	var color := T.COL_ORANGE if randf() < 0.6 else Color(1.0, 0.82, 0.35)
	emit(at, Vector2(randf_range(-20.0, 20.0), randf_range(-60.0, -20.0)), randf_range(0.3, 0.6), randf_range(5.0, 9.0), color, 1.5)
	if randf() < 0.35:
		emit(at, Vector2(randf_range(-15.0, 15.0), randf_range(-40.0, -10.0)), randf_range(0.8, 1.4), randf_range(10.0, 16.0), Color(0.12, 0.11, 0.1, 0.7), 0.8)


func explosion(at: Vector2, carry: Vector2) -> void:
	if glow != null:
		_atlas_explosion(at, carry)
		return
	# Armor plates and hull chunks.
	var palette: Array[Color] = [T.COL_STEEL, T.COL_RUST, T.COL_STEEL.darkened(0.3), T.COL_CYAN]
	for i in 36:
		var dir := Vector2.RIGHT.rotated(randf() * TAU)
		emit(at, carry * 0.4 + dir * randf_range(150.0, 620.0), randf_range(0.6, 1.3), randf_range(5.0, 11.0), palette[i % palette.size()], 2.5)
	# Fireball.
	for i in 40:
		var dir := Vector2.RIGHT.rotated(randf() * TAU)
		var color := T.COL_ORANGE if i % 2 == 0 else Color(1.0, 0.85, 0.4)
		emit(at, dir * randf_range(40.0, 260.0), randf_range(0.3, 0.8), randf_range(8.0, 16.0), color, 3.0)
	# Concrete dust.
	for i in 24:
		var dir := Vector2.RIGHT.rotated(randf() * TAU)
		emit(at, dir * randf_range(30.0, 160.0), randf_range(1.0, 2.0), randf_range(14.0, 24.0), Color(0.35, 0.33, 0.3, 0.5), 1.2)


## Green motes when the Emergency Patch fires.
func repair(at: Vector2) -> void:
	for i in 16:
		var dir := Vector2.RIGHT.rotated(randf() * TAU)
		emit(at + dir * randf_range(8.0, 30.0), dir * randf_range(30.0, 110.0), randf_range(0.4, 0.8), randf_range(3.0, 6.0), Color(0.45, 0.9, 0.5), 2.0)


## A mine going off: a ring of fire sized to the blast radius, plus dust.
func blast(at: Vector2, radius: float) -> void:
	for i in 22:
		var dir := Vector2.RIGHT.rotated(randf() * TAU)
		var color := T.COL_ORANGE if i % 2 == 0 else Color(1.0, 0.85, 0.4)
		emit(at, dir * randf_range(radius * 1.2, radius * 3.0), randf_range(0.25, 0.5), randf_range(7.0, 13.0), color, 4.0)
	for i in 10:
		var dir := Vector2.RIGHT.rotated(randf() * TAU)
		emit(at, dir * randf_range(20.0, radius), randf_range(0.8, 1.4), randf_range(12.0, 20.0), Color(0.35, 0.33, 0.3, 0.5), 1.5)


func _process(delta: float) -> void:
	if _count == 0:
		return
	var i := 0
	while i < _count:
		_life[i] -= delta
		if _life[i] <= 0.0:
			_count -= 1
			_pos[i] = _pos[_count]
			_vel[i] = _vel[_count]
			_life[i] = _life[_count]
			_max_life[i] = _max_life[_count]
			_size[i] = _size[_count]
			_drag[i] = _drag[_count]
			_col[i] = _col[_count]
			continue
		_vel[i] *= exp(-_drag[i] * delta)
		_pos[i] += _vel[i] * delta
		i += 1
	queue_redraw()


func _draw() -> void:
	for i in _count:
		var color := _col[i]
		color.a *= clampf(_life[i] / _max_life[i], 0.0, 1.0)
		var s := _size[i]
		draw_rect(Rect2(_pos[i] - Vector2(s, s) * 0.5, Vector2(s, s)), color)


## V4.4 sample sequence: flash -> fireball (additive) -> shockwave ring ->
## flung debris -> a rising smoke column that drifts; a scorch decal stays.
func _atlas_explosion(at: Vector2, carry: Vector2) -> void:
	for l: Node2D in [glow, smoke, decals]:
		l.set("density", density)
	glow.spawn("flash", 3, at, Vector2.ZERO, 0.12, 2.2, 2.8, Color.WHITE, 0.0, randf() * TAU, 0.0, 0.0, 0.0, true)
	glow.spawn("fireball", 6, at, carry * 0.2, 0.7, 1.7, 2.3, Color.WHITE, 3.0, randf() * TAU, 0.0, 0.0, 1.0, true)
	for i in 3:
		var off := Vector2.RIGHT.rotated(randf() * TAU) * randf_range(10.0, 22.0)
		glow.spawn("fireball", 6, at + off, carry * 0.2 + off * 2.0, randf_range(0.45, 0.6), 0.9, 1.3, Color.WHITE, 3.0, randf() * TAU, 0.0, 0.0, 1.0)
	glow.spawn("ring", 1, at, Vector2.ZERO, 0.35, 0.3, 2.6, Color(1.0, 1.0, 1.0, 0.9), 0.0, 0.0, 0.0, 0.0, 0.0, true)
	for i in 14:
		var dir := Vector2.RIGHT.rotated(randf() * TAU)
		var chip := "chip_rust_%d" % (i % 3) if i % 2 == 0 else "chip_steel_%d" % (i % 3)
		smoke.spawn(chip, 1, at, carry * 0.4 + dir * randf_range(160.0, 520.0), randf_range(0.7, 1.3), 2.0, 2.0, Color.WHITE, 2.5, randf() * TAU, randf_range(-14.0, 14.0), 0.0, 1.0)
	var drift := Vector2(randf_range(-14.0, 14.0), 0.0)
	for i in 7:
		var sz := "smoke_%d" % mini(3, 1 + i / 2)
		smoke.spawn(sz, 1, at + Vector2(randf_range(-10.0, 10.0), randf_range(-6.0, 6.0)), drift + Vector2(randf_range(-10.0, 10.0), -randf_range(10.0, 30.0)),
				randf_range(1.8, 3.2), 1.2, 3.4, Color(1.0, 1.0, 1.0, 0.85), 0.6, randf() * TAU, randf_range(-0.6, 0.6), 18.0)
	decals.spawn("scorch", 1, at, Vector2.ZERO, 30.0, 1.6, 1.6, Color(1.0, 1.0, 1.0, 0.9), 0.0, randf() * TAU, 0.0, 0.0, 1.0, true)
	# A few square embers keep the old sparkle.
	for i in 10:
		var dir := Vector2.RIGHT.rotated(randf() * TAU)
		emit(at, dir * randf_range(120.0, 380.0), randf_range(0.25, 0.5), 3.0, T.COL_ORANGE.lightened(0.3), 4.0)
