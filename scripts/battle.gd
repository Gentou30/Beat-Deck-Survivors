class_name Battle
extends RefCounted
## One real-time battle: survivor-style swarm + card hand played on the beat.
## kind: battle | elite | boss | endless. Emits `finished(won)`.

signal finished(won: bool)

const W := 1280.0
const H := 720.0
const HAND_SIZE := 5
const ARENA_BOTTOM := 490.0
const TILE_DIR := "res://assets/kenney_tiny_dungeon/tile_%04d.png"
const TILE_SWORD := 104
const GOOD_BASE := 0.14
const PERFECT_BASE := 0.07
const BOSS_NAMES := {"bass": "ベースデーモン", "drum": "ドラムメイジ", "metronome": "メトロノーム・ジャイアント", "maestro": "マエストロ"}
const TILE_DIR2 := "res://assets/kenney_tiny_battle/tile_%04d.png"
const ACT2_TILES := {"grunt": 160, "fast": 154, "tank": 152, "shooter": 153, "charger": 150, "splitter": 155, "elite": 158, "bomber": 173}

class Enemy:
	var pos := Vector2.ZERO
	var hp := 10.0
	var max_hp := 10.0
	var speed := 80.0
	var radius := 12.0
	var dmg := 6
	var color := Color.RED
	var kind := "grunt"
	var blade_cd := 0.0
	var flash := 0.0
	var spawn_t := 0.35
	var phase := 0.0
	var tex: Texture2D
	var stun := 0
	var ctr := 0
	var tele := 0
	var aim_dir := Vector2.ZERO
	var dash_t := 0.0
	var dash_dir := Vector2.ZERO
	var boss_id := ""
	var thorn_cd := 0.0
	var bphase := 0

class Bolt:
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var dmg := 8.0
	var life := 1.6
	var color := Color(1.0, 0.85, 0.5)
	var pierce := 0
	var hit_ids: Array = []

class EShot:
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var dmg := 5
	var life := 6.0

class Part:
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var life := 0.5
	var max_life := 0.5
	var color := Color.WHITE
	var size := 4.0
	var grav := 0.0

class Fx:
	var kind := "ring"  # ring | line | beam | text
	var pos := Vector2.ZERO
	var to := Vector2.ZERO
	var text := ""
	var color := Color.WHITE
	var life := 0.4
	var max_life := 0.4
	var radius := 100.0
	var size := 18
	var tex: Texture2D

var run: RunState
var ui: Ui
var kind := "battle"
var diff := 1.0
var char_def: Dictionary
var deck := Deck.new()
var enemies: Array[Enemy] = []
var bolts: Array[Bolt] = []
var parts: Array[Part] = []
var fxs: Array[Fx] = []
var slams: Array = []  # {pos, r, t, dmg}
var eshots: Array[EShot] = []
var delayed: Array = []  # {beats, pos, r, dmg}
var pending_spawns: Array[Enemy] = []
var boss_id := "bass"
var fever_gauge := 0.0
var fever_beats := 0
var overdrive := 0
var thorns := 0
var heart_k := 0
var last_card := ""
var aegis_ready := false

var player_pos := Vector2(W / 2.0, 250.0)
var shield := 0
var energy := 3
var max_energy := 5
var invuln := 0.0
var combo := 0
var kills := 0
var time_left := 24.0
var spawning := true
var beat_count := 0
var energy_t := 0.0
var spawn_acc := 0.0
var blade_beats := 0
var blade_n := 3
var blade_power := 1.0
var blade_angle := 0.0
var frenzy_beats := 0
var slow_beats := 0
var echo_pending := false
var res_bonus := 0
var fort := 0
var aura_k := 0
var aura_count := 0
var fang_count := 0
var banner := ""
var banner_time := 0.0
var shake := 0.0
var hitstop := 0.0
var beat_pulse := 0.0
var flash_a := 0.0
var flash_col := Color.WHITE
var ending := false
var tutorial := false
var tut_step := 0
var tut_timer := 0.0
var moved_dist := 0.0
var plays := 0
var perfects := 0
var last_off := 0.0
var last_off_t := 0.0
var last_off_col := Color.WHITE
var touch_dir := Vector2.ZERO
var cast_name := ""
var cast_short := ""
var cast_col := Color.WHITE
var cast_grade := ""
var cast_t := 0.0
var slot_anim: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
var done := false
var cur_base := Transform2D.IDENTITY
var player_vel := Vector2.ZERO
var facing := 1.0
var _muffled := false
var started := false
var count_n := 0
var count_t := 0.0
var intro_banner := ""
var took_damage := false
var end_timer := 0.0
var end_won := false
var elapsed := 0.0
var _trail_t := 0.0
var _lit := {}
var _stars: Array = []
var _tex_cache := {}
var _beat_cb: Callable
var _step_cb: Callable

func _init() -> void:
	for i in 70:
		_stars.append([Vector2(randf() * W, randf() * H), randf() * TAU, 0.3 + randf() * 0.7])

func tex(i: int) -> Texture2D:
	if not _tex_cache.has(i):
		_tex_cache[i] = load(TILE_DIR % i)
	return _tex_cache[i]

func tex2(i: int) -> Texture2D:
	var key := 1000 + i
	if not _tex_cache.has(key):
		_tex_cache[key] = load(TILE_DIR2 % i)
	return _tex_cache[key]

func setup(p_run: RunState, p_kind: String, p_diff: float, p_ui: Ui) -> void:
	run = p_run
	ui = p_ui
	kind = p_kind
	diff = p_diff
	char_def = Characters.DB[run.char_id]
	deck.setup(run.deck, HAND_SIZE)
	max_energy = run.max_energy()
	energy = 3
	shield = 0
	if run.char_id == "knight":
		shield += 8
	if run.has_relic("ring"):
		shield += 10
	tutorial = kind == "tutorial"
	boss_id = run.boss_id if run.mode == "run" else (["bass", "drum", "metronome"] as Array)[(run.wave / 10) % 3]
	echo_pending = run.has_relic("echoshell")
	aegis_ready = run.has_relic("aegis")
	time_left = 0.0 if (kind == "boss" or tutorial) else (26.0 if kind == "elite" or kind == "endless" else 24.0)
	spawning = true
	match kind:
		"boss":
			banner = "BOSS: " + String(BOSS_NAMES[boss_id])
			var b := _make_enemy("boss")
			b.pos = Vector2(W / 2.0, -40.0)
			enemies.append(b)
		"elite":
			banner = "エリート出現！"
			var e := _make_enemy("elite")
			e.pos = _edge_point()
			enemies.append(e)
		"tutorial":
			banner = ""
		"endless":
			banner = Loc.t("ウェーブ %d") % (run.wave + 1)
		_:
			banner = "バトル開始"
	banner_time = 2.2
	intro_banner = banner
	Conductor.guide = true
	Conductor.force_clap = true  # 4-beat countdown claps always sound
	_beat_cb = Callable(self, "on_beat")
	Conductor.beat.connect(_beat_cb)
	_step_cb = Callable(self, "on_step")
	Conductor.step.connect(_step_cb)

func dispose() -> void:
	Conductor.set_muffle(false)
	Conductor.guide = false
	Conductor.force_clap = false
	if Conductor.beat.is_connected(_beat_cb):
		Conductor.beat.disconnect(_beat_cb)
	if Conductor.step.is_connected(_step_cb):
		Conductor.step.disconnect(_step_cb)

# ---- helpers ---------------------------------------------------------------

func perfect_window() -> float:
	return 0.03 * Settings.assist + PERFECT_BASE + (0.02 if run.has_relic("metronome") else 0.0) + (0.025 if run.char_id == "drummer" else 0.0)

func good_window() -> float:
	return 0.03 * Settings.assist + GOOD_BASE + (0.02 if run.has_relic("metronome") else 0.0) + (0.025 if run.char_id == "drummer" else 0.0)

func dmg_mult() -> float:
	var per := (0.03 if run.has_relic("amp") else 0.02) + (0.01 if run.char_id == "drummer" else 0.0)
	return (2.0 if frenzy_beats > 0 else 1.0) * (1.5 if fever_beats > 0 else 1.0) * (1.0 + minf(combo, 20.0) * per)

const THEMES := [
	{"floor": Color(0.45, 0.85, 1.9), "line": Color(0.6, 0.5, 1.0), "tint": Color(0.4, 0.3, 0.9)},
	{"floor": Color(1.9, 0.8, 0.45), "line": Color(1.0, 0.5, 0.3), "tint": Color(0.9, 0.35, 0.15)},
	{"floor": Color(0.35, 1.6, 1.4), "line": Color(0.3, 1.0, 0.9), "tint": Color(0.1, 0.7, 0.6)},
	{"floor": Color(0.55, 1.05, 1.9), "line": Color(0.45, 0.75, 1.0), "tint": Color(0.2, 0.4, 0.9)},
]

func theme() -> Dictionary:
	var i := 0
	if run.mode == "run" and run.act == 2:
		i = 3 if run.floor_idx < 5 else 2
	elif run.mode == "run":
		i = clampi(maxi(run.floor_idx, 0) / 4, 0, 2)
	else:
		i = (run.wave / 5) % 3
	return THEMES[i]

func fever_max() -> float:
	return 8.0 if run.has_relic("headphones") else 10.0

func _add_fever(v: float) -> void:
	if fever_beats > 0:
		return
	fever_gauge = minf(fever_max(), fever_gauge + v)
	if fever_gauge >= fever_max():
		_start_fever()

func _start_fever() -> void:
	Settings.stats["fevers"] += 1
	Settings.unlock("fever")
	fever_beats = 8
	fever_gauge = 0.0
	banner = "FEVER!!"
	banner_time = 1.6
	flash(Color(1.0, 0.85, 0.3), 0.55)
	ring(player_pos, 320.0, Color(1.0, 0.85, 0.3), 0.6)
	burst(player_pos, Color(1.0, 0.9, 0.4), 70, 520.0, 0.8, 6.0)
	do_shake(14.0)
	hitstop = 0.08
	Conductor.play_sfx("big")
	for e in enemies:
		if e.pos.distance_to(player_pos) < 320.0 + e.radius:
			hit(e, 25.0 * dmg_mult())
			e.pos += (e.pos - player_pos).normalized() * 60.0

