extends CharacterBody2D


# =========================================================
# PLAYER ID
# =========================================================

var player_id: int = 0


# =========================================================
# MOVEMENT
# =========================================================

@export var speed: float = 180.0


# =========================================================
# HEALTH
# =========================================================

@export var max_health: int = 100
@export var respawn_time: float = 3.0

var health: int
var dead: bool = false
var hurt: bool = false


# =========================================================
# ATTACK DAMAGE
# =========================================================

@export var attack1_damage: int = 10
@export var attack2_damage: int = 15


# =========================================================
# HEAL
# =========================================================

@export var heal_amount: int = 30


# =========================================================
# ATTACK STATE
# =========================================================

var attacking: bool = false
var current_attack: String = ""


# =========================================================
# NODES
# =========================================================

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D


# =========================================================
# READY
# =========================================================

func _ready():

	add_to_group("players")


	if get_parent().name == "Player1":

		player_id = 1

	elif get_parent().name == "Player2":

		player_id = 2

	else:

		print("WARNING: Healer is not under Player1 or Player2")


	health = max_health

	dead = false
	hurt = false
	attacking = false


	collision_shape.set_deferred(
		"disabled",
		false
	)


	print("================================")
	print("HEALER READY")
	print("PLAYER ID:", player_id)
	print("HP:", health)
	print("GROUPS:", get_groups())
	print("AVAILABLE ANIMATIONS:")
	print(animated_sprite.sprite_frames.get_animation_names())
	print("================================")


# =========================================================
# INPUT ACTIONS
# =========================================================

func get_up_action() -> String:

	if player_id == 1:
		return "p1_up"

	return "p2_up"


func get_down_action() -> String:

	if player_id == 1:
		return "p1_down"

	return "p2_down"


func get_left_action() -> String:

	if player_id == 1:
		return "p1_left"

	return "p2_left"


func get_right_action() -> String:

	if player_id == 1:
		return "p1_right"

	return "p2_right"


func get_attack1_action() -> String:

	if player_id == 1:
		return "p1_attack1"

	return "p2_attack1"


func get_attack2_action() -> String:

	if player_id == 1:
		return "p1_attack2"

	return "p2_attack2"


func get_attack3_action() -> String:

	if player_id == 1:
		return "p1_attack3"

	return "p2_attack3"


# =========================================================
# PHYSICS
# =========================================================

func _physics_process(_delta):

	if dead:

		velocity = Vector2.ZERO

		return


	if hurt:

		velocity = Vector2.ZERO

		return


	if attacking:

		velocity = Vector2.ZERO

		move_and_slide()

		return


	if Input.is_action_just_pressed(
		get_attack1_action()
	):

		start_attack("attack1")

		return


	if Input.is_action_just_pressed(
		get_attack2_action()
	):

		start_attack("attack2")

		return


	if Input.is_action_just_pressed(
		get_attack3_action()
	):

		start_heal()

		return


	var direction = Input.get_vector(
		get_left_action(),
		get_right_action(),
		get_up_action(),
		get_down_action()
	)


	velocity = direction * speed


	if direction.x < 0:

		animated_sprite.flip_h = true

	elif direction.x > 0:

		animated_sprite.flip_h = false


	if direction == Vector2.ZERO:

		animated_sprite.play("idle")

	else:

		animated_sprite.play("walk")


	move_and_slide()


# =========================================================
# ATTACK
# =========================================================

func start_attack(animation_name: String):

	if attacking or hurt or dead:

		return


	attacking = true

	current_attack = animation_name

	velocity = Vector2.ZERO


	print(
		"PLAYER",
		player_id,
		"HEALER ATTACK:",
		animation_name
	)


	animated_sprite.stop()

	animated_sprite.animation = animation_name

	animated_sprite.frame = 0

	animated_sprite.play()


	await animated_sprite.animation_finished


	if dead or hurt:

		return


	end_attack()


# =========================================================
# HEAL
# =========================================================

func start_heal():

	if attacking or hurt or dead:

		return


	attacking = true

	current_attack = "heal"

	velocity = Vector2.ZERO


	print(
		"PLAYER",
		player_id,
		"HEALER HEAL"
	)


	animated_sprite.stop()

	animated_sprite.animation = "heal"

	animated_sprite.frame = 0

	animated_sprite.play()


	await animated_sprite.animation_finished


	if dead or hurt:

		return


	heal(heal_amount)

	end_attack()


func heal(amount: int):

	health += amount

	health = min(
		health,
		max_health
	)


	print(
		"PLAYER",
		player_id,
		"HEALED:",
		amount
	)

	print(
		"HP:",
		health,
		"/",
		max_health
	)


# =========================================================
# ATTACK DAMAGE
# =========================================================

func get_attack_damage():

	if current_attack == "attack1":

		return attack1_damage


	if current_attack == "attack2":

		return attack2_damage


	return 0


# =========================================================
# END ATTACK
# =========================================================

func end_attack():

	attacking = false

	current_attack = ""

	velocity = Vector2.ZERO


	if not dead and not hurt:

		animated_sprite.play("idle")


# =========================================================
# TAKE DAMAGE
# =========================================================

func take_damage(damage: int):

	if dead:

		return


	health -= damage

	health = max(health, 0)


	print(
		"PLAYER",
		player_id,
		"HEALER TOOK DAMAGE:",
		damage
	)

	print(
		"HEALER HP:",
		health,
		"/",
		max_health
	)


	if health <= 0:

		die()

		return


	hurt = true

	attacking = false

	current_attack = ""

	velocity = Vector2.ZERO


	animated_sprite.stop()

	animated_sprite.animation = "hurt"

	animated_sprite.frame = 0

	animated_sprite.play()


	print("HEALER HURT")


	await animated_sprite.animation_finished


	if dead:

		return


	hurt = false

	animated_sprite.play("idle")


# =========================================================
# DEATH
# =========================================================

func die():

	if dead:

		return


	dead = true

	hurt = false

	attacking = false

	current_attack = ""

	velocity = Vector2.ZERO


	collision_shape.set_deferred(
		"disabled",
		true
	)


	animated_sprite.stop()

	animated_sprite.animation = "death"

	animated_sprite.frame = 0

	animated_sprite.play()


	print(
		"PLAYER",
		player_id,
		"HEALER DIED"
	)


	await animated_sprite.animation_finished


	await get_tree().create_timer(
		respawn_time
	).timeout


	if not is_inside_tree():

		return


	respawn()


# =========================================================
# RESPAWN
# =========================================================

func respawn():

	health = max_health

	dead = false

	hurt = false

	attacking = false

	current_attack = ""

	velocity = Vector2.ZERO


	collision_shape.set_deferred(
		"disabled",
		false
	)


	animated_sprite.play("idle")


	print("================================")
	print("HEALER RESPAWNED")
	print("PLAYER ID:", player_id)
	print("HP:", health)
	print("================================")
