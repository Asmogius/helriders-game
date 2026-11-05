extends Control
## The menu: pause in a job (RESUME, RESTART JOB, SETTINGS, DATABASE, QUIT
## GAME) or the garage's MENU button (SETTINGS, DATABASE, QUIT GAME, CLOSE).
## Agreed with the owner: there's no way back to the garage mid-job; a quit
## or a closed app drops you back into the same job at relaunch, the fight
## reset. It keeps running while the game is paused.

signal resumed
signal restart_requested
signal closed
signal tutorial_requested
signal leave_requested

const T := preload("res://scripts/tuning.gd")
const UI := preload("res://scripts/ui_theme.gd")
const Parts := preload("res://scripts/parts.gd")
const Codex := preload("res://scripts/codex.gd")
const ProfileScript := preload("res://scripts/profile.gd")
const PadScript := preload("res://scripts/pad.gd")

var profile: ProfileScript
var in_job := false
var in_tutorial := false     # the Training Run: LEAVE TUTORIAL instead of a resume-on-relaunch job
var page := "main"            # main / settings / database
var category := "parts"       # Database tab
var restart_armed := false    # RESTART JOB needs a second tap
var _focus_action := ""       # Controller page: the row last picked

var _panel: PanelContainer
var _body: VBoxContainer


func setup(p: ProfileScript, job: bool, tutorial := false) -> void:
	profile = p
	in_job = job
	in_tutorial = tutorial


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("pad_modal")
	set_meta("pad_close", back)
	z_index = 10   # above the garage's rig preview (its sprites draw at z 1-3)
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


## Esc on a PC works like the phone's back button (the menu runs while paused).
## During a rebind, Esc cancels the capture instead of leaving the page.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo and (event as InputEventKey).keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		var pad := _pad()
		if pad != null and (str(pad.get("capturing")) != "" or str(pad.get("capturing_kbm")) != ""):
			pad.call("cancel_capture")
			pad.call("cancel_kbm_capture")
			show_page(page)
			return
		back()


## The phone's back button: up a page, or close.
func back() -> void:
	var pad := _pad()
	if pad != null:
		pad.call("cancel_capture")
		pad.call("cancel_kbm_capture")
	if page == "controller" or page == "kbm":
		show_page("settings")
	elif page != "main":
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
	var pad := _pad()
	if pad != null:
		if which != "controller" and str(pad.get("capturing")) != "":
			pad.call("cancel_capture")
		if which != "kbm" and str(pad.get("capturing_kbm")) != "":
			pad.call("cancel_kbm_capture")
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
		"controller":
			_controller_page()
		"kbm":
			_kbm_page()