func _pick_kind() -> String:
	if run.act == 2 and run.mode == "run":
		var r2 := randf()
		if r2 < 0.12:
			return "tank"
		if r2 < 0.25:
			return "shooter"
		if r2 < 0.35:
			return "charger"
		if r2 < 0.43:
			return "splitter"
		if r2 < 0.57:
			return "bomber"
		if r2 < 0.72:
			return "fast"
		return "grunt"
	var r := randf()
	if diff >= 2.2 and r < 0.12:
		return "tank"
	if diff >= 2.0 and r < 0.22:
		return "shooter"
	if diff >= 2.6 and r < 0.30:
		return "charger"
	if diff >= 1.8 and r < 0.40:
		return "splitter"
	if diff >= 1.5 and r < 0.58:
		return "fast"
	return "grunt"

func _eshot(p: Vector2, dir: Vector2, spd: float, dmg: int) -> void:
	var sh := EShot.new()
	sh.pos = p
	sh.vel = dir.normalized() * spd
	sh.dmg = dmg
	eshots.append(sh)

func _keep_distance(e: Enemy, to_p: Vector2, far: float, near: float) -> Vector2:
	var dd := e.pos.distance_to(player_pos)
	if dd > far:
		return to_p
	if dd < near:
		return -to_p
	return to_p.orthogonal() * (1.0 if sin(e.phase) > 0.0 else -1.0)

func _cluster_pos() -> Vector2:
	var best := player_pos + Vector2(0, -160)
	var best_n := -1
	var cand := nearest_enemies(14)
	for a in cand:
		var n := 0
		for b in cand:
			if (a as Enemy).pos.distance_to((b as Enemy).pos) < 130.0:
				n += 1
		if n > best_n:
			best_n = n
			best = (a as Enemy).pos
	return best

func _mini_nova() -> void:
	ring(player_pos, 130.0, Color(0.95, 0.7, 0.4), 0.35)
	burst(player_pos, Color(0.95, 0.7, 0.4), 20, 260.0, 0.4, 4.0)
	for e in enemies:
		if e.pos.distance_to(player_pos) < 130.0 + e.radius:
			hit(e, 12.0 * dmg_mult())

func card_rect(i: int) -> Rect2:
	var cw := 150.0
	var gap := 12.0
	var x0 := (W - (HAND_SIZE * cw + (HAND_SIZE - 1) * gap)) / 2.0
	return Rect2(x0 + i * (cw + gap), H - 210.0, cw, 196.0)

func _edge_point() -> Vector2:
	match randi() % 4:
		0: return Vector2(randf() * W, -30.0)
		1: return Vector2(randf() * W, ARENA_BOTTOM + 30.0)
		2: return Vector2(-30.0, randf() * ARENA_BOTTOM)
		_: return Vector2(W + 30.0, randf() * ARENA_BOTTOM)

func _make_enemy(k: String) -> Enemy:
	var e := Enemy.new()
	e.kind = k
	var d := diff
	match k:
		"boss":
			e.boss_id = boss_id
			e.max_hp = 260.0 + 70.0 * d
			e.speed = 48.0
			e.radius = 44.0
			e.dmg = 14
			e.color = Color(0.85, 0.25, 0.6)
			e.tex = tex(110)
			if boss_id == "drum":
				e.max_hp = 220.0 + 60.0 * d
				e.speed = 36.0
				e.radius = 38.0
				e.color = Color(0.5, 0.7, 1.0)
				e.tex = tex(111)
			elif boss_id == "maestro":
				e.max_hp = 420.0 + 90.0 * d
				e.speed = 40.0
				e.radius = 54.0
				e.dmg = 16
				e.color = Color(1.0, 0.35, 0.35)
				e.tex = tex2(68)
			elif boss_id == "metronome":
				e.max_hp = 300.0 + 80.0 * d
				e.speed = 44.0
				e.radius = 50.0
				e.color = Color(1.0, 0.7, 0.3)
				e.tex = tex(109)
		"shooter":
			e.max_hp = 14.0 + 6.0 * d
			e.speed = 70.0
			e.radius = 13.0
			e.dmg = 4 + int(d)
			e.color = Color(0.7, 0.8, 1.0)
			e.tex = tex(121)
		"charger":
			e.max_hp = 26.0 + 12.0 * d
			e.speed = 60.0
			e.radius = 16.0
			e.dmg = 7 + int(d)
			e.color = Color(1.0, 0.6, 0.4)
			e.tex = tex(123)
		"bomber":
			e.max_hp = 12.0 + 5.0 * d
			e.speed = 105.0 + 4.0 * d
			e.radius = 13.0
			e.dmg = 9 + int(d * 0.6)
			e.color = Color(1.0, 0.55, 0.2)
			e.tex = tex(120)
		"splitter":
			e.max_hp = 28.0 + 10.0 * d
			e.speed = 54.0 + 3.0 * d
			e.radius = 17.0
			e.dmg = 5 + int(d)
			e.color = Color(0.7, 0.9, 0.5)
			e.tex = tex(124)
		"elite":
			e.max_hp = 110.0 + 38.0 * d
			e.speed = 62.0 + 3.0 * d
			e.radius = 30.0
			e.dmg = 9 + int(d)
			e.color = Color(0.95, 0.75, 0.3)
			e.tex = tex(109)
		"tank":
			e.max_hp = 40.0 + 20.0 * d
			e.speed = 42.0 + 4.0 * d
			e.radius = 20.0
			e.dmg = 8 + int(d * 1.4)
			e.color = Color(0.7, 0.55, 0.9)
			e.tex = tex(122)
		"fast":
			e.max_hp = 7.0 + 3.5 * d
			e.speed = 125.0 + 8.0 * d
			e.radius = 10.0
			e.dmg = 4 + int(d * 0.7)
			e.color = Color(1.0, 0.65, 0.35)
			e.tex = tex(120)
		_:
			e.max_hp = 11.0 + 7.0 * d
			e.speed = 62.0 + 9.0 * d + randf() * 18.0
			e.radius = 12.0 + randf() * 3.0
			e.dmg = 4 + int(d)
			e.color = Color(0.4, 1.0, 0.8)
			e.tex = tex(108)
	if run.act == 2 and run.mode == "run" and k != "boss" and ACT2_TILES.has(k):
		e.tex = tex2(ACT2_TILES[k])
	var hpm := 1.0 + 0.1 * run.asc + (0.25 if run.mod_id == 1 else 0.0)
	if k == "boss" and run.asc >= 4:
		hpm *= 1.25
	e.max_hp *= hpm
	e.speed *= 1.0 + 0.04 * maxi(0, run.asc - 1)
	e.hp = e.max_hp
	e.phase = randf() * TAU
	return e

func nearest_enemies(n: int) -> Array:
	var arr: Array = enemies.filter(func(e: Enemy) -> bool: return e.spawn_t <= 0.0)
	arr.sort_custom(func(a: Enemy, b: Enemy) -> bool:
		return a.pos.distance_squared_to(player_pos) < b.pos.distance_squared_to(player_pos))
	return arr.slice(0, n)

# ---- juice helpers ---------------------------------------------------------

func burst(p: Vector2, col: Color, n: int, spd: float, life := 0.5, size := 4.0, grav := 0.0) -> void:
	if parts.size() > 700:
		return
	for i in n:
		var q := Part.new()
		q.pos = p
		q.vel = Vector2.from_angle(randf() * TAU) * spd * (0.3 + randf() * 0.9)
		q.life = life * (0.6 + randf() * 0.6)
		q.max_life = q.life
		q.color = col.lerp(Color.WHITE, randf() * 0.4)
		q.size = size * (0.6 + randf() * 0.8)
		q.grav = grav
		parts.append(q)

func ring(p: Vector2, r: float, col: Color, life := 0.35) -> void:
	var f := Fx.new()
	f.kind = "ring"
	f.pos = p
	f.radius = r
	f.color = col
	f.life = life
	f.max_life = life
	fxs.append(f)

func float_text(p: Vector2, s: String, col: Color, size := 18, life := 0.7) -> void:
	if fxs.size() > 160:
		return
	var f := Fx.new()
	f.kind = "text"
	f.pos = p + Vector2(randf_range(-10, 10), 0)
	f.text = s
	f.color = col
	f.size = size
	f.life = life
	f.max_life = life
	fxs.append(f)

func line_fx(a: Vector2, b: Vector2, col: Color, life := 0.18, kind_s := "line", w := 3.0) -> void:
	var f := Fx.new()
	f.kind = kind_s
	f.pos = a
	f.to = b
	f.color = col
	f.life = life
	f.max_life = life
	f.radius = w
	fxs.append(f)

func do_shake(a: float) -> void:
	if Settings.shake:
		shake = maxf(shake, a)

func flash(col: Color, a: float) -> void:
	flash_col = col
	flash_a = maxf(flash_a, a * (0.25 if Settings.reduce_flash else 1.0))

# ---- simulation ------------------------------------------------------------

