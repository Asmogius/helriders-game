extends Control
## The Research station (DESIGN §4, §5): spend scrap to level schematics you
## own. Tap a schematic on the left to see what the next level does on the
## right, then LEVEL UP. Levels are instant but capped per day; the station's
## upgrades (Bench Discount, Second Shift) make them cheaper and raise the cap.
## Rules live in profile.gd, numbers in tuning.gd, the per-level math in
## Parts.at_level.

const T := preload("res://scripts/tuning.gd")
const UI := preload("res://scripts/ui_theme.gd")
const Parts := preload("res://scripts/parts.gd")
const ProfileScript := preload("res://scripts/profile.gd")

const CATEGORY_ORDER := ["Chassis", "Engine", "Drive", "Armor", "Weapon", "Internal", "Utility"]
const RARITY_ORDER := ["Common", "Uncommon", "Rare", "Epic", "Legendary"]
const LIST_W := 600.0
const ROW_H := 62.0

var profile: ProfileScript
var selected := ""        # schematic id shown on the right

var _title: Label
var _info: Label
var _rows: VBoxContainer
var _name: Label
var _kind: Label
var _level: Label
var _stats: VBoxContainer
var _note: Label
var _level_up: Button
var _upgrades: Control


func _ready() -> void:
	profile = get_node("/root/Profile")
	var bg := ColorRect.new()
	bg.color = Color(0.075, 0.075, 0.085)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_title = UI.label("", 30, T.COL_CYAN)
	_title.position = Vector2(24, 14)
	add_child(_title)
	_info = UI.label("", 22, T.COL_ORANGE)
	_info.position = Vector2(24, 54)
	add_child(_info)

	var bar := HBoxContainer.new()
	bar.anchor_left = 1.0
	bar.anchor_right = 1.0
	bar.offset_left = -400.0
	bar.offset_right = -20.0
	bar.offset_top = 10.0
	bar.offset_bottom = 60.0
	bar.alignment = BoxContainer.ALIGNMENT_END
	add_child(bar)
	var upgrades := _button("UPGRADES", 170)
	upgrades.pressed.connect(open_upgrades)
	bar.add_child(upgrades)

	# Left: every schematic you own.
	var scroll := ScrollContainer.new()
	scroll.anchor_bottom = 1.0
	scroll.offset_left = 20.0
	scroll.offset_right = 20.0 + LIST_W
	scroll.offset_top = 96.0
	scroll.offset_bottom = -12.0
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.scroll_deadzone = 14
	add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.custom_minimum_size = Vector2(LIST_W - 16.0, 0)
	_rows.add_theme_constant_override("separation", 8)
	scroll.add_child(_rows)

	# Right: the selected schematic, now and at the next level.
	var panel := PanelContainer.new()
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 40.0 + LIST_W
	panel.offset_right = -20.0
	panel.offset_top = 96.0
	panel.offset_bottom = -12.0
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	_name = UI.label("", 28, UI.TEXT)
	column.add_child(_name)
	_kind = UI.label("", 18, UI.TEXT_DIM)
	column.add_child(_kind)
	_level = UI.label("", 24, T.COL_CYAN)
	column.add_child(_level)
	_stats = VBoxContainer.new()
	_stats.add_theme_constant_override("separation", 4)
	_stats.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_stats)
	_note = UI.label("", 17, UI.TEXT_DIM)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD
	column.add_child(_note)
	_level_up = _button("LEVEL UP", 0)
	_level_up.custom_minimum_size = Vector2(0, 58)
	UI.accent(_level_up, T.COL_ORANGE)
	_level_up.pressed.connect(level_selected)
	column.add_child(_level_up)

	profile.changed.connect(refresh)
	refresh()


# --- Actions (also used by tests) ------------------------------------------------

func select(id: String) -> void:
	selected = id
	refresh()


## Level the selected schematic up by one. Returns success.
func level_selected() -> bool:
	var ok := selected != "" and profile.research(selected)
	refresh()
	return ok


## Owned schematics in display order: by category, then rarity, then name.
func schematic_ids() -> Array[String]:
	var ids: Array[String] = []
	for id in profile.schematics:
		ids.append(id)
	ids.sort_custom(func(a: String, b: String) -> bool:
		var pa := Parts.get_part(a)
		var pb := Parts.get_part(b)
		var ca := CATEGORY_ORDER.find(str(pa.category))
		var cb := CATEGORY_ORDER.find(str(pb.category))
		if ca != cb:
			return ca < cb
		var ra := RARITY_ORDER.find(str(pa.rarity))
		var rb := RARITY_ORDER.find(str(pb.rarity))
		if ra != rb:
			return ra < rb
		return str(pa.name) < str(pb.name))
	return ids


