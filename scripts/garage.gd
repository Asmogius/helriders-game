extends Control
## The Garage (DESIGN §5): your one rig, its slots, and the scrap economy.
##
## Tap a slot tag (or the part on the rig) to open the bottom sheet of part
## cards. Tap a card to preview it on the full stat sheet (every number, green
## better, red worse); tap it again to fit it. A part you don't have yet is
## built for scrap; whatever comes off goes to storage and can go back on for
## free. Drag the rig to turn it. Footer tabs lead to the other stations.

const T := preload("res://scripts/tuning.gd")
const Parts := preload("res://scripts/parts.gd")
const Mods := preload("res://scripts/mods.gd")
const Loadout := preload("res://scripts/loadout.gd")
const Vehicle := preload("res://scripts/vehicle.gd")
const UI := preload("res://scripts/ui_theme.gd")
const ProfileScript := preload("res://scripts/profile.gd")
const Comms := preload("res://scripts/comms.gd")
const Inn := preload("res://scripts/inn.gd")
const Saloon := preload("res://scripts/saloon.gd")
const Research := preload("res://scripts/research.gd")
const Crew := preload("res://scripts/crew.gd")
const Missions := preload("res://scripts/missions.gd")
const MISSION_SCENE := "res://scenes/mission.tscn"
const GameMenu := preload("res://scripts/game_menu.gd")
const GarageTour := preload("res://scripts/garage_tour.gd")
const PadScript := preload("res://scripts/pad.gd")

var auto_resume := true    # closed mid-job last time: go straight back in (tests switch it off)
var menu: GameMenu
var tour: GarageTour
var tab := "GARAGE"        # the station on screen

# Slot tags: the loadout slot, where its line points on the rig (rig-local
# pixels), and which screen side the tag sits on (0 left, 1 right). Second
# weapon and utility tags only show on a chassis with the slot.
const SLOTS := [
	{"key": "chassis", "index": 0, "label": "CHASSIS", "category": "Chassis", "anchor": Vector2(-6, 15), "side": 0},
	{"key": "engine", "index": 0, "label": "ENGINE", "category": "Engine", "anchor": Vector2(-25, 0), "side": 0},
	{"key": "drive", "index": 0, "label": "DRIVE", "category": "Drive", "anchor": Vector2(-17, 18), "side": 0},
	{"key": "armor_front", "index": 0, "label": "ARMOR FRONT", "category": "Armor", "anchor": Vector2(28, 0), "side": 0},
	{"key": "armor_sides", "index": 0, "label": "ARMOR SIDES", "category": "Armor", "anchor": Vector2(4, 17), "side": 0},
	{"key": "armor_rear", "index": 0, "label": "ARMOR REAR", "category": "Armor", "anchor": Vector2(-30, 0), "side": 0},
	{"key": "weapons", "index": 0, "label": "WEAPON 1", "category": "Weapon", "anchor": Vector2(-4, 0), "side": 1},
	{"key": "weapons", "index": 1, "label": "WEAPON 2", "category": "Weapon", "anchor": Vector2(-20, 0), "side": 1},
	{"key": "internal", "index": 0, "label": "INTERNAL 1", "category": "Internal", "anchor": Vector2(-27, -6), "side": 1},
	{"key": "internal", "index": 1, "label": "INTERNAL 2", "category": "Internal", "anchor": Vector2(-12, -7), "side": 1},
	{"key": "utility", "index": 0, "label": "UTILITY 1", "category": "Utility", "anchor": Vector2(14, -12), "side": 1},
	{"key": "utility", "index": 1, "label": "UTILITY 2", "category": "Utility", "anchor": Vector2(14, 12), "side": 1},
]
const REQUIRED := ["chassis", "engine", "drive"]
const TABS := ["GARAGE", "RESEARCH", "SALOON", "INN", "COMMS"]

const TAG_SIZE := Vector2(272, 70)
const TAG_TOP := 108.0
const TAG_GAP := 8.0
const TAG_COMPACT_H := 56.0        # five tags on one side: shorter, so the sheet doesn't cover one
const TAG_COMPACT_TOP := 100.0
const TAG_COMPACT_GAP := 5.0
const RIG_SCALE := 3.4
const FOOTER_H := UI.BAR_H  # shared grid (ui_theme.gd)
const SHEET_H := 236.0

var selected := -1                 # index into SLOTS of the open sheet, -1 = closed
var profile: ProfileScript         # the /root/Profile autoload
var preview: Vehicle

var _rig_holder: Node2D
var _rig_touch: Control
var _stat_sheet: StatSheet
var _preview := ""                 # part id previewed in the open sheet ("" = empty slot)
var _tags: Array[SlotTag] = []
var _callouts: Callouts
var _rings: Callouts
var _power_meter: PowerMeter
var _hint: Label
var _scrap_label: Label
var _stats_label: Label
var _stats_icons: Control   # V6.3 icon row over the stat line
const IconLine := preload("res://scripts/icon_line.gd")
var _toast: Label
var _toast_tween: Tween
var _no_rig: Label
var _deploy: Button
var _rebuild: Button
var _sheet: Panel
var _sheet_title: Label
var _cards: HBoxContainer
var _sheet_scroll: ScrollContainer
var _overlay: Control
var _tab_buttons: Array[Button] = []
var _comms: Comms
var _inn: Inn
var _saloon: Saloon
var _research: Research
var _job: Label
var _crew_line: Button


func _ready() -> void:
	profile = get_node("/root/Profile")
	var pad := get_node_or_null("/root/Pad")
	if pad != null:
		pad.connect("mode_changed", _on_pad_mode)
	var music := get_node_or_null("/root/MusicManager")
	if music != null:
		music.play_garage()
	if auto_resume and profile.resume_job():
		# Agreed with the owner: a job quit or closed mid-fight starts over.
		get_tree().change_scene_to_file.call_deferred(MISSION_SCENE)
	elif profile.tour_active:
		start_tour.call_deferred()
	theme = UI.make()
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0.075, 0.075, 0.085)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	add_child(FloorGrid.new())

	_build_rig_area()
	_build_top_bar()
	_build_tags()
	_build_sheet()
	_build_footer()

	_comms = Comms.new()
	_comms.anchor_right = 1.0
	_comms.anchor_bottom = 1.0
	_comms.offset_bottom = -FOOTER_H
	_comms.visible = false
	_comms.job_taken.connect(_on_job_taken)
	add_child(_comms)
	_inn = Inn.new()
	_saloon = Saloon.new()
	_research = Research.new()
	for panel: Control in [_inn, _saloon, _research]:
		panel.anchor_right = 1.0
		panel.anchor_bottom = 1.0
		panel.offset_bottom = -FOOTER_H
		panel.visible = false
		add_child(panel)

	_toast = UI.label("", 22, T.COL_ORANGE)
	_toast.z_index = 12   # above overlays and the menu
	_toast.anchor_right = 1.0
	_toast.offset_top = 100.0
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.modulate.a = 0.0
	add_child(_toast)

	resized.connect(_layout)
	profile.changed.connect(_refresh)
	_layout()
	_refresh()
	if profile.notice != "":
		toast(profile.notice, 5.0)
		profile.notice = ""
		profile.save_game()


func _process(delta: float) -> void:
	_callouts.queue_redraw()
	_rings.queue_redraw()
	# Controller: the right stick turns the rig, as dragging does.
	var pad := get_node_or_null("/root/Pad")
	if pad != null and bool(pad.get("active")) and _rig_holder.visible and menu == null and (_overlay == null or not is_instance_valid(_overlay)):
		var x: float = (pad.call("stick", false) as Vector2).x
		if absf(x) > 0.2:
			rotate_rig(x * 2.5 * delta)


# --- Actions (also used by tests) ------------------------------------------------

func open_slot(i: int) -> void:
	if i == selected or i < 0:
		close_sheet()
		return
	_close_overlay()
	selected = i
	_preview = _slot_part(SLOTS[i])
	_sheet.visible = true
	_show_stat_sheet(true)
	_fill_sheet()
	_refresh_tags()


func close_sheet() -> void:
	selected = -1
	_sheet.visible = false
	_show_stat_sheet(false)
	_refresh()


## Sheet open: the stat sheet takes the rig's place. Closed: back to the rig.
func _show_stat_sheet(on: bool) -> void:
	_stat_sheet.visible = on
	_hint.visible = not on
	_job.visible = not on
	_power_meter.visible = not on and profile.has_rig()
	_no_rig.visible = not on and not profile.has_rig()
	_rig_holder.visible = not on and tab == "GARAGE"   # V0.1: never over a station
	_callouts.visible = not on
	_rings.visible = not on
	_rig_touch.mouse_filter = Control.MOUSE_FILTER_IGNORE if on else Control.MOUSE_FILTER_STOP


## First tap on a card previews it; a second tap on the same card fits it.
func press_card(id: String) -> bool:
	if selected < 0:
		return false
	if id != _preview:
		preview_part(id)
		return false
	return choose(id)


