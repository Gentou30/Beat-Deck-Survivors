extends Node2D
## Game flow / screens. Battles live in battle.gd; this file is menus, map, shop, events, etc.

const W := 1280.0
const H := 720.0
const SL_X := 480.0
const SL_W := 420.0

enum S { MENU, MODE, CHAR, SETTINGS, CALIB, MAP, BATTLE, REWARD, REST, PICK, SHOP, EVENT, TREASURE, END }

const NODE_COL := {
	"battle": Color(0.9, 0.35, 0.35), "elite": Color(1.0, 0.6, 0.2), "rest": Color(0.4, 0.85, 0.5),
	"shop": Color(1.0, 0.85, 0.3), "event": Color(0.5, 0.75, 1.0), "treasure": Color(1.0, 0.8, 0.4),
	"boss": Color(0.9, 0.3, 0.7),
}
const NODE_GLYPH := {"battle": "戦", "elite": "強", "rest": "休", "shop": "店", "event": "？", "treasure": "宝", "boss": "王"}
const NODE_NAME := {"battle": "バトル", "elite": "エリート", "rest": "休憩所", "shop": "ショップ", "event": "イベント", "treasure": "宝箱", "boss": "ボス"}

var ui := Ui.new()
var state: S = S.MENU
var pending := -1
var fade := 0.0
var t := 0.0
var run := RunState.new()
var battle: Battle
var paused := false
var deck_view := false
var hud: Control
var menu_pulse := 0.0
var menu_idx := 0
var settings_return: S = S.MENU
var sel_mode := "run"
var sel_char := 0
var bg_parts: Array = []
var drag_id := ""
var tex_cache := {}
var font_res: Font

# screen data
var reward_cards: Array = []
var reward_gold := 0
var reward_relic := ""
var shop_cards: Array = []
var shop_relics: Array = []
var shop_removed := 0
var event_data: Dictionary = {}
var event_result := ""
var treasure_relic := ""
var pick_mode := "upgrade"
var pick_return: S = S.MAP
var pick_scroll := 0
var endless_queue: Array = []
var end_won := false
var calib_taps: Array = []
var calib_done := false

var _autotest := false
var _autotest_t := 0.0
var _shot_path := ""
var _screen_arg := ""

func _ready() -> void:
	randomize()
	font_res = load("res://assets/fonts/DotGothic16-Regular.ttf")
	ui.font = font_res
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Control.new()
	hud.set_script(load("res://scripts/hud.gd"))
	hud.game = self
	layer.add_child(hud)
	Conductor.beat.connect(func(_n: int) -> void: menu_pulse = 1.0)
	for i in 50:
		bg_parts.append([Vector2(randf() * W, randf() * H), 10.0 + randf() * 40.0, 2.0 + randf() * 4.0, randf()])
	var args := OS.get_cmdline_user_args()
	_autotest = "--autotest" in args
	for a in args:
		if a.begins_with("--shot="):
			_shot_path = a.substr(7)
		elif a.begins_with("--screen="):
			_screen_arg = a.substr(9)
	if not Conductor.running:
		Conductor.start()
	if _autotest:
		Engine.time_scale = 5.0 if _shot_path == "" else 1.0
		start_run("endless" if "--endless" in args else "run", Characters.ORDER[randi() % 3])
	elif _screen_arg != "":
		_debug_screen(_screen_arg)

func tex(i: int) -> Texture2D:
	if not tex_cache.has(i):
		tex_cache[i] = load(Battle.TILE_DIR % i)
	return tex_cache[i]

# ---- flow ------------------------------------------------------------------

func goto(s: S) -> void:
	pending = s
	if _autotest or _screen_arg != "":
		state = s
		pending = -1
		fade = 0.0
		_on_enter(s)

func start_run(mode: String, char_id: String) -> void:
	run = RunState.new()
	run.setup(mode, char_id)
	paused = false
	deck_view = false
	endless_queue.clear()
	Settings.stats["runs"] += 1
	if mode == "run":
		goto(S.MAP)
	else:
		_start_battle("battle")

func _start_battle(kind: String) -> void:
	if battle:
		battle.dispose()
	var diff := 1.0
	if run.mode == "run":
		diff = 1.0 + maxf(0.0, run.floor_idx) * 0.5
	else:
		diff = 1.0 + run.wave * 0.35
	battle = Battle.new()
	battle.setup(run, kind, diff, ui)
	if _autotest:
		battle.bot_dir = Callable(self, "_bot_dir")
	battle.finished.connect(_on_battle_done.bind(kind))
	paused = false
	goto(S.BATTLE)

func _on_battle_done(won: bool, kind: String) -> void:
	battle.dispose()
	run.battles += 1
	if not won:
		_end_run(false)
		return
	if kind == "boss":
		_end_run(true)
		return
	var base := 14 + randi() % 8
	if kind == "elite":
		base = 32 + randi() % 10
	base += battle.kills / 15
	reward_gold = run.gain_gold(base)
	reward_relic = ""
	if kind == "elite":
		var r := Relics.random_ids(1, run.relics)
		if not r.is_empty():
			reward_relic = r[0]
	reward_cards = Cards.random_choices(3)
	if run.mode == "endless":
		run.wave += 1
	Conductor.play_sfx("win")
	goto(S.REWARD)

func _end_run(won: bool) -> void:
	end_won = won
	var st: Dictionary = Settings.stats
	if run.mode == "run":
		st["best_floor"] = maxi(st["best_floor"], run.floor_idx + (1 if won else 0))
		if won:
			st["wins"] += 1
	else:
		st["endless_best"] = maxi(st["endless_best"], run.wave)
	st["best_kills"] = maxi(st["best_kills"], run.kills)
	Settings.save_cfg()
	goto(S.END)

func proceed() -> void:
	deck_view = false
	if run.mode == "run":
		goto(S.MAP)
		return
	if endless_queue.is_empty():
		var w := run.wave
		if w % 4 == 0 and w > 0:
			endless_queue.append("shop")
		if w % 3 == 0 and w > 0:
			endless_queue.append("rest")
		endless_queue.append("elite" if (w + 1) % 5 == 0 else "battle")
	var nxt: String = endless_queue.pop_front()
	_enter_type(nxt)

func _enter_type(k: String) -> void:
	match k:
		"battle", "elite", "boss":
			_start_battle(k)
		"rest":
			goto(S.REST)
		"shop":
			_gen_shop()
			goto(S.SHOP)
		"event":
			event_data = _events().pick_random()
			event_result = ""
			goto(S.EVENT)
		"treasure":
			var r := Relics.random_ids(1, run.relics)
			treasure_relic = r[0] if not r.is_empty() else ""
			goto(S.TREASURE)

func _enter_node(j: int) -> void:
	run.floor_idx += 1
	run.node_idx = j
	var node: Dictionary = run.map[run.floor_idx][j]
	node["visited"] = true
	_enter_type(node["type"])

