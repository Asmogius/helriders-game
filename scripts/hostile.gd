extends CharacterBody2D
## Base for every non-rig enemy (shamblers, hunters). Gives bullets, rams and
## the lock-on system one shared interface:
##   is_targetable(), lock_priority, lock_radius, take_hit(damage, impulse)

signal died(at: Vector2)

const T := preload("res://scripts/tuning.gd")

var active := false
var hp := 0.0
var lock_priority := 1     # lock-on prefers higher numbers
var lock_radius := 18.0    # reticle size
var last_hit_cause := ""   # "shot", "rammed", "crushed", "scraped" (for tests/feedback)
# Spotter statuses: Mark and Flare make it take more damage; Flare slows it.
var vuln := 1.0
var slow := 1.0
var status_left := 0.0


func is_targetable() -> bool:
	return active


## `dtype` is the damage type ("" or "kinetic", "shock", "fire", "acid", "toxic", ...).
func take_hit(damage: float, impulse: Vector2, cause := "shot", _dtype := "") -> void:
	if not active:
		return
	if status_left > 0.0:
		damage *= vuln
	hp -= damage
	last_hit_cause = cause
	_on_hit(damage, impulse)
	if hp <= 0.0:
		var at := global_position
		deactivate()
		died.emit(at)


## Marked or flared: takes `vuln_mult` damage and moves at `slow_mult` speed
## for `seconds`.
func apply_status(vuln_mult: float, slow_mult: float, seconds: float) -> void:
	vuln = vuln_mult
	slow = slow_mult
	status_left = seconds
	queue_redraw()


func clear_status() -> void:
	vuln = 1.0
	slow = 1.0
	status_left = 0.0


## Ticks the status down; true on the tick it ends (redraw then).
func tick_status(delta: float) -> bool:
	if status_left <= 0.0:
		return false
	status_left -= delta
	if status_left <= 0.0:
		vuln = 1.0
		slow = 1.0
		queue_redraw()
		return true
	return false


## Speed multiplier from a Flare.
func speed_mult() -> float:
	return slow if status_left > 0.0 else 1.0


## A red ring while marked or flared.
func draw_status(radius: float) -> void:
	if status_left > 0.0:
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 20, Color(0.95, 0.3, 0.25, 0.85), 2.0)


## Override: react to a hit (knockback, flash).
func _on_hit(_damage: float, _impulse: Vector2) -> void:
	pass


## Override: hide, disable collision, park off-map. Must set active = false.
func deactivate() -> void:
	active = false
