extends Button
## One crew member as a card (Inn roster and Saloon hires): role, rarity,
## name, level and XP, what they do, and a status line.

const T := preload("res://scripts/tuning.gd")
const UI := preload("res://scripts/ui_theme.gd")
const Crew := preload("res://scripts/crew.gd")
const SIZE := Vector2(286, 300)

var member := {}:   # clear with {}
	set(v):
		member = v
		var f: Control = get_node_or_null("RarityFrame")
		if v.is_empty():   # cleared: no member, no frame
			if f != null:
				f.hide()
			queue_redraw()
			return
		# V1.3: crew cards wear the shared rarity frame
		UI.rarity_frame(self, str(v.get("rarity", "Common"))).show()
		queue_redraw()
var status := ""
var status_color := UI.TEXT_DIM
var selected := false
var dim := false            # resting or already hired
var flashed := false           # V6.5: this card played the level-up flash (tests, capture)
var _icons: RefCounted = UI.icons()   # V6.3: class icon in the portrait chip


func _ready() -> void:
	flat = true
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = SIZE
	action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	if not member.is_empty() and member.has("id"):
		var lv := Crew.level(member)
		var key := str(member.id)
		var seen := _seen_levels()
		if seen.has(key) and lv > int(seen[key]):
			preload("res://scripts/ui_transitions.gd").flash(self)
			flashed = true
		seen[key] = lv


## V6.5: member id -> level last shown, for the level-up flash. Kept as meta
## on the Profile node (not a static var, which kept this script alive at exit);
## Profile.new_game() drops it (SEEN_META), so a new game's crew (ids start
## over) never flash against the last game's levels.
const SEEN_META := &"crew_seen_level"


func _seen_levels() -> Dictionary:
	var profile := get_node_or_null("/root/Profile")
	if profile == null:
		return {}
	if not profile.has_meta(SEEN_META):
		profile.set_meta(SEEN_META, {})
	return profile.get_meta(SEEN_META)


func _draw() -> void:
	if member.is_empty():
		return
	var font := get_theme_default_font()
	var rarity := UI.rarity_color(str(member.get("rarity", "Common")))
	var fill := Color(0.12, 0.12, 0.13)
	if get_draw_mode() == DRAW_PRESSED:
		fill = Color(0.2, 0.13, 0.08)
	draw_rect(Rect2(Vector2.ZERO, size), fill)
	if selected:   # inside the rarity frame, so both show
		draw_rect(Rect2(Vector2(4, 4), size - Vector2(8, 8)), T.COL_UI_ACCENT, false, 3.0)
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
	if not _icons.draw(self, str(member.get("role", "")), Rect2(chip.position + Vector2(7, 7), Vector2(32, 32)), Color(role_color, a)):
		draw_string(font, Vector2(16, 54), initials, HORIZONTAL_ALIGNMENT_CENTER, 46, 20, Color(UI.TEXT, a))
	draw_string(font, Vector2(74, 40), Crew.role_name(member).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, w - 58, 18, Color(role_color, a))
	draw_string(font, Vector2(74, 62), "%s - %s" % [member.rarity, Crew.specialty_name(member)], HORIZONTAL_ALIGNMENT_LEFT, w - 58, 14, Color(rarity, a))
	if Crew.perks_due(member) > 0:
		var badge := Rect2(size.x - 104.0, 14.0, 92.0, 22.0)
		draw_rect(badge, T.COL_UI_ACCENT)
		draw_string(font, badge.position + Vector2(0, 16), "PERK READY", HORIZONTAL_ALIGNMENT_CENTER, badge.size.x, 13, Color(0.08, 0.08, 0.09))
	draw_string(font, Vector2(16, 98), str(member.name), HORIZONTAL_ALIGNMENT_LEFT, w, 22, Color(UI.TEXT, a))
	# Level and XP.
	var lv := Crew.level(member)
	draw_string(font, Vector2(16, 126), "LEVEL %d / %d" % [lv, Crew.max_level(member)], HORIZONTAL_ALIGNMENT_LEFT, w, 15, Color(UI.TEXT_DIM, a))
	var bar := Rect2(16, 134, w, 8)
	draw_rect(bar, Color(0, 0, 0, 0.5))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * Crew.level_progress(member), bar.size.y)), Color(T.COL_UI_ACCENT, 0.8 * a))
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
		draw_string(font, Vector2(16, y + 6.0), "PERKS  " + ", ".join(names), HORIZONTAL_ALIGNMENT_LEFT, w, 13, Color(T.COL_UI_ACCENT, 0.9 * a))
	if status != "":
		draw_string(font, Vector2(16, size.y - 16), status, HORIZONTAL_ALIGNMENT_LEFT, w, 17, status_color)
