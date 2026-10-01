extends Node2D
## Beat Deck Survivors: auto-battle survivor arena + Slay-the-Spire deck + rhythm timing.
## Move with WASD/arrows. Play cards (keys 1-5 or click) ON THE BEAT for bonus power.

const W := 1280.0
const H := 720.0
const HAND_SIZE := 5
const MAX_WAVE := 5
const WAVE_TIME := 28.0
const MAX_ENERGY := 5
const PLAYER_SPEED := 270.0
const PERFECT_WINDOW := 0.07
const GOOD_WINDOW := 0.14

enum State { TITLE, PLAYING, REWARD, WON, LOST }

class Enemy:
	var pos := Vector2.ZERO
	var hp := 10.0
	var max_hp := 10.0
	var speed := 80.0
	var radius := 12.0
	var dmg := 6
	var color := Color.RED
	var boss := false
	var blade_cd := 0.0
	var flash := 0.0

class Bolt:
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var dmg := 8.0
	var life := 1.6

class Fx:
	var kind := "ring"  # ring | line | text
	var pos := Vector2.ZERO
	var to := Vector2.ZERO
	var text := ""
	var color := Color.WHITE
	var life := 0.4
	var max_life := 0.4
	var radius := 100.0

var state: State = State.TITLE
var deck := Deck.new()
var enemies: Array[Enemy] = []
var bolts: Array[Bolt] = []
var fxs: Array[Fx] = []

var player_pos := Vector2(W / 2.0, H / 2.0 - 40.0)
var hp := 60
var max_hp := 60
var shield := 0
var energy := 3
var invuln := 0.0
var combo := 0
var kills := 0
var wave := 0
var wave_time_left := 0.0
var spawning := false
var boss_alive := false
var beat_count := 0
var blade_beats := 0
var blade_power := 1.0
var blade_angle := 0.0
var frenzy_beats := 0
var banner := ""
var banner_time := 0.0
var reward_options: Array = []
var shake := 0.0

var _autotest := false
var _autotest_time := 0.0
var _shot_path := ""
var _hud: Control

func _ready() -> void:
	randomize()
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Control.new()
	_hud.set_script(load("res://scripts/hud.gd"))
	_hud.game = self
	layer.add_child(_hud)
	Conductor.beat.connect(_on_beat)
	var args := OS.get_cmdline_user_args()
	_autotest = "--autotest" in args
	for a in args:
		if a.begins_with("--shot="):
			_shot_path = a.substr(7)
	if _autotest:
		Engine.time_scale = 5.0
		start_game()

func start_game() -> void:
	deck.setup(Cards.STARTER, HAND_SIZE)
	enemies.clear()
	bolts.clear()
	fxs.clear()
	player_pos = Vector2(W / 2.0, H / 2.0 - 40.0)
	hp = max_hp
	shield = 0
	energy = 3
	combo = 0
	kills = 0
	wave = 0
	beat_count = 0
	blade_beats = 0
	frenzy_beats = 0
	if not Conductor.running:
		Conductor.start()
	_start_wave()

func _start_wave() -> void:
	wave += 1
	state = State.PLAYING
	wave_time_left = WAVE_TIME
	spawning = true
	boss_alive = false
	energy = maxi(energy, 3)
	banner = "WAVE %d" % wave if wave < MAX_WAVE else "FINAL WAVE - BOSS"
	banner_time = 2.5
	if wave == MAX_WAVE:
		var b := _make_enemy(_edge_point(), true)
		enemies.append(b)
		boss_alive = true

# ---- input -----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).keycode
		match state:
			State.TITLE:
				if k == KEY_ENTER or k == KEY_SPACE:
					start_game()
			State.PLAYING:
				if k >= KEY_1 and k <= KEY_5:
					try_play(k - KEY_1)
			State.REWARD:
				if k >= KEY_1 and k <= KEY_3:
					pick_reward(k - KEY_1)
				elif k == KEY_4 or k == KEY_SPACE:
					rest()
			State.WON, State.LOST:
				if k == KEY_ENTER or k == KEY_R:
					start_game()
		if k == KEY_BRACKETLEFT:
			Conductor.offset -= 0.01
		elif k == KEY_BRACKETRIGHT:
			Conductor.offset += 0.01
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var p := (event as InputEventMouseButton).position
		match state:
			State.TITLE:
				start_game()
			State.PLAYING:
				for i in HAND_SIZE:
					if card_rect(i).has_point(p):
						try_play(i)
			State.REWARD:
				for i in reward_options.size():
					if reward_rect(i).has_point(p):
						pick_reward(i)
				if rest_rect().has_point(p):
					rest()
			State.WON, State.LOST:
				start_game()