func _gen_shop() -> void:
	shop_cards.clear()
	for id in Cards.random_choices(4):
		shop_cards.append({"id": id, "price": Cards.price(id) + randi() % 10, "sold": false})
	shop_relics.clear()
	for id in Relics.random_ids(2, run.relics):
		shop_relics.append({"id": id, "price": int(Relics.DB[id]["price"]) + randi() % 20, "sold": false})
	shop_removed = 0

func _events() -> Array:
	return [
		{"title": "さすらいの吟遊詩人", "text": "路上でリュートを弾く吟遊詩人が、こちらをじっと見ている。",
			"opts": [["聴く: HPを15回復", "heal15"], ["ヤジを飛ばす: 30G獲得 / HP-8", "heckle"]]},
		{"title": "低音の祭壇", "text": "重低音を響かせる古い祭壇。捧げ物を求めているようだ。",
			"opts": [["最大HP-10を捧げる: レリックを得る", "shrine"], ["立ち去る", "leave"]]},
		{"title": "呪われたアンプ", "text": "不気味に唸るアンプ。触れると力が湧いてきそうだ。",
			"opts": [["触れる: カード1枚を強化 / HP-10", "amp"], ["立ち去る", "leave"]]},
		{"title": "怪しい宝箱", "text": "鍵のかかっていない宝箱。罠かもしれない。",
			"opts": [["開ける: 50%で70G / 50%でHP-15", "chest"], ["無視する", "leave"]]},
		{"title": "カード商人", "text": "「いい曲(カード)があるよ。持ち札を整理するのもアリさ」",
			"opts": [["30Gでカードを1枚買う", "dealer_buy"], ["カード1枚を無料で削除", "dealer_remove"], ["立ち去る", "leave"]]},
	]

func _event_choice(e: String) -> void:
	match e:
		"heal15":
			run.heal(15)
			event_result = "心が安らぎ、HPが15回復した。"
		"heckle":
			run.gain_gold(30)
			run.hp = maxi(1, run.hp - 8)
			event_result = "投げ銭を奪い取った。30G獲得、HPが8減った。"
		"shrine":
			if run.max_hp > 20:
				run.max_hp -= 10
				run.hp = mini(run.hp, run.max_hp)
				var r := Relics.random_ids(1, run.relics)
				if not r.is_empty():
					run.add_relic(r[0])
					event_result = "祭壇が応えた。レリック「%s」を得た。" % Relics.DB[r[0]]["name"]
			else:
				event_result = "祭壇は何も応えなかった。"
		"amp":
			var ups: Array = []
			for i in run.deck.size():
				if not Cards.is_upgraded(run.deck[i]):
					ups.append(i)
			if ups.is_empty():
				event_result = "何も起こらなかった。"
			else:
				var i: int = ups.pick_random()
				run.deck[i] = Cards.upgrade(run.deck[i])
				run.hp = maxi(1, run.hp - 10)
				event_result = "「%s」が強化された。HPが10減った。" % Cards.def(run.deck[i])["name"]
		"chest":
			if randf() < 0.5:
				run.gain_gold(70)
				event_result = "金貨が詰まっていた！ 70G獲得。"
			else:
				run.hp = maxi(1, run.hp - 15)
				event_result = "罠だった！ HPが15減った。"
		"dealer_buy":
			if run.gold >= 30:
				run.gold -= 30
				var id: String = Cards.random_choices(1)[0]
				run.deck.append(id)
				event_result = "「%s」を手に入れた。" % Cards.def(id)["name"]
			else:
				event_result = "ゴールドが足りない。"
		"dealer_remove":
			pick_mode = "remove_free"
			pick_return = S.EVENT
			event_result = "カードを1枚選んで削除する。"
			pick_scroll = 0
			goto(S.PICK)
			return
		_:
			event_result = "あなたは静かに立ち去った。"

# ---- input -----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if fade > 0.3:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		_key((event as InputEventKey).keycode)
	elif event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			var p := hud.get_local_mouse_position()
			var id := ui.hit(p)
			if id.begins_with("sl:"):
				drag_id = id
				_slide(id, p.x)
			elif id != "":
				_click(id)
			elif state == S.CALIB:
				_calib_tap()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			pick_scroll += 1
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			pick_scroll = maxi(0, pick_scroll - 1)
	elif event is InputEventMouseButton and not event.pressed and drag_id != "":
		drag_id = ""
		Settings.save_cfg()
	elif event is InputEventMouseMotion and drag_id != "":
		_slide(drag_id, (event as InputEventMouseMotion).position.x)

func _slide(id: String, x: float) -> void:
	var f := clampf((x - SL_X) / SL_W, 0.0, 1.0)
	if id == "sl:music":
		Settings.music_vol = f
	else:
		Settings.sfx_vol = f
	Settings.apply()

func _key(k: int) -> void:
	if deck_view and (k == KEY_ESCAPE):
		deck_view = false
		return
	match state:
		S.MENU:
			if k == KEY_UP:
				menu_idx = (menu_idx + 2) % 3
				Conductor.play_sfx("tick")
			elif k == KEY_DOWN:
				menu_idx = (menu_idx + 1) % 3
				Conductor.play_sfx("tick")
			elif k == KEY_ENTER or k == KEY_SPACE:
				_click(["start", "settings", "quit"][menu_idx])
		S.MODE, S.CHAR:
			if k == KEY_ESCAPE:
				_click("back")
			elif state == S.CHAR and (k == KEY_LEFT or k == KEY_RIGHT):
				sel_char = (sel_char + (1 if k == KEY_RIGHT else 2)) % 3
				Conductor.play_sfx("tick")
			elif state == S.CHAR and (k == KEY_ENTER or k == KEY_SPACE):
				_click("go")
		S.SETTINGS:
			if k == KEY_ESCAPE:
				_click("back")
		S.CALIB:
			if k == KEY_SPACE or k == KEY_ENTER:
				_calib_tap()
			elif k == KEY_ESCAPE:
				_click("back")
		S.BATTLE:
			if k == KEY_ESCAPE:
				_toggle_pause()
			elif not paused and k >= KEY_1 and k <= KEY_5:
				battle.try_play(k - KEY_1)
		S.REWARD:
			if k >= KEY_1 and k <= KEY_3:
				_click("rw:%d" % (k - KEY_1))
			elif k == KEY_SPACE or k == KEY_S:
				_click("skip")
		S.PICK:
			if k == KEY_ESCAPE and pick_mode != "remove_free":
				_click("back")
		S.END:
			if k == KEY_ENTER:
				_click("menu")

func _toggle_pause() -> void:
	paused = not paused
	Conductor.set_paused(paused)
	Conductor.play_sfx("open")

