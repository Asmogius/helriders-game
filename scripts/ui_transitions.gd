extends RefCounted
## Interface transitions (VISUAL_PLAN V6.5 + Ebbtide garage→fight). Look only:
## nothing here changes game state or text the game reads. Overlays ignore the
## mouse except the deploy fade (tap / click skips).
##   fade_in(scene)            charcoal fade when the garage or a fight opens
##   deploy_to_fight(garage, path)  push-in on the rig, then fade to the fight
##   slide_in(control)         a station screen's cards slide and fade in (#47)
##   tick_numbers(label)       results card numbers count up (#47)
##   flash(control)            a short white flash (crew level-up) (#47)
##
## Ebbtide (Cameron): the only transition in scope for deploy is the garage→fight
## push-in plus fade. #47's card slides / results tick / level-up flash stay as
## already shipped; this file does not add more of those.

const T := preload("res://scripts/tuning.gd")

const FADE_TIME := 0.35
const SLIDE_TIME := 0.25
const SLIDE_PX := 36.0
const TICK_TIME := 0.7
# Garage → fight (Ebbtide): short and skippable. Total ≈ 0.45 s.
const DEPLOY_PUSH_TIME := 0.22
const DEPLOY_FADE_TIME := 0.28
const DEPLOY_FADE_DELAY := 0.12   # fade starts while the push is still going
const DEPLOY_PUSH_SCALE := 1.55
const DEPLOY_META := &"ui_deploy_transitioning"

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


## A full-screen charcoal layer that fades out over the new scene, then frees.
## Colour is COL_UI_DEEP (#131311) so it matches the deploy fade.
static func fade_in(scene: Node) -> void:
	if not enabled():
		return
	var layer := CanvasLayer.new()
	layer.layer = 100
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	var rect := ColorRect.new()
	rect.color = Color(T.COL_UI_DEEP.r, T.COL_UI_DEEP.g, T.COL_UI_DEEP.b, 1.0)
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


## Garage DEPLOY: push the camera in on the rig, fade to charcoal #131311, then
## open the fight. Respects enabled(). Tap / click / confirm skips to the scene
## change. Look only — the mission is already chosen; this does not touch scrap,
## loadout or the day. Total ≈ 0.4 s (push 0.22 overlapping a 0.28 fade).
static func deploy_to_fight(garage: Node, scene_path: String) -> void:
	if garage == null or scene_path == "":
		return
	if not enabled():
		garage.get_tree().change_scene_to_file(scene_path)
		return
	if garage.has_meta(DEPLOY_META):
		return
	garage.set_meta(DEPLOY_META, true)

	var holder: Node2D = garage.get("_rig_holder") as Node2D
	var start_scale := Vector2.ONE
	if holder != null:
		start_scale = holder.scale

	var layer := CanvasLayer.new()
	layer.name = "DeployTransition"
	layer.layer = 100
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	# Full-screen catcher: charcoal fade plate that also accepts a skip tap / key.
	var catcher := Control.new()
	catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	catcher.focus_mode = Control.FOCUS_ALL
	layer.add_child(catcher)
	var rect := ColorRect.new()
	rect.color = Color(T.COL_UI_DEEP.r, T.COL_UI_DEEP.g, T.COL_UI_DEEP.b, 1.0)
	rect.modulate.a = 0.0
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	catcher.add_child(rect)
	garage.add_child(layer)
	catcher.grab_focus.call_deferred()

	var done := [false]
	var tw_ref: Array = [null]
	var finish := func() -> void:
		if done[0]:
			return
		done[0] = true
		var tw0: Tween = tw_ref[0]
		if tw0 != null and is_instance_valid(tw0) and tw0.is_running():
			tw0.kill()
		# Captures may cancel mid-way so they can shoot mid-push / mid-fade.
		if is_instance_valid(garage) and garage.has_meta(&"ui_deploy_cancel"):
			return
		if is_instance_valid(garage) and garage.get_tree() != null:
			garage.get_tree().change_scene_to_file(scene_path)

	catcher.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
			finish.call()
		elif ev is InputEventScreenTouch and (ev as InputEventScreenTouch).pressed:
			finish.call()
		elif ev.is_action_pressed("ui_accept") or (ev is InputEventKey and (ev as InputEventKey).pressed and not (ev as InputEventKey).echo):
			finish.call())

	var tw := layer.create_tween()
	tw_ref[0] = tw
	if holder != null:
		tw.tween_property(holder, "scale", start_scale * DEPLOY_PUSH_SCALE, DEPLOY_PUSH_TIME) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	else:
		tw.tween_interval(DEPLOY_PUSH_TIME)
	# Fade overlaps the end of the push; charcoal covers the bay before the cut.
	tw.parallel().tween_property(rect, "modulate:a", 1.0, DEPLOY_FADE_TIME) \
		.set_delay(DEPLOY_FADE_DELAY).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(finish)
