
extends CharacterBody2D

# =========================================================
# MOVEMENT
# =========================================================

@export var speed: float = 180.0


# =========================================================
# HEALTH
# =========================================================

@export var max_health: int = 100
@export var respawn_time: float = 3.0


# =========================================================
# ATTACK 1: TARGETED AOE
# =========================================================

@export var attack1_damage: int = 10
@export var aoe_effect_scene: PackedScene
@export var attack1_radius: float = 90.0

# Scales the whole AoE effect (visual AND hitbox together).
# Effective hit radius = attack1_radius * attack1_size_multiplier.
@export var attack1_size_multiplier: float = 1.4

# Interrupts the enemy and makes it play its hurt animation (even mid-attack).
# Turn this off for damage only.
@export var attack1_stagger: bool = true

# Maximum distance for finding an enemy.
@export var attack1_target_range: float = 400.0

# Frame of the Healer's attack animation when the AoE spawns.
@export var attack1_cast_frame: int = 2

# Active frames in the AoE effect's own animation.
@export var attack1_active_start_frame: int = 2
@export var attack1_active_end_frame: int = 5

@export var attack2_damage: int = 15


# =========================================================
# ATTACK 2: HEAL
# =========================================================

@export var heal_amount: int = 30
@export var heal_effect_scene: PackedScene
@export var heal_cast_frame: int = 2


# =========================================================
# ANIMATIONS
# =========================================================

@export var attack1_animation: StringName = &"attack1"
@export var heal_cast_animation: StringName = &"attack2"
@export var hurt_animation: StringName = &"hurt"
@export var death_animation: StringName = &"death"
@export var idle_animation: StringName = &"idle"
@export var walk_animation: StringName = &"walk"


# =========================================================
# HIT FLASH
# =========================================================

@export var hit_flash_color: Color = Color(1.0, 0.25, 0.25, 1.0)
@export var hit_flash_time: float = 0.25


# =========================================================
# STATE
# =========================================================

var player_id: int = 0
var health: int = 100

var dead: bool = false
var hurt: bool = false
var attacking: bool = false
var current_attack: String = ""

var base_modulate: Color = Color.WHITE
var flash_tween: Tween

var attack_id: int = 0

# Remember the last direction of movement for targeting.
var last_direction: Vector2 = Vector2.RIGHT


# =========================================================
# INPUT ACTIONS
# =========================================================

var act_up: String
var act_down: String
var act_left: String
var act_right: String

var act_attack1: String
var act_attack2: String
var act_attack3: String


# =========================================================
# NODES
# =========================================================

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D


# =========================================================
# READY
# =========================================================

func _ready() -> void:
	add_to_group("players")
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING

	player_id = _detect_player_id()
	_setup_actions()
	_check_input_actions()

	health = max_health
	dead = false
	hurt = false
	attacking = false

	base_modulate = animated_sprite.modulate
	collision_shape.set_deferred("disabled", false)

	for anim_name in [
		attack1_animation,
		heal_cast_animation,
		hurt_animation,
		death_animation
	]:
		if _has_animation(anim_name):
			animated_sprite.sprite_frames.set_animation_loop(anim_name, false)

	if _has_animation(idle_animation):
		animated_sprite.play(idle_animation)

	print("HEALER READY | PLAYER ID: ", player_id, " | HP: ", health)
	print("ANIMATIONS: ", animated_sprite.sprite_frames.get_animation_names())

	if aoe_effect_scene == null:
		push_warning("Assign AoE Effect Scene in the Healer Inspector.")

	if heal_effect_scene == null:
		push_warning("Heal Effect Scene is not assigned.")


func _detect_player_id() -> int:
	var current_node: Node = self

	while current_node != null:
		var node_name: String = String(current_node.name)

		if node_name.begins_with("Player") and node_name.length() > 6:
			var id_text: String = node_name.substr(6)

			if id_text.is_valid_int():
				var detected_id: int = id_text.to_int()

				if detected_id >= 1 and detected_id <= 4:
					return detected_id

		current_node = current_node.get_parent()

	push_warning("Healer '%s' could not find a Player1-Player4 ancestor. Using Player1 controls." % name)
	return 1


