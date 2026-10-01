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

class Bolt:
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var dmg := 8.0
	var life := 1.6
	var color := Color(1.0, 0.85, 0.5)

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
var touch_dir := Vector2.ZERO
var cast_name := ""
var cast_short := ""
var cast_col := Color.WHITE
var cast_grade := ""
var cast_t := 0.0
var slot_anim: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
var done := false
var end_timer := 0.0
var end_won := false
var elapsed := 0.0
var _trail_t := 0.0
var _lit := {}
var _stars: Array = []
var _tex_cache := {}
var _beat_cb: Callable

func _init() -> void:
	for i in 70:
		_stars.append([Vector2(randf() * W, randf() * H), randf() * TAU, 0.3 + randf() * 0.7])

func tex(i: int) -> Texture2D:
	if not _tex_cache.has(i):
		_tex_cache[i] = load(TILE_DIR % i)
	return _tex_cache[i]

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
	time_left = 0.0 if kind == "boss" else (26.0 if kind == "elite" or kind == "endless" else 24.0)
	spawning = true
	match kind:
		"boss":
			banner = "BOSS"
			var b := _make_enemy("boss")
			b.pos = Vector2(W / 2.0, -40.0)
			enemies.append(b)
		"elite":
			banner = "エリート出現！"
			var e := _make_enemy("elite")
			e.pos = _edge_point()
			enemies.append(e)
		"endless":
			banner = "ウェーブ %d" % (run.wave + 1)
		_:
			banner = "バトル開始"
	banner_time = 2.2
	_beat_cb = Callable(self, "on_beat")
	Conductor.beat.connect(_beat_cb)

func dispose() -> void:
	if Conductor.beat.is_connected(_beat_cb):
		Conductor.beat.disconnect(_beat_cb)

# ---- helpers ---------------------------------------------------------------

func perfect_window() -> float:
	return PERFECT_BASE + (0.02 if run.has_relic("metronome") else 0.0)

func good_window() -> float:
	return GOOD_BASE + (0.02 if run.has_relic("metronome") else 0.0)

func dmg_mult() -> float:
	var per := 0.03 if run.has_relic("amp") else 0.02
	return (2.0 if frenzy_beats > 0 else 1.0) * (1.0 + minf(combo, 20.0) * per)

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
			e.max_hp = 260.0 + 70.0 * d
			e.speed = 48.0
			e.radius = 44.0
			e.dmg = 14
			e.color = Color(0.85, 0.25, 0.6)
			e.tex = tex(110)
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
			e.tex = tex(108 if d < 2.6 else 121)
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
	flash_a = maxf(flash_a, a)

# ---- simulation ------------------------------------------------------------

func on_beat(_n: int) -> void:
	beat_pulse = 1.0
	beat_count += 1
	for i in 4:
		_lit[Vector2i(randi() % 20, randi() % 8)] = 1.0
	if ending:
		return
	ring(player_pos, 70.0, Color(1, 1, 1, 0.25), 0.4)
	if blade_beats > 0:
		blade_beats -= 1
	if frenzy_beats > 0:
		frenzy_beats -= 1
	if slow_beats > 0:
		slow_beats -= 1
	if beat_count % 2 == 0:
		energy = mini(max_energy, energy + 1)
	if fort > 0 and beat_count % 4 == 0:
		shield = mini(60, shield + fort)
		float_text(player_pos + Vector2(0, -34), "+%d" % fort, Color(0.5, 0.7, 1.0))
	# auto weapon
	var targets := nearest_enemies(2 if run.char_id == "ranger" else 1)
	var adm := 4.0 + res_bonus + (3.0 if run.has_relic("sword") else 0.0)
	for i in targets.size():
		_fire_bolt((targets[i] as Enemy).pos, adm * dmg_mult(), 0.0)
	# spawning
	if spawning and enemies.size() < 110 and (kind != "boss" or beat_count % 2 == 0):
		var n := 1 + int(diff / 2.0)
		for i in n:
			var k := "grunt"
			var r := randf()
			if diff >= 2.2 and r < 0.14:
				k = "tank"
			elif diff >= 1.5 and r < 0.38:
				k = "fast"
			var e := _make_enemy(k)
			e.pos = _edge_point()
			enemies.append(e)
	# boss / elite abilities
	for e in enemies:
		if e.spawn_t > 0.0:
			continue
		if e.kind == "boss" and beat_count % 8 == 0:
			slams.append({"pos": player_pos, "r": 170.0, "t": 4.0 * Conductor.spb, "dmg": 14})
			if beat_count % 16 == 0:
				for i in 4:
					var m := _make_enemy("grunt")
					m.pos = e.pos + Vector2.from_angle(i * TAU / 4.0) * 60.0
					enemies.append(m)
		elif e.kind == "elite" and beat_count % 8 == 4:
			slams.append({"pos": player_pos, "r": 120.0, "t": 4.0 * Conductor.spb, "dmg": 10})