func on_beat(_n: int) -> void:
	beat_pulse = 1.0
	beat_count += 1
	if not started:
		var bi := beat_count - 1
		if bi < 4:
			count_n = 4 - bi
			count_t = 1.0
			return
		started = true
		Conductor.force_clap = false
		count_n = 0
		count_t = 0.7
		banner = "GO!"
		banner_time = 0.9
		flash(Color(1, 1, 1), 0.25)
		ring(player_pos, 140.0, Color(1.0, 0.9, 0.4), 0.5)
		burst(player_pos, Color(1.0, 0.9, 0.4), 30, 320.0, 0.6, 5.0)
		Conductor.play_sfx("big")
		return
	for i in 4:
		_lit[Vector2i(randi() % 20, randi() % 8)] = 1.0
	if ending:
		return
	ring(player_pos, 70.0, Color(1, 1, 1, 0.25), 0.4)
	for dl in delayed:
		dl["beats"] -= 1
	for dl in delayed:
		if dl["beats"] <= 0:
			var dp: Vector2 = dl["pos"]
			ring(dp, dl["r"], Color(1.0, 0.55, 0.25), 0.5)
			burst(dp, Color(1.0, 0.6, 0.25), 45, 380.0, 0.6, 6.0, 120.0)
			do_shake(11.0)
			hitstop = 0.05
			Conductor.play_sfx("boom")
			for e in enemies:
				if e.pos.distance_to(dp) < float(dl["r"]) + e.radius:
					hit(e, float(dl["dmg"]))
	delayed = delayed.filter(func(d: Dictionary) -> bool: return d["beats"] > 0)
	if fever_beats > 0:
		fever_beats -= 1
		if fever_beats == 0:
			float_text(player_pos + Vector2(0, -80), "フィーバー終了", Color(1.0, 0.9, 0.5), 16)
	if run.has_relic("shieldgen") and beat_count % 2 == 0 and shield < 10:
		shield += 1
	if run.has_relic("drumstick") and beat_count % 10 == 0:
		_mini_nova()
	if heart_k > 0 and beat_count % heart_k == 0:
		_heal(1)
	if blade_beats > 0:
		blade_beats -= 1
	if frenzy_beats > 0:
		frenzy_beats -= 1
	if slow_beats > 0:
		slow_beats -= 1
	energy_t += Conductor.spb  # 1 energy per second regardless of BPM
	if energy_t >= 1.0:
		energy_t -= 1.0
		energy = mini(max_energy, energy + 1)
	if fort > 0 and beat_count % 4 == 0:
		shield = mini(60, shield + fort)
		float_text(player_pos + Vector2(0, -34), "+%d" % fort, Color(0.5, 0.7, 1.0))
	# auto weapon
	var targets := nearest_enemies(2 if run.char_id == "ranger" else 1)
	var adm := 4.0 + res_bonus + (3.0 if run.has_relic("sword") else 0.0)
	for i in targets.size():
		var ab := _fire_bolt((targets[i] as Enemy).pos, adm * dmg_mult(), 0.0)
		if run.has_relic("scope"):
			ab.pierce = 2
	# spawning
	if tutorial:
		if tut_step >= 1 and enemies.size() < 2 + tut_step and beat_count % 2 == 0:
			var te := _make_enemy("grunt")
			te.pos = _edge_point()
			enemies.append(te)
	elif spawning and enemies.size() < 110 and (kind != "boss" or beat_count % 2 == 0):
		spawn_acc += (1 + int(diff / 2.0)) * Conductor.spb / 0.5  # same spawns per second at any BPM
		var n := int(spawn_acc)
		spawn_acc -= n
		for i in n:
			var k := _pick_kind()
			var e := _make_enemy(k)
			e.pos = _edge_point()
			enemies.append(e)
	# enemy abilities, all locked to the beat grid
	for e in enemies:
		if e.spawn_t > 0.0:
			continue
		e.ctr += 1
		if e.stun > 0:
			e.stun -= 1
			continue
		var to_p := (player_pos - e.pos).normalized()
		match e.kind:
			"shooter":
				if e.ctr % 4 == 3:
					e.tele = 1
					e.aim_dir = to_p
				elif e.ctr % 4 == 0 and e.tele > 0:
					e.tele = 0
					_eshot(e.pos, e.aim_dir, 240.0, 4 + int(diff))
			"charger":
				if e.ctr % 6 == 4:
					e.tele = 2
					e.aim_dir = to_p
				elif e.tele > 0:
					e.tele -= 1
					if e.tele == 0:
						e.dash_dir = e.aim_dir
						e.dash_t = 0.45
			"bomber":
				if e.ctr >= 6:
					_bomber_boom(e)
			"elite":
				if e.ctr % 8 == 4:
					slams.append({"pos": player_pos, "r": 120.0, "t": 4.0 * Conductor.spb, "dmg": 10})
			"boss":
				_boss_beat(e, to_p)

func _bomber_boom(e: Enemy) -> void:
	if e.hp <= 0.0:
		return
	e.hp = 0.0
	ring(e.pos, 95.0, Color(1.0, 0.55, 0.2), 0.4)
	burst(e.pos, Color(1.0, 0.6, 0.2), 26, 300.0, 0.5, 5.0, 100.0)
	do_shake(6.0)
	Conductor.play_sfx("boom")
	if invuln <= 0.0 and e.pos.distance_to(player_pos) < 95.0 + 14.0:
		damage_player(e.dmg)

## Boss shots keyed to the music's actual off-beat accents (measured per track).
func on_step(n: int) -> void:
	if ending or tutorial or kind != "boss":
		return
	if not ((n % 16) in Conductor.hits):
		return
	for e in enemies:
		if e.kind == "boss" and e.spawn_t <= 0.0 and (e.boss_id == "drum" or e.boss_id == "maestro"):
			_eshot(e.pos, player_pos - e.pos, 270.0, 5 + int(diff * 0.5))
			ring(e.pos, e.radius + 8.0, Color(1.0, 0.5, 0.7), 0.18)

func _boss_beat(e: Enemy, to_p: Vector2) -> void:
	match e.boss_id:
		"maestro":
			var f := e.hp / e.max_hp
			var ph := 0 if f > 0.66 else (1 if f > 0.33 else 2)
			if ph != e.bphase:
				e.bphase = ph
				banner = "PHASE %d" % (ph + 1)
				banner_time = 1.6
				flash(Color(1.0, 0.4, 0.4), 0.4)
				ring(e.pos, 420.0, Color(1.0, 0.4, 0.4), 0.6)
				do_shake(12.0)
				Conductor.play_sfx("big")
			if e.ctr % 4 == 0:
				var off := e.ctr * 0.31
				for i in 10:
					_eshot(e.pos, Vector2.from_angle(off + i * TAU / 10.0), 210.0, 7 + int(diff * 0.4))
			if e.ctr % 8 == 0:
				slams.append({"pos": player_pos, "r": 150.0, "t": 4.0 * Conductor.spb, "dmg": 14})
			if ph >= 1:
				if e.ctr % 8 == 4:
					e.tele = 2
					e.aim_dir = to_p
				elif e.tele > 0:
					e.tele -= 1
					if e.tele == 0:
						e.dash_dir = e.aim_dir
						e.dash_t = 0.6
			if ph >= 2:
				if e.ctr % 8 == 6:
					for i in 7:
						_eshot(e.pos, to_p.rotated((i - 3) * 0.2), 290.0, 8 + int(diff * 0.4))
				if e.ctr % 16 == 8:
					for i in 3:
						var mm := _make_enemy("grunt")
						mm.pos = e.pos + Vector2.from_angle(i * TAU / 3.0) * 70.0
						enemies.append(mm)
		"drum":
			if e.ctr % 4 == 0:
				var off := e.ctr * 0.37
				for i in 10:
					_eshot(e.pos, Vector2.from_angle(off + i * TAU / 10.0), 200.0, 6 + int(diff * 0.5))
			elif e.ctr % 8 == 6:
				for i in 5:
					_eshot(e.pos, to_p.rotated((i - 2) * 0.22), 280.0, 7 + int(diff * 0.5))
		"metronome":
			if e.ctr % 8 == 4:
				e.tele = 2
				e.aim_dir = to_p
			elif e.tele > 0:
				e.tele -= 1
				if e.tele == 0:
					e.dash_dir = e.aim_dir
					e.dash_t = 0.7
			if e.ctr % 8 == 0:
				slams.append({"pos": player_pos, "r": 130.0, "t": 4.0 * Conductor.spb, "dmg": 12})
		_:
			if e.ctr % 8 == 0:
				slams.append({"pos": player_pos, "r": 170.0, "t": 4.0 * Conductor.spb, "dmg": 14})
				if e.ctr % 16 == 0:
					for i in 4:
						var m := _make_enemy("grunt")
						m.pos = e.pos + Vector2.from_angle(i * TAU / 4.0) * 60.0
						enemies.append(m)

func _fire_bolt(target: Vector2, dmg: float, spread: float) -> Bolt:
	var b := Bolt.new()
	b.pos = player_pos
	b.vel = (target - player_pos).normalized().rotated(spread) * 640.0
	b.dmg = dmg
	bolts.append(b)
	return b

func update(delta: float) -> void:
	for f in fxs:
		f.life -= delta
	fxs = fxs.filter(func(f: Fx) -> bool: return f.life > 0.0)
	for q in parts:
		q.life -= delta
		q.pos += q.vel * delta
		q.vel.y += q.grav * delta
		q.vel *= 0.98
	parts = parts.filter(func(q: Part) -> bool: return q.life > 0.0)
	banner_time = maxf(0.0, banner_time - delta)
	cast_t = maxf(0.0, cast_t - delta)
	count_t = maxf(0.0, count_t - delta)
	last_off_t = maxf(0.0, last_off_t - delta)
	for i in slot_anim.size():
		slot_anim[i] = maxf(0.0, slot_anim[i] - delta)
	shake = maxf(0.0, shake - delta * 28.0)
	beat_pulse = maxf(0.0, beat_pulse - delta * 4.0)
	flash_a = maxf(0.0, flash_a - delta * 2.5)
	for k in _lit.keys():
		_lit[k] -= delta * 2.0
		if _lit[k] <= 0.0:
			_lit.erase(k)
	var low := run.hp < run.max_hp * 0.25 and not done
	if low != _muffled:
		_muffled = low
		Conductor.set_muffle(low)
	if hitstop > 0.0:
		hitstop -= delta
		return
	elapsed += delta
	if done:
		return
	if ending:
		end_timer -= delta
		if end_timer <= 0.0:
			done = true
			finished.emit(end_won)
		return
	_update_play(delta)

func move_dir() -> Vector2:
	if touch_dir.length() > 0.0:
		return touch_dir
	var jv := Vector2(Input.get_joy_axis(0, JOY_AXIS_LEFT_X), Input.get_joy_axis(0, JOY_AXIS_LEFT_Y))
	if jv.length() < 0.25:
		jv = Vector2.ZERO
	jv += Vector2(
		float(Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_RIGHT)) - float(Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_LEFT)),
		float(Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_DOWN)) - float(Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_UP)))
	if jv.length() > 0.0:
		return jv.limit_length(1.0)
	return Vector2(
		float(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)),
		float(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)) - float(Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)))

var bot_dir := Callable()

