extends Node2D
## Game flow / screens. Battles live in battle.gd; this file is menus, map, shop, events, etc.

const W := 1280.0
const H := 720.0
const SL_X := 480.0
const SL_W := 420.0

enum S { SPLASH, MENU, MODE, CHAR, SETTINGS, RECORDS, CALIB, MAP, BATTLE, REWARD, REST, PICK, SHOP, EVENT, TREASURE, END }

const NODE_COL := {
	"battle": Color(0.9, 0.35, 0.35), "elite": Color(1.0, 0.6, 0.2), "rest": Color(0.4, 0.85, 0.5),
	"shop": Color(1.0, 0.85, 0.3), "event": Color(0.5, 0.75, 1.0), "treasure": Color(1.0, 0.8, 0.4),
	"boss": Color(0.9, 0.3, 0.7),
}
const NODE_GLYPH := {"battle": "戦", "elite": "強", "rest": "休", "shop": "店", "event": "？", "treasure": "宝", "boss": "王"}
const NODE_NAME := {"battle": "バトル", "elite": "エリート", "rest": "休憩所", "shop": "ショップ", "event": "イベント", "treasure": "宝箱", "boss": "ボス"}

var ui := Ui.new()
var state: S = S.SPLASH
var pending := -1
var fade := 0.0
var t := 0.0
var run := RunState.new()
var battle: Battle
var paused := false
var deck_view := false
var hud: Control
var glow: Node2D
var menu_pulse := 0.0
var menu_idx := 0
var settings_return: S = S.MENU
var sel_mode := "run"
var sel_char := 0
var sel_asc := 0
var toasts: Array = []
var sel_long := true
var settings_tab := 0
var sys_menu := false
var sys_confirm := false
var rebind_action := ""
var rebind_slot := 0
var pad_hw := false
var beat_hist: Array = []
var beat_msg := ""
var beat_msg_t := 0.0
var beat_msg_col := Color.WHITE
var map_focus := 0
var reward_picked := -1
var pick_preview := -1
var act_clear := false
var act_banner := 0.0
var bg_parts: Array = []
var drag_id := ""
var touch_mode := false
var pad_mode := false
var focus_id := ""
var _axis_state := {}
var joy_id := -1
var joy_origin := Vector2.ZERO
var joy_pos := Vector2.ZERO
var scroll_acc := 0.0
var tex_cache := {}
var font_res: Font

# screen data
var reward_cards: Array = []
var reward_gold := 0
var reward_relic := ""
var reward_potion := ""
var shop_potions: Array = []
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
var _bot_human := false
var _last_prog := -1
var _bot_noise := Vector2.ZERO
var _bot_noise_t := 0.0
var _bot_beat := -1
var _bot_target := 0.0
var _bot_played := false
var _autotest_t := 0.0
var _shot_path := ""
var _screen_arg := ""

func _ready() -> void:
	randomize()
	font_res = load("res://assets/fonts/DotGothic16-Regular.ttf")
	ui.font = font_res
	glow = Node2D.new()
	var gm := CanvasItemMaterial.new()
	gm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = gm
	add_child(glow)
	glow.draw.connect(func() -> void:
		if state == S.BATTLE and battle:
			battle.draw_glow(glow))
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Control.new()
	hud.set_script(load("res://scripts/hud.gd"))
	hud.game = self
	layer.add_child(hud)
	Conductor.beat.connect(func(_n: int) -> void: menu_pulse = 1.0)
	Settings.ach_unlocked.connect(func(id: String) -> void:
		toasts.append({"id": id, "t": 4.0})
		Conductor.play_sfx("win"))
	for i in 50:
		bg_parts.append([Vector2(randf() * W, randf() * H), 10.0 + randf() * 40.0, 2.0 + randf() * 4.0, randf()])
	var args := OS.get_cmdline_user_args()
	_autotest = "--autotest" in args
	_bot_human = "--bot=human" in args
	for a in args:
		if a.begins_with("--lang="):
			Settings.lang = a.substr(7)
		if a.begins_with("--shot="):
			_shot_path = a.substr(7)
		elif a.begins_with("--screen="):
			_screen_arg = a.substr(9)
	if _autotest or _screen_arg != "":
		Conductor.start()
		state = S.MENU
		if "--padtest" in args:
			_padtest.call_deferred()
	if _autotest:
		Engine.time_scale = 5.0 if _shot_path == "" else 1.0
		if "--tutorial" in args:
			start_tutorial()
		elif "--daily" in args:
			start_daily()
		else:
			var asc_arg := 0
			for a in args:
				if a.begins_with("--asc="):
					asc_arg = int(a.substr(6))
			start_run("endless" if "--endless" in args else "run", Characters.ORDER[randi() % Characters.ORDER.size()], asc_arg)
			if "--act2" in args and run.mode == "run":
				run.start_act2()
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

func start_daily() -> void:
	var d := Time.get_date_dict_from_system()
	var day := int(d["year"]) * 10000 + int(d["month"]) * 100 + int(d["day"])
	run = RunState.new()
	run.setup_daily(day)
	paused = false
	deck_view = false
	endless_queue.clear()
	Settings.stats["runs"] += 1
	goto(S.MAP)

func start_run(mode: String, char_id: String, asc := 0, long_run := true) -> void:
	run = RunState.new()
	run.setup(mode, char_id, asc)
	run.long_run = long_run
	act_clear = false
	paused = false
	deck_view = false
	endless_queue.clear()
	Settings.stats["runs"] += 1
	if mode == "run":
		goto(S.MAP)
	else:
		_start_battle("battle")

func start_tutorial() -> void:
	run = RunState.new()
	run.setup("run", "wizard")
	paused = false
	deck_view = false
	_start_battle("tutorial")

func _start_battle(kind: String) -> void:
	if battle:
		battle.dispose()
	var diff := 1.0
	if kind == "tutorial":
		diff = 0.6
	elif run.mode == "run":
		diff = (6.0 + maxf(0.0, run.floor_idx) * 0.4) if run.act == 2 else (1.0 + maxf(0.0, run.floor_idx) * 0.5)
	else:
		diff = 1.0 + run.wave * 0.35
	Conductor.start_battle_track(-1 if kind == "tutorial" else Settings.bgm, kind == "boss")
	battle = Battle.new()
	battle.setup(run, kind, diff, ui)
	if _autotest:
		battle.bot_dir = Callable(self, "_bot_dir")
	battle.finished.connect(_on_battle_done.bind(kind))
	paused = false
	goto(S.BATTLE)

func _on_battle_done(won: bool, kind: String) -> void:
	battle.dispose()
	if kind == "tutorial":
		if won:
			Settings.unlock("tutorial")
			Settings.tutorial_done = true
			Settings.save_cfg()
		goto(S.MENU)
		return
	run.battles += 1
	if not won:
		_end_run(false)
		return
	if kind == "boss" and run.mode == "run":
		if run.act == 1 and run.long_run:
			act_clear = true
			Settings.stats["act1"] += 1
			Settings.unlock("first_clear")
		else:
			_end_run(true)
			return
	var base := 14 + randi() % 8
	if kind == "elite":
		base = 32 + randi() % 10
	elif kind == "boss":
		base = 70 + randi() % 20
	base += battle.kills / 15
	reward_gold = run.gain_gold(base)
	reward_relic = ""
	if kind == "elite" or act_clear:
		var r := Relics.random_ids(1, run.relics)
		if not r.is_empty():
			reward_relic = r[0]
	reward_potion = ""
	if kind == "elite" or kind == "boss" or randf() < 0.35:
		reward_potion = Potions.random_id()
	reward_cards = Cards.random_choices(3)
	reward_picked = -1
	if run.mode == "endless":
		run.wave += 1
	Conductor.play_sfx("win")
	goto(S.REWARD)

func _end_run(won: bool) -> void:
	end_won = won
	var st: Dictionary = Settings.stats
	st["total_kills"] += run.kills
	if st["total_kills"] >= 1000:
		Settings.unlock("kills1000")
	if run.mode == "run":
		var reached: int = run.floor_idx + (1 if won else 0)
		st["best_floor"] = maxi(st["best_floor"], reached)
		if run.daily:
			var d := Time.get_date_dict_from_system()
			var day := int(d["year"]) * 10000 + int(d["month"]) * 100 + int(d["day"])
			if st["daily_day"] != day:
				st["daily_day"] = day
				st["daily_best"] = -1
			st["daily_best"] = maxi(st["daily_best"], reached)
		if won:
			st["wins"] += 1
			Settings.unlock("first_clear")
			if run.act == 2:
				st["full_clears"] += 1
				Settings.unlock("trueclear")
			Settings.char_wins[run.char_id] = int(Settings.char_wins.get(run.char_id, 0)) + 1
			if run.daily:
				Settings.unlock("daily")
			elif run.asc >= st["asc_unlocked"] and st["asc_unlocked"] < 5:
				st["asc_unlocked"] = run.asc + 1
			if run.asc >= 3:
				Settings.unlock("asc3")
			var all_ok := true
			for cid in Characters.ORDER:
				if int(Settings.char_wins.get(cid, 0)) < 1:
					all_ok = false
			if all_ok:
				Settings.unlock("allchars")
	else:
		st["endless_best"] = maxi(st["endless_best"], run.wave)
		if run.wave >= 10:
			Settings.unlock("endless10")
		if run.wave >= 20:
			Settings.unlock("endless20")
	st["best_kills"] = maxi(st["best_kills"], run.kills)
	Settings.save_cfg()
	goto(S.END)

func proceed() -> void:
	deck_view = false
	if run.deck.size() >= 25:
		Settings.unlock("deck25")
	if act_clear:
		act_clear = false
		run.start_act2()
		Settings.unlock("act2")
		act_banner = 3.5
		Conductor.play_sfx("big")
		goto(S.MAP)
		return
	if run.mode == "run":
		goto(S.MAP)
		return
	if endless_queue.is_empty():
		var w := run.wave
		if w % 4 == 0 and w > 0:
			endless_queue.append("shop")
		if w % 3 == 0 and w > 0:
			endless_queue.append("rest")
		endless_queue.append("boss" if (w + 1) % 10 == 0 else ("elite" if (w + 1) % 5 == 0 else "battle"))
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
	shop_potions.clear()
	for i in 2:
		var pid := Potions.random_id()
		shop_potions.append({"id": pid, "price": int(Potions.DB[pid]["price"]) + randi() % 10, "sold": false})
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
					event_result = Loc.t("祭壇が応えた。レリック「%s」を得た。") % Relics.DB[r[0]]["name"]
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
				event_result = Loc.t("「%s」が強化された。HPが10減った。") % Cards.def(run.deck[i])["name"]
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
				event_result = Loc.t("「%s」を手に入れた。") % Cards.def(id)["name"]
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

func _menu_ids() -> Array:
	return ["start", "tutorial", "records", "settings"] if OS.has_feature("web") else ["start", "tutorial", "records", "settings", "quit"]

func _begin() -> void:
	# Browsers only allow audio after a user gesture, so music starts here.
	if not Conductor.running:
		Conductor.start()
	Conductor.play_sfx("select")
	goto(S.MENU)

