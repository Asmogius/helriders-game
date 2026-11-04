extends RefCounted
## P4 style sample (VISUAL_PLAN V5.1/V5.2/V5.5): bakes one map corner in the
## Outer Blocks look (grass, sidewalks, asphalt, low houses, bushes and trees)
## from the generated atlases in art/map/ into ONE texture, so the corner costs
## a single draw. Returns null when the art is missing or unreadable; the arena
## then keeps its code-drawn look (fallback rule). Purely visual: collision,
## layout data and every number in tuning.gd stay as they are.

const ArtAtlas := preload("res://scripts/art_atlas.gd")
const T := preload("res://scripts/tuning.gd")

const TILES := "res://art/map/outer_tiles"
const HOUSE := "res://art/map/outer_house"
const PROPS := "res://art/map/outer_props"   # optional: no props atlas = no decor
## The sample corner (north-west of the map). Not a rollout: one corner only.
const CORNER := Rect2(0, 0, 1500, 880)
const TILE := 64
const WALL_H := 30
const ROOF_TILE := 32
const SIDEWALK := 30
const WALL2_H := 46       # two-storey flat-roof block
const CURB_R := 24        # curb return radius at junction corners
const XWALK := 44         # crosswalk depth
const XGAP := 8           # gap between junction box and crosswalk


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
	var props: RefCounted = ArtAtlas.load_atlas(PROPS)
	var pi: Image = _image_of(props.texture) if props.ok() else null
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
	var junctions := _junctions(roads)

	# Lawn everywhere, then sidewalks along roads and aprons round houses.
	_fill(img, ti, tiles, "grass_", Rect2(Vector2.ZERO, corner.size), rng)
	for r: Rect2 in roads:
		_fill(img, ti, tiles, "pave_", r.grow(SIDEWALK), rng)
	for b: Rect2 in inside:
		_fill(img, ti, tiles, "pave_", b.grow(14), rng)
	# Asphalt as one surface (junctions filled once, no overlapping strips).
	for r: Rect2 in roads:
		_fill(img, ti, tiles, "asphalt_", r, rng)
	for j: Rect2 in junctions:
		_curb_returns(img, ti, tiles, j)
	for r: Rect2 in roads:
		_curbs_and_lines(img, ti, tiles, r, junctions, rng)
	for j: Rect2 in junctions:
		_crossings(img, ti, tiles, j, roads)

	# Keep-out for everything decorative: houses, props, stops, barrel spots.
	var keep_off: Array = []
	for b: Rect2 in inside + straddle:
		keep_off.append(b.grow(22))
	for p: Array in arena.props:
		var s: float = maxf((p[1] as Vector2).x, (p[1] as Vector2).y)
		keep_off.append(Rect2((p[0] as Vector2) - off - Vector2(s, s) * 0.6, Vector2(s, s) * 1.2))
	var points: Array = []
	for q: Vector2 in arena.checkpoints + arena.barrel_spots:
		points.append(q - off)
	var lanes: Array = []   # drive lanes: only flat decals there
	for r: Rect2 in roads:
		lanes.append(r.grow(-6))
	for j: Rect2 in junctions:
		lanes.append(j.grow(XGAP + XWALK + 24))

	if pi != null:
		_street_decals(img, pi, props, roads, junctions, keep_off, points, rng)

	# Bushes and trees, off roads and sidewalks.
	var green_off: Array = keep_off.duplicate()
	for r: Rect2 in roads:
		green_off.append(r.grow(SIDEWALK + 4))
	for i in 60:
		var tree := rng.randf() < 0.3
		var id := ("tree_%d" % rng.randi_range(0, 1)) if tree else ("bush_%d" % rng.randi_range(0, 2))
		if not tiles.has(id):
			continue
		var reg: Rect2 = tiles.region(id)
		var at := Vector2(rng.randf_range(0, corner.size.x - reg.size.x), rng.randf_range(0, corner.size.y - reg.size.y))
		var box := Rect2(at, reg.size)
		if _hits(box, green_off) or _near(box.get_center(), points, 70.0 + reg.size.x * 0.5):
			continue
		var sil := _silhouette(ti, Rect2i(reg), 0.32)
		img.blend_rect(sil, Rect2i(Vector2i.ZERO, sil.get_size()), Vector2i(at + Vector2(8, 6)))
		img.blend_rect(ti, Rect2i(reg), Vector2i(at))
		green_off.append(box)
		keep_off.append(box)

	var style := 0
	for b: Rect2 in inside:
		_building(img, hi, house, pi, props, b, style, rng)
		style += 1
	if pi != null:
		_street_props(img, pi, props, roads, junctions, inside, keep_off + lanes, points, rng)
	# Buildings that cross the corner edge keep their code-drawn look.
	for b: Rect2 in straddle:
		img.fill_rect(Rect2i(b.grow(4).position.floor(), b.grow(4).size.ceil() + Vector2(18, 18)), Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)