func preview_part(id: String) -> void:
	_preview = id
	for c in _cards.get_children():
		if c is PartCard:
			var card := c as PartCard
			card.selected = card.part_id == id
			_style_card(card)
	_update_stat_sheet()


## Install `id` in the open slot ("" takes the part off). Returns success.
func choose(id: String) -> bool:
	if selected < 0:
		return false
	var slot: Dictionary = SLOTS[selected]
	if _slot_part(slot) == id:
		return true
	var candidate := profile.with_part(profile.rig, slot.key, slot.index, id)
	if not profile.apply_loadout(candidate):
		toast("Not enough scrap")
		return false
	_preview = id
	toast("Fitted: " + (str(Parts.get_part(id).name) if id != "" else "slot emptied"), 2.2,
		UI.rarity_color(str(Parts.get_part(id).rarity)) if id != "" else T.COL_ORANGE)
	return true


## Your last build if you can afford it, otherwise a free all-Common starter.
func rebuild_target() -> Dictionary:
	if profile.build_cost(profile.plan) <= profile.scrap:
		return profile.plan
	return Parts.STARTER_LOADOUT


func rebuild() -> bool:
	if not profile.apply_loadout(rebuild_target()):
		toast("Not enough scrap to rebuild")
		return false
	toast("Rig rebuilt")
	return true


## Launch today's job. No job yet: off to Comms to pick one. No Driver, or a
## turret no one can aim: off to the Inn.
func deploy() -> void:
	if profile.tour_active:
		toast("Finish or skip the tour first")
		return
	if not profile.has_rig():
		return
	if not profile.has_mission():
		show_tab("COMMS")
		toast("Take a job in Comms first")
		return
	var block := profile.deploy_block()
	if block != "":
		show_tab("INN")
		toast(block, 3.5)
		return
	get_tree().change_scene_to_file(MISSION_SCENE)


## Rig stats for `loadout` with the seated crew's passives folded in.
func _built(loadout: Dictionary) -> Dictionary:
	return Crew.apply_passives(profile.build_stats(loadout), profile.seated_crew(loadout))


## Switch station: GARAGE, RESEARCH, SALOON, INN or COMMS.
func show_tab(tab_name: String) -> void:
	_on_tab(tab_name)


func _on_job_taken() -> void:
	show_tab("GARAGE")
	var m := profile.active_mission
	toast("Job taken: %s - %s. Tune your rig, then DEPLOY." % [Missions.label(m), str(m.name)], 3.5)


func rotate_rig(amount: float) -> void:
	_rig_holder.rotation += amount


## Tapping the rig opens the slot whose outlined point is closest.
func tap_rig(at: Vector2) -> void:
	var best := -1
	var best_d := 46.0
	for i in SLOTS.size():
		if not _slot_exists(SLOTS[i]):
			continue
		var d := at.distance_to(preview.to_global(slot_anchor(i)))
		if d < best_d:
			best_d = d
			best = i
	if best >= 0:
		open_slot(best)


## Where slot `i`'s callout points on the rig. With two weapons the first
## turret moves forward (vehicle.gd), so its line follows.
func slot_anchor(i: int) -> Vector2:
	var slot: Dictionary = SLOTS[i]
	var guns := profile.slot_count(profile.rig, "weapons")
	if slot.key == "weapons" and guns >= 2:
		return preview.turret_position(int(slot.index), guns)
	return slot.anchor


func toast(text: String, seconds := 2.2, color := T.COL_ORANGE) -> void:
	_toast.text = text
	_toast.add_theme_color_override("font_color", color)
	if _toast_tween != null:
		_toast_tween.kill()
	_toast.modulate.a = 1.0
	_toast_tween = create_tween()
	_toast_tween.tween_interval(seconds)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.5)


# --- Building the screen ---------------------------------------------------------

func _build_rig_area() -> void:
	var touch := RigTouch.new()
	_rig_touch = touch
	touch.garage = self
	touch.anchor_right = 1.0
	touch.anchor_bottom = 1.0
	touch.offset_left = TAG_SIZE.x + 30.0
	touch.offset_right = -(TAG_SIZE.x + 30.0)
	touch.offset_top = 96.0
	touch.offset_bottom = -FOOTER_H
	add_child(touch)

	# Callout lines go under the rig so the hull hides them; the hardpoint
	# rings go on top.
	_callouts = Callouts.new()
	_callouts.garage = self
	_callouts.slots = SLOTS
	_callouts.set_anchors_preset(Control.PRESET_FULL_RECT)
	_callouts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_callouts)

	_rig_holder = Node2D.new()
	_rig_holder.rotation = -0.3
	add_child(_rig_holder)
	preview = Vehicle.new()
	preview.scale = Vector2.ONE * RIG_SCALE
	_rig_holder.add_child(preview)
	preview.set_physics_process(false)

	_rings = Callouts.new()
	_rings.garage = self
	_rings.slots = SLOTS
	_rings.rings_only = true
	_rings.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rings.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rings)

	_power_meter = PowerMeter.new()
	_power_meter.anchor_left = 0.5
	_power_meter.anchor_right = 0.5
	_power_meter.offset_left = -270.0
	_power_meter.offset_right = 270.0
	_power_meter.offset_top = 470.0
	_power_meter.offset_bottom = 520.0
	_power_meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_power_meter)

	_stat_sheet = StatSheet.new()
	_stat_sheet.anchor_left = 0.5
	_stat_sheet.anchor_right = 0.5
	_stat_sheet.offset_left = -326.0
	_stat_sheet.offset_right = 326.0
	_stat_sheet.offset_top = 98.0
	_stat_sheet.offset_bottom = 406.0
	_stat_sheet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stat_sheet.visible = false
	add_child(_stat_sheet)

	_crew_line = Button.new()
	_crew_line.flat = true
	_crew_line.focus_mode = Control.FOCUS_NONE
	_crew_line.anchor_right = 1.0
	_crew_line.offset_left = 20.0     # below the slot tags: the full width fits a Bulwark's 4 riders
	_crew_line.offset_right = -20.0
	_crew_line.clip_text = true
	_crew_line.offset_top = 524.0
	_crew_line.offset_bottom = 556.0
	_crew_line.add_theme_font_size_override("font_size", 18)
	_crew_line.pressed.connect(func() -> void: show_tab("INN"))
	add_child(_crew_line)

	_job = UI.label("", 20, T.COL_ORANGE)
	_job.anchor_right = 1.0
	_job.anchor_top = 1.0
	_job.anchor_bottom = 1.0
	_job.offset_top = -(FOOTER_H + 82.0)
	_job.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_job)

	_hint = UI.label(_hint_text(), 18, UI.TEXT_DIM)
	_hint.anchor_right = 1.0
	_hint.anchor_top = 1.0
	_hint.anchor_bottom = 1.0
	_hint.offset_top = -(FOOTER_H + 44.0)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_hint)

	_no_rig = UI.label("NO RIG", 30, T.COL_ORANGE)
	_no_rig.anchor_left = 0.5
	_no_rig.anchor_right = 0.5
	_no_rig.offset_left = -250.0
	_no_rig.offset_right = 250.0
	_no_rig.offset_top = 380.0
	_no_rig.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_no_rig.autowrap_mode = TextServer.AUTOWRAP_WORD
	add_child(_no_rig)


func _build_top_bar() -> void:
	_scrap_label = UI.label("", 30, T.COL_ORANGE)
	_scrap_label.position = Vector2(24, 14)
	add_child(_scrap_label)

	var bar := HBoxContainer.new()
	bar.anchor_left = 1.0
	bar.anchor_right = 1.0
	bar.offset_left = -900.0
	bar.offset_right = -20.0
	bar.offset_top = 10.0
	bar.offset_bottom = 60.0
	bar.alignment = BoxContainer.ALIGNMENT_END
	bar.add_theme_constant_override("separation", 10)
	add_child(bar)

	var menu_button := _button("MENU", 120)
	menu_button.pressed.connect(open_menu)
	bar.add_child(menu_button)
	var presets := _button("PRESETS", 150)
	presets.pressed.connect(_open_presets)
	bar.add_child(presets)
	var upgrades := _button("UPGRADES", 170)
	upgrades.pressed.connect(_open_upgrades)
	bar.add_child(upgrades)
	_rebuild = _button("REBUILD", 200)
	_rebuild.pressed.connect(rebuild)
	UI.accent(_rebuild, T.COL_CYAN)
	bar.add_child(_rebuild)
	_deploy = _button("DEPLOY", 180)
	_deploy.pressed.connect(deploy)
	UI.accent(_deploy, T.COL_ORANGE)
	bar.add_child(_deploy)

	_stats_label = UI.label("", 19, UI.TEXT)
	_stats_label.anchor_right = 1.0
	_stats_label.offset_top = 66.0
	_stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_stats_label)
	# V6.3: the stat line as icons + numbers; the label keeps the text (tests,
	# fallback) and hides while the icon row draws.
	_stats_icons = IconLine.new()
	_stats_icons.anchor_right = 1.0
	_stats_icons.offset_top = 64.0
	_stats_icons.offset_bottom = 92.0
	add_child(_stats_icons)


