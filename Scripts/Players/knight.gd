extends CharacterBody2D

# --- Movement ---
@export var speed: float = 180.0

# --- Health ---
@export var max_health: int = 100
@export var respawn_time: float = 3.0

# --- Attack damage ---
@export var attack1_damage: int = 10
@export var attack2_damage: int = 15

# --- Knight slash (attack2 projectile) ---
@export var slash_scene: PackedScene
@export var slash_release_frame: int = 8

# --- Block ---
@export var block_duration: float = 1.5
@export var block_damage_reduction: float = 0.8  # 0.8 = take 20%, 1.0 = take none

# --- Attack area ---
@export var attack_area_distance: float = 35.0

# --- Hit flash ---
@export var hit_flash_color: Color = Color(1.0, 0.25, 0.25, 1.0)
@export var hit_flash_time: float = 0.25

# --- State ---
var player_id: int = 0
var health: int
var dead: bool = false
var hurt: bool = false
var attacking: bool = false
var blocking: bool = false
var current_attack: String = ""
var hit_targets: Array = []

var base_modulate: Color = Color.WHITE
var flash_tween: Tween

# --- Input action names (filled in by _setup_actions) ---
var act_up: String
var act_down: String
var act_left: String
var act_right: String
var act_attack1: String
var act_attack2: String
var act_attack3: String

# --- Nodes ---
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var attack_area: Area2D = $AttackArea
@onready var barrier: AnimatedSprite2D = $Barrier
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
			print("WARNING: Knight is not under Player1 or Player2")

	_setup_actions()

	health = max_health
	dead = false
	hurt = false
	attacking = false
	blocking = false

	base_modulate = animated_sprite.modulate

	attack_area.monitoring = false
	barrier.visible = false
	collision_shape.set_deferred("disabled", false)

	update_attack_area_direction()

	print("KNIGHT READY | PLAYER ID: ", player_id, " | HP: ", health)
	print("ANIMATIONS: ", animated_sprite.sprite_frames.get_animation_names())


func _setup_actions() -> void:
	# Anything that isn't player 1 uses the p2_ actions
	var prefix := "p1_" if player_id == 1 else "p2_"

	act_up = prefix + "up"
	act_down = prefix + "down"
	act_left = prefix + "left"
	act_right = prefix + "right"
	act_attack1 = prefix + "attack1"
	act_attack2 = prefix + "attack2"
	act_attack3 = prefix + "attack3"


# =========================================================
# HELPERS
# =========================================================

func _restart_animation(anim_name: String) -> void:
	animated_sprite.stop()
	animated_sprite.animation = anim_name
	animated_sprite.frame = 0
	animated_sprite.play()


func _clear_combat_state() -> void:
	attacking = false
	blocking = false
	current_attack = ""
	velocity = Vector2.ZERO
	attack_area.monitoring = false
	barrier.visible = false
	barrier.stop()


func update_attack_area_direction() -> void:
	attack_area.position.x = -abs(attack_area_distance) if animated_sprite.flip_h else abs(attack_area_distance)


func flash_red() -> void:
	if flash_tween:
		flash_tween.kill()

	animated_sprite.modulate = hit_flash_color

	flash_tween = create_tween()
	flash_tween.tween_property(animated_sprite, "modulate", base_modulate, hit_flash_time)


# =========================================================
# PHYSICS
# =========================================================

func _physics_process(_delta: float) -> void:
	if dead or hurt:
		velocity = Vector2.ZERO
		return

	if blocking or attacking:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var direction := Input.get_vector(act_left, act_right, act_up, act_down)

	velocity = direction * speed
	move_and_slide()

	if direction.x != 0:
		animated_sprite.flip_h = direction.x < 0
		update_attack_area_direction()

	var wanted_anim := "walk" if direction != Vector2.ZERO else "idle"
	if animated_sprite.animation != wanted_anim:
		animated_sprite.play(wanted_anim)

	if Input.is_action_just_pressed(act_attack1):
		start_attack("attack1")
	elif Input.is_action_just_pressed(act_attack2):
		start_attack("attack2")
	elif Input.is_action_just_pressed(act_attack3):
		start_block()