func _press(p: Vector2) -> void:
	pad_hw = false
	var id := ui.hit(p)
	if id.begins_with("sl:"):
		drag_id = id
		_slide(id, p.x)
	elif id != "":
		_click(id)
	elif state == S.CALIB:
		_calib_tap()

func _release() -> void:
	if drag_id != "":
		if drag_id == "sl:clap":
			Conductor.preview_clap()
		drag_id = ""
		Settings.save_cfg()

# ---- gamepad -----------------------------------------------------------

func _pad_input(event: InputEvent) -> void:
	if event is InputEventJoypadButton:
		var jb := event as InputEventJoypadButton
		if not jb.pressed:
			return
		pad_hw = true
		pad_mode = true
		match jb.button_index:
			JOY_BUTTON_DPAD_UP: _pad_nav(Vector2.UP)
			JOY_BUTTON_DPAD_DOWN: _pad_nav(Vector2.DOWN)
			JOY_BUTTON_DPAD_LEFT: _pad_nav(Vector2.LEFT)
			JOY_BUTTON_DPAD_RIGHT: _pad_nav(Vector2.RIGHT)
			JOY_BUTTON_START:
				if state == S.BATTLE:
					_toggle_pause()
				elif state != S.SPLASH and state != S.SETTINGS and state != S.CALIB:
					if sys_menu:
						sys_menu = false
					else:
						_open_sys_menu()
			_:
				_pad_button(jb.button_index)
	elif event is InputEventJoypadMotion:
		var jm := event as InputEventJoypadMotion
		if jm.axis != JOY_AXIS_LEFT_X and jm.axis != JOY_AXIS_LEFT_Y:
			return
		var key := int(jm.axis) * 2 + (1 if jm.axis_value > 0.0 else 0)
		var strong := absf(jm.axis_value) > 0.6
		if strong and not _axis_state.get(key, false):
			_axis_state[key] = true
			pad_mode = true
			pad_hw = true
			if jm.axis == JOY_AXIS_LEFT_X:
				_pad_nav(Vector2.RIGHT if jm.axis_value > 0.0 else Vector2.LEFT)
			else:
				_pad_nav(Vector2.DOWN if jm.axis_value > 0.0 else Vector2.UP)
		elif not strong:
			_axis_state[key] = false

func _in_battle_play() -> bool:
	return state == S.BATTLE and battle != null and not paused

func _pad_button(idx: int) -> void:
	if _in_battle_play():
		match idx:
			JOY_BUTTON_A: battle.try_play(0)
			JOY_BUTTON_B: battle.try_play(1)
			JOY_BUTTON_X: battle.try_play(2)
			JOY_BUTTON_Y: battle.try_play(3)
			JOY_BUTTON_RIGHT_SHOULDER: battle.try_play(4)
			JOY_BUTTON_LEFT_SHOULDER: battle.use_potion(0)
		return
	if state == S.SPLASH:
		return
	if idx == JOY_BUTTON_A:
		if focus_id == "":
			_pad_nav(Vector2.DOWN)
		elif not focus_id.begins_with("sl:"):
			_click(focus_id)
	elif idx == JOY_BUTTON_B:
		for bid in ["deck_close", "sys_no", "sys_resume", "resume", "up_cancel", "back", "leave", "skip", "menu"]:
			for bt in ui.buttons:
				if bt["id"] == bid:
					_click(bid)
					return

func _default_focus(cands: Array) -> String:
	var pri: Array = ["sys_resume", "resume", "up_ok", "start", "go", "mode:run", "skip", "leave", "event_done", "treasure_take", "rest:heal", "retry", "rw:0", "back"]
	if state == S.REWARD and reward_picked < 0:
		pri = ["rw:0", "skip"]
	for pid in pri:
		for bt in cands:
			if bt["id"] == pid:
				return pid
	return ""

func _pad_nav(dir: Vector2) -> void:
	if _in_battle_play():
		return
	var cands: Array = []
	for bt in ui.buttons:
		var bid: String = bt["id"]
		if bid.begins_with("relic:") or bid.begins_with("pot:") or bid == "tr":
			continue
		cands.append(bt)
	if cands.is_empty():
		return
	var cur_rect := Rect2()
	var found := false
	for bt in cands:
		if bt["id"] == focus_id:
			cur_rect = bt["rect"]
			found = true
	if not found:
		var pick := _default_focus(cands)
		if pick != "":
			focus_id = pick
			Conductor.play_sfx("tick")
			return
		cands.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var ra: Rect2 = a["rect"]
			var rb: Rect2 = b["rect"]
			return ra.position.y < rb.position.y or (is_equal_approx(ra.position.y, rb.position.y) and ra.position.x < rb.position.x))
		focus_id = cands[0]["id"]
		Conductor.play_sfx("tick")
		return
	if focus_id.begins_with("sl:") and (dir == Vector2.LEFT or dir == Vector2.RIGHT):
		var d := 0.05 * dir.x
		if focus_id == "sl:music":
			Settings.music_vol = clampf(Settings.music_vol + d, 0.0, 1.0)
		elif focus_id == "sl:clap":
			Settings.clap_vol = clampf(Settings.clap_vol + d, 0.0, 1.0)
			Conductor.preview_clap()
		else:
			Settings.sfx_vol = clampf(Settings.sfx_vol + d, 0.0, 1.0)
		Settings.apply()
		Settings.save_cfg()
		Conductor.play_sfx("tick")
		return
	var best := ""
	var best_score := 1e12
	var cc := cur_rect.get_center()
	for bt in cands:
		if bt["id"] == focus_id:
			continue
		var v: Vector2 = (bt["rect"] as Rect2).get_center() - cc
		if v.length() < 1.0:
			continue
		var dt := v.normalized().dot(dir)
		if dt < 0.35:
			continue
		var score := v.length() * (1.0 + 2.5 * (1.0 - dt))
		if score < best_score:
			best_score = score
			best = bt["id"]
	if best != "":
		focus_id = best
		Conductor.play_sfx("tick")

func _touch_input(event: InputEvent) -> void:
	# Touch is handled directly (mouse emulation is off) so a held joystick finger
	# never blocks a second finger from tapping cards.
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		touch_mode = true
		if st.pressed:
			var in_arena := state == S.BATTLE and battle != null and not paused and not deck_view 				and st.position.y < Battle.ARENA_BOTTOM + 30.0 and ui.hit(st.position) == ""
			if in_arena and joy_id == -1:
				joy_id = st.index
				joy_origin = st.position
				joy_pos = st.position
			elif st.index != joy_id:
				_press(st.position)
		else:
			if st.index == joy_id:
				joy_id = -1
				if battle:
					battle.touch_dir = Vector2.ZERO
			else:
				_release()
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if sd.index == joy_id:
			joy_pos = sd.position
			var v := (joy_pos - joy_origin) / 70.0
			v = v.limit_length(1.0)
			if battle:
				battle.touch_dir = v if v.length() > 0.15 else Vector2.ZERO
		elif drag_id != "":
			_slide(drag_id, sd.position.x)
		elif state == S.PICK or deck_view:
			scroll_acc += sd.relative.y
			while scroll_acc > 48.0:
				pick_scroll = maxi(0, pick_scroll - 1)
				scroll_acc -= 48.0
			while scroll_acc < -48.0:
				pick_scroll += 1
				scroll_acc += 48.0

func _unhandled_input(event: InputEvent) -> void:
	if fade > 0.3:
		return
	if state == S.SPLASH:
		# Touch: start on RELEASE - mobile browsers only grant audio on touchend/click, not touchstart.
		if (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed) or (event is InputEventJoypadButton and event.pressed) 				or (event is InputEventScreenTouch and not event.pressed):
			if event is InputEventScreenTouch:
				touch_mode = true
			_begin()
		return
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		_touch_input(event)
		return
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		_pad_input(event)
		return
	if event is InputEventMouseMotion and pad_mode:
		pad_mode = false
		focus_id = ""
	if event is InputEventKey and event.pressed and not event.echo:
		_key((event as InputEventKey).keycode)
	elif event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_press(mb.position)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			pick_scroll += 1
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			pick_scroll = maxi(0, pick_scroll - 1)
	elif event is InputEventMouseButton and not event.pressed:
		_release()
	elif event is InputEventMouseMotion and drag_id != "":
		_slide(drag_id, (event as InputEventMouseMotion).position.x)

func _slide(id: String, x: float) -> void:
	var f := clampf((x - SL_X) / SL_W, 0.0, 1.0)
	if id == "sl:music":
		Settings.music_vol = f
	elif id == "sl:clap":
		Settings.clap_vol = f
	else:
		Settings.sfx_vol = f
	Settings.apply()

func _kb_nav_state() -> bool:
	if sys_menu or sys_confirm or deck_view:
		return true
	if state == S.BATTLE:
		return paused
	return state in [S.MENU, S.MODE, S.SETTINGS, S.RECORDS, S.REWARD, S.REST, S.PICK, S.SHOP, S.EVENT, S.TREASURE, S.END]

func _open_sys_menu() -> void:
	sys_menu = true
	sys_confirm = false
	focus_id = ""
	Conductor.play_sfx("open")