## Every overlap of a horizontal and a vertical road.
static func _junctions(roads: Array) -> Array:
	var out: Array = []
	for a: Rect2 in roads:
		if a.size.x < a.size.y:
			continue
		for b: Rect2 in roads:
			if b.size.x >= b.size.y:
				continue
			var j := a.intersection(b)
			if j.size.x > 0 and j.size.y > 0:
				out.append(j)
	return out


static func _curb_color() -> Color:
	return T.COL_OB_PAVE.lightened(0.12)


static func _gutter_color() -> Color:
	return T.COL_OB_PAVE.darkened(0.55)


## Rounded kerbs where the sidewalks meet at a junction: the asphalt sweeps
## into each block corner on a quarter circle, with the kerb drawn on the arc.
static func _curb_returns(img: Image, src: Image, atlas: RefCounted, j: Rect2) -> void:
	var asphalt: Rect2 = atlas.region("asphalt_0")
	var bounds := Rect2i(Vector2i.ZERO, img.get_size())
	var curb := _curb_color()
	var gutter := _gutter_color()
	var r := float(CURB_R)
	for corner: Vector2 in [j.position, Vector2(j.end.x, j.position.y), Vector2(j.position.x, j.end.y), j.end]:
		var sx := -1.0 if corner.x <= j.position.x else 1.0
		var sy := -1.0 if corner.y <= j.position.y else 1.0
		var o := corner + Vector2(sx, sy) * (r + 4.0)   # arc centre, out in the block
		for dy in range(0, CURB_R + 8):
			for dx in range(0, CURB_R + 8):
				var p := Vector2i(int(corner.x + sx * dx - (1 if sx < 0 else 0)), int(corner.y + sy * dy - (1 if sy < 0 else 0)))
				if not bounds.has_point(p):
					continue
				var d := (Vector2(p) + Vector2(0.5, 0.5)).distance_to(o)
				if d > r + 4.0:
					img.set_pixelv(p, src.get_pixel(int(asphalt.position.x) + p.x % TILE, int(asphalt.position.y) + p.y % TILE))
				elif d > r:
					img.set_pixelv(p, curb if d < r + 3.0 else gutter)


## Kerbs along both long edges and the centre dashes, both stopping at the
## junction box (no strips crossing the other road).
static func _curbs_and_lines(img: Image, src: Image, atlas: RefCounted, r: Rect2, junctions: Array, rng: RandomNumberGenerator) -> void:
	var curb := _curb_color()
	var gutter := _gutter_color()
	var dash: Rect2 = atlas.region("lane_dash")
	var bounds := Rect2(Vector2.ZERO, Vector2(img.get_size()))
	var horiz := r.size.x >= r.size.y
	var cuts: Array = []        # [from, to] along the road axis
	var dash_cuts: Array = []
	for j: Rect2 in junctions:
		if not r.encloses(j):
			continue
		var a := j.position.x if horiz else j.position.y
		var b := j.end.x if horiz else j.end.y
		cuts.append(Vector2(a - CURB_R - 4, b + CURB_R + 4))
		dash_cuts.append(Vector2(a - XGAP - XWALK - 30, b + XGAP + XWALK + 30))
	var start := r.position.x if horiz else r.position.y
	var end := r.end.x if horiz else r.end.y
	for seg: Vector2 in _segments(start, end, cuts):
		if horiz:
			_rect(img, Rect2(seg.x, r.position.y - 4, seg.y - seg.x, 4), curb)
			_rect(img, Rect2(seg.x, r.position.y, seg.y - seg.x, 1), gutter)
			_rect(img, Rect2(seg.x, r.end.y, seg.y - seg.x, 4), curb)
			_rect(img, Rect2(seg.x, r.end.y - 1, seg.y - seg.x, 1), gutter)
		else:
			_rect(img, Rect2(r.position.x - 4, seg.x, 4, seg.y - seg.x), curb)
			_rect(img, Rect2(r.position.x, seg.x, 1, seg.y - seg.x), gutter)
			_rect(img, Rect2(r.end.x, seg.x, 4, seg.y - seg.x), curb)
			_rect(img, Rect2(r.end.x - 1, seg.x, 1, seg.y - seg.x), gutter)
	var piece := src.get_region(Rect2i(dash))
	if not horiz:
		piece.rotate_90(CLOCKWISE)
	for seg: Vector2 in _segments(start, end, dash_cuts):
		var t := seg.x + 20.0
		while t + dash.size.x <= seg.y:
			var at := Vector2(t, r.get_center().y - 3) if horiz else Vector2(r.get_center().x - 3, t)
			if rng.randf() > 0.15 and bounds.encloses(Rect2(at, Vector2(piece.get_size()))):
				img.blend_rect(piece, Rect2i(Vector2i.ZERO, piece.get_size()), Vector2i(at))
			t += 92.0


