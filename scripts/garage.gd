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
const Loadout := preload("res://scripts/loadout.gd")
const Vehicle := preload("res://scripts/vehicle.gd")
const UI := preload("res://scripts/ui_theme.gd")
const ProfileScript := preload("res://scripts/profile.gd")
const Comms := preload("res://scripts/comms.gd")
const Missions := preload("res://scripts/missions.gd")
const MISSION_SCENE := "res://scenes/mission.tscn"

# Slot tags: the loadout slot, where its line points on the rig (rig-local
# pixels), and which screen side the tag sits on (0 left, 1 right).
const SLOTS := [
	{"key": "chassis", "index": 0, "label": "CHASSIS", "category": "Chassis", "anchor": Vector2(-6, 15), "side": 0},
	{"key": "engine", "index": 0, "label": "ENGINE", "category": "Engine", "anchor": Vector2(-25, 0), "side": 0},
	{"key": "drive", "index": 0, "label": "DRIVE", "category": "Drive", "anchor": Vector2(-17, 18), "side": 0},
	{"key": "armor", "index": 0, "label": "ARMOR", "category": "Armor", "anchor": Vector2(28, 0), "side": 0},
	{"key": "weapons", "index": 0, "label": "WEAPON", "category": "Weapon", "anchor": Vector2(-4, 0), "side": 1},
	{"key": "internal", "index": 0, "label": "INTERNAL 1", "category": "Internal", "anchor": Vector2(-27, 0), "side": 1},
	{"key": "internal", "index": 1, "label": "INTERNAL 2", "category": "Internal", "anchor": Vector2(-12, -7), "side": 1},
	{"key": "utility", "index": 0, "label": "UTILITY", "category": "Utility", "anchor": Vector2(14, -12), "side": 1},
]
const REQUIRED := ["chassis", "engine", "drive"]
const TABS := ["GARAGE", "RESEARCH", "SALOON", "INN", "COMMS"]
const COMING_SOON := {
	"RESEARCH": "Spend scrap to level up your schematics. Higher levels, better parts.",
	"SALOON": "Hire crew and buy new schematics.",
	"INN": "Rest injured crew and send your reserves out on expeditions.",
	"COMMS": "Pick the day's mission from the board.",
}

const TAG_SIZE := Vector2(272, 70)
const TAG_TOP := 108.0
const TAG_GAP := 8.0
const RIG_SCALE := 3.4
const FOOTER_H := 72.0
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
var _job: Label


func _ready() -> void:
	profile = get_node("/root/Profile")
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

	_toast = UI.label("", 22, T.COL_ORANGE)
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


func _process(_delta: float) -> void:
	_callouts.queue_redraw()
	_rings.queue_redraw()


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
	_rig_holder.visible = not on
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
	toast("Fitted: " + (str(Parts.get_part(id).name) if id != "" else "slot emptied"))
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


## Launch today's job. No job yet: off to Comms to pick one.
func deploy() -> void:
	if not profile.has_rig():
		return
	if not profile.has_mission():
		show_tab("COMMS")
		toast("Take a job in Comms first")
		return
	get_tree().change_scene_to_file(MISSION_SCENE)


## Switch station: GARAGE, COMMS, or a placeholder for the others.
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
		var d := at.distance_to(preview.to_global(SLOTS[i].anchor))
		if d < best_d:
			best_d = d
			best = i
	if best >= 0:
		open_slot(best)


func toast(text: String, seconds := 2.2) -> void:
	_toast.text = text
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

	_job = UI.label("", 20, T.COL_ORANGE)
	_job.anchor_right = 1.0
	_job.anchor_top = 1.0
	_job.anchor_bottom = 1.0
	_job.offset_top = -(FOOTER_H + 82.0)
	_job.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_job)

	_hint = UI.label("Tap a slot to change parts.  Drag the rig to turn it.", 18, UI.TEXT_DIM)
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
	bar.offset_left = -760.0
	bar.offset_right = -20.0
	bar.offset_top = 10.0
	bar.offset_bottom = 60.0
	bar.alignment = BoxContainer.ALIGNMENT_END
	bar.add_theme_constant_override("separation", 10)
	add_child(bar)

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