func _key(k: int) -> void:
	pad_hw = false
	# key re-binding capture
	if rebind_action != "":
		if k != KEY_ESCAPE:
			Settings.bind(rebind_action, rebind_slot, k)
			Settings.save_cfg()
		rebind_action = ""
		Conductor.play_sfx("select")
		return
	# overlays first
	if sys_confirm:
		if k == KEY_ESCAPE:
			sys_confirm = false
			return
	elif sys_menu:
		if k == KEY_ESCAPE:
			sys_menu = false
			return
	elif deck_view and k == KEY_ESCAPE:
		deck_view = false
		return
	if state == S.PICK and pick_preview >= 0 and not sys_menu and not sys_confirm:
		if k == KEY_ENTER or k == KEY_SPACE or k == KEY_Y:
			_click("up_ok")
			return
		if k == KEY_ESCAPE or k == KEY_BACKSPACE:
			_click("up_cancel")
			return
	# generic arrow / Enter / Space navigation for every menu-like screen
	if _kb_nav_state():
		var nd := Vector2.ZERO
		match k:
			KEY_UP: nd = Vector2.UP
			KEY_DOWN: nd = Vector2.DOWN
			KEY_LEFT: nd = Vector2.LEFT
			KEY_RIGHT: nd = Vector2.RIGHT
		if nd != Vector2.ZERO:
			pad_mode = true
			_pad_nav(nd)
			return
		if k == KEY_ENTER or k == KEY_SPACE or k == KEY_KP_ENTER:
			if state == S.SETTINGS and k == KEY_SPACE and not sys_menu and not sys_confirm and not deck_view:
				_beat_tap()
				return
			pad_mode = true
			if focus_id == "":
				_pad_nav(Vector2.DOWN)
			elif not focus_id.begins_with("sl:"):
				_click(focus_id)
			return
		if k == KEY_ESCAPE:
			if state == S.BATTLE and paused:
				_toggle_pause()
			return
	match state:
		S.MODE:
			if k == KEY_ESCAPE:
				_click("back")
		S.CHAR:
			var unl := Settings.chars_unlocked()
			if k == KEY_ESCAPE:
				_click("back")
			elif k == KEY_LEFT or k == KEY_RIGHT:
				var n := Characters.ORDER.size()
				for tries in n:
					sel_char = (sel_char + (1 if k == KEY_RIGHT else n - 1)) % n
					if Characters.ORDER[sel_char] in unl:
						break
				Conductor.play_sfx("tick")
			elif k == KEY_UP:
				_click("asc+")
			elif k == KEY_DOWN:
				_click("asc-")
			elif k == KEY_L:
				_click("len")
			elif k == KEY_ENTER or k == KEY_SPACE:
				_click("go")
		S.SETTINGS:
			if k == KEY_ESCAPE:
				_click("back")
		S.RECORDS:
			if k == KEY_ESCAPE:
				_click("back")
		S.CALIB:
			if k == KEY_SPACE or k == KEY_ENTER:
				_calib_tap()
			elif k == KEY_ESCAPE:
				_click("back")
		S.BATTLE:
			var act := Settings.action_for_key(k)
			if k == KEY_ESCAPE or act == "pause":
				_toggle_pause()
			elif act.begins_with("card"):
				battle.try_play(int(act.substr(4)) - 1)
			elif act.begins_with("potion"):
				battle.use_potion(int(act.substr(6)) - 1)
		S.REWARD:
			if k >= KEY_1 and k <= KEY_3:
				_click("rw:%d" % (k - KEY_1))
			elif k == KEY_S:
				_click("skip")
			elif k == KEY_ESCAPE:
				_open_sys_menu()
		S.PICK:
			if k == KEY_ESCAPE:
				if pick_mode != "remove_free":
					_click("back")
		S.MAP:
			var av := _map_avail()
			if k == KEY_ESCAPE:
				_open_sys_menu()
			elif av.is_empty():
				return
			elif k == KEY_LEFT or k == KEY_A:
				map_focus = (map_focus + av.size() - 1) % av.size()
				Conductor.play_sfx("tick")
			elif k == KEY_RIGHT or k == KEY_D:
				map_focus = (map_focus + 1) % av.size()
				Conductor.play_sfx("tick")
			elif k == KEY_ENTER or k == KEY_SPACE:
				Conductor.play_sfx("select")
				_enter_node(av[clampi(map_focus, 0, av.size() - 1)])
			elif k >= KEY_1 and k <= KEY_6 and (k - KEY_1) < av.size():
				Conductor.play_sfx("select")
				_enter_node(av[k - KEY_1])
		S.REST, S.SHOP, S.EVENT, S.TREASURE, S.END:
			if k == KEY_ESCAPE and state != S.END:
				_open_sys_menu()

## Settings-screen beat tester: shows the judgement and the signed ms offset of each press.
func _beat_tap() -> void:
	var off := Conductor.beat_offset() * 1000.0
	var a := absf(off) / 1000.0
	var pw := 0.07 + 0.03 * Settings.assist
	var gw := 0.14 + 0.03 * Settings.assist
	var g := "MISS"
	beat_msg_col = Color(0.9, 0.35, 0.35)
	if a <= pw:
		g = "PERFECT"
		beat_msg_col = Color(1.0, 0.9, 0.3)
	elif a <= gw:
		g = "GOOD"
		beat_msg_col = Color(0.5, 0.9, 1.0)
	beat_hist.append(off)
	if beat_hist.size() > 8:
		beat_hist.pop_front()
	var tag := "" if absf(off) < 3.0 else (Loc.t(" 遅め") if off > 0.0 else Loc.t(" 早め"))
	beat_msg = "%s  %+d ms%s" % [g, int(round(off)), tag]
	beat_msg_t = 2.5
	Conductor.play_sfx(g.to_lower())

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
	if id.begins_with("potion:"):
		if state == S.BATTLE and not paused and battle:
			battle.use_potion(int(id.substr(7)))
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
			sel_asc = mini(sel_asc, Settings.stats["asc_unlocked"])
			goto(S.CHAR)
		"mode:daily":
			start_daily()
		"records":
			goto(S.RECORDS)
		"len":
			sel_long = not sel_long
		"asc-":
			sel_asc = maxi(0, sel_asc - 1)
		"asc+":
			sel_asc = mini(mini(5, Settings.stats["asc_unlocked"]), sel_asc + 1)
		"back":
			match state:
				S.MODE: goto(S.MENU)
				S.CHAR: goto(S.MODE)
				S.SETTINGS: goto(settings_return)
				S.RECORDS: goto(S.MENU)
				S.CALIB: goto(S.SETTINGS)
				S.PICK: goto(pick_return)
		"go":
			if Characters.ORDER[sel_char] in Settings.chars_unlocked():
				start_run(sel_mode, Characters.ORDER[sel_char], sel_asc if sel_mode == "run" else 0, sel_long)
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
			if battle and battle.tutorial:
				battle.dispose()
				goto(S.MENU)
			else:
				_end_run(false)
		"tutorial":
			start_tutorial()
		"off-":
			Settings.offset_ms = maxi(-200, Settings.offset_ms - 5)
		"off+":
			Settings.offset_ms = mini(200, Settings.offset_ms + 5)
		"bgm-", "bgm+":
			var bt := Conductor.battle_tracks()
			var n: int = bt.size() + 1  # -1 (random) + each battle track
			var cur: int = Settings.bgm + 1
			cur = (cur + (1 if id == "bgm+" else n - 1)) % n
			Settings.bgm = cur - 1
			if Settings.bgm >= 0 and settings_return != S.BATTLE:
				Conductor.set_track(bt[Settings.bgm])  # preview
			Settings.save_cfg()
		"tab:audio":
			settings_tab = 0
		"tab:game":
			settings_tab = 1
		"tab:keys":
			settings_tab = 2
		"keys_reset":
			Settings.reset_keys()
			Settings.save_cfg()
		"beat_tap":
			_beat_tap()
		"avg_apply":
			if beat_hist.size() >= 3:
				var sum := 0.0
				for v in beat_hist:
					sum += v
				Settings.offset_ms = clampi(Settings.offset_ms + int(round(sum / beat_hist.size())), -200, 200)
				Settings.save_cfg()
				beat_hist.clear()
				beat_msg = ""
		"sys_open":
			_open_sys_menu()
		"sys_resume":
			sys_menu = false
			sys_confirm = false
		"sys_settings":
			sys_menu = false
			settings_return = state
			goto(S.SETTINGS)
		"sys_title":
			sys_confirm = true
			focus_id = ""
		"sys_no":
			sys_confirm = false
			focus_id = ""
		"sys_yes":
			sys_menu = false
			sys_confirm = false
			deck_view = false
			if paused:
				paused = false
				Conductor.set_paused(false)
			if battle:
				battle.dispose()
			goto(S.MENU)
		"clap":
			Settings.clap_on = not Settings.clap_on
			Settings.save_cfg()
			Conductor.preview_clap()
		"clap-", "clap+":
			var nt: int = Conductor.CLAP_TYPES.size()
			Settings.clap_type = (Settings.clap_type + (1 if id == "clap+" else nt - 1)) % nt
			Settings.save_cfg()
			Conductor.preview_clap()
		"pat":
			Settings.clap_pat = 1 - Settings.clap_pat
			Settings.save_cfg()
		"shake":
			Settings.shake = not Settings.shake
			Settings.save_cfg()
		"flash":
			Settings.reduce_flash = not Settings.reduce_flash
			Settings.save_cfg()
		"assist":
			Settings.assist = (Settings.assist + 1) % 3
			Settings.save_cfg()
		"lang":
			Settings.lang = "en" if Settings.lang == "ja" else "ja"
			Loc.clear_cache()
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
		"up_ok":
			if pick_preview >= 0 and pick_preview < run.deck.size():
				run.deck[pick_preview] = Cards.upgrade(run.deck[pick_preview])
				pick_preview = -1
				Conductor.play_sfx("win")
				proceed()
		"up_cancel":
			pick_preview = -1
		"relic_take":
			run.add_relic(reward_relic)
			reward_relic = ""
		"potion_take":
			if run.add_potion(reward_potion):
				reward_potion = ""
		"leave":
			proceed()
		"rest:heal":
			run.heal(int(run.max_hp * (0.45 if run.has_relic("fuel") else 0.3)))
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
	if id.begins_with("keybind:"):
		var parts := id.split(":")
		rebind_action = parts[1]
		rebind_slot = int(parts[2])
		Conductor.play_sfx("open")
	elif id.begins_with("rw:"):
		# choose / switch / cancel the reward card until "continue" is pressed
		var i := int(id.substr(3))
		if reward_picked >= 0:
			var old_id: String = reward_cards[reward_picked]
			var di := run.deck.rfind(old_id)
			if di >= 0:
				run.deck.remove_at(di)
			if reward_picked == i:
				reward_picked = -1
				Conductor.play_sfx("back" if false else "tick")
				return
		run.deck.append(reward_cards[i])
		reward_picked = i
		Conductor.play_sfx("win")
	elif id.begins_with("node:"):
		_enter_node(int(id.substr(5)))
	elif id.begins_with("char:"):
		if Characters.ORDER[int(id.substr(5))] in Settings.chars_unlocked():
			sel_char = int(id.substr(5))
	elif id.begins_with("buy:c"):
		var it: Dictionary = shop_cards[int(id.substr(5))]
		if not it["sold"] and run.gold >= it["price"]:
			run.gold -= it["price"]
			it["sold"] = true
			run.deck.append(it["id"])
			Conductor.play_sfx("win")
	elif id.begins_with("buy:p"):
		var it: Dictionary = shop_potions[int(id.substr(5))]
		if not it["sold"] and run.gold >= it["price"] and run.potions.size() < run.potion_slots():
			run.gold -= it["price"]
			it["sold"] = true
			run.add_potion(it["id"])
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
	elif id.begins_with("scroll:"):
		pick_scroll = maxi(0, pick_scroll + int(id.substr(7)))

func _pick_card(i: int) -> void:
	if i >= run.deck.size():
		return
	match pick_mode:
		"upgrade":
			if Cards.is_upgraded(run.deck[i]):
				return
			pick_preview = i
			Conductor.play_sfx("open")
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
	act_banner = maxf(0.0, act_banner - delta)
	beat_msg_t = maxf(0.0, beat_msg_t - delta)
	for tt in toasts:
		tt["t"] -= delta
	toasts = toasts.filter(func(x: Dictionary) -> bool: return x["t"] > 0.0)
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
	glow.queue_redraw()

func _on_enter(s: S) -> void:
	focus_id = ""
	if s != S.BATTLE and s != S.SETTINGS and s != S.CALIB and s != S.RECORDS and s != S.SPLASH:
		Conductor.play_menu()
	Conductor.guide = s == S.SETTINGS or s == S.CALIB or s == S.BATTLE
	if s == S.MAP:
		map_focus = _map_avail().size() / 2
	if s == S.PICK:
		pick_preview = -1
	if s == S.BATTLE and battle == null:
		state = S.MENU
	if s == S.MENU:
		menu_idx = 1 if not Settings.tutorial_done else 0
	if s == S.PICK:
		pick_scroll = 0

