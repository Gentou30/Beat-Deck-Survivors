class_name Potions
## Single-use consumables (StS-style). Used in battle with 6/7/8 or by tapping the icon.

const DB := {
	"heal": {"name": "回復薬", "desc": "最大HPの30%を回復。", "price": 50, "color": Color(0.4, 0.9, 0.5), "glyph": "癒"},
	"energy": {"name": "活力薬", "desc": "エネルギーを3得る。", "price": 45, "color": Color(1.0, 0.85, 0.3), "glyph": "力"},
	"bomb": {"name": "爆弾", "desc": "全ての敵に40ダメージ。", "price": 55, "color": Color(0.95, 0.4, 0.3), "glyph": "爆"},
	"freeze": {"name": "氷結薬", "desc": "8ビートの間、敵を大きく減速。", "price": 50, "color": Color(0.55, 0.85, 1.0), "glyph": "氷"},
	"shield": {"name": "守りの薬", "desc": "シールドを20得る。", "price": 45, "color": Color(0.45, 0.65, 1.0), "glyph": "守"},
	"fury": {"name": "狂乱薬", "desc": "10ビート与ダメージ2倍+フィーバーゲージ+3。", "price": 60, "color": Color(0.95, 0.55, 0.9), "glyph": "狂"},
}

static func random_id() -> String:
	var ids: Array = DB.keys()
	return ids.pick_random()