func _build_tags() -> void:
	var row := [0, 0]
	for i in SLOTS.size():
		var slot: Dictionary = SLOTS[i]
		var tag := SlotTag.new()
		tag.side = slot.side
		tag.slot_label = slot.label
		var y: float = TAG_TOP + int(row[slot.side]) * (TAG_SIZE.y + TAG_GAP)
		row[slot.side] += 1
		if slot.side == 0:
			tag.offset_left = 20.0
			tag.offset_right = 20.0 + TAG_SIZE.x
		else:
			tag.anchor_left = 1.0
			tag.anchor_right = 1.0
			tag.offset_left = -20.0 - TAG_SIZE.x
			tag.offset_right = -20.0
		tag.offset_top = y
		tag.offset_bottom = y + TAG_SIZE.y
		tag.pressed.connect(open_slot.bind(i))
		add_child(tag)
		_tags.append(tag)


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
		_job.text = "JOB:  %s  -  %s     THREAT %d     PAYS %d" % [Missions.label(m), str(m.name), int(m.threat), int(m.reward)]
	else:
		_job.text = "No job taken. Open COMMS to pick today's job."
	_job.visible = selected < 0
	var has_rig := profile.has_rig()
	var shown: Dictionary = profile.rig
	var any_part := not profile.parts_in(profile.rig).is_empty()
	if not any_part and profile.is_complete(profile.plan):
		shown = profile.plan  # ghost of the rig you lost
	var stats := Loadout.build(shown)
	preview.apply_stats(stats)
	preview.modulate.a = 1.0 if has_rig else 0.3
	var built := Loadout.build(profile.rig)
	_stats_label.text = _stats_line(built, has_rig)
	_power_meter.set_values(float(built.power_draw), float(built.power_output))
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
	if not has_rig:
		_no_rig.text = "NO RIG\nRebuild your last build, or fit parts slot by slot. Common parts are free."
	_refresh_tags()
	if selected >= 0:
		_fill_sheet()


func _stats_line(s: Dictionary, complete: bool) -> String:
	if not complete:
		var missing: Array[String] = []
		for key: String in REQUIRED:
			if str(profile.rig.get(key, "")) == "":
				missing.append(key.to_upper())
		return "Needs " + ", ".join(missing) + " to deploy"
	var dps := float(s.fire_rate) * float(s.bullet_damage)
	var lock := "LOCK %d" % int(s.lock_range) if float(s.lock_range) > 0.0 else "NO LOCK"
	var power := "POWER %d/%d" % [int(s.power_draw), int(s.power_output)]
	if float(s.power_draw) > float(s.power_output):
		power += "  OVERLOAD"
	return "ARMOR %d    SPEED %d    ACCEL %d    GRIP %.1f    DPS %d    %s    %s" % [
		int(s.armor), int(s.max_speed), int(s.acceleration), float(s.grip), roundi(dps), lock, power]


func _refresh_tags() -> void:
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
			tag.detail = "REQUIRED" if tag.required else "Tap to fit a part"
		else:
			var part := Parts.get_part(id)
			tag.part_name = part.name
			tag.detail = "%s    PWR %d" % [part.rarity, int(part.power)] if not part.has("power_output") \
				else "%s    OUTPUT %d" % [part.rarity, int(part.power_output)]
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
	_sheet_title.text = "%s   -   tap a part to compare, tap again to fit it    (scrap %d)" % [slot.label, profile.scrap]

	var ids: Array[String] = []
	for id in profile.schematics:
		if Parts.get_part(id).category == slot.category:
			ids.append(id)
	ids.sort_custom(func(a: String, b: String) -> bool:
		return (a == current and b != current) or (a != current and b != current and int(Parts.get_part(a).cost) < int(Parts.get_part(b).cost)))
	if ids.is_empty():
		var none := UI.label("No %s schematics yet. Find them in missions, or buy them at the Saloon." % slot.category.to_lower(), 20, UI.TEXT_DIM)
		_cards.add_child(none)
		_update_stat_sheet()
		return

	var now := Loadout.build(profile.rig)
	for id in ids:
		_cards.add_child(_make_card(slot, id, current, now))
	if current != "" and not REQUIRED.has(slot.key):
		_cards.add_child(_make_card(slot, "", current, now))
	_update_stat_sheet()


