extends CharacterBody2D
## A rig: arcade drift handling, weapons, ramming, armor. The player's rig and
## enemy rigs share this script; enemy_rig.gd extends it with an AI brain.
##
## Driving: point the left stick where you want to go; pull it behind you while
## slow to reverse. Turret rigs aim with the right stick (push past halfway to
## fire) or, with lock on, aim and fire at the locked target by themselves.
##
## Crew (player only, crew.gd): the seated Driver and Gunner add passives and
## a triggered ability each, and a big hit can injure one mid-fight. A turret
## turns only with a Gunner seated or a targeting computer fitted.

signal wrecked
signal damaged(amount: float)
signal crew_injured(index: int)
signal crew_healed(index: int)
signal crew_ability_used(kind: String, ability: Dictionary)   # Mark, Flare, Magnet: the mission acts
signal status_started(kind: int)   # a status bar filled (StatusBars index)
signal revived                     # a Patcher brought this wreck back

const T := preload("res://scripts/tuning.gd")
const Hostile := preload("res://scripts/hostile.gd")
const BulletPool := preload("res://scripts/bullet_pool.gd")
const Parts := preload("res://scripts/parts.gd")
const Loadout := preload("res://scripts/loadout.gd")
const Crew := preload("res://scripts/crew.gd")
const StatusBars := preload("res://scripts/status_bars.gd")
const Tether := preload("res://scripts/tether.gd")
const Mods := preload("res://scripts/mods.gd")

enum Mount { TURRET, FIXED }

const REVERSE_ANGLE := 2.27        # ~130 degrees: stick this far behind = reverse
const AIM_DEADZONE := 0.2
const FIRE_THRESHOLD := 0.5
const RAM_MIN_SPEED := 150.0       # impact speed needed to hurt anything
const WALL_DAMAGE_SPEED := 300.0   # impact speed before walls hurt you
const LOCK_FIRE_CONE := 0.15       # radians: turret must be this close to fire on lock

var body_len := 64.0
var body_wid := 36.0

# Final stats (filled from a stats dictionary, see apply_stats).
var max_speed := 0.0
var reverse_speed := 0.0
var acceleration := 0.0
var brake := 0.0
var coast := 0.0
var turn_rate := 0.0
var grip := 0.0
var ram_damage := 0.0
var mount := Mount.TURRET
var fire_rate := 0.0
var bullet_damage := 0.0
var bullet_speed := 0.0
var spread := 0.0
var turret_turn_rate := 0.0
var lock_range := 0.0             # 0 = no lock (weapon can't, or no targeting system)
var power_output := 0.0            # engine budget (0 = no power model, e.g. enemy rigs)
var power_draw := 0.0              # constant draw of everything installed
var weight_load := 0.0             # weight of everything installed
var weight_capacity := 0.0         # chassis limit (0 = no weight model, e.g. enemy rigs)
var gun_stats: Array[Dictionary] = []   # every weapon (see loadout.gd)
var abilities: Array[Dictionary] = []   # utility parts, each with "ready_in" seconds
var look := {}                     # which parts are installed, for drawing
var manual_aim := true             # a targeting computer can aim turrets (enemy rigs: always)
var injury_mult := 1.0             # crew injury chance multiplier (Roll Cage)

# Crew riding this rig: one entry per seated member, see set_crew().
var crew: Array[Dictionary] = []
var big_hits := 0                  # big hits taken (tests and stats)
# Live crew modifiers, rebuilt by _refresh_crew_mods() when anything changes.
var crew_mods: Dictionary = Crew.base_mods()
var latch_mult := 1.0              # latched Hunter damage (hunter.gd reads it)
var vuln := 1.0                    # damage taken while marked (enemy rigs)
var vuln_left := 0.0
var crew_accel := 1.0
var crew_turn := 1.0
var crew_grip := 0.0
var crew_speed := 1.0
var crew_aim := 1.0
var crew_spread := 1.0
var crew_lock := 1.0
var crew_fire := 1.0
var crew_damage := 1.0

var team := BulletPool.TEAM_PLAYER

# Defense layers (§14): shield (recharges) -> armor per facing -> HP (zero =
# wreck). Facings: FRONT, LEFT, RIGHT, REAR.
enum { FRONT, LEFT, RIGHT, REAR }
var hp := 0.0
var hp_max := 0.0
var facing_armor := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var facing_max := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var shield := 0.0
var mods: Array = []                # unlocked part-mod ids on this build (Mods)
var shield_max := 0.0
var shield_delay := T.DEFAULT_SHIELD_DELAY
var shield_refill := T.DEFAULT_SHIELD_REFILL
var shield_skulls := 0             # enemy rigs: the shield only comes up from this many skulls
var last_facing := -1              # the facing the last hit landed on (tests, HUD)
# Statuses (§14): buildup bars and resistances (shock fire acid toxic slime goop).
var status := StatusBars.new()
var resist: Array = [50.0, 50.0, 50.0, 50.0, 50.0, 50.0]
var _burn_angle := 0.0
var spike_left := 0.0               # seconds of shredded tyres left after a spike strip
var _status_bar: EnemyStatusBar   # enemy rigs: a small bar under the hull while building

## Everything left before a wreck: HP plus every facing's armor plus the shield.
## Kept for the many readers that think in one number. Setting it refills from
## the bottom up: HP first, then armor (evenly), then the shield.
var armor: float:
	get:
		return hp + _armor_total() + shield
	set(value):
		var left := maxf(value, 0.0)
		hp = minf(left, hp_max)
		left -= hp
		var room := _armor_max_total()
		var fill := clampf(left / room, 0.0, 1.0) if room > 0.0 else 0.0
		for i in 4:
			facing_armor[i] = facing_max[i] * fill
		left -= room * fill
		shield = clampf(left, 0.0, shield_max)
## The full total. Setting it resizes HP so the total matches (tests use a
## huge value to make a rig unkillable).
var armor_max: float:
	get:
		return hp_max + _armor_max_total() + shield_max
	set(value):
		hp_max = maxf(value - _armor_max_total() - shield_max, 1.0)
		hp = minf(hp, hp_max)
var traction := 1.0                # grip multiplier: slime lowers it (set_on_slime)
var is_wrecked := false
var cannot_wreck := false          # the tutorial's loaner: patched up instead of wrecked
var lock_priority := 3             # when someone else locks onto this rig
var lock_radius := 40.0

# Inputs, set every tick by the player (mission.gd) or the AI (enemy_rig.gd).
var drive_input := Vector2.ZERO
var aim_input := Vector2.ZERO
var fire_trigger := false          # fixed-mount weapons
var lock_enabled := false:
	set(value):
		# No targeting system (or a weapon that can't lock): lock stays off.
		lock_enabled = value and can_lock()
		if not lock_enabled:
			lock_target = null
var lock_target: Node2D = null
var lock_candidates := Callable()  # returns Array[Node2D] of things to lock onto

# Wall contact this tick, read by Hunters clinging to the hull.
var touching_wall := false
var wall_normal := Vector2.ZERO
var wall_impact := 0.0             # crash speed of a fresh impact this tick, else 0
var latched: Array[Node2D] = []    # Hunters on the hull

var bullets: Node2D                # BulletPool
var fx: Node2D                     # Fx
var mines: Node2D                  # MinePool, for the Mine Dropper
var hazards: Node2D                # GroundHazards, for the Oil Slick
var shells: Node2D                 # ShellPool, for the Mortar
var tether: Tether                 # the Harpoon's cable, while it holds a rig
var harpoon_hits := 0              # spears that struck something (tests)
var lobs := 0                      # lobber shells thrown (Sludger alternates acid / goop)
var jammed_left := 0.0             # Jammer's Static Burst: shield can't recharge
var chain_target: Node2D           # Wrangler's Chain Drag: the rig on the chain

var _turret: Node2D                # the first turret, if any
var _turrets: Array[Node2D] = []   # one per weapon; null for fixed guns
var _cooldowns: Array[float] = []
var _burst_left: Array[int] = []     # rounds still to go in each gun's burst
var _burst_gap: Array[float] = []
var _ammo: Array[int] = []          # rounds left in each magazine weapon
var _reload_left: Array[float] = [] # its reload, while it's reloading
var _heat: Array[float] = []        # heat guns: 0 cold, 1 overheated
var _overheated: Array[bool] = []   # locked until the bar drains to empty
var _cable: CableLine               # draws the Harpoon spear and cable
var _fire_cooldown := 0.0
var _flash := 0.0
const DirectionalSprite := preload("res://scripts/directional_sprite.gd")
## Voxel art per chassis id (look.chassis). A chassis without art keeps the
## code-drawn hull below.
## Art lookup is by id: a chassis, weapon or enemy rig with id X wears
## res://art/sprites/X.json when that file exists (see docs/ART_PIPELINE.md).
const ART_DIR := "res://art/sprites/"
## Weapon ids that share a name with a rig id get their own sheet name.
const ART_WEAPON_ALIASES := {"": "pintle_turret", "scrapper": "scrapper_turret"}
const WRECK_PIECE_LIFE := 1.4       # s a flung wreck piece lasts (fades over the last half)
var wreck_pieces: Array[Node2D] = []   # the pieces flung by the last wreck (tests read it)
var _hull_texture: Texture2D = null
var _layer_ids: Array[String] = []
var _layer_sprites: Dictionary = {}   # layer id -> Sprite2D on the hull art
var _fixed_art: Array[Sprite2D] = []   # art for fixed guns, on the hull's nose_mount


## Sheet metadata for an art id, or "" when there is no art for it yet.
static func art_path(id: String) -> String:
	if id == "":
		return ""
	var path := ART_DIR + id + ".json"
	return path if FileAccess.file_exists(path) else ""
var _hull_art: Sprite2D = null   # DirectionalSprite, or null when drawing by code
var _art_overlay: Node2D = null  # rotates with the rig, above the hull art
var _reversing := false
var _burn_timer := 0.0
var _burn_left := 0.0
var _barrel_side := 1.0
var _lock_check := 0.0
var _lock_blind := 0.0
var _ray := PhysicsRayQueryParameters2D.new()
var _active := {}                  # crew ability kind -> its numbers + "left"
var _base_hp := 0.0
var _base_facings := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _shield_wait := 0.0
var _sheet_shield := 0.0
var _streak_timer := 0.0
# Damage taken per 0.1 s over the last second (big-hit check). No allocation.
var _dmg_buckets := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
var _bucket_i := 0
var _bucket_t := 0.0


func _init() -> void:
	apply_stats(Loadout.build(Parts.STARTER_LOADOUT))


func apply_stats(s: Dictionary) -> void:
	mods = (s.get("mods", []) as Array).duplicate()
	max_speed = s.max_speed
	reverse_speed = s.reverse_speed
	acceleration = s.acceleration
	brake = s.brake
	coast = s.coast
	turn_rate = s.turn_rate
	grip = s.grip
	_set_layers(s)
	var r: Array = s.get("resist", [])
	resist = r.duplicate() if r.size() == 6 else [50.0, 50.0, 50.0, 50.0, 50.0, 50.0]
	ram_damage = s.ram_damage
	mount = s.mount
	fire_rate = s.fire_rate
	bullet_damage = s.bullet_damage
	bullet_speed = s.bullet_speed
	spread = deg_to_rad(s.spread_deg)
	turret_turn_rate = s.turret_turn_rate
	lock_range = s.lock_range
	power_output = s.get("power_output", 0.0)
	power_draw = s.get("power_draw", 0.0)
	weight_load = s.get("weight", 0.0)
	weight_capacity = s.get("weight_capacity", 0.0)
	manual_aim = bool(s.get("manual_aim", true))
	injury_mult = float(s.get("injury_mult", 1.0))
	look = s.get("look", {})
	if s.has("body"):
		body_len = float(s.body[0])
		body_wid = float(s.body[1])
	# Weapons: a list from loadout.gd, or one gun from a flat enemy stat sheet.
	gun_stats.clear()
	if s.has("weapons"):
		for w: Dictionary in s.weapons:
			gun_stats.append(w)
	elif float(s.fire_rate) > 0.0:
		gun_stats.append({
			"id": str(s.get("gun_id", "")), "mount": int(s.mount), "fire_rate": float(s.fire_rate),
			"bullet_damage": float(s.bullet_damage), "bullet_speed": float(s.bullet_speed),
			"spread_deg": float(s.spread_deg), "turret_turn_rate": float(s.turret_turn_rate),
			"lock_range": float(s.lock_range), "pellets": int(s.get("pellets", 1)),
			"burst": int(s.get("burst", 1)), "burst_rate": float(s.get("burst_rate", 0.0)),
			"kind": str(s.get("kind", "")), "mag": int(s.get("mag", 0)), "reload": float(s.get("reload", 0.0)),
		})
		# Enemy ammo and special weapons (proposal 01): heat, lobbers, damage types.
		for key: String in ["heat_time", "lockout", "cool", "dtype", "pierce", "blast", "min_range", "max_range", "flight"]:
			if s.has(key):
				gun_stats[0][key] = s[key]
	_cooldowns.clear()
	_burst_left.clear()
	_burst_gap.clear()
	_ammo.clear()
	_reload_left.clear()
	_heat.clear()
	_overheated.clear()
	for w in gun_stats:
		_cooldowns.append(0.0)
		_burst_left.append(0)
		_burst_gap.append(0.0)
		_ammo.append(int(w.get("mag", 0)))
		_reload_left.append(0.0)
		_heat.append(0.0)
		_overheated.append(false)
	release_tether()
	abilities.clear()
	for a: Dictionary in s.get("abilities", []):
		var copy := a.duplicate()
		copy["ready_in"] = 0.0
		abilities.append(copy)
	armor = armor_max   # rolls out with every layer full
	if not can_lock():
		lock_enabled = false
	if is_inside_tree():
		_sync_parts()


## Where turret `index` of `count` sits on the hull: one gun mid-hull, two
## front and back.
func turret_position(index: int, count: int) -> Vector2:
	if count <= 1:
		return Vector2(-4.0, 0.0)
	return Vector2(body_len * (0.2 if index == 0 else -0.3), 0.0)


func has_weapon() -> bool:
	return not gun_stats.is_empty()


## Turret sprites to match the weapons (fixed guns are drawn on the nose).
func _sync_parts() -> void:
	for t in _turrets:
		if t != null:
			t.queue_free()
	_turrets.clear()
	_turret = null
	var count := gun_stats.size()
	for i in count:
		var w := gun_stats[i]
		if int(w.mount) != Mount.TURRET:
			_turrets.append(null)
			continue
		var sprite := TurretSprite.new()
		sprite.kind = str(w.get("id", ""))
		sprite.enemy = team != BulletPool.TEAM_PLAYER
		sprite.position = turret_position(i, count)
		add_child(sprite)
		var tpath := art_path(str(ART_WEAPON_ALIASES.get(sprite.kind, sprite.kind)))
		if tpath != "":
			var ta: Sprite2D = DirectionalSprite.new()
			if ta.load_meta(tpath):
				ta.meta_path = tpath
				ta.top_level = true   # never rotates; picks its frame from the aim
				ta.z_index = 1
				sprite.art = ta
				sprite.add_child(ta)
				var glow := Node2D.new()   # Overcharge: white-hot muzzle
				glow.top_level = true
				glow.z_index = 2
				glow.draw.connect(func() -> void: glow.draw_rect(Rect2(-3.0, -3.0, 6.0, 6.0), Color(1.0, 0.95, 0.8)))
				sprite.glow = glow
				sprite.add_child(glow)
			else:
				ta.free()
		_turrets.append(sprite)
		if _turret == null:
			_turret = sprite
	_sync_fixed_art()
	_sync_art()
	queue_redraw()


## Fixed guns with art (Harpoon and friends) get their own sheet, bolted to
## the hull's nose_mount; guns without art keep the stock nose-guns layer.
func _sync_fixed_art() -> void:
	for a in _fixed_art:
		a.queue_free()
	_fixed_art.clear()
	for w in gun_stats:
		if int(w.mount) != Mount.FIXED:
			continue
		var wid := str(w.get("id", ""))
		var path := art_path(str(ART_WEAPON_ALIASES.get(wid, wid))) if wid != "" else ""
		if path == "":
			continue
		var a: Sprite2D = DirectionalSprite.new()
		if a.load_meta(path):
			a.meta_path = path
			a.top_level = true
			a.z_index = 1
			a.set_meta("weapon", str(w.get("id", "")))
			add_child(a)
			_fixed_art.append(a)
		else:
			a.free()


