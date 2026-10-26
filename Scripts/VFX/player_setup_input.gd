extends RefCounted
class_name PlayerSetupInput

const MAX_PLAYERS := 2

const ACTIONS: Array[String] = [
	"up", "down", "left", "right",
	"attack1", "attack2", "attack3", "switch"
]


# Creates the pN_ actions if they do not exist yet (safe to call many times).
# Bind the keys for Player 1 and Player 2 in Project Settings > Input Map,
# including p1_switch and p2_switch.
static func setup_player(player_id: int) -> void:
	if player_id < 1 or player_id > MAX_PLAYERS:
		return

	var prefix := "p%d_" % player_id

	for action in ACTIONS:
		var action_name := prefix + action

		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)


static func setup_all() -> void:
	for player_id in range(1, MAX_PLAYERS + 1):
		setup_player(player_id)
