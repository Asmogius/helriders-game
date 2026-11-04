extends RefCounted
## Interface transitions (VISUAL_PLAN V6.5). Look only: nothing here changes
## state, text the game reads, or input (every overlay ignores the mouse).
##   fade_in(scene)       black fade when the garage or a fight opens
##   slide_in(control)    a station screen's cards slide and fade in
##   tick_numbers(label)  results card numbers count up (the label's text stays final)
##   flash(control)       a short white flash (crew level-up)

const FADE_TIME := 0.35
const SLIDE_TIME := 0.25
const SLIDE_PX := 36.0
const TICK_TIME := 0.7

const OFF_META := &"ui_transitions_off"


## Tests and captures may turn transitions off. The switch is Engine meta, not
## a static var: a static var kept this script alive past exit ("resources
## still in use").
static func set_enabled(on: bool) -> void:
	if on:
		Engine.remove_meta(OFF_META)
	else:
		Engine.set_meta(OFF_META, true)


static func enabled() -> bool:
	return not Engine.has_meta(OFF_META)


## A full-screen black layer that fades out over the new scene, then frees.
static func fade_in(scene: Node) -> void:
	if not enabled():
		return
	var layer := CanvasLayer.new()
	layer.layer = 100
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	var rect := ColorRect.new()
	rect.color = Color(0.02, 0.02, 0.025)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(rect)
	scene.add_child(layer)
	var tw := layer.create_tween()
	tw.tween_property(rect, "modulate:a", 0.0, FADE_TIME).set_ease(Tween.EASE_IN)
	tw.tween_callback(layer.queue_free)


## Slides `c` in from the right with a fade (fade only inside a container). Draws only; layout is untouched
## (it tweens the canvas transform via `position` relative to where it is).
static func slide_in(c: CanvasItem) -> void:
	if not enabled() or c == null:
		return
	c.modulate.a = 0.0
	var tw := c.create_tween().set_parallel()
	tw.tween_property(c, "modulate:a", 1.0, SLIDE_TIME)
	if c is Control and not (c.get_parent() is Container):   # containers own their children's position: fade only
		var ctl := c as Control
		if not ctl.has_meta("slide_home"):
			ctl.set_meta("slide_home", ctl.position)
		var to: Vector2 = ctl.get_meta("slide_home")
		ctl.position = to + Vector2(SLIDE_PX, 0.0)
		tw.tween_property(ctl, "position", to, SLIDE_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Results numbers tick up from 0. `label.text` keeps its final value (tests
## and the pad read it); a child copy shows the counting text meanwhile.
static func tick_numbers(label: Label) -> void:
	if not enabled() or label == null or label.text == "":
		return
	var final := label.text
	var ticker: Label = label.get_node_or_null("Ticker")
	if ticker == null:
		ticker = label.duplicate(0) as Label
		ticker.name = "Ticker"
		ticker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		ticker.self_modulate.a = 1.0
		label.add_child(ticker)
	ticker.visible = true
	label.self_modulate.a = 0.0
	var re := RegEx.create_from_string("\\d+")
	var step := func(t: float) -> void:
		var out := ""
		var at := 0
		for m in re.search_all(final):
			out += final.substr(at, m.get_start() - at) + str(roundi(int(m.get_string()) * t))
			at = m.get_end()
		ticker.text = out + final.substr(at)
	var tw := label.create_tween()
	tw.tween_method(step, 0.0, 1.0, TICK_TIME).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void:
		label.self_modulate.a = 1.0
		ticker.visible = false)


## A quick white flash on a card (modulate up, then back).
static func flash(c: CanvasItem) -> void:
	if not enabled() or c == null:
		return
	var tw := c.create_tween()
	tw.tween_property(c, "modulate", Color(1.8, 1.8, 1.8), 0.08)
	tw.tween_property(c, "modulate", Color.WHITE, 0.35)
	tw.tween_property(c, "modulate", Color(1.5, 1.5, 1.5), 0.08)
	tw.tween_property(c, "modulate", Color.WHITE, 0.35)
