class_name Scoring
extends RefCounted
## Score, combo multiplier and per-stage statistics.

const POINTS := {"torso": 100, "head": 200, "weapon": 300, "legs": 100, "barrel": 500, "boss": 3000, "grenade": 100, "rescue": 500}

var total := 0
var combo := 0
var stage := {}

func _init() -> void:
	reset_stage()

func reset_stage() -> void:
	stage = {"score": 0, "shots": 0, "hits": 0, "heads": 0, "disarms": 0, "civilians": 0, "damage": 0, "time": 0.0, "kills": 0}
	combo = 0

func multiplier() -> int:
	return 4 if combo >= 12 else (3 if combo >= 8 else (2 if combo >= 4 else 1))

func shot() -> void: stage["shots"] += 1
func miss() -> void: combo = 0

func hit(part: String) -> int:
	stage["hits"] += 1
	combo += 1
	if part == "head": stage["heads"] += 1
	if part == "weapon": stage["disarms"] += 1
	return add(int(POINTS.get(part, 100)), true)

func add(points: int, with_mult := false) -> int:
	var p := points * (multiplier() if with_mult else 1)
	stage["score"] += p
	total += p
	return p

func reset_score() -> void:
	total = 0; stage["score"] = 0; combo = 0

func accuracy() -> int:
	return roundi(100.0 * stage["hits"] / stage["shots"]) if stage["shots"] > 0 else 0

func rank(target := 30000, continues := 0) -> Dictionary:
	var acc := accuracy()
	var score_f := minf(1.0, float(stage["score"]) / target)
	var v: float = acc * 0.45 + score_f * 45.0 + minf(10.0, stage["heads"] + stage["disarms"] * 2) - stage["civilians"] * 8 - stage["damage"] * 3 - continues * 15
	v = clampf(v, 0.0, 100.0)
	var letter := "S" if v >= 85 else ("A" if v >= 70 else ("B" if v >= 55 else ("C" if v >= 38 else "D")))
	return {"letter": letter, "value": v}

static func zone_bonus(seconds: float, par := 20.0) -> int:
	var over := maxf(0.0, seconds - par)
	return maxi(200, roundi((2000.0 - over * 60.0) / 10.0) * 10)
