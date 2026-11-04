extends RefCounted
## A Harpoon cable between two rigs (§14). It reels in, and when it's taut it
## pulls both ends together, the lighter rig (smaller hull) moving more. It
## pops when either rig takes a big hit (over 15% of its max inside 1 s) or
## crashes hard into a wall. `step()` returns false once it has broken.

const T := preload("res://scripts/tuning.gd")

var a: CharacterBody2D      # the rig that fired it
var b: CharacterBody2D      # the rig it's stuck in
var length := 500.0
var reel_speed := T.HARPOON_REEL_SPEED   # Power Winch mod raises these
var reel_to := T.HARPOON_REEL_TO

var _hits_a := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
var _hits_b := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
var _i := 0
var _t := 0.0


func _init(from: CharacterBody2D, to: CharacterBody2D, cable: float) -> void:
	a = from
	b = to
	length = minf(cable, from.global_position.distance_to(to.global_position) + 10.0)
	a.connect("damaged", _on_a_hit)
	b.connect("damaged", _on_b_hit)


## Let go of both rigs (disconnects the hit counters).
func release() -> void:
	if is_instance_valid(a) and a.is_connected("damaged", _on_a_hit):
		a.disconnect("damaged", _on_a_hit)
	if is_instance_valid(b) and b.is_connected("damaged", _on_b_hit):
		b.disconnect("damaged", _on_b_hit)


static func mass_of(rig: Node) -> float:
	return float(rig.get("body_len")) * float(rig.get("body_wid"))


func step(delta: float) -> bool:
	if not is_instance_valid(a) or not is_instance_valid(b) or not b.is_inside_tree() or bool(a.get("is_wrecked")) or bool(b.get("is_wrecked")):
		return false
	_t += delta
	while _t >= 0.1:
		_t -= 0.1
		_i = (_i + 1) % 10
		_hits_a[_i] = 0.0
		_hits_b[_i] = 0.0
	if _sum(_hits_a) > float(a.get("armor_max")) * T.HARPOON_POP_HIT or _sum(_hits_b) > float(b.get("armor_max")) * T.HARPOON_POP_HIT:
		return false
	if float(a.get("wall_impact")) > T.HARPOON_POP_CRASH or float(b.get("wall_impact")) > T.HARPOON_POP_CRASH:
		return false
	length = maxf(reel_to, length - reel_speed * delta)
	var gap := b.global_position - a.global_position
	var dist := gap.length()
	if dist <= length or dist < 1.0:
		return true
	var dir := gap / dist
	var ma := mass_of(a)
	var mb := mass_of(b)
	var share_a := mb / (ma + mb)   # the lighter rig takes more of the pull
	var excess := dist - length
	a.move_and_collide(dir * excess * share_a)
	b.move_and_collide(-dir * excess * (1.0 - share_a))
	# Kill the part of their speed that stretches the cable, shared by mass.
	var stretch := b.velocity.dot(dir) - a.velocity.dot(dir)
	if stretch > 0.0:
		a.velocity += dir * stretch * share_a
		b.velocity -= dir * stretch * (1.0 - share_a)
	return true


func _on_a_hit(amount: float) -> void:
	_hits_a[_i] += amount


func _on_b_hit(amount: float) -> void:
	_hits_b[_i] += amount


static func _sum(arr: PackedFloat32Array) -> float:
	var t := 0.0
	for v in arr:
		t += v
	return t
