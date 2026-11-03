extends Button
## One crew member as a card (Inn roster and Saloon hires): role, rarity,
## name, level and XP, what they do, and a status line.

const T := preload("res://scripts/tuning.gd")
const UI := preload("res://scripts/ui_theme.gd")
const Crew := preload("res://scripts/crew.gd")
const SIZE := Vector2(286, 300)

var member := {}
var status := ""
var status_color := UI.TEXT_DIM
var selected := false
var dim := false            # resting or already hired


func _ready() -> void:
	flat = true
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = SIZE
	action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE


func _draw() -> void:
	if member.is_empty():
		return
	var font := get_theme_default_font()
	var rarity := Crew.color_of(member)
	var fill := Color(0.12, 0.12, 0.13)
	if get_draw_mode() == DRAW_PRESSED:
		fill = Color(0.2, 0.13, 0.08)
	draw_rect(Rect2(Vector2.ZERO, size), fill)
	draw_rect(Rect2(0, 0, size.x, 6), rarity)
	if selected:
		draw_rect(Rect2(Vector2.ZERO, size), T.COL_ORANGE, false, 3.0)
	else:
		draw_rect(Rect2(Vector2.ZERO, size), Color(rarity, 0.35), false, 2.0)
	var a := 0.5 if dim else 1.0
	var w := size.x - 32.0
	var role_color := Crew.role_color(member)
	# Portrait chip: initials on the role color.
	var chip := Rect2(16, 22, 46, 46)
	draw_rect(chip, Color(role_color, 0.25 * a))
	draw_rect(chip, Color(role_color, 0.8 * a), false, 2.0)
	var initials := ""
	for part in str(member.name).split(" "):
		if part != "":
			initials += part.substr(0, 1)
	draw_string(font, Vector2(16, 54), initials, HORIZONTAL_ALIGNMENT_CENTER, 46, 20, Color(UI.TEXT, a))
	draw_string(font, Vector2(74, 40), Crew.role_name(member).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, w - 58, 18, Color(role_color, a))
	draw_string(font, Vector2(74, 62), "%s - %s" % [member.rarity, Crew.specialty_name(member)], HORIZONTAL_ALIGNMENT_LEFT, w - 58, 14, Color(rarity, a))
	if Crew.perks_due(member) > 0:
		var badge := Rect2(size.x - 104.0, 14.0, 92.0, 22.0)
		draw_rect(badge, T.COL_ORANGE)
		draw_string(font, badge.position + Vector2(0, 16), "PERK READY", HORIZONTAL_ALIGNMENT_CENTER, badge.size.x, 13, Color(0.08, 0.08, 0.09))
	draw_string(font, Vector2(16, 98), str(member.name), HORIZONTAL_ALIGNMENT_LEFT, w, 22, Color(UI.TEXT, a))
	# Level and XP.
	var lv := Crew.level(member)
	draw_string(font, Vector2(16, 126), "LEVEL %d / %d" % [lv, Crew.max_level(member)], HORIZONTAL_ALIGNMENT_LEFT, w, 15, Color(UI.TEXT_DIM, a))
	var bar := Rect2(16, 134, w, 8)
	draw_rect(bar, Color(0, 0, 0, 0.5))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * Crew.level_progress(member), bar.size.y)), Color(T.COL_CYAN, 0.8 * a))
	# What they do, two lines.
	var text := Crew.summary(member)
	var halves := text.split("    ")
	var y := 168.0
	for line in halves:
		draw_string(font, Vector2(16, y), line, HORIZONTAL_ALIGNMENT_LEFT, w, 14, Color(UI.TEXT, a))
		y += 20.0
	var perks: Array = member.get("perks", [])
	if not perks.is_empty():
		var names: Array[String] = []
		for p: String in perks:
			names.append(Crew.perk_name(p))
		draw_string(font, Vector2(16, y + 6.0), "PERKS  " + ", ".join(names), HORIZONTAL_ALIGNMENT_LEFT, w, 13, Color(T.COL_CYAN, 0.9 * a))
	if status != "":
		draw_string(font, Vector2(16, size.y - 16), status, HORIZONTAL_ALIGNMENT_LEFT, w, 17, status_color)