# =========================================================
# ATTACKS
# =========================================================

func start_attack(attack_name: String) -> void:
	if attacking or blocking or hurt or dead:
		return

	hit_targets.clear()
	attacking = true
	current_attack = attack_name
	velocity = Vector2.ZERO

	update_attack_area_direction()
	attack_area.monitoring = false

	_restart_animation(attack_name)

	if attack_name == "attack1":
		attack_area.monitoring = true

	await get_tree().physics_frame

	if dead or hurt:
		return

	if attack_name == "attack1":
		do_melee_damage()
	elif attack_name == "attack2":
		await wait_for_slash_frame()
		if dead or hurt:
			return
		fire_slash()

	await animated_sprite.animation_finished

	if dead or hurt:
		return

	attacking = false
	current_attack = ""
	attack_area.monitoring = false
	animated_sprite.play("idle")


func do_melee_damage() -> void:
	for body in attack_area.get_overlapping_bodies():
		if body == self:
			continue
		if not body.is_in_group("enemies"):
			continue
		if body in hit_targets:
			continue
		if not body.has_method("take_damage"):
			continue

		hit_targets.append(body)
		body.take_damage(attack1_damage)


func wait_for_slash_frame() -> void:
	while animated_sprite.frame < slash_release_frame:
		await animated_sprite.frame_changed
		if dead or hurt:
			return


func fire_slash() -> void:
	if slash_scene == null:
		print("ERROR: SLASH SCENE IS NOT ASSIGNED")
		return

	var slash = slash_scene.instantiate()
	get_parent().get_parent().add_child(slash)

	var facing_direction := -1.0 if animated_sprite.flip_h else 1.0

	slash.global_position = global_position + Vector2(facing_direction * 35.0, 0)
	slash.direction = Vector2(facing_direction, 0)

	if facing_direction < 0:
		slash.scale.x = -1


# =========================================================
# BLOCK
# =========================================================

func start_block() -> void:
	if attacking or blocking or hurt or dead:
		return

	blocking = true
	velocity = Vector2.ZERO
	attack_area.monitoring = false

	_restart_animation("attack3")

	barrier.visible = true
	barrier.play()

	await animated_sprite.animation_finished

	if dead or hurt:
		return

	# Hold the last frame of the block animation
	animated_sprite.stop()
	animated_sprite.frame = animated_sprite.sprite_frames.get_frame_count("attack3") - 1

	await get_tree().create_timer(block_duration).timeout

	if dead or hurt:
		return

	blocking = false
	barrier.visible = false
	barrier.stop()
	animated_sprite.play("idle")


# =========================================================
# DAMAGE / DEATH / RESPAWN
# =========================================================

func take_damage(damage: int) -> void:
	if dead:
		return

	var was_blocking := blocking

	if was_blocking:
		damage = int(damage * (1.0 - block_damage_reduction))
		print("KNIGHT BLOCKED! REDUCED DAMAGE: ", damage)

	health = max(health - damage, 0)
	print("KNIGHT HP: ", health, "/", max_health)

	# Red flash, even while attacking or blocking (skipped if fully blocked)
	if damage > 0:
		flash_red()

	if health <= 0:
		die()
		return

	# Blocked hits don't interrupt the shield
	if was_blocking:
		return

	hurt = true
	_clear_combat_state()
	_restart_animation("hurt")

	await animated_sprite.animation_finished

	if dead:
		return

	hurt = false
	animated_sprite.play("idle")


func die() -> void:
	if dead:
		return

	dead = true
	hurt = false
	_clear_combat_state()

	collision_shape.set_deferred("disabled", true)
	_restart_animation("death")

	print("KNIGHT DIED")

	await animated_sprite.animation_finished
	await get_tree().create_timer(respawn_time).timeout

	if not is_inside_tree():
		return

	respawn()


func respawn() -> void:
	health = max_health
	dead = false
	hurt = false
	_clear_combat_state()

	if flash_tween:
		flash_tween.kill()
	animated_sprite.modulate = base_modulate

	collision_shape.set_deferred("disabled", false)
	animated_sprite.play("idle")

	print("KNIGHT RESPAWNED | PLAYER ID: ", player_id, " | HP: ", health)
