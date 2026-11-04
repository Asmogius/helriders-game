extends Control
## One shared rarity frame drawer (VISUAL_PLAN P0 + V1.2). Fills its parent and
## draws a border, a top strip and a pip row (1-6 pips) so the tier reads
## without colour. Tiers look different, not just tinted:
##   Common grey frame; Uncommon green; Rare blue plus a soft inner glow;
##   Epic purple plus a slow shimmer sweep; Legendary gold, shimmer and a
##   pulsing corner glint; Mythic a colour-cycling frame with sparks.
## Common to Rare are static (draw once). Epic and up animate only while
## visible, and not at all on the Low quality preset (`animate = false`).
## Add it with `UI.rarity_frame(control, rarity)`.

const T := preload("res://scripts/tuning.gd")

const BORDER := 2.0
const STRIP := 4.0
const PIP := 5.0
const PIP_GAP := 3.0
const SHIMMER_PERIOD := 2.6   # seconds per sweep
const SPARKS := 5

var rarity := "Common":
	set(v):
		if v != rarity:
			rarity = v
			_update_process()
			queue_redraw()
var animate := true:
	set(v):
		animate = v
		_update_process()
		queue_redraw()
var t := 0.0   # animation clock (tests and captures may set it)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)
	visibility_changed.connect(_update_process)
	var profile: Node = get_node_or_null("/root/Profile")
	if profile != null:
		# Re-read the preset whenever settings change, so toggling Low/High
		# in the options takes effect on frames already on screen.
		profile.changed.connect(_read_quality.bind(profile))
		_read_quality(profile)
	_update_process()


## Animation follows the quality preset: off on Low, on otherwise.
func _read_quality(profile: Node) -> void:
	var low := str(profile.get("settings").get("quality", "High")) == "Low"
	if animate == low:
		animate = not low


func tier() -> int:
	return T.RARITY_ORDER.find(rarity) + 1


## True for the tiers that move (Epic and up) when animation is on.
func animated() -> bool:
	return animate and tier() >= 4


func _update_process() -> void:
	set_process(animated() and is_visible_in_tree())


func color() -> Color:
	var c: Color = T.RARITY_COLORS.get(rarity, Color.WHITE)
	if rarity == "Mythic" and animate:
		c = Color.from_hsv(fposmod(c.h + 0.08 * sin(t * 1.3), 1.0), c.s, c.v)
	return c


func _process(delta: float) -> void:
	t += delta
	queue_redraw()


func _draw() -> void:
	var n := tier()
	var c := color()
	if n >= 3:   # Rare+: soft inner glow
		for i in 4:
			draw_rect(Rect2(Vector2.ONE * (BORDER + i * 2.0), size - Vector2.ONE * (BORDER + i * 2.0) * 2.0),
				Color(c, 0.16 - i * 0.035), false, 2.0)
	draw_rect(Rect2(Vector2.ZERO, size).grow(-BORDER * 0.5), c, false, BORDER)
	draw_rect(Rect2(0, 0, size.x, STRIP), c)
	if n >= 4:   # Epic+: a shimmer band sweeps along the strip and border
		var k := fposmod(t / SHIMMER_PERIOD, 1.0) if animate else 0.3
		var x := lerpf(-40.0, size.x + 40.0, k)
		var hi := c.lightened(0.6)
		var box := Rect2(Vector2.ZERO, size)
		draw_rect(Rect2(x - 14.0, 0, 28.0, STRIP).intersection(box), Color(hi, 0.8))
		draw_rect(Rect2(x - 8.0, size.y - BORDER, 16.0, BORDER).intersection(box), Color(hi, 0.6))
	if n >= 5:   # Legendary+: pulsing corner glint
		var p := 0.55 + 0.45 * sin(t * 3.0) if animate else 1.0
		var g := Vector2(BORDER + 1.0, BORDER + 1.0)
		var r := 4.0 + 3.0 * p
		var w := Color(1, 1, 0.92, 0.9 * p)
		draw_line(g - Vector2(r, 0), g + Vector2(r, 0), w, 2.0)
		draw_line(g - Vector2(0, r), g + Vector2(0, r), w, 2.0)
		draw_circle(g, 2.0 + p, Color(c.lightened(0.5), p))
	if n >= 6:   # Mythic: sparks running round the frame
		var per := 2.0 * (size.x + size.y)
		for i in SPARKS:
			var d := fposmod(t * 90.0 + per * i / SPARKS, per)
			draw_rect(Rect2(_edge_point(d) - Vector2(1.5, 1.5), Vector2(3, 3)), Color(1, 0.95, 0.8, 0.9))
	var px := size.x - BORDER - 4.0 - n * (PIP + PIP_GAP) + PIP_GAP
	for i in n:
		draw_rect(Rect2(px + i * (PIP + PIP_GAP), STRIP + 3.0, PIP, PIP), c)


## A point `d` pixels clockwise round the frame's edge from the top-left.
func _edge_point(d: float) -> Vector2:
	if d < size.x:
		return Vector2(d, 1.0)
	d -= size.x
	if d < size.y:
		return Vector2(size.x - 1.0, d)
	d -= size.y
	if d < size.x:
		return Vector2(size.x - d, size.y - 1.0)
	return Vector2(1.0, size.y - (d - size.x))
