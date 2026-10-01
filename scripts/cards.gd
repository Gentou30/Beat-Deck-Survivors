class_name Cards
## Card ids are strings; a trailing "+" marks the upgraded version (e.g. "pulse+").
## DB entries: name/cost/type/color/tmpl (desc template using {param}), p = params,
## plus = upgrade overrides ({"p": {...}, "cost": n}). Powers last for the whole battle.

const DB := {
	"pulse": {"name": "パルスショット", "cost": 1, "type": "attack", "color": Color(0.95, 0.45, 0.35),
		"tmpl": "近くの敵に弾を{n}発。各{dmg}ダメージ。", "p": {"n": 3, "dmg": 8}, "plus": {"p": {"n": 4, "dmg": 9}}},
	"chain": {"name": "チェインボルト", "cost": 1, "type": "attack", "color": Color(0.95, 0.85, 0.3),
		"tmpl": "近い敵{n}体に雷撃。各{dmg}ダメージ。", "p": {"n": 5, "dmg": 10}, "plus": {"p": {"n": 7, "dmg": 12}}},
	"nova": {"name": "ノヴァ", "cost": 2, "type": "attack", "color": Color(0.95, 0.5, 0.8),
		"tmpl": "周囲に{dmg}ダメージ+吹き飛ばし。", "p": {"dmg": 20}, "plus": {"p": {"dmg": 30}}},
	"blades": {"name": "ビートブレード", "cost": 1, "type": "attack", "color": Color(0.4, 0.8, 0.95),
		"tmpl": "{beats}ビートの間、剣{n}本が周囲を回る。", "p": {"beats": 10, "n": 3}, "plus": {"p": {"beats": 14, "n": 4}}},
	"bass": {"name": "ベースドロップ", "cost": 3, "type": "attack", "color": Color(0.7, 0.4, 0.95), "exhaust": true,
		"tmpl": "全ての敵に{dmg}ダメージ。廃棄。", "p": {"dmg": 30}, "plus": {"p": {"dmg": 45}}},
	"leech": {"name": "リーチウェーブ", "cost": 1, "type": "attack", "color": Color(0.8, 0.25, 0.45),
		"tmpl": "周囲に{dmg}ダメージ。命中ごとにHP1回復(最大{max})。", "p": {"dmg": 10, "max": 6}, "plus": {"p": {"dmg": 14, "max": 9}}},
	"heavy": {"name": "ヘビーコード", "cost": 2, "type": "attack", "color": Color(1.0, 0.6, 0.2),
		"tmpl": "前方を貫く極太ビーム。{dmg}ダメージ。", "p": {"dmg": 45}, "plus": {"p": {"dmg": 65}}},
	"guard": {"name": "ガード", "cost": 1, "type": "skill", "color": Color(0.4, 0.6, 0.95),
		"tmpl": "シールドを{n}得る。", "p": {"n": 8}, "plus": {"p": {"n": 12}}},
	"mend": {"name": "ヒール", "cost": 1, "type": "skill", "color": Color(0.4, 0.9, 0.5),
		"tmpl": "HPを{n}回復。", "p": {"n": 10}, "plus": {"p": {"n": 15}}},
	"surge": {"name": "サージ", "cost": 0, "type": "skill", "color": Color(0.9, 0.9, 0.5),
		"tmpl": "エネルギーを{n}得る。", "p": {"n": 2}, "plus": {"p": {"n": 3}}},
	"frenzy": {"name": "フレンジー", "cost": 1, "type": "skill", "color": Color(0.95, 0.65, 0.3),
		"tmpl": "{beats}ビートの間、与ダメージ2倍。", "p": {"beats": 8}, "plus": {"p": {"beats": 12}}},
	"freeze": {"name": "フリーズビート", "cost": 1, "type": "skill", "color": Color(0.55, 0.85, 1.0),
		"tmpl": "{beats}ビートの間、敵を大きく減速。", "p": {"beats": 6}, "plus": {"p": {"beats": 10}}},
	"echo": {"name": "エコー", "cost": 1, "type": "skill", "color": Color(0.85, 0.7, 1.0),
		"tmpl": "次に使うカードを2回発動する。", "p": {}, "plus": {"cost": 0}},
	"resonance": {"name": "レゾナンス", "cost": 2, "type": "power", "color": Color(1.0, 0.4, 0.5),
		"tmpl": "【パワー】自動弾のダメージ+{n}。", "p": {"n": 3}, "plus": {"p": {"n": 5}, "cost": 1}},
	"fortress": {"name": "フォートレス", "cost": 1, "type": "power", "color": Color(0.5, 0.7, 1.0),
		"tmpl": "【パワー】4ビートごとにシールド{n}。", "p": {"n": 3}, "plus": {"p": {"n": 5}}},
	"aura": {"name": "吸血オーラ", "cost": 2, "type": "power", "color": Color(0.75, 0.2, 0.55),
		"tmpl": "【パワー】{k}体撃破ごとにHP1回復。", "p": {"k": 6}, "plus": {"p": {"k": 4}}},
	"pierce": {"name": "貫通弾", "cost": 1, "type": "attack", "color": Color(0.7, 0.95, 1.0),
		"tmpl": "最大6体を貫く弾。{dmg}ダメージ。", "p": {"dmg": 14}, "plus": {"p": {"dmg": 20}}},
	"meteor": {"name": "メテオコール", "cost": 2, "type": "attack", "color": Color(1.0, 0.5, 0.25),
		"tmpl": "敵が密集する場所に2拍後に着弾。{dmg}ダメージ。", "p": {"dmg": 45}, "plus": {"p": {"dmg": 70}}},
	"drum": {"name": "ドラムロール", "cost": 1, "type": "attack", "color": Color(0.95, 0.75, 0.4),
		"tmpl": "全方位に弾を{n}発。各{dmg}ダメージ。", "p": {"n": 8, "dmg": 6}, "plus": {"p": {"n": 12, "dmg": 7}}},
	"sonic": {"name": "ソニックブーム", "cost": 1, "type": "attack", "color": Color(0.6, 0.85, 1.0),
		"tmpl": "前方の扇形に{dmg}ダメージ+吹き飛ばし+2拍スタン。", "p": {"dmg": 8}, "plus": {"p": {"dmg": 14}}},
	"replay": {"name": "リプレイ", "cost": 1, "type": "skill", "color": Color(0.85, 0.7, 1.0),
		"tmpl": "直前に使ったカードをもう一度発動。", "p": {}, "plus": {"cost": 0}},
	"phase": {"name": "フェイズステップ", "cost": 0, "type": "skill", "color": Color(0.75, 0.9, 1.0),
		"tmpl": "移動方向へ瞬間移動し、1秒間無敵。", "p": {}, "plus": {"p": {}}},
	"pguard": {"name": "コンボガード", "cost": 1, "type": "skill", "color": Color(0.4, 0.75, 1.0),
		"tmpl": "コンボ数×{k}のシールドを得る(最大コンボ20)。", "p": {"k": 2}, "plus": {"p": {"k": 3}}},
	"overdrive": {"name": "オーバードライブ", "cost": 1, "type": "skill", "color": Color(1.0, 0.45, 0.35),
		"tmpl": "次の{n}枚のカードの威力が1.5倍。", "p": {"n": 3}, "plus": {"p": {"n": 4}}},
	"feverboost": {"name": "フィーバーブースト", "cost": 0, "type": "skill", "color": Color(1.0, 0.85, 0.2), "exhaust": true,
		"tmpl": "フィーバーゲージ+{n}。廃棄。", "p": {"n": 4}, "plus": {"p": {"n": 6}}},
	"heartbeat": {"name": "ハートビート", "cost": 1, "type": "power", "color": Color(1.0, 0.4, 0.5),
		"tmpl": "【パワー】{k}拍ごとにHP1回復。", "p": {"k": 8}, "plus": {"p": {"k": 5}}},
	"thorns": {"name": "トゲのオーラ", "cost": 1, "type": "power", "color": Color(0.5, 0.9, 0.4),
		"tmpl": "【パワー】触れた敵に{n}ダメージ。", "p": {"n": 8}, "plus": {"p": {"n": 14}}},
}