func _draw() -> void:
	if state == S.BATTLE and battle:
		battle.draw_world(self)

# ---- HUD / screens ---------------------------------------------------------

func draw_hud(c: Control) -> void:
	ui.begin(c, get_process_delta_time())
	ui.touch = touch_mode
	ui.pad = pad_hw
	ui.focus_id = focus_id if pad_mode else ""
	match state:
		S.SPLASH: _draw_splash(c)
		S.MENU: _draw_menu(c)
		S.MODE: _draw_mode(c)
		S.CHAR: _draw_char(c)
		S.SETTINGS: _draw_settings(c)
		S.RECORDS: _draw_records(c)
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
	if sys_menu and state != S.BATTLE:
		ui.buttons.clear()
		_draw_sys_menu(c)
	if sys_confirm:
		ui.buttons.clear()
		_draw_confirm(c)
	_draw_toasts(c)
	if state == S.BATTLE and not paused:
		_draw_joystick(c)
	var ws := DisplayServer.window_get_size()
	if ws.y > ws.x and state != S.SPLASH:
		c.draw_rect(Rect2(0, 0, W, H), Color(0.03, 0.02, 0.08, 0.95))
		ui.center(c, "画面を横向きにしてください", 330.0, 44, Color(1, 0.9, 0.5))
		ui.center(c, "(スマホは横向き+全画面がおすすめ)", 390.0, 22, Color(0.8, 0.8, 0.95))
	if fade > 0.0:
		c.draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, clampf(fade, 0.0, 1.0)))

func _draw_joystick(c: Control) -> void:
	if joy_id != -1:
		var off := (joy_pos - joy_origin).limit_length(60.0)
		c.draw_circle(joy_origin, 60.0, Color(1, 1, 1, 0.08))
		c.draw_arc(joy_origin, 60.0, 0.0, TAU, 32, Color(1, 1, 1, 0.35), 3.0)
		c.draw_circle(joy_origin + off, 26.0, Color(1, 1, 1, 0.35))
	elif touch_mode and battle and not battle.ending:
		ui.text(c, "画面をドラッグで移動", Vector2(0, 470), 16, Color(1, 1, 1, 0.3), HORIZONTAL_ALIGNMENT_CENTER, W)

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

func _draw_splash(c: Control) -> void:
	_bg(c)
	_logo(c, 200.0)
	_dancers(c, 520.0)
	var a := 0.5 + 0.5 * sin(t * 4.0)
	ui.center(c, "タップ / クリック / キーでスタート", 440.0, 26, Color(1, 0.9, 0.5, 0.4 + 0.6 * a))
	ui.center(c, "♪ 音が出ます", 475.0, 14, Color(0.7, 0.7, 0.85))

func _draw_menu(c: Control) -> void:
	_bg(c)
	_logo(c, 130.0)
	ui.center(c, "ビートに乗って、デッキで生き残れ。", 262.0, 22, Color(0.85, 0.85, 1.0))
	var names := {"start": "はじめる", "tutorial": "あそびかた", "records": "記録・実績", "settings": "設定", "quit": "終了"}
	var ids := _menu_ids()
	for i in ids.size():
		var r := Rect2(W / 2.0 - 160.0, 300.0 + i * 56.0, 320.0, 48.0)
		var acc := Color(1.0, 0.8, 0.35) if i == menu_idx else Color(0.55, 0.5, 0.95)
		if ids[i] == "tutorial" and not Settings.tutorial_done:
			acc = Color(0.5, 1.0, 0.6)
		ui.button(c, ids[i], r, names[ids[i]], true, acc, 24)
		if ids[i] == "tutorial" and not Settings.tutorial_done:
			ui.text(c, "NEW! はじめての方はここから", Vector2(r.end.x + 14.0, r.position.y + 32.0), 14, Color(0.6, 1.0, 0.7, 0.75 + 0.25 * sin(t * 5.0)))
		if ui.is_hover(ids[i]):
			menu_idx = i
	_dancers(c, 595.0)
	var st: Dictionary = Settings.stats
	ui.center(c, Loc.t("プレイ %d回   クリア %d回   最高到達 %d階   エンドレス最高 %dウェーブ   最多撃破 %d") % [st["runs"], st["wins"], st["best_floor"], st["endless_best"], st["best_kills"]], 678.0, 14, Color(0.7, 0.7, 0.85))
	ui.text(c, "CC0素材: Kenney  /  音楽・効果音は自作", Vector2(16, H - 12), 11, Color(0.5, 0.5, 0.65))
	ui.text(c, "♪ %s" % Conductor.TRACKS[Conductor.track_idx]["name"], Vector2(0, H - 12), 11, Color(0.6, 0.6, 0.8), HORIZONTAL_ALIGNMENT_RIGHT, W - 16.0)

