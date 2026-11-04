extends Control
## A station's upgrade tracks as a modal panel: one row per track with what it
## does now, its level and a BUY button (or why it can't be bought yet). Used
## by the Inn and the Saloon. Build it with setup(), add it as a child of the
## station; it frees itself when closed.

const T := preload("res://scripts/tuning.gd")
const UI := preload("res://scripts/ui_theme.gd")
const ProfileScript := preload("res://scripts/profile.gd")

signal closed

var profile: ProfileScript
var title := ""
var keys: Array = []
var effect: Callable          # func(key: String) -> String
var footnote := ""

var _column: VBoxContainer


func setup(p: ProfileScript, panel_title: String, track_keys: Array, effect_text: Callable, note := "") -> void:
	profile = p
	title = panel_title
	keys = track_keys
	effect = effect_text
	footnote = note


func _ready() -> void:
	add_to_group("pad_modal")
	set_meta("pad_close", close)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			close())
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(900, 0)
	center.add_child(panel)
	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", 10)
	panel.add_child(_column)
	rebuild()


func rebuild() -> void:
	for c in _column.get_children():
		_column.remove_child(c)
		c.queue_free()
	var head := HBoxContainer.new()
	var title_label := UI.label(title, 28, T.COL_ORANGE)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title_label)
	head.add_child(UI.label("Scrap  %d    " % profile.scrap, 22, T.COL_ORANGE))
	var close_button := _button("CLOSE", 120)
	close_button.pressed.connect(close)
	head.add_child(close_button)
	_column.add_child(head)
	for key: String in keys:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 0)
		info.add_child(UI.label(str(T.UPGRADES[key].name), 22, UI.TEXT))
		info.add_child(UI.label(str(effect.call(key)), 16, UI.TEXT_DIM))
		row.add_child(info)
		var level := profile.upgrade_level(key)
		var max_level: int = (T.UPGRADES[key].costs as Array).size()
		row.add_child(UI.label("LV %d/%d" % [level, max_level], 20, T.COL_CYAN))
		var cost := profile.upgrade_cost(key)
		var block := profile.upgrade_block(key)
		var text := "MAXED" if cost < 0 else (block if block != "" else "BUY  %d" % cost)
		var buy := _button(text, 250)
		buy.disabled = cost < 0 or block != "" or cost > profile.scrap
		buy.pressed.connect(buy_track.bind(key))
		row.add_child(buy)
		_column.add_child(row)
	if footnote != "":
		var note := UI.label(footnote, 16, UI.TEXT_DIM)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD
		note.custom_minimum_size = Vector2(860, 0)
		_column.add_child(note)


func buy_track(key: String) -> bool:
	var ok := profile.buy_upgrade(key)
	rebuild()
	return ok


func close() -> void:
	closed.emit()
	queue_free()


func _button(text: String, min_width: float) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(min_width, 0)
	return b
