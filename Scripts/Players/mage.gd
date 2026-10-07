extends CharacterBody2D

# =========================================================
# MOVEMENT
# =========================================================

@export var speed: float = 180.0


# =========================================================
# HEALTH
# =========================================================

@export var max_health: int = 70
@export var respawn_time: float = 3.0


# =========================================================
# ATTACKS
# =========================================================

@export var attack1_damage: int = 20
@export var attack2_damage: int = 30

@export var attack1_cooldown: float = 0.0
@export var attack2_cooldown: float = 3.0


# =========================================================
# FIREBALL
# =========================================================

@export var fireball_scene: PackedScene
@export var fireball_release_frame: int = 4
@export var fireball_spawn_offset: float = 35.0


# =========================================================
# ICE
# =========================================================

@export var ice_scene: PackedScene

# Lower number = faster cast
@export var ice_release_frame: int = 1

@export var ice_spawn_offset: float = 40.0

@export var ice_target_range: float = 400.0

@export var ice_front_only: bool = true

@export var ice_target_offset: Vector2 = Vector2.ZERO


# =========================================================
# HIT FLASH
# =========================================================

@export var hit_flash_color: Color = Color(1.0, 0.25, 0.25, 1.0)
@export var hit_flash_time: float = 0.25


# =========================================================
# STATE
# =========================================================

var player_id: int = 0
var health: int = 0

var dead: bool = false
var hurt: bool = false
var attacking: bool = false

var current_attack: String = ""

var projectile_fired: bool = false

var attack_id: int = 0

var attack_cooldowns: Dictionary = {
	"attack1": 0.0,
	"attack2": 0.0
}

var base_modulate: Color = Color.WHITE
var flash_tween: Tween


# =========================================================
# INPUT
# =========================================================

var act_up: String
var act_down: String
var act_left: String
var act_right: String

var act_attack1: String
var act_attack2: String


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

	match get_parent().name:
		"Player1":
			player_id = 1

		"Player2":
			player_id = 2

		_:
			print("WARNING: Mage is not under Player1 or Player2")

	_setup_actions()

	health = max_health

	base_modulate = animated_sprite.modulate

	collision_shape.set_deferred("disabled", false)

	animated_sprite.play("idle")

	_log("READY | HP: %d | SPEED: %s" % [health, speed])

	_log(
		"FIREBALL: %d dmg | release frame %d" %
		[attack1_damage, fireball_release_frame]
	)

	_log(
		"ICE: %d dmg | release frame %d | range %s | freeze" %
		[attack2_damage, ice_release_frame, ice_target_range]
	)

	_log(
		"ANIMATIONS: %s" %
		[animated_sprite.sprite_frames.get_animation_names()]
	)

	if fireball_scene == null:
		_log("WARNING: Fireball Scene is NOT assigned")

	if ice_scene == null:
		_log("WARNING: Ice Scene is NOT assigned")


# =========================================================
# INPUT SETUP
# =========================================================

func _setup_actions() -> void:
	var prefix := "p1_" if player_id == 1 else "p2_"

	act_up = prefix + "up"
	act_down = prefix + "down"
	act_left = prefix + "left"
	act_right = prefix + "right"

	act_attack1 = prefix + "attack1"
	act_attack2 = prefix + "attack2"


# =========================================================
# HELPERS
# =========================================================

func _log(message: String) -> void:
	print("[P%d MAGE] %s" % [player_id, message])


func _restart_animation(anim_name: String) -> void:
	animated_sprite.stop()
	animated_sprite.animation = anim_name
	animated_sprite.frame = 0
	animated_sprite.play()


func _cancel_attack() -> void:
	attacking = false
	current_attack = ""
	projectile_fired = false
	attack_id += 1


func _facing() -> float:
	return -1.0 if animated_sprite.flip_h else 1.0


func _spawn_container() -> Node:
	var container: Node = get_parent().get_parent()

	if container == null:
		container = get_tree().current_scene

	return container


func flash_red() -> void:
	if flash_tween:
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
# COOLDOWNS
# =========================================================