func _draw_mode(c: Control) -> void:
	_bg(c)
	ui.center(c, "モード選択", 90.0, 44, Color(1, 0.9, 0.6))
	var d := Time.get_date_dict_from_system()
	var day := int(d["year"]) * 10000 + int(d["month"]) * 100 + int(d["day"])
	var dmod: int = day % 3
	var modes := [
		["mode:run", "ステージ攻略", "2つの幕(各10階+ボス)を勝ち抜き、最後のボスを倒せ。\nバトル・エリート・休憩・ショップ・イベント・宝箱。\n難易度(アセンション)で何度も挑める。", Color(0.9, 0.5, 0.4), 84,
			Loc.t("クリア %d回 / 最高 %d階") % [Settings.stats["wins"], Settings.stats["best_floor"]]],
		["mode:endless", "エンドレス", "ウェーブが延々と続くサバイバル。\n勝ち抜くごとにカード報酬。\n10ウェーブごとにボスが出現！", Color(0.5, 0.8, 1.0), 108,
			Loc.t("最高 %dウェーブ") % Settings.stats["endless_best"]],
		["mode:daily", "デイリーラン", "今日だけの固定マップ・キャラ・特殊ルール。\n\n★ 本日のルール ★\n" + RunState.MOD_NAMES[dmod], Color(1.0, 0.85, 0.3), 86,
			(Loc.t("今日の記録: %d階") % (int(Settings.stats["daily_best"]) + 1)) if (Settings.stats["daily_day"] == day and Settings.stats["daily_best"] >= 0) else "今日は未挑戦"],
	]
	for i in 3:
		var m: Array = modes[i]
		var r := Rect2(70.0 + i * 385.0, 160.0, 350.0, 400.0)
		ui.button(c, m[0], r, "", true, m[3])
		c.draw_texture_rect(tex(m[4]), Rect2(r.position.x + r.size.x / 2.0 - 48.0, r.position.y + 26.0 - absf(sin(t * 3.0 + i)) * 8.0, 96, 96), false)
		ui.text(c, m[1], Vector2(r.position.x, r.position.y + 165.0), 32, m[3], HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		ui.dms(c, Vector2(r.position.x + 20.0, r.position.y + 212.0), m[2], HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 40.0, 16, -1, Color(0.9, 0.9, 0.95))
		ui.text(c, m[5], Vector2(r.position.x, r.position.y + 375.0), 14, Color(0.8, 0.8, 0.9), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	if not Settings.tutorial_done:
		ui.center(c, "初めての方は、メニューの『あそびかた』でリズムの基本を練習できます", 610.0, 16, Color(0.6, 1.0, 0.7))
	ui.button(c, "back", Rect2(40, H - 80, 160, 48), "もどる", true, Color(0.6, 0.6, 0.8), 20)

func _draw_char(c: Control) -> void:
	_bg(c)
	ui.center(c, "キャラクター選択", 66.0, 40, Color(1, 0.9, 0.6))
	var n := Characters.ORDER.size()
	var pw := 290.0
	var gap := 14.0
	var x0 := (W - (n * pw + (n - 1) * gap)) / 2.0
	var unl := Settings.chars_unlocked()
	for i in n:
		var cid: String = Characters.ORDER[i]
		var cd: Dictionary = Characters.DB[cid]
		var ok := cid in unl
		var col: Color = cd["color"] if ok else Color(0.4, 0.4, 0.45)
		var r := Rect2(x0 + i * (pw + gap), 100.0, pw, 400.0)
		var sel := i == sel_char
		ui.button(c, "char:%d" % i, r, "", ok, col)
		if sel:
			var gp := 0.5 + 0.5 * sin(t * 5.0)
			c.draw_rect(r, Color(col.r, col.g, col.b, 0.16 + 0.1 * gp))
			c.draw_rect(r.grow(10.0), Color(col, 0.18 + 0.14 * gp))
			c.draw_rect(r.grow(7.0), Color(1.0, 0.95, 0.6, 0.65 + 0.35 * gp), false, 6.0)
			c.draw_rect(r.grow(2.0), Color(1, 1, 1, 0.9), false, 3.0)
			ui.text(c, "▼ 選択中 ▼", Vector2(r.position.x, r.position.y - 16.0 - 4.0 * gp), 17, Color(1.0, 0.95, 0.5), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		elif ok:
			c.draw_rect(r, Color(0, 0, 0, 0.38))
		var bob := absf(sin(t * 4.0 + i)) * (14.0 if sel else 3.0)
		var sp := Rect2(r.position.x + r.size.x / 2.0 - 48.0, r.position.y + 20.0 - bob, 96, 96)
		c.draw_texture_rect(tex(int(cd["tile"])), sp, false, Color.WHITE if ok else Color(0, 0, 0, 0.8))
		if not ok:
			ui.text(c, "？？？", Vector2(r.position.x, r.position.y + 160.0), 30, col, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
			ui.text(c, "ロック中", Vector2(r.position.x, r.position.y + 200.0), 18, Color(1, 0.8, 0.5), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
			ui.dms(c, Vector2(r.position.x + 16.0, r.position.y + 240.0), cd["unlock"], HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 32.0, 15, -1, Color(0.8, 0.8, 0.85))
			continue
		ui.text(c, cd["name"], Vector2(r.position.x, r.position.y + 158.0), 28, col, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		ui.text(c, Loc.t("HP %d   速度 %d%%   クリア%d回") % [cd["hp"], int(float(cd["speed"]) * 100.0), int(Settings.char_wins.get(cid, 0))], Vector2(r.position.x, r.position.y + 184.0), 13, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		ui.text(c, "◆ " + cd["passive"], Vector2(r.position.x + 14.0, r.position.y + 218.0), 16, Color(1, 0.9, 0.5))
		ui.dms(c, Vector2(r.position.x + 14.0, r.position.y + 240.0), cd["passive_desc"], HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 28.0, 13, -1, Color(0.9, 0.9, 0.95))
		var counts := {}
		for id in cd["starter"]:
			counts[id] = counts.get(id, 0) + 1
		var line := ""
		for id in counts:
			line += "%s ×%d    " % [Cards.def(id)["name"], counts[id]]
		ui.text(c, "初期デッキ", Vector2(r.position.x + 14.0, r.position.y + 305.0), 13, Color(0.7, 0.8, 1.0))
		ui.dms(c, Vector2(r.position.x + 14.0, r.position.y + 325.0), line, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 28.0, 12, -1, Color(0.85, 0.85, 0.9))
	if sel_mode == "run":
		var au: int = Settings.stats["asc_unlocked"]
		ui.button(c, "asc-", Rect2(W / 2.0 - 330.0, 530.0, 50.0, 40.0), "◀", sel_asc > 0, Color(0.6, 0.6, 0.9), 20)
		ui.button(c, "asc+", Rect2(W / 2.0 + 280.0, 530.0, 50.0, 40.0), "▶", sel_asc < mini(5, au), Color(0.6, 0.6, 0.9), 20)
		ui.text(c, Loc.t("アセンション %d") % sel_asc, Vector2(0, 556.0), 22, Color(1, 0.7, 0.4), HORIZONTAL_ALIGNMENT_CENTER, W)
		ui.text(c, RunState.ASC_TEXT[sel_asc] + ("" if au >= 5 else "  (クリアで次の段階が解放)"), Vector2(0, 582.0), 14, Color(0.85, 0.85, 0.95), HORIZONTAL_ALIGNMENT_CENTER, W)
	if sel_mode == "run":
		ui.button(c, "len", Rect2(W - 330.0, H - 82.0, 290.0, 48.0), "長さ: 2幕(フル)" if sel_long else "長さ: 1幕(ショート)", true, Color(0.9, 0.7, 0.3), 17)
	ui.button(c, "back", Rect2(40, H - 80, 160, 48), "もどる", true, Color(0.6, 0.6, 0.8), 20)
	var gp2 := 0.5 + 0.5 * sin(t * 6.0)
	var go_ok: bool = Characters.ORDER[sel_char] in unl
	if go_ok:
		c.draw_rect(Rect2(W / 2.0 - 160.0, H - 90.0, 320.0, 60.0).grow(6.0 + 6.0 * gp2), Color(1.0, 0.85, 0.3, 0.25 + 0.25 * gp2))
		c.draw_rect(Rect2(W / 2.0 - 160.0, H - 90.0, 320.0, 60.0).grow(4.0 + 3.0 * gp2), Color(1.0, 0.95, 0.6, 0.6 + 0.4 * gp2), false, 4.0)
		ui.arrow(c, Vector2(W / 2.0 - 195.0 - 8.0 * gp2, H - 60.0), 1, 34.0, Color(1.0, 0.9, 0.4))
		ui.arrow(c, Vector2(W / 2.0 + 195.0 + 8.0 * gp2, H - 60.0), -1, 34.0, Color(1.0, 0.9, 0.4))
		ui.text(c, "キャラを決めたら出発！(Enter)   ←→キャラ  ↑↓アセンション  Lで長さ切替", Vector2(0, H - 102.0 - 4.0 * gp2), 14, Color(1.0, 0.95, 0.6), HORIZONTAL_ALIGNMENT_CENTER, W)
	ui.button(c, "go", Rect2(W / 2.0 - 160.0, H - 90.0, 320.0, 60.0), "出発！", go_ok, Color(1.0, 0.8, 0.35), 30)

func _draw_records(c: Control) -> void:
	_bg(c)
	ui.center(c, "記録・実績", 76.0, 40, Color(1, 0.9, 0.6))
	var st: Dictionary = Settings.stats
	var lines := [
		Loc.t("プレイ回数: %d") % st["runs"], Loc.t("クリア回数: %d") % st["wins"], Loc.t("最高到達階: %d") % st["best_floor"],
		Loc.t("エンドレス最高: %dウェーブ") % st["endless_best"], Loc.t("1ランの最多撃破: %d") % st["best_kills"], Loc.t("累計撃破: %d") % st["total_kills"],
		Loc.t("最高コンボ: %d") % st["best_combo"], Loc.t("PERFECT累計: %d") % st["perfects"], Loc.t("フィーバー発動: %d回") % st["fevers"],
		Loc.t("解放済みアセンション: %d") % st["asc_unlocked"],
	]
	ui.panel(c, Rect2(60, 120, 340, 420))
	for i in lines.size():
		ui.text(c, lines[i], Vector2(80, 160 + i * 36), 17, Color.WHITE)
	var cnt := 0
	for id in Achievements.ORDER:
		if Settings.ach.has(id):
			cnt += 1
	ui.text(c, Loc.t("実績 %d / %d") % [cnt, Achievements.ORDER.size()], Vector2(430, 140), 20, Color(1, 0.9, 0.5))
	for i in Achievements.ORDER.size():
		var id: String = Achievements.ORDER[i]
		var got := Settings.ach.has(id)
		var r := Rect2(430.0 + (i % 2) * 410.0, 156.0 + (i / 2) * 50.0, 400.0, 44.0)
		c.draw_rect(r, Color(0.2, 0.17, 0.05, 0.9) if got else Color(0.1, 0.1, 0.15, 0.85))
		c.draw_rect(r, Color(1, 0.85, 0.3) if got else Color(0.35, 0.35, 0.45), false, 2.0)
		ui.text(c, ("★ " if got else "☆ ") + Achievements.DB[id]["name"], r.position + Vector2(10, 19), 16, Color(1, 0.92, 0.55) if got else Color(0.6, 0.6, 0.7))
		ui.text(c, Achievements.DB[id]["desc"], r.position + Vector2(10, 37), 11, Color(0.85, 0.85, 0.9) if got else Color(0.5, 0.5, 0.6))
	ui.button(c, "back", Rect2(W / 2.0 - 100.0, H - 70.0, 200.0, 48), "もどる", true, Color(0.55, 0.5, 0.95), 22)

func _draw_toasts(c: Control) -> void:
	for i in toasts.size():
		var tt: Dictionary = toasts[i]
		var k := minf(1.0, float(tt["t"]) * 3.0) * minf(1.0, (4.0 - float(tt["t"])) * 4.0)
		var r := Rect2(W / 2.0 - 190.0, -60.0 + 78.0 * k + i * 64.0, 380.0, 56.0)
		c.draw_rect(Rect2(r.position + Vector2(3, 4), r.size), Color(0, 0, 0, 0.5))
		c.draw_rect(r, Color(0.16, 0.12, 0.03, 0.97))
		c.draw_rect(r, Color(1, 0.85, 0.3), false, 3.0)
		ui.text(c, "実績解除！", r.position + Vector2(14, 22), 13, Color(1, 0.85, 0.4))
		ui.text(c, "★ " + Achievements.DB[tt["id"]]["name"], r.position + Vector2(14, 44), 20, Color.WHITE)

func _toggle_btn(c: Control, id: String, r: Rect2, label: String, on: bool, value := "") -> void:
	var txt := value if value != "" else ("ON" if on else "OFF")
	ui.button(c, id, r, "%s:  %s" % [Loc.t(label), Loc.t(txt)], true, Color(0.5, 0.9, 0.6) if on else Color(0.6, 0.6, 0.75), 18)

func _arrow_row(c: Control, id_minus: String, id_plus: String, y: float, label: String, value: String) -> void:
	ui.text(c, label, Vector2(290.0, y + 26.0), 20, Color.WHITE)
	ui.button(c, id_minus, Rect2(SL_X, y, 56.0, 36.0), "◀", true, Color(0.6, 0.6, 0.9), 20)
	ui.text(c, value, Vector2(SL_X + 60.0, y + 26.0), 17, Color(1, 0.9, 0.4), HORIZONTAL_ALIGNMENT_CENTER, 300.0)
	ui.button(c, id_plus, Rect2(SL_X + 364.0, y, 56.0, 36.0), "▶", true, Color(0.6, 0.6, 0.9), 20)

const KEY_ROWS_L := ["card1", "card2", "card3", "card4", "card5", "potion1", "potion2"]
const KEY_ROWS_R := ["potion3", "potion4", "up", "down", "left", "right", "pause"]

func _action_label(a: String) -> String:
	if a.begins_with("card"):
		return Loc.t("カード%d") % int(a.substr(4))
	if a.begins_with("potion"):
		return Loc.t("ポーション%d") % int(a.substr(6))
	return {"up": Loc.t("上へ移動"), "down": Loc.t("下へ移動"), "left": Loc.t("左へ移動"), "right": Loc.t("右へ移動"), "pause": Loc.t("ポーズ")}[a]

func _key_col(c: Control, rows: Array, x0: float) -> void:
	for i in rows.size():
		var act: String = rows[i]
		var y := 190.0 + i * 52.0
		ui.text(c, _action_label(act), Vector2(x0, y + 26.0), 17, Color.WHITE)
		for slot in 2:
			var waiting := rebind_action == act and rebind_slot == slot
			var lab := Loc.t("キーを押す…") if waiting else Settings.key_name(Settings.keymap[act][slot])
			ui.button(c, "keybind:%s:%d" % [act, slot], Rect2(x0 + 150.0 + slot * 150.0, y, 140.0, 38.0), lab, true, Color(1.0, 0.85, 0.3) if waiting else Color(0.6, 0.65, 0.95), 15)

func _draw_beat_tester(c: Control) -> void:
	var cx := 1110.0
	var cy := 230.0
	ui.button_hit(c, "beat_tap", Rect2(cx - 70.0, cy - 70.0, 140.0, 140.0))
	c.draw_circle(Vector2(cx, cy), 36.0 + 22.0 * menu_pulse, Color(1, 0.9, 0.4, 0.15 + 0.4 * menu_pulse))
	c.draw_arc(Vector2(cx, cy), 36.0, 0.0, TAU, 32, Color(1, 1, 1, 0.8 if ui.is_hover("beat_tap") else 0.6), 3.0)
	ui.text(c, "ビートを試す", Vector2(cx - 100.0, cy + 66.0), 15, Color(0.9, 0.9, 1.0), HORIZONTAL_ALIGNMENT_CENTER, 200.0)
	ui.text(c, "Space / クリック", Vector2(cx - 100.0, cy + 86.0), 12, Color(0.7, 0.7, 0.85), HORIZONTAL_ALIGNMENT_CENTER, 200.0)
	if beat_msg_t > 0.0:
		ui.text(c, beat_msg, Vector2(cx - 120.0, cy + 118.0), 17, Color(beat_msg_col, minf(1.0, beat_msg_t * 2.0)), HORIZONTAL_ALIGNMENT_CENTER, 240.0)
	if beat_hist.size() > 0:
		var sum := 0.0
		for v in beat_hist:
			sum += v
		ui.text(c, Loc.t("平均 %+d ms  (%d回)") % [int(round(sum / beat_hist.size())), beat_hist.size()], Vector2(cx - 120.0, cy + 144.0), 14, Color(0.9, 0.9, 1.0), HORIZONTAL_ALIGNMENT_CENTER, 240.0)
		ui.button(c, "avg_apply", Rect2(cx - 115.0, cy + 156.0, 230.0, 34.0), "平均をオフセットに反映", beat_hist.size() >= 3, Color(0.9, 0.7, 0.3), 13)

func _draw_settings(c: Control) -> void:
	_bg(c)
	ui.center(c, "設定", 62.0, 36, Color(1, 0.9, 0.6))
	var tabs := [["tab:audio", "音声・リズム"], ["tab:game", "ゲーム"], ["tab:keys", "キー設定"]]
	for i in 3:
		ui.button(c, tabs[i][0], Rect2(W / 2.0 - 375.0 + i * 260.0, 78.0, 240.0, 40.0), tabs[i][1], true, Color(1.0, 0.8, 0.35) if settings_tab == i else Color(0.55, 0.5, 0.95), 18)
	var x := 290.0
	if settings_tab == 0:
		ui.text(c, "音楽音量", Vector2(x, 170), 20, Color.WHITE)
		ui.slider(c, "sl:music", Rect2(SL_X, 156.0, SL_W, 16.0), Settings.music_vol)
		ui.text(c, "%d%%" % int(Settings.music_vol * 100.0), Vector2(SL_X + SL_W + 20.0, 172), 18, Color.WHITE)
		ui.text(c, "効果音量", Vector2(x, 218), 20, Color.WHITE)
		ui.slider(c, "sl:sfx", Rect2(SL_X, 204.0, SL_W, 16.0), Settings.sfx_vol)
		ui.text(c, "%d%%" % int(Settings.sfx_vol * 100.0), Vector2(SL_X + SL_W + 20.0, 220), 18, Color.WHITE)
		ui.text(c, "ハンドクラップ", Vector2(x, 282), 20, Color.WHITE)
		ui.button(c, "clap", Rect2(SL_X, 256.0, 130.0, 36.0), "ON" if Settings.clap_on else "OFF", true, Color(0.5, 0.9, 0.6) if Settings.clap_on else Color(0.6, 0.6, 0.7), 18)
		ui.button(c, "pat", Rect2(SL_X + 150.0, 256.0, 270.0, 36.0), "毎拍に鳴らす" if Settings.clap_pat == 0 else "2・4拍のみ鳴らす", true, Color(0.6, 0.7, 1.0), 16)
		ui.text(c, "クラップ音量", Vector2(x, 332), 20, Color.WHITE)
		ui.slider(c, "sl:clap", Rect2(SL_X, 318.0, SL_W, 16.0), Settings.clap_vol, Color(1.0, 0.8, 0.35))
		ui.text(c, "%d%%" % int(Settings.clap_vol * 100.0), Vector2(SL_X + SL_W + 20.0, 334), 18, Color.WHITE)
		_arrow_row(c, "clap-", "clap+", 358.0, "クラップの音", Conductor.CLAP_NAMES[Settings.clap_type])
		var bt := Conductor.battle_tracks()
		var bname := "ランダム (戦闘ごと)" if Settings.bgm < 0 else "%s  (%d BPM)" % [Conductor.TRACKS[bt[Settings.bgm]]["name"], int(Conductor.TRACKS[bt[Settings.bgm]]["bpm"])]
		_arrow_row(c, "bgm-", "bgm+", 412.0, "戦闘BGM", bname)
		ui.text(c, "判定オフセット", Vector2(x, 494), 20, Color.WHITE)
		ui.button(c, "off-", Rect2(SL_X, 468.0, 56.0, 36.0), "－", true, Color(0.6, 0.6, 0.9), 22)
		ui.text(c, "%+d ms" % Settings.offset_ms, Vector2(SL_X + 60.0, 494), 20, Color(1, 0.9, 0.4), HORIZONTAL_ALIGNMENT_CENTER, 130.0)
		ui.button(c, "off+", Rect2(SL_X + 200.0, 468.0, 56.0, 36.0), "＋", true, Color(0.6, 0.6, 0.9), 22)
		ui.button(c, "calib", Rect2(SL_X + 270.0, 468.0, 220.0, 36.0), "自動キャリブレーション", true, Color(0.9, 0.7, 0.3), 15)
		ui.text(c, "クラップは戦闘・チュートリアル・この画面で拍を知らせます。戦闘開始時は4拍のカウントダウン付き。", Vector2(0, 540), 13, Color(0.7, 0.7, 0.85), HORIZONTAL_ALIGNMENT_CENTER, W)
		ui.text(c, "右の円をクリック/Spaceで押すと、判定とズレ(ms)を確認できます。", Vector2(0, 562), 13, Color(0.7, 0.7, 0.85), HORIZONTAL_ALIGNMENT_CENTER, W)
		_draw_beat_tester(c)
	elif settings_tab == 1:
		_toggle_btn(c, "shake", Rect2(290, 190, 340, 44), "画面揺れ", Settings.shake)
		_toggle_btn(c, "flash", Rect2(650, 190, 340, 44), "フラッシュ軽減", Settings.reduce_flash)
		_toggle_btn(c, "fullscreen", Rect2(290, 250, 340, 44), "フルスクリーン", Settings.fullscreen)
		var al := ["オフ", "広い", "とても広い"]
		_toggle_btn(c, "assist", Rect2(650, 250, 340, 44), "判定アシスト", Settings.assist > 0, al[Settings.assist])
		ui.button(c, "lang", Rect2(290, 320, 700, 44), "言語 / Language:  " + ("日本語" if Settings.lang == "ja" else "English"), true, Color(1.0, 0.8, 0.35), 18)
	else:
		ui.text(c, "キー1", Vector2(150.0 + 120.0 - 20.0, 172.0), 13, Color(0.8, 0.8, 0.9))
		ui.text(c, "キー2", Vector2(150.0 + 270.0 - 20.0 + 40.0, 172.0), 13, Color(0.8, 0.8, 0.9))
		_key_col(c, KEY_ROWS_L, 100.0)
		_key_col(c, KEY_ROWS_R, 700.0)
		ui.text(c, "ボタンを押してから割り当てたいキーを押します(Escでキャンセル)。同じキーは他の操作から外れます。", Vector2(0, 566), 13, Color(0.7, 0.7, 0.85), HORIZONTAL_ALIGNMENT_CENTER, W)
		ui.button(c, "keys_reset", Rect2(W / 2.0 - 120.0, 580.0, 240.0, 36.0), "初期設定に戻す", true, Color(0.9, 0.6, 0.4), 16)
	ui.button(c, "back", Rect2(W / 2.0 - 120.0, 628.0, 240.0, 44.0), "もどる", true, Color(0.55, 0.5, 0.95), 22)

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
		ui.center(c, Loc.t("結果: %+d ms を設定しました") % Settings.offset_ms, 520.0, 28, Color(1, 0.9, 0.4))
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
	var fl := Loc.t("ウェーブ %d") % (run.wave + 1) if run.mode == "endless" else (Loc.t("第%d幕  %d / %d階") % [run.act, maxi(0, run.floor_idx + 1), MapGen.FLOORS + 1] if run.long_run else Loc.t("%d / %d階") % [maxi(0, run.floor_idx + 1), MapGen.FLOORS + 1])
	ui.text(c, fl, Vector2(150, 46), 15, Color(0.85, 0.85, 1.0))
	for i in run.relics.size():
		ui.relic_icon(c, run.relics[i], Rect2(300 + i * 34, 12, 30, 30), "relic:%d" % i)
	if run.daily:
		var dt := Loc.t("★ デイリー: %s") % Loc.t(RunState.MOD_NAMES[run.mod_id])
		ui.text(c, dt, Vector2(0, 47), 14, Color(1.0, 0.85, 0.3), HORIZONTAL_ALIGNMENT_CENTER, W)
	for i in run.potion_slots():
		var pr := Rect2(W - 282.0 - (run.potion_slots() - i) * 40.0, 10, 34, 34)
		if i < run.potions.size():
			var pd: Dictionary = Potions.DB[run.potions[i]]
			var pc: Color = pd["color"]
			var hv := ui.button_hit(c, "pot:%d" % i, pr)
			c.draw_rect(pr, Color(pc.r * 0.3, pc.g * 0.3, pc.b * 0.3))
			c.draw_rect(pr, pc.lerp(Color.WHITE, 0.4 if hv else 0.0), false, 2.0)
			ui.text(c, pd["glyph"], Vector2(pr.position.x, pr.position.y + 25), 20, pc.lerp(Color.WHITE, 0.4), HORIZONTAL_ALIGNMENT_CENTER, pr.size.x)
		else:
			c.draw_rect(pr, Color(0.1, 0.1, 0.16, 0.6))
			c.draw_rect(pr, Color(1, 1, 1, 0.15), false, 1.0)
	if show_deck:
		ui.button(c, "deck", Rect2(W - 224, 8, 160, 38), Loc.t("デッキ (%d)") % run.deck.size(), true, Color(0.5, 0.7, 1.0), 18)
	ui.button(c, "sys_open", Rect2(W - 54, 8, 44, 38), "≡", true, Color(0.7, 0.7, 0.9), 22)

func _relic_tips(c: Control) -> void:
	for i in run.potions.size():
		if ui.is_hover("pot:%d" % i) or ui.is_hover("potion:%d" % i):
			var pd: Dictionary = Potions.DB[run.potions[i]]
			ui.tooltip(c, pd["name"], pd["desc"], Vector2(ui.mouse.x, ui.mouse.y))
	for i in run.relics.size():
		if ui.is_hover("relic:%d" % i):
			var d: Dictionary = Relics.DB[run.relics[i]]
			ui.tooltip(c, d["name"], d["desc"], Vector2(ui.mouse.x, ui.mouse.y))

## Available next nodes, ordered left to right.
func _map_avail() -> Array:
	var nf := run.floor_idx + 1
	var av: Array = []
	if nf > MapGen.FLOORS:
		return av
	if run.floor_idx == -1:
		for j in run.map[0].size():
			av.append(j)
	else:
		av = (run.map[run.floor_idx][run.node_idx]["next"] as Array).duplicate()
	var row: Array = run.map[nf]
	av.sort_custom(func(a: int, b: int) -> bool: return float(row[a]["col"]) < float(row[b]["col"]))
	return av

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
				var order: int = _map_avail().find(j)
				if order == map_focus:
					c.draw_arc(p, rad + 12.0, 0.0, TAU, 32, Color(1, 1, 1, 0.95), 4.0)
					ui.text(c, "▼", Vector2(p.x - 20.0, p.y - rad - 16.0 - 4.0 * sin(t * 8.0)), 26, Color(1, 0.95, 0.4), HORIZONTAL_ALIGNMENT_CENTER, 40.0)
				if not touch_mode:
					ui.text(c, "[%d]" % (order + 1), Vector2(p.x - 20.0, p.y + rad + 20.0), 13, Color(1, 1, 0.8), HORIZONTAL_ALIGNMENT_CENTER, 40.0)
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
	if not touch_mode:
		ui.center(c, "← → / A D で選択   Enter / Space で決定   1〜4 で直接選択", H - 18.0, 14, Color(0.9, 0.9, 1.0, 0.8))
	if act_banner > 0.0:
		var ab := minf(1.0, act_banner)
		c.draw_rect(Rect2(0, 250, W, 120), Color(0, 0, 0, 0.6 * ab))
		ui.center(c, Loc.t("第%d幕  開幕") % run.act, 330.0, 64, Color(1, 0.6, 0.4, ab))
	_relic_tips(c)

func _node_pos(f: int, j: int) -> Vector2:
	var col: float = run.map[f][j]["col"]
	return Vector2(W / 2.0 + (col - 1.5) * 180.0, 650.0 - f * 52.0)

func _draw_reward(c: Control) -> void:
	_bg(c)
	_run_bar(c)
	ui.center(c, "勝利！", 110.0, 52, Color(1, 0.9, 0.4))
	ui.center(c, Loc.t("+%d G 獲得  /  カードを1枚選ぼう") % reward_gold if reward_picked < 0 else Loc.t("+%d G 獲得  /  別のカードを押すと変更できます") % reward_gold, 150.0, 22, Color(1, 0.85, 0.4))
	for i in reward_cards.size():
		var rr := Rect2(W / 2.0 - 255.0 + i * 180.0, 200.0, 160.0, 250.0)
		if i == reward_picked:
			ui.card(c, reward_cards[i], rr, str(i + 1), true, true, "rw:%d" % i)
			c.draw_rect(rr.grow(5.0), Color(1, 0.95, 0.4, 0.6 + 0.4 * sin(t * 6.0)), false, 4.0)
			ui.text(c, "獲得！(もう一度押すと取消)", Vector2(rr.position.x - 10.0, rr.position.y - 8.0), 14, Color(1, 0.95, 0.4), HORIZONTAL_ALIGNMENT_CENTER, rr.size.x + 20.0)
		else:
			ui.card(c, reward_cards[i], rr, str(i + 1), true, false, "rw:%d" % i)
	if reward_relic != "":
		var d: Dictionary = Relics.DB[reward_relic]
		ui.panel(c, Rect2(W / 2.0 - 260.0, 485.0, 520.0, 56.0), Color(0.1, 0.08, 0.04, 0.95), Color(1, 0.85, 0.4))
		ui.text(c, Loc.t("レリック: %s - %s") % [d["name"], d["desc"]], Vector2(W / 2.0 - 250.0, 520.0), 16, Color(1, 0.95, 0.7))
		ui.button(c, "relic_take", Rect2(W / 2.0 + 280.0, 485.0, 110.0, 56.0), "受け取る", true, Color(1.0, 0.8, 0.3), 18)
	if reward_potion != "":
		var pd: Dictionary = Potions.DB[reward_potion]
		var full := run.potions.size() >= run.potion_slots()
		ui.panel(c, Rect2(W / 2.0 - 260.0, 550.0, 520.0, 50.0), Color(0.05, 0.08, 0.1, 0.95), pd["color"])
		ui.text(c, Loc.t("ポーション: %s - %s") % [pd["name"], pd["desc"]], Vector2(W / 2.0 - 250.0, 581.0), 15, Color(0.95, 1, 0.95))
		ui.button(c, "potion_take", Rect2(W / 2.0 + 280.0, 550.0, 110.0, 50.0), "満杯" if full else "受け取る", not full, pd["color"], 18)
	if reward_picked >= 0 or reward_cards.is_empty():
		var gp3 := 0.5 + 0.5 * sin(t * 6.0)
		c.draw_rect(Rect2(W / 2.0 - 120.0, 626.0, 240.0, 54.0).grow(3.0 + 3.0 * gp3), Color(0.6, 1.0, 0.7, 0.5 + 0.4 * gp3), false, 3.0)
		ui.button(c, "skip", Rect2(W / 2.0 - 120.0, 626.0, 240.0, 54.0), "進む [S]", true, Color(0.5, 0.9, 0.6), 22)
	else:
		ui.button(c, "skip", Rect2(W / 2.0 - 120.0, 630.0, 240.0, 48.0), "スキップして進む [S]", true, Color(0.6, 0.6, 0.8), 18)
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
	var heal := int(run.max_hp * (0.45 if run.has_relic("fuel") else 0.3))
	ui.button(c, "rest:heal", Rect2(W / 2.0 - 340.0, 420.0, 320.0, 110.0), Loc.t("休む  HP +%d") % heal, true, Color(0.4, 0.9, 0.5), 24)
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
		title = Loc.t("削除するカードを選ぶ (%dG)") % (50 + 25 * shop_removed)
	elif pick_mode == "remove_free":
		title = "削除するカードを選ぶ (無料)"
	ui.center(c, title, 92.0, 30, Color(1, 0.9, 0.6))
	_deck_grid(c, pick_preview < 0)
	if pick_mode != "remove_free" and pick_preview < 0:
		ui.button(c, "back", Rect2(40, H - 70, 160, 48), "やめる", true, Color(0.6, 0.6, 0.8), 20)
	if pick_preview >= 0:
		_draw_upgrade_preview(c)

const PARAM_LABEL := {"dmg": "ダメージ", "n": "効果量", "beats": "持続拍数", "k": "係数", "max": "上限"}

func _draw_upgrade_preview(c: Control) -> void:
	var id: String = run.deck[pick_preview]
	var up_id := Cards.upgrade(id)
	var before: Dictionary = Cards.def(id)
	var after: Dictionary = Cards.def(up_id)
	c.draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, 0.82))
	ui.center(c, "強化の確認 - 性能比較", 90.0, 34, Color(1, 0.9, 0.6))
	var lx := W / 2.0 - 380.0
	var rx := W / 2.0 + 140.0
	ui.text(c, "現在", Vector2(lx, 150.0), 20, Color(0.8, 0.8, 0.9), HORIZONTAL_ALIGNMENT_CENTER, 240.0)
	ui.text(c, "強化後", Vector2(rx, 150.0), 20, Color(0.6, 1.0, 0.6), HORIZONTAL_ALIGNMENT_CENTER, 240.0)
	ui.card(c, id, Rect2(lx, 165.0, 240.0, 300.0), "", true, false)
	ui.card(c, up_id, Rect2(rx, 165.0, 240.0, 300.0), "", true, true)
	c.draw_rect(Rect2(rx, 165.0, 240.0, 300.0).grow(5.0), Color(0.5, 1.0, 0.6, 0.6 + 0.4 * sin(t * 6.0)), false, 4.0)
	ui.text(c, "▶", Vector2(W / 2.0 - 30.0, 330.0), 60, Color(1, 0.9, 0.4), HORIZONTAL_ALIGNMENT_CENTER, 60.0)
	# stat diff list
	var y := 490.0
	var lines: Array = []
	if int(before["cost"]) != int(after["cost"]):
		lines.append([Loc.t("コスト") + ":  %d  ->  %d" % [int(before["cost"]), int(after["cost"])], int(after["cost"]) < int(before["cost"])])
	var bp: Dictionary = before["p"]
	var ap: Dictionary = after["p"]
	for key in ap:
		var bv = bp.get(key, 0)
		if bv != ap[key]:
			lines.append([Loc.t(PARAM_LABEL.get(key, key)) + ":  %s  ->  %s" % [str(bv), str(ap[key])], true])
	if lines.is_empty():
		lines.append([Loc.t("変化: 名前に + が付く"), true])
	for ln in lines:
		ui.text(c, ln[0], Vector2(0, y), 20, Color(0.6, 1.0, 0.65) if ln[1] else Color(1, 0.7, 0.6), HORIZONTAL_ALIGNMENT_CENTER, W)
		y += 28.0
	ui.button(c, "up_ok", Rect2(W / 2.0 - 280.0, 628.0, 260.0, 54.0), "強化する [Enter]", true, Color(0.5, 0.9, 0.6), 22)
	ui.button(c, "up_cancel", Rect2(W / 2.0 + 20.0, 628.0, 260.0, 54.0), "もどる [Esc]", true, Color(0.6, 0.6, 0.8), 22)

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
		ui.button(c, "scroll:-1", Rect2(W - 80.0, 140.0, 56.0, 56.0), "▲", pick_scroll > 0, Color(0.6, 0.7, 1.0), 24)
		ui.button(c, "scroll:1", Rect2(W - 80.0, 206.0, 56.0, 56.0), "▼", pick_scroll < total_rows - rows_vis, Color(0.6, 0.7, 1.0), 24)
		ui.text(c, Loc.t("マウスホイール / ドラッグ / ▲▼でスクロール (%d/%d)") % [pick_scroll + 1, total_rows - rows_vis + 1], Vector2(0, H - 24.0), 14, Color(0.7, 0.7, 0.85), HORIZONTAL_ALIGNMENT_CENTER, W)

func _draw_deck_overlay(c: Control) -> void:
	c.draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, 0.85))
	ui.center(c, Loc.t("デッキ (%d枚)") % run.deck.size(), 92.0, 30, Color(1, 0.9, 0.6))
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
		ui.dms(c, r.position + Vector2(14, 50), d["desc"], HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 28.0, 14, -1, Color(0.9, 0.9, 0.95))
		ui.text(c, "%d G" % it["price"], r.position + Vector2(0, 92), 18, Color(1, 0.85, 0.3) if run.gold >= it["price"] else Color(0.7, 0.4, 0.4), HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 12.0)
	for i in shop_potions.size():
		var it: Dictionary = shop_potions[i]
		var pd: Dictionary = Potions.DB[it["id"]]
		var r := Rect2(880.0, 400.0 + i * 70.0, 300.0, 60.0)
		if it["sold"]:
			ui.text(c, "売り切れ", r.position + Vector2(0, 38), 18, Color(0.6, 0.6, 0.6), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
			continue
		var ok: bool = run.gold >= it["price"] and run.potions.size() < run.potion_slots()
		ui.button(c, "buy:p%d" % i, r, "", ok, pd["color"])
		ui.text(c, "%s  %s" % [pd["glyph"], pd["name"]], r.position + Vector2(14, 24), 18, pd["color"])
		ui.text(c, pd["desc"], r.position + Vector2(14, 46), 12, Color(0.9, 0.9, 0.95))
		ui.text(c, "%d G" % it["price"], r.position + Vector2(0, 24), 16, Color(1, 0.85, 0.3) if ok else Color(0.7, 0.4, 0.4), HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 12.0)
	var rc := 50 + 25 * shop_removed
	ui.button(c, "remove", Rect2(95.0, 470.0, 340.0, 60.0), Loc.t("カードを削除 (%d G)") % rc, run.gold >= rc and run.deck.size() > 5, Color(0.9, 0.5, 0.5), 20)
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

func _draw_sys_menu(c: Control) -> void:
	c.draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, 0.7))
	ui.center(c, "メニュー", 190.0, 52, Color(1, 0.95, 0.8))
	ui.button(c, "sys_resume", Rect2(W / 2.0 - 160.0, 250.0, 320.0, 56.0), "再開", true, Color(0.5, 0.9, 0.6), 26)
	ui.button(c, "sys_settings", Rect2(W / 2.0 - 160.0, 320.0, 320.0, 56.0), "設定", true, Color(0.55, 0.5, 0.95), 26)
	ui.button(c, "sys_title", Rect2(W / 2.0 - 160.0, 390.0, 320.0, 56.0), "タイトルへ戻る", true, Color(0.9, 0.5, 0.4), 24)
	ui.center(c, "Esc で閉じる", 480.0, 14, Color(0.8, 0.8, 0.9, 0.7))

func _draw_confirm(c: Control) -> void:
	c.draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, 0.78))
	ui.panel(c, Rect2(W / 2.0 - 300.0, 240.0, 600.0, 230.0), Color(0.08, 0.05, 0.1, 0.98), Color(1, 0.5, 0.4))
	ui.center(c, "タイトルに戻りますか？", 300.0, 30, Color(1, 0.9, 0.7))
	ui.center(c, "進行中のランは失われます。", 345.0, 18, Color(1, 0.7, 0.6))
	ui.button(c, "sys_yes", Rect2(W / 2.0 - 260.0, 390.0, 240.0, 52.0), "はい", true, Color(0.9, 0.4, 0.4), 22)
	ui.button(c, "sys_no", Rect2(W / 2.0 + 20.0, 390.0, 240.0, 52.0), "いいえ", true, Color(0.5, 0.9, 0.6), 22)