func pick_reward(i: int) -> void:
	if i >= reward_options.size():
		return
	deck.add_card(reward_options[i])
	_start_wave()

func rest() -> void:
	hp = mini(max_hp, hp + 15)
	_start_wave()

# ---- layout ----------------------------------------------------------------

func card_rect(i: int) -> Rect2:
	var cw := 150.0
	var gap := 12.0
	var x0 := (W - (HAND_SIZE * cw + (HAND_SIZE - 1) * gap)) / 2.0
	return Rect2(x0 + i * (cw + gap), H - 210.0, cw, 196.0)

func reward_rect(i: int) -> Rect2:
	return Rect2(W / 2.0 - 270.0 * 1.5 + i * 285.0 - 0.0, 190.0, 255.0, 300.0)

func rest_rect() -> Rect2:
	return Rect2(W / 2.0 - 150.0, 520.0, 300.0, 56.0)

# ---- simulation ------------------------------------------------------------

func _process(delta: float) -> void:
	if state == State.PLAYING:
		_update_play(delta)
	for f in fxs:
		f.life -= delta
	fxs = fxs.filter(func(f: Fx) -> bool: return f.life > 0.0)
	banner_time = maxf(0.0, banner_time - delta)
	shake = maxf(0.0, shake - delta * 30.0)
	if _autotest:
		_run_autotest(delta)
	queue_redraw()

func _update_play(delta: float) -> void:
	var dir := Vector2(
		float(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)),
		float(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)) - float(Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)))
	if _autotest:
		dir = Vector2.from_angle(Time.get_ticks_msec() / 900.0)
	player_pos += dir.normalized() * PLAYER_SPEED * delta
	player_pos = player_pos.clamp(Vector2(20, 20), Vector2(W - 20, H - 230))
	invuln = maxf(0.0, invuln - delta)
	blade_angle += delta * 4.5

	for e in enemies:
		e.pos += (player_pos - e.pos).normalized() * e.speed * delta
		e.flash = maxf(0.0, e.flash - delta)
		e.blade_cd = maxf(0.0, e.blade_cd - delta)
		if invuln <= 0.0 and e.pos.distance_to(player_pos) < e.radius + 14.0:
			_damage_player(e.dmg)

	for b in bolts:
		b.pos += b.vel * delta
		b.life -= delta
		for e in enemies:
			if e.hp > 0.0 and b.pos.distance_to(e.pos) < e.radius + 5.0:
				_hit(e, b.dmg)
				b.life = 0.0
				break
	bolts = bolts.filter(func(b: Bolt) -> bool: return b.life > 0.0)

	if blade_beats > 0:
		for i in 3:
			var bp := player_pos + Vector2.from_angle(blade_angle + i * TAU / 3.0) * 85.0
			for e in enemies:
				if e.blade_cd <= 0.0 and bp.distance_to(e.pos) < e.radius + 12.0:
					_hit(e, 7.0 * blade_power * _dmg_mult())
					e.blade_cd = 0.3

	var boss_was_alive := boss_alive
	var alive: Array[Enemy] = []
	boss_alive = false
	for e in enemies:
		if e.hp > 0.0:
			alive.append(e)
			if e.boss:
				boss_alive = true
		else:
			kills += 1
			_ring(e.pos, e.radius * 2.0, e.color, 0.25)
	enemies = alive

	if spawning and wave < MAX_WAVE:
		wave_time_left -= delta
		if wave_time_left <= 0.0:
			spawning = false
	if wave < MAX_WAVE:
		if not spawning:
			_end_wave()
	elif boss_was_alive and not boss_alive:
		_end_wave()

	if hp <= 0:
		state = State.LOST
		banner = ""

func _end_wave() -> void:
	for e in enemies:
		_ring(e.pos, 30.0, e.color, 0.3)
	enemies.clear()
	bolts.clear()
	spawning = false
	if wave >= MAX_WAVE:
		state = State.WON
	else:
		reward_options = Cards.random_choices(3)
		state = State.REWARD

