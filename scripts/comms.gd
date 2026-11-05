extends Control
## The Comms station (DESIGN §5): today's job board, district progress, and
## the Comms upgrades. Tap a job to read it, then TAKE JOB; that sends you
## back to the Garage to tune the rig and DEPLOY. One job per day.

signal job_taken

const T := preload("res://scripts/tuning.gd")
const UI := preload("res://scripts/ui_theme.gd")
const Parts := preload("res://scripts/parts.gd")
const Missions := preload("res://scripts/missions.gd")
const ProfileScript := preload("res://scripts/profile.gd")

const TYPE_COLORS := {
	"clear": Color(0.25, 0.82, 0.88),
	"survive": Color(0.93, 0.48, 0.17),
	"hunt": Color(1.0, 0.78, 0.25),
	"courier": Color(0.45, 0.85, 0.5),
	"retrieve": Color(0.95, 0.8, 0.3),
	"escort": Color(0.4, 0.8, 0.75),
}

var profile: ProfileScript
var selected := -1

var _day: Label
var _scrap: Label
var _cards: HBoxContainer
var _take: Button
var _districts: DistrictBar
var _upgrades: Control


func _ready() -> void:
	profile = get_node("/root/Profile")
	var bg := ColorRect.new()
	bg.color = Color(0.075, 0.075, 0.085)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_day = UI.label("", 30, T.COL_CYAN)
	_day.position = Vector2(24, 14)
	add_child(_day)
	_scrap = UI.label("", 24, T.COL_ORANGE)
	_scrap.position = Vector2(24, 54)
	add_child(_scrap)

	var bar := HBoxContainer.new()
	bar.anchor_left = 1.0
	bar.anchor_right = 1.0
	bar.offset_left = -560.0
	bar.offset_right = -20.0
	bar.offset_top = 10.0
	bar.offset_bottom = 60.0
	bar.alignment = BoxContainer.ALIGNMENT_END
	bar.add_theme_constant_override("separation", 10)
	add_child(bar)
	var upgrades := _button("UPGRADES", 170)
	upgrades.pressed.connect(_open_upgrades)
	bar.add_child(upgrades)
	_take = _button("TAKE JOB", 200)
	UI.accent(_take, T.COL_ORANGE)
	_take.pressed.connect(take_selected)
	bar.add_child(_take)

	var scroll := ScrollContainer.new()
	scroll.anchor_right = 1.0
	scroll.offset_left = 20.0
	scroll.offset_right = -20.0
	scroll.offset_top = 92.0
	scroll.offset_bottom = 92.0 + MissionCard.SIZE.y + 6.0
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.scroll_deadzone = 14
	add_child(scroll)
	_cards = HBoxContainer.new()
	_cards.add_theme_constant_override("separation", 14)
	scroll.add_child(_cards)

	_districts = DistrictBar.new()
	_districts.anchor_right = 1.0
	_districts.anchor_top = 1.0
	_districts.anchor_bottom = 1.0
	_districts.offset_left = 20.0
	_districts.offset_right = -20.0
	_districts.offset_top = -132.0
	_districts.offset_bottom = -16.0
	_districts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_districts)

	profile.changed.connect(refresh)
	refresh()


## Rebuild from the profile: day, scrap, today's cards, districts.
func refresh() -> void:
	profile.ensure_board()
	_day.text = "COMMS   -   DAY %d" % profile.day
	_scrap.text = "SCRAP  %d" % profile.scrap
	for c in _cards.get_children():
		_cards.remove_child(c)
		c.queue_free()
	var taken_id := str(profile.active_mission.get("id", ""))
	if selected < 0 or selected >= profile.board.size():
		selected = -1
		for i in profile.board.size():
			if str(profile.board[i].id) == taken_id:
				selected = i
	for i in profile.board.size():
		var m: Dictionary = profile.board[i]
		var card := MissionCard.new()
		card.mission = m
		card.color = TYPE_COLORS[m.type]
		card.taken = str(m.id) == taken_id
		card.selected = i == selected
		card.schematic_odds = _schematic_odds(m)
		card.odds_rarity = _best_rarity(m)
		card.pressed.connect(select.bind(i))
		_cards.add_child(card)
	_take.disabled = selected < 0 or (selected >= 0 and str(profile.board[selected].id) == taken_id)
	_take.text = "SWITCH JOB" if taken_id != "" and selected >= 0 and str(profile.board[selected].id) != taken_id else "TAKE JOB"
	var names: Array[String] = []
	var needs: Array[int] = []
	for d: Dictionary in T.DISTRICTS:
		names.append(str(d.name))
		needs.append(int(d.need))
	_districts.set_data(names, needs, profile.district_score())


func select(index: int) -> void:
	selected = index
	refresh()


## Takes the selected job and heads back to the Garage.
func take_selected() -> bool:
	if selected < 0:
		return false
	profile.choose_mission(selected)
	job_taken.emit()
	return true


