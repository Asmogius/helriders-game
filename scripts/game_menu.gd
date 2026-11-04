extends Control
## The menu: pause in a job (RESUME, RESTART JOB, SETTINGS, DATABASE, QUIT
## GAME) or the garage's MENU button (SETTINGS, DATABASE, QUIT GAME, CLOSE).
## Agreed with the owner: there's no way back to the garage mid-job; a quit
## or a closed app drops you back into the same job at relaunch, the fight
## reset. It keeps running while the game is paused.

signal resumed
signal restart_requested
signal closed

const T := preload("res://scripts/tuning.gd")
const UI := preload("res://scripts/ui_theme.gd")
const Codex := preload("res://scripts/codex.gd")
const ProfileScript := preload("res://scripts/profile.gd")

var profile: ProfileScript
var in_job := false
var page := "main"            # main / settings / database
var category := "parts"       # Database tab
var restart_armed := false    # RESTART JOB needs a second tap

var _panel: PanelContainer
var _body: VBoxContainer


func setup(p: ProfileScript, job: bool) -> void:
	profile = p
	in_job = job


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UI.make()
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UI.box(UI.PANEL, UI.PANEL_EDGE, 2))
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -520.0
	_panel.offset_right = 520.0
	_panel.offset_top = -320.0
	_panel.offset_bottom = 320.0
	add_child(_panel)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 12)
	_panel.add_child(_body)
	show_page("main")


## The phone's back button: up a page, or close.
func back() -> void:
	if page != "main":
		show_page("main")
	elif in_job:
		resume()
	else:
		close()


func resume() -> void:
	resumed.emit()
	queue_free()


func close() -> void:
	closed.emit()
	queue_free()


func restart() -> bool:
	if not in_job:
		return false
	if not restart_armed:
		restart_armed = true
		show_page("main")
		return false
	restart_requested.emit()
	return true


func quit_game() -> void:
	get_tree().quit()


func show_page(which: String) -> void:
	page = which
	if _body == null:
		return   # not on screen yet; _ready shows the main page
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	match which:
		"main":
			_main_page()
		"settings":
			_settings_page()
		"database":
			_database_page()


func _title(text: String) -> void:
	var l := UI.label(text, 30, T.COL_CYAN)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.add_child(l)


func _button(text: String, call: Callable, accent := Color.TRANSPARENT) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 62)
	if accent != Color.TRANSPARENT:
		UI.accent(b, accent)
	b.pressed.connect(call)
	_body.add_child(b)
	return b


func _main_page() -> void:
	_title("PAUSED" if in_job else "MENU")
	if in_job:
		_button("RESUME", resume, T.COL_CYAN)
		_button("TAP AGAIN TO RESTART THE JOB" if restart_armed else "RESTART JOB", restart, T.COL_ORANGE if restart_armed else Color.TRANSPARENT)
	_button("SETTINGS", show_page.bind("settings"))
	_button("DATABASE", show_page.bind("database"))
	_button("QUIT GAME", quit_game)
	if not in_job:
		_button("CLOSE", close, T.COL_CYAN)
	var note := UI.label("Quitting or closing the app mid-job puts you back into the same job next time, the fight reset." if in_job else "", 18, UI.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD
	_body.add_child(note)


# --- Settings ---

func _settings_page() -> void:
	_title("SETTINGS")
	_body.add_child(UI.label("QUALITY", 20, UI.TEXT_DIM))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_body.add_child(row)
	for q: String in T.QUALITY_ORDER:
		var b := Button.new()
		b.text = q.to_upper()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 58)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if str(profile.settings.get("quality", "")) == q:
			UI.accent(b, T.COL_ORANGE)
		b.pressed.connect(set_quality.bind(q))
		row.add_child(b)
	_button("SCREEN SHAKE: %s" % ("ON" if bool(profile.settings.get("shake", true)) else "OFF"), toggle_shake)
	for key: String in ["music", "effects"]:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 14)
		_body.add_child(line)
		var l := UI.label(key.to_upper(), 22)
		l.custom_minimum_size = Vector2(150, 0)
		line.add_child(l)
		var slider := HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.05
		slider.value = float(profile.settings.get(key, 0.8))
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.custom_minimum_size = Vector2(0, 48)
		slider.value_changed.connect(func(v: float) -> void: profile.set_setting(key, v))
		line.add_child(slider)
	var note := UI.label("Lower quality caps the frame rate and draws fewer effects. New settings apply to the next fight; the frame cap applies now. Sound comes in a later build.", 18, UI.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD
	_body.add_child(note)
	_button("BACK", show_page.bind("main"), T.COL_CYAN)


func set_quality(q: String) -> void:
	profile.set_setting("quality", q)
	show_page("settings")


func toggle_shake() -> void:
	profile.set_setting("shake", not bool(profile.settings.get("shake", true)))
	show_page("settings")


# --- Database ---

func _database_page() -> void:
	var found := 0
	var rows := Codex.entries(category)
	for e: Array in rows:
		if profile.is_discovered(category, str(e[0])):
			found += 1
	_title("DATABASE   -   %s  %d / %d" % [str(Codex.CATEGORY_NAMES[category]), found, rows.size()])
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	_body.add_child(tabs)
	for cat: String in Codex.CATEGORIES:
		var b := Button.new()
		b.text = str(Codex.CATEGORY_NAMES[cat])
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 52)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if cat == category:
			UI.accent(b, T.COL_ORANGE)
		b.pressed.connect(show_category.bind(cat))
		tabs.add_child(b)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 390)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.scroll_deadzone = 14
	_body.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)
	for e: Array in rows:
		var known := profile.is_discovered(category, str(e[0]))
		var name := UI.label(str(e[1]) if known else "? ? ? ? ?", 22, UI.TEXT if known else UI.TEXT_DIM)
		list.add_child(name)
		var text := UI.label(str(e[2]) if known else "Not met yet.", 18, UI.TEXT_DIM)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD
		text.custom_minimum_size = Vector2(980, 0)
		list.add_child(text)
	_button("BACK", show_page.bind("main"), T.COL_CYAN)


func show_category(cat: String) -> void:
	category = cat
	show_page("database")