func _on_beat(_n: int) -> void:
	beat_count += 1
	if state != State.PLAYING:
		return
	if blade_beats > 0:
		blade_beats -= 1
	if frenzy_beats > 0:
		frenzy_beats -= 1
	if beat_count % 2 == 0:
		energy = mini(MAX_ENERGY, energy + 1)
	# base weapon: weak bolt every beat
	var t := nearest_enemies(1)
	if not t.is_empty():
		_fire_bolt((t[0] as Enemy).pos, 4.0 * _dmg_mult(), 0.0)
	if spawning:
		var per_beat := 1 + wave / 2
		for i in per_beat:
			enemies.append(_make_enemy(_edge_point(), false))

func _make_enemy(p: Vector2, boss: bool) -> Enemy:
	var e := Enemy.new()
	e.pos = p
	if boss:
		e.boss = true
		e.max_hp = 700.0
		e.speed = 50.0
		e.radius = 42.0
		e.dmg = 14
		e.color = Color(0.8, 0.2, 0.6)
	else:
		e.max_hp = 12.0 + wave * 7.0
		e.speed = 65.0 + wave * 9.0 + randf() * 20.0
		e.radius = 11.0 + randf() * 4.0
		e.dmg = 5 + wave
		e.color = Color.from_hsv(0.0 + wave * 0.04 + randf() * 0.03, 0.7, 0.9)
	e.hp = e.max_hp
	return e

func _edge_point() -> Vector2:
	match randi() % 4:
		0: return Vector2(randf() * W, -30.0)
		1: return Vector2(randf() * W, H - 200.0)
		2: return Vector2(-30.0, randf() * (H - 200.0))
		_: return Vector2(W + 30.0, randf() * (H - 200.0))

func _damage_player(d: int) -> void:
	invuln = 0.5
	shake = 6.0
	var absorbed := mini(shield, d)
	shield -= absorbed
	hp -= d - absorbed
	Conductor.play_sfx("hit")

func _hit(e: Enemy, dmg: float) -> void:
	e.hp -= dmg
	e.flash = 0.1

func _dmg_mult() -> float:
	return (2.0 if frenzy_beats > 0 else 1.0) * (1.0 + minf(combo, 20.0) * 0.02)

func nearest_enemies(n: int) -> Array:
	var arr: Array = enemies.duplicate()
	arr.sort_custom(func(a: Enemy, b: Enemy) -> bool:
		return a.pos.distance_squared_to(player_pos) < b.pos.distance_squared_to(player_pos))
	return arr.slice(0, n)

func _fire_bolt(target: Vector2, dmg: float, spread: float) -> void:
	var b := Bolt.new()
	b.pos = player_pos
	b.vel = (target - player_pos).normalized().rotated(spread) * 620.0
	b.dmg = dmg
	bolts.append(b)

# ---- cards -----------------------------------------------------------------

func try_play(slot: int) -> void:
	if state != State.PLAYING:
		return
	var id := deck.hand[slot]
	if id == "":
		return
	var card: Dictionary = Cards.DB[id]
	var cost: int = card["cost"]
	if energy < cost:
		_text(player_pos + Vector2(0, -40), "NO ENERGY", Color(0.7, 0.7, 0.7))
		return
	energy -= cost
	var a := absf(Conductor.beat_offset())
	var grade := "MISS"
	var gm := 0.6
	var col := Color(0.8, 0.3, 0.3)
	if a <= PERFECT_WINDOW:
		grade = "PERFECT"
		gm = 1.5
		col = Color(1.0, 0.9, 0.3)
		combo += 1
	elif a <= GOOD_WINDOW:
		grade = "GOOD"
		gm = 1.0
		col = Color(0.5, 0.9, 1.0)
		combo += 1
	else:
		combo = 0
	Conductor.play_sfx(grade.to_lower())
	_text(player_pos + Vector2(0, -50), grade, col)
	_apply_card(id, gm * _dmg_mult())
	deck.play(slot)

