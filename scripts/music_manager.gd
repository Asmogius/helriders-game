extends Node
## Music and one-shot effects (autoload `MusicManager`).
##
## Garage: "Yard Idle". Fights: three loops of the same length started on the
## same frame (Street Clear -> Contact -> Crossfire) that always play and
## crossfade by volume, so they stay in sync. Courier jobs swap Contact for a
## tighter pulse. A wreck fades everything to near-silence and a drone.
## Music goes to the "Music" bus, effects to "Effects"; Profile.apply_settings()
## sets their volumes from the settings file.

const T := preload("res://scripts/tuning.gd")

const YARD := "res://audio/music/yard_idle.ogg"
const LAYERS := [
	"res://audio/music/combat_street_clear.ogg",
	"res://audio/music/combat_contact.ogg",
	"res://audio/music/combat_crossfire.ogg",
]
const COURIER_MID := "res://audio/music/combat_courier_pulse.ogg"
const WRECK := "res://audio/music/wreck_drone.ogg"
const SFX := {
	"courier_checkpoint": "res://audio/sfx/courier_checkpoint.ogg",
	"courier_complete": "res://audio/sfx/courier_complete.ogg",
	"courier_warning": "res://audio/sfx/courier_warning.ogg",
	"wreck_hit": "res://audio/sfx/wreck_hit.ogg",
	"rig_wrecked": "res://audio/sfx/rig_wrecked.ogg",
	"results": "res://audio/sfx/results_confirm.ogg",
	"bulwark_windup": "res://audio/sfx/bulwark_windup.ogg",
	"ram_impact": "res://audio/sfx/ram_impact.ogg",
	"torcher_rupture": "res://audio/sfx/torcher_rupture.ogg",
	"acid_fire": "res://audio/sfx/acid_fire.ogg",
	"acid_impact": "res://audio/sfx/acid_impact.ogg",
}
const SFX_VOICES := 6

var mode := ""                      # "", "garage", "combat", "wreck"
var intensity := 0                  # 0 low, 1 mid, 2 high
var _yard: AudioStreamPlayer
var _layers: Array[AudioStreamPlayer] = []
var _wreck: AudioStreamPlayer
var _voices: Array[AudioStreamPlayer] = []
var _next_voice := 0
var sfx_counts := {}                # id -> times played (tests)
var _tweens := {}                   # player -> Tween
var _sfx_cache := {}
var _last_raise := -100.0
var _windup: AudioStreamPlayer      # Bulwark engine roar; pitch follows the wind-up
var _windup_rig: Node = null
var _duck: AudioEffectAmplify       # on the Music bus; dips while the tree is paused
## Headless runs (tests, CI) set everything up but don't start playback: the
## dummy audio driver otherwise keeps playbacks alive past quit and Godot
## reports leaked resources.
var silent := DisplayServer.get_name() == "headless"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # keep playing under the pause menu
	var bus := AudioServer.get_bus_index("Music")
	if bus >= 0:
		_duck = AudioEffectAmplify.new()
		AudioServer.add_bus_effect(bus, _duck)
	_yard = _player("Music")
	for i in 3:
		_layers.append(_player("Music"))
	_wreck = _player("Music")
	for i in SFX_VOICES:
		_voices.append(_player("Effects"))
	_windup = _player("Effects")


## Music dips under the pause menu and the driver's radio call (any pause),
## so the settings volume stays the player's own.
func _process(delta: float) -> void:
	_follow_windup()
	if _duck == null:
		return
	var target := T.MUSIC_PAUSE_DUCK_DB if get_tree().paused else 0.0
	_duck.volume_db = move_toward(_duck.volume_db, target, absf(T.MUSIC_PAUSE_DUCK_DB) * delta / T.MUSIC_DUCK_FADE)