## Which voxel sheet this rig wears ("" = drawn by code).
func _art_meta_path() -> String:
	return art_path(str(look.get("chassis", "")))


func _sync_art() -> void:
	var path := _art_meta_path()
	if _hull_art != null and (path == "" or _hull_art.meta_path != path):
		_hull_art.queue_free()
		_hull_art = null
		_layer_sprites.clear()
		_layer_ids = []
		if _art_overlay != null:
			_art_overlay.queue_free()
			_art_overlay = null
	if path != "" and _hull_art == null and ResourceLoader.exists(path.get_basename() + ".png"):
		_hull_art = DirectionalSprite.new()
		if _hull_art.load_meta(path):
			_hull_art.meta_path = path
			_hull_art.top_level = true
			_hull_texture = _hull_art.texture
			add_child(_hull_art)
			move_child(_hull_art, 0)
			_art_overlay = Node2D.new()
			_art_overlay.top_level = true
			_art_overlay.draw.connect(_on_overlay_draw.bind(_art_overlay))
			add_child(_art_overlay)
			move_child(_art_overlay, 1)
		else:
			_hull_art.free()
			_hull_art = null
	_update_art()


## Per-layer tint/alpha (state layers that fade or pulse override this).
func art_layer_modulate(_id: String) -> Color:
	return Color.WHITE


## Art follows the rig: the hull sheet picks the frame for the rig's heading,
## part layers ride on it with the same frame, each turret sheet picks the
## frame for its own aim, placed on the hull's projected mount point.
## Gameplay (bodies, turret pivots, muzzles) is untouched.
func _update_art() -> void:
	if _hull_art != null:
		_hull_art.visible = visible
		_hull_art.global_position = global_position
		_hull_art.heading = global_rotation
		_hull_art.modulate = Color.WHITE if is_wrecked else Color.WHITE.lerp(Color(1.6, 1.4, 1.2), _flash * 0.6)
		var want := art_layers()
		if want != _layer_ids:
			_rebuild_layers(want)
		for id: String in _layer_sprites:
			var ls: Sprite2D = _layer_sprites[id]
			ls.frame = _hull_art.frame
			ls.visible = not is_wrecked
			ls.modulate = art_layer_modulate(id)
	if _art_overlay != null:
		_art_overlay.global_position = global_position
		_art_overlay.global_rotation = global_rotation
	var total := _turrets.size()
	for i in total:
		var t = _turrets[i]
		if t == null or t.art == null:
			continue
		var a: Sprite2D = t.art
		a.heading = t.global_rotation
		var base: Vector2 = t.global_position
		if _hull_art != null:
			base = global_position + _hull_art.point_offset(art_mount_name(i, total))
		a.global_position = base - a.point_offset("pivot")
		if t.glow != null:
			t.glow.visible = t.hot and t.visible
			t.glow.global_position = a.global_position + a.point_offset("muzzle")
	for k in _fixed_art.size():
		var fa := _fixed_art[k]
		fa.visible = visible and not is_wrecked
		fa.heading = global_rotation
		var at := global_position + Vector2(body_len * 0.35, 0.0).rotated(global_rotation)
		if _hull_art != null and _hull_art.meta.has("points") and _hull_art.meta.points.has("nose_mount"):
			at = global_position + _hull_art.point_offset("nose_mount")
		fa.global_position = at - fa.point_offset("pivot")


## Which hull point turret `index` of `total` sits on.
static func art_mount_name(index: int, total: int) -> String:
	if total >= 2:
		return "mount_a" if index == 0 else "mount_b"
	return "turret_mount"


## The part layers (voxel sheets over the hull) for the equipped parts, in
## draw order: drive, front armor, extras. A part without its own sheet uses
## the stock one for that slot.
func art_layers() -> Array[String]:
	var ids: Array[String] = []
	if _hull_art == null or not _hull_art.meta.has("layers"):
		return ids
	var have: Dictionary = _hull_art.meta.layers
	var drive := "drive:" + str(look.get("drive", "street_wheels"))
	ids.append(drive if have.has(drive) else "drive:street_wheels")
	var armor := "armor:" + str(look.get("armor", "scrap_plating"))
	ids.append(armor if have.has(armor) else "armor:scrap_plating")
	for w in gun_stats:
		if int(w.mount) == Mount.FIXED and art_path(str(w.get("id", ""))) == "":
			ids.append("nose_guns_hot" if _active.has("overcharge") or _active.has("deadeye") else "nose_guns")
			break
	var utils: Array = look.get("utility", [])
	if utils.has("shock_pulse"):
		ids.append("shock_emitter")
	if utils.has("emergency_patch"):
		ids.append("patch_kit")
	if utils.has("mine_dropper"):
		ids.append("mine_rack")
	var internal: Array = look.get("internal", [])
	if internal.has("targeting_computer") or internal.has("advanced_targeting"):
		ids.append("sensor_dish")
	if internal.has("roll_cage"):
		ids.append("roll_cage")
	return ids.filter(func(id: String) -> bool: return have.has(id))


func _rebuild_layers(want: Array[String]) -> void:
	for id: String in _layer_sprites:
		(_layer_sprites[id] as Node).queue_free()
	_layer_sprites.clear()
	_layer_ids = want
	var dir := String(_hull_art.meta_path).get_base_dir()
	for id in want:
		var ls := Sprite2D.new()
		ls.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		ls.texture = load(dir.path_join(String(_hull_art.meta.layers[id].sheet)))
		ls.hframes = _hull_art.hframes
		ls.vframes = _hull_art.vframes
		ls.frame = _hull_art.frame
		_hull_art.add_child(ls)
		_layer_sprites[id] = ls


## Wreck: every core part but the chassis, and every piece of the fitted part
## layers (each wheel on its own), flies off from where it sits at this
## heading; the chassis stays as the burnt-out hull (lights out).
func _spawn_wreck_pieces() -> void:
	wreck_pieces.clear()
	if _hull_art == null or _hull_art.meta.is_empty():
		return
	var world := get_parent()
	if world == null:
		return
	var meta: Dictionary = _hull_art.meta
	var dir := String(_hull_art.meta_path).get_base_dir()
	var sources: Array = []   # [sheet, offsets]
	for name: String in meta.chunks:
		if name != "chassis":
			sources.append([meta.chunks[name].sheet, meta.chunks[name].offsets])
	for id in _layer_ids:
		var pieces: Dictionary = meta.layers[id].pieces
		for pn: String in pieces:
			sources.append([pieces[pn].sheet, pieces[pn].offsets])
	var f: int = _hull_art.frame
	for src: Array in sources:
		var p := WreckPiece.new()
		p.texture = load(dir.path_join(String(src[0])))
		p.hframes = _hull_art.hframes
		p.vframes = _hull_art.vframes
		p.frame = f
		p.position = global_position
		var o: Array = src[1][f]
		var off := Vector2(float(o[0]), float(o[1]))
		var d := off.normalized() if off.length() > 0.5 else Vector2.RIGHT.rotated(randf() * TAU)
		p.velocity = d.rotated(randf_range(-0.35, 0.35)) * randf_range(160.0, 300.0) + velocity * 0.4
		p.spin = randf_range(-7.0, 7.0)
		p.life = WRECK_PIECE_LIFE
		p.z_index = 3
		world.add_child(p)
		wreck_pieces.append(p)
	if meta.has("burnt"):
		_hull_art.texture = load(dir.path_join(String(meta.burnt)))
	elif meta.chunks.has("chassis"):
		_hull_art.texture = _hull_art.chunk_texture("chassis")
	for id: String in _layer_sprites:
		(_layer_sprites[id] as CanvasItem).visible = false


func _process(_delta: float) -> void:
	if _hull_art != null or _turret != null:
		_update_art()
	if _art_overlay != null:
		_art_overlay.visible = not is_wrecked and visible
		_art_overlay.queue_redraw()


func _on_overlay_draw(node: Node2D) -> void:
	if node == _art_overlay:
		_draw_art_overlay()


## Readability marks over a voxel hull (rig-local, rotates with it). Parts
## are voxel layers now; enemy rigs draw their vulnerable ring and elite stripe.
func _draw_art_overlay() -> void:
	pass


func can_lock() -> bool:
	return lock_range > 0.0


## Lock range with an Epic+ Gunner's bonus.
func lock_reach() -> float:
	return lock_range * crew_lock


## Turrets turn only with a Gunner seated or a targeting computer fitted.
func can_aim_turrets() -> bool:
	if manual_aim:
		return true
	for c in crew:
		if str(c.role) == "gunner":
			return true
	return false


# --- Crew -----------------------------------------------------------------------

## Seat `members` (crew.gd dictionaries) on this rig for the run.
func set_crew(members: Array) -> void:
	crew.clear()
	for m: Dictionary in members:
		var e := Crew.entry(m)
		e.merge({"id": int(m.id), "name": str(m.name), "specialty": Crew.specialty(m),
			"tough": Crew.has_perk(m, "tough"), "ability": Crew.ability(m), "ready_in": 0.0})
		crew.append(e)
	_active.clear()
	_refresh_crew_mods()
	armor = armor_max


func _refresh_crew_mods() -> void:
	var active := {}
	for kind: String in _active:
		active[kind] = _active[kind]
	crew_mods = Crew.compute_mods(crew, active)
	crew_turn = float(crew_mods.turn)
	crew_grip = float(crew_mods.grip)
	crew_speed = float(crew_mods.speed)
	crew_accel = float(crew_mods.accel)
	crew_aim = float(crew_mods.aim)
	crew_spread = float(crew_mods.spread)
	crew_lock = float(crew_mods.lock)
	crew_fire = float(crew_mods.fire)
	crew_damage = float(crew_mods.damage)
	latch_mult = float(crew_mods.latch)
	_apply_armor_mods()
	for t in _turrets:
		if t != null:
			t.set("hot", _active.has("overcharge") or _active.has("deadeye"))
			t.queue_redraw()
	queue_redraw()


## A crew modifier by name (see Crew.base_mods()).
func crew_mod(key: String) -> Variant:
	return crew_mods.get(key, Crew.base_mods().get(key))


## Fire crew member `index`'s triggered ability (from the crew wheel).
func use_crew_ability(index: int) -> bool:
	if is_wrecked or index < 0 or index >= crew.size():
		return false
	var c := crew[index]
	if bool(c.injured) or float(c.ready_in) > 0.0:
		return false
	var a: Dictionary = c.ability
	var kind := str(a.kind)
	match kind:
		"field_dressing":
			# Only with someone to treat.
			var patient := -1
			for i in crew.size():
				if bool(crew[i].injured):
					patient = i
					break
			if patient < 0:
				return false
			crew[patient].injured = false
			if _member_has(c, "sp_back_in_it"):
				crew[patient].ready_in = 0.0   # Back in It
				_perk_fired("sp_back_in_it")
			crew_healed.emit(patient)
		"field_repair":
			var fixed := _worst_facing()
			repair_armor(float(a.heal) * float(crew_mods.repair))
			if _member_has(c, "sp_fresh_weld") and fixed >= 0:
				_fresh_weld_facing = fixed   # Fresh Weld: that facing takes -20% for 4 s
				_fresh_weld_left = 4.0
				_perk_fired("sp_fresh_weld")
			throw_off_hunters()
			if fx != null:
				fx.call("repair", global_position)
			if bool(a.get("epic", false)):
				_active["repair_guard"] = {"dr": float(a.epic_dr), "left": float(a.epic_time)}
		"bootleg":
			# Snap to face the left stick (or swing round), keeping speed.
			var heading := drive_input.angle() if drive_input.length() > 0.2 else rotation + PI
			var speed := velocity.length()
			rotation = heading
			velocity = Vector2.RIGHT.rotated(heading) * speed
			if _member_has(c, "sp_tail_swipe"):
				_tail_swipe_left = T.TAIL_SWIPE_TIME   # the rear rams while it swings
		"reroute":
			for u in abilities:
				u.ready_in = float(u.ready_in) * (1.0 - minf(float(a.cut), 0.95))
		"shockwave":
			var dmg := float(a.damage)
			if _member_has(c, "sp_payback"):
				var extra := minf(recent_taken() * 0.5, 60.0)
				if extra > 0.0:
					dmg += extra
					_perk_fired("sp_payback")
			_shockwave(dmg, float(a.radius), _member_has(c, "sp_live_wire"), _member_has(c, "sp_clear_out"))
			if _member_has(c, "sp_clear_out"):
				_perk_fired("sp_clear_out")
		"static_burst":
			static_burst(float(a.radius), float(a.shock_buildup), float(a.time) + float(a.get("jam_add", 0.0)))   # Lingering Static perk
		"chain_drag":
			if not chain_drag(float(a.latch_range)):
				return false
			var timed := a.duplicate()
			timed.left = float(a.time)
			_active[kind] = timed
		"mark", "flare", "magnet":
			crew_ability_used.emit(kind, a)
			if a.time > 0.0:
				var timed := a.duplicate()
				timed.left = float(a.time)
				_active[kind] = timed
		_:
			var timed := a.duplicate()
			timed.left = float(a.time)
			_active[kind] = timed
	c.ready_in = float(a.cooldown)
	var two := _charges_perk(kind)
	if two != "" and _member_has(c, two):
		c.spent = int(c.get("spent", 0)) + 1
		if int(c.spent) < 2:
			c.ready_in = T.SECOND_CHARGE_PAUSE   # second charge ready almost at once
		else:
			c.spent = 0
		_perk_fired(two)
	_on_ability_used(c, kind, a)
	_refresh_crew_mods()
	return true


## 0 when ready, up to 1 right after use.
func crew_charge(index: int) -> float:
	if index < 0 or index >= crew.size():
		return 0.0
	var c := crew[index]
	return clampf(float(c.ready_in) / maxf(float(c.ability.cooldown), 0.01), 0.0, 1.0)


func is_crew_injured(index: int) -> bool:
	return index >= 0 and index < crew.size() and bool(crew[index].injured)


func ability_active(kind: String) -> bool:
	return _active.has(kind)


func hard_line_active() -> bool:
	return _active.has("hard_line")


func overcharge_active() -> bool:
	return _active.has("overcharge")


## Throw every Hunter off the hull (Field Repair, Shake It Off).
func throw_off_hunters() -> void:
	for h: Node2D in latched.duplicate():
		var away := (h.global_position - global_position).normalized()
		h.call("knock_off", away if away != Vector2.ZERO else Vector2.RIGHT)


func _shockwave(damage: float, radius: float, shock := false, clear_out := false) -> void:
	var push := 500.0 * (T.CLEAR_OUT_PUSH if clear_out else 1.0)   # Clear Out hurls zombies
	var shape := CircleShape2D.new()
	shape.radius = radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, global_position)
	query.collision_mask = T.LAYER_ZOMBIE | (T.LAYER_ENEMY if team == BulletPool.TEAM_PLAYER else T.LAYER_VEHICLE)
	for hit: Dictionary in get_world_2d().direct_space_state.intersect_shape(query, 32):
		var body: Object = hit.collider
		if body != null and body != self and body.has_method("take_hit"):
			var away: Vector2 = ((body as Node2D).global_position - global_position).normalized()
			body.call("take_hit", damage, away * push, "shockwave", "shock" if shock else "")   # Live Wire
	throw_off_hunters()
	if fx != null:
		fx.call("blast", global_position, radius)


## Injure crew member `index` now: their passive, perks and ability are gone
## for the run, and the rig takes their class's debuff.
func injure_crew(index: int) -> void:
	if index < 0 or index >= crew.size() or bool(crew[index].injured):
		return
	var c := crew[index]
	c.injured = true
	_active.erase(str(c.ability.kind))
	if str(c.ability.kind) == "field_repair":
		_active.erase("repair_guard")
	_refresh_crew_mods()
	crew_injured.emit(index)


## A big hit (over the big-hit share of max armor inside a second) may injure
## a random crew member who isn't hurt yet. Tough crew are half as likely to
## be the one.
func _check_big_hit() -> void:
	var total := 0.0
	for v in _dmg_buckets:
		total += v
	if total <= armor_max * float(crew_mods.big_hit):
		return
	big_hits += 1
	_dmg_buckets.fill(0.0)
	if bool(crew_mods.immune):
		return
	if randf() >= T.CREW_INJURY_CHANCE * injury_mult * float(crew_mods.injury):
		return
	var weights := 0.0
	for c in crew:
		if not bool(c.injured):
			weights += 0.5 if bool(c.tough) else 1.0
	if weights <= 0.0:
		return
	var roll := randf() * weights
	for i in crew.size():
		if bool(crew[i].injured):
			continue
		roll -= 0.5 if bool(crew[i].tough) else 1.0
		if roll <= 0.0:
			injure_crew(i)
			return