func update_cooldowns(delta: float) -> void:
	for attack_name in attack_cooldowns:
		if attack_cooldowns[attack_name] > 0.0:
			attack_cooldowns[attack_name] = maxf(
				attack_cooldowns[attack_name] - delta,
				0.0
			)

			if attack_cooldowns[attack_name] == 0.0:
				_log("%s COOLDOWN READY" % attack_name.to_upper())


func try_attack(attack_name: String) -> bool:
	if attack_cooldowns[attack_name] > 0.0:
		_log(
			"%s BLOCKED | COOLDOWN: %.2fs" %
			[
				attack_name.to_upper(),
				attack_cooldowns[attack_name]
			]
		)

		return false

	start_attack(attack_name)
	return true


# =========================================================
# PHYSICS
# =========================================================

func _physics_process(delta: float) -> void:
	update_cooldowns(delta)

	if dead or hurt:
		velocity = Vector2.ZERO
		return

	if attacking:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if Input.is_action_just_pressed(act_attack1):
		if try_attack("attack1"):
			return

	if Input.is_action_just_pressed(act_attack2):
		if try_attack("attack2"):
			return

	var direction := Input.get_vector(
		act_left,
		act_right,
		act_up,
		act_down
	)

	velocity = direction * speed

	if direction.x != 0:
		animated_sprite.flip_h = direction.x < 0

	var wanted_anim := "walk" if direction != Vector2.ZERO else "idle"

	if animated_sprite.animation != wanted_anim:
		animated_sprite.play(wanted_anim)

	move_and_slide()


# =========================================================
# ATTACKS
# =========================================================

func start_attack(attack_name: String) -> void:
	if attacking or hurt or dead:
		return

	var is_fireball := attack_name == "attack1"

	attack_id += 1

	var my_id := attack_id

	attacking = true
	current_attack = attack_name
	projectile_fired = false

	velocity = Vector2.ZERO

	if is_fireball:
		attack_cooldowns["attack1"] = attack1_cooldown
	else:
		attack_cooldowns["attack2"] = attack2_cooldown

	_log(
		"%s | FACING: %s" %
		[
			"FIREBALL" if is_fireball else "ICE",
			"LEFT" if animated_sprite.flip_h else "RIGHT"
		]
	)

	_restart_animation(attack_name)

	var release_frame: int

	if is_fireball:
		release_frame = fireball_release_frame
	else:
		release_frame = ice_release_frame

	var release_ok := await wait_for_attack_frame(
		release_frame,
		my_id
	)

	if not release_ok:
		return

	if is_fireball:
		fire_fireball()
	else:
		fire_ice()

	await animated_sprite.animation_finished

	if dead or hurt or my_id != attack_id:
		return

	end_attack()


# =========================================================
# WAIT FOR ATTACK FRAME
# =========================================================

func wait_for_attack_frame(
	target_frame: int,
	id: int
) -> bool:

	var last_frame := (
		animated_sprite.sprite_frames
		.get_frame_count(animated_sprite.animation) - 1
	)

	target_frame = mini(target_frame, last_frame)

	while animated_sprite.frame < target_frame:
		await get_tree().process_frame

		if dead or hurt or id != attack_id:
			return false

	return not (dead or hurt or id != attack_id)


# =========================================================
# END ATTACK
# =========================================================

func end_attack() -> void:
	attacking = false
	current_attack = ""
	projectile_fired = false

	velocity = Vector2.ZERO

	if not dead and not hurt:
		animated_sprite.play("idle")


# =========================================================
# FIREBALL
# =========================================================