func _draw_pause(c: Control) -> void:
	c.draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, 0.65))
	ui.center(c, "ポーズ", 200.0, 56, Color(1, 0.95, 0.8))
	ui.button(c, "resume", Rect2(W / 2.0 - 160.0, 270.0, 320.0, 56.0), "再開", true, Color(0.5, 0.9, 0.6), 26)
	ui.button(c, "p_settings", Rect2(W / 2.0 - 160.0, 340.0, 320.0, 56.0), "設定", true, Color(0.55, 0.5, 0.95), 26)
	ui.button(c, "abandon", Rect2(W / 2.0 - 160.0, 410.0, 320.0, 56.0), "あきらめる", true, Color(0.9, 0.4, 0.4), 26)
	ui.button(c, "sys_title", Rect2(W / 2.0 - 160.0, 480.0, 320.0, 56.0), "タイトルへ戻る", true, Color(0.9, 0.5, 0.4), 24)

func _draw_end(c: Control) -> void:
	_bg(c, Color(0.05, 0.1, 0.06) if end_won else Color(0.12, 0.04, 0.05))
	ui.center(c, "VICTORY!" if end_won else "GAME OVER", 150.0, 80, Color(1, 0.9, 0.4) if end_won else Color(0.9, 0.3, 0.35))
	var cd: Dictionary = Characters.DB[run.char_id]
	c.draw_texture_rect(tex(int(cd["tile"])), Rect2(W / 2.0 - 40.0, 200.0, 80, 80), false)
	var lines: Array = []
	if run.mode == "run":
		lines.append((Loc.t("到達: 第%d幕  %d / %d階") % [run.act, maxi(0, run.floor_idx + 1), MapGen.FLOORS + 1]) if run.long_run else (Loc.t("到達階層: %d / %d") % [maxi(0, run.floor_idx + 1), MapGen.FLOORS + 1]))
	else:
		lines.append(Loc.t("到達ウェーブ: %d") % (run.wave + 1))
	lines.append(Loc.t("撃破数: %d    戦闘数: %d") % [run.kills, run.battles])
	lines.append(Loc.t("デッキ: %d枚    レリック: %d個    所持金: %dG") % [run.deck.size(), run.relics.size(), run.gold])
	for i in lines.size():
		ui.center(c, lines[i], 330.0 + i * 36.0, 24, Color.WHITE)
	ui.button(c, "retry", Rect2(W / 2.0 - 330.0, 520.0, 300.0, 60.0), "もう一度", true, Color(1.0, 0.8, 0.35), 26)
	ui.button(c, "menu", Rect2(W / 2.0 + 30.0, 520.0, 300.0, 60.0), "メニューへ", true, Color(0.55, 0.5, 0.95), 26)