func _click(id: String) -> void:
	if pending >= 0:
		return
	Conductor.play_sfx("select")
	if id.begins_with("hand:"):
		if not paused:
			battle.try_play(int(id.substr(5)))
		return
	if id == "deck":
		deck_view = true
		return
	if id == "deck_close":
		deck_view = false
		return
	match id:
		"start":
			goto(S.MODE)
		"settings":
			settings_return = S.MENU
			goto(S.SETTINGS)
		"quit":
			get_tree().quit()
		"mode:run", "mode:endless":
			sel_mode = id.substr(5)
			goto(S.CHAR)
		"back":
			match state:
				S.MODE: goto(S.MENU)
				S.CHAR: goto(S.MODE)
				S.SETTINGS: goto(settings_return)
				S.CALIB: goto(S.SETTINGS)
				S.PICK: goto(pick_return)
		"go":
			start_run(sel_mode, Characters.ORDER[sel_char])
		"menu":
			if battle:
				battle.dispose()
			goto(S.MENU)
		"retry":
			start_run(run.mode, run.char_id)
		"pause":
			_toggle_pause()
		"resume":
			_toggle_pause()
		"p_settings":
			settings_return = S.BATTLE
			goto(S.SETTINGS)
		"abandon":
			paused = false
			Conductor.set_paused(false)
			_end_run(false)
		"off-":
			Settings.offset_ms = maxi(-200, Settings.offset_ms - 5)
		"off+":
			Settings.offset_ms = mini(200, Settings.offset_ms + 5)
		"shake":
			Settings.shake = not Settings.shake
			Settings.save_cfg()
		"fullscreen":
			Settings.fullscreen = not Settings.fullscreen
			Settings.apply()
			Settings.save_cfg()
		"calib":
			calib_taps.clear()
			calib_done = false
			goto(S.CALIB)
		"calib_retry":
			calib_taps.clear()
			calib_done = false
		"skip":
			proceed()
		"relic_take":
			run.add_relic(reward_relic)
			reward_relic = ""
		"leave":
			proceed()
		"rest:heal":
			run.heal(int(run.max_hp * 0.3))
			proceed()
		"rest:upgrade":
			pick_mode = "upgrade"
			pick_return = S.REST
			pick_scroll = 0
			goto(S.PICK)
		"remove":
			pick_mode = "remove"
			pick_return = S.SHOP
			pick_scroll = 0
			goto(S.PICK)
		"treasure_take":
			if treasure_relic != "":
				run.add_relic(treasure_relic)
			proceed()
		"event_done":
			proceed()
		_:
			_click_prefixed(id)

func _click_prefixed(id: String) -> void:
	if id.begins_with("rw:"):
		var i := int(id.substr(3))
		run.deck.append(reward_cards[i])
		proceed()
	elif id.begins_with("node:"):
		_enter_node(int(id.substr(5)))
	elif id.begins_with("char:"):
		sel_char = int(id.substr(5))
	elif id.begins_with("buy:c"):
		var it: Dictionary = shop_cards[int(id.substr(5))]
		if not it["sold"] and run.gold >= it["price"]:
			run.gold -= it["price"]
			it["sold"] = true
			run.deck.append(it["id"])
			Conductor.play_sfx("win")
	elif id.begins_with("buy:r"):
		var it: Dictionary = shop_relics[int(id.substr(5))]
		if not it["sold"] and run.gold >= it["price"]:
			run.gold -= it["price"]
			it["sold"] = true
			run.add_relic(it["id"])
			Conductor.play_sfx("win")
	elif id.begins_with("ev:"):
		_event_choice(event_data["opts"][int(id.substr(3))][1])
	elif id.begins_with("pick:"):
		_pick_card(int(id.substr(5)))

func _pick_card(i: int) -> void:
	if i >= run.deck.size():
		return
	match pick_mode:
		"upgrade":
			if Cards.is_upgraded(run.deck[i]):
				return
			run.deck[i] = Cards.upgrade(run.deck[i])
			proceed()
		"remove":
			var cost := 50 + 25 * shop_removed
			if run.gold < cost or run.deck.size() <= 5:
				return
			run.gold -= cost
			shop_removed += 1
			run.deck.remove_at(i)
			goto(S.SHOP)
		"remove_free":
			if run.deck.size() <= 5:
				return
			run.deck.remove_at(i)
			event_result = "カードを1枚削除した。"
			goto(S.EVENT)

func _calib_tap() -> void:
	if calib_done:
		return
	var raw := Conductor.raw_beat_offset()
	if absf(raw) > 0.25:
		return
	calib_taps.append(raw)
	Conductor.play_sfx("tick")
	if calib_taps.size() >= 10:
		var arr := calib_taps.duplicate()
		arr.sort()
		var med: float = (arr[4] + arr[5]) / 2.0
		Settings.offset_ms = clampi(int(med * 1000.0), -200, 200)
		Settings.save_cfg()
		calib_done = true

# ---- loop ------------------------------------------------------------------

func _process(delta: float) -> void:
	t += delta
	menu_pulse = maxf(0.0, menu_pulse - delta * 4.0)
	if pending >= 0:
		fade += delta * 7.0
		if fade >= 1.0:
			state = pending as S
			pending = -1
			_on_enter(state)
	elif fade > 0.0:
		fade = maxf(0.0, fade - delta * 5.0)
	for p in bg_parts:
		p[0].y -= p[1] * delta
		if p[0].y < -10.0:
			p[0] = Vector2(randf() * W, H + 10.0)
	if state == S.BATTLE and battle and not paused:
		battle.update(delta)
	if _autotest or _shot_path != "":
		_run_autotest(delta)
	queue_redraw()

func _on_enter(s: S) -> void:
	if s == S.BATTLE and battle == null:
		state = S.MENU
	if s == S.MENU:
		menu_idx = 0
	if s == S.PICK:
		pick_scroll = 0

func _draw() -> void:
	if state == S.BATTLE and battle:
		battle.draw_world(self)

# ---- HUD / screens ---------------------------------------------------------

func draw_hud(c: Control) -> void:
	ui.begin(c, get_process_delta_time())
	match state:
		S.MENU: _draw_menu(c)
		S.MODE: _draw_mode(c)
		S.CHAR: _draw_char(c)
		S.SETTINGS: _draw_settings(c)
		S.CALIB: _draw_calib(c)
		S.MAP: _draw_map(c)
		S.BATTLE:
			if battle:
				battle.draw_hud(c)
				_relic_tips(c)
				if paused:
					_draw_pause(c)
		S.REWARD: _draw_reward(c)
		S.REST: _draw_rest(c)
		S.PICK: _draw_pick(c)
		S.SHOP: _draw_shop(c)
		S.EVENT: _draw_event(c)
		S.TREASURE: _draw_treasure(c)
		S.END: _draw_end(c)
	if deck_view:
		_draw_deck_overlay(c)
	if fade > 0.0:
		c.draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, clampf(fade, 0.0, 1.0)))

