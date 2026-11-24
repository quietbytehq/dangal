class_name Characters
extends RefCounted
## The roster. Each fighter's stats, attacks, specials, ultra and asset folders.
##
## Hitboxes are in units of body height (H), measured from the feet, facing right
## (for air attacks: from the feet at the current height of the jump).
## "active" is the part of the move (0..1) where it can hit. "time" is the whole move in seconds.
## Optional: "low" (must be blocked crouching), "air", "move" (px/s forward while active),
## "hits" (number of hits while active), "quake" (screen shake), "vfx" (effect on impact).

const ROSTER := ["rustam", "babasher"]

const DATA := {
	"rustam": {
		"name": "RUSTAM",
		"from": "Karachi",
		"country": "PAKISTAN",
		"style": "Street brawler",
		"age": 29,
		"height": "1.83 m",
		"stats": {"POWER": 3, "SPEED": 4, "RANGE": 4, "DEFENSE": 3},
		"fact": "Learned to fight on Karachi rooftops. His fists crackle with storm energy.",
		"sprites": "res://assets/rustam",
		"json": "rustam_sprites.json",
		"voice": "rustam",
		"health": 1000,
		"walk_speed": 240.0,
		"push_width": 0.27,
		"special": "fireball",
		"special_name": "STORM FIST",
		"special_time": 0.95,
		"special_release": 0.5,
		"kick_special_name": "HURRICANE KICK",
		"ultra": "beam",
		"ultra_name": "LIGHTNING STORM",
		"ultra_time": 3.8,
		"ultra_release": 0.86,
		"ultra_damage": 330,
		"callout_text": "You! Step up and show me what you've got!",
		"tease_text": "Too slow! Better luck next time!",
		"groan_text": "Ugh... next time, I'll get you!",
		"attacks": {
			"jab": {"damage": 60, "active": Vector2(0.25, 0.55), "time": 0.45,
				"box": Rect2(0.10, -0.82, 0.55, 0.18), "hitstun": 0.35, "push": 140.0, "sfx": "punch"},
			"roundhouse": {"damage": 110, "active": Vector2(0.35, 0.65), "time": 0.80,
				"box": Rect2(0.10, -0.98, 0.62, 0.32), "hitstun": 0.45, "push": 240.0, "sfx": "kick"},
			"crouch_punch": {"damage": 45, "active": Vector2(0.48, 0.78), "time": 0.42,
				"box": Rect2(0.10, -0.42, 0.60, 0.18), "hitstun": 0.30, "push": 110.0, "sfx": "punch"},
			"crouch_kick": {"damage": 80, "active": Vector2(0.40, 0.70), "time": 0.70, "low": true,
				"box": Rect2(0.10, -0.30, 0.72, 0.26), "hitstun": 0.40, "push": 180.0, "sfx": "kick"},
			"jump_punch": {"damage": 70, "active": Vector2(0.38, 0.66), "time": 1.0, "air": true,
				"box": Rect2(0.05, -0.80, 0.55, 0.32), "hitstun": 0.40, "push": 160.0, "sfx": "punch"},
			"jump_kick": {"damage": 85, "active": Vector2(0.32, 0.66), "time": 1.0, "air": true,
				"box": Rect2(0.05, -0.60, 0.68, 0.30), "hitstun": 0.45, "push": 200.0, "sfx": "kick"},
			"kick_special": {"damage": 55, "active": Vector2(0.34, 0.90), "time": 1.0, "hits": 2,
				"move": 430.0, "box": Rect2(-0.25, -0.95, 0.95, 0.45), "hitstun": 0.40,
				"push": 170.0, "sfx": "kick", "vfx": "fire_burst"},
		},
	},
	"babasher": {
		"name": "BABA SHER",
		"from": "Hunza",
		"country": "PAKISTAN",
		"style": "Mountain wrestler",
		"age": 67,
		"height": "1.91 m",
		"stats": {"POWER": 5, "SPEED": 2, "RANGE": 3, "DEFENSE": 5},
		"fact": "Undefeated village wrestling champion for 40 years. Can shake a mountain with one stomp.",
		"sprites": "res://assets/babasher",
		"json": "babasher_sprites.json",
		"voice": "babasher",
		"health": 1150,
		"walk_speed": 185.0,
		"push_width": 0.33,
		"special": "shockwave",
		"special_name": "EARTHQUAKE",
		"special_time": 1.2,
		"special_release": 0.42,
		"kick_special_name": "AVALANCHE",
		"ultra": "quake",
		"ultra_name": "MOUNTAIN BREAKER",
		"ultra_time": 3.8,
		"ultra_release": 0.8,
		"ultra_damage": 360,
		"callout_text": "You there! The mountain has been waiting for you!",
		"tease_text": "Ha! Come back when you've grown a beard!",
		"groan_text": "Oof... I'm getting too old for this!",
		"attacks": {
			# heavy open-palm strike
			"jab": {"damage": 75, "active": Vector2(0.30, 0.58), "time": 0.60,
				"box": Rect2(0.12, -0.78, 0.58, 0.22), "hitstun": 0.40, "push": 200.0, "sfx": "punch"},
			# front push kick: big push-back
			"roundhouse": {"damage": 125, "active": Vector2(0.35, 0.62), "time": 0.95,
				"box": Rect2(0.12, -0.62, 0.66, 0.30), "hitstun": 0.50, "push": 360.0, "sfx": "kick"},
			"crouch_punch": {"damage": 55, "active": Vector2(0.54, 0.82), "time": 0.52,
				"box": Rect2(0.12, -0.40, 0.62, 0.20), "hitstun": 0.32, "push": 140.0, "sfx": "punch"},
			# low leg sweep
			"crouch_kick": {"damage": 90, "active": Vector2(0.40, 0.70), "time": 0.80, "low": true,
				"box": Rect2(0.10, -0.28, 0.75, 0.26), "hitstun": 0.45, "push": 200.0, "sfx": "kick"},
			"jump_punch": {"damage": 85, "active": Vector2(0.44, 0.72), "time": 1.05, "air": true,
				"box": Rect2(0.05, -0.75, 0.55, 0.35), "hitstun": 0.45, "push": 180.0, "sfx": "punch"},
			"jump_kick": {"damage": 95, "active": Vector2(0.45, 0.74), "time": 1.05, "air": true,
				"box": Rect2(0.05, -0.62, 0.52, 0.34), "hitstun": 0.45, "push": 220.0, "sfx": "kick"},
			# axe kick: heel smashes down, small forward hop, quake + rocks on impact
			"kick_special": {"damage": 140, "active": Vector2(0.46, 0.72), "time": 1.05,
				"move": 170.0, "box": Rect2(0.10, -0.60, 0.72, 0.60), "hitstun": 0.55,
				"push": 260.0, "sfx": "kick", "quake": 12.0, "vfx": "rock_burst"},
		},
	},
}


static func get_def(id: String) -> Dictionary:
	return DATA[id]
