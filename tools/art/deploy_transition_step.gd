extends "res://tools/art/capture_step.gd"
## Ebbtide: garage → fight deploy transition frame.
## Poses the rig scale + charcoal overlay to match deploy_to_fight at start /
## mid-push / mid-fade. Transitions are disabled here so the garage's own
## fade_in does not darken the shot; the real tween path is covered by
## transitions_test.gd.

const UITransitions := preload("res://scripts/ui_transitions.gd")

## 0 = start, 1 = mid-push, 2 = mid-fade. Override in each shot file.
var _kind := 0


func run(cap: SceneTree) -> void:
	# Skip the garage open fade so the posed overlay is the only charcoal.
	UITransitions.set_enabled(false)
	if cap.garage == null or not is_instance_valid(cap.garage):
		cap.garage = null
		cap.show_tab("GARAGE")
	else:
		cap.show_tab("GARAGE")
	if not cap.profile.has_mission():
		cap.profile.ensure_board()
		cap.profile.choose_mission(0)
	var g: Node = cap.garage
	# Clear any leftover deploy layer from a prior shot.
	var stale := g.get_node_or_null("DeployTransition")
	if stale != null:
		stale.free()
	if g.has_meta(UITransitions.DEPLOY_META):
		g.remove_meta(UITransitions.DEPLOY_META)

	var holder: Node2D = g.get("_rig_holder") as Node2D
	# Match deploy_to_fight timings: push 0→1.55, fade overlaps late push.
	var push_t := 0.0
	var fade_a := 0.0
	if _kind == 0:
		push_t = 0.05
		fade_a = 0.0
	elif _kind == 1:
		push_t = 0.55
		fade_a = 0.12
	else:
		push_t = 1.0
		fade_a = 0.55
	# Cubic ease-in, same as the live tween.
	var eased := push_t * push_t * push_t
	if holder != null:
		holder.scale = Vector2.ONE * (1.0 + (UITransitions.DEPLOY_PUSH_SCALE - 1.0) * eased)

	var layer := CanvasLayer.new()
	layer.name = "DeployTransition"
	layer.layer = 100
	var rect := ColorRect.new()
	rect.color = Color(T.COL_UI_DEEP.r, T.COL_UI_DEEP.g, T.COL_UI_DEEP.b, 1.0)
	rect.modulate.a = fade_a
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(rect)
	g.add_child(layer)


func wait() -> int:
	return 4   # just long enough for one draw of the posed frame


func after(cap: SceneTree) -> void:
	var g: Node = cap.garage
	if g == null or not is_instance_valid(g):
		return
	var layer := g.get_node_or_null("DeployTransition")
	if layer != null:
		layer.free()
	var holder: Node2D = g.get("_rig_holder") as Node2D
	if holder != null:
		holder.scale = Vector2.ONE
	UITransitions.set_enabled(true)
