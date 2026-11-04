extends RefCounted
## The six status bars (§14) for one rig or zombie: buildup that drains when
## nothing's added, a trigger when a bar fills, a short afterglow of slower
## buildup, and how long each status has left. Plain numbers, no nodes, so a
## zombie can carry one from the pool without allocating in the fight.
## Index order: shock, fire, acid, toxic, slime, goop
## (STUNNED, BURNING, CORRODED, TOXIC, SLICK, GOOPED).

const T := preload("res://scripts/tuning.gd")

enum { SHOCK, FIRE, ACID, TOXIC, SLIME, GOOP }

var build := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
var left := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
var _quiet := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
var _slow := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
var triggers := 0                 # tests and stats


static func kind_of(dtype: String) -> int:
	return T.STATUS_TYPES.find(dtype)


var drain_mult := 1.0   # Clean Lines (Gearhead perk): 2x during Tune-Up


func reset() -> void:
	build.fill(0.0)
	left.fill(0.0)
	_quiet.fill(0.0)
	_slow.fill(0.0)


## Add `amount` of buildup (before resistance) to bar `k`. Returns true when
## the bar fills and the status starts (for `seconds`).
func add(k: int, amount: float, resistance: float, seconds: float) -> bool:
	if k < 0 or amount <= 0.0:
		return false
	amount *= maxf(100.0 - resistance, 0.0) / 50.0
	if _slow[k] > 0.0:
		amount *= 0.5
	build[k] += amount
	_quiet[k] = 0.0
	if build[k] >= T.STATUS_BAR:
		trigger(k, seconds)
		return true
	return false


## Start status `k` now (a full bar, or something that fills it outright).
func trigger(k: int, seconds: float) -> void:
	build[k] = 0.0
	left[k] = maxf(left[k], seconds)
	_slow[k] = T.STATUS_AFTERGLOW
	triggers += 1


func active(k: int) -> bool:
	return left[k] > 0.0


## True while any bar has buildup on it (the HUD shows bars only then).
func building() -> bool:
	for k in 6:
		if build[k] > 0.0:
			return true
	return false


func any_active() -> bool:
	for k in 6:
		if left[k] > 0.0:
			return true
	return false


func tick(delta: float) -> void:
	for k in 6:
		if left[k] > 0.0:
			left[k] = maxf(left[k] - delta, 0.0)
		if _slow[k] > 0.0:
			_slow[k] -= delta
		if build[k] > 0.0:
			_quiet[k] += delta
			# Drain only for the time past the delay.
			var over := minf(_quiet[k] - T.STATUS_DRAIN_DELAY, delta)
			if over > 0.0:
				build[k] = maxf(build[k] - T.STATUS_DRAIN * drain_mult * over, 0.0)