## [start, end] minus the cut intervals, as Vector2(from, to) pieces.
static func _segments(start: float, end: float, cuts: Array) -> Array:
	cuts.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var out: Array = []
	var at := start
	for c: Vector2 in cuts:
		if c.x > at:
			out.append(Vector2(at, minf(c.x, end)))
		at = maxf(at, c.y)
	if at < end:
		out.append(Vector2(at, end))
	return out


## Zebra crosswalks on every arm of a junction and a stop line across the
## lane that drives into it (right-hand traffic).
static func _crossings(img: Image, src: Image, atlas: RefCounted, j: Rect2, roads: Array) -> void:
	var zebra := src.get_region(Rect2i(atlas.region("zebra")))      # 10 x 44, long side along traffic
	var zebra_v := zebra.duplicate() as Image
	zebra_v.rotate_90(CLOCKWISE)
	var bar := src.get_region(Rect2i(atlas.region("stop_bar")))     # 8 x 100
	var bar_v := bar.duplicate() as Image
	bar_v.rotate_90(CLOCKWISE)
	var cx := j.get_center()
	# West and east arms (horizontal road): stripes stacked down the road.
	for side in [-1, 1]:
		var x0 := (j.position.x - XGAP - XWALK) if side < 0 else (j.end.x + XGAP)
		var y := j.position.y + 8.0
		while y + 10.0 <= j.end.y - 6.0:
			_blend(img, zebra, Vector2(x0, y))
			y += 20.0
		var sx := (x0 - 14.0) if side < 0 else (x0 + XWALK + 6.0)
		var ys := cx.y + 6.0 if side < 0 else j.position.y + 6.0   # eastbound south half, westbound north half
		_tile_bar(img, bar_v, Rect2(sx, ys, 8, j.size.y * 0.5 - 12.0))
	# North and south arms (vertical road): stripes side by side.
	for side in [-1, 1]:
		var y0 := (j.position.y - XGAP - XWALK) if side < 0 else (j.end.y + XGAP)
		var x := j.position.x + 8.0
		while x + 10.0 <= j.end.x - 6.0:
			_blend(img, zebra_v, Vector2(x, y0))
			x += 20.0
		var sy := (y0 - 14.0) if side < 0 else (y0 + XWALK + 6.0)
		var xs := j.position.x + 6.0 if side < 0 else cx.x + 6.0   # southbound west half, northbound east half
		_tile_bar(img, bar, Rect2(xs, sy, j.size.x * 0.5 - 12.0, 8))


static func _tile_bar(img: Image, piece: Image, r: Rect2) -> void:
	var ps := Vector2(piece.get_size())
	var horiz := r.size.x >= r.size.y
	var t := 0.0
	var len := r.size.x if horiz else r.size.y
	while t < len:
		var w := minf((ps.x if horiz else ps.y), len - t)
		var sub := Rect2i(0, 0, int(w), int(ps.y)) if horiz else Rect2i(0, 0, int(ps.x), int(w))
		var at := r.position + (Vector2(t, 0) if horiz else Vector2(0, t))
		_blend_sub(img, piece, sub, at)
		t += w


static func _blend(img: Image, piece: Image, at: Vector2) -> void:
	_blend_sub(img, piece, Rect2i(Vector2i.ZERO, piece.get_size()), at)


## blend_rect clipped to the image (pieces near the corner edge).
static func _blend_sub(img: Image, piece: Image, sub: Rect2i, at: Vector2) -> void:
	var dst := Rect2i(Vector2i(at.floor()), sub.size)
	var cl := dst.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	if cl.size.x <= 0 or cl.size.y <= 0:
		return
	img.blend_rect(piece, Rect2i(sub.position + (cl.position - dst.position), cl.size), cl.position)


