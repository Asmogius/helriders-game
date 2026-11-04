extends SceneTree
## Headless check of the voxel sprite sheets: loads each sheet's metadata,
## checks texture size against the frame grid, and that DirectionalSprite
## picks the right frame for all 32 headings (with jitter, negatives, wrap).

const DS := preload("res://scripts/directional_sprite.gd")
var fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		printerr("FAIL: ", msg)


func _init() -> void:
	for name in ["scrap_frame", "outrider", "pintle_turret"]:
		var path := "res://art/sprites/%s.json" % name
		var s: Sprite2D = DS.new()
		s.meta_path = path
		root.add_child(s)
		check(s.load_meta(path), name + ": meta loads")
		check(s.texture != null, name + ": texture loads")
		if s.texture == null:
			continue
		var m: Dictionary = s.meta
		check(int(m.directions) == 32, name + ": 32 directions")
		check(s.texture.get_width() == int(m.frame_w) * int(m.columns), name + ": sheet width")
		check(s.texture.get_height() == int(m.frame_h) * int(ceil(float(m.directions) / m.columns)), name + ": sheet height")
		check(s.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, name + ": nearest filter")
		var step := TAU / 32.0
		for i in 32:
			for jitter in [0.0, step * 0.49, -step * 0.49]:
				s.heading = i * step + jitter
				check(s.frame == i, "%s: heading %d%+.2f -> frame %d" % [name, i, jitter, s.frame])
				s.heading = i * step + jitter - TAU * 3.0
				check(s.frame == i, "%s: wrapped heading %d -> frame %d" % [name, i, s.frame])
		for chunk in m.chunks:
			check(s.chunk_texture(chunk) != null, name + ": chunk sheet " + chunk)
			check((m.chunks[chunk].offsets as Array).size() == 32, name + ": offsets " + chunk)
			s.heading = 0.0
			s.chunk_offset(chunk)
	print("art_sheet_test: ", "PASS" if fails == 0 else "%d FAILURES" % fails)
	quit(1 if fails else 0)
