extends CharacterBody2D

# --- Movement ---
@export var speed: float = 180.0

# --- Health ---
@export var max_health: int = 100
@export var respawn_time: float = 3.0

# --- Attack damage ---
@export var attack1_damage: int = 10
@export var attack2_damage: int = 15

# --- Heal ---
@export var heal_amount: int = 30

# --- Hit flash ---
@export var hit_flash_color: Color = Color(1.0, 0.25, 0.25, 1.0)
@export var hit_flash_time: float = 0.25

# --- State ---
var player_id: int = 0
var health: int
var dead: bool = false
var hurt: bool = false
var attacking: bool = false
var current_attack: String = ""

var base_modulate: Color = Color.WHITE
var flash_tween: Tween

# --- Input action names (filled in by _setup_actions) ---
var act_up: String
var act_down: String
var act_left: String
var act_right: String
var act_attack1: String
var act_attack2: String
var act_attack3: String   # heal

# --- Nodes ---
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
			print("WARNING: Healer is not under Player1 or Player2")

	_setup_actions()

	health = max_health
	dead = false
	hurt = false
	attacking = false

	base_modulate = animated_sprite.modulate

	collision_shape.set_deferred("disabled", false)

	print("HEALER READY | PLAYER ID: ", player_id, " | HP: ", health)
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

	if attacking:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if Input.is_action_just_pressed(act_attack1):
		start_attack("attack1")
		return

	if Input.is_action_just_pressed(act_attack2):
		start_attack("attack2")
		return

	if Input.is_action_just_pressed(act_attack3):
		start_heal()
		return

	var direction := Input.get_vector(act_left, act_right, act_up, act_down)

	velocity = direction * speed

	if direction.x != 0:
		animated_sprite.flip_h = direction.x < 0

	animated_sprite.play("walk" if direction != Vector2.ZERO else "idle")

	move_and_slide()


# =========================================================
# ATTACK / HEAL
# =========================================================

func start_attack(animation_name: String) -> void:
	if attacking or hurt or dead:
		return

	attacking = true
	current_attack = animation_name
	velocity = Vector2.ZERO

	print("PLAYER ", player_id, " HEALER ATTACK: ", animation_name)

	_restart_animation(animation_name)

	await animated_sprite.animation_finished

	if dead or hurt:
		return

	end_attack()


func start_heal() -> void:
	if attacking or hurt or dead:
		return

	attacking = true
	current_attack = "heal"
	velocity = Vector2.ZERO

	print("PLAYER ", player_id, " HEALER HEAL")

	_restart_animation("heal")

	await animated_sprite.animation_finished

	if dead or hurt:
		return

	heal(heal_amount)
	end_attack()


func heal(amount: int) -> void:
	health = min(health + amount, max_health)

	print("PLAYER ", player_id, " HEALED: ", amount, " | HP: ", health, "/", max_health)


func end_attack() -> void:
	attacking = false
	current_attack = ""
	velocity = Vector2.ZERO

	if not dead and not hurt:
		animated_sprite.play("idle")


func get_attack_damage() -> int:
	match current_attack:
		"attack1":
			return attack1_damage
		"attack2":
			return attack2_damage

	return 0


# =========================================================
# DAMAGE / DEATH / RESPAWN
# =========================================================

func take_damage(damage: int) -> void:
	if dead:
		return

	health = max(health - damage, 0)

	print("PLAYER ", player_id, " HEALER TOOK DAMAGE: ", damage, " | HP: ", health, "/", max_health)

	# Red flash, even while an animation is playing
	flash_red()

	if health <= 0:
		die()
		return

	hurt = true
	attacking = false
	current_attack = ""
	velocity = Vector2.ZERO

	_restart_animation("hurt")

	print("HEALER HURT")

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
	attacking = false
	current_attack = ""
	velocity = Vector2.ZERO

	collision_shape.set_deferred("disabled", true)
	_restart_animation("death")

	print("PLAYER ", player_id, " HEALER DIED")

	await animated_sprite.animation_finished
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

	if flash_tween:
		flash_tween.kill()
	animated_sprite.modulate = base_modulate

	collision_shape.set_deferred("disabled", false)
	animated_sprite.play("idle")

	print("HEALER RESPAWNED | PLAYER ID: ", player_id, " | HP: ", health)