# --- Refresh ---------------------------------------------------------------------

func refresh() -> void:
	if not is_inside_tree():
		return
	_title.text = "RESEARCH   -   DAY %d" % profile.day
	_info.text = "SCRAP  %d      LEVELS TODAY  %d / %d      DISTRICT SCORE  %d" % [
		profile.scrap, profile.research_today, profile.research_cap(), profile.district_score()]
	var ids := schematic_ids()
	if selected == "" or not ids.has(selected):
		selected = _first_levelable(ids)
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	for id in ids:
		_rows.add_child(_make_row(id))
	_fill_detail()


func _first_levelable(ids: Array[String]) -> String:
	for id in ids:
		if profile.research_cost(id) >= 0:
			return id
	return ids[0] if not ids.is_empty() else ""


func _make_row(id: String) -> Button:
	var part := Parts.get_part(id)
	var row := _button("", 0)
	row.custom_minimum_size = Vector2(0, ROW_H)
	if id == selected:
		UI.accent(row, T.COL_CYAN)
	row.pressed.connect(select.bind(id))
	var line := HBoxContainer.new()
	line.set_anchors_preset(Control.PRESET_FULL_RECT)
	line.offset_left = 14.0
	line.offset_right = -14.0
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", 10)
	row.add_child(line)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_theme_constant_override("separation", 0)
	line.add_child(text)
	var name_label := UI.label(str(part.name), 21, Parts.color_of(part))
	name_label.clip_text = true
	text.add_child(name_label)
	text.add_child(UI.label("%s %s" % [part.rarity, part.category], 15, UI.TEXT_DIM))
	var level := profile.part_level(id)
	var right := VBoxContainer.new()
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_theme_constant_override("separation", 0)
	line.add_child(right)
	var lv := UI.label("LV %d / %d" % [level, Parts.max_level(part)], 20, T.COL_CYAN)
	lv.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(lv)
	var cost := profile.research_cost(id)
	var status := ""
	var color := UI.TEXT_DIM
	if not Parts.can_level(part):
		status = "NO LEVELS"
	elif cost < 0:
		status = "MAXED"
		color = UI.GOOD
	else:
		status = "NEXT  %d" % cost
		color = T.COL_ORANGE if cost <= profile.scrap else UI.BAD
	var st := UI.label(status, 15, color)
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(st)
	return row


func _fill_detail() -> void:
	for c in _stats.get_children():
		_stats.remove_child(c)
		c.queue_free()
	if selected == "":
		_name.text = "No schematics"
		_kind.text = ""
		_level.text = ""
		_note.text = ""
		_level_up.disabled = true
		_level_up.text = "LEVEL UP"
		return
	var base := Parts.get_part(selected)
	var level := profile.part_level(selected)
	var top := Parts.max_level(base)
	var now := Parts.at_level(base, level)
	_name.text = str(base.name)
	_name.add_theme_color_override("font_color", Parts.color_of(base))
	_kind.text = "%s %s    PWR %d    WT %d    (power and weight never change)" % [
		base.rarity, base.category, int(base.get("power", 0)), int(base.get("weight", 0))]
	var can := Parts.can_level(base)
	var maxed := level >= top
	_level.text = "LEVEL %d / %d" % [level, top] + ("" if maxed or not can else "   >   %d" % (level + 1))
	var next := Parts.at_level(base, level + 1) if can and not maxed else now
	for row: Array in stat_rows(now, next):
		var line := HBoxContainer.new()
		var key := UI.label(str(row[0]), 20, UI.TEXT_DIM)
		key.custom_minimum_size = Vector2(190, 0)
		line.add_child(key)
		line.add_child(UI.label(str(row[1]), 20, UI.TEXT))
		if str(row[2]) != str(row[1]):
			line.add_child(UI.label("   >   " + str(row[2]), 20, UI.GOOD))
		_stats.add_child(line)

	var notes: Array[String] = []
	if not can:
		notes.append("Nothing on this part has a number to improve.")
	elif maxed:
		notes.append("Max level for a %s part." % str(base.rarity))
	if Parts.STARTER_SCHEMATICS.has(selected):
		notes.append("Starter schematics don't count toward districts.")
	elif can and not maxed:
		notes.append("Next level: district score +%d." % int(T.RARITY_POINTS.get(str(base.rarity), 0)))
	var bonus: Dictionary = base.get("legendary_bonus", {})
	if not bonus.is_empty():
		var got := level >= int(bonus.get("at", 999))
		notes.append("%s at level %d: %s" % ["UNLOCKED" if got else "Legendary bonus", int(bonus.get("at", 0)), str(bonus.get("text", ""))])
	_note.text = "  ".join(notes)

	var block := profile.research_block(selected)
	_level_up.disabled = block != ""
	_level_up.text = "LEVEL UP  -  %d SCRAP" % profile.research_cost(selected) if block == "" else block


