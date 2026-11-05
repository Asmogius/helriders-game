extends Control
## Title screen (Quickplay QP4): CAMPAIGN goes to the garage, QUICKPLAY opens
## the Quickplay hub. A job quit mid-fight skips the title so the garage can
## drop you straight back into it (Profile.resume_job()).

const UI := preload("res://scripts/ui_theme.gd")
const GARAGE_SCENE := "res://scenes/garage.tscn"
const HUB_SCENE := "res://scenes/quickplay_hub.tscn"

var auto_resume := true    # tests switch it off
var campaign_button: Button
var quickplay_button: Button
var quit_button: Button


func _ready() -> void:
	var profile := get_node_or_null("/root/Profile")
	if auto_resume and profile != null and profile.resume_job():
		get_tree().change_scene_to_file.call_deferred(GARAGE_SCENE)
		return
	var music := get_node_or_null("/root/MusicManager")
	if music != null:
		music.play_garage()
	add_to_group("pad_modal")
	theme = UI.make()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var panel := build_panel(self, "HELRIDERS", "Scrap, rigs and the dead.")
	campaign_button = add_button(panel, "CAMPAIGN", true, open_campaign)
	quickplay_button = add_button(panel, "QUICKPLAY", false, open_quickplay)
	quit_button = add_button(panel, "QUIT", false, func() -> void: get_tree().quit())
	campaign_button.grab_focus.call_deferred()


func open_campaign() -> void:
	get_tree().change_scene_to_file(GARAGE_SCENE)


func open_quickplay() -> void:
	get_tree().change_scene_to_file(HUB_SCENE)


## Shared chrome for the title and the hub: deep backdrop, a centred charcoal
## panel with a gold hairline, a Black Ops One title and an Inter subtitle.
## Returns the VBox that buttons go into.
static func build_panel(root: Control, title: String, subtitle: String) -> VBoxContainer:
	var bg := ColorRect.new()
	bg.color = Color(UI.PANEL_DEEP, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	var sb := UI.box(UI.PANEL, UI.PANEL_EDGE, 2)
	sb.content_margin_left = 48
	sb.content_margin_right = 48
	sb.content_margin_top = 40
	sb.content_margin_bottom = 40
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(520, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(UI.GAP))
	panel.add_child(box)
	var t := UI.label(title, 56, UI.ACCENT)
	t.name = "Title"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	var s := UI.label(subtitle, 20, UI.TEXT_DIM)
	s.name = "Subtitle"
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(s)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, UI.GRID * 2)
	box.add_child(gap)
	return box


static func add_button(box: VBoxContainer, text: String, primary: bool, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.name = text.replace(" ", "")
	b.custom_minimum_size = Vector2(0, UI.MIN_TOUCH)
	b.add_theme_font_override("font", UI.font())
	b.add_theme_font_size_override("font_size", 28)
	if primary:
		UI.primary(b)
		b.add_theme_color_override("font_focus_color", UI.PANEL_DEEP)   # stay dark on gold when focused
		b.add_theme_color_override("font_hover_pressed_color", UI.PANEL_DEEP)
	else:
		UI.ghost(b)
	b.pressed.connect(cb)
	box.add_child(b)
	return b