## Flat storytelling on the ground: cracks, potholes, oil, puddles on the
## asphalt; weeds in the kerb line, trash and blood on sidewalks; scorch marks.
static func _street_decals(img: Image, pi: Image, atlas: RefCounted, roads: Array, junctions: Array, keep_off: Array, points: Array, rng: RandomNumberGenerator) -> void:
	var road_kinds := ["crack_", "crack_", "pothole_", "oil_", "puddle_", "crack_", "oil_"]
	for r: Rect2 in roads:
		var n := int(r.size.x * r.size.y / 15000.0)
		for i in n:
			var kind: String = road_kinds[rng.randi_range(0, road_kinds.size() - 1)]
			var id := kind + str(rng.randi_range(0, 3 if kind == "crack_" else 2))
			var reg: Rect2 = atlas.region(id)
			var at := Vector2(rng.randf_range(r.position.x + 6, r.end.x - reg.size.x - 6), rng.randf_range(r.position.y + 6, r.end.y - reg.size.y - 6))
			if _near_any_rect(Rect2(at, reg.size), junctions, XGAP + XWALK + 4):
				continue   # keep the crossings clean
			_decal(img, pi, atlas, id, at)
		# Weeds in the gutter and trash / blood on the sidewalk strips.
		var horiz := r.size.x >= r.size.y
		var t := (r.position.x if horiz else r.position.y) + rng.randf_range(10, 60)
		var end := r.end.x if horiz else r.end.y
		while t < end:
			var side := rng.randi_range(0, 1)
			var id := "weeds_%d" % rng.randi_range(0, 3)
			var reg: Rect2 = atlas.region(id)
			var at: Vector2
			if horiz:
				at = Vector2(t, (r.position.y - 4 - reg.size.y + 3) if side == 0 else (r.end.y + 2))
			else:
				at = Vector2((r.position.x - 4 - reg.size.x * 0.5) if side == 0 else (r.end.x + 2), t)
			if not _near_any_rect(Rect2(at, reg.size), junctions, CURB_R + 6):
				_decal(img, pi, atlas, id, at)
			t += rng.randf_range(50, 150)
	var walk_kinds := ["trash_", "trash_", "blood_trail_", "blood_pool_", "crack_"]
	for i in 44:
		var kind: String = walk_kinds[rng.randi_range(0, walk_kinds.size() - 1)]
		var id := kind + str(rng.randi_range(0, 1))
		var reg: Rect2 = atlas.region(id)
		var r: Rect2 = roads[rng.randi_range(0, roads.size() - 1)]
		var horiz := r.size.x >= r.size.y
		var at: Vector2
		if horiz:
			at = Vector2(rng.randf_range(r.position.x, r.end.x - reg.size.x), (r.position.y - SIDEWALK + 2) if rng.randf() < 0.5 else (r.end.y + 6))
		else:
			at = Vector2((r.position.x - SIDEWALK + 2) if rng.randf() < 0.5 else (r.end.x + 6), rng.randf_range(r.position.y, r.end.y - reg.size.y))
		if kind == "blood_trail_" and rng.randf() < 0.5:
			at += Vector2(0, 0)   # some trails run onto the road
		if _hits(Rect2(at, reg.size), keep_off) or _near(at + reg.size * 0.5, points, 50.0):
			continue
		_decal(img, pi, atlas, id, at)
	# A blood trail dragged across the west arm of the first junction.
	if not junctions.is_empty():
		var j: Rect2 = junctions[0]
		_decal(img, pi, atlas, "blood_trail_1", Vector2(j.position.x - 190, j.end.y - 40))
		_decal(img, pi, atlas, "blood_pool_0", Vector2(j.position.x - 120, j.end.y - 48))


static func _decal(img: Image, pi: Image, atlas: RefCounted, id: String, at: Vector2) -> void:
	if not atlas.has(id):
		return
	_blend_sub(img, pi, Rect2i(atlas.region(id)), at)


## A voxel prop sprite with its soft shadow. `at` is the sprite's top-left.
static func _sprite(img: Image, pi: Image, atlas: RefCounted, id: String, at: Vector2, shadow := 0.3) -> Rect2:
	if not atlas.has(id):
		return Rect2()
	var reg := Rect2i(atlas.region(id))
	if shadow > 0.0:
		var sil := _silhouette(pi, reg, shadow)
		_blend_sub(img, sil, Rect2i(Vector2i.ZERO, sil.get_size()), at + Vector2(6, 4))
	_blend_sub(img, pi, reg, at)
	return Rect2(at, Vector2(reg.size))