func _build_tags() -> void:
	for i in SLOTS.size():
		var slot: Dictionary = SLOTS[i]
		var tag := SlotTag.new()
		tag.side = slot.side
		tag.slot_label = slot.label
		if slot.side == 0:
			tag.offset_left = 20.0
			tag.offset_right = 20.0 + TAG_SIZE.x
		else:
			tag.anchor_left = 1.0
			tag.anchor_right = 1.0
			tag.offset_left = -20.0 - TAG_SIZE.x
			tag.offset_right = -20.0
		tag.pressed.connect(open_slot.bind(i))
		add_child(tag)
		_tags.append(tag)
	_layout_tags()


## Stack the visible tags on each side top-down. A side with five tags goes
## compact so the bottom one stays clear of the part sheet.
func _layout_tags() -> void:
	for side in 2:
		var visible_tags: Array[SlotTag] = []
		for i in SLOTS.size():
			if int(SLOTS[i].side) == side and _slot_exists(SLOTS[i]):
				visible_tags.append(_tags[i])
		var compact := visible_tags.size() > 4
		var h := TAG_COMPACT_H if compact else TAG_SIZE.y
		var gap := TAG_COMPACT_GAP if compact else TAG_GAP
		var y := TAG_COMPACT_TOP if compact else TAG_TOP
		for tag in visible_tags:
			tag.compact = compact
			tag.offset_top = y
			tag.offset_bottom = y + h
			y += h + gap


func _build_sheet() -> void:
	_sheet = Panel.new()
	_sheet.anchor_top = 1.0
	_sheet.anchor_bottom = 1.0
	_sheet.anchor_right = 1.0
	_sheet.offset_top = -(FOOTER_H + SHEET_H)
	_sheet.offset_bottom = -FOOTER_H
	_sheet.visible = false
	add_child(_sheet)

	_sheet_title = UI.label("", 20, UI.TEXT_DIM)
	_sheet_title.position = Vector2(20, 10)
	_sheet.add_child(_sheet_title)

	var close := _button("CLOSE", 120)
	close.anchor_left = 1.0
	close.anchor_right = 1.0
	close.offset_left = -136.0
	close.offset_right = -16.0
	close.offset_top = 6.0
	close.offset_bottom = 42.0
	close.add_theme_font_size_override("font_size", 18)
	close.pressed.connect(close_sheet)
	_sheet.add_child(close)

	_sheet_scroll = ScrollContainer.new()
	_sheet_scroll.anchor_right = 1.0
	_sheet_scroll.anchor_bottom = 1.0
	_sheet_scroll.offset_left = 14.0
	_sheet_scroll.offset_right = -14.0
	_sheet_scroll.offset_top = 48.0
	_sheet_scroll.offset_bottom = -8.0
	_sheet_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_sheet_scroll.scroll_deadzone = 14
	_sheet.add_child(_sheet_scroll)
	_cards = HBoxContainer.new()
	_cards.add_theme_constant_override("separation", 12)
	_sheet_scroll.add_child(_cards)


func _build_footer() -> void:
	var footer := HBoxContainer.new()
	footer.anchor_top = 1.0
	footer.anchor_bottom = 1.0
	footer.anchor_right = 1.0
	footer.offset_top = -FOOTER_H
	footer.add_theme_constant_override("separation", 0)
	add_child(footer)
	for tab_name: String in TABS:
		var tab := _button(tab_name, 0)
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.add_theme_font_size_override("font_size", 20)
		tab.pressed.connect(_on_tab.bind(tab_name))
		footer.add_child(tab)
		_tab_buttons.append(tab)
	_highlight_tab("GARAGE")


func _button(text: String, min_width: float) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(min_width, 0)
	return b


func _layout() -> void:
	# The rig sits in the middle, nudged up so the sheet doesn't cover it.
	_rig_holder.position = Vector2(size.x * 0.5, 290.0)


# --- Refresh ---------------------------------------------------------------------

func _refresh() -> void:
	_scrap_label.text = "SCRAP  %d     DAY %d" % [profile.scrap, profile.day]
	if profile.has_mission():
		var m := profile.active_mission
		var level := Missions.skulls(m)
		_job.text = "JOB:  %s  -  %s     %d SKULL%s     PAYS %d" % [Missions.label(m), str(m.name), level, "" if level == 1 else "S", int(m.reward)]
	else:
		_job.text = "No job taken. Open COMMS to pick today's job."
	_job.visible = selected < 0
	var has_rig := profile.has_rig()
	var shown: Dictionary = profile.rig
	var any_part := not profile.parts_in(profile.rig).is_empty()
	if not any_part and profile.is_complete(profile.plan):
		shown = profile.plan  # ghost of the rig you lost
	var stats := profile.build_stats(shown)
	preview.apply_stats(stats)
	preview.modulate.a = 1.0 if has_rig else 0.3
	var built := _built(profile.rig)
	_refresh_crew_line()
	_stats_label.text = _stats_line(built, has_rig)
	_stats_icons.items = _stats_items(built) if has_rig and _stats_icons.get("_icons").ok() else []
	_stats_label.visible = (_stats_icons.items as Array).is_empty()
	_power_meter.set_values(float(built.power_draw), float(built.power_output), float(built.weight), float(built.weight_capacity))
	_power_meter.visible = has_rig and selected < 0

	_deploy.disabled = not has_rig
	var target := rebuild_target()
	var rebuild_cost := profile.build_cost(target)
	_rebuild.visible = not has_rig
	if target == profile.plan:
		_rebuild.text = "REBUILD  FREE" if rebuild_cost == 0 else "REBUILD  %d" % rebuild_cost
	else:
		_rebuild.text = "STARTER RIG  FREE"
	_rebuild.disabled = rebuild_cost > profile.scrap
	_no_rig.visible = not has_rig and selected < 0
	_crew_line.visible = has_rig and selected < 0
	if not has_rig:
		_no_rig.text = "NO RIG\nRebuild your last build, or fit parts slot by slot. Common parts are free."
	_refresh_tags()
	if selected >= 0:
		_fill_sheet()


## "CREW   DRIVER Mae Voss L2   GUNNER empty", red when DEPLOY is blocked.
func _refresh_crew_line() -> void:
	var bits: Array[String] = []
	var riders := profile.seated_crew()
	for seat: String in profile.seats():
		if seat == "open":
			continue
		var m := profile.seated_in(seat)
		bits.append("%s %s" % [str(Crew.ROLE_NAMES[seat]).to_upper(), "empty" if m.is_empty() else "%s L%d" % [m.name, Crew.level(m)]])
	var open := profile.seats().count("open")
	var filled := 0
	for m in riders:
		if Crew.OPEN_CLASSES.has(str(m.role)):
			bits.append("%s %s L%d" % [Crew.role_name(m).to_upper(), m.name, Crew.level(m)])
			filled += 1
	for i in open - filled:
		bits.append("OPEN SEAT")
	var waiting := profile.perks_waiting()
	var tail := "    PERK READY  >" if waiting > 0 else "    >"
	_crew_line.text = "CREW    " + "    ".join(bits) + tail
	var blocked := profile.has_rig() and profile.deploy_block() != ""
	var color := UI.BAD if blocked else T.COL_CYAN
	for state: String in ["font_color", "font_hover_color", "font_pressed_color"]:
		_crew_line.add_theme_color_override(state, color)


## V6.3: the stat line as [icon, label, value, tint] for the icon row.
func _stats_items(s: Dictionary) -> Array:
	var m := Loadout.mobility(s)
	var items: Array = [
		["hp", "HP", str(int(s.get("hp", 0.0))), UI.GOOD],
		["armor", "ARMOR", "%d/%d/%d" % [int(s.get("front", 0.0)), int(s.get("side", 0.0)), int(s.get("rear", 0.0))], UI.TEXT_DIM],
		["shield", "SHIELD", str(int(s.get("shield", 0.0))), T.COL_CYAN],
		["speed", "SPEED", str(roundi(float(s.max_speed) * m)), UI.TEXT_DIM],
		["accel", "ACCEL", str(roundi(float(s.acceleration) * m)), UI.TEXT_DIM],
		["dps", "DPS", str(roundi(Loadout.total_dps(s))), T.COL_ORANGE],
		["lock", "LOCK", str(int(s.lock_range)) if float(s.lock_range) > 0.0 else "NONE", UI.TEXT_DIM],
	]
	var over := StatSheet.overload_cause(s)
	if over != "":
		items.append(["power", "", over, T.COL_ORANGE])
	return items


func _stats_line(s: Dictionary, complete: bool) -> String:
	if not complete:
		var missing: Array[String] = []
		for key: String in REQUIRED:
			if str(profile.rig.get(key, "")) == "":
				missing.append(key.to_upper())
		return "Needs " + ", ".join(missing) + " to deploy"
	var m := Loadout.mobility(s)
	var lock := "LOCK %d" % int(s.lock_range) if float(s.lock_range) > 0.0 else "NO LOCK"
	var line := "HP %d   ARMOR %d/%d/%d   SHIELD %d    SPEED %d    ACCEL %d    DPS %d    %s" % [
		int(s.get("hp", 0.0)), int(s.get("front", 0.0)), int(s.get("side", 0.0)), int(s.get("rear", 0.0)), int(s.get("shield", 0.0)),
		roundi(float(s.max_speed) * m), roundi(float(s.acceleration) * m), roundi(Loadout.total_dps(s)), lock]
	var over := StatSheet.overload_cause(s)
	if over != "":
		line += "    " + over
	return line