func _update_play(delta: float) -> void:
	var dir := move_dir()
	if bot_dir.is_valid():
		dir = bot_dir.call()
	var spd := 270.0 * float(char_def["speed"]) * (1.15 if run.has_relic("boots") else 1.0)
	var before := player_pos
	player_vel = dir.normalized() * spd if dir.length() > 0.05 else Vector2.ZERO
	if absf(dir.x) > 0.2:
		facing = signf(dir.x)
	else:
		var nn := nearest_enemies(1)
		if not nn.is_empty():
			facing = signf((nn[0] as Enemy).pos.x - player_pos.x) if absf((nn[0] as Enemy).pos.x - player_pos.x) > 6.0 else facing
	player_pos += dir.normalized() * spd * delta
	player_pos = player_pos.clamp(Vector2(24, 24), Vector2(W - 24, ARENA_BOTTOM))
	moved_dist += before.distance_to(player_pos)
	invuln = maxf(0.0, invuln - delta)
	blade_angle += delta * 4.5
	if not started:
		return
	if tutorial:
		energy = max_energy
		_tut_update(delta)
	_trail_t -= delta
	if dir.length() > 0.1 and _trail_t <= 0.0:
		_trail_t = 0.05
		burst(player_pos + Vector2(0, 14), Color(0.7, 0.6, 1.0, 0.7), 1, 15.0, 0.35, 5.0)

	var slow := 0.35 if slow_beats > 0 else 1.0
	for e in enemies:
		e.flash = maxf(0.0, e.flash - delta)
		e.blade_cd = maxf(0.0, e.blade_cd - delta)
		e.thorn_cd = maxf(0.0, e.thorn_cd - delta)
		if e.spawn_t > 0.0:
			e.spawn_t -= delta
			continue
		var to_p := (player_pos - e.pos).normalized()
		var mv := to_p
		var spd_e := e.speed
		var moving := e.stun <= 0
		match e.kind:
			"fast":
				mv = (to_p + to_p.orthogonal() * sin(elapsed * 6.0 + e.phase) * 0.8).normalized()
			"shooter":
				mv = _keep_distance(e, to_p, 330.0, 230.0)
			"charger":
				if e.tele > 0:
					moving = false
				elif e.dash_t > 0.0:
					e.dash_t -= delta
					mv = e.dash_dir
					spd_e = 560.0
			"boss":
				if e.boss_id == "drum":
					mv = _keep_distance(e, to_p, 380.0, 260.0)
				elif e.boss_id == "metronome" or e.boss_id == "maestro":
					if e.tele > 0:
						moving = false
					elif e.dash_t > 0.0:
						e.dash_t -= delta
						mv = e.dash_dir
						spd_e = 620.0
		if moving:
			e.pos += mv * spd_e * slow * delta
			e.pos = e.pos.clamp(Vector2(-70, -70), Vector2(W + 70, ARENA_BOTTOM + 70))
		if e.pos.distance_to(player_pos) < e.radius + 14.0:
			if thorns > 0 and e.thorn_cd <= 0.0:
				hit(e, float(thorns))
				e.thorn_cd = 0.4
			if e.kind == "bomber":
				_bomber_boom(e)
			elif invuln <= 0.0:
				damage_player(e.dmg)

	for sh in eshots:
		sh.pos += sh.vel * delta
		sh.life -= delta
		if sh.pos.x < -60.0 or sh.pos.x > W + 60.0 or sh.pos.y < -60.0 or sh.pos.y > H:
			sh.life = 0.0
		elif invuln <= 0.0 and sh.pos.distance_to(player_pos) < 20.0:
			damage_player(sh.dmg)
			sh.life = 0.0
	eshots = eshots.filter(func(x: EShot) -> bool: return x.life > 0.0)

	for b in bolts:
		b.pos += b.vel * delta
		b.life -= delta
		if randf() < 0.7:
			burst(b.pos, b.color, 1, 20.0, 0.25, 3.0)
		for e in enemies:
			if e.hp > 0.0 and e.spawn_t <= 0.0 and b.pos.distance_to(e.pos) < e.radius + 5.0 and not b.hit_ids.has(e.get_instance_id()):
				hit(e, b.dmg)
				if b.pierce > 0:
					b.pierce -= 1
					b.hit_ids.append(e.get_instance_id())
				else:
					b.life = 0.0
					break
	bolts = bolts.filter(func(b: Bolt) -> bool: return b.life > 0.0)

	if blade_beats > 0:
		for i in blade_n:
			var bp := player_pos + Vector2.from_angle(blade_angle + i * TAU / blade_n) * 85.0
			burst(bp, Color(0.5, 0.9, 1.0), 1, 10.0, 0.25, 3.0)
			for sh in eshots:
				if bp.distance_to(sh.pos) < 24.0:
					sh.life = 0.0
					burst(sh.pos, Color(1.0, 0.5, 0.6), 5, 120.0, 0.3, 3.0)
			for e in enemies:
				if e.blade_cd <= 0.0 and e.spawn_t <= 0.0 and bp.distance_to(e.pos) < e.radius + 14.0:
					hit(e, 7.0 * blade_power * dmg_mult())
					e.blade_cd = 0.3

	# slam telegraphs
	for s in slams:
		s["t"] -= delta
		if s["t"] <= 0.0:
			var sp: Vector2 = s["pos"]
			ring(sp, s["r"], Color(1, 0.4, 0.3), 0.4)
			burst(sp, Color(1, 0.5, 0.3), 30, 260.0, 0.5, 5.0)
			do_shake(9.0)
			Conductor.play_sfx("boom")
			if invuln <= 0.0 and player_pos.distance_to(sp) < float(s["r"]):
				damage_player(int(s["dmg"]))
	slams = slams.filter(func(s: Dictionary) -> bool: return s["t"] > 0.0)

	var boss_alive := false
	var elite_alive := false
	var alive: Array[Enemy] = []
	for e in enemies:
		if e.hp > 0.0:
			alive.append(e)
			if e.kind == "boss":
				boss_alive = true
			elif e.kind == "elite":
				elite_alive = true
		else:
			_on_kill(e)
	alive.append_array(pending_spawns)
	pending_spawns.clear()
	enemies = alive

	if tutorial:
		return
	if kind != "boss" and spawning:
		time_left -= delta
		if time_left <= 0.0:
			spawning = false
	if kind == "boss":
		if not boss_alive and elapsed > 1.0:
			_finish(true)
	elif not spawning and not elite_alive:
		_finish(true)

func _on_kill(e: Enemy) -> void:
	kills += 1
	run.kills += 1
	if fxs.size() < 150:
		var sf := Fx.new()
		sf.kind = "sprite"
		sf.pos = e.pos
		sf.tex = e.tex
		sf.radius = e.radius * 3.2
		sf.to = Vector2(-1.0 if player_pos.x < e.pos.x else 1.0, 0.0)
		sf.life = 0.45
		sf.max_life = 0.45
		fxs.append(sf)
	if e.kind == "splitter":
		for i in 2:
			var sp := _make_enemy("grunt")
			sp.max_hp = maxf(6.0, e.max_hp * 0.3)
			sp.hp = sp.max_hp
			sp.radius = 9.0
			sp.speed *= 1.2
			sp.pos = e.pos + Vector2.from_angle(randf() * TAU) * 14.0
			sp.spawn_t = 0.1
			pending_spawns.append(sp)
	burst(e.pos, e.color, 14 if e.radius < 25.0 else 40, 220.0, 0.6, 5.0, 120.0)
	ring(e.pos, e.radius * 2.2, e.color, 0.25)
	if e.kind == "boss":
		Settings.bosses[e.boss_id] = true
		if Settings.bosses.size() >= 3:
			Settings.unlock("boss3")
		if not took_damage:
			Settings.unlock("flawless")
		hitstop = 0.3
		do_shake(22.0)
		flash(Color(1, 1, 1), 0.7)
		burst(e.pos, Color(1, 0.8, 0.5), 120, 500.0, 1.0, 7.0, 80.0)
		ring(e.pos, 400.0, Color(1, 0.7, 0.9), 0.8)
		Conductor.play_sfx("big")
	elif e.kind == "elite":
		hitstop = 0.12
		do_shake(10.0)
	if run.has_relic("fang"):
		fang_count += 1
		if fang_count >= 8:
			fang_count = 0
			_heal(1)
	if aura_k > 0:
		aura_count += 1
		if aura_count >= aura_k:
			aura_count = 0
			_heal(1)

func _heal(n: int) -> void:
	run.heal(n)
	float_text(player_pos + Vector2(0, -30), "+%d" % n, Color(0.4, 1.0, 0.5))

func _finish(won: bool) -> void:
	if ending:
		return
	ending = true
	end_won = won
	end_timer = 1.3 if (won and kind == "boss") else 0.7
	spawning = false
	bolts.clear()
	slams.clear()
	eshots.clear()
	delayed.clear()
	for e in enemies:
		burst(e.pos, e.color, 10, 200.0, 0.5, 4.0, 100.0)
	enemies.clear()
	if won:
		banner = "CLEAR!"
		banner_time = 1.5
		Conductor.play_sfx("win")

func damage_player(d: int) -> void:
	if tutorial:
		run.hp = run.max_hp
		invuln = 0.4
		do_shake(3.0)
		burst(player_pos, Color(1, 0.4, 0.4), 6, 160.0, 0.4, 4.0)
		return
	if aegis_ready:
		aegis_ready = false
		invuln = 0.7
		ring(player_pos, 56.0, Color(1.0, 1.0, 0.6), 0.5)
		float_text(player_pos + Vector2(0, -40), "イージス！", Color(1.0, 1.0, 0.6), 20)
		Conductor.play_sfx("big")
		return
	invuln = 0.55
	do_shake(8.0)
	hitstop = 0.06
	flash(Color(1, 0.2, 0.2), 0.35)
	var absorbed := mini(shield, d)
	shield -= absorbed
	var real := d - absorbed
	run.hp -= real
	if real > 0:
		took_damage = true
	run.dmg_taken += real
	burst(player_pos, Color(1, 0.3, 0.3), 16, 240.0, 0.5, 5.0)
	if absorbed > 0:
		ring(player_pos, 36.0, Color(0.5, 0.7, 1.0), 0.3)
	if real > 0:
		float_text(player_pos + Vector2(0, -30), "-%d" % real, Color(1, 0.35, 0.35), 24)
	Conductor.play_sfx("hit")
	if run.hp <= 0:
		run.hp = 0
		_finish(false)
		end_timer = 0.9
		banner = ""
		burst(player_pos, Color(0.6, 1.0, 1.0), 60, 400.0, 0.9, 6.0, 100.0)

func hit(e: Enemy, dmg: float) -> void:
	e.hp -= dmg
	e.flash = 0.1
	burst(e.pos, Color(1, 0.9, 0.6), 3, 160.0, 0.3, 3.0)
	float_text(e.pos + Vector2(0, -e.radius - 6.0), str(int(dmg)), Color(1, 0.95, 0.7), 14 if dmg < 20.0 else 20, 0.55)

# ---- potions ---------------------------------------------------------------