func _fire_bolt(target: Vector2, dmg: float, spread: float) -> void:
	var b := Bolt.new()
	b.pos = player_pos
	b.vel = (target - player_pos).normalized().rotated(spread) * 640.0
	b.dmg = dmg
	bolts.append(b)

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
	for i in slot_anim.size():
		slot_anim[i] = maxf(0.0, slot_anim[i] - delta)
	shake = maxf(0.0, shake - delta * 28.0)
	beat_pulse = maxf(0.0, beat_pulse - delta * 4.0)
	flash_a = maxf(0.0, flash_a - delta * 2.5)
	for k in _lit.keys():
		_lit[k] -= delta * 2.0
		if _lit[k] <= 0.0:
			_lit.erase(k)
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
	return Vector2(
		float(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)),
		float(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)) - float(Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)))

var bot_dir := Callable()

func _update_play(delta: float) -> void:
	var dir := move_dir()
	if bot_dir.is_valid():
		dir = bot_dir.call()
	var spd := 270.0 * float(char_def["speed"]) * (1.15 if run.has_relic("boots") else 1.0)
	player_pos += dir.normalized() * spd * delta
	player_pos = player_pos.clamp(Vector2(24, 24), Vector2(W - 24, ARENA_BOTTOM))
	invuln = maxf(0.0, invuln - delta)
	blade_angle += delta * 4.5
	_trail_t -= delta
	if dir.length() > 0.1 and _trail_t <= 0.0:
		_trail_t = 0.05
		burst(player_pos + Vector2(0, 14), Color(0.7, 0.6, 1.0, 0.7), 1, 15.0, 0.35, 5.0)

	var slow := 0.35 if slow_beats > 0 else 1.0
	for e in enemies:
		e.flash = maxf(0.0, e.flash - delta)
		e.blade_cd = maxf(0.0, e.blade_cd - delta)
		if e.spawn_t > 0.0:
			e.spawn_t -= delta
			continue
		var to_p := (player_pos - e.pos).normalized()
		var mv := to_p
		if e.kind == "fast":
			mv = (to_p + to_p.orthogonal() * sin(elapsed * 6.0 + e.phase) * 0.8).normalized()
		e.pos += mv * e.speed * slow * delta
		if invuln <= 0.0 and e.pos.distance_to(player_pos) < e.radius + 14.0:
			damage_player(e.dmg)

	for b in bolts:
		b.pos += b.vel * delta
		b.life -= delta
		if randf() < 0.7:
			burst(b.pos, b.color, 1, 20.0, 0.25, 3.0)
		for e in enemies:
			if e.hp > 0.0 and e.spawn_t <= 0.0 and b.pos.distance_to(e.pos) < e.radius + 5.0:
				hit(e, b.dmg)
				b.life = 0.0
				break
	bolts = bolts.filter(func(b: Bolt) -> bool: return b.life > 0.0)

	if blade_beats > 0:
		for i in blade_n:
			var bp := player_pos + Vector2.from_angle(blade_angle + i * TAU / blade_n) * 85.0
			burst(bp, Color(0.5, 0.9, 1.0), 1, 10.0, 0.25, 3.0)
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
	enemies = alive

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
	burst(e.pos, e.color, 14 if e.radius < 25.0 else 40, 220.0, 0.6, 5.0, 120.0)
	ring(e.pos, e.radius * 2.2, e.color, 0.25)
	if e.kind == "boss":
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
	for e in enemies:
		burst(e.pos, e.color, 10, 200.0, 0.5, 4.0, 100.0)
	enemies.clear()
	if won:
		banner = "CLEAR!"
		banner_time = 1.5
		Conductor.play_sfx("win")

func damage_player(d: int) -> void:
	invuln = 0.55
	do_shake(8.0)
	hitstop = 0.06
	flash(Color(1, 0.2, 0.2), 0.35)
	var absorbed := mini(shield, d)
	shield -= absorbed
	var real := d - absorbed
	run.hp -= real
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

# ---- cards -----------------------------------------------------------------

