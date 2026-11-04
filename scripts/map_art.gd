extends RefCounted
## P4 style sample (VISUAL_PLAN V5.1/V5.2/V5.5): bakes one map corner in the
## Outer Blocks look (grass, sidewalks, asphalt, low houses, bushes and trees)
## from the generated atlases in art/map/ into ONE texture, so the corner costs
## a single draw. Returns null when the art is missing or unreadable; the arena
## then keeps its code-drawn look (fallback rule). Purely visual: collision,
## layout data and every number in tuning.gd stay as they are.

const ArtAtlas := preload("res://scripts/art_atlas.gd")

const TILES := "res://art/map/outer_tiles"
const HOUSE := "res://art/map/outer_house"
## The sample corner (north-west of the map). Not a rollout: one corner only.
const CORNER := Rect2(0, 0, 1500, 880)
const TILE := 64
const WALL_H := 30
const ROOF_TILE := 32
const SIDEWALK := 30


## `arena` is any object with buildings, roads, props, checkpoints and
## barrel_spots (arena.gd). Same arena in, same picture out (seeded).
static func bake(arena: Object, corner := CORNER) -> ImageTexture:
	var tiles: RefCounted = ArtAtlas.load_atlas(TILES)
	var house: RefCounted = ArtAtlas.load_atlas(HOUSE)
	if not tiles.ok() or not house.ok():
		return null
	var ti := _image_of(tiles.texture)
	var hi := _image_of(house.texture)
	if ti == null or hi == null:
		return null
	var size := Vector2i(corner.size)
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	var off := corner.position
	var roads: Array = []
	for r: Rect2 in arena.roads:
		if r.intersects(corner):
			roads.append(Rect2(r.position - off, r.size))
	var inside: Array = []
	var straddle: Array = []
	for b: Rect2 in arena.buildings:
		if corner.encloses(b):
			inside.append(Rect2(b.position - off, b.size))
		elif corner.intersects(b.grow(24)):
			straddle.append(Rect2(b.position - off, b.size))

	# Lawn everywhere, then sidewalks along roads and aprons round houses.
	_fill(img, ti, tiles, "grass_", Rect2(Vector2.ZERO, corner.size), rng)
	for r: Rect2 in roads:
		_fill(img, ti, tiles, "pave_", r.grow(SIDEWALK), rng)
	for b: Rect2 in inside:
		_fill(img, ti, tiles, "pave_", b.grow(14), rng)
	for r: Rect2 in roads:
		_fill(img, ti, tiles, "asphalt_", r, rng)
		_curbs_and_lines(img, ti, tiles, r, rng)

	# Bushes and trees: decoration only, kept off roads, houses, props and
	# anything the player needs to read (stops, barrel spots).
	var keep_off: Array = []
	for r: Rect2 in roads:
		keep_off.append(r.grow(SIDEWALK + 4))
	for b: Rect2 in inside + straddle:
		keep_off.append(b.grow(22))
	for p: Array in arena.props:
		var s: float = maxf((p[1] as Vector2).x, (p[1] as Vector2).y)
		keep_off.append(Rect2((p[0] as Vector2) - off - Vector2(s, s) * 0.6, Vector2(s, s) * 1.2))
	var points: Array = []
	points.append_array(arena.checkpoints)
	points.append_array(arena.barrel_spots)
	for i in 60:
		var tree := rng.randf() < 0.3
		var id := ("tree_%d" % rng.randi_range(0, 1)) if tree else ("bush_%d" % rng.randi_range(0, 2))
		if not tiles.has(id):
			continue
		var reg: Rect2 = tiles.region(id)
		var at := Vector2(rng.randf_range(0, corner.size.x - reg.size.x), rng.randf_range(0, corner.size.y - reg.size.y))
		var box := Rect2(at, reg.size)
		if _hits(box, keep_off) or _near(box.get_center() + off, points, 70.0 + reg.size.x * 0.5):
			continue
		var sil := _silhouette(ti, Rect2i(reg), 0.32)
		img.blend_rect(sil, Rect2i(Vector2i.ZERO, sil.get_size()), Vector2i(at + Vector2(8, 6)))
		img.blend_rect(ti, Rect2i(reg), Vector2i(at))
		keep_off.append(box)

	for b: Rect2 in inside:
		_house(img, hi, house, b, rng)
	# Buildings that cross the corner edge keep their code-drawn look.
	for b: Rect2 in straddle:
		img.fill_rect(Rect2i(b.grow(4).position.floor(), b.grow(4).size.ceil() + Vector2(18, 18)), Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)