## Standing decor (all baked, none collides): streetlights and stop signs at
## the junctions, wrecked and burnt cars on the verges, a sandbag and barrier
## checkpoint, fences behind the lots, a dumpster by the shop block. Lanes,
## stops and barrel spots stay clear, so nothing looks like a hidden wall.
static func _street_props(img: Image, pi: Image, atlas: RefCounted, roads: Array, junctions: Array, houses: Array, keep_off: Array, points: Array, rng: RandomNumberGenerator) -> void:
	var items: Array = []   # [bottom y, id, top-left, shadow]
	var taken: Array = keep_off.duplicate()
	var place := func(id: String, foot: Vector2, shadow: float, force: bool) -> bool:
		# `foot` = where the prop stands (bottom centre of the sprite).
		if not atlas.has(id):
			return false
		var sz: Vector2 = (atlas.region(id) as Rect2).size
		var at := foot - Vector2(sz.x * 0.5, sz.y)
		var box := Rect2(at, sz).grow(4)
		if not Rect2(Vector2.ZERO, Vector2(img.get_size())).encloses(Rect2(at, sz)):
			return false
		if not force and (_hits(box, taken) or _near(foot, points, 64.0)):
			return false
		taken.append(box)
		items.append([foot.y, id, at, shadow])
		return true
	for j: Rect2 in junctions:
		var s := float(SIDEWALK)
		# Lamps on the far side of each kerb return; stop signs by the stop lines.
		place.call("light_w", Vector2(j.position.x - CURB_R - 18, j.position.y - 6), 0.25, true)
		place.call("light_e", Vector2(j.end.x + CURB_R + 18, j.end.y + s - 4), 0.25, true)
		place.call("stop", Vector2(j.position.x - XGAP - XWALK - 18, j.end.y + s - 6), 0.25, true)
		place.call("stop", Vector2(j.end.x + XGAP + XWALK + 18, j.position.y - 8), 0.25, true)
		place.call("stop", Vector2(j.position.x - 10, j.position.y - XGAP - XWALK - 16), 0.25, true)
		# A burnt-out car shoved onto the north-west corner, scorched ground under it.
		var bc := Vector2(j.position.x - 120, j.position.y - s - 34)
		_decal(img, pi, atlas, "scorch_0", bc - Vector2(32, 44))
		place.call("burnt0_h", bc, 0.35, true)
		# Checkpoint that didn't hold: sandbags and barriers on the south-east verge.
		var cp := Vector2(j.end.x + s + 40, j.end.y + s + 50)
		place.call("sandbags_h", cp, 0.3, false)
		place.call("sandbags_v", cp + Vector2(-22, 26), 0.3, false)
		place.call("jersey_h", cp + Vector2(50, 4), 0.3, false)
		place.call("jersey_h", cp + Vector2(88, 10), 0.3, false)
		place.call("debris_0", cp + Vector2(20, 30), 0.0, false)
	# Lamps along each road, alternating sides, every ~340 px.
	for r: Rect2 in roads:
		var horiz := r.size.x >= r.size.y
		var t := (r.position.x if horiz else r.position.y) + 140.0
		var end := r.end.x if horiz else r.end.y
		var side := 0
		while t < end:
			var foot := Vector2(t, r.position.y - 8) if horiz else Vector2(r.end.x + 14, t)
			if horiz and side == 1:
				foot = Vector2(t, r.end.y + SIDEWALK - 4)
			if not _near_any_rect(Rect2(foot, Vector2.ONE), junctions, CURB_R + 70):
				place.call(("light_s" if side == 0 else "light_n") if horiz else "light_w", foot, 0.25, false)
			side = 1 - side
			t += 340.0
	# Abandoned cars on the verges and one in a front yard, plus a second burnt one.
	var cars := ["car0_h", "car1_v", "car2_a", "burnt1_v", "car1_h", "car0_a", "burnt1_h"]
	var tries := 0
	var placed := 0
	while placed < 6 and tries < 120:
		tries += 1
		var id: String = cars[rng.randi_range(0, cars.size() - 1)]
		var r: Rect2 = roads[rng.randi_range(0, roads.size() - 1)]
		var horiz := r.size.x >= r.size.y
		var foot: Vector2
		if horiz:
			foot = Vector2(rng.randf_range(r.position.x + 40, r.end.x - 40), (r.position.y - SIDEWALK - 8) if rng.randf() < 0.5 else (r.end.y + SIDEWALK + 34))
		else:
			foot = Vector2((r.position.x - SIDEWALK - 30) if rng.randf() < 0.5 else (r.end.x + SIDEWALK + 30), rng.randf_range(r.position.y + 60, r.end.y - 40))
		if place.call(id, foot, 0.35, false):
			placed += 1
			if id.begins_with("burnt"):
				_decal(img, pi, atlas, "scorch_1", foot - Vector2(32, 48))
			elif rng.randf() < 0.5:
				_decal(img, pi, atlas, "oil_%d" % rng.randi_range(0, 2), foot - Vector2(15, 12))
	# Fences along the back of each lot; dumpster and tyres beside wide blocks.
	for b: Rect2 in houses:
		var y := b.position.y - 34.0
		var x := b.position.x - 10.0
		var wood := b.size.x < 480.0
		while x + 48.0 <= b.end.x + 10.0:
			if rng.randf() > 0.2:   # gaps where the fence came down
				place.call("wfence_h" if wood else "fence_h", Vector2(x + 24, y), 0.2, true)
			x += 48.0
		place.call("wfence_v" if wood else "fence_v", Vector2(b.position.x - 30, b.position.y + 40), 0.2, false)
		if not wood:
			place.call("dumpster", Vector2(b.end.x + 30, b.end.y + 4), 0.3, false)
			place.call("tyres", Vector2(b.end.x + 48, b.end.y - 20), 0.3, false)
			place.call("debris_1", Vector2(b.end.x + 26, b.end.y + 26), 0.0, false)
		else:
			place.call("debris_2", Vector2(b.position.x - 30, b.end.y - 8), 0.0, false)
	items.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for it: Array in items:
		_sprite(img, pi, atlas, it[1], it[2], it[3])