func _update_stat_sheet() -> void:
	if selected < 0:
		return
	var slot: Dictionary = SLOTS[selected]
	var now := Loadout.build(profile.rig)
	var after := Loadout.build(profile.with_part(profile.rig, slot.key, slot.index, _preview))
	var name_now := _slot_part(slot)
	var title := "%s:  %s" % [slot.label, Parts.get_part(name_now).name if name_now != "" else "Empty"]
	if _preview != name_now:
		title += "   >   " + (str(Parts.get_part(_preview).name) if _preview != "" else "Empty")
	_stat_sheet.set_data(title, now, after)

func _make_card(slot: Dictionary, id: String, current: String, now: Dictionary) -> PartCard:
	var card := PartCard.new()
	card.part_id = id
	var candidate := profile.with_part(profile.rig, slot.key, slot.index, id)
	var after := Loadout.build(candidate)
	var cost := profile.build_cost(candidate)
	card.cost = cost
	card.selected = id == _preview
	if id == "":
		card.title = "Remove"
		card.subtitle = "Back to storage"
		card.rarity_color = UI.TEXT_DIM
	else:
		var part := Parts.get_part(id)
		card.title = part.name
		card.subtitle = "%s %s" % [part.rarity, part.category]
		card.rarity_color = Parts.color_of(part)
		card.headline = _headline(part)
	if id == current:
		card.installed = true
	else:
		card.deltas = _deltas(now, after)
		if float(after.power_draw) > float(after.power_output) and float(after.power_output) > 0.0:
			card.warning = "OVERLOAD  %d / %d" % [int(after.power_draw), int(after.power_output)]
	_style_card(card)
	card.pressed.connect(press_card.bind(id))
	return card


## Status line on a card: what a tap (or a second tap) would do.
func _style_card(card: PartCard) -> void:
	var again := "TAP AGAIN:  " if card.selected else ""
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
			return "ARMOR %d  SPD %d  SLOTS %d/%d/%d" % [int(part.armor), int(part.max_speed), int(part.hardpoints), int(part.internal_slots), int(part.utility_slots)]
		"Engine":
			return "OUTPUT %d  ACCEL %d" % [int(part.power_output), int(part.acceleration)]
		"Drive":
			return "PWR %d  GRIP %.1f  SPD x%.2f" % [int(part.power), float(part.grip), float(part.speed_mult)]
		"Armor":
			return "ARMOR +%d  RAM %d" % [int(part.armor), int(part.ram_damage)]
		"Weapon":
			var dps := float(part.fire_rate) * float(part.bullet_damage)
			var aim := "TURRET" if int(part.mount) == 0 else "FIXED"
			return "PWR %d  DPS %d  %s%s" % [int(part.power), roundi(dps), aim, "  LOCK" if float(part.lock_range) > 0.0 else ""]
		"Internal":
			return "PWR %d%s" % [int(part.power), "  ENABLES LOCK" if part.get("enables_lock", false) else ""]
	return "PWR %d" % int(part.get("power", 0))


