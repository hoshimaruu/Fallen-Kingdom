extends RefCounted
class_name PlayerInputSetup

const ACTIONS: Array[String] = [
	"up", "down", "left", "right",
	"attack1", "attack2", "attack3"
]

# Keyboard layouts for the extra players, in the same order as ACTIONS.
# Players 1 and 2 are expected to be defined in Project Settings > Input Map.
const KEYS := {
	3: [KEY_T, KEY_G, KEY_F, KEY_H, KEY_1, KEY_2, KEY_3],
	4: [KEY_0, KEY_9, KEY_8, KEY_7, KEY_6, KEY_5, KEY_4],
}


static func setup_player(player_id: int) -> void:
	var prefix := "p%d_" % player_id

	# Make sure every action exists (safe to call many times).
	for action in ACTIONS:
		var action_name := prefix + action

		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)

	# Only players 3 and 4 get default keys from code.
	if not KEYS.has(player_id):
		return

	var keys: Array = KEYS[player_id]

	for i in ACTIONS.size():
		_bind_key(prefix + ACTIONS[i], keys[i])


static func setup_all() -> void:
	for player_id in [1, 2, 3, 4]:
		setup_player(player_id)


static func _bind_key(action_name: String, keycode: Key) -> void:
	# Avoid adding the same key repeatedly.
	for existing_event in InputMap.action_get_events(action_name):
		if existing_event is InputEventKey and existing_event.physical_keycode == keycode:
			return

	var event := InputEventKey.new()
	event.physical_keycode = keycode
	InputMap.action_add_event(action_name, event)