func _bg(c: Control, tint := Color(0.07, 0.05, 0.14)) -> void:
	c.draw_rect(Rect2(0, 0, W, H), tint)
	var pul := menu_pulse
	c.draw_polygon(PackedVector2Array([Vector2(0, H * 0.55), Vector2(W, H * 0.55), Vector2(W, H), Vector2(0, H)]),
		PackedColorArray([Color(tint, 0.0), Color(tint, 0.0), Color(0.3, 0.15, 0.5, 0.35 + 0.15 * pul), Color(0.3, 0.15, 0.5, 0.35 + 0.15 * pul)]))
	var gc := Color(0.6, 0.45, 1.0, 0.05 + 0.1 * pul)
	var scroll := fmod(t * 20.0, 64.0)
	for x in range(0, int(W) + 64, 64):
		c.draw_line(Vector2(x, 0), Vector2(x, H), gc)
	for y in range(-64, int(H) + 64, 64):
		c.draw_line(Vector2(0, y + scroll), Vector2(W, y + scroll), gc)
	for p in bg_parts:
		var a: float = 0.15 + 0.4 * p[3]
		c.draw_rect(Rect2(p[0], Vector2(p[2], p[2])), Color(1.0, 0.8, 0.5, a))

func _logo(c: Control, y: float) -> void:
	var s := 72 + int(8.0 * menu_pulse)
	ui.text(c, "BEAT DECK", Vector2(0, y), s, Color(1.0, 0.85, 0.4), HORIZONTAL_ALIGNMENT_CENTER, W)
	ui.text(c, "SURVIVORS", Vector2(0, y + 70), s, Color(0.75, 0.55, 1.0), HORIZONTAL_ALIGNMENT_CENTER, W)

func _dancers(c: Control, y: float) -> void:
	var tiles := [84, 87, 112, 108, 120, 121, 122, 109, 110]
	for i in tiles.size():
		var x := 140.0 + i * 125.0
		var bob := absf(sin(t * 4.0 + i * 0.7)) * 14.0 * (0.5 + menu_pulse)
		c.draw_texture_rect(tex(tiles[i]), Rect2(x, y - bob, 64, 64), false)

func _draw_menu(c: Control) -> void:
	_bg(c)
	_logo(c, 150.0)
	ui.center(c, "ビートに乗って、デッキで生き残れ。", 280.0, 22, Color(0.85, 0.85, 1.0))
	var labels := ["はじめる", "設定", "終了"]
	var ids := ["start", "settings", "quit"]
	for i in 3:
		var r := Rect2(W / 2.0 - 160.0, 330.0 + i * 70.0, 320.0, 56.0)
		ui.button(c, ids[i], r, labels[i], true, Color(1.0, 0.8, 0.35) if i == menu_idx else Color(0.55, 0.5, 0.95), 26)
		if ui.is_hover(ids[i]):
			menu_idx = i
	_dancers(c, 560.0)
	var st: Dictionary = Settings.stats
	ui.center(c, "プレイ %d回   クリア %d回   最高到達 %d階   エンドレス最高 %dウェーブ   最多撃破 %d" % [st["runs"], st["wins"], st["best_floor"], st["endless_best"], st["best_kills"]], 665.0, 14, Color(0.7, 0.7, 0.85))
	ui.text(c, "CC0素材: Kenney / Joth", Vector2(16, H - 12), 11, Color(0.5, 0.5, 0.65))