func try_play(slot: int) -> void:
	if ending:
		return
	var id := deck.hand[slot]
	if id == "":
		return
	var d: Dictionary = Cards.def(id)
	var cost: int = d["cost"]
	if energy < cost:
		float_text(player_pos + Vector2(0, -44), "エネルギー不足", Color(0.7, 0.7, 0.75))
		Conductor.play_sfx("miss")
		return
	energy -= cost
	var a := absf(Conductor.beat_offset())
	var grade := "MISS"
	var gm := 0.6
	var col := Color(0.8, 0.3, 0.3)
	if a <= perfect_window():
		grade = "PERFECT"
		gm = 1.5
		col = Color(1.0, 0.9, 0.3)
		combo += 1
		flash(Color(1.0, 0.9, 0.4), 0.18)
		ring(player_pos, 110.0, col, 0.4)
		burst(player_pos, col, 22, 280.0, 0.5, 5.0)
	elif a <= good_window():
		grade = "GOOD"
		gm = 1.0
		col = Color(0.5, 0.9, 1.0)
		combo += 1
		ring(player_pos, 80.0, col, 0.3)
		burst(player_pos, col, 10, 200.0, 0.4, 4.0)
	else:
		combo = 0
	if grade != "MISS" and run.char_id == "wizard" and combo > 0 and combo % 5 == 0:
		energy = mini(max_energy, energy + 1)
		float_text(player_pos + Vector2(0, -80), "アルカナ +1", Color(0.8, 0.6, 1.0), 16)
	Conductor.play_sfx(grade.to_lower())
	Conductor.play_sfx("card")
	float_text(player_pos + Vector2(0, -52), grade + ("!" if grade == "PERFECT" else ""), col, 26 if grade == "PERFECT" else 20, 0.8)
	var times := 2 if (echo_pending and Cards.base_id(id) != "echo") else 1
	if Cards.base_id(id) != "echo":
		echo_pending = false
	var m := gm * dmg_mult()
	for i in times:
		_apply_card(id, m)
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

# ---- drawing: world --------------------------------------------------------