func _title(text: String) -> void:
	var l := UI.label(text, 30, T.COL_UI_ACCENT)
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
		_button("RESUME", resume, T.COL_UI_ACCENT)
		_button(PadScript.hint("TAP AGAIN TO RESTART THE JOB", "PRESS AGAIN TO RESTART THE JOB") if restart_armed else "RESTART JOB", restart, T.COL_UI_ACCENT if restart_armed else Color.TRANSPARENT)
	if in_tutorial:
		_button("LEAVE TUTORIAL", func() -> void: leave_requested.emit())
	_button("SETTINGS", show_page.bind("settings"))
	_button("DATABASE", show_page.bind("database"))
	if not in_job:
		_button("TUTORIAL", func() -> void: tutorial_requested.emit())
	_button("QUIT GAME", quit_game)
	if not in_job:
		_button("CLOSE", close, T.COL_UI_ACCENT)
	var note_text := ""
	if in_tutorial:
		note_text = "The Training Run uses a loaner rig and crew. Nothing here counts and nothing can be lost."
	elif in_job:
		note_text = "Quitting or closing the app mid-job puts you back into the same job next time, the fight reset."
	else:
		note_text = "TUTORIAL: a guided Training Run on a loaner rig, then a tour of the garage. Costs no day; nothing is kept."
	var note := UI.label(note_text, 18, UI.TEXT_DIM)
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
			UI.accent(b, T.COL_UI_ACCENT)
		b.pressed.connect(set_quality.bind(q))
		row.add_child(b)
	var shake := _button("SCREEN SHAKE: %s" % ("ON" if bool(profile.settings.get("shake", true)) else "OFF"), toggle_shake)
	if ProfileScript.is_desktop():
		# On a PC: windowed or fullscreen, side by side with the shake toggle.
		var pair := HBoxContainer.new()
		pair.add_theme_constant_override("separation", 8)
		_body.add_child(pair)
		_body.move_child(pair, shake.get_index())
		shake.reparent(pair)
		shake.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var display := _button("DISPLAY: %s" % ("FULLSCREEN" if bool(profile.settings.get("fullscreen", false)) else "WINDOWED"), toggle_fullscreen)
		display.reparent(pair)
		display.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	_button("CONTROLLER BUTTONS", show_page.bind("controller"))
	_button("KEYBOARD & MOUSE", show_page.bind("kbm"))
	var note := UI.label("Lower quality caps the frame rate and draws fewer effects. New settings apply to the next fight; the frame cap applies now.", 18, UI.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD
	_body.add_child(note)
	_button("BACK", show_page.bind("main"), T.COL_UI_ACCENT)


func set_quality(q: String) -> void:
	profile.set_setting("quality", q)
	show_page("settings")


func toggle_fullscreen() -> void:
	profile.set_setting("fullscreen", not bool(profile.settings.get("fullscreen", false)))
	show_page("settings")


func toggle_shake() -> void:
	profile.set_setting("shake", not bool(profile.settings.get("shake", true)))
	show_page("settings")


# --- Controller buttons (pad.gd) ---

func _pad() -> Node:
	return get_node_or_null("/root/Pad")


func _controller_page() -> void:
	_title("CONTROLLER BUTTONS")
	var pad := _pad()
	if pad == null:
		return
	if not pad.is_connected("map_changed", _on_map_changed):
		pad.connect("map_changed", _on_map_changed)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 8)
	_body.add_child(grid)
	var waiting := str(pad.get("capturing"))
	for action: String in PadScript.ACTIONS:
		var l := UI.label(str(PadScript.ACTION_NAMES[action]), 20)
		l.custom_minimum_size = Vector2(170, 0)
		grid.add_child(l)
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(300, 54)
		b.text = ("PRESS A BUTTON... (Esc cancels)" if waiting == action else str(pad.call("button_name", action)))
		if waiting == action:
			UI.accent(b, T.COL_UI_ACCENT)
		b.pressed.connect(rebind.bind(action))
		grid.add_child(b)
		if action == _focus_action and bool(pad.get("active")):
			b.focus_mode = Control.FOCUS_ALL   # keep the pad's place on the row just rebound
			b.grab_focus.call_deferred()
	var swapped := bool(pad.call("sticks_swapped"))
	_button("STICKS: %s" % ("LEFT AIMS, RIGHT DRIVES" if swapped else "LEFT DRIVES, RIGHT AIMS"), func() -> void:
		pad.call("set_sticks_swapped", not swapped))
	_button("RESET TO DEFAULT", func() -> void: pad.call("reset_map"))
	var note := UI.label("Pick an action, then press the pad button you want for it (L2 and R2 work too). Esc cancels a rebind without leaving this page. A button already in use swaps over. Menus always use the D-pad, Cross, Circle and L1 / R1; Cross always picks in the crew wheel.", 18, UI.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD
	_body.add_child(note)
	_button("BACK", show_page.bind("settings"), T.COL_UI_ACCENT)


## Wait for the next pad press for `action`.
func rebind(action: String) -> void:
	var pad := _pad()
	if pad == null:
		return
	_focus_action = action
	pad.call("start_capture", action)
	show_page("controller")


func _on_map_changed() -> void:
	if page in ["controller", "kbm"] and is_inside_tree():
		show_page(page)



# --- Keyboard & mouse (pad.gd) ---

func _kbm_page() -> void:
	_title("KEYBOARD & MOUSE")
	var pad := _pad()
	if pad == null:
		return
	if not pad.is_connected("map_changed", _on_map_changed):
		pad.connect("map_changed", _on_map_changed)
	var layout := UI.label("DRIVE  WASD / arrows      AIM  mouse      FIRE  left click      LOCK  right click      PAUSE  Esc", 18, UI.TEXT)
	layout.autowrap_mode = TextServer.AUTOWRAP_WORD
	_body.add_child(layout)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 8)
	_body.add_child(grid)
	var waiting := str(pad.get("capturing_kbm"))
	for action: String in PadScript.KBM_REBIND:
		var l := UI.label(str(PadScript.ACTION_NAMES[action]), 20)
		l.custom_minimum_size = Vector2(170, 0)
		grid.add_child(l)
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(300, 54)
		b.text = "PRESS A KEY... (Esc cancels)" if waiting == action else str(pad.call("kbm_button_name", action))
		if waiting == action:
			UI.accent(b, T.COL_UI_ACCENT)
		b.pressed.connect(rebind_kbm.bind(action))
		grid.add_child(b)
	_button("RESET TO DEFAULT", func() -> void: pad.call("reset_kbm_map"))
	var note := UI.label("Click a row, then press the key you want. Esc cancels a rebind without leaving this page. Fire, lock and pause stay on the mouse buttons and Esc. A key already in use swaps over.", 18, UI.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD
	_body.add_child(note)
	_button("BACK", show_page.bind("settings"), T.COL_UI_ACCENT)


func rebind_kbm(action: String) -> void:
	var pad := _pad()
	if pad == null:
		return
	pad.call("start_kbm_capture", action)
	show_page("kbm")


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
			UI.accent(b, T.COL_UI_ACCENT)
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
		var name_color := UI.TEXT if known else UI.TEXT_DIM
		if known and category == "parts":   # V1.3: part names in rarity colour
			name_color = UI.rarity_color(str(Parts.get_part(str(e[0])).get("rarity", "")))
		var name := UI.label(str(e[1]) if known else "? ? ? ? ?", 22, name_color)
		list.add_child(name)
		var text := UI.label(str(e[2]) if known else "Not met yet.", 18, UI.TEXT_DIM)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD
		text.custom_minimum_size = Vector2(980, 0)
		list.add_child(text)
	_button("BACK", show_page.bind("main"), T.COL_UI_ACCENT)


func show_category(cat: String) -> void:
	category = cat
	show_page("database")