# ---- headless / screenshot self-test --------------------------------------

func _bot_dir() -> Vector2:
	if _bot_human:
		# imperfect "human-like" movement: late/short-sighted flee, no bullet dodging, wobble
		_bot_noise_t -= get_process_delta_time()
		if _bot_noise_t <= 0.0:
			_bot_noise_t = 0.35
			_bot_noise = Vector2.from_angle(randf() * TAU) * 0.6
		var hv := (Vector2(W / 2.0, 220.0) - battle.player_pos) * 0.0015 + _bot_noise
		for e in battle.enemies:
			var hd: float = e.pos.distance_to(battle.player_pos)
			if hd < 110.0:
				hv += (battle.player_pos - e.pos).normalized() * (110.0 - hd) / 110.0
		return hv
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
	run.potions = ["heal", "bomb", "fury"]
	run.floor_idx = 2
	run.node_idx = 0
	run.map[0][0]["visited"] = true
	match sname:
		"menu": state = S.MENU
		"mode": state = S.MODE
		"char": state = S.CHAR
		"settings": state = S.SETTINGS
		"keys":
			state = S.SETTINGS
			settings_tab = 2
		"sysmenu":
			state = S.MAP
			sys_menu = true
		"records": state = S.RECORDS
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
		"upgrade":
			pick_mode = "upgrade"
			pick_return = S.REST
			state = S.PICK
			pick_preview = 0
		"daily":
			run.daily = true
			run.mod_id = 1
			state = S.MAP
		"tutorial": start_tutorial()
		"end":
			end_won = true
			state = S.END
		_:
			if sname == "act2" or sname == "maestro":
				run.start_act2()
				run.floor_idx = 3
				run.node_idx = 0
				run.max_hp = 400
				run.hp = 400
				_start_battle("boss" if sname == "maestro" else "battle")
			elif sname.begins_with("boss_"):
				run.boss_id = sname.substr(5)
				_start_battle("boss")
			else:
				_start_battle(sname if sname in ["boss", "elite"] else "battle")

