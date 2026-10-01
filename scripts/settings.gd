extends Node

signal ach_unlocked(id: String)
## Persistent user settings + run statistics (user://settings.cfg). Autoload.

const PATH := "user://settings.cfg"

var music_vol := 0.7
var sfx_vol := 0.8
var offset_ms := 0
var shake := true
var fullscreen := false
var tutorial_done := false
var lang := "ja"
var reduce_flash := false
var perk_carry := false  # level-up boosts last for the whole run (enemies get tougher)
var assist := 0  # 0 off, 1 wide, 2 very wide timing windows
var clap_on := true
var clap_vol := 0.7
var clap_type := 1  # rimshot
var clap_pat := 0  # 0 every beat, 1 beats 2 & 4 only
var bgm := -1  # -1 = random per battle, else Conductor.TRACKS index
var stats := {"runs": 0, "wins": 0, "best_floor": 0, "endless_best": 0, "best_kills": 0,
	"asc_unlocked": 0, "best_combo": 0, "fevers": 0, "perfects": 0, "total_kills": 0, "daily_day": 0, "daily_best": -1, "act1": 0, "full_clears": 0}
var ach := {}
var keymap := {}  # action -> [primary, secondary] keycodes (0 = unbound)

const ACTIONS := ["card1", "card2", "card3", "card4", "card5", "potion1", "potion2", "potion3", "potion4", "up", "down", "left", "right", "pause", "perk"]

func default_keys() -> Dictionary:
	return {
		"card1": [KEY_1, 0], "card2": [KEY_2, 0], "card3": [KEY_3, 0], "card4": [KEY_4, 0], "card5": [KEY_5, 0],
		"potion1": [KEY_6, KEY_Z], "potion2": [KEY_7, KEY_X], "potion3": [KEY_8, KEY_C], "potion4": [KEY_9, KEY_V],
		"up": [KEY_W, KEY_UP], "down": [KEY_S, KEY_DOWN], "left": [KEY_A, KEY_LEFT], "right": [KEY_D, KEY_RIGHT],
		"pause": [KEY_P, 0], "perk": [KEY_TAB, KEY_E],
	}

func reset_keys() -> void:
	keymap = default_keys()

func key_pressed(action: String) -> bool:
	for k in keymap.get(action, []):
		if k != 0 and Input.is_key_pressed(k):
			return true
	return false

func action_for_key(k: int) -> String:
	for a in ACTIONS:
		if k in keymap[a]:
			return a
	return ""

func bind(action: String, slot: int, k: int) -> void:
	for a in ACTIONS:
		for i in 2:
			if keymap[a][i] == k:
				keymap[a][i] = 0
	keymap[action][slot] = k

func key_name(k: int) -> String:
	return "-" if k == 0 else OS.get_keycode_string(k)
var char_wins := {}
var bosses := {}

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
	lang = "ja" if OS.get_locale_language() == "ja" else "en"
	reset_keys()
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
	clap_on = cf.get_value("game", "clap_on", clap_on)
	clap_vol = cf.get_value("game", "clap_vol", clap_vol)
	clap_type = cf.get_value("game", "clap_type", clap_type)
	clap_pat = cf.get_value("game", "clap_pat", clap_pat)
	tutorial_done = cf.get_value("game", "tutorial_done", tutorial_done)
	lang = cf.get_value("game", "lang", lang)
	reduce_flash = cf.get_value("game", "reduce_flash", reduce_flash)
	assist = cf.get_value("game", "assist", assist)
	perk_carry = cf.get_value("game", "perk_carry", perk_carry)
	for k in stats:
		stats[k] = cf.get_value("stats", k, stats[k])
	for a in ACTIONS:
		if cf.has_section_key("keys", a):
			var kv = cf.get_value("keys", a)
			if kv is Array and kv.size() == 2:
				keymap[a] = [int(kv[0]), int(kv[1])]
	if int(cf.get_value("game", "version", 1)) < 2:
		clap_type = 1  # new default: rimshot
	for id in Achievements.DB:
		if cf.get_value("ach", id, false):
			ach[id] = true
	for ch in Characters.DB:
		char_wins[ch] = cf.get_value("char_wins", ch, 0)
	for bn in ["bass", "drum", "metronome"]:
		if cf.get_value("bosses", bn, false):
			bosses[bn] = true

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
	cf.set_value("game", "clap_on", clap_on)
	cf.set_value("game", "clap_vol", clap_vol)
	cf.set_value("game", "clap_type", clap_type)
	cf.set_value("game", "clap_pat", clap_pat)
	cf.set_value("game", "tutorial_done", tutorial_done)
	cf.set_value("game", "lang", lang)
	cf.set_value("game", "reduce_flash", reduce_flash)
	cf.set_value("game", "assist", assist)
	cf.set_value("game", "perk_carry", perk_carry)
	for k in stats:
		cf.set_value("stats", k, stats[k])
	cf.set_value("game", "version", 2)
	for a in ACTIONS:
		cf.set_value("keys", a, keymap[a])
	for id in ach:
		cf.set_value("ach", id, true)
	for ch in char_wins:
		cf.set_value("char_wins", ch, char_wins[ch])
	for bn in bosses:
		cf.set_value("bosses", bn, true)
	cf.save(PATH)

func _is_test() -> bool:
	for a in OS.get_cmdline_user_args():
		if a == "--autotest" or a.begins_with("--screen="):
			return true
	return false

## Returns true if newly unlocked. (Tests never persist or toast.)
func unlock(id: String) -> bool:
	if ach.has(id) or not Achievements.DB.has(id):
		return false
	ach[id] = true
	if not _is_test():
		save_cfg()
		ach_unlocked.emit(id)
	return true

func chars_unlocked() -> Array:
	var out: Array = ["wizard", "knight", "ranger"]
	if stats["wins"] >= 1 or stats["act1"] >= 1:
		out.append("drummer")
	return out