## The best rarity among the schematics this job can still drop (V1.3).
func _best_rarity(m: Dictionary) -> String:
	var pool: Array = Parts.DROP_POOLS.get("elite" if m.type == "hunt" else str(m.type), [])
	var best := 0
	for id in profile.unknown_schematics(pool):
		best = maxi(best, UI.rarity_tier(str(Parts.get_part(str(id)).get("rarity", ""))))
	return str(T.RARITY_ORDER[best - 1]) if best > 0 else ""


## The chance of a schematic in the pay, shown on the card ("" if none).
func _schematic_odds(m: Dictionary) -> String:
	var pool: Array = Parts.DROP_POOLS.get("elite" if m.type == "hunt" else str(m.type), [])
	if profile.unknown_schematics(pool).is_empty():
		return ""
	if m.type == "hunt":
		return "Elite drops a schematic"
	if m.type == "retrieve":
		return "Deep cache holds a schematic"
	if m.type == "escort":
		return "%d%% schematic, 100%% if you risk it" % roundi(Missions.schematic_chance(m) * 100.0)
	var odds := roundi(Missions.schematic_chance(m) * 100.0)
	if odds <= 0:
		return ""
	return "%d%% schematic%s" % [odds, " (gold time)" if m.type == "courier" else ""]


func _button(text: String, min_width: float) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(min_width, 0)
	return b


func _open_upgrades() -> void:
	_close_upgrades()
	_upgrades = Control.new()
	_upgrades.add_to_group("pad_modal")
	_upgrades.set_meta("pad_close", _close_upgrades)
	_upgrades.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_upgrades)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			_close_upgrades())
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
	var title := UI.label("COMMS UPGRADES", 28, T.COL_ORANGE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := _button("CLOSE", 120)
	close.pressed.connect(_close_upgrades)
	head.add_child(close)
	column.add_child(head)
	column.add_child(UI.label("Scrap  %d" % profile.scrap, 22, T.COL_ORANGE))
	var effects := {
		"choices": "Jobs on the board: %d" % profile.board_size(),
		"quality": "Job pay +%d%%" % roundi(float(T.UPGRADES.quality.per_level) * profile.upgrade_level("quality") * 100.0),
	}
	for key: String in ["choices", "quality"]:
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
			_open_upgrades())
		row.add_child(buy)
		column.add_child(row)


func _close_upgrades() -> void:
	if _upgrades != null:
		_upgrades.queue_free()
		_upgrades = null