const SHORT := {
	"pulse": "弾{n}発 各{dmg}", "chain": "{n}体に雷撃 各{dmg}", "nova": "範囲{dmg}+吹き飛ばし",
	"blades": "剣{n}本 {beats}拍", "bass": "全体に{dmg}", "leech": "範囲{dmg} 吸収最大{max}",
	"heavy": "貫通ビーム{dmg}", "guard": "シールド+{n}", "mend": "HP+{n}", "surge": "エネルギー+{n}",
	"frenzy": "与ダメ2倍 {beats}拍", "freeze": "敵を減速 {beats}拍", "echo": "次のカードを2回発動",
	"resonance": "自動弾+{n} (永続)", "fortress": "4拍ごとシールド+{n}", "aura": "{k}体撃破でHP+1",
	"pierce": "貫通弾 {dmg} (6体)", "meteor": "2拍後に着弾 {dmg}", "drum": "全方位に{n}発 各{dmg}", "sonic": "扇形{dmg}+スタン",
	"replay": "直前のカードを再発動", "phase": "瞬間移動+無敵1秒", "pguard": "コンボ×{k}のシールド", "overdrive": "次の{n}枚 威力1.5倍",
	"feverboost": "フィーバー+{n}", "heartbeat": "{k}拍ごとHP+1", "thorns": "接触した敵に{n}",
}

