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


func is_targetable() -> bool:
	return active


func take_hit(damage: float, impulse: Vector2, cause := "shot") -> void:
	if not active:
		return
	hp -= damage
	last_hit_cause = cause
	_on_hit(damage, impulse)
	if hp <= 0.0:
		var at := global_position
		deactivate()
		died.emit(at)


## Override: react to a hit (knockback, flash).
func _on_hit(_damage: float, _impulse: Vector2) -> void:
	pass


## Override: hide, disable collision, park off-map. Must set active = false.
func deactivate() -> void:
	active = false