class MissionCard extends Button:
	## One job on the board: type, name, skulls, what's in the block, pay.
	const T := preload("res://scripts/tuning.gd")
	const UI := preload("res://scripts/ui_theme.gd")
	const Missions := preload("res://scripts/missions.gd")
	const SIZE := Vector2(300, 330)
	var mission := {}
	var color := Color.WHITE
	var taken := false
	var selected := false
	var schematic_odds := ""
	var odds_rarity := ""   # best rarity on offer: the odds line takes its colour

	func _ready() -> void:
		flat = true
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = SIZE
		action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE

	func _draw() -> void:
		var font := get_theme_default_font()
		var fill := Color(0.12, 0.12, 0.13)
		if taken:
			fill = Color(0.1, 0.14, 0.15)
		elif get_draw_mode() == DRAW_PRESSED:
			fill = Color(0.2, 0.13, 0.08)
		draw_rect(Rect2(Vector2.ZERO, size), fill)
		draw_rect(Rect2(0, 0, size.x, 6), color)
		if selected:
			draw_rect(Rect2(Vector2.ZERO, size), T.COL_ORANGE, false, 3.0)
		else:
			draw_rect(Rect2(Vector2.ZERO, size), Color(color, 0.35), false, 2.0)
		var w := size.x - 32.0
		draw_string(font, Vector2(16, 40), Missions.label(mission), HORIZONTAL_ALIGNMENT_LEFT, w, 26, color)
		draw_string(font, Vector2(16, 72), str(mission.name), HORIZONTAL_ALIGNMENT_LEFT, w, 21, UI.TEXT)
		# Difficulty: lit skulls out of six.
		var level := Missions.skulls(mission)
		for i in T.MAX_SKULLS:
			UI.draw_skull(self, Vector2(26 + i * 26, 100), 10.0, UI.skull_color(level), i < level)
		_wrapped(font, Missions.brief(mission), Vector2(16, 136), w, 16, UI.TEXT_DIM)
		# Up to five tighter lines: a 6-skull job lists a lot of trouble.
		_wrapped(font, Missions.threats_text(mission), Vector2(16, 182), w, 13, UI.TEXT, 5, 3.0)
		draw_string(font, Vector2(16, size.y - 52), "PAYS %d SCRAP" % Missions.night_pay(int(mission.reward), mission), HORIZONTAL_ALIGNMENT_LEFT, w, 20, T.COL_ORANGE)
		if Missions.is_night(mission):
			_draw_night_icon(font)
		if schematic_odds != "":
			var oc := UI.rarity_color(odds_rarity) if odds_rarity != "" else UI.GOOD
			UI.draw_fit(self, font, Vector2(16, size.y - 28), "+ " + schematic_odds, HORIZONTAL_ALIGNMENT_LEFT, w, 15, oc)
		if taken:
			draw_string(font, Vector2(16, size.y - 8), "TAKEN", HORIZONTAL_ALIGNMENT_RIGHT, w, 15, T.COL_CYAN)

	## Night job (PR #69): a crescent badge, top right, before the job is taken.
	func _draw_night_icon(font: Font) -> void:
		var box := Rect2(size.x - 92, 14, 78, 28)
		draw_rect(box, T.COL_NIGHT)
		draw_rect(box, UI.TEXT_DIM, false, 1.0)
		var c := box.position + Vector2(15, 14)
		draw_circle(c, 9.0, UI.TEXT)
		draw_circle(c + Vector2(4, -3), 8.0, T.COL_NIGHT)   # bite out of the moon
		draw_string(font, box.position + Vector2(28, 20), "NIGHT", HORIZONTAL_ALIGNMENT_LEFT, 48, 14, UI.TEXT)

	## Simple word wrap for card text (up to `max_lines` lines).
	func _wrapped(font: Font, text: String, at: Vector2, width: float, font_size: int, tint: Color, max_lines := 3, gap := 6.0) -> void:
		var line := ""
		var y := at.y
		var lines := 0
		for word in text.split(" "):
			var trial := word if line == "" else line + " " + word
			if font.get_string_size(trial, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width and line != "":
				draw_string(font, Vector2(at.x, y), line, HORIZONTAL_ALIGNMENT_LEFT, width, font_size, tint)
				y += font_size + gap
				lines += 1
				line = word
				if lines >= max_lines:
					return
			else:
				line = trial
		if line != "":
			draw_string(font, Vector2(at.x, y), line, HORIZONTAL_ALIGNMENT_LEFT, width, font_size, tint)


class DistrictBar extends Control:
	## The four districts along the bottom: parts score against each threshold.
	const T := preload("res://scripts/tuning.gd")
	const UI := preload("res://scripts/ui_theme.gd")
	var names: Array[String] = []
	var needs: Array[int] = []
	var score := 0

	func set_data(new_names: Array[String], new_needs: Array[int], new_score: int) -> void:
		names = new_names
		needs = new_needs
		score = new_score
		queue_redraw()

	func _draw() -> void:
		if names.is_empty():
			return
		var font := get_theme_default_font()
		draw_string(font, Vector2(0, 18), "DISTRICTS   -   parts score %d  (extracted schematics: rarity points x Research level)" % score, HORIZONTAL_ALIGNMENT_LEFT, size.x, 16, UI.TEXT_DIM)
		var gap := 12.0
		var w := (size.x - gap * (names.size() - 1)) / names.size()
		for i in names.size():
			var x := i * (w + gap)
			var open := score >= needs[i]
			var r := Rect2(x, 30, w, size.y - 30)
			draw_rect(r, Color(0.1, 0.1, 0.11))
			draw_rect(r, Color(T.COL_CYAN, 0.6) if open else UI.PANEL_EDGE, false, 2.0)
			draw_string(font, Vector2(x + 12, 58), names[i], HORIZONTAL_ALIGNMENT_LEFT, w - 24, 19, UI.TEXT if open else UI.TEXT_DIM)
			var status := "OPEN" if open else "%d / %d" % [score, needs[i]]
			draw_string(font, Vector2(x + 12, 58), status, HORIZONTAL_ALIGNMENT_RIGHT, w - 24, 15, T.COL_CYAN if open else T.COL_ORANGE)
			var bar := Rect2(x + 12, 72, w - 24, 10)
			draw_rect(bar, Color(0, 0, 0, 0.5))
			var fill := 1.0 if needs[i] == 0 else clampf(float(score) / needs[i], 0.0, 1.0)
			draw_rect(Rect2(bar.position, Vector2(bar.size.x * fill, bar.size.y)), T.COL_CYAN if open else T.COL_ORANGE)
			var band: Array = T.DISTRICTS[i].skulls
			var skull_text := "%d-%d skulls" % [int(band[0]), int(band[1])]
			if i == 0:
				draw_string(font, Vector2(x + 12, size.y - 8), "Jobs today are here", HORIZONTAL_ALIGNMENT_LEFT, w - 24, 14, UI.TEXT_DIM)
			elif not open:
				draw_string(font, Vector2(x + 12, size.y - 8), "Locked", HORIZONTAL_ALIGNMENT_LEFT, w - 24, 14, UI.TEXT_DIM)
			draw_string(font, Vector2(x + 12, size.y - 8), skull_text, HORIZONTAL_ALIGNMENT_RIGHT, w - 24, 14, UI.TEXT_DIM)
