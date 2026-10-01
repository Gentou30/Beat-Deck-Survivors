class_name Cards

# type: attack / skill. All numbers are base values; timing grade scales them.
const DB := {
	"pulse": {"name": "Pulse Shot", "cost": 1, "type": "attack", "color": Color(0.95, 0.45, 0.35),
		"desc": "Fire 3 bolts at the nearest foes. 8 dmg each."},
	"chain": {"name": "Chain Bolt", "cost": 1, "type": "attack", "color": Color(0.95, 0.85, 0.3),
		"desc": "Lightning hits 5 nearest foes for 10."},
	"nova": {"name": "Nova", "cost": 2, "type": "attack", "color": Color(0.95, 0.5, 0.8),
		"desc": "Blast everything nearby for 20 and knock back."},
	"blades": {"name": "Beat Blades", "cost": 1, "type": "attack", "color": Color(0.4, 0.8, 0.95),
		"desc": "3 blades orbit you for 10 beats."},
	"bass": {"name": "Bass Drop", "cost": 3, "type": "attack", "color": Color(0.7, 0.4, 0.95),
		"desc": "Hit EVERY enemy for 30."},
	"guard": {"name": "Guard", "cost": 1, "type": "skill", "color": Color(0.4, 0.6, 0.95),
		"desc": "Gain 8 shield."},
	"mend": {"name": "Mend", "cost": 1, "type": "skill", "color": Color(0.4, 0.9, 0.5),
		"desc": "Heal 10 HP."},
	"surge": {"name": "Surge", "cost": 0, "type": "skill", "color": Color(0.9, 0.9, 0.5),
		"desc": "Gain 2 energy."},
	"frenzy": {"name": "Frenzy", "cost": 1, "type": "skill", "color": Color(0.95, 0.65, 0.3),
		"desc": "Double all damage for 8 beats."},
}

const STARTER := ["pulse", "pulse", "pulse", "pulse", "guard", "guard", "nova", "chain", "blades", "surge"]

static func random_choices(n: int) -> Array:
	var ids: Array = DB.keys()
	ids.shuffle()
	return ids.slice(0, n)
