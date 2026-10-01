class_name RunState
extends RefCounted

var mode := "run"  # run | endless
var char_id := "wizard"
var hp := 60
var max_hp := 60
var gold := 50
var deck: Array[String] = []
var relics: Array[String] = []
var potions: Array[String] = []
var boss_id := "bass"
var map: Array = []
var floor_idx := -1
var node_idx := -1
var wave := 0  # endless: battles completed
var kills := 0
var battles := 0
var dmg_taken := 0

func setup(p_mode: String, p_char: String) -> void:
	mode = p_mode
	char_id = p_char
	var c: Dictionary = Characters.DB[p_char]
	max_hp = c["hp"]
	hp = max_hp
	gold = 50
	deck.clear()
	for id in c["starter"]:
		deck.append(id)
	relics.clear()
	potions.clear()
	boss_id = ["bass", "drum", "metronome"].pick_random()
	floor_idx = -1
	node_idx = -1
	wave = 0
	kills = 0
	battles = 0
	dmg_taken = 0
	map = MapGen.generate() if p_mode == "run" else []

func has_relic(id: String) -> bool:
	return relics.has(id)

func add_relic(id: String) -> void:
	if relics.has(id):
		return
	relics.append(id)
	if id == "heart":
		max_hp += 15
		hp += 15

func max_energy() -> int:
	return 5 + (1 if has_relic("battery") else 0)

func gain_gold(n: int) -> int:
	var g := int(n * (1.5 if has_relic("coin") else 1.0))
	gold += g
	return g

func heal(n: int) -> void:
	hp = mini(max_hp, hp + n)

func potion_slots() -> int:
	return 3 + (1 if has_relic("belt") else 0)

func add_potion(id: String) -> bool:
	if potions.size() >= potion_slots():
		return false
	potions.append(id)
	return true