func use_potion(i: int) -> void:
	if ending or i < 0 or i >= run.potions.size():
		return
	var id: String = run.potions[i]
	run.potions.remove_at(i)
	Settings.unlock("potion")
	var col: Color = Potions.DB[id]["color"]
	float_text(player_pos + Vector2(0, -74), String(Potions.DB[id]["name"]), col, 18, 1.0)
	burst(player_pos, col, 22, 230.0, 0.6, 4.0)
	ring(player_pos, 80.0, col, 0.4)
	Conductor.play_sfx("open")
	match id:
		"heal":
			_heal(int(run.max_hp * 0.3))
		"energy":
			energy = mini(max_energy, energy + 3)
		"bomb":
			ring(player_pos, 600.0, col, 0.5)
			do_shake(10.0)
			Conductor.play_sfx("boom")
			for e in enemies:
				hit(e, 40.0)
		"freeze":
			slow_beats = maxi(slow_beats, 8)
			flash(col, 0.2)
		"shield":
			shield = mini(80, shield + 20)
		"fury":
			frenzy_beats = maxi(frenzy_beats, 10)
			_add_fever(3.0)

# ---- tutorial --------------------------------------------------------------

const TUT_STEPS := [
	{"text": "まずは移動してみよう。
キー: WASD / 矢印   スマホ: 画面をドラッグ", "goal": 250.0},
	{"text": "カードを使ってみよう。
[1]〜[5]キー / タップ。上のレーンで『丸が輪に重なる瞬間』が拍だ！", "goal": 3.0},
	{"text": "金色の PERFECT を2回出そう！
丸が輪に重なった瞬間に押す(判定は±0.07秒)。", "goal": 2.0},
	{"text": "続けて当てるとコンボ！ コンボ5を目指そう。
外すとコンボは0に戻る。ダメージもUPするよ。", "goal": 5.0},
	{"text": "エネルギー(左上の黄色い丸)は1秒に1回復。
左下『次のカード』で次に引くカードが分かる。", "goal": 8.0},
	{"text": "仕上げ！ 敵を10体倒そう。
(チュートリアル中は倒れません)", "goal": 10.0},
]

func tut_progress() -> float:
	if tut_step >= TUT_STEPS.size():
		return 1.0
	var g: float = TUT_STEPS[tut_step]["goal"]
	var v := 0.0
	match tut_step:
		0: v = moved_dist
		1: v = plays
		2: v = perfects
		3: v = combo
		4: v = tut_timer
		5: v = kills
	return clampf(v / g, 0.0, 1.0)

func _tut_update(delta: float) -> void:
	if tut_step >= TUT_STEPS.size() or ending:
		return
	if tut_step == 4:
		tut_timer += delta
	if tut_progress() >= 1.0:
		tut_step += 1
		Conductor.play_sfx("win")
		flash(Color(0.6, 1.0, 0.7), 0.2)
		if tut_step >= TUT_STEPS.size():
			banner = "チュートリアル完了！"
			banner_time = 2.2
			_finish(true)
		elif tut_step == 2:
			combo = 0

func _draw_tutorial(c: Control) -> void:
	if tut_step >= TUT_STEPS.size():
		return
	var cx := W / 2.0
	var r := Rect2(cx - 330.0, 104.0, 660.0, 92.0)
	ui.panel(c, r, Color(0.04, 0.1, 0.06, 0.92), Color(0.5, 1.0, 0.6, 0.9))
	ui.text(c, "STEP %d / %d" % [tut_step + 1, TUT_STEPS.size()], r.position + Vector2(14, 22), 14, Color(0.6, 1.0, 0.7))
	ui.dms(c, r.position + Vector2(14, 46), TUT_STEPS[tut_step]["text"], HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 28.0, 17, 2, Color(1, 1, 1))
	ui.bar(c, Rect2(r.position.x + 14, r.end.y - 14, r.size.x - 28, 6), tut_progress(), Color(0.5, 1.0, 0.6), Color(0.1, 0.2, 0.12))
	if tut_step >= 1 and tut_step <= 3:
		var a := 0.5 + 0.5 * sin(elapsed * 8.0)
		c.draw_arc(Vector2(cx, 46.0), 24.0 + 4.0 * a, 0.0, TAU, 32, Color(1, 0.9, 0.3, 0.9), 3.0)
		ui.text(c, "ここ！", Vector2(cx - 40.0, 90.0), 14, Color(1, 0.9, 0.4, 0.6 + 0.4 * a), HORIZONTAL_ALIGNMENT_CENTER, 80.0)

# ---- cards -----------------------------------------------------------------

func try_play(slot: int) -> void:
	if ending or not started:
		return
	var id := deck.hand[slot]
	if id == "":
		return
	var d: Dictionary = Cards.def(id)
	var cost: int = d["cost"]
	var free := fever_beats > 0
	if not free and run.has_relic("clover") and randf() < 0.15:
		free = true
		float_text(player_pos + Vector2(0, -100), "ラッキー！", Color(0.5, 1.0, 0.5), 14)
	if free:
		cost = 0
	if energy < cost:
		float_text(player_pos + Vector2(0, -44), "エネルギー不足", Color(0.7, 0.7, 0.75))
		Conductor.play_sfx("miss")
		return
	energy -= cost
	var so := Conductor.beat_offset()
	var a := absf(so)
	var grade := "MISS"
	var gm := 0.6
	var col := Color(0.8, 0.3, 0.3)
	if a <= perfect_window():
		grade = "PERFECT"
		gm = 1.5
		col = Color(1.0, 0.9, 0.3)
		combo += 1
		flash(Color(1.0, 0.9, 0.4), 0.18)
		_add_fever(1.0)
		ring(player_pos, 110.0, col, 0.4)
		burst(player_pos, col, 22, 280.0, 0.5, 5.0)
	elif a <= good_window():
		grade = "GOOD"
		gm = 1.0
		col = Color(0.5, 0.9, 1.0)
		combo += 1
		ring(player_pos, 80.0, col, 0.3)
		burst(player_pos, col, 10, 200.0, 0.4, 4.0)
		_add_fever(0.4)
	else:
		combo = 0
		fever_gauge *= 0.5
	if grade != "MISS" and run.char_id == "wizard" and combo > 0 and combo % 5 == 0:
		energy = mini(max_energy, energy + 1)
		float_text(player_pos + Vector2(0, -80), "アルカナ +1", Color(0.8, 0.6, 1.0), 16)
	var pitch := 1.0
	if grade == "PERFECT":
		var scale_st := [0, 2, 4, 7, 9]
		pitch = pow(2.0, float(scale_st[combo % 5] + 12 * mini(combo / 5, 1)) / 12.0)
	Conductor.play_sfx(grade.to_lower(), pitch)
	Conductor.play_sfx("card", randf_range(0.94, 1.08))
	plays += 1
	Settings.stats["best_combo"] = maxi(Settings.stats["best_combo"], combo)
	if combo >= 10:
		Settings.unlock("combo10")
	if combo >= 20:
		Settings.unlock("combo20")
	if grade == "PERFECT":
		Settings.stats["perfects"] += 1
		perfects += 1
	last_off = so
	last_off_t = 1.3
	last_off_col = col
	var tag := ""
	if grade == "GOOD":
		tag = " 早め" if so < 0.0 else " 遅め"
	elif grade == "MISS":
		tag = " 早すぎ" if so < 0.0 else " 遅すぎ"
	float_text(player_pos + Vector2(0, -52), grade + ("!" if grade == "PERFECT" else "") + tag, col, 26 if grade == "PERFECT" else 20, 0.8)
	var times := 2 if (echo_pending and Cards.base_id(id) != "echo") else 1
	if Cards.base_id(id) != "echo":
		echo_pending = false
	var m := gm * dmg_mult()
	var od := overdrive > 0 and Cards.base_id(id) != "overdrive"
	if od:
		m *= 1.5
		overdrive -= 1
	for i in times:
		_apply_card(id, m)
	if Cards.base_id(id) != "replay":
		last_card = id
	cast_name = String(d["name"]) + (" ×2" if times == 2 else "")
	cast_short = Cards.short(id)
	cast_col = d["color"]
	cast_grade = grade
	cast_t = 1.5
	deck.play(slot, d["exhaust"])
	slot_anim[slot] = 0.35

func _apply_card(id: String, m: float) -> void:
	var d: Dictionary = Cards.def(id)
	var p: Dictionary = d["p"]
	var col: Color = d["color"]
	match Cards.base_id(id):
		"pulse":
			var t := nearest_enemies(int(p["n"]))
			var n: int = p["n"]
			for i in n:
				var tgt := player_pos + Vector2(randf_range(-1.0, 1.0), -1.0)
				if not t.is_empty():
					tgt = (t[i % t.size()] as Enemy).pos
				_fire_bolt(tgt, float(p["dmg"]) * m, (i - (n - 1) / 2.0) * 0.08)
		"chain":
			var prev := player_pos
			for e in nearest_enemies(int(p["n"])):
				hit(e, float(p["dmg"]) * m)
				line_fx(prev, (e as Enemy).pos, Color(1.0, 0.95, 0.4), 0.2, "beam", 4.0)
				prev = (e as Enemy).pos
			Conductor.play_sfx("tick")
		"nova":
			ring(player_pos, 190.0, col, 0.4)
			ring(player_pos, 120.0, Color(1, 1, 1, 0.7), 0.3)
			burst(player_pos, col, 50, 420.0, 0.6, 5.0)
			do_shake(9.0)
			Conductor.play_sfx("boom")
			for e in enemies:
				if e.pos.distance_to(player_pos) < 190.0 + e.radius:
					hit(e, float(p["dmg"]) * m)
					e.pos += (e.pos - player_pos).normalized() * 80.0
		"blades":
			blade_beats = maxi(blade_beats, int(p["beats"]))
			blade_n = int(p["n"])
			blade_power = m
		"bass":
			ring(player_pos, 760.0, col, 0.6)
			ring(player_pos, 400.0, Color(1, 1, 1, 0.6), 0.45)
			burst(player_pos, col, 80, 600.0, 0.8, 6.0)
			do_shake(16.0)
			hitstop = 0.1
			flash(col, 0.5)
			Conductor.play_sfx("big")
			for e in enemies:
				hit(e, float(p["dmg"]) * m)
		"leech":
			ring(player_pos, 150.0, col, 0.4)
			burst(player_pos, col, 30, 300.0, 0.5, 4.0)
			var healed := 0
			for e in enemies:
				if e.pos.distance_to(player_pos) < 150.0 + e.radius:
					hit(e, float(p["dmg"]) * m)
					if healed < int(p["max"]):
						healed += 1
			if healed > 0:
				_heal(healed)
		"heavy":
			var t := nearest_enemies(1)
			var dir := Vector2.UP
			if not t.is_empty():
				dir = ((t[0] as Enemy).pos - player_pos).normalized()
			var end := player_pos + dir * 900.0
			line_fx(player_pos, end, col, 0.35, "beam", 22.0)
			do_shake(10.0)
			Conductor.play_sfx("big")
			for e in enemies:
				var v := e.pos - player_pos
				var proj := v.dot(dir)
				if proj > 0.0 and absf(v.cross(dir)) < e.radius + 22.0:
					hit(e, float(p["dmg"]) * m)
		"guard":
			var n := int(float(p["n"]) * m * (1.25 if run.char_id == "knight" else 1.0))
			shield = mini(60, shield + n)
			ring(player_pos, 40.0, Color(0.5, 0.7, 1.0), 0.35)
			float_text(player_pos + Vector2(0, -34), "+%d" % n, Color(0.5, 0.7, 1.0))
		"mend":
			_heal(int(float(p["n"]) * m))
			burst(player_pos, Color(0.4, 1.0, 0.5), 20, 160.0, 0.6, 4.0, -80.0)
		"surge":
			energy = mini(max_energy, energy + int(p["n"]))
			burst(player_pos, Color(1, 0.9, 0.4), 16, 200.0, 0.5, 4.0)
		"frenzy":
			frenzy_beats = maxi(frenzy_beats, int(p["beats"]))
			flash(Color(1, 0.6, 0.2), 0.2)
		"freeze":
			slow_beats = maxi(slow_beats, int(p["beats"]))
			ring(player_pos, 500.0, Color(0.6, 0.9, 1.0), 0.6)
			flash(Color(0.5, 0.8, 1.0), 0.2)
		"echo":
			echo_pending = true
			float_text(player_pos + Vector2(0, -78), "ECHO", Color(0.85, 0.7, 1.0), 16)
		"resonance":
			res_bonus += int(p["n"])
		"fortress":
			fort += int(p["n"])
		"aura":
			aura_k = int(p["k"]) if aura_k == 0 else mini(aura_k, int(p["k"]))
		"pierce":
			var t := nearest_enemies(1)
			var tgt := player_pos + Vector2.UP
			if not t.is_empty():
				tgt = (t[0] as Enemy).pos
			var pb := _fire_bolt(tgt, float(p["dmg"]) * m, 0.0)
			pb.pierce = 6
			pb.life = 1.3
			pb.color = col
		"meteor":
			delayed.append({"beats": 2, "pos": _cluster_pos(), "r": 120.0, "dmg": float(p["dmg"]) * m})
		"drum":
			var n: int = p["n"]
			for i in n:
				var db := Bolt.new()
				db.pos = player_pos
				db.vel = Vector2.from_angle(i * TAU / n + elapsed) * 560.0
				db.dmg = float(p["dmg"]) * m
				db.life = 0.9
				db.color = col
				bolts.append(db)
			ring(player_pos, 90.0, col, 0.3)
		"sonic":
			var t := nearest_enemies(1)
			var dir := Vector2.UP
			if not t.is_empty():
				dir = ((t[0] as Enemy).pos - player_pos).normalized()
			ring(player_pos + dir * 70.0, 130.0, col, 0.3)
			line_fx(player_pos, player_pos + dir * 260.0, col, 0.3, "beam", 40.0)
			do_shake(6.0)
			Conductor.play_sfx("boom")
			for e in enemies:
				var v := e.pos - player_pos
				if v.length() < 260.0 + e.radius and absf(v.angle_to(dir)) < 0.9:
					hit(e, float(p["dmg"]) * m)
					e.pos += v.normalized() * 110.0
					e.stun = 2
		"replay":
			if last_card != "":
				_apply_card(last_card, m)
		"phase":
			var md := move_dir()
			if bot_dir.is_valid():
				md = bot_dir.call()
			if md.length() < 0.1:
				var t := nearest_enemies(1)
				md = (player_pos - (t[0] as Enemy).pos) if not t.is_empty() else Vector2.UP
			burst(player_pos, col, 18, 200.0, 0.4, 4.0)
			player_pos = (player_pos + md.normalized() * 150.0).clamp(Vector2(24, 24), Vector2(W - 24, ARENA_BOTTOM))
			invuln = maxf(invuln, 1.0)
			burst(player_pos, col, 18, 200.0, 0.4, 4.0)
		"pguard":
			var n := int(float(p["k"]) * maxf(1.0, minf(combo, 20.0)))
			shield = mini(80, shield + n)
			float_text(player_pos + Vector2(0, -34), "+%d" % n, Color(0.5, 0.7, 1.0))
		"overdrive":
			overdrive = int(p["n"])
			flash(col, 0.15)
		"feverboost":
			_add_fever(float(p["n"]))
		"heartbeat":
			heart_k = int(p["k"]) if heart_k == 0 else mini(heart_k, int(p["k"]))
		"thorns":
			thorns += int(p["n"])

# ---- drawing: world --------------------------------------------------------

func draw_world(c: Node2D) -> void:
	var pulse := beat_pulse
	var off := Vector2.ZERO
	if shake > 0.0:
		off = Vector2(randf_range(-shake, shake), randf_range(-shake, shake)) * 0.6
	var z := 1.0 + 0.012 * pulse
	var base := Transform2D(0.0, Vector2(z, z), 0.0, Vector2(W, ARENA_BOTTOM) / 2.0 * (1.0 - z) + off)
	cur_base = base
	var th := theme()
	var fcol: Color = th["floor"]
	var lcol: Color = th["line"]
	c.draw_set_transform_matrix(base)
	var floor_tex := tex(0)
	for x in 20:
		for y in 12:
			var lit: float = _lit.get(Vector2i(x, y), 0.0)
			var v := 0.40 + 0.06 * pulse + lit * 0.45
			c.draw_texture_rect(floor_tex, Rect2(x * 64, y * 64, 64, 64), false, Color(v * fcol.r, v * fcol.g, v * fcol.b))
	for s in _stars:
		var a: float = 0.3 + 0.4 * sin(elapsed * 2.0 * s[2] + s[1])
		c.draw_rect(Rect2(s[0], Vector2(2, 2)), Color(1, 1, 1, a * 0.5))
	c.draw_rect(Rect2(0, ARENA_BOTTOM + 14, W, 3), Color(lcol, 0.25 + 0.3 * pulse))

	# telegraphs
	for s in slams:
		var k: float = 1.0 - float(s["t"]) / (4.0 * Conductor.spb)
		var sp: Vector2 = s["pos"]
		c.draw_circle(sp, s["r"], Color(1, 0.2, 0.2, 0.08 + 0.15 * k))
		c.draw_arc(sp, s["r"], 0.0, TAU, 48, Color(1, 0.4, 0.3, 0.5 + 0.5 * k), 3.0)
		c.draw_arc(sp, s["r"] * k, 0.0, TAU, 48, Color(1, 0.8, 0.5, 0.8), 2.0)
	# telegraphs: charge lines + delayed impacts
	for e in enemies:
		if e.tele > 0:
			var tl := 0.5 + 0.5 * sin(elapsed * 14.0)
			if e.kind == "shooter":
				c.draw_line(e.pos, e.pos + e.aim_dir * 520.0, Color(1.0, 0.4, 0.5, 0.18 + 0.2 * tl), 2.0)
			else:
				c.draw_line(e.pos, e.pos + e.aim_dir * 900.0, Color(1.0, 0.3, 0.3, 0.25 + 0.3 * tl), e.radius * 1.6)
	for dl in delayed:
		var dp: Vector2 = dl["pos"]
		var dk: float = float(dl["beats"]) / 2.0
		c.draw_circle(dp, dl["r"], Color(1.0, 0.45, 0.2, 0.08 + 0.12 * (1.0 - dk)))
		c.draw_arc(dp, dl["r"], 0.0, TAU, 40, Color(1.0, 0.6, 0.3, 0.9), 3.0)
		c.draw_arc(dp, dl["r"] * dk, 0.0, TAU, 40, Color(1.0, 0.9, 0.5, 0.8), 2.0)
	# enemies
	for e in enemies:
		var sc := 1.0 - maxf(e.spawn_t, 0.0) / 0.35
		var squash := 1.0 + 0.08 * sin(elapsed * 10.0 + e.phase) + 0.1 * pulse
		var sz := e.radius * 3.2 * sc
		var col := Color(3, 3, 3) if e.flash > 0.0 else (Color(0.6, 0.8, 1.3) if slow_beats > 0 else Color.WHITE)
		var flip := -1.0 if player_pos.x < e.pos.x else 1.0
		c.draw_circle(e.pos + Vector2(0, e.radius * 0.9), e.radius * 0.9 * sc, Color(0, 0, 0, 0.35))
		var w := sz * flip * (2.0 - squash)
		c.draw_texture_rect(e.tex, Rect2(e.pos.x - absf(w) / 2.0, e.pos.y - sz * squash / 2.0, w, sz * squash), false, col)
		if e.kind == "boss" or e.kind == "elite":
			c.draw_arc(e.pos, e.radius + 5.0, 0.0, TAU, 48, Color(e.color, 0.8), 3.0)
		if e.spawn_t > 0.0:
			c.draw_arc(e.pos, 22.0 * (1.0 + e.spawn_t * 3.0), 0.0, TAU, 20, Color(1, 0.4, 0.4, 0.6), 2.0)
	if blade_beats > 0:
		for i in blade_n:
			var a := blade_angle + i * TAU / blade_n
			var bp := player_pos + Vector2.from_angle(a) * 85.0
			c.draw_set_transform_matrix(base * Transform2D(a + PI / 2.0, Vector2.ONE, 0.0, bp))
			c.draw_texture_rect(tex(TILE_SWORD), Rect2(-22, -22, 44, 44), false)
		c.draw_set_transform_matrix(base)
	# player
	var blink := invuln > 0.0 and int(invuln * 20.0) % 2 == 0
	var ps := 52.0 + 8.0 * pulse
	var bob := 1.0 + 0.05 * sin(elapsed * (14.0 if player_vel.length() > 1.0 else 5.0))
	var tilt := clampf(player_vel.x / 270.0, -1.0, 1.0) * 0.14
	c.draw_circle(player_pos + Vector2(0, 24), 18.0, Color(0, 0, 0, 0.4))
	c.draw_circle(player_pos, 34.0 + 6.0 * pulse, Color(char_def["color"] as Color, 0.12 + 0.1 * pulse))
	c.draw_set_transform_matrix(base * Transform2D(tilt, Vector2(facing, 1.0), 0.0, player_pos + Vector2(0, 26)))
	c.draw_texture_rect(tex(int(char_def["tile"])), Rect2(-ps / 2.0, -ps * bob, ps, ps * bob), false, Color.WHITE if not blink else Color(1, 1, 1, 0.35))
	c.draw_set_transform_matrix(base)
	if shield > 0:
		c.draw_arc(player_pos, 26.0, 0.0, TAU, 32, Color(0.5, 0.7, 1.0, 0.9), 3.0)
	if frenzy_beats > 0:
		c.draw_arc(player_pos, 32.0 + 3.0 * pulse, 0.0, TAU, 32, Color(1.0, 0.6, 0.2), 2.0)
	if fever_beats > 0:
		c.draw_arc(player_pos, 38.0 + 4.0 * pulse, 0.0, TAU, 32, Color.from_hsv(fmod(elapsed * 1.5, 1.0), 0.6, 1.0), 4.0)
		if randf() < 0.6:
			burst(player_pos, Color.from_hsv(randf(), 0.6, 1.0), 1, 90.0, 0.5, 4.0)
	if echo_pending:
		c.draw_arc(player_pos, 38.0, 0.0, TAU, 6, Color(0.85, 0.7, 1.0), 2.0)
	_draw_mini_status(c)
	_draw_cast(c)
	# fx: sprites (death) and text stay in the normal pass; glows are in draw_glow()
	for f in fxs:
		var k := f.life / f.max_life
		match f.kind:
			"sprite":
				var fl: float = f.to.x
				var sz := f.radius * (0.35 + 0.65 * k)
				c.draw_set_transform_matrix(base * Transform2D((1.0 - k) * 3.0 * fl, Vector2(fl, 1.0), 0.0, f.pos))
				c.draw_texture_rect(f.tex, Rect2(-sz / 2.0, -sz / 2.0, sz, sz), false, Color(1.0 + k * 2.0, 1.0 + k * 2.0, 1.0 + k * 2.0, k))
				c.draw_set_transform_matrix(base)
			"text":
				var rise := 34.0 * (1.0 - k)
				var pop := 1.0 + 0.5 * maxf(0.0, k - 0.8) * 5.0
				ui.ds(c, f.pos + Vector2(-60, -rise + 1), f.text, HORIZONTAL_ALIGNMENT_CENTER, 120.0, int(f.size * pop), Color(0, 0, 0, k))
				ui.ds(c, f.pos + Vector2(-60, -rise), f.text, HORIZONTAL_ALIGNMENT_CENTER, 120.0, int(f.size * pop), Color(f.color, minf(1.0, k * 2.0)))
	c.draw_set_transform_matrix(Transform2D.IDENTITY)
	# screen overlays
	var hp_frac := float(run.hp) / float(run.max_hp)
	if hp_frac < 0.35:
		_vignette(c, Color(0.9, 0.05, 0.1), (0.35 - hp_frac) * 1.4 + 0.1 * sin(elapsed * 6.0))
	_vignette(c, th["tint"], 0.12 * pulse)
	if fever_beats > 0:
		_vignette(c, Color(1.0, 0.8, 0.2), 0.2 + 0.12 * pulse)
	if flash_a > 0.0:
		c.draw_rect(Rect2(0, 0, W, H), Color(flash_col, flash_a * 0.5))

## Additive-blended layer: projectiles, particles, rings, beams. Drawn by main's glow node.
func draw_glow(c: Node2D) -> void:
	c.draw_set_transform_matrix(cur_base)
	for bl in bolts:
		c.draw_circle(bl.pos, 13.0, Color(bl.color, 0.22))
		c.draw_circle(bl.pos, 7.0, Color(bl.color, 0.55))
		c.draw_circle(bl.pos, 3.5, Color(1, 1, 1, 0.9))
	for sh in eshots:
		c.draw_circle(sh.pos, 16.0, Color(1.0, 0.25, 0.45, 0.22))
		c.draw_circle(sh.pos, 8.0, Color(1.0, 0.45, 0.6, 0.6))
		c.draw_circle(sh.pos, 4.0, Color(1, 0.9, 0.95, 0.95))
	for q in parts:
		var k := q.life / q.max_life
		var sz := Vector2(q.size, q.size) * k
		c.draw_rect(Rect2(q.pos - sz * 0.5, sz), Color(q.color, k * 0.9))
	for f in fxs:
		var k := f.life / f.max_life
		match f.kind:
			"ring":
				var r := f.radius * (1.0 - k * k * 0.9)
				c.draw_arc(f.pos, r, 0.0, TAU, 48, Color(f.color, k * 0.35), 9.0)
				c.draw_arc(f.pos, r, 0.0, TAU, 48, Color(f.color, k), 3.0)
			"line":
				c.draw_line(f.pos, f.to, Color(f.color, k), 3.0)
			"beam":
				c.draw_line(f.pos, f.to, Color(f.color, k * 0.35), f.radius * 2.6 * k)
				c.draw_line(f.pos, f.to, Color(f.color, k * 0.6), f.radius * 1.4 * k)
				c.draw_line(f.pos, f.to, Color(1, 1, 1, k), maxf(1.0, f.radius * k * 0.5))
	c.draw_set_transform_matrix(Transform2D.IDENTITY)

## Tiny HP / shield / energy readout hugging the player so the HUD corner needn't be checked.
func _draw_mini_status(c: Node2D) -> void:
	var bw := 48.0
	var by := player_pos.y + 32.0
	if by > ARENA_BOTTOM - 4.0:
		by = player_pos.y - 44.0
	var bx := player_pos.x - bw / 2.0
	c.draw_rect(Rect2(bx - 1, by - 1, bw + 2, 7), Color(0, 0, 0, 0.55))
	var frac := clampf(float(run.hp) / run.max_hp, 0.0, 1.0)
	var hcol := Color(0.4, 0.9, 0.45) if frac > 0.5 else (Color(0.95, 0.75, 0.3) if frac > 0.25 else Color(0.95, 0.3, 0.3))
	c.draw_rect(Rect2(bx, by, bw * frac, 5), Color(hcol, 0.9))
	if shield > 0:
		c.draw_rect(Rect2(bx, by + 6, bw * minf(1.0, shield / 40.0), 3), Color(0.5, 0.7, 1.0, 0.9))
	var pw := 7.0
	var total := max_energy * (pw + 2.0) - 2.0
	for i in max_energy:
		var on := i < energy
		c.draw_rect(Rect2(player_pos.x - total / 2.0 + i * (pw + 2.0), by + 10, pw, 5), Color(1.0, 0.85, 0.3, 0.95) if on else Color(0.3, 0.27, 0.2, 0.7))

## Card name + short effect text above the player after playing a card.
func _draw_cast(c: Node2D) -> void:
	if cast_t <= 0.0:
		return
	var k := cast_t / 1.5
	var a := minf(1.0, k * 2.5)
	var px := clampf(player_pos.x, 150.0, W - 150.0)
	var py := maxf(130.0, player_pos.y - 100.0 - 12.0 * (1.0 - k))
	c.draw_rect(Rect2(px - 130, py - 24, 260, 50), Color(0, 0, 0, 0.5 * a))
	c.draw_rect(Rect2(px - 130, py - 24, 4, 50), Color(cast_col, a))
	ui.ds(c, Vector2(px - 120, py - 3), cast_name, HORIZONTAL_ALIGNMENT_LEFT, 170.0, 19, Color(cast_col.lerp(Color.WHITE, 0.35), a))
	var gcol := Color(1.0, 0.9, 0.3) if cast_grade == "PERFECT" else (Color(0.5, 0.9, 1.0) if cast_grade == "GOOD" else Color(0.9, 0.4, 0.4))
	ui.ds(c, Vector2(px + 40, py - 3), cast_grade, HORIZONTAL_ALIGNMENT_RIGHT, 84.0, 13, Color(gcol, a))
	ui.ds(c, Vector2(px - 120, py + 17), cast_short, HORIZONTAL_ALIGNMENT_LEFT, 244.0, 13, Color(0.92, 0.92, 1.0, a))

func _vignette(c: Node2D, col: Color, a: float) -> void:
	if a <= 0.01:
		return
	var t := 130.0
	var clear := Color(col, 0.0)
	var solid := Color(col, clampf(a, 0.0, 0.8))
	c.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(W, 0), Vector2(W, t), Vector2(0, t)]), PackedColorArray([solid, solid, clear, clear]))
	c.draw_polygon(PackedVector2Array([Vector2(0, H - t), Vector2(W, H - t), Vector2(W, H), Vector2(0, H)]), PackedColorArray([clear, clear, solid, solid]))
	c.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(t, 0), Vector2(t, H), Vector2(0, H)]), PackedColorArray([solid, clear, clear, solid]))
	c.draw_polygon(PackedVector2Array([Vector2(W - t, 0), Vector2(W, 0), Vector2(W, H), Vector2(W - t, H)]), PackedColorArray([clear, solid, solid, clear]))

