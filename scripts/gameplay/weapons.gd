class_name PlayerWeapon
extends RefCounted
## Player weapons: pistol (default, infinite magazines) and limited special weapons.

const WEAPONS := {
	"pistol": {"name": "אקדח", "mag": 6, "reload": 0.6, "rate": 0.12, "pellets": 1, "auto": false, "pierce": false, "sound": "pistol", "shake": 0.08},
	"mpistol": {"name": "תת־מקלע", "mag": 30, "reload": 0.0, "rate": 0.085, "pellets": 1, "auto": true, "pierce": false, "sound": "mpistol", "shake": 0.05},
	"shotgun": {"name": "רובה ציד", "mag": 6, "reload": 0.0, "rate": 0.45, "pellets": 5, "spread": 0.055, "auto": false, "pierce": false, "sound": "shotgun", "shake": 0.3},
	"magnum": {"name": "מגנום", "mag": 6, "reload": 0.0, "rate": 0.32, "pellets": 1, "auto": false, "pierce": true, "sound": "magnum", "shake": 0.25},
}

var id := "pistol"
var def: Dictionary = WEAPONS["pistol"]
var ammo := 6
var reloading := 0.0
var cooldown := 0.0

func _init() -> void:
	equip("pistol")

func equip(w: String) -> void:
	id = w; def = WEAPONS[w]; ammo = int(def["mag"]); reloading = 0.0; cooldown = 0.0

func special() -> bool:
	return id != "pistol"

func can_fire() -> bool:
	return cooldown <= 0.0 and reloading <= 0.0 and ammo > 0

func fire() -> String:
	ammo -= 1
	cooldown = float(def["rate"])
	return "depleted" if ammo <= 0 and special() else "ok"

func start_reload() -> bool:
	if special() or reloading > 0.0 or ammo == int(def["mag"]):
		return false
	reloading = float(def["reload"])
	return true

func update(dt: float) -> String:
	cooldown -= dt
	if reloading > 0.0:
		reloading -= dt
		if reloading <= 0.0:
			reloading = 0.0; ammo = int(def["mag"])
			return "reloaded"
	return ""
