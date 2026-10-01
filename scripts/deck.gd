class_name Deck
extends RefCounted

var draw_pile: Array[String] = []
var discard_pile: Array[String] = []
var hand: Array[String] = []

func setup(cards: Array, hand_size: int) -> void:
	draw_pile.clear()
	discard_pile.clear()
	hand.clear()
	for c in cards:
		draw_pile.append(c)
	draw_pile.shuffle()
	for i in hand_size:
		hand.append(draw_one())

func draw_one() -> String:
	if draw_pile.is_empty():
		draw_pile.append_array(discard_pile)
		discard_pile.clear()
		draw_pile.shuffle()
	if draw_pile.is_empty():
		return ""
	return draw_pile.pop_back()

func play(slot: int, exhaust := false) -> String:
	var id := hand[slot]
	if id != "" and not exhaust:
		discard_pile.append(id)
	hand[slot] = draw_one()
	return id

func add_card(id: String) -> void:
	discard_pile.append(id)

func total_cards() -> int:
	var n := draw_pile.size() + discard_pile.size()
	for h in hand:
		if h != "":
			n += 1
	return n
