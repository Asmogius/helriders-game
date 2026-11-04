extends Node2D
## Keyword feedback (§14): one symbol, one short animation and one fixed
## color per keyword (T.KEYWORDS), popped above whatever it happened to.
## No floating text. Every popup lives in this one node: packed arrays, one
## draw pass. At most T.KEYWORD_MAX_ON_SCREEN at once; rigs throttle their
## own popups (Vehicle.keyword_pop).

const T := preload("res://scripts/tuning.gd")

const LIFE := 0.7            # seconds on screen (the animation is the first 0.4)
const RISE := 26.0           # px it drifts up
const ORDER := ["RAM", "DRIFT", "BURST", "MARKED", "STUNNED", "OVERLOAD", "SLICK", "BURNING", "CORRODED", "GOOPED", "TOXIC"]

var shown := 0               # popups ever shown (tests)
var counts := {}             # keyword -> times shown (tests)

var _kw := PackedByteArray()
var _pos := PackedVector2Array()
var _age := PackedFloat32Array()
var _count := 0


func _ready() -> void:
	z_index = 6
	_kw.resize(T.KEYWORD_MAX_ON_SCREEN)
	_pos.resize(T.KEYWORD_MAX_ON_SCREEN)
	_age.resize(T.KEYWORD_MAX_ON_SCREEN)


## Pop keyword `kw` at world point `at` (the oldest goes if the screen is full).
func pop(kw: String, at: Vector2) -> void:
	var k := ORDER.find(kw)
	if k < 0:
		return
	if _count >= T.KEYWORD_MAX_ON_SCREEN:
		_remove(0)
	_kw[_count] = k
	_pos[_count] = at + Vector2(0, -46)
	_age[_count] = 0.0
	_count += 1
	shown += 1
	counts[kw] = int(counts.get(kw, 0)) + 1


func active_count() -> int:
	return _count


func _process(delta: float) -> void:
	if _count == 0:
		return
	var i := 0
	while i < _count:
		_age[i] += delta
		if _age[i] >= LIFE:
			_remove(i)
			continue
		i += 1
	queue_redraw()


func _remove(i: int) -> void:
	_count -= 1
	for j in range(i, _count):
		_kw[j] = _kw[j + 1]
		_pos[j] = _pos[j + 1]
		_age[j] = _age[j + 1]


func _draw() -> void:
	for i in _count:
		var kw: String = ORDER[_kw[i]]
		var t := _age[i]
		var a := clampf(1.0 - (t - 0.4) / (LIFE - 0.4), 0.0, 1.0) if t > 0.4 else 1.0
		var col: Color = (T.KEYWORDS[kw] as Dictionary).color
		col.a = a
		var c := _pos[i] + Vector2(0, -RISE * t / LIFE)
		draw_circle(c, 13.0, Color(0, 0, 0, 0.55 * a))
		_glyph(kw, c, t, col)


## The symbol and its animation (the first 0.4 s), about 14 px across.
func _glyph(kw: String, c: Vector2, t: float, col: Color) -> void:
	var p := clampf(t / 0.4, 0.0, 1.0)
	match kw:
		"RAM":   # a chevron that punches forward and shakes
			var o := Vector2(lerpf(-6.0, 0.0, p) + (2.0 if int(t * 30.0) % 2 == 0 and p < 1.0 else 0.0), 0)
			for k in 2:
				var x := c.x + o.x - 3.0 + 6.0 * k
				draw_polyline(PackedVector2Array([Vector2(x - 3, c.y - 6), Vector2(x + 3, c.y), Vector2(x - 3, c.y + 6)]), col, 2.5)
		"DRIFT":   # a curved arrow sweeping round
			draw_arc(c, 8.0, -PI * 0.5, -PI * 0.5 + TAU * 0.75 * p, 16, col, 2.5)
			var tip := c + Vector2.RIGHT.rotated(-PI * 0.5 + TAU * 0.75 * p) * 8.0
			draw_circle(tip, 2.5, col)
		"BURST":   # three dots popping in turn
			for k in 3:
				if p >= k / 3.0:
					draw_circle(c + Vector2(-6.0 + 6.0 * k, 0), 2.5, col)
		"MARKED":   # a diamond shrinking onto the target, then pulsing
			var r := lerpf(14.0, 8.0, p) + (sin(t * TAU) * 1.0 if p >= 1.0 else 0.0)
			draw_polyline(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0), c + Vector2(0, -r)]), col, 2.0)
			draw_line(c + Vector2(-3, 0), c + Vector2(3, 0), col, 1.5)
			draw_line(c + Vector2(0, -3), c + Vector2(0, 3), col, 1.5)
		"STUNNED":   # a jittering zig-zag
			var j := Vector2(randf_range(-1.5, 1.5), 0) if p < 1.0 else Vector2.ZERO
			draw_polyline(PackedVector2Array([c + j + Vector2(-2, -8), c + j + Vector2(3, -2), c + j + Vector2(-3, 1), c + j + Vector2(2, 8)]), col, 2.5)
		"OVERLOAD":   # a gauge whose needle flicks past red
			draw_arc(c + Vector2(0, 4), 9.0, PI, TAU, 12, col, 2.0)
			var ang := lerpf(PI * 1.1, PI * 2.05, p)
			draw_line(c + Vector2(0, 4), c + Vector2(0, 4) + Vector2.RIGHT.rotated(ang) * 8.0, col, 2.0)
		"SLICK":   # a droplet sliding sideways over a skid line
			var dx := lerpf(-4.0, 4.0, p)
			draw_circle(c + Vector2(dx, 0), 4.0, col)
			draw_colored_polygon(PackedVector2Array([c + Vector2(dx - 3, -1), c + Vector2(dx, -8), c + Vector2(dx + 3, -1)]), col)
			draw_line(c + Vector2(-8, 7), c + Vector2(8, 7), col, 1.5)
		"BURNING":   # a flickering flame
			var h := 8.0 + (2.0 if int(t * 12.0) % 3 == 0 else 0.0)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-5, 5), c + Vector2(0, -h), c + Vector2(5, 5)]), col)
			draw_circle(c + Vector2(0, 3), 4.0, col)
		"CORRODED":   # a plate with a crack spreading
			draw_rect(Rect2(c - Vector2(7, 6), Vector2(14, 12)), col, false, 2.0)
			draw_polyline(PackedVector2Array([c + Vector2(-5, -5), c + Vector2(-1, -1).lerp(Vector2(-1, -1), p), c + Vector2(2, 2) * p, c + Vector2(5, 5) * p]), col, 1.5)
		"GOOPED":   # a wobbling blob with eyes
			var sq := 1.0 + sin(t * 18.0) * 0.15 * (1.0 - p * 0.5)
			draw_set_transform(c, 0.0, Vector2(sq, 1.0 / sq))
			draw_circle(Vector2.ZERO, 7.0, col)
			draw_circle(Vector2(-2.5, -1.5), 1.5, Color(0, 0, 0, col.a))
			draw_circle(Vector2(2.5, -1.5), 1.5, Color(0, 0, 0, col.a))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"TOXIC":   # a skull in a rising puff
			var up := Vector2(0, -3.0 * p)
			draw_circle(c + up, 6.0, Color(col, col.a * 0.5))
			draw_circle(c + up + Vector2(0, -1), 4.0, col)
			draw_circle(c + up + Vector2(-1.5, -1.5), 1.0, Color(0, 0, 0, col.a))
			draw_circle(c + up + Vector2(1.5, -1.5), 1.0, Color(0, 0, 0, col.a))
