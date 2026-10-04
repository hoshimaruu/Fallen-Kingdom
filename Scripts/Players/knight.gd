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

var health: int = max_health
var dead: bool = false


# =========================================================
# ATTACKS
# =========================================================

@export var attack1_damage: int = 10
@export var attack2_damage: int = 15

var attacking: bool = false
var current_attack: String = ""


# =========================================================
# ATTACK 2 - RED SLASH
# =========================================================

@export var slash_scene: PackedScene

# Slash appears on frame 8
@export var slash_release_frame: int = 8


# =========================================================
# ATTACK 3 - BLOCK
# =========================================================

var blocking: bool = false

@export var block_duration: float = 1.5

# 0.8 = 80% damage reduction
@export var block_damage_reduction: float = 0.8


# =========================================================
# NODES
# =========================================================

@onready var animated_sprite = $AnimatedSprite2D
@onready var attack_area = $AttackArea
@onready var barrier = $Barrier


# =========================================================
# READY
# =========================================================

func _ready():

	var parent_name = get_parent().name

	if parent_name == "Player1":
		player_id = 1

	elif parent_name == "Player2":
		player_id = 2

	else:
		print("WARNING: Knight is not under Player1 or Player2")

	health = max_health

	attack_area.monitoring = false

	# Barrier starts hidden
	barrier.visible = false

	print("KNIGHT READY")
	print("PLAYER ID:", player_id)
	print("HP:", health)
	print("AVAILABLE ANIMATIONS:")
	print(animated_sprite.sprite_frames.get_animation_names())


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


	# =====================================================
	# BLOCKING
	# =====================================================

	if blocking:

		velocity = Vector2.ZERO
		move_and_slide()
		return


	# =====================================================
	# ATTACKING
	# =====================================================

	if attacking:

		velocity = Vector2.ZERO
		move_and_slide()
		return


	# =====================================================
	# MOVEMENT
	# =====================================================

	var direction = Input.get_vector(
		get_left_action(),
		get_right_action(),
		get_up_action(),
		get_down_action()
	)

	velocity = direction * speed

	move_and_slide()


	# =====================================================
	# SPRITE FACING
	# =====================================================

	if direction.x < 0:

		animated_sprite.flip_h = true

	elif direction.x > 0:

		animated_sprite.flip_h = false


	# =====================================================
	# MOVEMENT ANIMATION
	# =====================================================

	if direction != Vector2.ZERO:

		if animated_sprite.animation != "walk":
			animated_sprite.play("walk")

	else:

		if animated_sprite.animation != "idle":
			animated_sprite.play("idle")


	# =====================================================
	# ATTACK INPUT
	# =====================================================

	if Input.is_action_just_pressed(get_attack1_action()):

		start_attack("attack1")

	elif Input.is_action_just_pressed(get_attack2_action()):

		start_attack("attack2")

	elif Input.is_action_just_pressed(get_attack3_action()):

		start_block()


# =========================================================
# ATTACK 1 / ATTACK 2
# =========================================================

func start_attack(attack_name: String):

	if attacking or blocking or dead:
		return

	attacking = true
	current_attack = attack_name

	velocity = Vector2.ZERO

	attack_area.monitoring = false


	# =====================================================
	# PLAY ATTACK ANIMATION
	# =====================================================

	animated_sprite.stop()
	animated_sprite.animation = attack_name
	animated_sprite.frame = 0
	animated_sprite.play()


	# =====================================================
	# ATTACK 2 PROJECTILE
	# =====================================================

	if attack_name == "attack2":

		await wait_for_slash_frame()

		if dead:
			return

		fire_slash()


	# =====================================================
	# WAIT FOR ATTACK TO FINISH
	# =====================================================

	await animated_sprite.animation_finished

	if dead:
		return

	attacking = false
	current_attack = ""

	attack_area.monitoring = false

	animated_sprite.play("idle")