func _draw_mode(c: Control) -> void:
	_bg(c)
	ui.center(c, "モード選択", 100.0, 44, Color(1, 0.9, 0.6))
	var modes := [
		["mode:run", "ステージ攻略", "10階層のマップを進み、最上階のボスを倒せ。\nバトル・エリート・休憩・ショップ・イベント・宝箱。\nデッキとレリックを育てる本格モード。", Color(0.9, 0.5, 0.4), 84],
		["mode:endless", "エンドレス", "ウェーブが延々と続くサバイバル。\n勝ち抜くごとにカード報酬、時々ショップと休憩。\nどこまで生き延びられる？", Color(0.5, 0.8, 1.0), 108],
	]
	for i in 2:
		var m: Array = modes[i]
		var r := Rect2(190.0 + i * 450.0, 170.0, 410.0, 380.0)
		ui.button(c, m[0], r, "", true, m[3])
		c.draw_texture_rect(tex(m[4]), Rect2(r.position.x + r.size.x / 2.0 - 48.0, r.position.y + 30.0 - absf(sin(t * 3.0 + i)) * 8.0, 96, 96), false)
		ui.text(c, m[1], Vector2(r.position.x, r.position.y + 170.0), 34, m[3], HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		c.draw_multiline_string(font_res, Vector2(r.position.x + 24.0, r.position.y + 220.0), m[2], HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 48.0, 17, -1, Color(0.9, 0.9, 0.95))
		if i == 0:
			ui.text(c, "クリア %d回 / 最高 %d階" % [Settings.stats["wins"], Settings.stats["best_floor"]], Vector2(r.position.x, r.position.y + 350.0), 14, Color(0.8, 0.8, 0.9), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		else:
			ui.text(c, "最高 %dウェーブ" % Settings.stats["endless_best"], Vector2(r.position.x, r.position.y + 350.0), 14, Color(0.8, 0.8, 0.9), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	ui.button(c, "back", Rect2(40, H - 80, 160, 48), "もどる", true, Color(0.6, 0.6, 0.8), 20)

func _draw_char(c: Control) -> void:
	_bg(c)
	ui.center(c, "キャラクター選択", 80.0, 44, Color(1, 0.9, 0.6))
	for i in 3:
		var cd: Dictionary = Characters.DB[Characters.ORDER[i]]
		var col: Color = cd["color"]
		var r := Rect2(70.0 + i * 385.0, 120.0, 350.0, 450.0)
		var sel := i == sel_char
		ui.button(c, "char:%d" % i, r, "", true, col)
		if sel:
			c.draw_rect(r.grow(5.0), Color(col, 0.5 + 0.4 * menu_pulse), false, 4.0)
		var bob := absf(sin(t * 4.0 + i)) * (14.0 if sel else 3.0)
		c.draw_texture_rect(tex(int(cd["tile"])), Rect2(r.position.x + r.size.x / 2.0 - 56.0, r.position.y + 24.0 - bob, 112, 112), false)
		ui.text(c, cd["name"], Vector2(r.position.x, r.position.y + 175.0), 32, col, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		ui.text(c, "HP %d    速度 %d%%" % [cd["hp"], int(float(cd["speed"]) * 100.0)], Vector2(r.position.x, r.position.y + 205.0), 17, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		ui.text(c, "◆ " + cd["passive"], Vector2(r.position.x + 20.0, r.position.y + 245.0), 18, Color(1, 0.9, 0.5))
		c.draw_multiline_string(font_res, Vector2(r.position.x + 20.0, r.position.y + 270.0), cd["passive_desc"], HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 40.0, 15, -1, Color(0.9, 0.9, 0.95))
		var counts := {}
		for id in cd["starter"]:
			counts[id] = counts.get(id, 0) + 1
		var line := ""
		for id in counts:
			line += "%s×%d  " % [Cards.def(id)["name"], counts[id]]
		ui.text(c, "初期デッキ", Vector2(r.position.x + 20.0, r.position.y + 335.0), 14, Color(0.7, 0.8, 1.0))
		c.draw_multiline_string(font_res, Vector2(r.position.x + 20.0, r.position.y + 358.0), line, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 40.0, 13, -1, Color(0.85, 0.85, 0.9))
	ui.button(c, "back", Rect2(40, H - 80, 160, 48), "もどる", true, Color(0.6, 0.6, 0.8), 20)
	ui.button(c, "go", Rect2(W / 2.0 - 160.0, H - 90.0, 320.0, 60.0), "出発！", true, Color(1.0, 0.8, 0.35), 30)

func _draw_settings(c: Control) -> void:
	_bg(c)
	ui.center(c, "設定", 90.0, 44, Color(1, 0.9, 0.6))
	var x := 290.0
	ui.text(c, "音楽音量", Vector2(x, 190), 22, Color.WHITE)
	ui.slider(c, "sl:music", Rect2(SL_X, 176.0, SL_W, 16.0), Settings.music_vol)
	ui.text(c, "%d%%" % int(Settings.music_vol * 100.0), Vector2(SL_X + SL_W + 20.0, 192), 20, Color.WHITE)
	ui.text(c, "効果音量", Vector2(x, 250), 22, Color.WHITE)
	ui.slider(c, "sl:sfx", Rect2(SL_X, 236.0, SL_W, 16.0), Settings.sfx_vol)
	ui.text(c, "%d%%" % int(Settings.sfx_vol * 100.0), Vector2(SL_X + SL_W + 20.0, 252), 20, Color.WHITE)
	ui.text(c, "判定オフセット", Vector2(x, 320), 22, Color.WHITE)
	ui.button(c, "off-", Rect2(SL_X, 296.0, 56.0, 38.0), "－", true, Color(0.6, 0.6, 0.9), 22)
	ui.text(c, "%+d ms" % Settings.offset_ms, Vector2(SL_X + 60.0, 324), 22, Color(1, 0.9, 0.4), HORIZONTAL_ALIGNMENT_CENTER, 130.0)
	ui.button(c, "off+", Rect2(SL_X + 200.0, 296.0, 56.0, 38.0), "＋", true, Color(0.6, 0.6, 0.9), 22)
	ui.button(c, "calib", Rect2(SL_X + 270.0, 296.0, 220.0, 38.0), "自動キャリブレーション", true, Color(0.9, 0.7, 0.3), 16)
	ui.text(c, "押すのが遅れる/早いと感じたら調整。ずれが大きい時はキャリブレーションが便利です。", Vector2(x, 360), 14, Color(0.7, 0.7, 0.85))
	ui.text(c, "画面揺れ", Vector2(x, 420), 22, Color.WHITE)
	ui.button(c, "shake", Rect2(SL_X, 396.0, 160.0, 38.0), "ON" if Settings.shake else "OFF", true, Color(0.5, 0.9, 0.6) if Settings.shake else Color(0.6, 0.6, 0.7), 20)
	ui.text(c, "フルスクリーン", Vector2(x, 480), 22, Color.WHITE)
	ui.button(c, "fullscreen", Rect2(SL_X, 456.0, 160.0, 38.0), "ON" if Settings.fullscreen else "OFF", true, Color(0.5, 0.9, 0.6) if Settings.fullscreen else Color(0.6, 0.6, 0.7), 20)
	ui.button(c, "back", Rect2(W / 2.0 - 120.0, 580.0, 240.0, 52.0), "もどる", true, Color(0.55, 0.5, 0.95), 24)
	var cx := 1060.0
	c.draw_circle(Vector2(cx, 300), 30.0 + 22.0 * menu_pulse, Color(1, 0.9, 0.4, 0.15 + 0.4 * menu_pulse))
	c.draw_arc(Vector2(cx, 300), 30.0, 0.0, TAU, 32, Color(1, 1, 1, 0.7), 3.0)
	ui.text(c, "ビート", Vector2(cx - 50.0, 360), 16, Color(0.8, 0.8, 0.95), HORIZONTAL_ALIGNMENT_CENTER, 100.0)

func _draw_calib(c: Control) -> void:
	_bg(c)
	ui.center(c, "キャリブレーション", 100.0, 40, Color(1, 0.9, 0.6))
	ui.center(c, "円が光るビートに合わせて SPACE かクリックを10回。", 160.0, 20, Color.WHITE)
	var cx := W / 2.0
	var cy := 330.0
	c.draw_circle(Vector2(cx, cy), 60.0 + 40.0 * menu_pulse, Color(1, 0.9, 0.4, 0.12 + 0.45 * menu_pulse))
	c.draw_arc(Vector2(cx, cy), 60.0, 0.0, TAU, 48, Color(1, 1, 1, 0.8), 4.0)
	for i in 10:
		c.draw_circle(Vector2(cx - 135.0 + i * 30.0, 460.0), 9.0, Color(0.4, 1.0, 0.6) if i < calib_taps.size() else Color(0.3, 0.3, 0.4))
	if calib_done:
		ui.center(c, "結果: %+d ms を設定しました" % Settings.offset_ms, 520.0, 28, Color(1, 0.9, 0.4))
		ui.button(c, "calib_retry", Rect2(cx - 270.0, 570.0, 240.0, 50.0), "やり直す", true, Color(0.9, 0.7, 0.3), 22)
		ui.button(c, "back", Rect2(cx + 30.0, 570.0, 240.0, 50.0), "完了", true, Color(0.5, 0.9, 0.6), 22)
	else:
		ui.button(c, "back", Rect2(40, H - 80, 160, 48), "もどる", true, Color(0.6, 0.6, 0.8), 20)

# -- run screens -------------------------------------------------------------

func _run_bar(c: Control, show_deck := true) -> void:
	c.draw_rect(Rect2(0, 0, W, 54), Color(0.04, 0.03, 0.09, 0.9))
	c.draw_line(Vector2(0, 54), Vector2(W, 54), Color(0.5, 0.45, 0.8, 0.6), 2.0)
	var cd: Dictionary = Characters.DB[run.char_id]
	c.draw_texture_rect(tex(int(cd["tile"])), Rect2(10, 7, 40, 40), false)
	ui.bar(c, Rect2(58, 10, 200, 16), float(run.hp) / run.max_hp, Color(0.85, 0.25, 0.3))
	ui.text(c, "HP %d/%d" % [run.hp, run.max_hp], Vector2(64, 24), 13, Color.WHITE)
	ui.text(c, "%d G" % run.gold, Vector2(58, 46), 17, Color(1, 0.85, 0.3))
	var fl := "ウェーブ %d" % (run.wave + 1) if run.mode == "endless" else "%d / %d階" % [maxi(0, run.floor_idx + 1), MapGen.FLOORS + 1]
	ui.text(c, fl, Vector2(150, 46), 15, Color(0.85, 0.85, 1.0))
	for i in run.relics.size():
		ui.relic_icon(c, run.relics[i], Rect2(300 + i * 34, 12, 30, 30), "relic:%d" % i)
	if show_deck:
		ui.button(c, "deck", Rect2(W - 190, 8, 170, 38), "デッキ (%d)" % run.deck.size(), true, Color(0.5, 0.7, 1.0), 18)

func _relic_tips(c: Control) -> void:
	for i in run.relics.size():
		if ui.is_hover("relic:%d" % i):
			var d: Dictionary = Relics.DB[run.relics[i]]
			ui.tooltip(c, d["name"], d["desc"], Vector2(ui.mouse.x, ui.mouse.y))

func _draw_map(c: Control) -> void:
	_bg(c, Color(0.06, 0.05, 0.12))
	_run_bar(c)
	var nf := run.floor_idx + 1
	var avail: Array = []
	if nf <= MapGen.FLOORS:
		if run.floor_idx == -1:
			for j in run.map[0].size():
				avail.append(j)
		else:
			avail = run.map[run.floor_idx][run.node_idx]["next"]
	for f in run.map.size() - 1:
		for j in run.map[f].size():
			var a := _node_pos(f, j)
			for k in run.map[f][j]["next"]:
				var b := _node_pos(f + 1, k)
				var active: bool = f == run.floor_idx and j == run.node_idx
				c.draw_line(a, b, Color(1, 0.9, 0.5, 0.8) if active else Color(0.6, 0.55, 0.8, 0.28), 3.0 if active else 2.0)
	for f in run.map.size():
		for j in run.map[f].size():
			var node: Dictionary = run.map[f][j]
			var p := _node_pos(f, j)
			var col: Color = NODE_COL[node["type"]]
			var rad := 28.0 if node["type"] == "boss" else (22.0 if node["type"] == "elite" else 19.0)
			var can := f == nf and avail.has(j)
			var cur: bool = f == run.floor_idx and j == run.node_idx
			var dim := 0.35 if (f < nf and not cur) else (1.0 if can or cur else 0.55)
			if can:
				ui.button(c, "node:%d" % j, Rect2(p - Vector2(rad + 6, rad + 6), Vector2((rad + 6) * 2.0, (rad + 6) * 2.0)), "", true, col)
				c.draw_arc(p, rad + 6.0 + 3.0 * sin(t * 6.0), 0.0, TAU, 32, Color(1, 1, 0.7, 0.9), 3.0)
			c.draw_circle(p, rad, Color(col.r * 0.4, col.g * 0.4, col.b * 0.4, dim))
			c.draw_arc(p, rad, 0.0, TAU, 32, Color(col, dim), 3.0)
			ui.text(c, NODE_GLYPH[node["type"]], p + Vector2(-rad, 7.0), int(rad * 0.95), Color(1, 1, 1, dim), HORIZONTAL_ALIGNMENT_CENTER, rad * 2.0)
			if cur:
				c.draw_texture_rect(tex(int(Characters.DB[run.char_id]["tile"])), Rect2(p + Vector2(-16, -52 + sin(t * 5.0) * 3.0), Vector2(32, 32)), false)
	var ly := 90.0
	for k in ["battle", "elite", "rest", "shop", "event", "treasure", "boss"]:
		c.draw_circle(Vector2(36, ly), 12.0, NODE_COL[k])
		ui.text(c, NODE_NAME[k], Vector2(56, ly + 5.0), 14, Color(0.85, 0.85, 0.95))
		ly += 30.0
	ui.center(c, "進む場所を選べ", 82.0, 18, Color(1, 0.95, 0.7))
	_relic_tips(c)

func _node_pos(f: int, j: int) -> Vector2:
	var col: float = run.map[f][j]["col"]
	return Vector2(W / 2.0 + (col - 1.5) * 180.0, 650.0 - f * 52.0)

func _draw_reward(c: Control) -> void:
	_bg(c)
	_run_bar(c)
	ui.center(c, "勝利！", 110.0, 52, Color(1, 0.9, 0.4))
	ui.center(c, "+%d G 獲得  /  カードを1枚選ぼう" % reward_gold, 150.0, 22, Color(1, 0.85, 0.4))
	for i in reward_cards.size():
		ui.card(c, reward_cards[i], Rect2(W / 2.0 - 255.0 + i * 180.0, 200.0, 160.0, 250.0), str(i + 1), true, false, "rw:%d" % i)
	if reward_relic != "":
		var d: Dictionary = Relics.DB[reward_relic]
		ui.panel(c, Rect2(W / 2.0 - 260.0, 485.0, 520.0, 56.0), Color(0.1, 0.08, 0.04, 0.95), Color(1, 0.85, 0.4))
		ui.text(c, "レリック: %s - %s" % [d["name"], d["desc"]], Vector2(W / 2.0 - 250.0, 520.0), 16, Color(1, 0.95, 0.7))
		ui.button(c, "relic_take", Rect2(W / 2.0 + 280.0, 485.0, 110.0, 56.0), "受け取る", true, Color(1.0, 0.8, 0.3), 18)
	ui.button(c, "skip", Rect2(W / 2.0 - 110.0, 590.0, 220.0, 50.0), "スキップ [S]", true, Color(0.6, 0.6, 0.8), 20)
	_relic_tips(c)

func _draw_rest(c: Control) -> void:
	_bg(c, Color(0.05, 0.09, 0.07))
	_run_bar(c)
	ui.center(c, "休憩所", 130.0, 50, Color(0.5, 1.0, 0.6))
	ui.center(c, "焚き火のそばで、ひと息つく。", 175.0, 20, Color(0.85, 0.95, 0.85))
	var fx := W / 2.0
	for i in 5:
		var fy := 330.0 - fmod(t * 60.0 + i * 25.0, 90.0)
		c.draw_circle(Vector2(fx + sin(t * 3.0 + i) * 14.0, fy + 60.0), 14.0 - fmod(t * 60.0 + i * 25.0, 90.0) * 0.12, Color(1.0, 0.5 + i * 0.08, 0.2, 0.7))
	var heal := int(run.max_hp * 0.3)
	ui.button(c, "rest:heal", Rect2(W / 2.0 - 340.0, 420.0, 320.0, 110.0), "休む  HP +%d" % heal, true, Color(0.4, 0.9, 0.5), 24)
	var can_up := false
	for id in run.deck:
		if not Cards.is_upgraded(id):
			can_up = true
	ui.button(c, "rest:upgrade", Rect2(W / 2.0 + 20.0, 420.0, 320.0, 110.0), "鍛える  カード強化", can_up, Color(1.0, 0.8, 0.35), 24)
	_relic_tips(c)

func _draw_pick(c: Control) -> void:
	_bg(c)
	_run_bar(c, false)
	var title := "強化するカードを選ぶ"
	if pick_mode == "remove":
		title = "削除するカードを選ぶ (%dG)" % (50 + 25 * shop_removed)
	elif pick_mode == "remove_free":
		title = "削除するカードを選ぶ (無料)"
	ui.center(c, title, 92.0, 30, Color(1, 0.9, 0.6))
	_deck_grid(c, true)
	if pick_mode != "remove_free":
		ui.button(c, "back", Rect2(40, H - 70, 160, 48), "やめる", true, Color(0.6, 0.6, 0.8), 20)

func _deck_grid(c: Control, clickable: bool) -> void:
	var cols := 4
	var cw := 290.0
	var ch := 54.0
	var rows_vis := 8
	var total_rows := int(ceil(run.deck.size() / float(cols)))
	pick_scroll = clampi(pick_scroll, 0, maxi(0, total_rows - rows_vis))
	var x0 := (W - cols * cw) / 2.0 + 4.0
	var idx_sorted: Array = range(run.deck.size())
	idx_sorted.sort_custom(func(a: int, b: int) -> bool: return Cards.base_id(run.deck[a]) < Cards.base_id(run.deck[b]))
	for n in idx_sorted.size():
		var row := n / cols - pick_scroll
		if row < 0 or row >= rows_vis:
			continue
		var i: int = idx_sorted[n]
		var r := Rect2(x0 + (n % cols) * cw, 130.0 + row * (ch + 6.0), cw - 8.0, ch)
		var ok := clickable and (pick_mode != "upgrade" or not Cards.is_upgraded(run.deck[i]))
		var rid := "pick:%d" % i if ok else ""
		ui.mini_card(c, run.deck[i], r, rid)
	if total_rows > rows_vis:
		ui.text(c, "マウスホイールでスクロール (%d/%d)" % [pick_scroll + 1, total_rows - rows_vis + 1], Vector2(0, H - 24.0), 14, Color(0.7, 0.7, 0.85), HORIZONTAL_ALIGNMENT_CENTER, W)

func _draw_deck_overlay(c: Control) -> void:
	c.draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, 0.85))
	ui.center(c, "デッキ (%d枚)" % run.deck.size(), 92.0, 30, Color(1, 0.9, 0.6))
	ui.buttons.clear()
	_deck_grid(c, false)
	ui.button(c, "deck_close", Rect2(W / 2.0 - 100.0, H - 70.0, 200.0, 48), "閉じる", true, Color(0.6, 0.6, 0.8), 20)

func _draw_shop(c: Control) -> void:
	_bg(c, Color(0.1, 0.08, 0.04))
	_run_bar(c)
	ui.center(c, "ショップ", 100.0, 44, Color(1, 0.9, 0.4))
	for i in shop_cards.size():
		var it: Dictionary = shop_cards[i]
		var r := Rect2(95.0 + i * 190.0, 140.0, 170.0, 230.0)
		if it["sold"]:
			ui.text(c, "売り切れ", r.position + Vector2(0, 110), 20, Color(0.6, 0.6, 0.6), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		else:
			ui.card(c, it["id"], r, "", run.gold >= it["price"], false, "buy:c%d" % i)
			ui.text(c, "%d G" % it["price"], r.position + Vector2(0, 258), 20, Color(1, 0.85, 0.3) if run.gold >= it["price"] else Color(0.7, 0.4, 0.4), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	for i in shop_relics.size():
		var it: Dictionary = shop_relics[i]
		var d: Dictionary = Relics.DB[it["id"]]
		var r := Rect2(880.0, 150.0 + i * 120.0, 300.0, 100.0)
		if it["sold"]:
			ui.text(c, "売り切れ", r.position + Vector2(0, 55), 20, Color(0.6, 0.6, 0.6), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
			continue
		ui.button(c, "buy:r%d" % i, r, "", run.gold >= it["price"], d["color"])
		ui.text(c, d["name"], r.position + Vector2(14, 28), 20, d["color"])
		c.draw_multiline_string(font_res, r.position + Vector2(14, 50), d["desc"], HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 28.0, 14, -1, Color(0.9, 0.9, 0.95))
		ui.text(c, "%d G" % it["price"], r.position + Vector2(0, 92), 18, Color(1, 0.85, 0.3) if run.gold >= it["price"] else Color(0.7, 0.4, 0.4), HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 12.0)
	var rc := 50 + 25 * shop_removed
	ui.button(c, "remove", Rect2(95.0, 470.0, 340.0, 60.0), "カードを削除 (%d G)" % rc, run.gold >= rc and run.deck.size() > 5, Color(0.9, 0.5, 0.5), 20)
	ui.button(c, "leave", Rect2(W / 2.0 - 110.0, 600.0, 220.0, 52.0), "店を出る", true, Color(0.6, 0.6, 0.8), 22)
	_relic_tips(c)

func _draw_event(c: Control) -> void:
	_bg(c, Color(0.07, 0.06, 0.12))
	_run_bar(c)
	ui.center(c, event_data["title"], 150.0, 42, Color(0.6, 0.85, 1.0))
	ui.center(c, event_data["text"], 210.0, 20, Color(0.9, 0.9, 1.0))
	if event_result == "":
		var opts: Array = event_data["opts"]
		for i in opts.size():
			ui.button(c, "ev:%d" % i, Rect2(W / 2.0 - 320.0, 290.0 + i * 76.0, 640.0, 62.0), opts[i][0], true, Color(0.55, 0.7, 1.0), 20)
	else:
		ui.center(c, event_result, 330.0, 24, Color(1, 0.95, 0.7))
		ui.button(c, "event_done", Rect2(W / 2.0 - 110.0, 440.0, 220.0, 52.0), "進む", true, Color(0.5, 0.9, 0.6), 22)
	_relic_tips(c)

func _draw_treasure(c: Control) -> void:
	_bg(c, Color(0.09, 0.07, 0.03))
	_run_bar(c)
	ui.center(c, "宝箱", 150.0, 50, Color(1, 0.85, 0.4))
	if treasure_relic != "":
		var d: Dictionary = Relics.DB[treasure_relic]
		var r := Rect2(W / 2.0 - 90.0, 230.0 + sin(t * 3.0) * 6.0, 180.0, 180.0)
		c.draw_circle(r.get_center(), 110.0 + 10.0 * menu_pulse, Color(d["color"], 0.18))
		ui.relic_icon(c, treasure_relic, r, "tr")
		ui.center(c, d["name"], 450.0, 32, d["color"])
		ui.center(c, d["desc"], 490.0, 20, Color.WHITE)
	else:
		ui.center(c, "中は空っぽだった…", 300.0, 26, Color.WHITE)
	ui.button(c, "treasure_take", Rect2(W / 2.0 - 120.0, 560.0, 240.0, 56.0), "受け取る", true, Color(1.0, 0.8, 0.3), 24)

func _draw_pause(c: Control) -> void:
	c.draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, 0.65))
	ui.center(c, "ポーズ", 200.0, 56, Color(1, 0.95, 0.8))
	ui.button(c, "resume", Rect2(W / 2.0 - 160.0, 270.0, 320.0, 56.0), "再開", true, Color(0.5, 0.9, 0.6), 26)
	ui.button(c, "p_settings", Rect2(W / 2.0 - 160.0, 340.0, 320.0, 56.0), "設定", true, Color(0.55, 0.5, 0.95), 26)
	ui.button(c, "abandon", Rect2(W / 2.0 - 160.0, 410.0, 320.0, 56.0), "あきらめる", true, Color(0.9, 0.4, 0.4), 26)

func _draw_end(c: Control) -> void:
	_bg(c, Color(0.05, 0.1, 0.06) if end_won else Color(0.12, 0.04, 0.05))
	ui.center(c, "VICTORY!" if end_won else "GAME OVER", 150.0, 80, Color(1, 0.9, 0.4) if end_won else Color(0.9, 0.3, 0.35))
	var cd: Dictionary = Characters.DB[run.char_id]
	c.draw_texture_rect(tex(int(cd["tile"])), Rect2(W / 2.0 - 40.0, 200.0, 80, 80), false)
	var lines: Array = []
	if run.mode == "run":
		lines.append("到達階層: %d / %d" % [maxi(0, run.floor_idx + 1), MapGen.FLOORS + 1])
	else:
		lines.append("到達ウェーブ: %d" % (run.wave + 1))
	lines.append("撃破数: %d    戦闘数: %d" % [run.kills, run.battles])
	lines.append("デッキ: %d枚    レリック: %d個    所持金: %dG" % [run.deck.size(), run.relics.size(), run.gold])
	for i in lines.size():
		ui.center(c, lines[i], 330.0 + i * 36.0, 24, Color.WHITE)
	ui.button(c, "retry", Rect2(W / 2.0 - 330.0, 520.0, 300.0, 60.0), "もう一度", true, Color(1.0, 0.8, 0.35), 26)
	ui.button(c, "menu", Rect2(W / 2.0 + 30.0, 520.0, 300.0, 60.0), "メニューへ", true, Color(0.55, 0.5, 0.95), 26)

# ---- headless / screenshot self-test --------------------------------------

func _bot_dir() -> Vector2:
	var v := (Vector2(W / 2.0, 220.0) - battle.player_pos) * 0.002
	for e in battle.enemies:
		var d: float = e.pos.distance_to(battle.player_pos)
		if d < 200.0:
			v += (battle.player_pos - e.pos).normalized() * (200.0 - d) / 200.0
	return v

func _debug_screen(sname: String) -> void:
	run = RunState.new()
	run.setup("run", "wizard")
	run.gold = 180
	for id in ["frenzy", "heavy", "leech", "echo", "resonance+"]:
		run.deck.append(id)
	run.relics = ["metronome", "sword", "coin"]
	run.floor_idx = 2
	run.node_idx = 0
	run.map[0][0]["visited"] = true
	match sname:
		"menu": state = S.MENU
		"mode": state = S.MODE
		"char": state = S.CHAR
		"settings": state = S.SETTINGS
		"map": state = S.MAP
		"reward":
			reward_cards = ["heavy", "echo", "aura"]
			reward_gold = 23
			reward_relic = "fang"
			state = S.REWARD
		"shop":
			_gen_shop()
			state = S.SHOP
		"event":
			event_data = _events()[0]
			state = S.EVENT
		"rest": state = S.REST
		"pick": state = S.PICK
		"end":
			end_won = true
			state = S.END
		_:
			_start_battle(sname if sname in ["boss", "elite"] else "battle")

func _run_autotest(delta: float) -> void:
	_autotest_t += delta
	if _shot_path != "" and _autotest_t > (7.0 if _screen_arg in ["boss", "elite", "battle"] else 1.0) and pending < 0:
		get_viewport().get_texture().get_image().save_png(_shot_path)
		print("shot saved")
		get_tree().quit()
		return
	if not _autotest or pending >= 0 or _shot_path != "":
		return
	match state:
		S.MAP:
			var avail: Array = []
			if run.floor_idx == -1:
				for j in run.map[0].size():
					avail.append(j)
			else:
				avail = run.map[run.floor_idx][run.node_idx]["next"]
			_enter_node(avail[randi() % avail.size()])
		S.BATTLE:
			if battle and not battle.ending and absf(Conductor.beat_offset()) < 0.03:
				var slot := randi() % 5
				var id := battle.deck.hand[slot]
				if id != "" and battle.energy >= int(Cards.def(id)["cost"]):
					battle.try_play(slot)
		S.REWARD:
			if reward_relic != "":
				_click("relic_take")
			_click("rw:%d" % (randi() % 3))
		S.REST:
			if run.hp < run.max_hp * 0.7:
				_click("rest:heal")
			else:
				_click("rest:upgrade")
		S.PICK:
			var i := 0
			for k in run.deck.size():
				if not Cards.is_upgraded(run.deck[k]):
					i = k
					break
			if pick_mode == "upgrade":
				_pick_card(i)
			else:
				goto(pick_return)
		S.SHOP:
			for i in shop_cards.size():
				_click_prefixed("buy:c%d" % i)
			for i in shop_relics.size():
				_click_prefixed("buy:r%d" % i)
			proceed()
		S.EVENT:
			if event_result == "":
				_click("ev:0")
			else:
				_click("event_done")
		S.TREASURE:
			_click("treasure_take")
		S.END:
			print("AUTOTEST result=%s mode=%s char=%s floor=%d wave=%d kills=%d deck=%d relics=%d hp=%d/%d t=%.1f" % ["WON" if end_won else "LOST", run.mode, run.char_id, run.floor_idx, run.wave, run.kills, run.deck.size(), run.relics.size(), run.hp, run.max_hp, _autotest_t])
			get_tree().quit()
	if _autotest_t > 1500.0:
		print("AUTOTEST timeout state=%s floor=%d" % [S.keys()[state], run.floor_idx])
		get_tree().quit()
