extends Node
## Registers every input action at startup, for keyboard and joypad.
## Player 1 uses joypad 0 and player 2 uses joypad 1. Both players can also
## share one keyboard.

const KEYS := {
	1: {"left": KEY_A, "right": KEY_D, "up": KEY_W, "down": KEY_S,
		"punch": KEY_J, "kick": KEY_K, "special": KEY_L, "ultra": KEY_I},
	2: {"left": KEY_LEFT, "right": KEY_RIGHT, "up": KEY_UP, "down": KEY_DOWN,
		"punch": KEY_KP_1, "kick": KEY_KP_2, "special": KEY_KP_3, "ultra": KEY_KP_4},
}

# Xbox layout: X = punch, A = kick, B = special, Y = ultra.
# (PlayStation: Square, Cross, Circle, Triangle.)
const PAD_BUTTONS := {
	"left": JOY_BUTTON_DPAD_LEFT, "right": JOY_BUTTON_DPAD_RIGHT,
	"up": JOY_BUTTON_DPAD_UP, "down": JOY_BUTTON_DPAD_DOWN,
	"punch": JOY_BUTTON_X, "kick": JOY_BUTTON_A, "special": JOY_BUTTON_B, "ultra": JOY_BUTTON_Y,
}

const PAD_AXES := {
	"left": [JOY_AXIS_LEFT_X, -1.0], "right": [JOY_AXIS_LEFT_X, 1.0],
	"up": [JOY_AXIS_LEFT_Y, -1.0], "down": [JOY_AXIS_LEFT_Y, 1.0],
}


func _ready() -> void:
	for p in [1, 2]:
		for a in KEYS[p]:
			var action := "p%d_%s" % [p, a]
			if not InputMap.has_action(action):
				InputMap.add_action(action, 0.5)

			var key := InputEventKey.new()
			key.physical_keycode = KEYS[p][a]
			InputMap.action_add_event(action, key)

			var btn := InputEventJoypadButton.new()
			btn.device = p - 1
			btn.button_index = PAD_BUTTONS[a]
			InputMap.action_add_event(action, btn)

			if PAD_AXES.has(a):
				var axis := InputEventJoypadMotion.new()
				axis.device = p - 1
				axis.axis = PAD_AXES[a][0]
				axis.axis_value = PAD_AXES[a][1]
				InputMap.action_add_event(action, axis)

	# Start / Enter: next round, or toggle CPU for player 2 on the title screen.
	if not InputMap.has_action("start"):
		InputMap.add_action("start")
	var enter := InputEventKey.new()
	enter.physical_keycode = KEY_ENTER
	InputMap.action_add_event("start", enter)
	var start_btn := InputEventJoypadButton.new()
	start_btn.device = -1
	start_btn.button_index = JOY_BUTTON_START
	InputMap.action_add_event("start", start_btn)
