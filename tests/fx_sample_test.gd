extends SceneTree
## V4 style sample: atlas explosion + tracers, and the code-drawn fallback.

const Fx := preload("res://scripts/fx.gd")
const BulletPool := preload("res://scripts/bullet_pool.gd")
var fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		printerr("FAIL: ", msg)


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var fx: Node2D = Fx.new()
	root.add_child(fx)
	if fx.atlas != null:
		var kids := fx.get_child_count()
		fx.explosion(Vector2(100, 100), Vector2.ZERO)
		check(fx.glow.live_count() >= 5, "explosion: flash, fireballs and ring on the glow layer")
		check(fx.smoke.live_count() >= 10, "explosion: debris and smoke column")
		check(fx.decals.live_count() == 1, "explosion: scorch decal")
		check(fx.glow.material is CanvasItemMaterial and (fx.glow.material as CanvasItemMaterial).blend_mode == CanvasItemMaterial.BLEND_MODE_ADD, "glow layer is additive")
		for i in 40:
			fx.explosion(Vector2(i, i), Vector2.ZERO)
		check(fx.get_child_count() == kids and fx.glow.live_count() <= fx.glow.MAX, "pooled: no nodes per explosion, capped")
	# Fallback: no atlas -> square particles, no error.
	fx.glow = null
	fx._count = 0
	var before: int = fx._count
	fx.explosion(Vector2.ZERO, Vector2.ZERO)
	check(fx._count > before, "fallback explosion still draws squares")
	var bp: Node2D = BulletPool.new()
	root.add_child(bp)
	bp._tracer_tried = true
	bp._tracer = null
	bp.queue_redraw()
	print("FX SAMPLE TEST ", "PASSED" if fails == 0 else "FAILED (%d)" % fails)
	quit(1 if fails else 0)
