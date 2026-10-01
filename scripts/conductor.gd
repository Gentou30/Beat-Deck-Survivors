extends Node
## Global beat clock. Generates its own music procedurally; SFX are Kenney CC0 .ogg files,
## and exposes song_time / beat signal / timing-offset helpers for rhythm judging.

signal beat(n: int)

const MIX_RATE := 22050
const LOOP_BEATS := 8
## CC0 tracks by Joth (opengameart.org). bpm/beats were measured; the files are ~50-70 ms
## longer than `beats`, so we restart playback at exactly `beats` instead of stream looping.
## offset = time of the first beat inside the file (seconds).
const TRACKS := [
	{"name": "Party Sector", "path": "res://assets/music/party_sector.mp3", "bpm": 120.0, "beats": 192, "offset": 0.0},
	{"name": "Dreaming of Victory", "path": "res://assets/music/dreaming_of_victory.mp3", "bpm": 120.0, "beats": 208, "offset": -0.04},
	{"name": "Porkymon Battle", "path": "res://assets/music/pkmn_battle_main.mp3", "bpm": 148.0, "beats": 64, "offset": 0.0},
]

var track_idx := 0
var bpm := 120.0
var track_offset := 0.0
var spb: float = 0.5
var song_time: float = 0.0
var running: bool = false
var clock_only: bool = false  # headless / tests: ignore audio position

var _music: AudioStreamPlayer
var _sfx: Dictionary = {}
var _loop_len: float
var _loops: int = 0
var _last_pos: float = 0.0
var _last_beat: int = -1
var _manual_loop := false

func _ready() -> void:
	clock_only = DisplayServer.get_name() == "headless"
	_music = AudioStreamPlayer.new()
	_apply_track(0)
	_music.volume_db = -6.0
	_music.bus = "Music"
	add_child(_music)
	var d := "res://assets/kenney_interface_sounds/"
	_sfx["perfect"] = load(d + "confirmation_002.ogg")
	_sfx["good"] = load(d + "click_003.ogg")
	_sfx["miss"] = load(d + "error_003.ogg")
	_sfx["hit"] = load(d + "drop_001.ogg")
	_sfx["boom"] = load(d + "bong_001.ogg")
	_sfx["card"] = load(d + "pluck_001.ogg")
	_sfx["select"] = load(d + "select_002.ogg")
	_sfx["tick"] = load(d + "tick_002.ogg")
	_sfx["toggle"] = load(d + "toggle_001.ogg")
	_sfx["big"] = load(d + "maximize_006.ogg")
	_sfx["open"] = load(d + "open_001.ogg")
	_sfx["win"] = load(d + "confirmation_004.ogg")
	for k in _sfx:
		var p := AudioStreamPlayer.new()
		p.stream = _sfx[k]
		p.volume_db = -6.0
		p.bus = "SFX"
		add_child(p)
		_sfx[k] = p

func _apply_track(i: int) -> void:
	track_idx = i
	var t: Dictionary = TRACKS[i]
	bpm = t["bpm"]
	spb = 60.0 / bpm
	track_offset = t["offset"]
	if ResourceLoader.exists(t["path"]):
		_music.stream = load(t["path"])
		_loop_len = spb * int(t["beats"])
		_manual_loop = true
	else:
		bpm = 120.0
		spb = 0.5
		track_offset = 0.0
		_music.stream = _make_music()
		_loop_len = spb * LOOP_BEATS
		_manual_loop = false

func _reset_clock() -> void:
	song_time = 0.0
	_loops = 0
	_last_pos = 0.0
	_last_beat = -1

func start() -> void:
	_reset_clock()
	running = true
	if not clock_only:
		_music.play()

## Switch to another track (restarts the song / beat clock).
func set_track(i: int) -> void:
	i = clampi(i, 0, TRACKS.size() - 1)
	var was_playing := running and not clock_only
	_music.stop()
	_apply_track(i)
	_reset_clock()
	if was_playing:
		_music.play()

## Pick the BGM for a battle: mode >= 0 fixed track, -1 random (different from current).
func choose_for_battle(mode: int) -> void:
	if mode >= 0:
		if mode != track_idx:
			set_track(mode)
		return
	var opts: Array = []
	for i in TRACKS.size():
		if i != track_idx:
			opts.append(i)
	set_track(opts.pick_random())

func play_sfx(kind: String) -> void:
	if clock_only or not _sfx.has(kind):
		return
	(_sfx[kind] as AudioStreamPlayer).play()

var offset: float:
	get:
		return Settings.offset_ms / 1000.0 + track_offset

func set_paused(p: bool) -> void:
	running = not p
	_music.stream_paused = p

## Offset ignoring the user setting (used by the calibration screen).
func raw_beat_offset() -> float:
	var phase := fposmod(song_time - track_offset, spb)
	return phase if phase < spb * 0.5 else phase - spb

func _process(delta: float) -> void:
	if not running:
		return
	if clock_only or not _music.playing:
		song_time += delta
	else:
		var p := _music.get_playback_position() + AudioServer.get_time_since_last_mix()
		if _manual_loop and p >= _loop_len - 0.02:
			_loops += 1
			_music.play(0.0)
			_last_pos = 0.0
			return
		if p < _last_pos - 1.0:
			_loops += 1
		_last_pos = p
		song_time = _loops * _loop_len + p - AudioServer.get_output_latency()
	var cur := floori((song_time - offset) / spb)
	while _last_beat < cur:
		_last_beat += 1
		beat.emit(_last_beat)

## Seconds from the nearest beat; positive = late, negative = early.
func beat_offset() -> float:
	var phase := fposmod(song_time - offset, spb)
	return phase if phase < spb * 0.5 else phase - spb

## 0..1 within the current beat (0 = on the beat).
func beat_phase() -> float:
	return fposmod(song_time - offset, spb) / spb

# ---- procedural audio ------------------------------------------------------

func _make_music() -> AudioStreamWAV:
	var n := int(MIX_RATE * spb * LOOP_BEATS)
	var data := PackedByteArray()
	data.resize(n * 2)
	var bass := [55.0, 55.0, 65.41, 49.0]
	var lead := [220.0, 261.63, 329.63, 261.63, 196.0, 246.94, 293.66, 246.94]
	for i in n:
		var t := float(i) / MIX_RATE
		var bt := fposmod(t, spb)
		var s := 0.0
		# kick on every beat
		var phase := 45.0 * bt + 90.0 * (1.0 - exp(-30.0 * bt)) / 30.0
		s += 0.7 * sin(TAU * phase) * exp(-bt * 12.0)
		# off-beat hat
		var ht := fposmod(t - spb * 0.5, spb)
		s += 0.10 * (randf() * 2.0 - 1.0) * exp(-ht * 70.0)
		# bass with pseudo side-chain
		var bn: float = bass[(int(t / spb) / 2) % 4]
		s += 0.22 * sin(TAU * bn * t) * minf(1.0, bt * 8.0)
		# eighth-note lead
		var ei := int(t / (spb * 0.5))
		var et := fposmod(t, spb * 0.5)
		var lf: float = lead[ei % 8]
		s += 0.07 * signf(sin(TAU * lf * et)) * exp(-et * 9.0)
		data.encode_s16(i * 2, int(clampf(s * 0.8, -1.0, 1.0) * 30000.0))
	return _wav(data, true)

func _wav(data: PackedByteArray, looped: bool) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = MIX_RATE
	w.stereo = false
	w.data = data
	if looped:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = data.size() / 2
	return w