func _setup_actions() -> void:
	var prefix: String = "p%d_" % player_id

	act_up = prefix + "up"
	act_down = prefix + "down"
	act_left = prefix + "left"
	act_right = prefix + "right"

	act_attack1 = prefix + "attack1"
	act_attack2 = prefix + "attack2"
	act_attack3 = prefix + "attack3"


func _check_input_actions() -> void:
	var actions: Array = [
		act_up, act_down, act_left, act_right,
		act_attack1, act_attack2, act_attack3
	]

	for action_name in actions:
		if not InputMap.has_action(action_name):
			push_warning("Healer Player%d is missing Input Map action '%s'." % [player_id, action_name])


# =========================================================
# ANIMATION HELPERS
# =========================================================

func _has_animation(anim_name: StringName) -> bool:
	return (
		animated_sprite.sprite_frames != null
		and animated_sprite.sprite_frames.has_animation(anim_name)
	)


func _restart_animation(anim_name: StringName) -> void:
	if not _has_animation(anim_name):
		push_warning("Missing Healer animation: " + str(anim_name))
		return

	animated_sprite.stop()
	animated_sprite.animation = anim_name
	animated_sprite.frame = 0
	animated_sprite.play()


func flash_red() -> void:
	if flash_tween and flash_tween.is_running():
		flash_tween.kill()

	animated_sprite.modulate = hit_flash_color

	flash_tween = create_tween()
	flash_tween.tween_property(
		animated_sprite,
		"modulate",
		base_modulate,
		hit_flash_time
	)


# =========================================================
# PHYSICS / INPUT
# =========================================================

func _physics_process(_delta: float) -> void:
	if dead or hurt:
		velocity = Vector2.ZERO
		return

	if attacking:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if Input.is_action_just_pressed(act_attack1):
		start_attack1()
		return

	if Input.is_action_just_pressed(act_attack2):
		start_heal()
		return

	var direction: Vector2 = Input.get_vector(
		act_left,
		act_right,
		act_up,
		act_down
	)

	velocity = direction * speed

	if direction != Vector2.ZERO:
		last_direction = direction.normalized()

	if direction.x != 0.0:
		animated_sprite.flip_h = direction.x < 0.0

	var wanted_animation: StringName = (
		walk_animation
		if direction != Vector2.ZERO
		else idle_animation
	)

	if _has_animation(wanted_animation):
		if (
			animated_sprite.animation != wanted_animation
			or not animated_sprite.is_playing()
		):
			animated_sprite.play(wanted_animation)

	move_and_slide()


# =========================================================
# ATTACK 1: FIND NEAREST ENEMY AND SPAWN AOE
# =========================================================

func start_attack1() -> void:
	if attacking or hurt or dead:
		return

	if not _has_animation(attack1_animation):
		push_warning("Healer is missing attack1 animation.")
		return

	attacking = true
	current_attack = "attack1"
	velocity = Vector2.ZERO

	attack_id += 1
	var this_attack_id: int = attack_id

	print("PLAYER ", player_id, " HEALER AOE ATTACK")

	_restart_animation(attack1_animation)

	if not await _wait_for_frame(
		attack1_animation,
		attack1_cast_frame,
		this_attack_id
	):
		return

	_spawn_aoe_on_nearest_enemy()

	if not await _wait_for_animation_end(
		attack1_animation,
		this_attack_id
	):
		return

	end_attack()


func _find_nearest_enemy() -> Node2D:
	var nearest_enemy: Node2D = null
	var nearest_distance: float = attack1_target_range

	# Search enemies registered in the enemies group.
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue

		if not enemy is Node2D:
			continue

		if enemy.get("dead") == true:
			continue

		var enemy_node: Node2D = enemy as Node2D
		var offset: Vector2 = enemy_node.global_position - global_position
		var distance: float = offset.length()

		# Ignore enemies outside the target range.
		if distance > attack1_target_range:
			continue

		# Only target enemies in the direction the Healer faces.
		if distance > 0.0:
			var direction_to_enemy: Vector2 = offset.normalized()

			if direction_to_enemy.dot(last_direction) <= 0.0:
				continue

		# Keep the closest eligible enemy.
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_enemy = enemy_node

	return nearest_enemy