func _player(bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	p.volume_db = T.MUSIC_SILENT_DB
	add_child(p)
	return p


func _load(path: String, loop: bool) -> AudioStream:
	var s := load(path) as AudioStream
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = loop
	return s


func _fade(p: AudioStreamPlayer, to_db: float, secs: float, stop_after := false) -> void:
	if _tweens.has(p) and (_tweens[p] as Tween).is_valid():
		(_tweens[p] as Tween).kill()
	var tw := create_tween()
	tw.tween_property(p, "volume_db", to_db, secs)
	if stop_after:
		tw.tween_callback(p.stop)
	_tweens[p] = tw


func _play(p: AudioStreamPlayer) -> void:
	if not silent:
		p.play()


func _fade_out_all(secs: float) -> void:
	for p: AudioStreamPlayer in [_yard, _wreck] + _layers:
		if p.playing or (silent and p.stream != null):
			_fade(p, T.MUSIC_SILENT_DB, secs, true)


## Garage / menus.
func play_garage() -> void:
	if mode == "garage":
		return
	_fade_out_all(T.MUSIC_FADE)
	_yard.stream = _load(YARD, true)
	_yard.volume_db = T.MUSIC_SILENT_DB
	_play(_yard)
	_fade(_yard, 0.0, T.MUSIC_FADE)
	mode = "garage"


## A fight starts. All three layers start together; only the low one is heard.
func start_combat(courier := false) -> void:
	_fade_out_all(T.MUSIC_FADE)
	for i in 3:
		var path: String = COURIER_MID if courier and i == 1 else LAYERS[i]
		_layers[i].stream = _load(path, true)
		_layers[i].volume_db = T.MUSIC_SILENT_DB
	for p in _layers:
		_play(p)
	mode = "combat"
	intensity = -1
	set_intensity(0, true)


## 0 Street Clear, 1 + Contact, 2 + Crossfire. Layers stack: higher levels
## keep the lower layers in. Drops wait MUSIC_INTENSITY_HOLD after a rise.
func set_intensity(level: int, force := false) -> void:
	level = clampi(level, 0, 2)
	if mode != "combat" or level == intensity:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if level < intensity and not force and now - _last_raise < T.MUSIC_INTENSITY_HOLD:
		return
	if level > intensity:
		_last_raise = now
	intensity = level
	for i in 3:
		_fade(_layers[i], 0.0 if i <= level else T.MUSIC_SILENT_DB, T.MUSIC_LAYER_FADE)


## Intensity from what's in the fight right now (numbers in tuning.gd).
## `boosts` are extra steps (elite alive, low armor, Survive's last stretch).
static func intensity_for(rigs: int, zombies: int, boosts := 0) -> int:
	var base := 0
	if rigs >= T.MUSIC_HIGH_RIGS or zombies >= T.MUSIC_HIGH_ZOMBIES:
		base = 2
	elif rigs >= T.MUSIC_MID_RIGS or zombies >= T.MUSIC_MID_ZOMBIES:
		base = 1
	return clampi(base + boosts, 0, 2)


## The player's rig is wrecked: hit, then near-silence and a drone.
func play_wreck() -> void:
	play_sfx("wreck_hit")
	_fade_out_all(0.4)
	_wreck.stream = _load(WRECK, false)
	_wreck.volume_db = -6.0
	_play(_wreck)
	mode = "wreck"


## The fight ended without a wreck: let the combat bed drop out.
func end_combat() -> void:
	if mode == "combat":
		_fade_out_all(T.MUSIC_FADE)
		mode = ""


## A Bulwark starts its wind-up (`windup_started`): the engine roar plays on its
## own voice and its pitch rises with the rig's windup_progress().
func start_windup(rig: Node) -> void:
	_windup_rig = rig
	if not SFX.has("bulwark_windup"):
		return
	if not _sfx_cache.has("bulwark_windup"):
		_sfx_cache["bulwark_windup"] = _load(SFX["bulwark_windup"], false)
	_windup.stream = _sfx_cache["bulwark_windup"]
	_windup.volume_db = 0.0
	_windup.pitch_scale = T.SFX_WINDUP_PITCH[0]
	sfx_counts["bulwark_windup"] = int(sfx_counts.get("bulwark_windup", 0)) + 1
	_play(_windup)


## The wind-up ended (it charged, rammed, wrecked or got stuck).
func stop_windup(rig: Node) -> void:
	if rig != _windup_rig:
		return
	_windup_rig = null
	if _windup.playing:
		_fade(_windup, T.MUSIC_SILENT_DB, 0.08, true)


func _follow_windup() -> void:
	if _windup_rig == null:
		return
	if not is_instance_valid(_windup_rig) or not _windup_rig.has_method("windup_progress"):
		_windup_rig = null
		return
	var p: float = _windup_rig.call("windup_progress")
	_windup.pitch_scale = lerpf(T.SFX_WINDUP_PITCH[0], T.SFX_WINDUP_PITCH[1], p)


## Pitch the wind-up voice is at now (tests).
func windup_pitch() -> float:
	return _windup.pitch_scale


## One-shot effect on the Effects bus (round-robin voices).
func play_sfx(id: String, volume_db := 0.0) -> void:
	if not SFX.has(id):
		push_warning("MusicManager: unknown sfx %s" % id)
		return
	if not _sfx_cache.has(id):
		_sfx_cache[id] = _load(SFX[id], false)
	sfx_counts[id] = int(sfx_counts.get(id, 0)) + 1
	var p := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	p.stream = _sfx_cache[id]
	p.volume_db = volume_db
	_play(p)


## Let go of streams and tweens on quit (headless runs report leaks otherwise).
func _exit_tree() -> void:
	for tw: Tween in _tweens.values():
		if tw.is_valid():
			tw.kill()
	_tweens.clear()
	_sfx_cache.clear()
	for p: AudioStreamPlayer in [_yard, _wreck, _windup] + _layers + _voices:
		p.stop()
		p.stream = null
