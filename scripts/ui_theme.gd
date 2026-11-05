extends RefCounted
## Shared look for menu screens (Garage and the other stations): charcoal
## panels, phone-sized text, gold accent (Ebbtide). Apply with `control.theme`.

const T := preload("res://scripts/tuning.gd")

# Aliases into tuning.gd COL_UI_* so every screen reads one palette.
const TEXT := T.COL_UI_TEXT
const TEXT_DIM := T.COL_UI_TEXT_DIM
const PANEL := T.COL_UI_PANEL
const PANEL_EDGE := T.COL_UI_BORDER
const GOOD := T.COL_UI_OK_TEXT
const BAD := T.COL_UI_DANGER_TEXT
const ACCENT := T.COL_UI_ACCENT
const ACCENT_HOVER := T.COL_UI_ACCENT_HOVER
const PANEL_ALT := T.COL_UI_PANEL_ALT
const PANEL_DEEP := T.COL_UI_DEEP
const HEADER := T.COL_UI_HEADER
const DANGER := T.COL_UI_DANGER
const OK := T.COL_UI_OK


# --- Fonts (P7 / V6.1) -----------------------------------------------------------
# Black Ops One (SIL OFL 1.1, see docs/ART_CREDITS.md), the owner's pick for the
# whole interface. If the file is missing the engine font stays (fallback rule).
const FONT_PATH := "res://art/ui/fonts/BlackOpsOne-Regular.ttf"


## The interface font, or the engine default if the art file is missing.
static func font() -> Font:
	if ResourceLoader.exists(FONT_PATH):
		return load(FONT_PATH)
	return ThemeDB.fallback_font


## Makes every Control and every custom _draw that asks ThemeDB.fallback_font
## use the interface font. Runs once, from the first make() (garage, menus) or
## the fight HUD's _ready, whichever comes first; later calls do nothing.
static func apply_fonts() -> void:
	var f := font()
	if ThemeDB.fallback_font == f:
		return   # already applied
	ThemeDB.fallback_font = f
	var project := ThemeDB.get_project_theme()
	if project != null:
		project.default_font = f
	ThemeDB.get_default_theme().default_font = f


## Font size that fits `text` in `width` px: `size`, shrunk down to `min_size`.
## Black Ops One is wide, so fixed-width HUD and card labels use this.
static func fit_size(f: Font, text: String, width: float, size: int, min_size := 10) -> int:
	var s := size
	while s > min_size and f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x > width:
		s -= 1
	return s


## draw_string that never spills past `width` (shrinks the font instead).
static func draw_fit(canvas: CanvasItem, f: Font, at: Vector2, text: String, align: HorizontalAlignment, width: float, size: int, color: Color) -> void:
	canvas.draw_string(f, at, text, align, width, fit_size(f, text, width, size), color)


# --- Icons (P7 / V6.3) ------------------------------------------------------------
# 16 px white glyphs from tools/art/icons.py, tinted when drawn.
const ArtAtlas := preload("res://scripts/art_atlas.gd")
const STATUS_ICONS := ["shock", "fire", "acid", "toxic", "slime", "goop"]   # T.STATUS_NAMES order


## The shared icon atlas (art_atlas.gd caches one instance per tree, so
## icons.json is read once). Drawers keep it in a
## member var; `ok()` is false when the art is missing (draw the old way).
static func icons() -> RefCounted:
	return ArtAtlas.load_atlas("res://art/ui/icons")


static func make() -> Theme:
	apply_fonts()
	var th := Theme.new()
	th.default_font = font()
	th.default_font_size = 22
	th.set_color("font_color", "Label", TEXT)
	th.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.8))
	th.set_constant("outline_size", "Label", 4)

	th.set_stylebox("normal", "Button", skin("button_normal", box(PANEL_ALT, PANEL_EDGE, 2)))
	th.set_stylebox("hover", "Button", skin("button_hover", box(Color(HEADER.r, HEADER.g, HEADER.b, 0.95), ACCENT, 2)))
	th.set_stylebox("pressed", "Button", skin("button_pressed", box(HEADER, ACCENT, 2)))
	th.set_stylebox("disabled", "Button", skin("button_disabled", box(PANEL_DEEP, Color(PANEL_EDGE, 0.5), 2)))
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


## Gold outline accent (tabs, selected rows). Prefer primary()/ghost() for actions.
static func accent(button: Button, color: Color = ACCENT) -> void:
	button.add_theme_stylebox_override("normal", box(HEADER, color, 2))
	button.add_theme_stylebox_override("hover", box(Color(HEADER.r * 1.15, HEADER.g * 1.15, HEADER.b * 1.1, 1.0), ACCENT_HOVER if color == ACCENT else color.lightened(0.1), 2))
	button.add_theme_stylebox_override("pressed", box(Color(0.20, 0.16, 0.10), color, 2))
	button.add_theme_color_override("font_color", color.lightened(0.2))


