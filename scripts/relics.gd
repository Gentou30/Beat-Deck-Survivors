class_name Relics

const DB := {
	"metronome": {"name": "メトロノーム", "desc": "PERFECT判定の幅が+20ms広がる。", "price": 150, "color": Color(1.0, 0.9, 0.3)},
	"battery": {"name": "予備電池", "desc": "最大エネルギー+1。", "price": 170, "color": Color(0.9, 0.8, 0.2)},
	"coin": {"name": "幸運のコイン", "desc": "獲得ゴールド+50%。", "price": 120, "color": Color(1.0, 0.8, 0.3)},
	"heart": {"name": "鉄の心臓", "desc": "最大HP+15(取得時に全回復分も+15)。", "price": 140, "color": Color(0.9, 0.3, 0.35)},
	"fang": {"name": "吸血の牙", "desc": "8体撃破ごとにHP1回復。", "price": 130, "color": Color(0.8, 0.2, 0.5)},
	"amp": {"name": "ブーストアンプ", "desc": "コンボ1あたりのダメージ上昇が3%になる。", "price": 160, "color": Color(0.5, 0.8, 1.0)},
	"sword": {"name": "鋭い剣", "desc": "自動弾のダメージ+3。", "price": 130, "color": Color(0.8, 0.85, 0.95)},
	"boots": {"name": "俊足のブーツ", "desc": "移動速度+15%。", "price": 110, "color": Color(0.6, 0.45, 0.3)},
	"ring": {"name": "ビートリング", "desc": "戦闘開始時にシールド10。", "price": 120, "color": Color(0.4, 0.6, 1.0)},
}

static func random_ids(n: int, owned: Array) -> Array:
	var ids: Array = []
	for k in DB.keys():
		if not owned.has(k):
			ids.append(k)
	ids.shuffle()
	return ids.slice(0, n)