var _shot_played := false

func _run_autotest(delta: float) -> void:
	_autotest_t += delta
	if _autotest and int(_autotest_t) % 40 == 0 and int(_autotest_t) != _last_prog:
		_last_prog = int(_autotest_t)
		print("AUTOPROGRESS t=%d state=%s act=%d wave=%d floor=%d hp=%d kills=%d" % [_last_prog, S.keys()[state], run.act, run.wave, run.floor_idx, run.hp, run.kills])
	if _shot_path != "" and state == S.BATTLE and battle and not _shot_played and _autotest_t > 5.6:
		_shot_played = true
		for i in 5:
			var id := battle.deck.hand[i]
			if id != "" and battle.energy >= int(Cards.def(id)["cost"]):
				battle.try_play(i)
				break
	if _shot_path != "" and _autotest_t > (7.0 if (_screen_arg in ["boss", "elite", "battle", "act2", "maestro"] or _screen_arg.begins_with("boss_")) else 1.0) and pending < 0:
		get_viewport().get_texture().get_image().save_png(_shot_path)
		print("shot saved")
		get_tree().quit()
		return
	if not _autotest or pending >= 0 or _shot_path != "":
		return
	if state == S.MENU and "--tutorial" in OS.get_cmdline_user_args():
		print("AUTOTEST tutorial_done=%s" % Settings.tutorial_done)
		get_tree().quit()
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
			if battle and not battle.ending and not run.potions.is_empty() and (run.hp < run.max_hp * 0.45 or battle.enemies.size() > 40):
				battle.use_potion(0)
			if battle and not battle.ending and _bot_human:
				var bn := floori((Conductor.song_time - Conductor.offset) / Conductor.spb)
				if bn != _bot_beat:
					_bot_beat = bn
					_bot_target = randfn(0.0, 0.055)
					_bot_played = false
				if not _bot_played and Conductor.beat_offset() >= _bot_target and Conductor.beat_offset() < 0.2:
					_bot_played = true
					if randf() < 0.55:
						var hs := randi() % 5
						var hid := battle.deck.hand[hs]
						if hid != "" and battle.energy >= int(Cards.def(hid)["cost"]):
							battle.try_play(hs)
			elif battle and not battle.ending and absf(Conductor.beat_offset()) < 0.03:
				var slot := randi() % 5
				var id := battle.deck.hand[slot]
				if id != "" and battle.energy >= int(Cards.def(id)["cost"]):
					battle.try_play(slot)
		S.REWARD:
			if reward_relic != "":
				_click("relic_take")
			if reward_potion != "":
				_click("potion_take")
			if reward_picked < 0:
				_click("rw:%d" % (randi() % 3))
			else:
				_click("skip")
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
				if pick_preview < 0:
					_pick_card(i)
				else:
					_click("up_ok")
			elif pick_mode == "remove_free":
				_pick_card(0)
			else:
				goto(pick_return)
		S.SHOP:
			for i in shop_cards.size():
				_click_prefixed("buy:c%d" % i)
			for i in shop_relics.size():
				_click_prefixed("buy:r%d" % i)
			proceed()
		S.EVENT:
			if event_result == "" or event_result == "カードを1枚選んで削除する。":
				if event_result == "":
					_click("ev:%d" % (randi() % (event_data["opts"] as Array).size()))
			else:
				_click("event_done")
		S.TREASURE:
			_click("treasure_take")
		S.END:
			print("AUTOTEST result=%s act=%d mode=%s char=%s floor=%d wave=%d kills=%d deck=%d relics=%d hp=%d/%d dmg_taken=%d t=%.1f" % ["WON" if end_won else "LOST", run.act, run.mode, run.char_id, run.floor_idx, run.wave, run.kills, run.deck.size(), run.relics.size(), run.hp, run.max_hp, run.dmg_taken, _autotest_t])
			get_tree().quit()
	if _autotest_t > 1500.0:
		print("AUTOTEST timeout state=%s floor=%d" % [S.keys()[state], run.floor_idx])
		get_tree().quit()

## Headless gamepad navigation test: --padtest (prints PADTEST lines).
func _padtest() -> void:
	for i in 4:
		await get_tree().process_frame
	pad_mode = true
	var seq: Array = []
	for i in 3:
		_pad_nav(Vector2.DOWN)
		seq.append(focus_id)
		await get_tree().process_frame
	print("PADTEST focus seq=", seq)
	_pad_nav(Vector2.UP)
	print("PADTEST after up=", focus_id)
	focus_id = "start"
	_pad_button(JOY_BUTTON_A)
	for i in 30:
		await get_tree().process_frame
	print("PADTEST state after A on start=", S.keys()[state])
	_pad_button(JOY_BUTTON_B)
	for i in 30:
		await get_tree().process_frame
	print("PADTEST state after B=", S.keys()[state])
	_beat_tap()
	print("PADTEST beat tap -> ", beat_msg)
	Settings.bind("card1", 1, KEY_Q)
	print("PADTEST bind Q ->", Settings.action_for_key(KEY_Q), " card1 keys=", Settings.keymap["card1"])
	Settings.bind("potion1", 0, KEY_Q)
	print("PADTEST rebind steals key ->", Settings.action_for_key(KEY_Q), Settings.keymap["card1"])
	Settings.reset_keys()
	# one-card-at-a-time lockout
	_start_battle("tutorial")
	for i in 400:
		await get_tree().process_frame
		if battle.started:
			break
	var p0 := battle.plays
	battle.try_play(0)
	battle.try_play(1)
	battle.try_play(2)
	print("PADTEST simultaneous presses -> plays added=", battle.plays - p0, " (started=", battle.started, ")")
	get_tree().quit()