func _tick_crew(delta: float) -> void:
	# Roll the damage window forward in 0.1 s steps.
	_bucket_t += delta
	while _bucket_t >= 0.1:
		_bucket_t -= 0.1
		_bucket_i = (_bucket_i + 1) % _dmg_buckets.size()
		_dmg_buckets[_bucket_i] = 0.0
	for c in crew:
		c.ready_in = maxf(float(c.ready_in) - delta, 0.0)
	if _active.is_empty():
		return
	var ended: Array[String] = []
	for kind: String in _active:
		var a: Dictionary = _active[kind]
		a.left = float(a.left) - delta
		if float(a.left) <= 0.0:
			ended.append(kind)
	# Tyre streaks while a driving ability runs: cyan Hard Line, orange Floor It.
	var streak := T.COL_CYAN if _active.has("hard_line") else (T.COL_ORANGE if _active.has("floor_it") or _active.has("overclock") else Color.TRANSPARENT)
	if streak.a > 0.0:
		_streak_timer -= delta
		if fx != null and _streak_timer <= 0.0 and velocity.length() > 120.0:
			_streak_timer = 0.04
			var back := -Vector2.RIGHT.rotated(rotation) * body_len * 0.4
			var side := Vector2.RIGHT.rotated(rotation).orthogonal() * body_wid * 0.5
			for s: float in [-1.0, 1.0]:
				fx.call("emit", global_position + back + side * s, -velocity * 0.1, 0.35, 4.0, streak, 4.0)
	if not ended.is_empty():
		for kind in ended:
			var done: Dictionary = _active[kind]
			_active.erase(kind)
			_on_ability_ended(kind, done)
		_refresh_crew_mods()


## Power drawn by the build (crew can trim it). Fixed by what's installed,
## not by what's switched on.
func power_load() -> float:
	return power_draw * float(crew_mods.draw)


## The engine's output with crew bonuses (Engineer).
func power_capacity() -> float:
	return power_output * float(crew_mods.power)


func weight_limit() -> float:
	return weight_capacity * float(crew_mods.weight_cap)


func is_overloaded() -> bool:
	return is_power_overloaded() or is_weight_overloaded()


func is_power_overloaded() -> bool:
	return power_output > 0.0 and power_load() > power_capacity()


func is_weight_overloaded() -> bool:
	return weight_capacity > 0.0 and weight_load > weight_limit()


## 1.0 within budget; less when overloaded on power or weight (scales top
## speed and acceleration). Overclock ignores overload while it runs.
func mobility() -> float:
	if bool(crew_mods.ignore_overload):
		return 1.0
	return Loadout.mobility({"power_draw": power_load(), "power_output": power_capacity(),
		"weight": weight_load, "weight_capacity": weight_limit()})


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	if team != BulletPool.TEAM_PLAYER and _status_bar == null:
		_status_bar = EnemyStatusBar.new()
		_status_bar.top_level = true
		_status_bar.z_index = 6
		_status_bar.bars = status
		_status_bar.visible = false
		add_child(_status_bar)
	if team == BulletPool.TEAM_PLAYER:
		collision_layer = T.LAYER_VEHICLE
		collision_mask = T.LAYER_WORLD | T.LAYER_ZOMBIE | T.LAYER_ENEMY
	else:
		collision_layer = T.LAYER_ENEMY
		collision_mask = T.LAYER_WORLD | T.LAYER_ZOMBIE | T.LAYER_VEHICLE | T.LAYER_ENEMY
	_ray.collision_mask = T.LAYER_WORLD
	var capsule := CapsuleShape2D.new()
	capsule.radius = body_wid * 0.5
	capsule.height = body_len
	var shape := CollisionShape2D.new()
	shape.shape = capsule
	shape.rotation = PI / 2.0
	add_child(shape)
	_sync_parts()


func is_targetable() -> bool:
	return not is_wrecked and is_inside_tree()


func gun_range() -> float:
	return bullet_speed * BulletPool.LIFETIME


func _physics_process(delta: float) -> void:
	if is_wrecked:
		velocity = velocity.move_toward(Vector2.ZERO, 900.0 * delta)
		move_and_slide()
		touching_wall = false
		wall_impact = 0.0
		_burn(delta)
		return
	_tick_perks(delta)
	if not crew.is_empty() or not _active.is_empty():
		_tick_crew(delta)
	if vuln_left > 0.0:
		vuln_left -= delta
		if vuln_left <= 0.0:
			queue_redraw()
	_recharge_shield(delta)
	_tick_status(delta)
	var stunned := status.active(StatusBars.SHOCK)
	if stunned:
		drive_input = Vector2.ZERO   # STUNNED: no driving, firing or turret turning
	_drive(delta)
	_tick_tether(delta)
	_update_lock(delta)
	if not stunned:
		_weapons(delta)
	for a in abilities:
		a.ready_in = maxf(float(a.ready_in) - delta, 0.0)
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 5.0, 0.0)
		queue_redraw()


# --- Driving -------------------------------------------------------------------

func _drive(delta: float) -> void:
	var forward := Vector2.RIGHT.rotated(rotation)
	var fwd_speed := velocity.dot(forward)
	var stick := drive_input.length()
	var throttle := 0.0

	if stick > 0.0:
		var desired := drive_input.angle()
		var diff := wrapf(desired - rotation, -PI, PI)
		if absf(diff) > REVERSE_ANGLE and (fwd_speed < max_speed * 0.2 or _reversing):
			# Stick points behind us and we're slow: back up, steering the tail.
			_reversing = true
			diff = wrapf(desired + PI - rotation, -PI, PI)
			throttle = -stick
		else:
			_reversing = false
			# Ease off the gas while turning hard; that's where drifts come from.
			throttle = stick * clampf(0.35 + 0.65 * cos(diff), 0.15, 1.0)
		var authority := clampf(absf(fwd_speed) / (max_speed * 0.3), 0.3, 1.0)
		var max_turn := turn_rate * crew_turn * authority * delta
		rotation += clampf(diff, -max_turn, max_turn)
	else:
		_reversing = false

	# Re-project velocity onto the new heading. Leftover sideways speed is the
	# drift, and grip decides how quickly it dies.
	forward = Vector2.RIGHT.rotated(rotation)
	var side := forward.orthogonal()
	fwd_speed = velocity.dot(forward)
	var side_speed := velocity.dot(side)

	# An overloaded power plant can't deliver full speed or acceleration.
	var power := mobility()
	if throttle > 0.0:
		var spiked := T.SPIKE_RIG_SPEED if spike_left > 0.0 else 1.0
		var target := throttle * max_speed * power * crew_speed * spiked * (0.75 if neuro_left > 0.0 else 1.0)   # Neurotoxin
		var rate := acceleration * power * crew_accel if fwd_speed < target else coast
		if fwd_speed < 0.0:
			rate = brake
		fwd_speed = move_toward(fwd_speed, target, rate * delta)
	elif throttle < 0.0:
		var rate := brake if fwd_speed > 0.0 else acceleration * power * crew_accel
		fwd_speed = move_toward(fwd_speed, throttle * reverse_speed * power, rate * delta)
	else:
		fwd_speed = move_toward(fwd_speed, 0.0, coast * delta)

	side_speed *= exp(-(grip + crew_grip) * traction * grip_mult * delta)
	velocity = forward * fwd_speed + side * side_speed
	_track_drift(delta, side_speed, fwd_speed)

	var pre_velocity := velocity
	move_and_slide()
	_resolve_collisions(pre_velocity)


func _resolve_collisions(pre_velocity: Vector2) -> void:
	var hit_wall := false
	var plowed_through := false
	var already_hit: Array[Object] = []
	var normal := Vector2.ZERO
	var impact_max := 0.0
	var impact_rig := 0.0
	var juggernaut := false
	var bulwark_hit := false
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		var other := collision.get_collider()
		var impact := -pre_velocity.dot(collision.get_normal())
		if other is Hostile:
			var hostile := other as Hostile
			if already_hit.has(hostile) or impact < RAM_MIN_SPEED:
				continue
			already_hit.append(hostile)
			var damage := ram_damage * float(crew_mods.ram) * clampf(impact / max_speed, 0.0, 1.2)
			hostile.take_hit(damage, pre_velocity.normalized() * impact * 0.6, "rammed")
			if bool(crew_mods.shake_off):
				throw_off_hunters()
			if not hostile.active:
				plowed_through = true
		elif other != null and other.has_method("receive_ram"):
			if other.has_method("is_winding_up") and immovable():
				bulwark_hit = true
			# Another rig. Hit it hard enough and it hurts; it'll hit back from its side.
			# Friendly rigs (your rig and an Escort's truck) only bump.
			if already_hit.has(other) or impact < RAM_MIN_SPEED:
				continue
			if team == BulletPool.TEAM_PLAYER and int(other.get("team")) == BulletPool.TEAM_PLAYER:
				continue
			already_hit.append(other)
			var weight := T.COUNTERWEIGHT if _active.has("brace") and has_sp("sp_counterweight") else 1.0   # Counterweight
			other.call("receive_ram", ram_damage * float(crew_mods.ram) * clampf(impact / max_speed, 0.0, 1.2) * weight, global_position)
			if team == BulletPool.TEAM_PLAYER:
				keyword_pop("RAM", (other as Node2D).global_position)
			if weight > 1.0:
				_perk_fired("sp_counterweight")
			if _active.has("brace") and has_sp("sp_juggernaut") and other is CharacterBody2D:
				var ob := other as CharacterBody2D
				var dir := pre_velocity.normalized()
				var want := impact * (1.0 + T.JUGGERNAUT_FLING)   # rigs go flying (not stacking every frame)
				if ob.velocity.dot(dir) < want:
					ob.velocity += dir * (want - ob.velocity.dot(dir))
				juggernaut = true
				_perk_fired("sp_juggernaut")
			if has_mod("tow_hitch") and other is CharacterBody2D:
				(other as CharacterBody2D).velocity += pre_velocity.normalized() * impact * (Mods.TOW_HITCH - 1.0)   # shoves 50% further
				_perk_fired("tow_hitch")
			if other.has_method("finish_off"):
				impact_rig = maxf(impact_rig, impact)
			if has_mod("molten_skin") and other.has_method("add_buildup"):
				other.call("add_buildup", StatusBars.FIRE, Mods.MOLTEN_SKIN_BUILDUP)   # Molten Skin mod
			if bool(crew_mods.shake_off):
				throw_off_hunters()
		else:
			hit_wall = true
			normal = collision.get_normal()
			impact_max = maxf(impact_max, impact)

	# Only a fresh crash counts as an impact; grinding along a wall doesn't.
	wall_impact = impact_max if hit_wall and not touching_wall else 0.0
	if wall_impact > WALL_DAMAGE_SPEED:
		take_damage((wall_impact - WALL_DAMAGE_SPEED) * 0.05 * float(crew_mods.wall), -normal)
	# Wrecking Ball (Harpoon mod): held on its tether, a crash over 250 px/s
	# hurts twice as much (at least 40).
	if wrecking_by != null and is_instance_valid(wrecking_by) and wrecking_by.get("tether") != null and (wrecking_by.get("tether") as RefCounted).get("b") == self:
		var crash := maxf(wall_impact, impact_rig)
		if crash > Mods.WRECKING_BALL_SPEED:
			var base := maxf(crash - WALL_DAMAGE_SPEED, 0.0) * 0.05
			take_damage(maxf(base * 2.0, Mods.WRECKING_BALL_MIN) - base, -normal if normal != Vector2.ZERO else Vector2.ZERO)
			wrecking_by.call("_perk_fired", "wrecking_ball")
	# Slingshot (Wrangler): a flung rig that hits a wall takes a RAM.
	if slung_left > 0.0 and wall_impact > RAM_MIN_SPEED:
		take_damage(slung_damage, -normal)
		slung_left = 0.0
		slung_hits += 1
	touching_wall = hit_wall
	wall_normal = normal

	if bulwark_hit and not hit_wall:
		velocity = pre_velocity   # Immovable Line: a Bulwark doesn't shove you
		_perk_fired("sp_immovable_line")
		return
	if juggernaut and not hit_wall:
		velocity = pre_velocity   # Juggernaut: RAMs don't slow you
		return
	if plowed_through and not hit_wall:
		# Plowing through a body that died shouldn't stop the rig dead.
		velocity = pre_velocity * (1.0 if bool(crew_mods.plow) else 0.88)
	else:
		# Keep only the speed we actually achieved, so pinning the rig against
		# a wall doesn't leave phantom speed in the model.
		velocity = get_real_velocity()


# --- Lock-on -------------------------------------------------------------------

func _update_lock(delta: float) -> void:
	if not lock_enabled or lock_reach() <= 0.0 or not lock_candidates.is_valid():
		lock_target = null
		return
	if lock_target != null and not _lock_still_valid(lock_target):
		lock_target = null
	if lock_target != null:
		# Drop a target we've lost sight of for a moment.
		_lock_blind = 0.0 if _has_los(lock_target.global_position) else _lock_blind + delta
		if _lock_blind > 0.5:
			lock_target = null
	_lock_check -= delta
	if lock_target == null or _lock_check <= 0.0:
		_lock_check = 0.25
		var best := _best_lock_target()
		# Only switch if nothing locked yet or something more dangerous showed up.
		if best != null and (lock_target == null or _priority_of(best) > _priority_of(lock_target)):
			lock_target = best
			_lock_blind = 0.0


func _lock_still_valid(target: Node2D) -> bool:
	if not is_instance_valid(target) or not target.call("is_targetable"):
		return false
	return global_position.distance_to(target.global_position) <= lock_reach() * 1.15


func _priority_of(target: Node2D) -> int:
	if latched.has(target):
		return 10  # a Hunter on the hull beats everything
	return int(target.get("lock_priority"))


func _best_lock_target() -> Node2D:
	var candidates: Array = lock_candidates.call()
	var best: Node2D = null
	var best_score := -INF
	var checks := 0
	# Score: priority first, then distance. Check line of sight on the best few.
	candidates.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		return _score(a) > _score(b))
	for c: Node2D in candidates:
		if global_position.distance_to(c.global_position) > lock_reach():
			continue
		if not c.call("is_targetable"):
			continue
		if checks >= 4:
			break
		checks += 1
		if _has_los(c.global_position):
			var s := _score(c)
			if s > best_score:
				best_score = s
				best = c
	return best


func _score(c: Node2D) -> float:
	return _priority_of(c) * 10000.0 - global_position.distance_to(c.global_position)


func _has_los(to: Vector2) -> bool:
	_ray.from = global_position
	_ray.to = to
	return get_world_2d().direct_space_state.intersect_ray(_ray).is_empty()


# --- Weapons -------------------------------------------------------------------

