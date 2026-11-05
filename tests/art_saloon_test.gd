extends SceneTree
## Headless check of the Saloon C room bake (art/saloon/saloon_room.json).
## Verifies UI seat schema, hit_rect >= 64x64, textures load, card_side clears the fire.

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
	var data: Variant = JSON.parse_string(f.get_as_text())
	check(typeof(data) == TYPE_DICTIONARY, "json is Dictionary")
	var meta: Dictionary = data
	check(meta.has("room_size") and meta.room_size is Array and meta.room_size.size() == 2, "room_size [w,h]")
	check(int(meta.room_size[0]) == 1280 and int(meta.room_size[1]) == 720, "room_size 1280x720")
	check(meta.has("seats") and meta.seats is Array and meta.seats.size() >= 1, "seats array")
	check(FileAccess.file_exists(String(meta.get("background", ""))), "background texture")
	check(FileAccess.file_exists(String(meta.get("lights", ""))), "lights texture")
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
		check(String(seat.card_side) in ["left", "right"], "%s.card_side" % seat.id)
		# Fireplace is on the right → cards open left so they never cover it.
		check(String(seat.card_side) == "left", "%s card_side left (fireplace right)" % seat.id)
		check(seat.sprites is Dictionary, "%s.sprites" % seat.id)
		for sk in ["idle", "highlight", "dim"]:
			check(seat.sprites.has(sk), "%s.sprites.%s" % [seat.id, sk])
			check(FileAccess.file_exists(String(seat.sprites[sk])), "%s texture %s" % [seat.id, sk])
		check(not ids.has(seat.id), "unique id %s" % seat.id)
		ids[seat.id] = true
		# seat must not sit in the right card strip (x > 900) — hireables stay left/center
		check(int(seat.pos[0]) < 900, "%s pos clear of right strip" % seat.id)
	print("art_saloon_test: ", "PASS" if fails == 0 else "%d FAILURES" % fails)
	quit(1 if fails else 0)
