class_name Characters

const DB := {
	"wizard": {"name": "ウィザード", "tile": 84, "hp": 55, "speed": 1.0, "color": Color(0.7, 0.5, 1.0),
		"passive": "アルカナ・リズム", "passive_desc": "コンボが5の倍数になるたび、エネルギー+1。",
		"starter": ["pulse", "pulse", "pulse", "pulse", "guard", "guard", "nova", "chain", "blades", "surge"]},
	"knight": {"name": "ヴァイキング", "tile": 87, "hp": 80, "speed": 0.9, "color": Color(0.95, 0.6, 0.35),
		"passive": "鉄の鼓動", "passive_desc": "戦闘開始時にシールド8。シールド獲得量+25%。",
		"starter": ["pulse", "pulse", "pulse", "guard", "guard", "guard", "nova", "blades", "mend", "frenzy"]},
	"ranger": {"name": "レンジャー", "tile": 112, "hp": 62, "speed": 1.15, "color": Color(0.5, 0.95, 0.55),
		"passive": "疾風", "passive_desc": "移動速度+15%。ビートごとの自動弾が2発になる。",
		"starter": ["chain", "chain", "chain", "pulse", "pulse", "surge", "surge", "frenzy", "guard", "blades"]},
	"drummer": {"name": "ドラマー", "tile": 86, "hp": 58, "speed": 1.0, "color": Color(1.0, 0.78, 0.35),
		"passive": "リズムマスター", "passive_desc": "PERFECT判定の幅+25ms。コンボ1あたりのダメージ上昇+1%。",
		"unlock": "ステージ攻略で第1幕のボスを倒すと解放",
		"starter": ["drum", "drum", "pulse", "pulse", "chain", "guard", "guard", "sonic", "surge", "frenzy"]},
}

const ORDER := ["wizard", "knight", "ranger", "drummer"]