## Up to four "+/-" changes this swap would make, worst first so costs show.
## Same numbers as the stat sheet, so speed and accel include any overload.
func _deltas(now_stats: Dictionary, after_stats: Dictionary) -> Array:
	var now := StatSheet.values(now_stats)
	var after := StatSheet.values(after_stats)
	var out: Array = []
	var rows := [
		["PWR", "load", false, 0],
		["ARMOR", "armor", true, 0],
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
	body.add_child(UI.label("Save your current rig, or switch to a saved one. Parts you don't have are built for scrap.", 18, UI.TEXT_DIM))
	for i in T.PRESET_COUNT:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var p := profile.preset(i)
		var name_label := UI.label("P%d" % (i + 1), 24, T.COL_CYAN)
		name_label.custom_minimum_size = Vector2(44, 0)
		row.add_child(name_label)
		var summary := UI.label(_summary(p) if not p.is_empty() else "Empty", 18, UI.TEXT if not p.is_empty() else UI.TEXT_DIM)
		summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		summary.clip_text = true
		summary.custom_minimum_size = Vector2(380, 0)
		row.add_child(summary)
		var save := _button("SAVE", 110)
		save.disabled = not profile.has_rig()
		save.pressed.connect(func() -> void:
			profile.save_preset(i)
			toast("Saved to P%d" % (i + 1))
			_open_presets())
		row.add_child(save)
		var cost := profile.build_cost(p) if not p.is_empty() else 0
		var load_button := _button("LOAD" if cost == 0 else "LOAD  %d" % cost, 150)
		load_button.disabled = p.is_empty() or cost > profile.scrap or p == profile.rig
		load_button.pressed.connect(func() -> void:
			if profile.load_preset(i):
				toast("Loaded P%d" % (i + 1))
			_close_overlay())
		row.add_child(load_button)
		body.add_child(row)
	_open_overlay("PRESETS", body)


func _summary(loadout: Dictionary) -> String:
	var names: Array[String] = []
	for key: String in ["weapons", "drive", "armor", "internal", "utility"]:
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
	_comms.visible = tab_name == "COMMS"
	if tab_name == "GARAGE":
		_close_overlay()
		return
	if tab_name == "COMMS":
		_close_overlay()
		close_sheet()
		_comms.selected = -1
		_comms.refresh()
		_highlight_tab("COMMS")
		return
	var body := VBoxContainer.new()
	body.add_child(UI.label(COMING_SOON[tab_name], 22, UI.TEXT))
	body.add_child(UI.label("Coming soon.", 20, UI.TEXT_DIM))
	_open_overlay(tab_name, body)
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
		draw_rect(Rect2(size.x - 4.0 if side == 0 else 0.0, 0.0, 4.0, size.y), a)
		draw_string(font, Vector2(14, 20), slot_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UI.TEXT_DIM)
		draw_string(font, Vector2(14, 45), part_name, HORIZONTAL_ALIGNMENT_LEFT, size.x - 26.0, 21, UI.TEXT_DIM if empty else UI.TEXT)
		draw_string(font, Vector2(14, 63), detail, HORIZONTAL_ALIGNMENT_LEFT, size.x - 26.0, 14, Color(a, 0.9))


class PartCard extends Button:
	## One part in the bottom sheet: what it is, what it changes, what it costs.
	const T := preload("res://scripts/tuning.gd")
	const UI := preload("res://scripts/ui_theme.gd")
	var title := ""
	var subtitle := ""
	var headline := ""
	var deltas: Array = []          # [text, better] pairs
	var status := ""
	var status_color := Color.WHITE
	var warning := ""
	var rarity_color := Color.WHITE
	var installed := false
	var selected := false          # previewed on the stat sheet
	var part_id := ""
	var cost := 0

	func _ready() -> void:
		flat = true
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = Vector2(262, 176)
		action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE

	func _draw() -> void:
		var font := get_theme_default_font()
		var fill := Color(0.12, 0.12, 0.13)
		if installed:
			fill = Color(0.08, 0.14, 0.15)
		elif get_draw_mode() == DRAW_PRESSED:
			fill = Color(0.2, 0.13, 0.08)
		draw_rect(Rect2(Vector2.ZERO, size), fill)
		draw_rect(Rect2(0, 0, size.x, 5), rarity_color)
		if selected:
			draw_rect(Rect2(Vector2.ZERO, size), T.COL_ORANGE, false, 3.0)
		else:
			draw_rect(Rect2(Vector2.ZERO, size), Color(rarity_color, 0.35), false, 2.0)
		var dim := 0.45 if disabled else 1.0
		draw_string(font, Vector2(12, 30), title, HORIZONTAL_ALIGNMENT_LEFT, size.x - 24.0, 19, Color(UI.TEXT, dim))
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
			var to := rig.to_global(slots[i].anchor)
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
	## and acceleration already include any overload penalty.
	const T := preload("res://scripts/tuning.gd")
	const UI := preload("res://scripts/ui_theme.gd")
	const Loadout := preload("res://scripts/loadout.gd")
	const BulletPool := preload("res://scripts/bullet_pool.gd")
	const ROW_H := 29.0
	# [label, key, higher is better, decimals, suffix]
	const LEFT := [
		["TOP SPEED", "speed", true, 0, ""],
		["ACCELERATION", "accel", true, 0, ""],
		["TURN RATE", "turn", true, 0, " DEG/S"],
		["GRIP", "grip", true, 1, ""],
		["BRAKING", "brake", true, 0, ""],
		["ARMOR", "armor", true, 0, ""],
		["RAM DAMAGE", "ram", true, 0, ""],
		["POWER OUTPUT", "output", true, 0, ""],
	]
	const RIGHT := [
		["DPS", "dps", true, 0, ""],
		["DAMAGE / SHOT", "damage", true, 0, ""],
		["FIRE RATE", "rate", true, 1, " /S"],
		["RANGE", "range", true, 0, ""],
		["SPREAD", "spread", false, 1, " DEG"],
		["TURRET AIM", "aim", true, 0, " DEG/S"],
		["LOCK RANGE", "lock", true, 0, ""],
		["POWER LOAD", "load", false, 0, ""],
	]
	var title := ""
	var now := {}
	var after := {}

	func set_data(new_title: String, now_stats: Dictionary, after_stats: Dictionary) -> void:
		title = new_title
		now = values(now_stats)
		after = values(after_stats)
		queue_redraw()

	static func values(s: Dictionary) -> Dictionary:
		var m := Loadout.mobility_factor(float(s.power_draw), float(s.power_output))
		var armed := float(s.fire_rate) > 0.0
		return {
			"speed": float(s.max_speed) * m,
			"accel": float(s.acceleration) * m,
			"turn": rad_to_deg(float(s.turn_rate)),
			"grip": float(s.grip),
			"brake": float(s.brake),
			"armor": float(s.armor),
			"ram": float(s.ram_damage),
			"output": float(s.power_output),
			"dps": float(s.fire_rate) * float(s.bullet_damage),
			"damage": float(s.bullet_damage),
			"rate": float(s.fire_rate),
			"range": float(s.bullet_speed) * BulletPool.LIFETIME if armed else 0.0,
			"spread": float(s.spread_deg) if armed else 0.0,
			"aim": rad_to_deg(float(s.turret_turn_rate)) if int(s.mount) == 0 and armed else -1.0,
			"lock": float(s.lock_range),
			"load": float(s.power_draw),
			"mobility": m,
		}

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
		var m_now: float = now.mobility
		var m_after: float = after.mobility
		var foot := Vector2(16, size.y - 12.0)
		if m_after < 1.0:
			draw_string(font, foot, "OVERLOAD: speed and acceleration -%d%%" % roundi((1.0 - m_after) * 100.0), HORIZONTAL_ALIGNMENT_LEFT, size.x - 32.0, 15, UI.BAD)
		elif m_now < 1.0:
			draw_string(font, foot, "Overload cleared", HORIZONTAL_ALIGNMENT_LEFT, size.x - 32.0, 15, UI.GOOD)

	func _column(font: Font, rows: Array, origin: Vector2, width: float) -> void:
		var y := origin.y
		for r: Array in rows:
			y += ROW_H
			var key: String = r[1]
			var a: float = now[key]
			var b: float = after[key]
			draw_string(font, Vector2(origin.x, y), r[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UI.TEXT_DIM)
			if absf(b - a) < 0.05:
				draw_string(font, Vector2(origin.x, y), _fmt(r, a), HORIZONTAL_ALIGNMENT_RIGHT, width, 17, UI.TEXT)
			else:
				var better := (b > a) == bool(r[2])
				var text_after := _fmt(r, b)
				var after_w := font.get_string_size(text_after, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
				draw_string(font, Vector2(origin.x, y), text_after, HORIZONTAL_ALIGNMENT_RIGHT, width, 17, UI.GOOD if better else UI.BAD)
				draw_string(font, Vector2(origin.x, y), _fmt(r, a) + "  >", HORIZONTAL_ALIGNMENT_RIGHT, width - after_w - 10.0, 14, UI.TEXT_DIM)
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
	## Big Armored Core-style energy load bar under the rig.
	const T := preload("res://scripts/tuning.gd")
	const UI := preload("res://scripts/ui_theme.gd")
	var used := 0.0
	var output := 0.0

	func set_values(new_used: float, new_output: float) -> void:
		used = new_used
		output = new_output
		queue_redraw()

	func _draw() -> void:
		if output <= 0.0:
			return
		var font := get_theme_default_font()
		var over := used > output
		var color := UI.BAD if over else Color(0.95, 0.85, 0.4)
		draw_string(font, Vector2(0, 16), "POWER LOAD", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UI.TEXT_DIM)
		var right := "%d / %d%s" % [roundi(used), roundi(output), "   OVERLOAD" if over else ""]
		draw_string(font, Vector2(0, 16), right, HORIZONTAL_ALIGNMENT_RIGHT, size.x, 16, color)
		var bar := Rect2(0, 24, size.x, 16)
		draw_rect(bar, Color(0, 0, 0, 0.5))
		var fill := minf(used / output, 1.0) * (bar.size.x - 4.0)
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