func _refresh_tags() -> void:
	_layout_tags()
	for i in SLOTS.size():
		var slot: Dictionary = SLOTS[i]
		var tag := _tags[i]
		tag.visible = _slot_exists(slot)
		var id := _slot_part(slot)
		tag.active = i == selected
		tag.empty = id == ""
		tag.required = REQUIRED.has(slot.key)
		if id == "":
			tag.part_name = "Empty"
			tag.detail = "REQUIRED" if tag.required else PadScript.hint("Tap to fit a part", "Cross to fit a part")
		else:
			var part := profile.part(id)
			tag.part_name = part.name
			if int(part.level) > 1:
				tag.part_name += "  LV %d" % int(part.level)
			if part.has("power_output"):
				tag.detail = "%s    OUTPUT %d    WT %d" % [part.rarity, int(part.power_output), int(part.weight)]
			elif part.has("weight_capacity"):
				tag.detail = "%s    PWR %d    CAP %d" % [part.rarity, int(part.power), int(part.weight_capacity)]
			elif part.category == "Armor":
				var sides := str(slot.key) == "armor_sides"
				tag.detail = "%s    %d / FACING    WT %d" % [part.rarity, int(part.armor), int(part.get("weight_sides" if sides else "weight", part.weight))]
			else:
				tag.detail = "%s    PWR %d    WT %d" % [part.rarity, int(part.power), int(part.get("weight", 0))]
		tag.rarity = "" if id == "" else str(profile.part(id).rarity)   # V1.3
		tag.queue_redraw()


func _slot_exists(slot: Dictionary) -> bool:
	if slot.key in profile.LIST_SLOTS:
		return int(slot.index) < profile.slot_count(profile.rig, slot.key)
	return true


func _slot_part(slot: Dictionary) -> String:
	var value: Variant = profile.rig.get(slot.key, "")
	if value is Array:
		var list: Array = value
		return str(list[slot.index]) if int(slot.index) < list.size() else ""
	return str(value)


# --- Bottom sheet ----------------------------------------------------------------

func _fill_sheet() -> void:
	for c in _cards.get_children():
		_cards.remove_child(c)
		c.queue_free()
	var slot: Dictionary = SLOTS[selected]
	var current := _slot_part(slot)
	_sheet_title.text = _sheet_title_text(slot)

	var ids: Array[String] = []
	for id in profile.schematics:
		var p := Parts.get_part(id)
		if p.category == slot.category and not (bool(p.get("front_only", false)) and slot.key != "armor_front"):
			ids.append(id)
	ids.sort_custom(func(a: String, b: String) -> bool:
		return (a == current and b != current) or (a != current and b != current and int(Parts.get_part(a).cost) < int(Parts.get_part(b).cost)))
	if ids.is_empty():
		var none := UI.label("No %s schematics yet. Find them in missions, or buy them at the Saloon." % slot.category.to_lower(), 20, UI.TEXT_DIM)
		_cards.add_child(none)
		_update_stat_sheet()
		return

	var now := _built(profile.rig)
	for id in ids:
		_cards.add_child(_make_card(slot, id, current, now))
	if current != "" and not REQUIRED.has(slot.key):
		_cards.add_child(_make_card(slot, "", current, now))
	_update_stat_sheet()


func _update_stat_sheet() -> void:
	if selected < 0:
		return
	var slot: Dictionary = SLOTS[selected]
	var now := _built(profile.rig)
	var after := _built(profile.with_part(profile.rig, slot.key, slot.index, _preview))
	var name_now := _slot_part(slot)
	var title := "%s:  %s" % [slot.label, Parts.get_part(name_now).name if name_now != "" else "Empty"]
	if _preview != name_now:
		title += "   >   " + (str(Parts.get_part(_preview).name) if _preview != "" else "Empty")
	var weapon := int(slot.index) if slot.key == "weapons" else 0
	_stat_sheet.set_data(title, now, after, weapon)

func _make_card(slot: Dictionary, id: String, current: String, now: Dictionary) -> PartCard:
	var card := PartCard.new()
	card.part_id = id
	var candidate := profile.with_part(profile.rig, slot.key, slot.index, id)
	var after := _built(candidate)
	var cost := profile.build_cost(candidate)
	card.cost = cost
	card.selected = id == _preview
	if id == "":
		card.title = "Remove"
		card.subtitle = "Back to storage"
		card.rarity_color = UI.TEXT_DIM
		card.rarity = ""
	else:
		var part := profile.part(id)
		card.title = part.name
		var kind := str(part.category)
		if kind == "Weapon":
			kind = "Turret" if int(part.mount) == 0 else "Fixed guns"
			if int(part.get("pellets", 1)) > 1:
				kind += ", %d pellets" % int(part.pellets)
		card.subtitle = "%s %s" % [part.rarity, kind]
		if int(part.level) > 1:
			card.subtitle += "  LV %d" % int(part.level)
		card.rarity_color = UI.rarity_color(str(part.rarity))   # V1.3
		card.rarity = str(part.rarity)
		card.category = "cat_armor" if str(part.category) == "Armor" else str(part.category).to_lower()   # V6.3 icon id
		card.headline = _headline(part)
		card.mod_line = mod_line(part)
		card.mod_chips = mod_chips(part)
	if id == current:
		card.installed = true
	else:
		card.deltas = _deltas(now, after)
		card.warning = StatSheet.overload_cause(after)
	_style_card(card)
	card.pressed.connect(press_card.bind(id))
	return card


## Status line on a card: what a tap (or a second tap) would do.
func _style_card(card: PartCard) -> void:
	var again := PadScript.hint("TAP AGAIN:  ", "PRESS AGAIN:  ") if card.selected else ""
	if card.installed:
		card.status = "INSTALLED"
		card.status_color = T.COL_CYAN
	elif card.cost > profile.scrap:
		card.status = "NEED %d SCRAP" % card.cost
		card.status_color = UI.BAD
	elif card.cost == 0:
		card.status = again + ("TAKE OFF" if card.part_id == "" else "FIT  -  FREE")
		card.status_color = UI.GOOD
	else:
		card.status = again + "BUILD  %d SCRAP" % card.cost
		card.status_color = T.COL_ORANGE
	card.queue_redraw()


func _headline(part: Dictionary) -> String:
	match str(part.category):
		"Chassis":
			return "W/I/U %d/%d/%d  CAP %d  HP %d" % [int(part.hardpoints), int(part.internal_slots), int(part.utility_slots), int(part.weight_capacity), int(part.hp)]
		"Engine":
			return "OUTPUT %d  ACCEL %d  WT %d" % [int(part.power_output), int(part.acceleration), int(part.weight)]
		"Drive":
			return "PWR %d  WT %d  GRIP %.1f  SPD x%.2f" % [int(part.power), int(part.weight), float(part.grip), float(part.speed_mult)]
		"Armor":
			var where := "FRONT ONLY" if bool(part.get("front_only", false)) else "WT %d/%d" % [int(part.weight), int(part.get("weight_sides", part.weight))]
			return "%d / FACING  RAM %d  %s" % [int(part.armor), int(part.ram_damage), where]
		"Weapon":
			var dps := Loadout.total_dps({"weapons": [part]})
			var burst := "  x%d BURST" % int(part.burst) if int(part.get("burst", 1)) > 1 else ""
			if int(part.get("mag", 0)) > 0:
				burst += "  MAG %d" % int(part.mag)
			match str(part.get("kind", "")):
				"harpoon":
					burst += "  TETHERS RIGS"
				"mortar":
					burst += "  LOBS %d-%d" % [int(part.min_range), int(part.max_range)]
			return "DPS %d  PWR %d  WT %d%s%s" % [roundi(dps), int(part.power), int(part.weight), burst, "  LOCK" if float(part.lock_range) > 0.0 else ""]
		"Internal":
			return "PWR %d  WT %d  %s" % [int(part.power), int(part.weight), effect_text(part)]
		"Utility":
			return "PWR %d  WT %d  EVERY %dS" % [int(part.power), int(part.weight), int(part.cooldown)]
	return "PWR %d" % int(part.get("power", 0))


## The part's mods on one line: unlocked ones by name, locked ones with the
## level they open at (mods show while locked; DESIGN §14).
static func mod_line(part: Dictionary) -> String:
	var bits: Array[String] = []
	var level := int(part.get("level", 1))
	for m: Array in Mods.reachable(str(part.get("id", "")), Parts.max_level(part)):
		var at := Mods.unlock_level(str(m[0]))
		bits.append(str(m[2]).to_upper() + ("" if level >= at else " LV%d" % at))
	return ("MODS  " + "  /  ".join(bits)) if not bits.is_empty() else ""