static func _near_any_rect(box: Rect2, rects: Array, d: float) -> bool:
	for r: Rect2 in rects:
		if box.intersects(r.grow(d)):
			return true
	return false


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


## One building filling footprint `b` (collision unchanged). Styles vary the
## roof and height: a wide lot becomes a two-storey flat-roof block with
## rooftop clutter; houses alternate a hip roof with a lower flat garage wing
## and a gable turned north-south. All seen at the 30 degree tilt: roof from
## above, south wall below it.
static func _building(img: Image, src: Image, atlas: RefCounted, pi: Image, props: RefCounted, b: Rect2, style: int, rng: RandomNumberGenerator) -> void:
	_shadow(img, b, Vector2(14, 10), 0.38)
	var roof_v := rng.randi_range(0, 2)
	var wall_v := rng.randi_range(0, 2)
	if b.size.x >= 480.0 and atlas.has("gravel_0"):
		var roof := Rect2(b.position, Vector2(b.size.x, b.size.y - WALL2_H))
		_roof_flat(img, src, atlas, roof, rng)
		_wall2(img, src, atlas, b.position.x, b.size.x, roof.end.y, rng)
		if pi != null:
			_rooftop(img, pi, props, roof, rng, true)
			_decal(img, pi, props, "graffiti_0", Vector2(b.position.x + 36, roof.end.y + 24))
			_decal(img, pi, props, "graffiti_2", Vector2(b.end.x - 120, roof.end.y + 26))
		return
	var wing_w := 0.0
	if b.size.x >= 360.0 and atlas.has("gravel_0"):
		wing_w = floorf(b.size.x * 0.32 / 32.0) * 32.0
	var main := Rect2(b.position, Vector2(b.size.x - wing_w, b.size.y))
	var roof := Rect2(main.position, Vector2(main.size.x, main.size.y - WALL_H))
	if style % 2 == 0:
		_roof_hip(img, src, atlas, roof, roof_v, rng)
	else:
		_roof_gable_ns(img, src, atlas, roof, roof_v, rng)
	var ch: Rect2 = atlas.region("chimney")
	img.blend_rect(src, Rect2i(ch), Vector2i(int(rng.randf_range(roof.position.x + roof.size.y * 0.5, roof.end.x - roof.size.y * 0.5 - 14)), int(roof.position.y + 10)))
	_wall(img, src, atlas, main.position.x, main.size.x, roof.end.y, WALL_H, wall_v, rng)
	if wing_w > 0.0:
		# Lower garage wing: shorter wall, flat roof, shaded by the main house.
		var wh := 20
		var wing := Rect2(main.end.x, b.position.y + 26, wing_w, b.size.y - 26)
		var wroof := Rect2(wing.position, Vector2(wing.size.x, wing.size.y - wh))
		_fill(img, src, atlas, "pave_", Rect2(wing.position.x, b.position.y, wing_w, 26), rng)   # yard strip behind it
		_roof_flat(img, src, atlas, wroof, rng)
		_shadow(img, Rect2(wroof.position, Vector2(10, wroof.size.y)), Vector2.ZERO, 0.35)
		_wall(img, src, atlas, wing.position.x, wing_w, wroof.end.y, wh, (wall_v + 1) % 3, rng, true)
		if pi != null:
			_rooftop(img, pi, props, wroof, rng, false)
			_decal(img, pi, props, "graffiti_1", Vector2(wing.position.x + 6, wroof.end.y + 4))


