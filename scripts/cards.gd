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
}

const SHORT := {
	"pulse": "弾{n}発 各{dmg}", "chain": "{n}体に雷撃 各{dmg}", "nova": "範囲{dmg}+吹き飛ばし",
	"blades": "剣{n}本 {beats}拍", "bass": "全体に{dmg}", "leech": "範囲{dmg} 吸収最大{max}",
	"heavy": "貫通ビーム{dmg}", "guard": "シールド+{n}", "mend": "HP+{n}", "surge": "エネルギー+{n}",
	"frenzy": "与ダメ2倍 {beats}拍", "freeze": "敵を減速 {beats}拍", "echo": "次のカードを2回発動",
	"resonance": "自動弾+{n} (永続)", "fortress": "4拍ごとシールド+{n}", "aura": "{k}体撃破でHP+1",
}

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
		"name": String(b["name"]) + ("+" if up else ""),
		"cost": cost, "type": t, "color": b["color"], "p": p,
		"desc": String(b["tmpl"]).format(p),
		"exhaust": b.get("exhaust", false) or t == "power",
		"up": up,
	}

## One-line effect summary shown when a card is played.
static func short(id: String) -> String:
	return String(SHORT[base_id(id)]).format(def(id)["p"])

static func upgrade(id: String) -> String:
	return id if is_upgraded(id) else id + "+"

static func random_choices(n: int) -> Array:
	var ids: Array = DB.keys()
	ids.shuffle()
	return ids.slice(0, n)

static func price(id: String) -> int:
	return 45 + int(DB[base_id(id)]["cost"]) * 18 + (20 if DB[base_id(id)]["type"] == "power" else 0)