func _apply_card(id: String, m: float) -> void:
	match id:
		"pulse":
			var t := nearest_enemies(3)
			for i in 3:
				var tgt := Vector2(player_pos.x + randf_range(-1.0, 1.0), player_pos.y - 1.0)
				if not t.is_empty():
					tgt = (t[i % t.size()] as Enemy).pos
				_fire_bolt(tgt, 8.0 * m, (i - 1) * 0.08)
		"chain":
			var t := nearest_enemies(5)
			var prev := player_pos
			for e in t:
				_hit(e, 10.0 * m)
				var f := Fx.new()
				f.kind = "line"
				f.pos = prev
				f.to = (e as Enemy).pos
				f.color = Color(1.0, 0.95, 0.4)
				f.life = 0.18
				f.max_life = 0.18
				fxs.append(f)
				prev = (e as Enemy).pos
		"nova":
			_ring(player_pos, 180.0, Color(1.0, 0.5, 0.85), 0.35)
			shake = 8.0
			Conductor.play_sfx("boom")
			for e in enemies:
				var d := e.pos.distance_to(player_pos)
				if d < 180.0 + e.radius:
					_hit(e, 20.0 * m)
					e.pos += (e.pos - player_pos).normalized() * 70.0
		"blades":
			blade_beats = 10
			blade_power = m
		"bass":
			_ring(player_pos, 700.0, Color(0.7, 0.4, 1.0), 0.5)
			shake = 14.0
			Conductor.play_sfx("boom")
			for e in enemies:
				_hit(e, 30.0 * m)
		"guard":
			shield += int(8.0 * m)
		"mend":
			hp = mini(max_hp, hp + int(10.0 * m))
			_text(player_pos + Vector2(0, -30), "+%d" % int(10.0 * m), Color(0.4, 1.0, 0.5))
		"surge":
			energy = mini(MAX_ENERGY, energy + 2)
		"frenzy":
			frenzy_beats = 8

func _ring(p: Vector2, r: float, c: Color, life: float) -> void:
	var f := Fx.new()
	f.kind = "ring"
	f.pos = p
	f.radius = r
	f.color = c
	f.life = life
	f.max_life = life
	fxs.append(f)

func _text(p: Vector2, s: String, c: Color) -> void:
	var f := Fx.new()
	f.kind = "text"
	f.pos = p
	f.text = s
	f.color = c
	f.life = 0.7
	f.max_life = 0.7
	fxs.append(f)

# ---- drawing: world --------------------------------------------------------

func _draw() -> void:
	var pulse := pow(1.0 - Conductor.beat_phase(), 3.0)
	var off := Vector2(randf_range(-shake, shake), randf_range(-shake, shake)) * 0.5
	draw_rect(Rect2(0, 0, W, H), Color(0.05, 0.04, 0.09))
	var gc := Color(0.5, 0.4, 0.9, 0.05 + 0.12 * pulse)
	for x in range(0, int(W) + 1, 64):
		draw_line(Vector2(x, 0) + off, Vector2(x, H) + off, gc)
	for y in range(0, int(H) + 1, 64):
		draw_line(Vector2(0, y) + off, Vector2(W, y) + off, gc)
	if state == State.TITLE:
		return

	for e in enemies:
		var c := Color.WHITE if e.flash > 0.0 else e.color
		draw_circle(e.pos + off, e.radius, c)
		if e.boss:
			draw_arc(e.pos + off, e.radius + 4.0, 0.0, TAU, 48, Color(1, 0.6, 0.9), 3.0)
			var w := 120.0
			draw_rect(Rect2(e.pos.x - w / 2.0, e.pos.y - e.radius - 18.0, w, 7.0), Color(0.2, 0.1, 0.2))
			draw_rect(Rect2(e.pos.x - w / 2.0, e.pos.y - e.radius - 18.0, w * e.hp / e.max_hp, 7.0), Color(0.9, 0.3, 0.6))
	for b in bolts:
		draw_circle(b.pos + off, 5.0, Color(1.0, 0.85, 0.5))
	if blade_beats > 0:
		for i in 3:
			var bp := player_pos + Vector2.from_angle(blade_angle + i * TAU / 3.0) * 85.0
			draw_circle(bp + off, 11.0, Color(0.5, 0.9, 1.0))
	# player
	var blink := invuln > 0.0 and int(invuln * 20.0) % 2 == 0
	draw_circle(player_pos + off, 14.0 + 3.0 * pulse, Color(0.4, 1.0, 0.9) if not blink else Color(1, 1, 1, 0.4))
	if shield > 0:
		draw_arc(player_pos + off, 22.0, 0.0, TAU, 32, Color(0.4, 0.6, 1.0), 3.0)
	if frenzy_beats > 0:
		draw_arc(player_pos + off, 28.0, 0.0, TAU, 32, Color(1.0, 0.6, 0.2), 2.0)
	# fx
	var font := ThemeDB.fallback_font
	for f in fxs:
		var k := f.life / f.max_life
		match f.kind:
			"ring":
				draw_arc(f.pos + off, f.radius * (1.0 - k * 0.6), 0.0, TAU, 48, Color(f.color, k), 4.0)
			"line":
				draw_line(f.pos + off, f.to + off, Color(f.color, k), 3.0)
			"text":
				draw_string(font, f.pos + off + Vector2(-40, -30.0 * (1.0 - k)), f.text, HORIZONTAL_ALIGNMENT_CENTER, 80.0, 18, Color(f.color, k))