func _weapons(delta: float) -> void:
	if bullets == null or not has_weapon():
		return
	var manual := aim_input.length() >= AIM_DEADZONE
	var trigger := aim_input.length() >= FIRE_THRESHOLD
	var locked := lock_target != null
	var forward := Vector2.RIGHT.rotated(rotation)
	var can_aim := can_aim_turrets()
	for i in gun_stats.size():
		var w := gun_stats[i]
		_cooldowns[i] = maxf(_cooldowns[i] - delta, 0.0)
		if _reload_left[i] > 0.0:
			_reload_left[i] -= delta
			if _reload_left[i] <= 0.0:
				_ammo[i] = int(w.get("mag", 0))
		if str(w.get("kind", "")) == "mortar" or str(w.get("kind", "")) == "lobber":
			_mortar(i, w, delta, manual, locked, can_aim)
			continue
		var wants_fire := false
		var direction := forward
		var muzzle := global_position + forward * (body_len * 0.25)
		var turret := _turrets[i] if i < _turrets.size() else null
		if turret != null and not can_aim:
			# No Gunner and no targeting computer: the turret stays facing
			# forward and fires on the trigger like a fixed gun.
			turret.rotation = lerp_angle(turret.rotation, 0.0, 1.0 - exp(-6.0 * delta))
			direction = Vector2.RIGHT.rotated(turret.global_rotation)
			muzzle = turret.global_position
			wants_fire = trigger or fire_trigger
		elif turret != null:
			var want_angle := 0.0
			if manual:
				want_angle = aim_input.angle()
			elif locked:
				want_angle = (_lead_point(lock_target, float(w.bullet_speed)) - turret.global_position).angle()
			if manual or locked:
				turret.rotation = rotate_toward(turret.rotation, wrapf(want_angle - rotation, -PI, PI), float(w.turret_turn_rate) * crew_aim * (0.5 if neuro_left > 0.0 else 1.0) * delta)
			else:
				turret.rotation = lerp_angle(turret.rotation, 0.0, 1.0 - exp(-4.0 * delta))
			direction = Vector2.RIGHT.rotated(turret.global_rotation)
			# Rays start at the turret pivot, not the muzzle tip, so a zombie
			# pressed against the hull is still in the line of fire.
			muzzle = turret.global_position
			if manual:
				wants_fire = trigger
			elif locked:
				wants_fire = absf(angle_difference(turret.global_rotation, want_angle)) < LOCK_FIRE_CONE
		else:
			# Fixed guns fire straight ahead: on the AI's trigger, when the player
			# pushes the right stick, or when a locked target is in front.
			wants_fire = fire_trigger or trigger
			if locked and not wants_fire:
				wants_fire = absf(forward.angle_to(lock_target.global_position - global_position)) < 0.2
			# Twin fixed guns alternate barrels.
			muzzle += forward.orthogonal() * 9.0 * _barrel_side
		if not has_round(i) or _overheated[i]:
			wants_fire = false
		_cool(i, w, delta, wants_fire)
		var burst := int(w.get("burst", 1))
		if burst > 1:
			# Burst guns: one pull fires `burst` rounds a beat apart; the burst
			# finishes even if the trigger lets go. The cooldown runs from its start.
			if _burst_left[i] > 0:
				_burst_gap[i] -= delta
				if _burst_gap[i] <= 0.0:
					_burst_left[i] -= 1
					_burst_gap[i] = 1.0 / maxf(float(w.burst_rate), 1.0)
					_last_of_burst = _burst_left[i] == 0
					_shoot(w, muzzle, direction)
					_last_of_burst = false
			elif wants_fire and _cooldowns[i] <= 0.0:
				_cooldowns[i] = 1.0 / (float(w.fire_rate) * crew_fire)
				_spend(i)
				_burst_left[i] = burst - 1
				if team == BulletPool.TEAM_PLAYER:
					keyword_pop("BURST")
				_burst_gap[i] = 1.0 / maxf(float(w.burst_rate), 1.0)
				_shoot(w, muzzle, direction)
		elif wants_fire and _cooldowns[i] <= 0.0:
			_cooldowns[i] = 1.0 / (float(w.fire_rate) * crew_fire)
			if turret == null:
				_barrel_side = -_barrel_side
			_spend(i)
			if str(w.get("kind", "")) == "harpoon":
				_fire_harpoon(w, global_position, forward)   # from the hull: zombies on the nose get it too
			else:
				_shoot(w, muzzle, direction)


## A magazine weapon has a round ready (anything without a magazine always does).
func has_round(i: int) -> bool:
	return i < _ammo.size() and (int(gun_stats[i].get("mag", 0)) <= 0 or _ammo[i] > 0)


## Rounds left in weapon `i`'s magazine (-1 if it has none).
func ammo_left(i: int) -> int:
	return _ammo[i] if int(gun_stats[i].get("mag", 0)) > 0 else -1


## One shot (or one burst): a round out of the magazine and/or heat in.
func _spend(i: int) -> void:
	_use_round(i)
	var heat_time := float(gun_stats[i].get("heat_time", 0.0))
	if heat_time > 0.0 and not _bottomless():
		# Firing nonstop fills the bar in heat_time seconds, whatever the fire rate.
		var was := _heat[i]
		_heat[i] += _cooldowns[i] / heat_time
		if was < T.OVERLOAD_HEAT and _heat[i] >= T.OVERLOAD_HEAT:
			keyword_pop("OVERLOAD")
		if _heat[i] >= 1.0:
			_heat[i] = 1.0
			_overheated[i] = true


## Heat guns cool while they aren't firing; an overheated one is locked
## until the bar drains to empty over its lockout.
func _cool(i: int, w: Dictionary, delta: float, firing: bool) -> void:
	if float(w.get("heat_time", 0.0)) <= 0.0 or _heat[i] <= 0.0:
		return
	if _overheated[i]:
		_heat[i] -= delta / maxf(float(w.get("lockout", 1.0)), 0.1)
		if _heat[i] <= 0.0:
			_heat[i] = 0.0
			_overheated[i] = false
	elif not firing:
		_heat[i] = maxf(_heat[i] - float(w.get("cool", 0.25)) * delta, 0.0)


func is_overheated(i: int) -> bool:
	return i < _overheated.size() and _overheated[i]


func heat_of(i: int) -> float:
	return _heat[i] if i < _heat.size() else 0.0


## What the HUD's ring around the fire stick shows, one entry per weapon
## that has a magazine or heat: kind ("mag" / "heat"), fill 0-1, and whether
## it's reloading or locked hot.
func weapon_gauges() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in gun_stats.size():
		var w := gun_stats[i]
		var mag := int(w.get("mag", 0))
		if mag > 0:
			var reloading := _reload_left[i] > 0.0
			var fill := 1.0 - _reload_left[i] / maxf(float(w.get("reload", 1.0)), 0.01) if reloading else float(_ammo[i]) / mag
			out.append({"kind": "mag", "fill": clampf(fill, 0.0, 1.0), "reloading": reloading, "hot": false})
		elif float(w.get("heat_time", 0.0)) > 0.0:
			out.append({"kind": "heat", "fill": _heat[i], "reloading": false, "hot": _overheated[i]})
	return out


func _use_round(i: int) -> void:
	if int(gun_stats[i].get("mag", 0)) <= 0 or _bottomless():
		return
	_ammo[i] -= 1
	if _ammo[i] <= 0:
		_reload_left[i] = float(gun_stats[i].get("reload", 1.0))


## Mortar: the stick's direction aims the turret and its push sets the
## distance (min to max range); it lobs a shell whenever one's ready while the
## stick is held. With LOCK it aims at where the target will be when the shell
## lands. Shells fly over walls.
func _mortar(i: int, w: Dictionary, delta: float, manual: bool, locked: bool, can_aim: bool) -> void:
	var turret := _turrets[i] if i < _turrets.size() else null
	if turret == null:
		return
	var min_r := float(w.get("min_range", 300.0))
	var max_r := float(w.get("max_range", 1200.0))
	var flight := float(w.get("flight", 1.2))
	var dist := -1.0
	var want_angle := 0.0
	if manual:
		var push := clampf(inverse_lerp(AIM_DEADZONE, 1.0, aim_input.length()), 0.0, 1.0)
		dist = lerpf(min_r, max_r, push)
		want_angle = aim_input.angle() if can_aim else rotation
	elif locked and can_aim:
		var vel: Vector2 = lock_target.get("velocity") if lock_target.get("velocity") != null else Vector2.ZERO
		var aim_point := lock_target.global_position + vel * flight
		dist = clampf(turret.global_position.distance_to(aim_point), min_r, max_r)
		want_angle = (aim_point - turret.global_position).angle()
	if dist < 0.0:
		turret.rotation = lerp_angle(turret.rotation, 0.0, 1.0 - exp(-4.0 * delta))
		_show_aim(Vector2.INF, i, w)
		return
	if can_aim:
		turret.rotation = rotate_toward(turret.rotation, wrapf(want_angle - rotation, -PI, PI), float(w.turret_turn_rate) * crew_aim * (0.5 if neuro_left > 0.0 else 1.0) * delta)
	else:
		turret.rotation = lerp_angle(turret.rotation, 0.0, 1.0 - exp(-6.0 * delta))   # no Gunner: straight ahead
	var landing := turret.global_position + Vector2.RIGHT.rotated(turret.global_rotation) * dist
	_show_aim(landing, i, w)
	var on_target := absf(angle_difference(turret.global_rotation, want_angle)) < T.MORTAR_AIM_CONE or not can_aim
	if on_target and has_round(i) and _cooldowns[i] <= 0.0 and shells != null:
		if _lob(w, turret.global_position, landing, flight):
			_cooldowns[i] = 1.0 / (float(w.fire_rate) * crew_fire)
			_use_round(i)


## One shell out of a Mortar or a lobber. The Acid Lobber's globs leave an
## acid puddle; the Sludger alternates acid shells and goop shells.
func _lob(w: Dictionary, from: Vector2, landing: Vector2, flight: float) -> bool:
	var damage := float(w.bullet_damage) * crew_damage
	var radius := float(w.get("blast", 90.0))
	var dtype := str(w.get("dtype", ""))
	var extra := {}
	if str(w.get("id", "")) == "sludger":
		lobs += 1
		if lobs % 2 == 0:
			damage = T.SLUDGER_GOOP_DAMAGE * skull_damage
			radius = T.SLUDGER_GOOP_RADIUS
			dtype = ""
			extra = {"buildup_kind": StatusBars.GOOP, "buildup": T.SLUDGER_GOOP_BUILDUP}
		else:
			extra = {"puddle_r": T.SLUDGER_PUDDLE_RADIUS, "puddle_t": T.SLUDGER_PUDDLE_TIME}
	elif dtype == "acid":
		lobs += 1
		extra = {"puddle_r": T.ACID_PUDDLE_RADIUS, "puddle_t": T.ACID_PUDDLE_TIME + float(w.get("puddle_add", 0.0))}   # Sticky Glob mod
		if has_mod("etch"):
			extra["etch"] = true
	elif str(w.get("kind", "")) == "mortar" and has_mod("cluster_shell"):
		extra = {"cluster": true}
	return bool(shells.call("launch", from, landing, flight, damage, radius, team, dtype, extra))


func _show_aim(at: Vector2, i: int, w: Dictionary) -> void:
	if shells == null or team != BulletPool.TEAM_PLAYER:
		return
	shells.set("aim_at", at)
	shells.set("aim_radius", float(w.get("blast", 90.0)))
	shells.set("aim_ammo", maxi(_ammo[i], 0))
	shells.set("aim_reloading", _reload_left[i] > 0.0)


## Harpoon: a spear straight ahead, out to its range. It goes through
## zombies (up to `pierce`), sets off barrels, stops at walls, and sticks in
## the first rig it meets, tethering it. Firing again lets go first.
func _fire_harpoon(w: Dictionary, from: Vector2, direction: Vector2) -> void:
	release_tether()
	var reach := float(w.get("range", 600.0))
	var to := from + direction * reach
	var space := get_world_2d().direct_space_state
	var ray := PhysicsRayQueryParameters2D.create(from, to, T.LAYER_WORLD | T.LAYER_ZOMBIE | (T.LAYER_ENEMY if team == BulletPool.TEAM_PLAYER else T.LAYER_VEHICLE))
	ray.hit_from_inside = true
	var skip: Array[RID] = [get_rid()]
	var pierced := 0
	var end := to
	for guard in 12:
		ray.exclude = skip
		var hit := space.intersect_ray(ray)
		if hit.is_empty():
			break
		var body := hit.collider as Node2D
		if body == null or not body.has_method("take_hit"):
			end = hit.position   # a wall
			break
		harpoon_hits += 1
		if body.get("is_wrecked") != null:
			# A rig: the spear sticks and the cable holds it.
			end = hit.position
			body.call("take_hit", float(w.bullet_damage) * crew_damage, direction * 200.0, "shot", "")
			if not bool(body.get("is_wrecked")):
				tether = Tether.new(self, body as CharacterBody2D, float(w.get("cable", 500.0)))
				tether.reel_speed = float(w.get("reel_speed", T.HARPOON_REEL_SPEED))   # Power Winch mod
				tether.reel_to = float(w.get("reel_to", T.HARPOON_REEL_TO))
				if has_mod("wrecking_ball"):
					body.set("wrecking_by", self)
			break
		body.call("take_hit", float(w.get("zombie_damage", w.bullet_damage)) * crew_damage, direction * 250.0, "shot", "")
		if fx != null:
			fx.call("gore", body.global_position, direction)
		pierced += 1
		skip.append(hit.rid)
		if pierced >= int(w.get("pierce", 1)):
			end = hit.position
			break
	_cable_line().flash(from, end)


func release_tether() -> void:
	if tether != null:
		tether.release()
		tether = null


func _tick_tether(delta: float) -> void:
	if tether == null:
		return
	if not tether.step(delta):
		release_tether()
		if _cable != null:
			_cable.hide_cable()
		return
	_cable_line().hold(global_position, tether.b.global_position)


func _cable_line() -> CableLine:
	if _cable == null:
		_cable = CableLine.new()
		_cable.top_level = true
		_cable.z_index = 3
		add_child(_cable)
	return _cable


func _lead_point(target: Node2D, speed := 1500.0) -> Vector2:
	var at := target.global_position
	if latched.has(target):
		return at
	var vel: Vector2 = target.get("velocity")
	var t := clampf(global_position.distance_to(at) / maxf(speed, 1.0), 0.0, 0.5)
	return at + vel * t


func _shoot(w: Dictionary, muzzle: Vector2, direction: Vector2) -> void:
	var pellets := int(w.get("pellets", 1))
	var damage := float(w.bullet_damage) * crew_damage
	if hit_run_left > 0.0:
		damage *= 1.0 + T.HIT_AND_RUN_DAMAGE   # Hit and Run
	if int(w.mount) == Mount.FIXED and _active.has("about_face"):
		damage *= 1.25   # About Face: fixed guns +25% for 2 s after a Bootleg Turn
	# A Hunter clinging to the hull is too close for a bullet to travel:
	# if the gun is pointing at it, it's a point-blank hit (every pellet).
	for h in latched:
		var to_h := h.global_position - global_position
		if absf(direction.angle_to(to_h)) < 0.6:
			h.call("take_hit", damage * pellets, Vector2.ZERO, "shot")
			if fx != null:
				fx.sparks(h.global_position, -to_h.normalized())
			bullets.record_direct_hit()
			return
	var cone := deg_to_rad(float(w.spread_deg) * crew_spread)
	var speed := float(w.bullet_speed) * float(crew_mods.bullet_speed)
	var pierce := maxi(int(crew_mods.pierce), int(w.get("pierce", 0)))
	var dtype := str(w.get("dtype", ""))
	# Demolisher's Cook Off: hits add 50% of their damage as a fire hit.
	var rider := float(T.COOK_OFF_FIRE_RIDER) if _active.has("cook_off") else 0.0
	if _active.has("overcharge"):
		rider += float((_active.overcharge as Dictionary).get("red_hot", 0.0))   # Red Hot perk
	var chain := bool(w.get("chain", false))
	# Overload Coil: an OVERLOADed Arc Projector's chain hits 2 extra targets.
	var jumps := 1
	if chain and has_mod("overload_coil") and _gun_overloaded(gun_stats.find(w)):
		jumps = T.OVERLOAD_COIL_JUMPS
		_perk_fired("overload_coil")
	for p in pellets:
		var dir := direction.rotated(randf_range(-cone, cone))
		bullets.fire(muzzle, dir * speed * randf_range(0.95, 1.05) if pellets > 1 else dir * speed, damage, team, pierce, dtype, 0.0, chain, rider, self,
				_last_of_burst and has_sp("sp_shrapnel"), jumps)   # Shrapnel: the burst's last round splashes


# --- Utilities ---------------------------------------------------------------------

func has_mod(id: String) -> bool:
	return mods.has(id)


