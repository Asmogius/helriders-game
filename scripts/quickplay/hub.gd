extends Control
## Quickplay hub (QP4): SANDBOX / ENDLESS / BACK. BACK (or the phone's back
## button / pad B) returns to the title.
##
## STUB (until QP9 / QP11 land): SANDBOX_SCENE / ENDLESS_SCENE are empty, so
## those buttons show a "coming soon" note instead of changing scene. QP9 sets
## SANDBOX_SCENE to the editor, QP11 sets ENDLESS_SCENE to the Endless garage.
## The Endless best-wave line reads EndlessProfile (QP5) when that script
## exists, else shows nothing.

signal mode_picked(mode: String)

const Title := preload("res://scripts/title.gd")
const UI := preload("res://scripts/ui_theme.gd")
const TITLE_SCENE := "res://scenes/title.tscn"
const SANDBOX_SCENE := ""   # QP9: "res://scenes/quickplay_editor.tscn"
const ENDLESS_SCENE := ""   # QP11: the Endless garage
const ENDLESS_PROFILE := "res://scripts/quickplay/endless_profile.gd"   # QP5

var sandbox_button: Button
var endless_button: Button
var back_button: Button
var note: Label


func _ready() -> void:
	add_to_group("pad_modal")
	set_meta("pad_close", back)
	theme = UI.make()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var box := Title.build_panel(self, "QUICKPLAY", "Off the books. Campaign scrap and days stay untouched.")
	sandbox_button = Title.add_button(box, "SANDBOX", true, pick.bind("sandbox"))
	box.add_child(_hint("Build a level, then drive it. Everything unlocked."))
	endless_button = Title.add_button(box, "ENDLESS", true, pick.bind("endless"))
	box.add_child(_hint(endless_line()))
	back_button = Title.add_button(box, "BACK", false, back)
	note = UI.label("", 20, UI.ACCENT)
	note.name = "Note"
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(note)
	sandbox_button.grab_focus.call_deferred()


func _hint(text: String) -> Label:
	var l := UI.label(text, 18, UI.TEXT_DIM)
	l.add_theme_font_override("font", UI.font_body())
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## "Waves until you're wrecked." plus the best wave once QP5's save exists.
static func endless_line() -> String:
	var line := "Waves until you're wrecked. Separate scrap."
	if ResourceLoader.exists(ENDLESS_PROFILE):
		var ep: Object = load(ENDLESS_PROFILE).new()
		if ep.has_method("load_game"):
			ep.call("load_game")
		var best := int(ep.get("best_wave")) if "best_wave" in ep else 0
		if best > 0:
			line += "  Best wave %d." % best
		if ep is Node:
			ep.free()
	return line


func pick(mode: String) -> void:
	mode_picked.emit(mode)
	var scene := SANDBOX_SCENE if mode == "sandbox" else ENDLESS_SCENE
	if scene != "" and ResourceLoader.exists(scene):
		get_tree().change_scene_to_file(scene)
	else:
		note.text = "%s is coming soon." % mode.to_upper()


func back() -> void:
	get_tree().change_scene_to_file(TITLE_SCENE)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		back()