static func _outline() -> Color:
	return Color(0.047, 0.043, 0.051)


## Hip roof: north slope lit, south dark, west and east triangles in between.
static func _roof_hip(img: Image, src: Image, atlas: RefCounted, roof: Rect2, v: int, rng: RandomNumberGenerator) -> void:
	var ridge := roof.position.y + roof.size.y * 0.5
	_fill_piece(img, src, atlas, "roof%d_lit_" % v, Rect2(roof.position, Vector2(roof.size.x, ridge - roof.position.y)), rng)
	_fill_piece(img, src, atlas, "roof%d_dark_" % v, Rect2(Vector2(roof.position.x, ridge), Vector2(roof.size.x, roof.end.y - ridge)), rng)
	var half := roof.size.y * 0.5
	var west := Color(1, 1, 1, 0.07)
	var east := Color(0, 0, 0, 0.22)
	var o := _outline()
	for y in range(int(roof.position.y), int(roof.end.y)):
		var d := minf(y - roof.position.y, roof.end.y - 1 - y)
		var w := int(d)
		if w > 0:
			_tint_row(img, Vector2i(int(roof.position.x), y), w, west)
			_tint_row(img, Vector2i(int(roof.end.x) - w, y), w, east)
		_px(img, Vector2i(int(roof.position.x) + w, y), o)
		_px(img, Vector2i(int(roof.end.x) - 1 - w, y), o)
	_rect(img, Rect2(roof.position.x + half, ridge - 1, roof.size.x - half * 2.0, 2), o)
	_frame(img, roof, o)


## Gable with the ridge running north-south: west slope lit, east dark.
static func _roof_gable_ns(img: Image, src: Image, atlas: RefCounted, roof: Rect2, v: int, rng: RandomNumberGenerator) -> void:
	var mid := roof.position.x + floorf(roof.size.x * 0.5)
	_fill_piece(img, src, atlas, "roof%d_lit_" % v, Rect2(roof.position, Vector2(mid - roof.position.x, roof.size.y)), rng)
	_fill_piece(img, src, atlas, "roof%d_dark_" % v, Rect2(Vector2(mid, roof.position.y), Vector2(roof.end.x - mid, roof.size.y)), rng)
	var o := _outline()
	_rect(img, Rect2(mid - 1, roof.position.y, 3, roof.size.y), o)
	_frame(img, roof, o)


static func _roof_flat(img: Image, src: Image, atlas: RefCounted, roof: Rect2, rng: RandomNumberGenerator) -> void:
	var y := roof.position.y
	while y < roof.end.y:
		var x := roof.position.x
		while x < roof.end.x:
			var reg: Rect2 = atlas.region("gravel_%d" % rng.randi_range(0, 2))
			img.blit_rect(src, Rect2i(int(reg.position.x), int(reg.position.y), int(minf(reg.size.x, roof.end.x - x)), int(minf(reg.size.y, roof.end.y - y))), Vector2i(int(x), int(y)))
			x += reg.size.x
		y += ROOF_TILE
	# Parapet: a lit lip on top, a dark inner edge.
	var lip := T.COL_OB_PAVE.lightened(0.05)
	_rect(img, Rect2(roof.position.x, roof.position.y, roof.size.x, 4), lip)
	_rect(img, Rect2(roof.position.x, roof.position.y, 4, roof.size.y), lip)
	_rect(img, Rect2(roof.end.x - 4, roof.position.y, 4, roof.size.y), lip.darkened(0.25))
	_rect(img, Rect2(roof.position.x, roof.end.y - 4, roof.size.x, 4), lip.darkened(0.15))
	_rect(img, Rect2(roof.position.x + 4, roof.position.y + 4, roof.size.x - 8, 2), Color(0, 0, 0, 0.0))
	_shadow(img, Rect2(roof.position + Vector2(4, 4), Vector2(roof.size.x - 8, 3)), Vector2.ZERO, 0.3)
	_frame(img, roof, _outline())