## Fire utility `index` (its HUD button). Returns false if it's still cooling down.
func use_ability(index: int) -> bool:
	if is_wrecked or index < 0 or index >= abilities.size():
		return false
	var a := abilities[index]
	if float(a.ready_in) > 0.0:
		return false
	a.ready_in = float(a.cooldown) * float(crew_mods.util_cd)
	match str(a.ability):
		"patch":
			repair_armor(float(a.heal) * float(crew_mods.patch) * float(crew_mods.repair))
			if fx != null:
				fx.call("repair", global_position)
		"oil":
			if hazards != null:
				# Your own oil only catches the other side (§14).
				var back := -Vector2.RIGHT.rotated(rotation)
				hazards.call("add_oil", global_position + back * (body_len * 0.5 + float(a.oil_radius) * 0.6), float(a.oil_radius), float(a.oil_time), team)
		"spikes":
			if hazards != null:
				lay_spikes(float(a.spike_length), float(a.spike_time))
		"pulse":
			shock_pulse(float(a.pulse_radius), float(a.pulse_damage), float(a.pulse_buildup))
		"goop":
			goop_shot(float(a.goop_range), float(a.goop_radius))
		"nitro":
			_active["nitro"] = {"speed": float(a.nitro_speed), "accel": float(a.nitro_accel), "ram": T.NITRO_RAM, "left": float(a.nitro_time)}
			_refresh_crew_mods()
		"mines":
			if mines != null:
				var back := -Vector2.RIGHT.rotated(rotation)
				var count := int(a.mines)
				for m in count:
					var side := (float(m) - (count - 1) * 0.5) * 34.0
					var at := global_position + back * (body_len * 0.5 + 18.0) + back.orthogonal() * side
					mines.call("drop", at, float(a.mine_damage) * float(crew_mods.mine), float(a.mine_radius), float(a.mine_arm), float(a.mine_life))
	return true


## Shock Pulse: a burst around the rig that hits the other side (zombies,
## Hunters, rigs) for `damage` and a fixed `buildup` of shock.
func shock_pulse(radius: float, damage: float, buildup: float) -> int:
	var q := PhysicsShapeQueryParameters2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	q.shape = circle
	q.transform = Transform2D(0.0, global_position)
	q.collision_mask = T.LAYER_ZOMBIE | (T.LAYER_ENEMY if team == BulletPool.TEAM_PLAYER else T.LAYER_VEHICLE)
	q.exclude = [get_rid()]
	var n := 0
	for hit: Dictionary in get_world_2d().direct_space_state.intersect_shape(q, 48):
		var body := hit.collider as Node2D
		if body == null or not body.has_method("take_hit") or body.has_method("explode"):
			continue   # barrels shrug it off
		var away := (body.global_position - global_position).normalized()
		body.call("take_hit", damage, away * 250.0, "pulse", "")
		if body.has_method("add_buildup"):
			body.call("add_buildup", StatusBars.SHOCK, buildup)
		if has_mod("drain_arc") and body.get("shield") != null:
			body.set("shield", float(body.get("shield")) * (1.0 - Mods.DRAIN_ARC_SHARE))   # Drain Arc mod
		n += 1
	if fx != null:
		fx.call("blast", global_position, radius)
	return n


## Enemy rigs (the other side's) within `radius`, nearest first.
func _rigs_near(radius: float) -> Array[Node2D]:
	var q := PhysicsShapeQueryParameters2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	q.shape = circle
	q.transform = Transform2D(0.0, global_position)
	q.collision_mask = T.LAYER_ENEMY if team == BulletPool.TEAM_PLAYER else T.LAYER_VEHICLE
	q.exclude = [get_rid()]
	var out: Array[Node2D] = []
	for hit: Dictionary in get_world_2d().direct_space_state.intersect_shape(q, 16):
		var body := hit.collider as Node2D
		if body != null and body.has_method("add_buildup") and not bool(body.get("is_wrecked")):
			out.append(body)
	out.sort_custom(func(a: Node2D, b: Node2D) -> bool: return a.global_position.distance_squared_to(global_position) < b.global_position.distance_squared_to(global_position))
	return out


## Goop Launcher: the nearest enemy rig in range (and any within `radius` of
## it) has its GOOPED bar filled, so the horde goes for it. Returns how many.
func goop_shot(reach: float, radius: float) -> int:
	var near := _rigs_near(reach)
	if near.is_empty():
		return 0
	var at := near[0].global_position
	var n := 0
	for rig in near:
		if rig.global_position.distance_to(at) <= radius + 1.0:
			rig.call("fill_status", StatusBars.GOOP)
			if has_mod("bait_shell"):
				rig.set("bait_shell_left", float(T.STATUS_TIME_RIG[StatusBars.GOOP]))   # Bait Shell
			n += 1
	if fx != null:
		fx.call("blast", at, radius)
	return n


## Jammer's Static Burst: shock buildup on every enemy rig in range, and their
## shields stop recharging for `seconds`.
func static_burst(radius: float, buildup: float, seconds: float) -> int:
	var near := _rigs_near(radius)
	for rig in near:
		rig.call("add_buildup", StatusBars.SHOCK, buildup)
		rig.set("jammed_left", seconds)
		# Feedback Loop: OVERLOADed enemy weapons overheat on the spot.
		if has_sp("sp_feedback_loop") and int(rig.call("force_overheat")) > 0:
			_perk_fired("sp_feedback_loop")
	if fx != null:
		fx.call("blast", global_position, radius)
	return near.size()


## Wrangler's Chain Drag: hooks the nearest enemy rig in reach on a cable
## (the Harpoon's tether rules); the next RAM within the ability is stronger.
func chain_drag(reach: float) -> bool:
	var near := _rigs_near(reach)
	if near.is_empty():
		return false
	chain_target = near[0]
	release_tether()
	tether = Tether.new(self, near[0] as CharacterBody2D, T.WRANGLER_TETHER)
	return true


## 0 when ready, up to 1 right after use.
func ability_charge(index: int) -> float:
	if index < 0 or index >= abilities.size():
		return 0.0
	var a := abilities[index]
	return clampf(float(a.ready_in) / maxf(float(a.cooldown) * float(crew_mods.util_cd), 0.01), 0.0, 1.0)


# --- Damage ----------------------------------------------------------------------

## A spike strip across the road behind the rig, tagged with its team (it
## only catches the other side). Returns the hazard slot.
func lay_spikes(length: float, seconds: float) -> int:
	var back := -Vector2.RIGHT.rotated(rotation)
	var centre := global_position + back * (body_len * 0.5 + 24.0)
	var across := back.orthogonal() * length * 0.5
	return int(hazards.call("add_spike", centre - across, centre + across, seconds, team))


## Crossing a spike strip: 30% slower for a few seconds.
func set_on_spikes(on: bool, delta: float) -> void:
	if on:
		spike_left = T.SPIKE_RIG_TIME
	elif spike_left > 0.0:
		spike_left = maxf(spike_left - delta, 0.0)


## Slime and oil on the ground build SLICK (§14); while SLICK the tyres keep
## only T.SLIME_GRIP of their grip (see _tick_status).
func set_on_slime(on: bool, delta: float) -> void:
	if on:
		add_buildup(StatusBars.SLIME, T.STATUS_POOL_BUILDUP * delta)


# --- Statuses (§14) ------------------------------------------------------------

## Resistance to status `k`, with an active shield's bonus.
func resistance(k: int) -> float:
	var r := float(resist[k])
	if shield > 0.0:
		r += T.STATUS_SHIELD_RESIST * (2.0 if _active.has("power_divert") and has_sp("sp_insulated_feed") else 1.0)   # Insulated Feed
	return minf(r, 100.0)


## Add `amount` of buildup (before resistance) to status `k`.
func add_buildup(k: int, amount: float) -> void:
	if is_wrecked:
		return
	if k == StatusBars.SLIME and _active.has("hard_line") and has_sp("sp_sure_footing"):
		amount *= 0.5   # Sure Footing
	if status.add(k, amount, resistance(k), float(T.STATUS_TIME_RIG[k])):
		status_started.emit(k)
		keyword_pop(STATUS_KEYWORDS[k])
		queue_redraw()


## Fill status `k` outright (a Boomer's burst fills GOOPED).
func fill_status(k: int) -> void:
	if is_wrecked:
		return
	status.trigger(k, float(T.STATUS_TIME_RIG[k]))
	status_started.emit(k)
	keyword_pop(STATUS_KEYWORDS[k])
	queue_redraw()


func is_status(k: int) -> bool:
	return status.active(k)


func _tick_status(delta: float) -> void:
	var was := status.any_active() or status.building()
	status.tick(delta)
	traction = T.SLIME_GRIP if status.active(StatusBars.SLIME) else 1.0
	if status.active(StatusBars.FIRE):
		# BURNING: damage across the facings, by the splash rule.
		_burn_angle += delta * 4.0
		take_damage(T.BURNING_RIG_DPS * delta * (Mods.HEAT_SOAK if has_mod("heat_soak") else 1.0), Vector2.RIGHT.rotated(_burn_angle), true)
	if status.active(StatusBars.TOXIC) and shield <= 0.0:
		# TOXIC: straight to HP, never below the floor; a raised shield blocks it.
		var floor_hp := hp_max * T.TOXIC_FLOOR
		if hp > floor_hp:
			hp = maxf(hp - T.TOXIC_DPS * delta, floor_hp)
	if team != BulletPool.TEAM_PLAYER:
		# Enemy rigs: a small bar under the hull, only while something builds or is on.
		# The Outrider's heat bar shows here too while its guns are warm.
		var warm := _heat.size() > 0 and heat_of(0) > 0.02 and float(gun_stats[0].get("heat_time", 0.0)) > 0.0
		var now := status.any_active() or status.building() or warm
		if _status_bar != null and (now or was or _status_bar.heat > 0.0):
			_status_bar.heat = heat_of(0) if warm else 0.0
			_status_bar.hot = warm and is_overheated(0)
			_status_bar.visible = now
			if now:
				_status_bar.global_position = global_position + Vector2(0, body_wid * 0.5 + 26.0)
				_status_bar.queue_redraw()


## A hit from a bullet or a blast. `impulse` points the way the hit travels,
## so it came from the opposite side; mines and other blasts splash.
func take_hit(damage: float, impulse: Vector2, cause := "shot", dtype := "") -> void:
	if not is_wrecked:
		velocity += impulse * 0.15
	if vuln_left > 0.0:
		damage *= vuln
	take_damage(damage, -impulse, cause == "mine" or cause == "blast", dtype)


## Rammed by another rig at world point `from` (its position).
func receive_ram(damage: float, from := Vector2.INF) -> void:
	take_damage(damage * float(crew_mods.ram_taken), from - global_position if from != Vector2.INF else Vector2.ZERO)


## Marked by a Spotter: takes `mult` damage for `seconds`.
func apply_status(mult: float, _slow: float, seconds: float) -> void:
	vuln = mult
	vuln_left = seconds
	keyword_pop("MARKED")
	queue_redraw()


## Damage through the layers (§14). `from` is the direction the hit came
## from (source minus this rig; zero = straight ahead). The shield takes it
## first; then the facing it lands on; a stripped facing passes the rest to
## HP. A `splash` (explosion) hits the nearest facing in full and each
## adjacent one at T.SPLASH_ADJACENT, and only reaches HP once every facing
## is stripped.
func take_damage(amount: float, from := Vector2.ZERO, splash := false, dtype := "") -> void:
	if is_wrecked or amount <= 0.0 or _invuln_left > 0.0:
		return
	if _active.has("floor_it"):
		_active.floor_it.hurt = true   # Clean Run needs a clean run
	if _active.has("brace"):
		_active.brace.blocked = float(_active.brace.get("blocked", 0.0)) + amount * minf(float(_active.brace.dr), 0.9)   # Absorb
		if splash and has_sp("sp_shell"):
			splash = false   # Shell: no splash spill during Brace
	if not _taken_ring.is_empty():
		_taken_ring[_ring_i] += amount
	# A typed hit builds its status (before CORRODED and crew modifiers).
	var k := StatusBars.kind_of(dtype)
	if k >= 0:
		add_buildup(k, amount * T.STATUS_HIT_BUILDUP)
	if status.active(StatusBars.ACID):
		amount *= T.CORRODED_TAKEN
	amount *= float(crew_mods.taken)
	var left := amount
	_shield_wait = shield_delay
	if shield > 0.0:
		# Shock hits shields harder.
		var vs := T.SHOCK_VS_SHIELD if dtype == "shock" else 1.0
		var soak := minf(shield, left * vs)
		shield -= soak
		left -= soak / vs
	if left > 0.0:
		var f := facing_of(from)
		last_facing = f
		if _fresh_weld_left > 0.0 and f == _fresh_weld_facing:
			left *= 0.8
		var vs_armor := T.ACID_VS_ARMOR if dtype == "acid" else 1.0   # acid eats plates
		if splash:
			if _armor_total() <= 0.0:
				hp -= left
			else:
				_strip(f, left, vs_armor)
				for adj: int in _adjacent(f):
					_strip(adj, left * T.SPLASH_ADJACENT, vs_armor)
		else:
			hp -= _strip(f, left, vs_armor)
	if amount >= 2.0:
		_flash = 1.0
		queue_redraw()
	damaged.emit(amount)
	if not crew.is_empty() and hp > 0.0:
		_dmg_buckets[_bucket_i] += amount
		_check_big_hit()
	if hp <= 0.0 and not _last_breath_used and has_sp("sp_last_breath"):
		# Last Breath (Field Medic, once per mission): HP floors at 1, 1 s invulnerable.
		_last_breath_used = true
		hp = 1.0
		_invuln_left = 1.0
		_perk_fired("sp_last_breath")
	_check_workshop()
	if hp <= 0.0 and cannot_wreck:
		hp = hp_max * 0.5
		for i in 4:
			facing_armor[i] = facing_max[i]
	if hp <= 0.0:
		hp = 0.0
		_wreck()


## Take `amount` off facing `f`'s armor (x `vs` for acid); returns what got
## through, in plain damage.
func _strip(f: int, amount: float, vs := 1.0) -> float:
	var soak := minf(facing_armor[f], amount * vs)
	facing_armor[f] -= soak
	return amount - soak / vs


## Which facing a hit from direction `from` (world space) lands on.
func facing_of(from: Vector2) -> int:
	if from == Vector2.ZERO:
		return FRONT
	var a := angle_difference(rotation, from.angle())
	if absf(a) <= PI * 0.25:
		return FRONT
	if absf(a) >= PI * 0.75:
		return REAR
	return RIGHT if a > 0.0 else LEFT


static func _adjacent(f: int) -> Array[int]:
	if f == FRONT or f == REAR:
		return [LEFT, RIGHT]
	return [FRONT, REAR]


## Repairs restore armor only, to the most damaged facing (never past its
## max; anything over is lost). Returns what was restored.
func repair_armor(amount: float) -> float:
	var worst := -1
	var gap := 0.0
	for i in 4:
		var g := facing_max[i] - facing_armor[i]
		if g > gap:
			gap = g
			worst = i
	if worst < 0 or amount <= 0.0:
		return 0.0
	var add := minf(amount, gap)
	facing_armor[worst] += add
	return add


func _armor_total() -> float:
	return facing_armor[0] + facing_armor[1] + facing_armor[2] + facing_armor[3]


func _armor_max_total() -> float:
	return facing_max[0] + facing_max[1] + facing_max[2] + facing_max[3]


## Read the layers from a stat sheet (Loadout.build or a flat enemy sheet:
## hp, front, side, rear, shield...). A sheet with only `armor` (old style)
## puts it all in HP.
func _set_layers(s: Dictionary) -> void:
	if s.has("hp"):
		_base_hp = float(s.hp)
		_base_facings = PackedFloat32Array([float(s.get("front", 0.0)), float(s.get("side", 0.0)), float(s.get("side", 0.0)), float(s.get("rear", 0.0))])
	else:
		_base_hp = float(s.get("armor", 0.0))
		_base_facings = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	shield_skulls = int(s.get("shield_skulls", 0))
	shield_max = float(s.get("shield", 0.0)) if shield_skulls == 0 else 0.0
	_sheet_shield = float(s.get("shield", 0.0))
	shield_delay = float(s.get("shield_delay", T.DEFAULT_SHIELD_DELAY))
	shield_refill = float(s.get("shield_refill", T.DEFAULT_SHIELD_REFILL))
	_apply_armor_mods()


## Crew armor modifiers (Reinforced) on top of the parts; keeps the current
## fill of each layer.
func _apply_armor_mods() -> void:
	var mult := float(crew_mods.armor)
	hp_max = _base_hp
	hp = minf(hp, hp_max)
	for i in 4:
		facing_max[i] = _base_facings[i] * mult
		facing_armor[i] = minf(facing_armor[i], facing_max[i])
	shield = minf(shield, shield_max)


## Enemy rigs with a shield from N skulls: switch it on for this job.
func arm_for_skulls(skulls: int) -> void:
	if shield_skulls > 0:
		shield_max = _sheet_shield if skulls >= shield_skulls else 0.0
		shield = shield_max


