extends SceneTree
## Headless check of the Saloon C room bake (art/saloon/saloon_room.json).
## Verifies UI seat schema, hit_rect >= 64x64, textures load, card_side opens
## away from the seat and never covers the fireplace (right upper).

var fails := 0

func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		printerr("FAIL: ", msg)

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var path := "res://art/saloon/saloon_room.json"
	check(FileAccess.file_exists(path), "saloon_room.json exists")
	var f := FileAccess.open(path, FileAccess.READ)
	check(f != null, "saloon_room.json opens")
	if f == null:
		print("art_saloon_test: %d FAILURES" % fails); quit(1); return
	# GDScript has no None — use null check above; continue:
	var data: Variant = JSON.parse_string(f.get_as_text())
	check(typeof(data) == TYPE_DICTIONARY, "json is Dictionary")
	var meta: Dictionary = data
	check(meta.has("room_size") and meta.room_size is Array and meta.room_size.size() == 2, "room_size [w,h]")
	check(int(meta.room_size[0]) == 1280 and int(meta.room_size[1]) == 720, "room_size 1280x720")
	check(meta.has("seats") and meta.seats is Array and meta.seats.size() >= 1, "seats array")
	check(FileAccess.file_exists(String(meta.get("background", ""))), "background texture")
	check(FileAccess.file_exists(String(meta.get("lights", ""))), "lights texture")
	# Fireplace occupies the right-upper strip; cards opening left would cover it.
	# Seats must sit left/center; card_side must open away from the figure.
	const FIRE_X0 := 780
	const CARD_LEFT_X1 := 380
	const CARD_RIGHT_X0 := 900
	var ids := {}
	for s in meta.seats:
		check(s is Dictionary, "seat is Dictionary")
		var seat: Dictionary = s
		for k in ["id", "slot", "pos", "z", "hit_rect", "anchor", "card_side", "sprites"]:
			check(seat.has(k), "seat.%s" % k)
		check(seat.pos is Array and seat.pos.size() == 2, "%s.pos" % seat.id)
		check(seat.anchor is Array and seat.anchor.size() == 2, "%s.anchor" % seat.id)
		check(seat.hit_rect is Array and seat.hit_rect.size() == 4, "%s.hit_rect" % seat.id)
		check(int(seat.hit_rect[2]) >= 64 and int(seat.hit_rect[3]) >= 64, "%s hit_rect >= 64x64" % seat.id)
		var side := String(seat.card_side)
		check(side in ["left", "right"], "%s.card_side" % seat.id)
		var cx := int(seat.pos[0]) + int(seat.hit_rect[2]) / 2
		if cx < 700:
			check(side == "right", "%s left/center seat → card_side right (away from figure)" % seat.id)
		else:
			check(side == "left", "%s right seat → card_side left (away from figure)" % seat.id)
		# No seat under the fireplace / right card strip when card opens right
		check(int(seat.pos[0]) < FIRE_X0, "%s clear of fireplace strip" % seat.id)
		if side == "right":
			check(int(seat.pos[0]) + int(seat.hit_rect[2]) < CARD_RIGHT_X0,
				"%s figure not under right card strip" % seat.id)
		else:
			check(int(seat.pos[0]) > CARD_LEFT_X1, "%s figure not under left card strip" % seat.id)
		check(seat.sprites is Dictionary, "%s.sprites" % seat.id)
		for sk in ["idle", "highlight", "dim"]:
			check(seat.sprites.has(sk), "%s.sprites.%s" % [seat.id, sk])
			check(FileAccess.file_exists(String(seat.sprites[sk])), "%s texture %s" % [seat.id, sk])
		check(not ids.has(seat.id), "unique id %s" % seat.id)
		ids[seat.id] = true
	print("art_saloon_test: ", "PASS" if fails == 0 else "%d FAILURES" % fails)
	quit(1 if fails else 0)
