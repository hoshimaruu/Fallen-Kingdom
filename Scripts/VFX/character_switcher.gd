class_name CharacterSwitcher
extends Node

# Replaces a player's character with a different class when they press
# "pN_switch". The old character is removed and the new one appears in the
# same spot. Two players can never be the same class.
#
# Add ONE Node with this script to your main scene (not under a Player node).
# Fill in the four scenes below in the Inspector.
#
# Each player's character must be a child of a node named "Player1" or
# "Player2" (that is how the character knows which controls to use).

signal character_switched(human_id: int, old_character, new_character)

@export_group("Character scenes")
@export var knight_scene: PackedScene
@export var archer_scene: PackedScene
@export var mage_scene: PackedScene
@export var healer_scene: PackedScene

@export_group("Rules")
@export var max_players: int = 2
@export var switch_cooldown: float = 0.4

# Keep the same health percentage on the new character (otherwise it spawns
# at full health, which makes switching a free heal).
@export var keep_health_percent: bool = true

var _scenes: Array[PackedScene] = []
var _characters: Dictionary = {}   # player id -> character
var _cooldowns: Dictionary = {}    # player id -> seconds left


func _ready() -> void:
	for scene in [knight_scene, archer_scene, mage_scene, healer_scene]:
		if scene != null:
			_scenes.append(scene)

	print("[SWITCHER] ready, %d scenes assigned" % _scenes.size())

	if _scenes.size() < 2:
		push_warning("[SWITCHER] Fill in the character scenes in the Inspector.")

	for human_id in range(1, max_players + 1):
		PlayerSetupInput.setup_player(human_id)

	# Wait a frame so every character has finished its own _ready().
	await get_tree().process_frame

	_find_characters()


func _find_characters() -> void:
	_characters.clear()

	for node in get_tree().get_nodes_in_group("players"):
		var human_id: int = int(node.get("player_id"))

		if human_id < 1 or human_id > max_players:
			continue

		if _characters.has(human_id):
			push_warning("[SWITCHER] Two characters use Player%d controls." % human_id)
			continue

		_characters[human_id] = node

	if _characters.is_empty():
		push_warning("[SWITCHER] No characters found. They must be in group 'players' and under a node named Player1 / Player2.")

	if _characters.size() == 2 and _scene_index(_characters[1]) == _scene_index(_characters[2]):
		push_warning("[SWITCHER] Player1 and Player2 start with the same class.")

	print("[SWITCHER] players: %s" % [_characters.keys()])


func _physics_process(delta: float) -> void:
	for human_id in _characters.keys():
		_cooldowns[human_id] = maxf(float(_cooldowns.get(human_id, 0.0)) - delta, 0.0)

		var action := "p%d_switch" % human_id

		if InputMap.has_action(action) and Input.is_action_just_pressed(action):
			print("[SWITCHER] %s pressed" % action)

			if not switch_character(human_id):
				print("[SWITCHER] switch failed for Player%d (see messages above)" % human_id)


# Replaces the player's character with the next free class.
func switch_character(human_id: int) -> bool:
	if float(_cooldowns.get(human_id, 0.0)) > 0.0:
		print("[SWITCHER] Player%d is on cooldown" % human_id)
		return false

	var old = _characters.get(human_id)

	if not is_instance_valid(old):
		print("[SWITCHER] Player%d has no character" % human_id)
		return false

	var next_scene: PackedScene = _pick_next_scene(old, human_id)

	if next_scene == null:
		print("[SWITCHER] no free scene (assigned: %d, current scene file: '%s')" % [_scenes.size(), old.scene_file_path])
		return false

	var parent: Node = old.get_parent()
	var old_name: StringName = old.name
	var old_position: Vector2 = old.global_position
	var health_ratio: float = 1.0

	if keep_health_percent and old.get("max_health") != null and int(old.get("max_health")) > 0:
		health_ratio = float(old.get("health")) / float(old.get("max_health"))

	var new_character = next_scene.instantiate()

	# Remove the old one first so the new one can take its node name.
	_remove_character(old)
	new_character.name = old_name

	# Same parent, so it keeps the PlayerN name and therefore the same controls.
	parent.add_child(new_character)
	new_character.global_position = old_position

	if new_character.has_method("set_controller"):
		new_character.set_controller(human_id)

	if keep_health_percent and new_character.get("max_health") != null:
		var max_hp: int = int(new_character.get("max_health"))
		new_character.set("health", maxi(1, roundi(max_hp * health_ratio)))

		if new_character.has_method("_update_healthbar"):
			new_character._update_healthbar()

	_characters[human_id] = new_character
	_cooldowns[human_id] = switch_cooldown

	print("[SWITCHER] Player%d: %s -> %s" % [human_id, old_name, next_scene.resource_path.get_file()])
	character_switched.emit(human_id, old, new_character)

	return true


func _remove_character(old) -> void:
	# Summons belong to the character and go away with it.
	if old.has_method("_clear_summons"):
		old._clear_summons()

	if old.has_method("_clear_paladins"):
		old._clear_paladins()

	# Leave the players group right away so nothing targets or counts it.
	old.remove_from_group("players")
	old.get_parent().remove_child(old)
	old.queue_free()


# Next scene in the list that the other player is not using.
func _pick_next_scene(current, human_id: int) -> PackedScene:
	var start: int = _scene_index(current)
	var taken: Array[int] = []

	for other_id in _characters.keys():
		if other_id != human_id and is_instance_valid(_characters[other_id]):
			taken.append(_scene_index(_characters[other_id]))

	for offset in range(1, _scenes.size() + 1):
		var index: int = (start + offset) % _scenes.size()

		if index == start or taken.has(index):
			continue

		return _scenes[index]

	return null


# Which entry in _scenes this character was made from (-1 if unknown).
func _scene_index(character) -> int:
	for i in _scenes.size():
		if _scenes[i].resource_path == character.scene_file_path:
			return i

	return -1


func get_character(human_id: int):
	return _characters.get(human_id)