# ---- drawing: HUD ----------------------------------------------------------

func draw_hud(c: Control) -> void:
	var f := ui.font
	# portrait + bars
	ui.panel(c, Rect2(10, 10, 300, 112), Color(0.05, 0.04, 0.1, 0.7), Color(0.5, 0.45, 0.8, 0.5), 1.0)
	c.draw_texture_rect(tex(int(char_def["tile"])), Rect2(16, 16, 40, 40), false)
	ui.bar(c, Rect2(62, 18, 236, 18), float(run.hp) / run.max_hp, Color(0.85, 0.25, 0.3))
	ui.text(c, "HP %d/%d" % [run.hp, run.max_hp], Vector2(68, 33), 14, Color.WHITE)
	if shield > 0:
		ui.bar(c, Rect2(62, 40, 236, 8), minf(1.0, shield / 40.0), Color(0.45, 0.65, 1.0), Color(0.1, 0.1, 0.2))
		ui.text(c, Loc.t("シールド %d") % shield, Vector2(66, 62), 12, Color(0.6, 0.75, 1.0))
	for i in max_energy:
		var on := i < energy
		var cx := 72.0 + i * 26.0
		c.draw_circle(Vector2(cx, 80), 10.0 + (2.0 * beat_pulse if on else 0.0), Color(1.0, 0.85, 0.3) if on else Color(0.25, 0.22, 0.15))
	var label := ""
	match kind:
		"boss": label = "BOSS戦"
		"elite": label = "エリート"
		"tutorial": label = "チュートリアル"
		"endless": label = Loc.t("エンドレス ウェーブ%d") % (run.wave + 1)
		_: label = "バトル"
	var tl := "" if (kind == "boss" or tutorial or not spawning) else Loc.t("  残り%.0f") % maxf(time_left, 0.0)
	ui.text(c, Loc.t("%s%s   撃破 %d   %dG") % [label, tl, kills, run.gold], Vector2(16, 112), 14, Color(0.9, 0.9, 1.0))
	# relics
	for i in run.relics.size():
		ui.relic_icon(c, run.relics[i], Rect2(10 + i * 30, 128, 26, 26), "relic:%d" % i)
	# combo / buffs
	var rx := W - 310.0
	if combo > 1:
		ui.text(c, Loc.t("コンボ x%d") % combo, Vector2(rx, 40), 28, Color(1.0, 0.9, 0.3) if combo < 10 else Color(1.0, 0.6, 0.2), HORIZONTAL_ALIGNMENT_RIGHT, 210.0)
		var per := 3.0 if run.has_relic("amp") else 2.0
		ui.text(c, Loc.t("ダメージ +%d%%") % int(minf(combo, 20.0) * per), Vector2(rx, 62), 14, Color(1.0, 0.9, 0.6), HORIZONTAL_ALIGNMENT_RIGHT, 210.0)
	var by := 86.0
	var buffs: Array = []
	if frenzy_beats > 0:
		buffs.append([Loc.t("フレンジー %d") % frenzy_beats, Color(1.0, 0.6, 0.2)])
	if slow_beats > 0:
		buffs.append([Loc.t("減速 %d") % slow_beats, Color(0.6, 0.9, 1.0)])
	if blade_beats > 0:
		buffs.append([Loc.t("ブレード %d") % blade_beats, Color(0.5, 0.9, 1.0)])
	if res_bonus > 0:
		buffs.append([Loc.t("レゾナンス +%d") % res_bonus, Color(1.0, 0.4, 0.5)])
	if fort > 0:
		buffs.append([Loc.t("フォートレス +%d") % fort, Color(0.5, 0.7, 1.0)])
	if aura_k > 0:
		buffs.append([Loc.t("オーラ %d/%d") % [aura_count, aura_k], Color(0.8, 0.3, 0.6)])
	if echo_pending:
		buffs.append(["エコー待機", Color(0.85, 0.7, 1.0)])
	if fever_beats > 0:
		buffs.append(["FEVER %d" % fever_beats, Color.from_hsv(fmod(elapsed * 1.5, 1.0), 0.5, 1.0)])
	if overdrive > 0:
		buffs.append([Loc.t("オーバードライブ x%d") % overdrive, Color(1.0, 0.5, 0.4)])
	if thorns > 0:
		buffs.append([Loc.t("トゲ %d") % thorns, Color(0.5, 0.9, 0.4)])
	if heart_k > 0:
		buffs.append(["ハートビート", Color(1.0, 0.45, 0.55)])
	for b in buffs:
		ui.text(c, b[0], Vector2(rx, by), 14, b[1], HORIZONTAL_ALIGNMENT_RIGHT, 210.0)
		by += 20.0
	ui.button(c, "pause", Rect2(W - 74, 8, 64, 46), "||", true, Color(0.6, 0.6, 0.8), 20)
	# fever gauge
	var fx0 := W - 310.0
	var fr := fever_gauge / fever_max() if fever_beats == 0 else fever_beats / 8.0
	var fcol := Color(1.0, 0.8, 0.25) if fever_beats == 0 else Color.from_hsv(fmod(elapsed * 1.5, 1.0), 0.6, 1.0)
	ui.bar(c, Rect2(fx0, 68, 210, 9), fr, fcol, Color(0.15, 0.12, 0.05))
	ui.text(c, "FEVER", Vector2(fx0 - 46.0, 77.0), 11, Color(1.0, 0.85, 0.4))
	# potions
	for i in run.potion_slots():
		var pr := Rect2(10 + i * 42, 160, 38, 38)
		if i < run.potions.size():
			var pd: Dictionary = Potions.DB[run.potions[i]]
			var pc: Color = pd["color"]
			var ph := ui.button_hit(c, "potion:%d" % i, pr)
			c.draw_rect(pr, Color(pc.r * 0.3, pc.g * 0.3, pc.b * 0.3, 0.95))
			c.draw_rect(pr, pc.lerp(Color.WHITE, 0.4 if ph else 0.0), false, 2.0)
			ui.text(c, pd["glyph"], Vector2(pr.position.x, pr.position.y + 27), 22, pc.lerp(Color.WHITE, 0.4), HORIZONTAL_ALIGNMENT_CENTER, pr.size.x)
			if not ui.touch:
				ui.text(c, str(6 + i), Vector2(pr.position.x + 2, pr.position.y + 12), 10, Color(1, 1, 1, 0.6))
		else:
			c.draw_rect(pr, Color(0.1, 0.1, 0.16, 0.6))
			c.draw_rect(pr, Color(1, 1, 1, 0.15), false, 1.0)

	# rhythm lane
	var cx := W / 2.0
	var ly := 46.0
	c.draw_rect(Rect2(cx - 320, ly - 18, 640, 36), Color(0, 0, 0, 0.35))
	c.draw_line(Vector2(cx - 300, ly), Vector2(cx + 300, ly), Color(1, 1, 1, 0.15), 2.0)
	var spb := Conductor.spb
	var st := Conductor.song_time - Conductor.offset
	var t0 := floorf(st / spb)
	for k in range(-1, 5):
		var dt := (t0 + k) * spb - st
		var dx := dt * 220.0
		var a := clampf(1.0 - absf(dx) / 320.0, 0.0, 1.0)
		var big := 1.0 + 0.5 * clampf(1.0 - absf(dx) / 40.0, 0.0, 1.0)
		for s in [-1.0, 1.0]:
			c.draw_circle(Vector2(cx + s * dx, ly), 8.0 * big, Color(0.6, 0.9, 1.0, a))
	var near := absf(Conductor.beat_offset()) <= perfect_window()
	var hr := 15.0 + 5.0 * beat_pulse
	c.draw_arc(Vector2(cx, ly), hr, 0.0, TAU, 32, Color(1.0, 0.9, 0.3) if near else Color(1, 1, 1, 0.6), 3.0)
	# perfect window band
	var pw_px := perfect_window() * 220.0
	c.draw_rect(Rect2(cx - pw_px, ly - 14, pw_px * 2.0, 28), Color(1.0, 0.9, 0.3, 0.08))

	# where your last press landed relative to the beat (left = early, right = late)
	if last_off_t > 0.0:
		var mk := clampf(last_off, -0.25, 0.25) * 220.0
		var ma := minf(1.0, last_off_t * 2.0)
		c.draw_rect(Rect2(cx + mk - 2.0, ly - 16.0, 4.0, 32.0), Color(last_off_col, ma))
		c.draw_colored_polygon(PackedVector2Array([Vector2(cx + mk - 6.0, ly + 24.0), Vector2(cx + mk + 6.0, ly + 24.0), Vector2(cx + mk, ly + 16.0)]), Color(last_off_col, ma))
	ui.text(c, "早い", Vector2(cx - 316.0, ly + 36.0), 11, Color(1, 1, 1, 0.3))
	ui.text(c, "遅い", Vector2(cx + 286.0, ly + 36.0), 11, Color(1, 1, 1, 0.3))
	if tutorial:
		_draw_tutorial(c)

	# boss / elite bar
	for e in enemies:
		if e.kind == "boss" or e.kind == "elite":
			var nm := ("BOSS: " + String(BOSS_NAMES[e.boss_id])) if e.kind == "boss" else "ELITE"
			ui.bar(c, Rect2(cx - 220, 82, 440, 14), e.hp / e.max_hp, Color(0.9, 0.3, 0.6))
			ui.text(c, nm, Vector2(cx - 220, 78), 12, Color(1, 0.7, 0.9))
			break

	if run.daily:
		ui.text(c, Loc.t("★ デイリー: %s") % Loc.t(RunState.MOD_NAMES[run.mod_id]), Vector2(0, 112), 13, Color(1.0, 0.85, 0.3, 0.85), HORIZONTAL_ALIGNMENT_CENTER, W)
	# 4-3-2-1 countdown
	if not started and count_n > 0:
		var k2 := count_t
		var sc := 1.0 + 0.6 * k2
		if intro_banner != "":
			ui.text(c, intro_banner, Vector2(0, 205), 40, Color(1, 0.95, 0.8, 0.9), HORIZONTAL_ALIGNMENT_CENTER, W)
		ui.text(c, str(count_n), Vector2(0, 415 + 25 * (1.0 - k2)), int(110 * sc), Color(1.0, 0.9, 0.4, 0.4 + 0.6 * k2), HORIZONTAL_ALIGNMENT_CENTER, W)
		ui.text(c, "ビートに合わせて準備！", Vector2(0, 450), 22, Color(1, 1, 1, 0.8), HORIZONTAL_ALIGNMENT_CENTER, W)
	# banner
	if banner_time > 0.0 and banner != "" and (started or banner == "GO!"):
		var k := banner_time / 2.2 if kind != "" else 1.0
		var slide := ease(clampf((1.0 - k) * 6.0, 0.0, 1.0), 0.3)
		var a := minf(1.0, banner_time * 2.0)
		c.draw_rect(Rect2(0, 190, W, 70 * slide), Color(0, 0, 0, 0.5 * a))
		ui.text(c, banner, Vector2(0, 240), int(52 + 10 * beat_pulse), Color(1, 0.95, 0.8, a), HORIZONTAL_ALIGNMENT_CENTER, W)

	# hand
	for i in HAND_SIZE:
		var id := deck.hand[i]
		if id != "":
			var d: Dictionary = Cards.def(id)
			var r := card_rect(i)
			var an := slot_anim[i] / 0.35
			if an > 0.0:
				r.position.y += pow(an, 2.0) * 90.0
			ui.card(c, id, r, str(i + 1), energy >= int(d["cost"]), an > 0.0, "hand:%d" % i)
			if an > 0.0:
				c.draw_rect(r.grow(4.0), Color(1, 1, 1, an * 0.5), false, 3.0)
	# next card preview
	var nxt := deck.peek_next()
	ui.text(c, "次のカード", Vector2(20, H - 156), 14, Color(1.0, 0.95, 0.7))
	if nxt != "":
		ui.mini_card(c, nxt, Rect2(20, H - 148, 204, 56))
	else:
		ui.text(c, "(なし)", Vector2(20, H - 120), 14, Color(0.7, 0.7, 0.8))
	ui.text(c, Loc.t("山札 %d") % deck.draw_pile.size(), Vector2(20, H - 66), 16, Color(0.8, 0.8, 0.95))
	ui.text(c, Loc.t("捨て札 %d") % deck.discard_pile.size(), Vector2(20, H - 42), 16, Color(0.8, 0.8, 0.95))