## Keyword chips for the part's mods (§14): [keyword, unlocked] for each mod
## that carries a keyword. The card draws them in the keyword's color, dim
## while locked.
static func mod_chips(part: Dictionary) -> Array:
	var out: Array = []
	var level := int(part.get("level", 1))
	for m: Array in Mods.reachable(str(part.get("id", "")), Parts.max_level(part)):
		var kw := str(m[4]) if m.size() > 4 else ""
		if T.KEYWORDS.has(kw):
			out.append([kw, level >= Mods.unlock_level(str(m[0]))])
	return out


## What an internal or utility part does, in a few words.
static func effect_text(part: Dictionary) -> String:
	var bits: Array[String] = []
	if part.get("enables_lock", false):
		bits.append("LOCK")
	elif part.get("manual_aim", false):
		bits.append("AIMS TURRETS")
	if part.has("injury_mult"):
		bits.append("CREW INJURY -%d%%" % roundi((1.0 - float(part.injury_mult)) * 100.0))
	var labels := {"fire_rate_mult": "FIRE", "damage_mult": "DMG", "lock_range_mult": "LOCK RNG", "turret_aim_mult": "AIM"}
	for key: String in labels:
		if part.has(key):
			bits.append("%s +%d%%" % [str(labels[key]), roundi((float(part[key]) - 1.0) * 100.0)])
	if part.has("hp_bonus"):
		bits.append("HP +%d" % int(part.hp_bonus))
	var res_names := ["SHOCK", "FIRE", "ACID", "TOXIC", "SLIME", "GOOP"]
	var res: Array = part.get("resist_bonus", [])
	for k in mini(res.size(), 6):
		if float(res[k]) > 0.0:
			bits.append("%s RES +%d" % [str(res_names[k]), int(res[k])])
	if part.has("shield"):
		bits.append("SHIELD %d" % int(part.shield))
	if part.has("ram_bonus"):
		bits.append("RAM +%d" % int(part.ram_bonus))
	match str(part.get("ability", "")):
		"patch":
			bits.append("REPAIR %d" % int(part.heal))
		"mines":
			bits.append("%d MINES x%d" % [int(part.mines), int(part.mine_damage)])
		"oil":
			bits.append("SLICK %d WIDE, %dS, ENEMIES ONLY" % [int(float(part.oil_radius) * 2.0), int(part.oil_time)])
		"spikes":
			bits.append("STRIP %d LONG, %dS" % [int(part.spike_length), int(part.spike_time)])
		"pulse":
			bits.append("SHOCK BURST %d PX, %d DMG" % [int(part.pulse_radius), int(part.pulse_damage)])
	return "  ".join(bits)


## Up to four "+/-" changes this swap would make, worst first so costs show.
## Same numbers as the stat sheet, so speed and accel include any overload.
func _deltas(now_stats: Dictionary, after_stats: Dictionary) -> Array:
	var now := StatSheet.values(now_stats)
	var after := StatSheet.values(after_stats)
	var out: Array = []
	var rows := [
		["PWR", "load", false, 0],
		["WT", "weight", false, 0],
		["ARMOR", "armor", true, 0],
		["SHIELD", "shield", true, 0],
		["SPD", "speed", true, 0],
		["ACCEL", "accel", true, 0],
		["GRIP", "grip", true, 1],
		["DPS", "dps", true, 0],
	]
	for r: Array in rows:
		var a: float = now[r[1]]
		var b: float = after[r[1]]
		var d := b - a
		if absf(d) < 0.05:
			continue
		var better := (d > 0.0) == bool(r[2])
		var text := ("%s %+.1f" if int(r[3]) == 1 else "%s %+d") % [r[0], d if int(r[3]) == 1 else roundi(d)]
		out.append([text, better])
	var lock_now := float(now.lock) > 0.0
	var lock_after := float(after.lock) > 0.0
	if lock_now != lock_after:
		out.append(["LOCK " + ("GAINED" if lock_after else "LOST"), lock_after])
	out.sort_custom(func(x: Array, y: Array) -> bool: return not bool(x[1]) and bool(y[1]))
	return out.slice(0, 4)


# --- Overlays: presets, upgrades, other stations ------------------------------

func _open_overlay(title: String, body: Control) -> void:
	_close_overlay()
	close_sheet()
	_overlay = Control.new()
	_overlay.z_index = 10   # above the rig preview (its sprites draw at z 1-3)
	_overlay.add_to_group("pad_modal")   # controller: focus stays in it, Circle closes it
	_overlay.set_meta("pad_close", _close_overlay)
	_overlay.anchor_right = 1.0
	_overlay.anchor_bottom = 1.0
	_overlay.offset_bottom = -FOOTER_H  # footer stays tappable
	add_child(_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			_close_overlay())
	_overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(820, 0)
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	panel.add_child(column)
	var head := HBoxContainer.new()
	var title_label := UI.label(title, 28, T.COL_ORANGE)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title_label)
	var close := _button("CLOSE", 120)
	close.pressed.connect(_close_overlay)
	head.add_child(close)
	column.add_child(head)
	column.add_child(body)


func _close_overlay() -> void:
	if _overlay != null:
		_overlay.queue_free()
		_overlay = null
	_highlight_tab("GARAGE")


func _open_presets() -> void:
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.add_child(UI.label("Save your current rig, or switch to a saved one. Parts you don't have are built for scrap. NAME gives a preset its own name.", 18, UI.TEXT_DIM))
	for i in T.PRESET_COUNT:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var p := profile.preset(i)
		var name_label := UI.label(profile.preset_name(i), 22, T.COL_CYAN)
		name_label.custom_minimum_size = Vector2(200, 0)
		name_label.clip_text = true
		row.add_child(name_label)
		var summary := UI.label(_summary(p) if not p.is_empty() else "Empty", 18, UI.TEXT if not p.is_empty() else UI.TEXT_DIM)
		summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		summary.clip_text = true
		summary.custom_minimum_size = Vector2(260, 0)
		row.add_child(summary)
		var rename := _button("NAME", 100)
		rename.pressed.connect(open_rename.bind(i))
		row.add_child(rename)
		var save := _button("SAVE", 100)
		save.disabled = not profile.has_rig()
		save.pressed.connect(func() -> void:
			profile.save_preset(i)
			toast("Saved to %s" % profile.preset_name(i))
			_open_presets())
		row.add_child(save)
		var cost := profile.build_cost(p) if not p.is_empty() else 0
		var load_button := _button("LOAD" if cost == 0 else "LOAD  %d" % cost, 150)
		load_button.disabled = p.is_empty() or cost > profile.scrap or p == profile.rig
		load_button.pressed.connect(func() -> void:
			if profile.load_preset(i):
				toast("Loaded %s" % profile.preset_name(i))
			_close_overlay())
		row.add_child(load_button)
		body.add_child(row)
	_open_overlay("PRESETS", body)


var _rename_edit: LineEdit   # the name box while naming a preset


## Name preset `index`: a text box (the phone's keyboard comes up), DONE / CANCEL.
func open_rename(index: int) -> void:
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.add_child(UI.label("Name this preset (up to %d letters). Leave it empty to go back to P%d." % [T.PRESET_NAME_MAX, index + 1], 18, UI.TEXT_DIM))
	_rename_edit = LineEdit.new()
	_rename_edit.max_length = T.PRESET_NAME_MAX
	_rename_edit.placeholder_text = "P%d" % (index + 1)
	_rename_edit.text = str(profile.preset_names[index]) if index < profile.preset_names.size() else ""
	_rename_edit.custom_minimum_size = Vector2(520, 60)
	_rename_edit.add_theme_font_size_override("font_size", 26)
	_rename_edit.text_submitted.connect(func(_t: String) -> void: finish_rename(index))
	body.add_child(_rename_edit)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var done := _button("DONE", 160)
	UI.accent(done, T.COL_CYAN)
	done.pressed.connect(finish_rename.bind(index))
	row.add_child(done)
	var cancel := _button("CANCEL", 160)
	cancel.pressed.connect(_open_presets)
	row.add_child(cancel)
	body.add_child(row)
	_open_overlay("NAME %s" % profile.preset_name(index), body)
	_rename_edit.grab_focus.call_deferred()   # brings up the keyboard
	_rename_edit.caret_column = _rename_edit.text.length()


func finish_rename(index: int) -> void:
	if _rename_edit == null or not is_instance_valid(_rename_edit):
		return
	profile.rename_preset(index, _rename_edit.text)
	toast("Preset named %s" % profile.preset_name(index))
	_rename_edit = null
	_open_presets()


func _summary(loadout: Dictionary) -> String:
	var names: Array[String] = []
	for key: String in ["weapons", "drive", "armor_front", "internal", "utility"]:
		var value: Variant = loadout.get(key, "")
		var ids: Array = value if value is Array else [value]
		for id: Variant in ids:
			if str(id) != "":
				names.append(str(Parts.get_part(str(id)).name))
	return " / ".join(names)


