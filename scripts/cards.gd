class_name Cards

# type: attack / skill. All numbers are base values; timing grade scales them.
const DB := {
	"pulse": {"name": "パルスショット", "cost": 1, "type": "attack", "color": Color(0.95, 0.45, 0.35),
		"desc": "近くの敵に弾を3発撃つ。各8ダメージ。"},
	"chain": {"name": "チェインボルト", "cost": 1, "type": "attack", "color": Color(0.95, 0.85, 0.3),
		"desc": "近い敵5体に雷撃。各10ダメージ。"},
	"nova": {"name": "ノヴァ", "cost": 2, "type": "attack", "color": Color(0.95, 0.5, 0.8),
		"desc": "周囲に20ダメージと吹き飛ばし。"},
	"blades": {"name": "ビートブレード", "cost": 1, "type": "attack", "color": Color(0.4, 0.8, 0.95),
		"desc": "10ビートの間、剣3本が周囲を回る。"},
	"bass": {"name": "ベースドロップ", "cost": 3, "type": "attack", "color": Color(0.7, 0.4, 0.95),
		"desc": "全ての敵に30ダメージ。"},
	"guard": {"name": "ガード", "cost": 1, "type": "skill", "color": Color(0.4, 0.6, 0.95),
		"desc": "シールドを8得る。"},
	"mend": {"name": "ヒール", "cost": 1, "type": "skill", "color": Color(0.4, 0.9, 0.5),
		"desc": "HPを10回復。"},
	"surge": {"name": "サージ", "cost": 0, "type": "skill", "color": Color(0.9, 0.9, 0.5),
		"desc": "エネルギーを2得る。"},
	"frenzy": {"name": "フレンジー", "cost": 1, "type": "skill", "color": Color(0.95, 0.65, 0.3),
		"desc": "8ビートの間、与ダメージ2倍。"},
}

const STARTER := ["pulse", "pulse", "pulse", "pulse", "guard", "guard", "nova", "chain", "blades", "surge"]

static func random_choices(n: int) -> Array:
	var ids: Array = DB.keys()
	ids.shuffle()
	return ids.slice(0, n)