static func _image_of(tex: Texture2D) -> Image:
	if tex == null:
		return null
	var im := tex.get_image()
	if im == null or im.is_empty():
		return null
	if im.is_compressed():
		im.decompress()
	im.convert(Image.FORMAT_RGBA8)
	return im


## Tiles `rect` (clipped to the image) with a random variant of `prefix`.
static func _fill(img: Image, src: Image, atlas: RefCounted, prefix: String, rect: Rect2, rng: RandomNumberGenerator) -> void:
	var r := rect.intersection(Rect2(Vector2.ZERO, Vector2(img.get_size())))
	if r.size.x <= 0 or r.size.y <= 0:
		return
	var y := r.position.y
	while y < r.end.y:
		var x := r.position.x
		while x < r.end.x:
			var reg: Rect2 = atlas.region(prefix + str(rng.randi_range(0, 3)))
			var w := minf(TILE, r.end.x - x)
			var h := minf(TILE, r.end.y - y)
			img.blit_rect(src, Rect2i(int(reg.position.x), int(reg.position.y), int(w), int(h)), Vector2i(int(x), int(y)))
			x += TILE
		y += TILE


static func _curbs_and_lines(img: Image, src: Image, atlas: RefCounted, r: Rect2, rng: RandomNumberGenerator) -> void:
	var curb := Color(0.3, 0.295, 0.28)
	var dash: Rect2 = atlas.region("lane_dash")
	var bounds := Rect2(Vector2.ZERO, Vector2(img.get_size()))
	if r.size.x >= r.size.y:
		_rect(img, Rect2(r.position.x, r.position.y - 4, r.size.x, 4), curb)
		_rect(img, Rect2(r.position.x, r.end.y, r.size.x, 4), curb)
		var x := r.position.x + 20.0
		while x < r.end.x:
			var at := Vector2(x, r.get_center().y - 3)
			if rng.randf() > 0.15 and bounds.encloses(Rect2(at, dash.size)):
				img.blend_rect(src, Rect2i(dash), Vector2i(at))
			x += 92.0
	else:
		_rect(img, Rect2(r.position.x - 4, r.position.y, 4, r.size.y), curb)
		_rect(img, Rect2(r.end.x, r.position.y, 4, r.size.y), curb)
		var y := r.position.y + 20.0
		var vdash := src.get_region(Rect2i(dash))
		vdash.rotate_90(CLOCKWISE)
		while y < r.end.y:
			var at := Vector2(r.get_center().x - 3, y)
			if rng.randf() > 0.15 and bounds.encloses(Rect2(at, Vector2(dash.size.y, dash.size.x))):
				img.blend_rect(vdash, Rect2i(Vector2i.ZERO, vdash.get_size()), Vector2i(at))
			y += 92.0