func _recharge_shield(delta: float) -> void:
	if jammed_left > 0.0:
		jammed_left -= delta   # Jammer's Static Burst
		return
	if shield >= shield_max or shield_max <= 0.0:
		return
	if _shield_wait > 0.0 and not _active.has("tune_up") and not _active.has("power_divert"):
		_shield_wait -= delta
		return
	shield = minf(shield + shield_max / maxf(shield_refill, 0.1) * delta, shield_max)


func _wreck() -> void:
	is_wrecked = true
	lock_target = null
	release_tether()
	if _cable != null:
		_cable.hide_cable()
	_burn_left = 6.0
	for t in _turrets:
		if t != null:
			t.visible = false
			if t.art != null:
				t.art.visible = false
	_spawn_wreck_pieces()
	queue_redraw()
	if fx != null:
		fx.explosion(global_position, velocity)
	wrecked.emit()


## Back from a wreck (a Patcher's revive): HP and each facing at `fraction`
## of max, shield empty, guns back on.
func revive(fraction: float) -> void:
	if not is_wrecked:
		return
	is_wrecked = false
	hp = hp_max * fraction
	for i in 4:
		facing_armor[i] = facing_max[i] * fraction
	shield = 0.0
	_shield_wait = shield_delay
	_burn_left = 0.0
	for t in _turrets:
		if t != null:
			t.visible = true
			if t.art != null:
				t.art.visible = true
	if _hull_art != null and _hull_texture != null:
		_hull_art.texture = _hull_texture
	queue_redraw()
	revived.emit()


func _burn(delta: float) -> void:
	if _burn_left <= 0.0 or fx == null:
		return
	_burn_left -= delta
	_burn_timer -= delta
	if _burn_timer <= 0.0:
		_burn_timer = 0.06
		var jitter := Vector2(randf_range(-22.0, 22.0), randf_range(-12.0, 12.0)).rotated(rotation)
		fx.flame(global_position + jitter)


# --- Look ----------------------------------------------------------------------

func _draw() -> void:
	if _hull_art != null:
		return   # the voxel sheet draws the rig (and its burnt-out chassis)
	var half_l := body_len * 0.5
	var half_w := body_wid * 0.5
	var hull := T.COL_STEEL
	if is_wrecked:
		hull = Color(0.11, 0.1, 0.095)
	elif _flash > 0.0:
		hull = hull.lerp(Color(1.0, 0.85, 0.7), _flash * 0.6)

	# Wheels first so the hull overlaps them. Each drive reads differently.
	var tyre := Color(0.07, 0.07, 0.075)
	var drive := str(look.get("drive", ""))
	if drive == "half_track":
		# Tracks at the back, small wheels up front.
		for sy: float in [-1.0, 1.0]:
			draw_rect(Rect2(Vector2(-half_l + 2.0, sy * half_w - 6.0), Vector2(body_len * 0.55, 12.0)), tyre)
			for k in 5:
				draw_rect(Rect2(Vector2(-half_l + 4.0 + k * body_len * 0.1, sy * half_w - 5.0), Vector2(3.0, 10.0)), Color(0.18, 0.18, 0.19))
			draw_rect(Rect2(Vector2(half_l * 0.55 - 7.0, sy * half_w - 4.0), Vector2(14.0, 8.0)), tyre)
	else:
		var big := drive == "off_road_tires"
		var size := Vector2(19.0, 13.0) if big else Vector2(16.0, 10.0)
		for sx: float in [-1.0, 1.0]:
			for sy: float in [-1.0, 1.0]:
				var wheel := Rect2(Vector2(sx * half_l * 0.55, sy * half_w) - size * 0.5, size)
				draw_rect(wheel, tyre)
				if drive == "outrider_sport_wheels":
					draw_rect(wheel.grow(-3.0), T.COL_ORANGE.darkened(0.2))
				elif big:
					for k in 3:
						draw_rect(Rect2(wheel.position + Vector2(3.0 + k * 5.0, 1.0), Vector2(2.0, size.y - 2.0)), Color(0.16, 0.16, 0.17))

	draw_rect(Rect2(-half_l, -half_w + 3.0, body_len, body_wid - 6.0), hull)
	if is_wrecked:
		draw_rect(Rect2(-10.0, -8.0, 22.0, 16.0), Color(0.05, 0.04, 0.04))
		return
	# Cab.
	draw_rect(Rect2(-half_l + 8.0, -half_w + 7.0, 26.0, body_wid - 14.0), hull.darkened(0.25))
	# Frame details: Bulwark gets side skirts, Courier a racing stripe.
	match str(look.get("chassis", "")):
		"bulwark_frame":
			draw_rect(Rect2(-half_l + 10.0, -half_w + 1.0, body_len - 24.0, 4.0), hull.darkened(0.4))
			draw_rect(Rect2(-half_l + 10.0, half_w - 5.0, body_len - 24.0, 4.0), hull.darkened(0.4))
		"courier_frame":
			draw_rect(Rect2(-half_l + 4.0, -3.0, body_len - 16.0, 6.0), T.COL_CYAN.darkened(0.35))
	# Front armor: each plate has its own nose.
	match str(look.get("armor", "scrap_plating")):
		"scrap_plating":
			draw_rect(Rect2(half_l - 11.0, -half_w + 2.0, 11.0, body_wid - 4.0), T.COL_RUST)
			draw_rect(Rect2(half_l - 4.0, -half_w + 2.0, 4.0, body_wid - 4.0), T.COL_RUST.darkened(0.3))
		"outrider_light_plating":
			draw_rect(Rect2(half_l - 7.0, -half_w + 3.0, 7.0, body_wid - 6.0), Color(0.3, 0.2, 0.16))
			draw_rect(Rect2(half_l - 7.0, -1.0, 7.0, 2.0), T.COL_ENEMY)
		"riot_plating":
			draw_rect(Rect2(half_l - 14.0, -half_w, 14.0, body_wid), Color(0.36, 0.37, 0.38))
			for k in 3:
				draw_rect(Rect2(half_l - 12.0, -half_w + 4.0 + k * (body_wid - 8.0) / 3.0, 10.0, 2.0), Color(0.22, 0.22, 0.23))
		"spiked_ram_plate":
			draw_rect(Rect2(half_l - 10.0, -half_w + 2.0, 10.0, body_wid - 4.0), T.COL_RUST.darkened(0.2))
			for k in 4:
				var y := -half_w + 4.0 + k * (body_wid - 8.0) / 3.0
				draw_colored_polygon(PackedVector2Array([Vector2(half_l, y - 3.0), Vector2(half_l + 9.0, y), Vector2(half_l, y + 3.0)]), Color(0.75, 0.72, 0.66))
		"composite_plating":
			draw_rect(Rect2(half_l - 13.0, -half_w + 1.0, 13.0, body_wid - 2.0), Color(0.24, 0.27, 0.3))
			draw_rect(Rect2(half_l - 13.0, -half_w + 1.0, 13.0, body_wid - 2.0), T.COL_CYAN.darkened(0.4), false, 1.5)
	# Fixed guns on the nose instead of a turret.
	for w in gun_stats:
		if int(w.mount) == Mount.FIXED:
			draw_rect(Rect2(half_l - 16.0, -12.0, 22.0, 4.0), Color(0.15, 0.15, 0.16))
			draw_rect(Rect2(half_l - 16.0, 8.0, 22.0, 4.0), Color(0.15, 0.15, 0.16))
			if _active.has("overcharge") or _active.has("deadeye"):
				draw_rect(Rect2(half_l + 2.0, -12.0, 4.0, 4.0), Color(1.0, 0.95, 0.8))
				draw_rect(Rect2(half_l + 2.0, 8.0, 4.0, 4.0), Color(1.0, 0.95, 0.8))
			break
	# Utilities: a patch kit (green cross) or a mine rack at the tail.
	var utils: Array = look.get("utility", [])
	if utils.has("emergency_patch"):
		draw_rect(Rect2(-half_l + 12.0, half_w - 13.0, 8.0, 8.0), Color(0.2, 0.2, 0.21))
		draw_rect(Rect2(-half_l + 15.0, half_w - 12.0, 2.0, 6.0), Color(0.45, 0.85, 0.5))
		draw_rect(Rect2(-half_l + 13.0, half_w - 10.0, 6.0, 2.0), Color(0.45, 0.85, 0.5))
	if utils.has("mine_dropper"):
		draw_rect(Rect2(-half_l - 3.0, -12.0, 7.0, 24.0), Color(0.12, 0.12, 0.13))
		for k in 3:
			var p := Vector2(-half_l + 0.5, -8.0 + k * 8.0)
			draw_circle(p, 3.0, Color(0.3, 0.29, 0.25))
			draw_circle(p, 1.2, T.COL_ENEMY)
	# Targeting computer: a sensor dish behind the cab.
	var internal: Array = look.get("internal", [])
	if internal.has("targeting_computer") or internal.has("advanced_targeting"):
		draw_rect(Rect2(-half_l + 2.0, -5.0, 7.0, 10.0), Color(0.16, 0.17, 0.18))
		draw_circle(Vector2(-half_l + 5.5, 0.0), 2.5, T.COL_CYAN)
	if internal.has("roll_cage"):
		# Bars over the cabin.
		var cage := Rect2(-half_l * 0.35, -half_w + 6.0, half_l * 0.6, body_wid - 12.0)
		draw_rect(cage, Color(0.12, 0.12, 0.13), false, 2.5)
		draw_line(cage.position, cage.end, Color(0.12, 0.12, 0.13), 2.0)
	# Practical lights: cyan edge strips, white headlights, orange tail lights.
	draw_rect(Rect2(-half_l + 6.0, -half_w + 3.0, body_len - 20.0, 2.0), T.COL_CYAN)
	draw_rect(Rect2(-half_l + 6.0, half_w - 5.0, body_len - 20.0, 2.0), T.COL_CYAN)
	draw_rect(Rect2(half_l - 2.0, -half_w + 5.0, 3.0, 6.0), Color(1.0, 0.96, 0.82))
	draw_rect(Rect2(half_l - 2.0, half_w - 11.0, 3.0, 6.0), Color(1.0, 0.96, 0.82))
	draw_rect(Rect2(-half_l - 1.0, -half_w + 5.0, 3.0, 6.0), T.COL_ORANGE)
	draw_rect(Rect2(-half_l - 1.0, half_w - 11.0, 3.0, 6.0), T.COL_ORANGE)


## A flung wreck piece: drifts out, slows, spins and fades, then frees itself.
class WreckPiece extends Sprite2D:
	## Counts as wreckage for rig caps (mission.active_rig_count) while it flies.
	var is_wrecked := true
	var velocity := Vector2.ZERO
	var spin := 0.0
	var life := 1.4
	var _age := 0.0

	func _init() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	func _process(delta: float) -> void:
		_age += delta
		position += velocity * delta
		velocity *= exp(-2.5 * delta)
		rotation += spin * delta
		modulate.a = clampf((life - _age) / (life * 0.5), 0.0, 1.0)
		if _age >= life:
			queue_free()


class TurretSprite extends Node2D:
	const T := preload("res://scripts/tuning.gd")
	var kind := ""   # weapon part id: changes the barrel
	var hot := false # Overcharge: white-hot muzzle
	var enemy := false  # enemy turrets wear red
	var art: Sprite2D = null  # DirectionalSprite when this weapon has voxel art
	var glow: Node2D = null   # white-hot muzzle over the art (Overcharge)

	func _draw() -> void:
		if art != null:
			return
		match kind:
			"scattergun_turret":
				# Short, wide, flared.
				draw_rect(Rect2(0.0, -5.0, 20.0, 10.0), Color(0.18, 0.18, 0.19))
				draw_colored_polygon(PackedVector2Array([Vector2(18, -5), Vector2(25, -8), Vector2(25, 8), Vector2(18, 5)]), T.COL_ORANGE.darkened(0.2))
			"burst_turret", "gunner_rig":
				# Twin slim barrels with a muzzle brake.
				draw_rect(Rect2(0.0, -5.0, 32.0, 3.0), Color(0.17, 0.17, 0.18))
				draw_rect(Rect2(0.0, 2.0, 32.0, 3.0), Color(0.17, 0.17, 0.18))
				draw_rect(Rect2(30.0, -6.0, 4.0, 12.0), T.COL_ENEMY if enemy else T.COL_ORANGE)
			"convoy_turret":
				# Heavy: a thick barrel on a wide armored mount.
				draw_rect(Rect2(-2.0, -9.0, 14.0, 18.0), Color(0.2, 0.2, 0.21))
				draw_rect(Rect2(0.0, -5.0, 40.0, 10.0), Color(0.15, 0.15, 0.16))
				draw_rect(Rect2(36.0, -6.0, 5.0, 12.0), T.COL_ENEMY)
			"heavy_mg_turret":
				# Long and thick, with a cooling jacket.
				draw_rect(Rect2(0.0, -4.0, 38.0, 8.0), Color(0.16, 0.16, 0.17))
				for k in 4:
					draw_rect(Rect2(10.0 + k * 6.0, -5.0, 2.0, 10.0), Color(0.26, 0.26, 0.27))
				draw_rect(Rect2(34.0, -4.0, 4.0, 8.0), T.COL_ORANGE)
			_:
				draw_rect(Rect2(0.0, -3.0, 30.0, 6.0), Color(0.18, 0.18, 0.19))
				draw_rect(Rect2(26.0, -3.0, 4.0, 6.0), T.COL_ORANGE)
		if hot:
			# Overcharge: the muzzle glows white-hot.
			var tip := {"scattergun_turret": 25.0, "heavy_mg_turret": 38.0}.get(kind, 30.0) as float
			draw_rect(Rect2(tip - 5.0, -4.0, 6.0, 8.0), Color(1.0, 0.95, 0.8))
		draw_circle(Vector2.ZERO, 11.0, Color(0.22, 0.225, 0.235))
		draw_arc(Vector2.ZERO, 11.0, 0.0, TAU, 20, T.COL_ENEMY if enemy else T.COL_CYAN, 2.0)
		draw_rect(Rect2(-4.0, -4.0, 8.0, 8.0), Color(0.14, 0.14, 0.15))


class EnemyStatusBar extends Node2D:
	## Under an enemy rig (§14): one thin bar per status building, a bright
	## full bar while one is on. Not rotated with the hull.
	const T := preload("res://scripts/tuning.gd")
	var bars: RefCounted   # the rig's StatusBars
	var heat := 0.0        # its heat gun's bar (0 = cold, hidden)
	var hot := false       # locked hot

	func _draw() -> void:
		if bars == null:
			return
		var build: PackedFloat32Array = bars.get("build")
		var left: PackedFloat32Array = bars.get("left")
		var y := 0.0
		if heat > 0.0:
			# Heat: orange to red, solid red while it's locked hot.
			var col := Color(1.0, 0.55, 0.15).lerp(Color(1.0, 0.15, 0.1), heat)
			draw_rect(Rect2(-24, y, 48, 5), Color(0, 0, 0, 0.6))
			draw_rect(Rect2(-23, y + 1, 46.0 * heat, 3), Color(1.0, 0.15, 0.1) if hot else col)
			if heat >= T.OVERLOAD_HEAT and not hot:
				draw_rect(Rect2(-24, y - 1, 48, 7), Color(1.0, 0.3, 0.15, 0.6), false, 1.0)   # OVERLOAD
			y += 7.0
		for k in 6:
			var on := left[k] > 0.0
			if not on and build[k] <= 0.0:
				continue
			var c: Color = T.STATUS_COLORS[k]
			draw_rect(Rect2(-24, y, 48, 5), Color(0, 0, 0, 0.6))
			draw_rect(Rect2(-23, y + 1, 46.0 * (1.0 if on else clampf(build[k] / T.STATUS_BAR, 0.0, 1.0)), 3), c)
			y += 7.0


class CableLine extends Node2D:
	## The Harpoon's spear flash and its cable, in world space.
	var _a := Vector2.ZERO
	var _b := Vector2.ZERO
	var _flash := 0.0
	var _held := false

	func flash(from: Vector2, to: Vector2) -> void:
		_a = from
		_b = to
		_flash = 0.25
		visible = true
		queue_redraw()

	func hold(from: Vector2, to: Vector2) -> void:
		_a = from
		_b = to
		_held = true
		visible = true
		queue_redraw()

	func hide_cable() -> void:
		_held = false
		queue_redraw()

	func _process(delta: float) -> void:
		if _flash > 0.0:
			_flash -= delta
			queue_redraw()

	func _draw() -> void:
		if _held:
			draw_line(_a, _b, Color(0.8, 0.78, 0.6), 2.5)
			draw_circle(_b, 4.0, Color(0.6, 0.6, 0.62))
		elif _flash > 0.0:
			draw_line(_a, _b, Color(0.9, 0.9, 0.85, _flash * 4.0), 3.0)


