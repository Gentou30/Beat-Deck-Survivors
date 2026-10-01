extends Node
## Persistent user settings + run statistics (user://settings.cfg). Autoload.

const PATH := "user://settings.cfg"

var music_vol := 0.7
var sfx_vol := 0.8
var offset_ms := 0
var shake := true
var fullscreen := false
var tutorial_done := false
var bgm := -1  # -1 = random per battle, else Conductor.TRACKS index
var stats := {"runs": 0, "wins": 0, "best_floor": 0, "endless_best": 0, "best_kills": 0}

func _ready() -> void:
	for n in ["Music", "SFX"]:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, n)
		AudioServer.set_bus_send(i, "Master")
	var lp := AudioEffectLowPassFilter.new()
	lp.cutoff_hz = 1100.0
	var mi := AudioServer.get_bus_index("Music")
	AudioServer.add_bus_effect(mi, lp, 0)
	AudioServer.set_bus_effect_enabled(mi, 0, false)
	load_cfg()
	apply()

func apply() -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(maxf(music_vol, 0.0001)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(maxf(sfx_vol, 0.0001)))
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)

func load_cfg() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	music_vol = cf.get_value("audio", "music", music_vol)
	sfx_vol = cf.get_value("audio", "sfx", sfx_vol)
	offset_ms = cf.get_value("game", "offset_ms", offset_ms)
	shake = cf.get_value("game", "shake", shake)
	fullscreen = cf.get_value("game", "fullscreen", fullscreen)
	bgm = cf.get_value("game", "bgm", bgm)
	tutorial_done = cf.get_value("game", "tutorial_done", tutorial_done)
	for k in stats:
		stats[k] = cf.get_value("stats", k, stats[k])

func save_cfg() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--autotest" or a.begins_with("--screen="):
			return
	var cf := ConfigFile.new()
	cf.set_value("audio", "music", music_vol)
	cf.set_value("audio", "sfx", sfx_vol)
	cf.set_value("game", "offset_ms", offset_ms)
	cf.set_value("game", "shake", shake)
	cf.set_value("game", "fullscreen", fullscreen)
	cf.set_value("game", "bgm", bgm)
	cf.set_value("game", "tutorial_done", tutorial_done)
	for k in stats:
		cf.set_value("stats", k, stats[k])
	cf.save(PATH)
