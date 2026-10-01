extends SceneTree
# Dev tool: play an audio file headless and dump mono float32 samples to a file for BPM analysis.
# Usage: godot --headless --path . -s tools/capture_audio.gd -- res://x.mp3 out.raw seconds
var cap: AudioEffectCapture
var out: FileAccess
var left := 0.0
var player: AudioStreamPlayer
var rate := 0.0
func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	AudioServer.add_bus()
	var b := AudioServer.bus_count - 1
	cap = AudioEffectCapture.new()
	cap.buffer_length = 2.0
	AudioServer.add_bus_effect(b, cap)
	AudioServer.set_bus_send(b, "Master")
	var p := AudioStreamPlayer.new()
	player = p
	p.stream = load(a[0])
	p.bus = AudioServer.get_bus_name(b)
	root.add_child(p)
	out = FileAccess.open(a[1], FileAccess.WRITE)
	left = float(a[2])
	rate = AudioServer.get_mix_rate()
	print("mix rate ", rate)
func _process(delta: float) -> bool:
	if not player.playing:
		player.play()
	var n := cap.get_frames_available()
	if n > 0:
		for f in cap.get_buffer(n):
			out.store_float((f.x + f.y) * 0.5)
	left -= delta
	if left <= 0.0:
		out.close()
		return true
	return false
