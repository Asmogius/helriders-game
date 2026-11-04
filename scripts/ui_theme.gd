extends RefCounted
## Shared look for menu screens (Garage and the other stations): dark steel
## panels, phone-sized text, cyan/orange accents. Apply with `control.theme`.

const T := preload("res://scripts/tuning.gd")

const TEXT := Color(0.88, 0.86, 0.82)
const TEXT_DIM := Color(0.6, 0.59, 0.56)
const PANEL := Color(0.085, 0.085, 0.095, 0.97)
const PANEL_EDGE := Color(0.26, 0.27, 0.29)
const GOOD := Color(0.45, 0.85, 0.5)
const BAD := Color(0.95, 0.38, 0.3)


static func make() -> Theme:
	var th := Theme.new()
	th.default_font_size = 22
	th.set_color("font_color", "Label", TEXT)
	th.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.8))
	th.set_constant("outline_size", "Label", 4)

	th.set_stylebox("normal", "Button", skin("button_normal", box(Color(0.13, 0.13, 0.145), PANEL_EDGE, 2)))
	th.set_stylebox("hover", "Button", skin("button_hover", box(Color(0.16, 0.16, 0.175), PANEL_EDGE, 2)))
	th.set_stylebox("pressed", "Button", skin("button_pressed", box(Color(0.22, 0.14, 0.08), T.COL_ORANGE, 2)))
	th.set_stylebox("disabled", "Button", skin("button_disabled", box(Color(0.1, 0.1, 0.105), Color(0.18, 0.18, 0.19), 2)))
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_color("font_color", "Button", TEXT)
	th.set_color("font_hover_color", "Button", Color.WHITE)
	th.set_color("font_pressed_color", "Button", Color.WHITE)
	th.set_color("font_disabled_color", "Button", Color(0.42, 0.42, 0.42))

	th.set_stylebox("panel", "Panel", skin("panel", box(PANEL, PANEL_EDGE, 2)))
	th.set_stylebox("panel", "PanelContainer", skin("panel", box(PANEL, PANEL_EDGE, 2)))
	return th


# --- Panels and buttons (P7 / V6.2) --------------------------------------------
# Riveted steel 9-slice textures from tools/art/ui_panels.py. Missing art keeps
# the flat box (fallback rule).
const NINE_MARGIN := 12


## A 9-slice StyleBoxTexture for art/ui/<name>.png, or `fallback` if it's missing.
static func skin(name: String, fallback: StyleBox) -> StyleBox:
	var path := "res://art/ui/%s.png" % name
	if not ResourceLoader.exists(path):
		return fallback
	var sb := StyleBoxTexture.new()
	sb.texture = load(path)
	sb.texture_margin_left = NINE_MARGIN
	sb.texture_margin_right = NINE_MARGIN
	sb.texture_margin_top = NINE_MARGIN
	sb.texture_margin_bottom = NINE_MARGIN
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT   # grain and edge chips repeat, never smear
	sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	sb.content_margin_left = fallback.content_margin_left
	sb.content_margin_right = fallback.content_margin_right
	sb.content_margin_top = fallback.content_margin_top
	sb.content_margin_bottom = fallback.content_margin_bottom
	return sb


static func box(fill: Color, border: Color, width: int) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = fill
	b.border_color = border
	b.set_border_width_all(width)
	b.content_margin_left = 12
	b.content_margin_right = 12
	b.content_margin_top = 6
	b.content_margin_bottom = 6
	return b


## An accent button (Deploy): orange border and bold text.
static func accent(button: Button, color: Color) -> void:
	button.add_theme_stylebox_override("normal", box(Color(0.16, 0.11, 0.07), color, 3))
	button.add_theme_stylebox_override("hover", box(Color(0.2, 0.13, 0.08), color, 3))
	button.add_theme_stylebox_override("pressed", box(Color(0.32, 0.18, 0.08), color, 3))
	button.add_theme_color_override("font_color", color.lightened(0.3))


static func label(text: String, size := 22, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## Color of a lit skull: orange for most jobs, red for the top two levels.
static func skull_color(skulls: int) -> Color:
	return BAD if skulls >= 5 else T.COL_ORANGE


## A small skull icon (job difficulty). `lit` false draws an empty outline.
static func draw_skull(canvas: CanvasItem, center: Vector2, r: float, color: Color, lit: bool) -> void:
	var cranium := center + Vector2(0.0, -r * 0.15)
	var jaw := Rect2(center + Vector2(-r * 0.5, r * 0.35), Vector2(r, r * 0.55))
	if lit:
		canvas.draw_circle(cranium, r * 0.8, color)
		canvas.draw_rect(jaw, color)
		var hole := Color(0.08, 0.08, 0.09)
		canvas.draw_circle(cranium + Vector2(-r * 0.33, r * 0.05), r * 0.22, hole)
		canvas.draw_circle(cranium + Vector2(r * 0.33, r * 0.05), r * 0.22, hole)
		canvas.draw_rect(Rect2(jaw.position + Vector2(r * 0.3, r * 0.25), Vector2(r * 0.12, r * 0.3)), hole)
		canvas.draw_rect(Rect2(jaw.position + Vector2(r * 0.58, r * 0.25), Vector2(r * 0.12, r * 0.3)), hole)
	else:
		canvas.draw_arc(cranium, r * 0.8, 0.0, TAU, 20, PANEL_EDGE, 2.0)
		canvas.draw_rect(jaw, PANEL_EDGE, false, 2.0)


# --- Rarity helpers (P0 / VISUAL_PLAN V1.1) ------------------------------------
# Every screen asks these for rarity colour; nothing else defines one.

const RarityFrame := preload("res://scripts/rarity_frame.gd")


## The colour of a rarity name ("Common" .. "Mythic"); white if unknown.
static func rarity_color(r: String) -> Color:
	return T.RARITY_COLORS.get(r, Color.WHITE)


## 1 (Common) .. 6 (Mythic); 0 if unknown. Drives the pip row.
static func rarity_tier(r: String) -> int:
	return T.RARITY_ORDER.find(r) + 1


## Adds (or updates) a rarity frame on `control`: border plus top strip and a
## pip row. One child drawer, ignores the mouse, draws only when changed.
static func rarity_frame(control: Control, r: String) -> Control:
	var f: Control = control.get_node_or_null("RarityFrame")
	if f == null:
		f = RarityFrame.new()
		f.name = "RarityFrame"
		control.add_child(f)
	f.set("rarity", r)
	return f


## The rarity a perk tier shows as ("minor", "major", "signature"); Common otherwise.
static func perk_rarity(tier: String) -> String:
	return str(T.PERK_TIER_RARITY.get(tier, "Common"))


## BBCode for a RichTextLabel: the name in its rarity colour.
static func rarity_text(text: String, r: String) -> String:
	return "[color=#%s]%s[/color]" % [rarity_color(r).to_html(false), text]