# ---- drawing: HUD ----------------------------------------------------------

func draw_hud(c: Control) -> void:
	var f := ThemeDB.fallback_font
	if state == State.TITLE:
		_center(c, f, "BEAT DECK SURVIVORS", 200.0, 56, Color(0.9, 0.8, 1.0))
		_center(c, f, "Survive the swarm. Play cards ON THE BEAT.", 270.0, 24, Color.WHITE)
		_center(c, f, "Move: WASD / Arrows     Cards: 1-5 or click     Tune timing: [ ]", 330.0, 20, Color(0.8, 0.8, 0.9))
		_center(c, f, "Perfect = x1.5 power, combo adds damage. Miss = x0.6 and combo reset.", 365.0, 20, Color(0.8, 0.8, 0.9))
		_center(c, f, "Press ENTER / click to start", 450.0, 28, Color(1.0, 0.9, 0.4))
		return

	# top-left stats
	c.draw_rect(Rect2(20, 20, 220, 18), Color(0.2, 0.08, 0.1))
	c.draw_rect(Rect2(20, 20, 220.0 * maxf(0, hp) / max_hp, 18), Color(0.85, 0.25, 0.3))
	c.draw_string(f, Vector2(26, 34), "HP %d/%d" % [hp, max_hp], HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
	if shield > 0:
		c.draw_string(f, Vector2(250, 34), "+%d shield" % shield, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.5, 0.7, 1.0))
	for i in MAX_ENERGY:
		var ec := Color(1.0, 0.85, 0.3) if i < energy else Color(0.25, 0.22, 0.15)
		c.draw_circle(Vector2(32 + i * 28, 62), 10.0, ec)
	c.draw_string(f, Vector2(20, 96), "Wave %d/%d   Kills %d" % [wave, MAX_WAVE, kills], HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
	if spawning and wave < MAX_WAVE:
		c.draw_string(f, Vector2(20, 118), "Time %.0f" % wave_time_left, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
	if combo > 1:
		c.draw_string(f, Vector2(W - 220, 40), "COMBO x%d" % combo, HORIZONTAL_ALIGNMENT_RIGHT, 200.0, 26, Color(1.0, 0.9, 0.3))
		c.draw_string(f, Vector2(W - 220, 62), "+%d%% dmg" % int(minf(combo, 20.0) * 2.0), HORIZONTAL_ALIGNMENT_RIGHT, 200.0, 14, Color(1.0, 0.9, 0.6))
	if frenzy_beats > 0:
		c.draw_string(f, Vector2(W - 220, 84), "FRENZY %d" % frenzy_beats, HORIZONTAL_ALIGNMENT_RIGHT, 200.0, 16, Color(1.0, 0.6, 0.2))

	# rhythm lane (notes converge on center hit marker)
	var cx := W / 2.0
	var ly := 44.0
	c.draw_line(Vector2(cx - 300, ly), Vector2(cx + 300, ly), Color(1, 1, 1, 0.15), 2.0)
	var spb := Conductor.spb
	var t0 := floorf((Conductor.song_time - Conductor.offset) / spb)
	for k in range(-1, 5):
		var bt := (t0 + k) * spb
		var dt := bt - (Conductor.song_time - Conductor.offset)
		var dx := dt * 220.0
		var a := clampf(1.0 - absf(dx) / 320.0, 0.0, 1.0)
		for s in [-1.0, 1.0]:
			c.draw_circle(Vector2(cx + s * dx, ly), 8.0, Color(0.6, 0.9, 1.0, a))
	var near := absf(Conductor.beat_offset()) <= PERFECT_WINDOW
	c.draw_arc(Vector2(cx, ly), 14.0, 0.0, TAU, 32, Color(1.0, 0.9, 0.3) if near else Color(1, 1, 1, 0.6), 3.0)

	# banner
	if banner_time > 0.0:
		_center(c, f, banner, 160.0, 48, Color(1, 1, 1, minf(1.0, banner_time)))

	if state == State.PLAYING or state == State.REWARD:
		_draw_hand(c, f)
	if state == State.REWARD:
		c.draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, 0.6))
		_center(c, f, "WAVE %d CLEARED - choose a card" % wave, 130.0, 36, Color(1, 1, 0.8))
		for i in reward_options.size():
			_draw_card(c, f, reward_rect(i), reward_options[i], str(i + 1), true)
		var rr := rest_rect()
		c.draw_rect(rr, Color(0.15, 0.3, 0.2))
		c.draw_rect(rr, Color(0.5, 0.9, 0.6), false, 2.0)
		c.draw_string(f, rr.position + Vector2(0, 35), "[4] Rest: heal 15 HP", HORIZONTAL_ALIGNMENT_CENTER, rr.size.x, 22)
	elif state == State.WON:
		c.draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, 0.6))
		_center(c, f, "VICTORY!", 280.0, 72, Color(1, 0.9, 0.4))
		_center(c, f, "Kills %d   Deck size %d   Press ENTER to play again" % [kills, deck.total_cards()], 350.0, 22, Color.WHITE)
	elif state == State.LOST:
		c.draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, 0.6))
		_center(c, f, "DEFEATED", 280.0, 72, Color(0.9, 0.3, 0.3))
		_center(c, f, "Reached wave %d   Kills %d   Press ENTER to retry" % [wave, kills], 350.0, 22, Color.WHITE)