# --- Flag mods and specialty perks (proposal 01, implement-03) ----------------------
# Numbers: Mods.* (proposal §2.1-2.3, §3.4) and Crew perk text (DESIGN §14 table
# with proposal §3.1 numbers). Specialty perks change the ability they belong
# to, so most apply while it runs; the passive ones say so.

var shutdown_left := 0.0           # Marker's Shutdown: no rig abilities while > 0
var hogtie_left := 0.0             # Wrangler's Hogtie: turn rate halved while > 0
var zombie_taken := 1.0            # Bait Shell: zombie damage multiplier on this rig
var bait_shell_left := 0.0
var wrecking_by: Node2D = null     # the rig whose Wrecking Ball harpoon holds us
var perk_hits := {}                # perk id -> times it fired (tests)
var _last_breath_used := false
var _full_rebuild_used := false
var _open_road_given := 0.0
var _invuln_left := 0.0
var _taken_ring := PackedFloat32Array()   # damage taken, 0.1 s steps over 3 s (Payback)
var _ring_t := 0.0
var _ring_i := 0
var _napalm_seen := -1
var _ignite_t := 0.0


func has_sp(perk: String) -> bool:
	for c in crew:
		if not bool(c.injured) and (c.get("perks", []) as Array).has(perk):
			return true
	return false


func _perk_fired(id: String) -> void:
	perk_hits[id] = int(perk_hits.get(id, 0)) + 1


func _bottomless() -> bool:
	return _active.has("overcharge") and has_sp("sp_bottomless")


## Rail Line: Piercing Rounds bullets go through one rig.
func rail_line_ok() -> bool:
	return _active.has("piercing") and has_sp("sp_rail_line")


func _is_enemy_rig(o: Object) -> bool:
	return o != null and o.has_method("finish_off") and int(o.get("team")) != team and not bool(o.get("is_wrecked"))


## A player bullet about to land on `target`: returns the damage it deals.
func player_pre_hit(target: Object, dmg: float, _dtype: String, passed: int) -> float:
	# Demolisher's Cook Off: a barrel you set off with it blows 50% harder.
	if _active.has("cook_off") and target.has_method("explode"):
		target.set("blast_mult", float((_active.cook_off as Dictionary).get("barrel_mult", T.COOK_OFF_BARREL_MULT)))
	var rig := _is_enemy_rig(target)
	if _active.has("deadeye"):
		var d: Dictionary = _active.deadeye
		if has_sp("sp_opening_shot") and not bool(d.get("opened", false)):
			d.opened = true
			dmg *= 3.0
			_perk_fired("sp_opening_shot")
		if rig and has_sp("sp_called_shot") and float(target.get("vuln_left")) > 0.0:
			dmg *= 1.5
			_perk_fired("sp_called_shot")
		if rig and has_sp("sp_plate_splitter") and float(target.call("_armor_total")) > 0.0:
			dmg *= 1.3
			_perk_fired("sp_plate_splitter")
	if passed > 0 and _active.has("piercing") and has_sp("sp_overpenetration"):
		dmg *= 1.0 + 0.1 * passed
		_perk_fired("sp_overpenetration")
	if rig and has_sp("sp_fire_discipline") and bool(target.call("is_status", StatusBars.FIRE)):
		dmg *= 1.0 + Crew.FIRE_DISCIPLINE
		_perk_fired("sp_fire_discipline")
	return dmg


## After a player bullet landed on `target` for `dmg`.
func player_post_hit(target: Object, dmg: float, dtype: String, went_through: bool) -> void:
	if went_through and _active.has("piercing") and has_sp("sp_acid_core") and target.has_method("add_buildup"):
		target.call("add_buildup", StatusBars.ACID, dmg * T.STATUS_HIT_BUILDUP)
		_perk_fired("sp_acid_core")
	if _active.has("overcharge") and has_sp("sp_siphon") and shield_max > 0.0:
		var o: Dictionary = _active.overcharge
		var add := minf(0.1 * dmg, 40.0 - float(o.get("siphoned", 0.0)))
		if add > 0.0:
			o.siphoned = float(o.get("siphoned", 0.0)) + add
			shield = minf(shield + add, shield_max)
			_perk_fired("sp_siphon")
	if not _is_enemy_rig(target):
		return
	var v = target
	var f: int = v.last_facing
	var stripped: bool = f >= 0 and float(v.facing_armor[f]) <= 0.0
	if _active.has("deadeye") and has_sp("sp_executioner") and stripped and v.hp < v.hp_max * 0.1:
		v.finish_off()
		_perk_fired("sp_executioner")
		return
	if _active.has("piercing") and has_sp("sp_bleed_through") and not stripped and f >= 0:
		v.bleed_hp(dmg * 0.2)
		_perk_fired("sp_bleed_through")
	if has_sp("sp_weak_point") and v.vuln_left > 0.0 and stripped:
		v.bleed_hp(dmg * 0.5)
		_perk_fired("sp_weak_point")
	if dtype == "fire" and has_mod("napalm_mix") and v.status.active(StatusBars.FIRE) and v._napalm_seen != v.status.triggers:
		v._napalm_seen = v.status.triggers   # once per BURNING
		v.status.left[StatusBars.FIRE] += Mods.NAPALM_BURN_ADD
		_perk_fired("napalm_mix")
	if dtype == "shock" and has_mod("thunderhead") and v.status.active(StatusBars.SHOCK):
		for i in gun_stats.size():
			if str(gun_stats[i].get("id", "")) == "arc_projector" and i < _heat.size() and not _overheated[i]:
				_heat[i] *= 1.0 - Mods.THUNDERHEAD_VENT
		_perk_fired("thunderhead")


# --- DRIFT and OVERLOAD keywords ---------------------------------------------------

## DRIFT: sliding sideways at speed. A slide that lasted long enough counts
## as a DRIFT when it dies down.
func _track_drift(delta: float, side_speed: float, fwd_speed: float) -> void:
	hit_run_left = maxf(hit_run_left - delta, 0.0)
	_kw_clock += delta
	var now := absf(side_speed) > T.DRIFT_SIDE_SPEED and absf(fwd_speed) > T.DRIFT_MIN_FWD
	if now:
		_drift_time += delta
	elif drifting:
		if _drift_time >= T.DRIFT_MIN_TIME:
			end_drift()
		_drift_time = 0.0
	drifting = now


func is_drifting() -> bool:
	return drifting and _drift_time >= T.DRIFT_MIN_TIME


## A DRIFT just ended: what's keyed to it fires (tests call this directly).
func end_drift() -> void:
	drifts += 1
	drift_ended.emit()
	keyword_pop("DRIFT")
	if has_mod("hit_and_run"):
		hit_run_left = T.HIT_AND_RUN_TIME
		_perk_fired("hit_and_run")
	if has_mod("drift_fuel"):
		for a in abilities:
			if str(a.get("ability", "")) == "nitro" and float(a.ready_in) > 0.0:
				a.ready_in = maxf(float(a.ready_in) - T.DRIFT_FUEL_REFUND, 0.0)
				_perk_fired("drift_fuel")
	if _active.has("hard_line") and has_sp("sp_clean_exit"):
		for c in crew:
			if str((c.ability as Dictionary).get("kind", "")) == "hard_line":
				c.ready_in = maxf(float(c.ready_in) - T.CLEAN_EXIT_REFUND, 0.0)
		_perk_fired("sp_clean_exit")


## OVERLOAD: heat gun `i` running at T.OVERLOAD_HEAT or more, not yet locked.
func _gun_overloaded(i: int) -> bool:
	return i >= 0 and i < _heat.size() and float(gun_stats[i].get("heat_time", 0.0)) > 0.0 \
		and _heat[i] >= T.OVERLOAD_HEAT and not _overheated[i]


func is_overloaded_gun() -> bool:
	for i in _heat.size():
		if _gun_overloaded(i):
			return true
	return false


## Every gun's damage and the ram, times `m` (the skull's enemy damage, or a
## Hunt Elite's multiplier).
func scale_damage(m: float) -> void:
	bullet_damage *= m
	for w in gun_stats:
		w.bullet_damage = float(w.bullet_damage) * m
		if w.has("zombie_damage"):
			w.zombie_damage = float(w.zombie_damage) * m
	ram_damage *= m


## Keyword feedback: ask for a popup of `kw` over this rig (or at `at`), at
## most once per T.KEYWORD_THROTTLE per keyword.
func keyword_pop(kw: String, at := Vector2.INF) -> void:
	var last := float(_kw_last.get(kw, -100.0))
	if _kw_clock - last < T.KEYWORD_THROTTLE:
		return
	_kw_last[kw] = _kw_clock
	keyword.emit(kw, global_position if at == Vector2.INF else at)


## Feedback Loop: every OVERLOADed heat gun locks hot now. Returns how many.
func force_overheat() -> int:
	var n := 0
	for i in _heat.size():
		if _gun_overloaded(i):
			_heat[i] = 1.0
			_overheated[i] = true
			n += 1
	return n


## Mobile Workshop (Hauler): the first time HP falls under 30%, 15% comes back.
func _check_workshop() -> void:
	if workshop_used or not has_mod("mobile_workshop") or hp <= 0.0 or hp >= hp_max * T.MOBILE_WORKSHOP_AT:
		return
	workshop_used = true
	hp = minf(hp + hp_max * T.MOBILE_WORKSHOP_HEAL, hp_max)
	if fx != null:
		fx.call("repair", global_position)
	_perk_fired("mobile_workshop")


## Straight to HP (Bleed-Through, Weak Point): armor doesn't stop it.
func bleed_hp(amount: float) -> void:
	if is_wrecked or amount <= 0.0:
		return
	hp -= amount
	damaged.emit(amount)
	if hp <= 0.0:
		hp = 0.0
		_wreck()


func finish_off() -> void:
	if not is_wrecked:
		hp = 0.0
		_wreck()


## Two-charge perks (Double Back, Second Kit, Two Hooks): the first use only
## costs a short pause; the second starts the full cooldown.
static func _charges_perk(kind: String) -> String:
	match kind:
		"bootleg":
			return "sp_double_back"
		"field_dressing":
			return "sp_second_kit"
		"chain_drag":
			return "sp_two_hooks"
	return ""


func _member_has(c: Dictionary, perk: String) -> bool:
	return not bool(c.injured) and (c.get("perks", []) as Array).has(perk)


## Perks that hang off an ability as it's used.
func _on_ability_used(c: Dictionary, kind: String, a: Dictionary) -> void:
	match kind:
		"field_repair":
			if _member_has(c, "sp_kickstart"):
				_shield_wait = 0.0
				_perk_fired("sp_kickstart")
			if _member_has(c, "sp_hull_patch"):
				hp = minf(hp + hp_max * 0.05, hp_max)
				_perk_fired("sp_hull_patch")
			if _member_has(c, "sp_full_rebuild") and not _full_rebuild_used:
				for i in 4:
					if facing_max[i] > 0.0 and facing_armor[i] <= 0.0:
						facing_armor[i] = facing_max[i]
						_full_rebuild_used = true
						_perk_fired("sp_full_rebuild")
						break
		"bootleg":
			if _member_has(c, "sp_shake_off"):
				throw_off_hunters()
			if _member_has(c, "sp_about_face"):
				_active["about_face"] = {"left": 2.0}
				_perk_fired("sp_about_face")
			if _member_has(c, "sp_oil_spin") and hazards != null:
				hazards.call("add_oil", global_position, 120.0, 8.0, team)
				_perk_fired("sp_oil_spin")
		"shockwave":
			if _member_has(c, "sp_aftershock"):
				_active["aftershock"] = {"left": 1.0, "damage": float(a.damage) * 0.5, "radius": float(a.radius), "shock": _member_has(c, "sp_live_wire")}
		"static_burst":
			if _member_has(c, "sp_blind_spot"):
				for rig in _rigs_near(float(a.radius)):
					if bool(rig.call("is_status", StatusBars.SHOCK)):
						rig.call("apply_status", 1.0 + float(Crew.ABILITIES.marker.effect.vuln), 1.0, 3.0)
						_perk_fired("sp_blind_spot")
			if _member_has(c, "sp_blackout"):
				for rig in _rigs_near(float(a.radius)):
					if rig.has_method("pop_hook"):
						rig.call("pop_hook")
						rig.set("wind_left", maxf(float(rig.get("wind_left")), 5.0))
						_perk_fired("sp_blackout")
		"chain_drag":
			if tether != null and _member_has(c, "sp_bulldog"):
				tether.reel_to = T.BULLDOG_REEL_TO   # Bulldog: reels to 120 px, then a free RAM
				_active.chain_drag.bulldog = true
			if _member_has(c, "sp_slingshot"):
				_active.chain_drag.slingshot = true
			if _member_has(c, "sp_hogtie") and tether != null and is_instance_valid(tether.b):
				tether.b.set("hogtie_left", float(a.time))
				_perk_fired("sp_hogtie")
		"tune_up":
			if _member_has(c, "sp_crew_tune"):
				for other in crew:
					if other != c:
						other.ready_in = float(other.ready_in) * 0.5
				_perk_fired("sp_crew_tune")
		"power_divert":
			var bonus := minf(maxf(power_capacity() - power_load(), 0.0), T.POWER_DIVERT_CAP)
			_active.power_divert.bonus = bonus
			_active.power_divert.spill = _member_has(c, "sp_spillover")
			shield_max += bonus
			shield += bonus
		"scrap_drones":
			_spawn_drones(c, a)


## Perks that act when an ability ends.
func _on_ability_ended(kind: String, a: Dictionary) -> void:
	match kind:
		"aftershock":
			_shockwave(float(a.damage), float(a.radius), bool(a.shock))
			_perk_fired("sp_aftershock")
		"floor_it":
			if not bool(a.get("hurt", false)):
				for c in crew:
					if str(c.ability.kind) == "floor_it" and _member_has(c, "sp_clean_run"):
						c.ready_in = float(c.ready_in) * 0.5
						_perk_fired("sp_clean_run")
		"brace":
			var blocked := float(a.get("blocked", 0.0))
			if blocked > 0.0 and has_sp("sp_absorb"):
				shock_pulse(150.0, blocked * 0.5, blocked * 0.5 * T.STATUS_HIT_BUILDUP)
				_perk_fired("sp_absorb")
		"power_divert":
			var bonus := float(a.get("bonus", 0.0))
			var leftover := clampf(shield - (shield_max - bonus), 0.0, bonus)
			shield_max = maxf(shield_max - bonus, 0.0)
			shield = minf(shield, shield_max)
			if bool(a.get("spill", false)) and leftover > 0.0:
				repair_armor(minf(leftover * 0.5, 30.0))
				_perk_fired("sp_spillover")
		"tune_up":
			if has_sp("sp_afterglow"):
				# Afterglow: the boosts fade out linearly over 4 s instead of stopping.
				_active["tune_glow"] = {"left": T.AFTERGLOW_TIME, "speed": float(a.speed), "fire": float(a.fire)}
				_perk_fired("sp_afterglow")
		"chain_drag":
			if bool(a.get("slingshot", false)) and tether != null and is_instance_valid(tether.b) and velocity.length() > T.SLINGSHOT_SPEED:
				var b := tether.b
				release_tether()
				b.velocity += velocity * T.SLINGSHOT_FLING
				b.set("slung_left", T.SLINGSHOT_TIME)
				b.set("slung_damage", ram_damage * float(crew_mods.ram))
				_perk_fired("sp_slingshot")
		"miasma":
			if has_sp("sp_lingering_cloud"):
				_active["miasma_linger"] = {"left": 4.0, "at": global_position, "radius": float(a.radius), "buildup": float(a.buildup), "caustic": has_sp("sp_caustic_gas")}
				_perk_fired("sp_lingering_cloud")