## [label, now, next] text rows for every number Research can change.
static func stat_rows(now: Dictionary, next: Dictionary) -> Array:
	var rows: Array = []
	var flat := [
		["armor", "ARMOR"], ["weight_capacity", "WEIGHT CAP"], ["power_output", "POWER OUTPUT"],
		["acceleration", "ACCEL"], ["grip", "GRIP"], ["bullet_damage", "DAMAGE"],
		["armor_bonus", "ARMOR BONUS"], ["ram_bonus", "RAM BONUS"],
	]
	for f: Array in flat:
		if now.has(f[0]):
			rows.append([f[1], _num(float(now[f[0]])), _num(float(next[f[0]]))])
	if now.has("bullet_damage"):
		rows.append(["DPS", _num(_dps(now)), _num(_dps(next))])
	if now.has("turn_mult"):
		rows.append(["TURN", "x%.2f" % float(now.turn_mult), "x%.2f" % float(next.turn_mult)])
	var mults := [["fire_rate_mult", "FIRE RATE"], ["damage_mult", "DAMAGE"], ["lock_range_mult", "LOCK RANGE"], ["turret_aim_mult", "TURRET AIM"]]
	for m: Array in mults:
		if now.has(m[0]):
			rows.append([m[1], _pct(float(now[m[0]]) - 1.0), _pct(float(next[m[0]]) - 1.0)])
	if now.has("injury_mult"):
		rows.append(["CREW INJURY", _pct(float(now.injury_mult) - 1.0), _pct(float(next.injury_mult) - 1.0)])
	if now.has("cooldown"):
		rows.append(["COOLDOWN", "%.1fs" % float(now.cooldown), "%.1fs" % float(next.cooldown)])
	return rows


static func _dps(p: Dictionary) -> float:
	return float(p.get("fire_rate", 0.0)) * float(p.get("bullet_damage", 0.0)) * int(p.get("pellets", 1))


static func _num(v: float) -> String:
	return str(roundi(v)) if absf(v) >= 20.0 else "%.1f" % v


static func _pct(v: float) -> String:
	return "%+d%%" % roundi(v * 100.0)


# --- Upgrades overlay ------------------------------------------------------------

func open_upgrades() -> void:
	close_upgrades()
	_upgrades = Control.new()
	_upgrades.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_upgrades)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			close_upgrades())
	_upgrades.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_upgrades.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(820, 0)
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	panel.add_child(column)
	var head := HBoxContainer.new()
	var title := UI.label("RESEARCH UPGRADES", 28, T.COL_ORANGE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := _button("CLOSE", 120)
	close.pressed.connect(close_upgrades)
	head.add_child(close)
	column.add_child(head)
	column.add_child(UI.label("Scrap  %d" % profile.scrap, 22, T.COL_ORANGE))
	var discount := float(T.UPGRADES.research_discount.per_level) * profile.upgrade_level("research_discount")
	var effects := {
		"research_discount": "Levels cost %d%% less" % roundi(discount * 100.0),
		"research_speed": "Levels per day: %d" % profile.research_cap(),
	}
	for key: String in ["research_discount", "research_speed"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(UI.label(str(T.UPGRADES[key].name), 24, UI.TEXT))
		info.add_child(UI.label(effects[key], 17, UI.TEXT_DIM))
		row.add_child(info)
		var level := profile.upgrade_level(key)
		var max_level: int = (T.UPGRADES[key].costs as Array).size()
		row.add_child(UI.label("LV %d/%d" % [level, max_level], 22, T.COL_CYAN))
		var cost := profile.upgrade_cost(key)
		var buy := _button("MAXED" if cost < 0 else "BUY  %d" % cost, 170)
		buy.disabled = cost < 0 or cost > profile.scrap
		buy.pressed.connect(func() -> void:
			profile.buy_upgrade(key)
			open_upgrades())
		row.add_child(buy)
		column.add_child(row)
	column.add_child(UI.label("Upgrades never raise a part's max level.", 17, UI.TEXT_DIM))


func close_upgrades() -> void:
	if _upgrades != null:
		_upgrades.queue_free()
		_upgrades = null


func _button(text: String, min_width: float) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(min_width, 0)
	return b