# =========================================================
# WAIT FOR ATTACK 2 RELEASE FRAME
# =========================================================

func wait_for_slash_frame():

	while animated_sprite.frame < slash_release_frame:

		await animated_sprite.frame_changed

		if dead:
			return


# =========================================================
# FIRE RED SLASH
# =========================================================

func fire_slash():

	if slash_scene == null:

		print("ERROR: Knight Slash Scene is not assigned!")
		return


	# =====================================================
	# CREATE PROJECTILE
	# =====================================================

	var slash = slash_scene.instantiate()


	# =====================================================
	# ADD PROJECTILE TO MAIN
	# =====================================================

	get_parent().get_parent().add_child(slash)


	# =====================================================
	# DETERMINE FACING DIRECTION
	# =====================================================

	var facing_direction := 1.0

	if animated_sprite.flip_h:

		facing_direction = -1.0


	# =====================================================
	# SPAWN SLIGHTLY IN FRONT OF KNIGHT
	# =====================================================

	slash.global_position = global_position + Vector2(
		facing_direction * 35.0,
		0
	)


	# =====================================================
	# SET PROJECTILE DIRECTION
	# =====================================================

	slash.direction = Vector2(
		facing_direction,
		0
	)


	# =====================================================
	# FLIP PROJECTILE WHEN GOING LEFT
	# =====================================================

	if facing_direction < 0:

		slash.scale.x = -1


	print("KNIGHT FIRED RED SLASH")


# =========================================================
# ATTACK 3 = BLOCK
# =========================================================

func start_block():

	if attacking or blocking or dead:
		return

	blocking = true

	velocity = Vector2.ZERO

	attack_area.monitoring = false


	# =====================================================
	# PLAY ATTACK 3 BLOCK ANIMATION
	# =====================================================

	animated_sprite.stop()
	animated_sprite.animation = "attack3"
	animated_sprite.frame = 0
	animated_sprite.play()


	# =====================================================
	# SHOW BARRIER
	# =====================================================

	barrier.visible = true
	barrier.play()


	# =====================================================
	# WAIT FOR BLOCK ANIMATION
	# =====================================================

	await animated_sprite.animation_finished

	if dead:
		return


	# =====================================================
	# HOLD LAST FRAME
	# =====================================================

	animated_sprite.stop()

	animated_sprite.frame = (
		animated_sprite.sprite_frames.get_frame_count("attack3") - 1
	)


	# =====================================================
	# BLOCK DURATION
	# =====================================================

	await get_tree().create_timer(block_duration).timeout

	if dead:
		return


	# =====================================================
	# END BLOCK
	# =====================================================

	blocking = false

	barrier.visible = false
	barrier.stop()

	animated_sprite.play("idle")


# =========================================================
# DAMAGE
# =========================================================

func take_damage(damage: int):

	if dead:
		return


	# =====================================================
	# BLOCK DAMAGE REDUCTION
	# =====================================================

	if blocking:

		damage = int(
			damage * (1.0 - block_damage_reduction)
		)

		print("KNIGHT BLOCKED!")
		print("Reduced damage:", damage)


	# =====================================================
	# APPLY DAMAGE
	# =====================================================

	health -= damage

	print("KNIGHT HP:", health)


	if health <= 0:

		die()


# =========================================================
# DEATH
# =========================================================

func die():

	if dead:
		return

	dead = true

	attacking = false
	blocking = false

	velocity = Vector2.ZERO

	attack_area.monitoring = false


	# =====================================================
	# HIDE BARRIER
	# =====================================================

	barrier.visible = false
	barrier.stop()


	# =====================================================
	# PLAY DEATH ANIMATION
	# =====================================================

	animated_sprite.stop()
	animated_sprite.animation = "death"
	animated_sprite.frame = 0
	animated_sprite.play()

	print("KNIGHT DIED")


	await animated_sprite.animation_finished

	animated_sprite.stop()