func _spawn_aoe_on_nearest_enemy() -> void:
	if aoe_effect_scene == null:
		push_warning("Assign AoE Effect Scene in the Healer Inspector.")
		return

	var target: Node2D = _find_nearest_enemy()

	if target == null:
		print(
			"[HEALER AOE] No enemy found in front within ",
			attack1_target_range,
			" pixels."
		)
		return

	var effect: Node = aoe_effect_scene.instantiate()

	# Configure the effect before adding it to the scene.
	if effect.get("damage") != null:
		effect.set("damage", attack1_damage)

	if effect.get("radius") != null:
		effect.set("radius", attack1_radius)

	if effect.get("active_start_frame") != null:
		effect.set("active_start_frame", attack1_active_start_frame)

	if effect.get("active_end_frame") != null:
		effect.set("active_end_frame", attack1_active_end_frame)

	if effect.get("stagger") != null:
		effect.set("stagger", attack1_stagger)
	elif attack1_stagger:
		push_warning("The AoE effect script has no 'stagger' property, so the enemy will only take damage.")

	# Bigger effect: scales the sprite and the hitbox together.
	if effect is Node2D:
		(effect as Node2D).scale = Vector2.ONE * attack1_size_multiplier

	var effect_parent: Node = get_tree().current_scene
	if effect_parent == null:
		effect_parent = get_parent()

	effect_parent.add_child(effect)

	# Spawn the effect at the selected enemy, not at the Healer.
	if effect is Node2D:
		(effect as Node2D).global_position = target.global_position

	print(
		"[HEALER AOE] SPAWNED ON: ",
		target.name,
		" | DISTANCE: ",
		round(global_position.distance_to(target.global_position)),
		" | DAMAGE: ",
		attack1_damage,
		" | HIT RADIUS: ",
		attack1_radius * attack1_size_multiplier,
		" | STAGGER: ",
		attack1_stagger
	)


# =========================================================
# ATTACK 2: HEAL THE OTHER PLAYER
# =========================================================

func start_heal() -> void:
	if attacking or hurt or dead:
		return

	if not _has_animation(heal_cast_animation):
		push_warning(
			"Missing heal casting animation: "
			+ str(heal_cast_animation)
		)
		return

	attacking = true
	current_attack = "attack2"
	velocity = Vector2.ZERO

	attack_id += 1
	var this_attack_id: int = attack_id

	print("PLAYER ", player_id, " HEALER CASTING HEAL")

	_restart_animation(heal_cast_animation)

	if not await _wait_for_frame(
		heal_cast_animation,
		heal_cast_frame,
		this_attack_id
	):
		return

	heal_other_player()

	if not await _wait_for_animation_end(
		heal_cast_animation,
		this_attack_id
	):
		return

	end_attack()


func heal_other_player() -> void:
	var target: Node = _find_heal_target()

	if target == null:
		print("[HEALER] No living teammate to heal.")
		return

	print(
		"[HEALER] Heal target: ", target.name,
		" (", target.get_parent().name, ")",
		" | HP: ", target.get("health"), "/", target.get("max_health")
	)

	_spawn_heal_effect(target)


# With up to 4 players: heals the living teammate with the LOWEST health percentage
# (ties go to the closest one). Never targets the Healer itself.
func _find_heal_target() -> Node:
	var best: Node = null
	var best_ratio: float = INF
	var best_distance: float = INF

	for player in get_tree().get_nodes_in_group("players"):
		if player == self or not is_instance_valid(player):
			continue

		if not player is Node2D:
			continue

		if player.get("dead") == true:
			continue

		var player_health: Variant = player.get("health")
		var player_max: Variant = player.get("max_health")

		if player_health == null or player_max == null or int(player_max) <= 0:
			continue

		var ratio: float = float(int(player_health)) / float(int(player_max))
		var distance: float = global_position.distance_to((player as Node2D).global_position)

		var lower_health: bool = ratio < best_ratio - 0.001
		var same_health_but_closer: bool = absf(ratio - best_ratio) <= 0.001 and distance < best_distance

		if lower_health or same_health_but_closer:
			best = player
			best_ratio = ratio
			best_distance = distance

	return best