func fire_fireball() -> void:
	if projectile_fired:
		return

	projectile_fired = true

	if fireball_scene == null:
		_log("ERROR: FIREBALL SCENE IS NOT ASSIGNED")
		return

	var facing := _facing()

	var fireball = fireball_scene.instantiate()

	_spawn_container().add_child(fireball)

	fireball.global_position = global_position + Vector2(
		facing * fireball_spawn_offset,
		0
	)

	if fireball.has_method("setup"):
		fireball.setup(
			Vector2(facing, 0),
			attack1_damage
		)
	else:
		if "direction" in fireball:
			fireball.direction = Vector2(facing, 0)

		if "damage" in fireball:
			fireball.damage = attack1_damage

	_log(
		"FIRED FIREBALL | DAMAGE: %d | DIRECTION: %s" %
		[
			attack1_damage,
			"LEFT" if facing < 0 else "RIGHT"
		]
	)


# =========================================================
# FIND ICE TARGET
# =========================================================

func find_ice_target() -> Node2D:
	var facing := _facing()

	var nearest: Node2D = null
	var nearest_distance: float = ice_target_range

	for enemy in get_tree().get_nodes_in_group("enemies"):

		if not is_instance_valid(enemy):
			continue

		if not enemy is Node2D:
			continue

		if "dead" in enemy and enemy.dead:
			continue

		var enemy_node := enemy as Node2D

		var offset: Vector2 = (
			enemy_node.global_position -
			global_position
		)

		# Only enemies in front
		if ice_front_only:
			if offset.x * facing < 0.0:
				continue

		var distance: float = offset.length()

		if distance <= nearest_distance:
			nearest_distance = distance
			nearest = enemy_node

	return nearest


# =========================================================
# ICE
# =========================================================

func fire_ice() -> void:
	if projectile_fired:
		return

	projectile_fired = true

	if ice_scene == null:
		_log("ERROR: ICE SCENE IS NOT ASSIGNED")
		return

	var facing := _facing()

	var target := find_ice_target()

	var spawn_position: Vector2

	if target != null:
		spawn_position = target.global_position + ice_target_offset

		_log(
			"ICE LOCKED ON: %s | DISTANCE: %.1f" %
			[
				target.name,
				global_position.distance_to(target.global_position)
			]
		)

	else:
		spawn_position = global_position + Vector2(
			facing * ice_spawn_offset,
			0
		)

		_log("ICE: NO TARGET, CASTING IN FRONT")

	var ice = ice_scene.instantiate()

	_spawn_container().add_child(ice)

	ice.global_position = spawn_position

	# Give Ice the target directly.
	if ice.has_method("setup"):
		ice.setup(
			Vector2(facing, 0),
			attack2_damage
		)

	if ice.has_method("set_target"):
		ice.set_target(target)

	_log(
		"CAST ICE | DAMAGE: %d | POSITION: %s" %
		[
			attack2_damage,
			spawn_position
		]
	)


# =========================================================
# DAMAGE
# =========================================================

func take_damage(damage: int) -> void:
	if dead:
		return

	health = max(health - damage, 0)

	_log(
		"TOOK %d DAMAGE | HP: %d/%d" %
		[
			damage,
			health,
			max_health
		]
	)

	flash_red()

	if health <= 0:
		die()
		return

	hurt = true

	_cancel_attack()

	velocity = Vector2.ZERO

	_restart_animation("hurt")

	await animated_sprite.animation_finished

	if dead:
		return

	hurt = false

	animated_sprite.play("idle")


# =========================================================
# DEATH
# =========================================================

func die() -> void:
	if dead:
		return

	dead = true
	hurt = false

	_cancel_attack()

	velocity = Vector2.ZERO

	collision_shape.set_deferred("disabled", true)

	_restart_animation("death")

	_log("DIED")

	await animated_sprite.animation_finished

	await get_tree().create_timer(respawn_time).timeout

	if not is_inside_tree():
		return

	respawn()


# =========================================================
# RESPAWN
# =========================================================

func respawn() -> void:
	health = max_health

	dead = false
	hurt = false

	_cancel_attack()

	velocity = Vector2.ZERO

	for attack_name in attack_cooldowns:
		attack_cooldowns[attack_name] = 0.0

	if flash_tween:
		flash_tween.kill()

	animated_sprite.modulate = base_modulate

	collision_shape.set_deferred("disabled", false)

	animated_sprite.play("idle")

	_log("RESPAWNED | HP: %d" % health)