## Per-tick perk and mod upkeep (Open Road, Payback ring, Miasma, timers).
func _tick_perks(delta: float) -> void:
	if shutdown_left > 0.0:
		shutdown_left -= delta
	if _invuln_left > 0.0:
		_invuln_left -= delta
	if hogtie_left > 0.0:
		hogtie_left -= delta
		crew_turn = float(crew_mods.turn) * 0.5
		if hogtie_left <= 0.0:
			crew_turn = float(crew_mods.turn)
	if bait_shell_left > 0.0:
		bait_shell_left -= delta
		zombie_taken = 1.0 + Mods.BAIT_SHELL_ZOMBIE if status.active(StatusBars.GOOP) else 1.0
		if bait_shell_left <= 0.0:
			zombie_taken = 1.0
	if neuro_left > 0.0:
		neuro_left -= delta
	if slung_left > 0.0:
		slung_left -= delta
	if _fresh_weld_left > 0.0:
		_fresh_weld_left -= delta
	if _tail_swipe_left > 0.0:
		_tail_swipe_left -= delta
		_tail_swipe()
	_arc_cd_tick(delta)
	if crew.is_empty():
		return
	_tick_perks_04(delta)
	if _taken_ring.is_empty():
		_taken_ring.resize(30)
	_ring_t += delta
	while _ring_t >= 0.1:
		_ring_t -= 0.1
		_ring_i = (_ring_i + 1) % 30
		_taken_ring[_ring_i] = 0.0
	# Open Road (Speedster, passive): above 80% top speed, 1% max armor/s to the
	# most damaged facing, at most 20% per mission.
	if has_sp("sp_open_road") and velocity.length() > max_speed * 0.8:
		var cap := _armor_max_total() * 0.2
		var give := minf(_armor_max_total() * 0.01 * delta, cap - _open_road_given)
		if give > 0.0:
			_open_road_given += repair_armor(give)
	for key: String in ["miasma", "miasma_linger"]:
		if _active.has(key):
			var m: Dictionary = _active[key]
			var at: Vector2 = m.get("at", global_position)
			for rig in _rigs_near(9999.0):
				if rig.global_position.distance_to(at) <= float(m.radius):
					rig.call("add_buildup", StatusBars.TOXIC, float(m.buildup) * delta)
					if bool(m.get("caustic", false)):
						rig.call("add_buildup", StatusBars.ACID, float(m.buildup) * delta)
			if zombies_ref != null:
				for z in zombies_ref.call("active_zombies"):
					if (z as Node2D).global_position.distance_to(at) <= float(m.radius):
						z.call("add_buildup", StatusBars.TOXIC, float(m.buildup) * delta)
	if has_mod("napalm_mix") and fire_trigger and hazards != null:
		_ignite_t -= delta
		if _ignite_t <= 0.0:
			_ignite_t = 0.25
			for w in gun_stats:
				if str(w.get("id", "")) == "flame_sprayer":
					var fwd := Vector2.RIGHT.rotated(rotation)
					hazards.call("ignite_oil", global_position + fwd * 150.0, 150.0)   # Napalm Mix: lights oil out to 300 px


var zombies_ref: Node = null       # ZombieDirector (Miasma reaches zombies)


## Payback (Breaker): damage taken in the last 3 s.
func recent_taken() -> float:
	var t := 0.0
	for v in _taken_ring:
		t += v
	return t


# --- Scrap Drones (Tinkerer) ---------------------------------------------------------

var drones: Array[Node2D] = []


func _spawn_drones(c: Dictionary, a: Dictionary) -> void:
	for d in drones:
		if is_instance_valid(d):
			d.queue_free()
	drones.clear()
	var n := int(a.drones) + (1 if _member_has(c, "sp_third_wheel") else 0)
	for k in n:
		var d := Drone.new()
		d.owner_rig = self
		d.phase = TAU * k / n
		d.life = float(a.time)
		d.hp = float(a.drone_hp)
		d.damage = float(a.drone_damage)
		d.rate = float(a.drone_rate)
		d.kamikaze = _member_has(c, "sp_kamikaze")
		d.bait = _member_has(c, "sp_bait_drones")
		if _member_has(c, "sp_copycat"):
			# Copycat: the drones fire your first gun's damage type and keywords.
			for w in gun_stats:
				d.dtype = str(w.get("dtype", ""))
				d.chain = bool(w.get("chain", false))
				d.pierce = int(w.get("pierce", 0))
				break
			_perk_fired("sp_copycat")
		get_parent().add_child(d)
		d.global_position = global_position
		drones.append(d)


class Drone extends Node2D:
	const T := preload("res://scripts/tuning.gd")
	const BulletPool := preload("res://scripts/bullet_pool.gd")
	var owner_rig: Node2D
	var phase := 0.0
	var life := 10.0
	var hp := 20.0
	var damage := 4.0
	var rate := 3.0
	var kamikaze := false
	var is_wrecked := false
	var bait := false
	var dtype := ""
	var chain := false
	var pierce := 0
	var shots := 0
	var _cd := 0.0

	func _physics_process(delta: float) -> void:
		if owner_rig == null or not is_instance_valid(owner_rig) or bool(owner_rig.get("is_wrecked")):
			queue_free()
			return
		life -= delta
		phase += delta * 2.0
		global_position = owner_rig.global_position + Vector2.RIGHT.rotated(phase) * (T.DRONE_BAIT_ORBIT if bait else T.DRONE_ORBIT)
		var zd0: Node = owner_rig.get("zombies_ref")
		if bait and zd0 != null:
			# Bait Drones: nearby zombies go for the drone, and gnaw on it.
			zd0.set("bait", self)
			zd0.set("bait_left", 0.2)
			for z in zd0.call("active_zombies"):
				if (z as Node2D).global_position.distance_to(global_position) < 30.0:
					hp -= T.DRONE_ZOMBIE_DPS * delta
		if life <= 0.0 or hp <= 0.0:
			if kamikaze and life <= 0.0:
				# Kamikaze: dives into the nearest enemy and blows (25 dmg, 60 px).
				var near: Array = owner_rig.call("_rigs_near", T.DRONE_RANGE)
				var at := (near[0] as Node2D).global_position if not near.is_empty() else global_position
				owner_rig.call("_area_hit", at, 60.0, 25.0, "")
				owner_rig.call("_perk_fired", "sp_kamikaze")
			queue_free()
			return
		_cd -= delta
		if _cd > 0.0:
			return
		var target := _target()
		if target != null:
			_cd = 1.0 / rate
			var dir := (target.global_position - global_position).normalized()
			var pool: Node = owner_rig.get("bullets")
			if pool != null:
				pool.call("fire", global_position, dir * 1000.0, damage, int(owner_rig.get("team")), pierce, dtype, 0.0, chain)
				shots += 1

	func _target() -> Node2D:
		var near: Array = owner_rig.call("_rigs_near", T.DRONE_RANGE)
		if not near.is_empty():
			return near[0]
		var zd: Node = owner_rig.get("zombies_ref")
		if zd == null:
			return null
		var best: Node2D = null
		var bd := T.DRONE_RANGE
		for z in zd.call("active_zombies"):
			var d := (z as Node2D).global_position.distance_to(global_position)
			if d < bd:
				bd = d
				best = z
		return best

	func _draw() -> void:
		draw_circle(Vector2.ZERO, 6.0, Color(0.55, 0.6, 0.62))
		draw_circle(Vector2.ZERO, 2.5, T.COL_CYAN)


## Damage everything hostile within `radius` of `at` (Kamikaze, Powder Keg).
func _area_hit(at: Vector2, radius: float, damage: float, dtype: String) -> int:
	var q := PhysicsShapeQueryParameters2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	q.shape = circle
	q.transform = Transform2D(0.0, at)
	q.collision_mask = T.LAYER_ZOMBIE | (T.LAYER_ENEMY if team == BulletPool.TEAM_PLAYER else T.LAYER_VEHICLE)
	var n := 0
	for hit: Dictionary in get_world_2d().direct_space_state.intersect_shape(q, 48):
		var body := hit.collider as Node2D
		if body == null or body == self or not body.has_method("take_hit"):
			continue
		body.call("take_hit", damage, (body.global_position - at).normalized() * 300.0, "blast", dtype)
		n += 1
	if fx != null:
		fx.call("blast", at, radius)
	return n


# --- Implement-04: the remaining Major / Signature perks -----------------------------
# Numbers: proposal 01 §3.1 and DESIGN §14 crew perk table (approved). Numbers
# neither gives are T.* constants in tuning.gd (agreed with the owner).

var skull_damage := 1.0            # enemy rigs: T.ENEMY_DAMAGE_BY_SKULL (scale_damage)
var grip_mult := 1.0                # an AI driver throwing the rig into a slide
var drifting := false              # DRIFT keyword: sliding sideways at speed
var drifts := 0                    # DRIFTs ended (tests, keyword feedback)
var hit_run_left := 0.0            # Hit and Run: +15% damage while > 0
var workshop_used := false         # Mobile Workshop: once per mission
var _drift_time := 0.0
signal drift_ended
signal keyword(kw: String, at: Vector2)   # keyword feedback (keyword_fx.gd)
var _kw_last := {}                 # keyword -> clock of its last popup (throttle)
var _kw_clock := 0.0
const STATUS_KEYWORDS := ["STUNNED", "BURNING", "CORRODED", "TOXIC", "SLICK", "GOOPED"]
var neuro_left := 0.0              # Neurotoxin: -25% speed, half turret turn while > 0
var slung_left := 0.0              # Slingshot: flung off a chain; a wall crash is a RAM
var slung_damage := 0.0
var slung_hits := 0                # tests
var strip_pending := 0.0           # Strip Mine scrap for the mission to bank
var strip_total := 0.0
var near_misses := 0               # tests
var arc_feedbacks := 0             # tests
var tail_swipes := 0               # tests
var afterburn_trail: Array = []    # [pos, life] (Afterburn)
var _last_of_burst := false
var _fresh_weld_facing := -1
var _fresh_weld_left := 0.0
var _tail_swipe_left := 0.0
var _tail_hit: Array = []
var _arc_cd := {}                  # attacker -> seconds before it can be shocked again
var _trail_t := 0.0
var _racing_added := 0.0


func _worst_facing() -> int:
	var worst := -1
	var gap := 0.0
	for i in 4:
		var g := facing_max[i] - facing_armor[i]
		if g > gap:
			gap = g
			worst = i
	return worst


func _arc_cd_tick(delta: float) -> bool:
	if _arc_cd.is_empty():
		return false
	for k in _arc_cd.keys():
		_arc_cd[k] = float(_arc_cd[k]) - delta
		if float(_arc_cd[k]) <= 0.0:
			_arc_cd.erase(k)
	return true


## An enemy bullet from `src` hit this rig; `on_shield` = the shield took it.
func shot_by(src: Object, on_shield: bool) -> void:
	if not on_shield or src == null or not is_instance_valid(src) or not _active.has("power_divert") or not has_sp("sp_arc_feedback"):
		return
	if _arc_cd.has(src) or not src.has_method("add_buildup"):
		return
	_arc_cd[src] = T.ARC_FEEDBACK_CD   # 0.5 s per attacker
	src.call("add_buildup", StatusBars.SHOCK, T.ARC_FEEDBACK_SHOCK)
	arc_feedbacks += 1
	_perk_fired("sp_arc_feedback")


## An enemy round passed close without hitting (Racing Line).
func near_miss() -> void:
	near_misses += 1
	if _active.has("hard_line") and has_sp("sp_racing_line") and _racing_added < T.RACING_LINE_CAP:
		var add := minf(T.RACING_LINE_ADD, T.RACING_LINE_CAP - _racing_added)
		_active.hard_line.left = float(_active.hard_line.left) + add
		_racing_added += add
		_perk_fired("sp_racing_line")


## Armor a player round stripped off an enemy rig (Strip Mine: 1 scrap per 40, cap 25).
func armor_dealt(amount: float) -> void:
	if amount <= 0.0 or not has_sp("sp_strip_mine") or strip_total >= T.STRIP_MINE_CAP:
		return
	var add := minf(amount / T.STRIP_MINE_PER, T.STRIP_MINE_CAP - strip_total)
	strip_total += add
	strip_pending += add
	_perk_fired("sp_strip_mine")


## Tail Swipe: while the Bootleg Turn swings, the rear rams at 60% of the front.
func _tail_swipe() -> void:
	var back := -Vector2.RIGHT.rotated(rotation)
	var at := global_position + back * body_len * 0.5
	var reach := body_wid * 0.5 + 30.0
	var hit_any := false
	for body in _rigs_near(body_len + 60.0):
		if _tail_hit.has(body) or body.global_position.distance_to(at) > reach + float(body.get("body_wid")) * 0.5:
			continue
		_tail_hit.append(body)
		body.call("receive_ram", ram_damage * float(crew_mods.ram) * T.TAIL_SWIPE_SHARE, at)
		hit_any = true
	if zombies_ref != null:
		for z in zombies_ref.call("active_zombies"):
			if not _tail_hit.has(z) and (z as Node2D).global_position.distance_to(at) <= reach:
				_tail_hit.append(z)
				z.call("take_hit", ram_damage * float(crew_mods.ram) * T.TAIL_SWIPE_SHARE, back * 300.0, "rammed")
				hit_any = true
	if hit_any:
		tail_swipes += 1
		_perk_fired("sp_tail_swipe")
	if _tail_swipe_left <= 0.0:
		_tail_hit.clear()


## Per-tick upkeep for implement-04 perks.
func _tick_perks_04(delta: float) -> void:
	# Afterglow: Tune-Up's boosts fade out.
	if _active.has("tune_glow"):
		var g: Dictionary = _active.tune_glow
		g.left = float(g.left) - delta
		if float(g.left) <= 0.0:
			_active.erase("tune_glow")
		_refresh_crew_mods()
	# Clean Lines: status buildup drains twice as fast during Tune-Up.
	status.drain_mult = 2.0 if _active.has("tune_up") and has_sp("sp_clean_lines") else 1.0
	if not _active.has("hard_line"):
		_racing_added = 0.0
	# Bulldog: once the chain has reeled the rig in, a free RAM.
	if _active.has("chain_drag") and bool(_active.chain_drag.get("bulldog", false)) and tether != null and is_instance_valid(tether.b):
		if global_position.distance_to(tether.b.global_position) <= T.BULLDOG_REEL_TO + 10.0:
			tether.b.call("receive_ram", ram_damage * float(crew_mods.ram), global_position)
			_active.chain_drag.bulldog = false
			_perk_fired("sp_bulldog")
	# Neurotoxin: TOXIC enemy rigs are slowed.
	if has_sp("sp_neurotoxin"):
		for rig in _rigs_near(9999.0):
			if bool(rig.call("is_status", StatusBars.TOXIC)):
				rig.set("neuro_left", 0.2)
	# Afterburn: a burning trail behind Floor It.
	if _active.has("floor_it") and has_sp("sp_afterburn"):
		_trail_t -= delta
		if _trail_t <= 0.0:
			_trail_t = 0.1
			afterburn_trail.append([global_position - Vector2.RIGHT.rotated(rotation) * body_len * 0.5, T.AFTERBURN_TIME])
			if hazards != null:
				hazards.call("ignite_oil", global_position, T.AFTERBURN_WIDTH * 0.5)
	if not afterburn_trail.is_empty():
		var r := T.AFTERBURN_WIDTH * 0.5
		var amount := T.AFTERBURN_BUILDUP * delta
		var rigs := _rigs_near(9999.0)
		var zs: Array = zombies_ref.call("active_zombies") if zombies_ref != null else []
		var burnt := {}
		for p: Array in afterburn_trail:
			p[1] = float(p[1]) - delta
			var at: Vector2 = p[0]
			for rig in rigs:
				if not burnt.has(rig) and rig.global_position.distance_to(at) <= r + float(rig.get("body_wid")) * 0.5:
					burnt[rig] = true
					rig.call("add_buildup", StatusBars.FIRE, amount)
			for z in zs:
				if not burnt.has(z) and (z as Node2D).global_position.distance_to(at) <= r + 12.0:
					burnt[z] = true
					z.call("add_buildup", StatusBars.FIRE, amount)
		afterburn_trail = afterburn_trail.filter(func(p: Array) -> bool: return float(p[1]) > 0.0)
		if not burnt.is_empty():
			_perk_fired("sp_afterburn")
		queue_redraw()


## Immovable Line (Wheelman): no shoves from a Tank or Bulwark during Hard Line.
func immovable() -> bool:
	return _active.has("hard_line") and has_sp("sp_immovable_line")