## A low house filling building rect `b`: gable roof (lit north slope, dark
## south slope), ridge, chimney, and the south wall seen at the 30 degree tilt.
static func _house(img: Image, src: Image, atlas: RefCounted, b: Rect2, rng: RandomNumberGenerator) -> void:
	_shadow(img, b, Vector2(14, 10), 0.38)
	var roof_v := rng.randi_range(0, 2)
	var wall_v := rng.randi_range(0, 2)
	var roof := Rect2(b.position, Vector2(b.size.x, b.size.y - WALL_H))
	var ridge := roof.position.y + roof.size.y * 0.5
	var lit := Rect2(roof.position, Vector2(roof.size.x, ridge - roof.position.y))
	var dark := Rect2(Vector2(roof.position.x, ridge), Vector2(roof.size.x, roof.end.y - ridge))
	_fill_piece(img, src, atlas, "roof%d_lit_" % roof_v, lit, rng)
	_fill_piece(img, src, atlas, "roof%d_dark_" % roof_v, dark, rng)
	var outline := Color(0.047, 0.043, 0.051)
	_rect(img, Rect2(roof.position.x, ridge - 1, roof.size.x, 3), outline)
	_rect(img, Rect2(roof.position.x, roof.position.y, roof.size.x, 2), outline)
	_rect(img, Rect2(roof.position.x, roof.position.y, 2, roof.size.y), outline)
	_rect(img, Rect2(roof.end.x - 2, roof.position.y, 2, roof.size.y), outline)
	var ch: Rect2 = atlas.region("chimney")
	img.blend_rect(src, Rect2i(ch), Vector2i(int(rng.randf_range(roof.position.x + 20, roof.end.x - 40)), int(roof.position.y + 8)))
	# South wall: windows, one door, a few warm lit windows.
	var n := int(b.size.x / 32.0)
	var door := rng.randi_range(1, maxi(1, n - 2))
	for i in n:
		var kind := "door" if i == door else ("plain" if i % 2 == 0 else ("lit" if rng.randf() < 0.25 else "window"))
		var reg: Rect2 = atlas.region("wall%d_%s" % [wall_v, kind])
		img.blit_rect(src, Rect2i(reg), Vector2i(int(b.position.x + i * 32), int(roof.end.y)))
	var rest := b.size.x - n * 32
	if rest > 0:
		var reg2: Rect2 = atlas.region("wall%d_plain" % wall_v)
		img.blit_rect(src, Rect2i(int(reg2.position.x), int(reg2.position.y), int(rest), int(reg2.size.y)), Vector2i(int(b.position.x + n * 32), int(roof.end.y)))
	_rect(img, Rect2(b.position.x, b.end.y - 2, b.size.x, 2), outline)


static func _fill_piece(img: Image, src: Image, atlas: RefCounted, prefix: String, r: Rect2, rng: RandomNumberGenerator) -> void:
	var y := r.position.y
	while y < r.end.y:
		var x := r.position.x
		while x < r.end.x:
			var reg: Rect2 = atlas.region(prefix + str(rng.randi_range(0, 1)))
			img.blit_rect(src, Rect2i(int(reg.position.x), int(reg.position.y), int(minf(reg.size.x, r.end.x - x)), int(minf(reg.size.y, r.end.y - y))), Vector2i(int(x), int(y)))
			x += reg.size.x
		y += ROOF_TILE


static func _rect(img: Image, r: Rect2, c: Color) -> void:
	var cl := r.intersection(Rect2(Vector2.ZERO, Vector2(img.get_size())))
	if cl.size.x > 0 and cl.size.y > 0:
		img.fill_rect(Rect2i(cl.position.floor(), cl.size.ceil()), c)


static func _shadow(img: Image, r: Rect2, by: Vector2, alpha: float) -> void:
	var s := Rect2(r.position + by, r.size).intersection(Rect2(Vector2.ZERO, Vector2(img.get_size())))
	if s.size.x <= 0 or s.size.y <= 0:
		return
	var sh := Image.create(int(s.size.x), int(s.size.y), false, Image.FORMAT_RGBA8)
	sh.fill(Color(0, 0, 0, alpha))
	img.blend_rect(sh, Rect2i(Vector2i.ZERO, sh.get_size()), Vector2i(s.position))


## A soft drop shadow shaped like the sprite (alpha only). Bake time only.
static func _silhouette(src: Image, r: Rect2i, alpha: float) -> Image:
	var out := src.get_region(r)
	for y in out.get_height():
		for x in out.get_width():
			var a := out.get_pixel(x, y).a
			out.set_pixel(x, y, Color(0, 0, 0, a * alpha))
	return out


static func _hits(box: Rect2, rects: Array) -> bool:
	for r: Rect2 in rects:
		if box.intersects(r):
			return true
	return false


static func _near(p: Vector2, points: Array, d: float) -> bool:
	for q: Vector2 in points:
		if p.distance_to(q) < d:
			return true
	return false
