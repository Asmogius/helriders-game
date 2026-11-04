extends SceneTree
## Headless test for audio: the Music and Effects buses exist and take the
## volume settings (0 mutes), every audio file loads, the MusicManager plays
## Yard Idle, starts three combat layers together and crossfades them by
## intensity (with boosts), swaps in the Courier pulse, ducks under a pause,
## and plays wreck and results cues.
##
## Run:  godot --headless --fixed-fps 60 --path . -s res://tests/audio_test.gd

const MM := preload("res://scripts/music_manager.gd")
const T := preload("res://scripts/tuning.gd")

var failures: Array[String] = []
var frame := 0


func _check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + what)
	if not ok:
		failures.append(what)


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 2:
		_run()
	elif frame == 4:
		paused = true
	elif frame == 40:
		var duck: AudioEffectAmplify = root.get_node("MusicManager")._duck
		_check(duck != null and duck.volume_db < T.MUSIC_PAUSE_DUCK_DB * 0.5, "music ducks while the game is paused")
		paused = false
	elif frame == 80:
		var duck: AudioEffectAmplify = root.get_node("MusicManager")._duck
		_check(duck.volume_db > -0.5, "music comes back after the pause")
		_finish()
	return false


func _run() -> void:
	var profile := root.get_node("Profile")
	profile.persist = false
	var music := root.get_node_or_null("MusicManager")
	_check(music != null, "MusicManager autoload exists")
	for bus: String in ["Music", "Effects"]:
		_check(AudioServer.get_bus_index(bus) >= 0, "%s bus exists" % bus)
	profile.set_setting("effects", 0.5)
	var e := AudioServer.get_bus_index("Effects")
	_check(absf(AudioServer.get_bus_volume_db(e) - linear_to_db(0.5)) < 0.1, "effects volume reaches its bus")
	profile.set_setting("music", 0.0)
	_check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")), "music at 0 mutes the bus")
	profile.set_setting("music", 0.8)
	var paths: Array = [MM.YARD, MM.COURIER_MID, MM.WRECK] + MM.LAYERS + MM.SFX.values()
	for p: String in paths:
		_check(load(p) is AudioStream, "loads %s" % p)
	music.play_garage()
	_check(music.mode == "garage" and music._yard.stream != null, "garage plays Yard Idle")
	music.start_combat(false)
	var all_on := true
	for p: AudioStreamPlayer in music._layers:
		all_on = all_on and p.stream != null and p.stream.loop
	_check(all_on, "all three combat layers are loaded and loop (playback is skipped headless)")
	_check(music.intensity == 0, "a fight starts at Street Clear")
	music.set_intensity(2)
	_check(music.intensity == 2, "intensity rises to Crossfire")
	music.set_intensity(0)
	_check(music.intensity == 2, "intensity holds before dropping")
	_check(MM.intensity_for(0, 0) == 0 and MM.intensity_for(T.MUSIC_MID_RIGS, 0) == 1 and MM.intensity_for(T.MUSIC_HIGH_RIGS, 0) == 2, "intensity follows rigs alive")
	_check(MM.intensity_for(0, 0, 1) == 1 and MM.intensity_for(1, 0, 1) == 2 and MM.intensity_for(2, 30, 3) == 2, "boosts (elite, low armor, Survive's end) add steps, capped at Crossfire")
	music.start_combat(true)
	_check(str(music._layers[1].stream.resource_path) == MM.COURIER_MID, "Courier swaps in the tighter pulse")
	music.play_wreck()
	_check(music.mode == "wreck" and music._wreck.stream != null, "wreck plays the drone")
	for id: String in ["bulwark_windup", "ram_impact", "torcher_rupture", "acid_fire", "acid_impact"]:
		music.play_sfx(id)
		_check(int(music.sfx_counts.get(id, 0)) >= 1, "%s plays on Effects" % id)
	music.play_sfx("results")
	_check(music._voices.any(func(v: AudioStreamPlayer) -> bool: return v.stream != null and v.bus == "Effects"), "results cue plays on Effects")


func _finish() -> void:
	if failures.is_empty():
		print("AUDIO TEST PASSED")
		quit(0)
	else:
		print("AUDIO TEST FAILED: %s" % ", ".join(failures))
		quit(1)
