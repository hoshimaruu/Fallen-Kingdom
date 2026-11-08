
extends Node2D


# =========================================================
# HALLWAY REFERENCES
# Assign these nodes in the Inspector.
# =========================================================

@export_group("Hallway")

@export var hidden_hallway: CanvasItem
@export var entry_point: Marker2D

@export var exit_trigger: Area2D
@export var return_point: Marker2D


# =========================================================
# ENTRANCE REFERENCES
# =========================================================

@export_group("Entrance")

@export var entrance_trigger: Area2D
@export var entrance_blocker: CollisionShape2D
@export var entrance_gate_visual: CanvasItem

# Set to 1 for one player, 2 if both players must enter.
@export_range(1, 2, 1) var players_required: int = 1


# =========================================================
# EXIT SETTINGS
# =========================================================

@export_group("Exit")

# If true, the gate opens again after all required players exit.
@export var reopen_entrance_after_exit: bool = false


# =========================================================
# PLAYER TRACKING
# Uses player_id instead of the character instance.
# This survives character switching.
# =========================================================

var _entered_players: Dictionary = {}
var _exited_players: Dictionary = {}


# =========================================================
# READY
# =========================================================

func _ready() -> void:

	var missing: Array[String] = []

	if hidden_hallway == null:
		missing.append("hidden_hallway")

	if entry_point == null:
		missing.append("entry_point")

	if entrance_trigger == null:
		missing.append("entrance_trigger")

	if entrance_blocker == null:
		missing.append("entrance_blocker")

	if exit_trigger == null:
		missing.append("exit_trigger")

	if return_point == null:
		missing.append("return_point")

	if not missing.is_empty():
		push_error("[HALLWAY] Missing references: %s" % missing)
		return

	# Hide hallway visuals.
	# This does NOT disable its physics collisions.
	hidden_hallway

	# Keep the entrance open initially.
	entrance_blocker.set_deferred("disabled", true)

	if entrance_gate_visual != null:
		entrance_gate_visual.hide()

	# Connect detection signals.
	entrance_trigger.body_entered.connect(
		_on_entrance_body_entered
	)

	exit_trigger.body_entered.connect(
		_on_exit_body_entered
	)

	print("[HALLWAY] System ready.")


# =========================================================
# PLAYER IDENTIFICATION
# =========================================================

func _get_player_id(body: Node2D) -> int:

	if not body is CharacterBody2D:
		return -1

	if not body.is_in_group("players"):
		return -1

	var player := body as CharacterBody2D

	var id_value: Variant = player.get("player_id")

	if id_value == null:
		return -1

	var id := int(id_value)

	if id < 1:
		return -1

	return id


# =========================================================
# PLAYER TELEPORTATION
# =========================================================

func _teleport_player(
	player: CharacterBody2D,
	target_position: Vector2
) -> void:

	if not is_instance_valid(player):
		return

	# Stop existing movement.
	player.velocity = Vector2.ZERO

	# Teleport the actual controlled character.
	player.global_position = target_position

	# Refresh attack direction if supported.
	if player.has_method("update_attack_area_direction"):
		player.call("update_attack_area_direction")


# =========================================================
# ENTRANCE DETECTION
# =========================================================

func _on_entrance_body_entered(body: Node2D) -> void:

	var player_id := _get_player_id(body)

	if player_id == -1:
		return

	# Prevent duplicate teleportation.
	if _entered_players.has(player_id):
		return

	var player := body as CharacterBody2D

	_entered_players[player_id] = true

	print("[HALLWAY] Player%d entered." % player_id)

	# Teleport into hidden hallway.
	# Deferred to avoid changing physics transforms
	# directly while processing collision signals.
	call_deferred(
		"_teleport_player",
		player,
		entry_point.global_position
	)

	# Close after the required players have entered.
	if _entered_players.size() >= maxi(players_required, 1):
		_close_entrance()


# =========================================================
# CLOSE ENTRANCE
# =========================================================

func _close_entrance() -> void:

	print("[HALLWAY] Closing entrance.")

	# Activate the physical blocker.
	entrance_blocker.set_deferred("disabled", false)

	# Stop detecting new entrance attempts.
	entrance_trigger.set_deferred("monitoring", false)

	# Show the gate, if assigned.
	if entrance_gate_visual != null:
		entrance_gate_visual.show()


# =========================================================
# EXIT DETECTION
# =========================================================

func _on_exit_body_entered(body: Node2D) -> void:

	var player_id := _get_player_id(body)

	if player_id == -1:
		return

	# Only players who entered this hallway can exit it.
	if not _entered_players.has(player_id):
		return

	# Prevent duplicate exit teleportation.
	if _exited_players.has(player_id):
		return

	var player := body as CharacterBody2D

	_exited_players[player_id] = true

	print("[HALLWAY] Player%d reached the exit." % player_id)

	# Return to Map1.
	call_deferred(
		"_teleport_player",
		player,
		return_point.global_position
	)

	# Optionally reopen after everyone exits.
	if reopen_entrance_after_exit:
		if _exited_players.size() >= maxi(players_required, 1):
			_open_entrance()


# =========================================================
# OPEN ENTRANCE
# =========================================================

func _open_entrance() -> void:

	print("[HALLWAY] Entrance reopened.")

	entrance_blocker.set_deferred("disabled", true)
	entrance_trigger.set_deferred("monitoring", true)

	if entrance_gate_visual != null:
		entrance_gate_visual.hide()

	# Reset tracking for another use.
	_entered_players.clear()
	_exited_players.clear()