func _open_upgrades() -> void:
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.add_child(UI.label("Scrap  %d" % profile.scrap, 22, T.COL_ORANGE))
	for key: String in ["fabrication", "loot", "salvage"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(UI.label(str(T.UPGRADES[key].name), 24, UI.TEXT))
		info.add_child(UI.label(_upgrade_effect(key), 17, UI.TEXT_DIM))
		row.add_child(info)
		var level := profile.upgrade_level(key)
		var max_level: int = (T.UPGRADES[key].costs as Array).size()
		row.add_child(UI.label("LV %d/%d" % [level, max_level], 22, T.COL_CYAN))
		var cost := profile.upgrade_cost(key)
		var buy := _button("MAXED" if cost < 0 else "BUY  %d" % cost, 170)
		buy.disabled = cost < 0 or cost > profile.scrap
		buy.pressed.connect(func() -> void:
			if profile.buy_upgrade(key):
				toast("%s upgraded" % str(T.UPGRADES[key].name))
			_open_upgrades())
		row.add_child(buy)
		body.add_child(row)
	_open_overlay("GARAGE UPGRADES", body)


func _upgrade_effect(key: String) -> String:
	var level := profile.upgrade_level(key)
	var step: float = T.UPGRADES[key].per_level
	var next := level + 1
	var max_level: int = (T.UPGRADES[key].costs as Array).size()
	var now_text := ""
	var next_text := ""
	match key:
		"fabrication":
			now_text = "Parts cost %d%% less" % roundi(step * level * 100.0)
			next_text = "%d%%" % roundi(step * next * 100.0)
		"loot":
			now_text = "Outrider schematic drop chance %d%%" % roundi(profile.schematic_chance() * 100.0)
			next_text = "%d%%" % roundi(minf(T.SCHEMATIC_DROP_CHANCE + step * next, 0.95) * 100.0)
		"salvage":
			now_text = "Scrap from kills +%d%%" % roundi(step * level * 100.0)
			next_text = "+%d%%" % roundi(step * next * 100.0)
	return now_text if level >= max_level else "%s    (next: %s)" % [now_text, next_text]


func _on_tab(tab_name: String) -> void:
	tab = tab_name
	_comms.visible = tab_name == "COMMS"
	_inn.visible = tab_name == "INN"
	_saloon.visible = tab_name == "SALOON"
	_research.visible = tab_name == "RESEARCH"
	_rig_holder.visible = tab_name == "GARAGE" and not _stat_sheet.visible   # V0.1
	if tab_name == "GARAGE":
		_close_overlay()
		return
	_close_overlay()
	close_sheet()
	match tab_name:
		"COMMS":
			_comms.selected = -1
			_comms.refresh()
		"INN":
			_inn.refresh()
		"SALOON":
			_saloon.selected = -1
			_saloon.refresh()
		"RESEARCH":
			_research.close_upgrades()
			_research.refresh()
	_highlight_tab(tab_name)


func _highlight_tab(tab_name: String) -> void:
	for tab in _tab_buttons:
		if tab.text == tab_name:
			UI.accent(tab, T.COL_CYAN)
		else:
			for state: String in ["normal", "hover", "pressed"]:
				tab.remove_theme_stylebox_override(state)
			tab.remove_theme_color_override("font_color")


# --- Small widgets -------------------------------------------------------------------

class SlotTag extends Button:
	## A slot callout beside the rig: slot name, the part in it, a detail line.
	const T := preload("res://scripts/tuning.gd")
	const UI := preload("res://scripts/ui_theme.gd")
	var side := 0
	var slot_label := ""
	var part_name := ""
	var detail := ""
	var empty := false
	var required := false
	var active := false
	var rarity := "":   # fitted part's rarity (V1.3); "" when empty
		set(v):
			if v != rarity:
				rarity = v
				var f: Control = UI.rarity_frame(self, v) if v != "" else get_node_or_null("RarityFrame")
				if f != null:
					f.visible = v != ""
	var compact := false   # shorter tag when five share a side

	func _ready() -> void:
		flat = true
		focus_mode = Control.FOCUS_NONE

	func accent() -> Color:
		if active:
			return T.COL_ORANGE
		if empty and required:
			return UI.BAD
		return T.COL_CYAN

	func _draw() -> void:
		var font := get_theme_default_font()
		var a := accent()
		var fill := Color(0.1, 0.1, 0.11, 0.92)
		if get_draw_mode() == DRAW_PRESSED or active:
			fill = Color(0.17, 0.12, 0.08, 0.95)
		draw_rect(Rect2(Vector2.ZERO, size), fill)
		draw_rect(Rect2(Vector2.ZERO, size), Color(a, 0.85 if active else 0.4), false, 2.0)
		if active and rarity != "":   # the rarity frame covers the edge: ring inside it
			draw_rect(Rect2(Vector2(4, 4), size - Vector2(8, 8)), Color(a, 0.85), false, 2.0)
		draw_rect(Rect2(size.x - 4.0 if side == 0 else 0.0, 0.0, 4.0, size.y), a)
		var ys := PackedFloat32Array([17.0, 36.0, 51.0]) if compact else PackedFloat32Array([20.0, 45.0, 63.0])
		draw_string(font, Vector2(14, ys[0]), slot_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13 if compact else 14, UI.TEXT_DIM)
		UI.draw_fit(self, font, Vector2(14, ys[1]), part_name, HORIZONTAL_ALIGNMENT_LEFT, size.x - 26.0, 18 if compact else 21, UI.TEXT_DIM if empty else UI.TEXT)
		UI.draw_fit(self, font, Vector2(14, ys[2]), detail, HORIZONTAL_ALIGNMENT_LEFT, size.x - 26.0, 13 if compact else 14, Color(a, 0.9))


class PartCard extends Button:
	## One part in the bottom sheet: what it is, what it changes, what it costs.
	const T := preload("res://scripts/tuning.gd")
	const UI := preload("res://scripts/ui_theme.gd")
	var title := ""
	var subtitle := ""
	var headline := ""
	var mod_line := ""
	var mod_chips: Array = []   # [keyword, unlocked]
	var deltas: Array = []          # [text, better] pairs
	var status := ""
	var status_color := Color.WHITE
	var warning := ""
	var rarity_color := Color.WHITE
	var category := ""   # V6.3: the category icon left of the title
	var _icons: RefCounted = UI.icons()
	var rarity := "":   # V1.3: a part's cards wear its rarity frame
		set(v):
			rarity = v
			if is_inside_tree():
				_frame()
	var installed := false
	var selected := false          # previewed on the stat sheet
	var part_id := ""
	var cost := 0

	func _ready() -> void:
		flat = true
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = Vector2(262, 176)
		action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
		_frame()

	func _frame() -> void:
		var f: Control = get_node_or_null("RarityFrame")
		if rarity == "":
			if f != null:
				f.visible = false
			return
		UI.rarity_frame(self, rarity).visible = true

	func _draw() -> void:
		var font := get_theme_default_font()
		var fill := Color(0.12, 0.12, 0.13)
		if installed:
			fill = Color(0.08, 0.14, 0.15)
		elif get_draw_mode() == DRAW_PRESSED:
			fill = Color(0.2, 0.13, 0.08)
		draw_rect(Rect2(Vector2.ZERO, size), fill)
		if rarity == "":
			draw_rect(Rect2(0, 0, size.x, 5), rarity_color)
			draw_rect(Rect2(Vector2.ZERO, size), Color(rarity_color, 0.35), false, 2.0)
		if selected:   # inside the rarity frame, so both show
			draw_rect(Rect2(Vector2(4, 4), size - Vector2(8, 8)), T.COL_ORANGE, false, 3.0)
		var dim := 0.45 if disabled else 1.0
		var tx := 12.0
		if category != "" and _icons.draw(self, category, Rect2(12, 14, 20, 20), Color(rarity_color, dim)):
			tx = 38.0
		UI.draw_fit(self, font, Vector2(tx, 30), title, HORIZONTAL_ALIGNMENT_LEFT, size.x - tx - 12.0, 19, Color(UI.TEXT, dim))
		draw_string(font, Vector2(12, 50), subtitle, HORIZONTAL_ALIGNMENT_LEFT, size.x - 24.0, 14, Color(rarity_color, 0.9 * dim))
		draw_string(font, Vector2(12, 72), headline, HORIZONTAL_ALIGNMENT_LEFT, size.x - 24.0, 14, Color(UI.TEXT_DIM, dim))
		var y := 94.0
		var x := 12.0
		for d: Array in deltas:
			var text: String = d[0]
			var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
			if x + w > size.x - 12.0:
				x = 12.0
				y += 18.0
			draw_string(font, Vector2(x, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(UI.GOOD if d[1] else UI.BAD, dim))
			x += w + 12.0
		if mod_line != "":
			draw_string(font, Vector2(12, size.y - 54.0), mod_line, HORIZONTAL_ALIGNMENT_LEFT, size.x - 24.0, 12, Color(UI.TEXT_DIM, 0.8 * dim))
		# Keyword chips: one per keyword mod, in its color, 40% while locked.
		for k in mod_chips.size():
			var chip: Array = mod_chips[k]
			var col: Color = (T.KEYWORDS[str(chip[0])] as Dictionary).color
			col.a = (1.0 if bool(chip[1]) else 0.4) * dim
			draw_rect(Rect2(size.x - 26.0 - 18.0 * k, 8.0, 12.0, 12.0), col)
		if warning != "":
			draw_string(font, Vector2(12, size.y - 34.0), warning, HORIZONTAL_ALIGNMENT_LEFT, size.x - 24.0, 14, UI.BAD)
		draw_string(font, Vector2(12, size.y - 12.0), status, HORIZONTAL_ALIGNMENT_LEFT, size.x - 24.0, 16, status_color)


class Callouts extends Control:
	## Lines from each slot tag to its point on the rig, with a ring there.
	const T := preload("res://scripts/tuning.gd")
	var garage: Control
	var slots: Array = []
	var rings_only := false

	func _draw() -> void:
		var g := garage
		var tags: Array = g.get("_tags")
		var rig: Node2D = g.get("preview")
		var selected: int = g.get("selected")
		for i in slots.size():
			var tag: Control = tags[i]
			if not tag.visible:
				continue
			var r := tag.get_global_rect()
			var from := Vector2(r.end.x, r.get_center().y) if int(slots[i].side) == 0 else Vector2(r.position.x, r.get_center().y)
			var to: Vector2 = rig.to_global(g.call("slot_anchor", i))
			var on := i == selected
			var c := T.COL_ORANGE if on else Color(T.COL_CYAN, 0.35)
			if rings_only:
				draw_arc(to, 9.0 if on else 6.0, 0.0, TAU, 20, Color(c, 1.0) if on else Color(T.COL_CYAN, 0.8), 2.5 if on else 2.0)
				continue
			var elbow := Vector2(lerpf(from.x, to.x, 0.3), from.y)
			draw_line(from, elbow, c, 2.0 if on else 1.5)
			draw_line(elbow, to, c, 2.0 if on else 1.5)


class StatSheet extends Control:
	## Armored Core-style readout: every number for the rig as it stands, and
	## what the previewed part would make it (green better, red worse). Speed
	## and acceleration already include any overload penalty. Weapon rows show
	## one weapon (the slot being changed, else the first); DPS adds up all.
	const T := preload("res://scripts/tuning.gd")
	const UI := preload("res://scripts/ui_theme.gd")
	const Loadout := preload("res://scripts/loadout.gd")
	const BulletPool := preload("res://scripts/bullet_pool.gd")
	const ROW_H := 26.0
	# [label, key, higher is better, decimals, suffix]
	const LEFT := [
		["TOP SPEED", "speed", true, 0, ""],
		["ACCELERATION", "accel", true, 0, ""],
		["TURN RATE", "turn", true, 0, " DEG/S"],
		["GRIP", "grip", true, 1, ""],
		["RAM DAMAGE", "ram", true, 0, ""],
		["HP", "hp", true, 0, ""],
		["FRONT ARMOR", "front", true, 0, ""],
		["SIDE ARMOR", "side", true, 0, " EACH"],
		["REAR ARMOR", "rear", true, 0, ""],
		["SHIELD", "shield", true, 0, ""],
	]
	const RIGHT := [
		["DPS (ALL GUNS)", "dps", true, 0, ""],
		["DAMAGE / SHOT", "damage", true, 0, ""],
		["FIRE RATE", "rate", true, 1, " /S"],
		["RANGE", "range", true, 0, ""],
		["SPREAD", "spread", false, 1, " DEG"],
		["TURRET AIM", "aim", true, 0, " DEG/S"],
		["LOCK RANGE", "lock", true, 0, ""],
		["BRAKING", "brake", true, 0, ""],
		["POWER LOAD", "load", false, 0, ""],
		["WEIGHT LOAD", "weight", false, 0, ""],
	]
	# Rows shown as "used / limit": compared by headroom, not the raw load.
	const LIMITS := {"load": "output", "weight": "capacity"}
	# V6.3: an icon per row (rows without one keep the same indent).
	const ROW_ICONS := {"speed": "speed", "accel": "accel", "turn": "drive", "grip": "drive", "ram": "cat_armor",
		"hp": "hp", "front": "armor", "side": "armor", "rear": "armor", "shield": "shield",
		"dps": "dps", "damage": "weapon", "rate": "weapon", "range": "lock", "spread": "dps", "aim": "gunner",
		"lock": "lock", "brake": "drive", "load": "power", "weight": "weight"}
	var _icons: RefCounted = UI.icons()
	var title := ""
	var now := {}
	var after := {}

	func set_data(new_title: String, now_stats: Dictionary, after_stats: Dictionary, weapon := 0) -> void:
		title = new_title
		now = values(now_stats, weapon)
		after = values(after_stats, weapon)
		queue_redraw()

	static func values(s: Dictionary, weapon := 0) -> Dictionary:
		var m := Loadout.mobility(s)
		var weapons: Array = s.get("weapons", [])
		var w: Dictionary = weapons[weapon] if weapon < weapons.size() else {}
		var armed := not w.is_empty()
		var pellets := int(w.get("pellets", 1))
		return {
			"speed": float(s.max_speed) * m,
			"accel": float(s.acceleration) * m,
			"turn": rad_to_deg(float(s.turn_rate)),
			"grip": float(s.grip),
			"brake": float(s.brake),
			"armor": float(s.armor),
			"hp": float(s.get("hp", 0.0)),
			"front": float(s.get("front", 0.0)),
			"side": float(s.get("side", 0.0)),
			"rear": float(s.get("rear", 0.0)),
			"shield": float(s.get("shield", 0.0)),
			"ram": float(s.ram_damage),
			"output": float(s.power_output),
			"dps": Loadout.total_dps(s),
			"damage": float(w.get("bullet_damage", 0.0)) * pellets,
			"pellets": float(pellets) if armed else 0.0,
			"rate": float(w.get("fire_rate", 0.0)) * int(w.get("burst", 1)),
			"range": float(w.get("bullet_speed", 0.0)) * BulletPool.LIFETIME if armed else 0.0,
			"spread": float(w.get("spread_deg", 0.0)) if armed else 0.0,
			"aim": rad_to_deg(float(w.turret_turn_rate)) if armed and int(w.mount) == 0 else -1.0,
			"lock": float(s.lock_range),
			"load": float(s.power_draw),
			"weight": float(s.get("weight", 0.0)),
			"capacity": float(s.get("weight_capacity", 0.0)),
			"mobility": m,
			"weapon": weapon,
			"weapon_count": weapons.size(),
		}

	## "OVER  PWR 110/100  WT 105/100" (whichever apply), or "" within budget.
	static func overload_cause(s: Dictionary) -> String:
		var causes: Array[String] = []
		if float(s.power_output) > 0.0 and float(s.power_draw) > float(s.power_output):
			causes.append("PWR %d/%d" % [roundi(float(s.power_draw)), roundi(float(s.power_output))])
		var cap := float(s.get("weight_capacity", 0.0))
		if cap > 0.0 and float(s.get("weight", 0.0)) > cap:
			causes.append("WT %d/%d" % [roundi(float(s.weight)), roundi(cap)])
		if causes.is_empty():
			return ""
		return "OVER  " + "  ".join(causes)

	func _draw() -> void:
		if now.is_empty():
			return
		var font := get_theme_default_font()
		draw_rect(Rect2(Vector2.ZERO, size), UI.PANEL)
		draw_rect(Rect2(Vector2.ZERO, size), UI.PANEL_EDGE, false, 2.0)
		draw_string(font, Vector2(16, 28), title, HORIZONTAL_ALIGNMENT_LEFT, size.x - 32.0, 17, T.COL_ORANGE)
		var col_w := (size.x - 56.0) / 2.0
		_column(font, LEFT, Vector2(16, 42), col_w)
		_column(font, RIGHT, Vector2(40 + col_w, 42), col_w)
		var count := maxi(int(now.weapon_count), int(after.weapon_count))
		if count > 1:
			draw_string(font, Vector2(40 + col_w, 47), "gun rows show WEAPON %d" % (int(now.weapon) + 1), HORIZONTAL_ALIGNMENT_RIGHT, col_w, 12, UI.TEXT_DIM)
		var m_now: float = now.mobility
		var m_after: float = after.mobility
		var foot := Vector2(16, size.y - 12.0)
		if m_after < 1.0:
			var why: Array[String] = []
			if float(after.output) > 0.0 and float(after.load) > float(after.output):
				why.append("power")
			if float(after.capacity) > 0.0 and float(after.weight) > float(after.capacity):
				why.append("weight")
			draw_string(font, foot, "OVERLOAD (%s): speed and acceleration -%d%%" % [" + ".join(why), roundi((1.0 - m_after) * 100.0)], HORIZONTAL_ALIGNMENT_LEFT, size.x - 32.0, 15, UI.BAD)
		elif m_now < 1.0:
			draw_string(font, foot, "Overload cleared", HORIZONTAL_ALIGNMENT_LEFT, size.x - 32.0, 15, UI.GOOD)

	func _column(font: Font, rows: Array, origin: Vector2, width: float) -> void:
		var y := origin.y
		for r: Array in rows:
			y += ROW_H
			var key: String = r[1]
			var a: float = now[key]
			var b: float = after[key]
			var text_now := _fmt(r, a)
			var text_after := _fmt(r, b)
			var better := (b > a) == bool(r[2])
			if LIMITS.has(key):
				# "used / limit": better means more headroom.
				var limit: String = LIMITS[key]
				text_now = "%d / %d" % [roundi(a), roundi(float(now[limit]))]
				text_after = "%d / %d" % [roundi(b), roundi(float(after[limit]))]
				a = float(now[limit]) - a
				b = float(after[limit]) - b
				better = b > a
			var lx := origin.x
			if _icons.ok():
				_icons.draw(self, str(ROW_ICONS.get(key, "")), Rect2(origin.x, y - 13.0, 16, 16), Color(UI.TEXT_DIM, 0.9))
				lx += 22.0
			draw_string(font, Vector2(lx, y), r[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UI.TEXT_DIM)
			if absf(b - a) < 0.05:
				var over := LIMITS.has(key) and a < 0.0
				draw_string(font, Vector2(origin.x, y), text_now, HORIZONTAL_ALIGNMENT_RIGHT, width, 17, UI.BAD if over else UI.TEXT)
			else:
				var after_w := font.get_string_size(text_after, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
				draw_string(font, Vector2(origin.x, y), text_after, HORIZONTAL_ALIGNMENT_RIGHT, width, 17, UI.GOOD if better else UI.BAD)
				draw_string(font, Vector2(origin.x, y), text_now + "  >", HORIZONTAL_ALIGNMENT_RIGHT, width - after_w - 10.0, 14, UI.TEXT_DIM)
			draw_line(Vector2(origin.x, y + 9.0), Vector2(origin.x + width, y + 9.0), Color(1, 1, 1, 0.06), 1.0)

	static func _fmt(r: Array, v: float) -> String:
		var key: String = r[1]
		if key == "aim" and v < 0.0:
			return "FIXED"
		if key in ["lock", "dps", "range", "damage", "rate"] and v <= 0.0:
			return "NONE"
		var text := "%.1f" % v if int(r[3]) == 1 else "%d" % roundi(v)
		return text + str(r[4])


class PowerMeter extends Control:
	## Armored Core-style budget bars under the rig: power load against the
	## engine's output, weight against the chassis's capacity.
	const T := preload("res://scripts/tuning.gd")
	const UI := preload("res://scripts/ui_theme.gd")
	var used := 0.0
	var output := 0.0
	var weight := 0.0
	var capacity := 0.0

	func set_values(new_used: float, new_output: float, new_weight := 0.0, new_capacity := 0.0) -> void:
		used = new_used
		output = new_output
		weight = new_weight
		capacity = new_capacity
		queue_redraw()

	func _draw() -> void:
		var gap := 24.0
		var w := (size.x - gap) * 0.5
		_bar(Rect2(0, 0, w, size.y), "POWER LOAD", used, output, Color(0.95, 0.85, 0.4))
		_bar(Rect2(w + gap, 0, w, size.y), "WEIGHT LOAD", weight, capacity, Color(0.7, 0.78, 0.85))

	func _bar(area: Rect2, label: String, value: float, limit: float, tint: Color) -> void:
		if limit <= 0.0:
			return
		var font := get_theme_default_font()
		var over := value > limit
		var color := UI.BAD if over else tint
		draw_string(font, area.position + Vector2(0, 16), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UI.TEXT_DIM)
		var right := "%d / %d%s" % [roundi(value), roundi(limit), "  OVER" if over else ""]
		draw_string(font, area.position + Vector2(0, 16), right, HORIZONTAL_ALIGNMENT_RIGHT, area.size.x, 15, color)
		var bar := Rect2(area.position + Vector2(0, 24), Vector2(area.size.x, 16))
		draw_rect(bar, Color(0, 0, 0, 0.5))
		var fill := minf(value / limit, 1.0) * (bar.size.x - 4.0)
		draw_rect(Rect2(bar.position + Vector2(2, 2), Vector2(fill, bar.size.y - 4.0)), color)
		draw_rect(bar, Color(UI.PANEL_EDGE, 1.0), false, 1.0)


class RigTouch extends Control:
	## Drag sideways to turn the rig; tap to pick the nearest slot on it.
	var garage: Control
	var _down_at := Vector2.ZERO
	var _moved := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.button_index != MOUSE_BUTTON_LEFT:
				return
			if mb.pressed:
				_down_at = mb.global_position
				_moved = 0.0
			elif _moved < 12.0:
				garage.call("tap_rig", mb.global_position)
		elif event is InputEventMouseMotion and (event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT:
			var mm := event as InputEventMouseMotion
			_moved += mm.relative.length()
			garage.call("rotate_rig", mm.relative.x * 0.012)


class FloorGrid extends Control:
	## Shop floor under the rig: a faint grid and a turntable ring.
	const T := preload("res://scripts/tuning.gd")

	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		var step := 48.0
		var x := 0.0
		while x < size.x:
			draw_line(Vector2(x, 96), Vector2(x, size.y), Color(1, 1, 1, 0.025), 1.0)
			x += step
		var y := 96.0
		while y < size.y:
			draw_line(Vector2(0, y), Vector2(size.x, y), Color(1, 1, 1, 0.025), 1.0)
			y += step
		var c := Vector2(size.x * 0.5, 290.0)
		draw_circle(c, 150.0, Color(0, 0, 0, 0.25))
		draw_arc(c, 150.0, 0.0, TAU, 64, Color(T.COL_CYAN, 0.18), 2.0)
		draw_arc(c, 158.0, 0.0, TAU, 64, Color(T.COL_ORANGE, 0.12), 1.0)


## The garage's menu: settings, the Database, quit.
func open_menu() -> GameMenu:
	if menu != null:
		return menu
	menu = GameMenu.new()
	menu.setup(profile, false)
	menu.closed.connect(func() -> void: menu = null)
	menu.tutorial_requested.connect(start_tutorial)
	add_child(menu)
	return menu


## The phone's back button steps back one level, like Circle: the menu,
## then an open panel, the part sheet, a station, and last opens MENU.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		go_back()


## Esc on a PC is the back button.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo and (event as InputEventKey).keycode == KEY_ESCAPE:
		go_back()
		get_viewport().set_input_as_handled()


func go_back() -> void:
	if menu != null:
		menu.back()
		return
	var pad := get_node_or_null("/root/Pad")
	var modal: Control = pad.call("top_modal") if pad != null else null
	if modal != null and modal.has_meta("pad_close"):
		(modal.get_meta("pad_close") as Callable).call()
	elif selected >= 0:
		close_sheet()
	elif tab != "GARAGE":
		show_tab("GARAGE")
	else:
		open_menu()


## The optional tutorial (MENU): the Training Run, then the garage tour.
func start_tutorial() -> void:
	if profile.tour_active:
		return
	profile.tutorial_active = true
	get_tree().change_scene_to_file(MISSION_SCENE)


func start_tour() -> GarageTour:
	if tour != null or not profile.tour_active:
		return tour
	close_sheet()
	tour = GarageTour.new()
	tour.garage = self
	tour.profile = profile
	tour.finished.connect(func() -> void: tour = null)
	add_child(tour)
	return tour


# --- Controller (pad.gd) ------------------------------------------------------------
# D-pad / left stick move between buttons, Cross presses, Circle backs out
# (closes the part sheet, or returns to the garage from a station), L1 / R1
# switch stations, Options opens MENU.

func _hint_text() -> String:
	return PadScript.hint("Tap a slot to change parts.  Drag the rig to turn it.",
		"D-pad: pick a slot.   Cross: change parts.   L1 / R1: stations.   Options: menu.")


func _sheet_title_text(slot: Dictionary) -> String:
	return "%s   -   %s    (scrap %d)" % [slot.label, PadScript.hint("tap a part to compare, tap again to fit it", "Cross on a part to compare, again to fit it"), profile.scrap]


## Touch <-> controller: swap the wording on screen.
func _on_pad_mode(_on: bool) -> void:
	_hint.text = _hint_text()
	_refresh_tags()
	if selected >= 0:
		_sheet_title.text = _sheet_title_text(SLOTS[selected])
		for c in _cards.get_children():
			if c is PartCard:
				_style_card(c as PartCard)


func pad_button(button: int) -> bool:
	match button:
		JOY_BUTTON_START:
			open_menu()
		JOY_BUTTON_B:
			if selected >= 0:
				close_sheet()
			elif tab != "GARAGE":
				show_tab("GARAGE")
			else:
				return false
		JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER:
			var i := TABS.find(tab)
			var step := -1 if button == JOY_BUTTON_LEFT_SHOULDER else 1
			show_tab(TABS[wrapi(i + step, 0, TABS.size())])
		_:
			return false
	return true
