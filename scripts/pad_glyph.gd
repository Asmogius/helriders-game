extends RefCounted
## Small PlayStation-style button badges, drawn with shapes (no font
## symbols): "square", "triangle", "circle", "cross", or a label such as
## "R1", "L1", "R2", "OPT". The HUD puts one on each button in controller mode.

const BG := Color(0.0, 0.0, 0.0, 0.75)
const COLORS := {
	"square": Color(0.95, 0.55, 0.8),
	"triangle": Color(0.4, 0.9, 0.7),
	"circle": Color(1.0, 0.4, 0.4),
	"cross": Color(0.5, 0.7, 1.0),
}


static func draw(ci: CanvasItem, at: Vector2, glyph: String, r := 13.0) -> void:
	ci.draw_circle(at, r, BG)
	ci.draw_arc(at, r, 0.0, TAU, 20, Color(1, 1, 1, 0.35), 1.5)
	var col: Color = COLORS.get(glyph, Color(0.95, 0.93, 0.88))
	var s := r * 0.48
	match glyph:
		"square":
			ci.draw_rect(Rect2(at - Vector2(s, s), Vector2(s, s) * 2.0), col, false, 2.0)
		"triangle":
			ci.draw_polyline(PackedVector2Array([at + Vector2(0, -s * 1.1), at + Vector2(s * 1.05, s * 0.75), at + Vector2(-s * 1.05, s * 0.75), at + Vector2(0, -s * 1.1)]), col, 2.0)
		"circle":
			ci.draw_arc(at, s, 0.0, TAU, 16, col, 2.0)
		"cross":
			ci.draw_line(at + Vector2(-s, -s), at + Vector2(s, s), col, 2.0)
			ci.draw_line(at + Vector2(s, -s), at + Vector2(-s, s), col, 2.0)
		_:
			var font := ThemeDB.fallback_font
			var fs := 13 if glyph.length() <= 2 else 10
			ci.draw_string(font, at + Vector2(-r, fs * 0.36), glyph, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, fs, col)
