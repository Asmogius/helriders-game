extends SceneTree
## Saloon C bake: schema, hit_rect >= 64x64, card clears fireplace + own crew.

var fails := 0

func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		printerr("FAIL: ", msg)

func _rects_overlap(a: Array, b: Array) -> bool:
	return int(a[0]) < int(b[0]) + int(b[2]) and int(a[0]) + int(a[2]) > int(b[0]) \
		and int(a[1]) < int(b[1]) + int(b[3]) and int(a[1]) + int(a[3]) > int(b[1])

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
	check(meta.has("fireplace_rect") and meta.fireplace_rect is Array and meta.fireplace_rect.size() == 4, "fireplace_rect")
	var fire: Array = meta.fireplace_rect
	var card_left: Array = meta.get("card_left_rect", [24, 72, 356, 448])
	var card_right: Array = meta.get("card_right_rect", [900, 72, 356, 448])
	check(not _rects_overlap(card_left, fire), "left card strip clear of fireplace")
	check(not _rects_overlap(card_right, fire), "right card strip clear of fireplace")
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
		check(side == "right", "%s.card_side right (all cards open right of fireplace)" % seat.id)
		var card: Array = card_right
		check(not _rects_overlap(card, fire), "%s card clear of fireplace" % seat.id)
		check(not _rects_overlap(card, seat.hit_rect), "%s card clear of own crew hit_rect" % seat.id)
		var ax := int(seat.anchor[0]); var ay := int(seat.anchor[1])
		var in_card := ax >= int(card[0]) and ax < int(card[0]) + int(card[2]) \
			and ay >= int(card[1]) and ay < int(card[1]) + int(card[3])
		check(not in_card, "%s anchor outside card (callout target)" % seat.id)
		check(seat.sprites is Dictionary, "%s.sprites" % seat.id)
		for sk in ["idle", "highlight", "dim"]:
			check(seat.sprites.has(sk), "%s.sprites.%s" % [seat.id, sk])
			check(FileAccess.file_exists(String(seat.sprites[sk])), "%s texture %s" % [seat.id, sk])
		check(not ids.has(seat.id), "unique id %s" % seat.id)
		ids[seat.id] = true
	print("art_saloon_test: ", "PASS" if fails == 0 else "%d FAILURES" % fails)
	quit(1 if fails else 0)