## Rooftop clutter: AC units, vents, a water tank on big blocks, junk.
static func _rooftop(img: Image, pi: Image, props: RefCounted, roof: Rect2, rng: RandomNumberGenerator, big: bool) -> void:
	var taken: Array = []
	var want := ["ac", "ac", "vent", "vent", "vent", "ac", "debris_2"] if big else ["vent", "ac"]
	if big:
		want.insert(0, "tank")
	for id: String in want:
		if not props.has(id):
			continue
		var sz: Vector2 = (props.region(id) as Rect2).size
		for k in 12:
			var at := Vector2(rng.randf_range(roof.position.x + 10, roof.end.x - sz.x - 10), rng.randf_range(roof.position.y + 8, roof.end.y - sz.y - 8))
			var box := Rect2(at, sz).grow(4)
			if _hits(box, taken):
				continue
			taken.append(box)
			_sprite(img, pi, props, id, at, 0.35)
			break
	if big and props.has("weeds_0"):
		for k in 4:   # weeds in the parapet gutter
			_decal(img, pi, props, "weeds_%d" % rng.randi_range(0, 3), Vector2(rng.randf_range(roof.position.x + 6, roof.end.x - 40), roof.end.y - 18))


## Single-storey south wall from 32 px pieces, optionally cut down to `h` rows.
static func _wall(img: Image, src: Image, atlas: RefCounted, x0: float, w: float, y: float, h: int, wall_v: int, rng: RandomNumberGenerator, garage := false) -> void:
	var n := int(w / 32.0)
	var door := rng.randi_range(1, maxi(1, n - 2))
	for i in n:
		var kind := "door" if i == door else ("plain" if i % 2 == 0 else ("lit" if rng.randf() < 0.25 else "window"))
		if garage:
			kind = "plain" if i == 0 or i == n - 1 else "door"
		var reg: Rect2 = atlas.region("wall%d_%s" % [wall_v, kind])
		img.blit_rect(src, Rect2i(int(reg.position.x), int(reg.position.y), int(reg.size.x), mini(h, int(reg.size.y))), Vector2i(int(x0 + i * 32), int(y)))
	var rest := w - n * 32
	if rest > 0:
		var reg2: Rect2 = atlas.region("wall%d_plain" % wall_v)
		img.blit_rect(src, Rect2i(int(reg2.position.x), int(reg2.position.y), int(rest), mini(h, int(reg2.size.y))), Vector2i(int(x0 + n * 32), int(y)))
	_rect(img, Rect2(x0, y + h - 2, w, 2), _outline())


## Two-storey shop-front wall (flat-roof block).
static func _wall2(img: Image, src: Image, atlas: RefCounted, x0: float, w: float, y: float, rng: RandomNumberGenerator) -> void:
	var kinds := ["window", "window", "boarded", "broken", "lit", "shutter", "window", "boarded"]
	var n := int(w / 32.0)
	var door := rng.randi_range(2, maxi(2, n - 3))
	for i in n + 1:
		var kind: String = "door" if i == door else kinds[rng.randi_range(0, kinds.size() - 1)]
		var reg: Rect2 = atlas.region("wall2_" + kind)
		var piece_w := int(minf(reg.size.x, w - i * 32))
		if piece_w <= 0:
			break
		img.blit_rect(src, Rect2i(int(reg.position.x), int(reg.position.y), piece_w, int(reg.size.y)), Vector2i(int(x0 + i * 32), int(y)))
	_rect(img, Rect2(x0, y + WALL2_H - 2, w, 2), _outline())


static func _frame(img: Image, r: Rect2, c: Color) -> void:
	_rect(img, Rect2(r.position.x, r.position.y, r.size.x, 2), c)
	_rect(img, Rect2(r.position.x, r.position.y, 2, r.size.y), c)
	_rect(img, Rect2(r.end.x - 2, r.position.y, 2, r.size.y), c)


static func _px(img: Image, p: Vector2i, c: Color) -> void:
	if Rect2i(Vector2i.ZERO, img.get_size()).has_point(p):
		img.set_pixelv(p, c)


static func _tint_row(img: Image, at: Vector2i, w: int, c: Color) -> void:
	var row := Image.create(w, 1, false, Image.FORMAT_RGBA8)
	row.fill(c)
	_blend(img, row, Vector2(at))


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