## Primary action (DEPLOY / LEVEL UP / EQUIP / TAKE): filled gold, dark text.
static func primary(button: Button) -> void:
	var fill := ACCENT
	var hover := ACCENT_HOVER
	var pressed := Color(0.75, 0.58, 0.18)
	var ink := PANEL_DEEP   # dark text on gold
	button.add_theme_stylebox_override("normal", box(fill, fill, 0))
	button.add_theme_stylebox_override("hover", box(hover, hover, 0))
	button.add_theme_stylebox_override("pressed", box(pressed, pressed, 0))
	button.add_theme_color_override("font_color", ink)
	button.add_theme_color_override("font_hover_color", ink)
	button.add_theme_color_override("font_pressed_color", ink)


## Secondary / ghost action: charcoal fill, gold hairline, light text.
static func ghost(button: Button) -> void:
	button.add_theme_stylebox_override("normal", box(PANEL_ALT, PANEL_EDGE, 2))
	button.add_theme_stylebox_override("hover", box(HEADER, ACCENT, 2))
	button.add_theme_stylebox_override("pressed", box(PANEL_DEEP, ACCENT, 2))
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_hover_color", ACCENT_HOVER)


static func label(text: String, size := 22, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## Color of a lit skull: orange for most jobs, red for the top two levels.
static func skull_color(skulls: int) -> Color:
	return BAD if skulls >= 5 else ACCENT


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


# --- Shared layout grid ---------------------------------------------------
# One grid for every screen: outer margin, gap between cards and panels, a base
# unit all sizes snap to, the bottom action bar and the phone touch minimum.

const MARGIN := 24.0     # outer screen margin, inside the display safe area
const GAP := 12.0        # between cards and panels
const GRID := 8.0        # base unit; sizes are multiples of it
const BAR_H := 72.0      # bottom action bar height (the garage footer)
const MIN_TOUCH := 64.0  # minimum button height on phones


## The viewport's visible rect inset by the display safe area (notches, rounded
## corners, gesture bars), mapped from screen pixels to viewport coordinates so
## it is right under any stretch mode, then inset by MARGIN.
static func safe_rect(node: Control) -> Rect2:
	var vp := node.get_viewport()
	if vp == null:
		return Rect2()
	var full: Rect2 = vp.get_visible_rect()
	var r := full
	if vp == node.get_tree().root and DisplayServer.get_name() != "headless":
		var safe := Rect2(DisplayServer.get_display_safe_area())
		if safe.has_area():
			var win_pos := Vector2(DisplayServer.window_get_position())
			safe.position -= win_pos
			# Window pixels -> viewport (canvas) coordinates.
			var to_vp: Transform2D = vp.get_final_transform().affine_inverse()
			var mapped := Rect2(to_vp * safe.position, Vector2.ZERO).expand(to_vp * safe.end)
			r = full.intersection(mapped)
			if not r.has_area():
				r = full
	r = r.grow(-MARGIN)
	if r.size.x < 0.0 or r.size.y < 0.0:
		r = Rect2(full.get_center(), Vector2.ZERO)
	return r


## Rounds a length to the base GRID unit.
static func snap(v: float) -> float:
	return roundf(v / GRID) * GRID


## One Theme from make(), built on first use and reused (bottom bars and any
## other helper that only needs the look). Kept as meta on the SceneTree root,
## not in a static var (which would keep this script alive past exit), so it is
## freed with the tree. Without a tree it falls back to a fresh make().
const THEME_META := &"ui_shared_theme"


static func shared_theme() -> Theme:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return make()
	if not tree.root.has_meta(THEME_META):
		tree.root.set_meta(THEME_META, make())
	return tree.root.get_meta(THEME_META)


## A themed action bar anchored to the bottom of safe_rect: BAR_H tall, GAP
## between buttons, every Button child at least MIN_TOUCH tall. Assumes the
## parent covers the viewport (a full-screen root Control), like every screen.
static func bottom_bar(parent: Control) -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.name = "BottomBar"
	bar.theme = shared_theme()
	bar.add_theme_constant_override("separation", int(GAP))
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.custom_minimum_size = Vector2(0.0, BAR_H)
	bar.child_entered_tree.connect(func(c: Node) -> void:
		if c is Button:
			var b := c as Button
			b.custom_minimum_size.y = maxf(b.custom_minimum_size.y, MIN_TOUCH)
			b.size_flags_vertical = Control.SIZE_SHRINK_CENTER)
	parent.add_child(bar)
	_place_bottom_bar(bar, parent)
	if not parent.is_inside_tree():
		parent.ready.connect(_place_bottom_bar.bind(bar, parent), CONNECT_ONE_SHOT)
	parent.resized.connect(_place_bottom_bar.bind(bar, parent))
	return bar


static func _place_bottom_bar(bar: HBoxContainer, parent: Control) -> void:
	if not is_instance_valid(bar) or not parent.is_inside_tree():
		return
	var r := safe_rect(parent)
	var vp_size: Vector2 = parent.get_viewport().get_visible_rect().size
	bar.anchor_left = 0.0
	bar.anchor_right = 1.0
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_left = r.position.x
	bar.offset_right = r.end.x - vp_size.x
	bar.offset_bottom = r.end.y - vp_size.y
	bar.offset_top = bar.offset_bottom - BAR_H