const ART := {
	"pulse": 129, "chain": 130, "nova": 127, "blades": 104, "bass": 118, "leech": 115, "heavy": 117,
	"guard": 101, "mend": 114, "surge": 116, "frenzy": 107, "freeze": 128, "echo": 105,
	"resonance": 125, "fortress": 102, "aura": 126, "pierce": 131, "meteor": 119, "drum": 82,
	"sonic": 62, "replay": 60, "phase": 103, "pguard": 100, "overdrive": 106, "feverboost": 92,
	"heartbeat": 61, "thorns": 76,
}

static func art(id: String) -> int:
	return ART.get(base_id(id), 104)

const TYPE_JA := {"attack": "アタック", "skill": "スキル", "power": "パワー"}

static func is_upgraded(id: String) -> bool:
	return id.ends_with("+")

static func base_id(id: String) -> String:
	return id.trim_suffix("+")

## Resolved definition: name, cost, type, color, p (params), desc, exhaust, up.
static func def(id: String) -> Dictionary:
	var up := is_upgraded(id)
	var b: Dictionary = DB[base_id(id)]
	var p: Dictionary = (b["p"] as Dictionary).duplicate()
	var cost: int = b["cost"]
	if up:
		var plus: Dictionary = b["plus"]
		if plus.has("p"):
			p.merge(plus["p"], true)
		if plus.has("cost"):
			cost = plus["cost"]
	var t: String = b["type"]
	return {
		"name": Loc.t(String(b["name"])) + ("+" if up else ""),
		"cost": cost, "type": t, "color": b["color"], "p": p,
		"desc": Loc.t(String(b["tmpl"])).format(p),
		"exhaust": b.get("exhaust", false) or t == "power",
		"up": up,
	}

## One-line effect summary shown when a card is played.
static func short(id: String) -> String:
	return Loc.t(String(SHORT[base_id(id)])).format(def(id)["p"])

static func upgrade(id: String) -> String:
	return id if is_upgraded(id) else id + "+"

static func random_choices(n: int) -> Array:
	var ids: Array = DB.keys()
	ids.shuffle()
	return ids.slice(0, n)

static func price(id: String) -> int:
	return 45 + int(DB[base_id(id)]["cost"]) * 18 + (20 if DB[base_id(id)]["type"] == "power" else 0)
