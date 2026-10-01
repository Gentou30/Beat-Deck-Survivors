class_name MapGen

const FLOORS := 10  # floors 0..9, boss on floor 10
const LANES := 4

static func _type_for(f: int) -> String:
	if f == 0:
		return "battle"
	if f == 4:
		return "treasure"
	if f == 9:
		return "rest"
	var w := {"battle": 50, "event": 20, "rest": 10}
	if f >= 2:
		w["shop"] = 9
	if f >= 3:
		w["elite"] = 14
	var total := 0
	for k in w:
		total += w[k]
	var r := randi() % total
	for k in w:
		r -= w[k]
		if r < 0:
			return k
	return "battle"

static func generate() -> Array:
	var rows: Array = []
	for f in FLOORS:
		var lanes := range(LANES)
		lanes.shuffle()
		var n := 3 + randi() % 2
		var picked: Array = lanes.slice(0, n)
		picked.sort()
		var row: Array = []
		for c in picked:
			row.append({"col": float(c), "type": _type_for(f), "next": []})
		rows.append(row)
	rows.append([{"col": (LANES - 1) / 2.0, "type": "boss", "next": []}])
	for f in rows.size() - 1:
		var row: Array = rows[f]
		var nxt: Array = rows[f + 1]
		for node in row:
			for j in nxt.size():
				if absf(nxt[j]["col"] - node["col"]) <= 1.01:
					node["next"].append(j)
			if node["next"].is_empty():
				var best := 0
				for j in nxt.size():
					if absf(nxt[j]["col"] - node["col"]) < absf(nxt[best]["col"] - node["col"]):
						best = j
				node["next"].append(best)
		for j in nxt.size():
			var has_in := false
			for node in row:
				if node["next"].has(j):
					has_in = true
			if not has_in:
				var best := 0
				for i in row.size():
					if absf(row[i]["col"] - nxt[j]["col"]) < absf(row[best]["col"] - nxt[j]["col"]):
						best = i
				row[best]["next"].append(j)
	return rows