func draw_world(c: Node2D) -> void:
	var pulse := beat_pulse
	var off := Vector2.ZERO
	if shake > 0.0:
		off = Vector2(randf_range(-shake, shake), randf_range(-shake, shake)) * 0.6
	var z := 1.0 + 0.012 * pulse
	var base := Transform2D(0.0, Vector2(z, z), 0.0, Vector2(W, ARENA_BOTTOM) / 2.0 * (1.0 - z) + off)
	c.draw_set_transform_matrix(base)
	var floor_tex := tex(0)
	for x in 20:
		for y in 12:
			var lit: float = _lit.get(Vector2i(x, y), 0.0)
			var v := 0.30 + 0.06 * pulse + lit * 0.35
			c.draw_texture_rect(floor_tex, Rect2(x * 64, y * 64, 64, 64), false, Color(v * 0.45, v * 0.85, v * 1.9))
	for s in _stars:
		var a: float = 0.3 + 0.4 * sin(elapsed * 2.0 * s[2] + s[1])
		c.draw_rect(Rect2(s[0], Vector2(2, 2)), Color(1, 1, 1, a * 0.5))
	c.draw_rect(Rect2(0, ARENA_BOTTOM + 14, W, 3), Color(0.6, 0.5, 1.0, 0.25 + 0.3 * pulse))

	# telegraphs
	for s in slams:
		var k: float = 1.0 - float(s["t"]) / (4.0 * Conductor.spb)
		var sp: Vector2 = s["pos"]
		c.draw_circle(sp, s["r"], Color(1, 0.2, 0.2, 0.08 + 0.15 * k))
		c.draw_arc(sp, s["r"], 0.0, TAU, 48, Color(1, 0.4, 0.3, 0.5 + 0.5 * k), 3.0)
		c.draw_arc(sp, s["r"] * k, 0.0, TAU, 48, Color(1, 0.8, 0.5, 0.8), 2.0)
	# enemies
	for e in enemies:
		var sc := 1.0 - maxf(e.spawn_t, 0.0) / 0.35
		var squash := 1.0 + 0.08 * sin(elapsed * 10.0 + e.phase) + 0.1 * pulse
		var sz := e.radius * 3.2 * sc
		var col := Color(3, 3, 3) if e.flash > 0.0 else (Color(0.6, 0.8, 1.3) if slow_beats > 0 else Color.WHITE)
		var flip := -1.0 if player_pos.x < e.pos.x else 1.0
		c.draw_circle(e.pos + Vector2(0, e.radius * 0.9), e.radius * 0.9 * sc, Color(0, 0, 0, 0.35))
		var w := sz * flip * (2.0 - squash)
		c.draw_texture_rect(e.tex, Rect2(e.pos.x - w / 2.0, e.pos.y - sz * squash / 2.0, w, sz * squash), false, col)
		if e.kind == "boss" or e.kind == "elite":
			c.draw_arc(e.pos, e.radius + 5.0, 0.0, TAU, 48, Color(e.color, 0.8), 3.0)
		if e.spawn_t > 0.0:
			c.draw_arc(e.pos, 22.0 * (1.0 + e.spawn_t * 3.0), 0.0, TAU, 20, Color(1, 0.4, 0.4, 0.6), 2.0)
	for b in bolts:
		c.draw_circle(b.pos, 7.0, Color(b.color, 0.35))
		c.draw_circle(b.pos, 4.0, b.color)
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
	c.draw_circle(player_pos + Vector2(0, 22), 18.0, Color(0, 0, 0, 0.4))
	c.draw_circle(player_pos, 34.0 + 6.0 * pulse, Color(char_def["color"] as Color, 0.12 + 0.1 * pulse))
	var pw := ps * (-1.0 if player_pos.x > W / 2.0 and false else 1.0)
	c.draw_texture_rect(tex(int(char_def["tile"])), Rect2(player_pos - Vector2(pw, ps) / 2.0, Vector2(pw, ps)), false, Color.WHITE if not blink else Color(1, 1, 1, 0.35))
	if shield > 0:
		c.draw_arc(player_pos, 26.0, 0.0, TAU, 32, Color(0.5, 0.7, 1.0, 0.9), 3.0)
	if frenzy_beats > 0:
		c.draw_arc(player_pos, 32.0 + 3.0 * pulse, 0.0, TAU, 32, Color(1.0, 0.6, 0.2), 2.0)
	if echo_pending:
		c.draw_arc(player_pos, 38.0, 0.0, TAU, 6, Color(0.85, 0.7, 1.0), 2.0)
	_draw_mini_status(c)
	_draw_cast(c)
	# particles
	for q in parts:
		var k := q.life / q.max_life
		c.draw_rect(Rect2(q.pos - Vector2(q.size, q.size) * 0.5 * k, Vector2(q.size, q.size) * k), Color(q.color, k))
	# fx
	for f in fxs:
		var k := f.life / f.max_life
		match f.kind:
			"ring":
				var r := f.radius * (1.0 - k * k * 0.9)
				c.draw_arc(f.pos, r, 0.0, TAU, 48, Color(f.color, k), 4.0)
			"line":
				c.draw_line(f.pos, f.to, Color(f.color, k), 3.0)
			"beam":
				c.draw_line(f.pos, f.to, Color(f.color, k * 0.4), f.radius * 2.0 * k)
				c.draw_line(f.pos, f.to, Color(1, 1, 1, k), maxf(1.0, f.radius * k * 0.6))
			"text":
				var rise := 34.0 * (1.0 - k)
				var pop := 1.0 + 0.5 * maxf(0.0, k - 0.8) * 5.0
				c.draw_string(ui.font, f.pos + Vector2(-60, -rise + 1), f.text, HORIZONTAL_ALIGNMENT_CENTER, 120.0, int(f.size * pop), Color(0, 0, 0, k))
				c.draw_string(ui.font, f.pos + Vector2(-60, -rise), f.text, HORIZONTAL_ALIGNMENT_CENTER, 120.0, int(f.size * pop), Color(f.color, minf(1.0, k * 2.0)))
	c.draw_set_transform_matrix(Transform2D.IDENTITY)
	# screen overlays
	var hp_frac := float(run.hp) / float(run.max_hp)
	if hp_frac < 0.35:
		_vignette(c, Color(0.9, 0.05, 0.1), (0.35 - hp_frac) * 1.4 + 0.1 * sin(elapsed * 6.0))
	_vignette(c, Color(0.4, 0.3, 0.9), 0.12 * pulse)
	if flash_a > 0.0:
		c.draw_rect(Rect2(0, 0, W, H), Color(flash_col, flash_a * 0.5))

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
	c.draw_string(ui.font, Vector2(px - 120, py - 3), cast_name, HORIZONTAL_ALIGNMENT_LEFT, 170.0, 19, Color(cast_col.lerp(Color.WHITE, 0.35), a))
	var gcol := Color(1.0, 0.9, 0.3) if cast_grade == "PERFECT" else (Color(0.5, 0.9, 1.0) if cast_grade == "GOOD" else Color(0.9, 0.4, 0.4))
	c.draw_string(ui.font, Vector2(px + 40, py - 3), cast_grade, HORIZONTAL_ALIGNMENT_RIGHT, 84.0, 13, Color(gcol, a))
	c.draw_string(ui.font, Vector2(px - 120, py + 17), cast_short, HORIZONTAL_ALIGNMENT_LEFT, 244.0, 13, Color(0.92, 0.92, 1.0, a))

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
		ui.text(c, "シールド %d" % shield, Vector2(66, 62), 12, Color(0.6, 0.75, 1.0))
	for i in max_energy:
		var on := i < energy
		var cx := 72.0 + i * 26.0
		c.draw_circle(Vector2(cx, 80), 10.0 + (2.0 * beat_pulse if on else 0.0), Color(1.0, 0.85, 0.3) if on else Color(0.25, 0.22, 0.15))
	var label := ""
	match kind:
		"boss": label = "BOSS戦"
		"elite": label = "エリート"
		"endless": label = "エンドレス ウェーブ%d" % (run.wave + 1)
		_: label = "バトル"
	var tl := "" if (kind == "boss" or not spawning) else "  残り%.0f" % maxf(time_left, 0.0)
	ui.text(c, "%s%s   撃破 %d   %dG" % [label, tl, kills, run.gold], Vector2(16, 112), 14, Color(0.9, 0.9, 1.0))
	# relics
	for i in run.relics.size():
		ui.relic_icon(c, run.relics[i], Rect2(10 + i * 30, 128, 26, 26), "relic:%d" % i)
	# combo / buffs
	var rx := W - 310.0
	if combo > 1:
		ui.text(c, "コンボ x%d" % combo, Vector2(rx, 40), 28, Color(1.0, 0.9, 0.3) if combo < 10 else Color(1.0, 0.6, 0.2), HORIZONTAL_ALIGNMENT_RIGHT, 210.0)
		var per := 3.0 if run.has_relic("amp") else 2.0
		ui.text(c, "ダメージ +%d%%" % int(minf(combo, 20.0) * per), Vector2(rx, 62), 14, Color(1.0, 0.9, 0.6), HORIZONTAL_ALIGNMENT_RIGHT, 210.0)
	var by := 86.0
	var buffs: Array = []
	if frenzy_beats > 0:
		buffs.append(["フレンジー %d" % frenzy_beats, Color(1.0, 0.6, 0.2)])
	if slow_beats > 0:
		buffs.append(["減速 %d" % slow_beats, Color(0.6, 0.9, 1.0)])
	if blade_beats > 0:
		buffs.append(["ブレード %d" % blade_beats, Color(0.5, 0.9, 1.0)])
	if res_bonus > 0:
		buffs.append(["レゾナンス +%d" % res_bonus, Color(1.0, 0.4, 0.5)])
	if fort > 0:
		buffs.append(["フォートレス +%d" % fort, Color(0.5, 0.7, 1.0)])
	if aura_k > 0:
		buffs.append(["オーラ %d/%d" % [aura_count, aura_k], Color(0.8, 0.3, 0.6)])
	if echo_pending:
		buffs.append(["エコー待機", Color(0.85, 0.7, 1.0)])
	for b in buffs:
		ui.text(c, b[0], Vector2(rx, by), 14, b[1], HORIZONTAL_ALIGNMENT_RIGHT, 210.0)
		by += 20.0
	ui.button(c, "pause", Rect2(W - 74, 8, 64, 46), "||", true, Color(0.6, 0.6, 0.8), 20)

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

	# boss / elite bar
	for e in enemies:
		if e.kind == "boss" or e.kind == "elite":
			var nm := "BOSS" if e.kind == "boss" else "ELITE"
			ui.bar(c, Rect2(cx - 220, 82, 440, 14), e.hp / e.max_hp, Color(0.9, 0.3, 0.6))
			ui.text(c, nm, Vector2(cx - 220, 78), 12, Color(1, 0.7, 0.9))
			break

	# banner
	if banner_time > 0.0 and banner != "":
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
	ui.text(c, "山札 %d" % deck.draw_pile.size(), Vector2(20, H - 66), 16, Color(0.8, 0.8, 0.95))
	ui.text(c, "捨て札 %d" % deck.discard_pile.size(), Vector2(20, H - 42), 16, Color(0.8, 0.8, 0.95))