func _spawn_heal_effect(target: Node) -> void:
	if heal_effect_scene == null:
		var old_health: int = int(target.get("health"))
		var max_target_health: int = int(target.get("max_health"))
		var new_health: int = mini(old_health + heal_amount, max_target_health)

		target.set("health", new_health)

		print("[HEALER] Healed teammate by ", new_health - old_health)
		return

	var effect: Node = heal_effect_scene.instantiate()

	if effect.has_method("configure"):
		effect.call("configure", target, heal_amount)
	elif effect.get("heal_amount") != null:
		effect.set("heal_amount", heal_amount)

	# Parent to the teammate so the effect follows them.
	target.add_child(effect)

	if effect is Node2D:
		(effect as Node2D).position = Vector2.ZERO

	print("[HEALER] Healing effect spawned on ", target.name)


# =========================================================
# ATTACK HELPERS
# =========================================================

func _attack_is_valid(this_attack_id: int) -> bool:
	return (
		is_inside_tree()
		and not dead
		and not hurt
		and attacking
		and attack_id == this_attack_id
	)


func _wait_for_frame(
	anim_name: StringName,
	target_frame: int,
	this_attack_id: int
) -> bool:
	var frame_count: int = animated_sprite.sprite_frames.get_frame_count(anim_name)
	target_frame = clampi(target_frame, 0, frame_count - 1)

	while animated_sprite.frame < target_frame:
		await get_tree().process_frame

		if not _attack_is_valid(this_attack_id):
			return false

		if animated_sprite.animation != anim_name:
			return false

	return _attack_is_valid(this_attack_id)


func _wait_for_animation_end(
	anim_name: StringName,
	this_attack_id: int
) -> bool:
	if (
		animated_sprite.animation == anim_name
		and animated_sprite.is_playing()
	):
		await animated_sprite.animation_finished

	return _attack_is_valid(this_attack_id)


func end_attack() -> void:
	attacking = false
	current_attack = ""
	velocity = Vector2.ZERO

	if not dead and not hurt and is_inside_tree():
		if _has_animation(idle_animation):
			animated_sprite.play(idle_animation)


func get_attack_damage() -> int:
	match current_attack:
		"attack1":
			return attack1_damage
		"attack2":
			return attack2_damage

	return 0


# =========================================================
# DAMAGE / HURT
# =========================================================

func take_damage(damage: int) -> void:
	if dead or damage <= 0:
		return

	health = max(health - damage, 0)

	print(
		"PLAYER ", player_id,
		" HEALER TOOK DAMAGE: ", damage,
		" | HP: ", health, "/", max_health
	)

	flash_red()

	if health <= 0:
		die()
		return

	# Interrupt the current attack.
	attack_id += 1
	attacking = false
	current_attack = ""
	velocity = Vector2.ZERO
	hurt = true

	if not _has_animation(hurt_animation):
		hurt = false
		return

	_restart_animation(hurt_animation)

	print("HEALER HURT")

	await animated_sprite.animation_finished

	if dead or not is_inside_tree():
		return

	hurt = false

	if _has_animation(idle_animation):
		animated_sprite.play(idle_animation)


# =========================================================
# DEATH / RESPAWN
# =========================================================

func die() -> void:
	if dead:
		return

	attack_id += 1
	dead = true
	hurt = false
	attacking = false
	current_attack = ""
	velocity = Vector2.ZERO

	collision_shape.set_deferred("disabled", true)

	if _has_animation(death_animation):
		_restart_animation(death_animation)

	print("PLAYER ", player_id, " HEALER DIED")

	if _has_animation(death_animation):
		await animated_sprite.animation_finished

	if not is_inside_tree():
		return

	await get_tree().create_timer(respawn_time).timeout

	if not is_inside_tree():
		return

	respawn()


func respawn() -> void:
	health = max_health
	dead = false
	hurt = false
	attacking = false
	current_attack = ""
	velocity = Vector2.ZERO
	attack_id += 1

	if flash_tween and flash_tween.is_running():
		flash_tween.kill()

	animated_sprite.modulate = base_modulate
	collision_shape.set_deferred("disabled", false)

	if _has_animation(idle_animation):
		animated_sprite.play(idle_animation)

	print(
		"HEALER RESPAWNED | PLAYER ID: ",
		player_id,
		" | HP: ",
		health
	)
