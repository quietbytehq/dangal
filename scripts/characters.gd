class_name Characters
extends RefCounted
## The roster. Each fighter's stats, attacks, special move and asset folders.
##
## Hitboxes are in units of body height (H), measured from the feet, facing right.
## "active" is the part of the move (0..1) where it can hit. "time" is the whole move in seconds.

const ROSTER := ["rustam", "babasher"]

const DATA := {
	"rustam": {
		"name": "RUSTAM",
		"from": "Karachi",
		"sprites": "res://assets/rustam",
		"json": "rustam_sprites.json",
		"voice": "rustam",
		"health": 1000,
		"walk_speed": 240.0,
		"special": "fireball",
		"special_time": 0.95,
		"special_release": 0.5,
		"attacks": {
			"jab": {"damage": 60, "active": Vector2(0.25, 0.55), "time": 0.45,
				"box": Rect2(0.10, -0.82, 0.55, 0.18), "hitstun": 0.35, "push": 140.0, "sfx": "punch"},
			"roundhouse": {"damage": 110, "active": Vector2(0.35, 0.65), "time": 0.80,
				"box": Rect2(0.10, -0.98, 0.62, 0.32), "hitstun": 0.45, "push": 240.0, "sfx": "kick"},
			"crouch_kick": {"damage": 80, "active": Vector2(0.40, 0.70), "time": 0.70,
				"box": Rect2(0.10, -0.30, 0.72, 0.26), "hitstun": 0.40, "push": 180.0, "sfx": "kick"},
		},
	},
	"babasher": {
		"name": "BABA SHER",
		"from": "Hunza",
		"sprites": "res://assets/babasher",
		"json": "babasher_sprites.json",
		"voice": "babasher",
		"health": 1150,
		"walk_speed": 185.0,
		"special": "shockwave",
		"special_time": 1.2,
		"special_release": 0.42,
		"attacks": {
			# heavy open-palm strike
			"jab": {"damage": 75, "active": Vector2(0.30, 0.58), "time": 0.60,
				"box": Rect2(0.12, -0.78, 0.58, 0.22), "hitstun": 0.40, "push": 200.0, "sfx": "punch"},
			# front push kick: big push-back
			"roundhouse": {"damage": 125, "active": Vector2(0.35, 0.62), "time": 0.95,
				"box": Rect2(0.12, -0.62, 0.66, 0.30), "hitstun": 0.50, "push": 360.0, "sfx": "kick"},
			# low leg sweep
			"crouch_kick": {"damage": 90, "active": Vector2(0.40, 0.70), "time": 0.80,
				"box": Rect2(0.10, -0.28, 0.75, 0.26), "hitstun": 0.45, "push": 200.0, "sfx": "kick"},
		},
	},
}


static func get_def(id: String) -> Dictionary:
	return DATA[id]