func _draw_hand(c: Control, f: Font) -> void:
	for i in HAND_SIZE:
		var id := deck.hand[i]
		if id != "":
			_draw_card(c, f, card_rect(i), id, str(i + 1), energy >= int((Cards.DB[id] as Dictionary)["cost"]))
	c.draw_string(f, Vector2(20, H - 40), "Draw: %d" % deck.draw_pile.size(), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.8, 0.8, 0.9))
	c.draw_string(f, Vector2(20, H - 18), "Discard: %d" % deck.discard_pile.size(), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.8, 0.8, 0.9))

func _draw_card(c: Control, f: Font, r: Rect2, id: String, key: String, usable: bool) -> void:
	var d: Dictionary = Cards.DB[id]
	var col: Color = d["color"]
	var dim := 1.0 if usable else 0.4
	c.draw_rect(r, Color(0.1, 0.09, 0.15, 0.95))
	c.draw_rect(Rect2(r.position, Vector2(r.size.x, 36)), Color(col.r * 0.6, col.g * 0.6, col.b * 0.6, dim))
	c.draw_rect(r, Color(col, dim), false, 2.0)
	c.draw_circle(r.position + Vector2(18, 18), 13.0, Color(0.15, 0.3, 0.8, dim))
	c.draw_string(f, r.position + Vector2(8, 25), str(d["cost"]), HORIZONTAL_ALIGNMENT_CENTER, 20.0, 18, Color(1, 1, 1, dim))
	c.draw_string(f, r.position + Vector2(34, 25), d["name"], HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 40.0, 16, Color(1, 1, 1, dim))
	c.draw_string(f, r.position + Vector2(10, 58), String(d["type"]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(col, dim))
	c.draw_multiline_string(f, r.position + Vector2(10, 90), d["desc"], HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 20.0, 15, -1, Color(0.9, 0.9, 0.95, dim))
	c.draw_string(f, r.position + Vector2(0, r.size.y - 8), "[" + key + "]", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 14, Color(1, 1, 1, 0.5 * dim))

func _center(c: Control, f: Font, s: String, y: float, size: int, col: Color) -> void:
	c.draw_string(f, Vector2(0, y), s, HORIZONTAL_ALIGNMENT_CENTER, W, size, col)

# ---- headless / screenshot self-test --------------------------------------

func _run_autotest(delta: float) -> void:
	_autotest_time += delta
	match state:
		State.PLAYING:
			# play a random affordable card whenever we are near a beat
			if absf(Conductor.beat_offset()) < 0.03:
				var slot := randi() % HAND_SIZE
				var id := deck.hand[slot]
				if id != "" and energy >= int((Cards.DB[id] as Dictionary)["cost"]):
					try_play(slot)
		State.REWARD:
			pick_reward(0)
		State.WON, State.LOST:
			print("AUTOTEST result=%s wave=%d kills=%d hp=%d deck=%d t=%.1f" % [State.keys()[state], wave, kills, hp, deck.total_cards(), _autotest_time])
			get_tree().quit()
	if _shot_path != "" and _autotest_time > 10.0:
		get_viewport().get_texture().get_image().save_png(_shot_path)
		print("shot saved")
		_shot_path = ""
	if _autotest_time > 400.0:
		print("AUTOTEST timeout state=%s wave=%d kills=%d hp=%d" % [State.keys()[state], wave, kills, hp])
		get_tree().quit()
