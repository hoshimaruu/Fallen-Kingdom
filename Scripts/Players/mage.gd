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

@export var max_health: int = 70

var health: int
var dead: bool = false


# =========================================================
# ATTACK DAMAGE
# =========================================================

@export var attack1_damage: int = 20
@export var attack2_damage: int = 30
@export var attack3_damage: int = 40


# =========================================================
# NODE
# =========================================================

@onready var animated_sprite = $AnimatedSprite2D


# =========================================================
# ATTACK
# =========================================================

var attacking: bool = false
var current_attack: String = ""


# =========================================================
# READY
# =========================================================

func _ready():

	if get_parent().name == "Player1":

		player_id = 1

	elif get_parent().name == "Player2":

		player_id = 2

	else:

		print("WARNING: Mage is not under Player1 or Player2")


	health = max_health


	print("MAGE READY")
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
# MAIN LOOP
# =========================================================

func _physics_process(_delta):

	if dead:

		velocity = Vector2.ZERO

		return


	# =====================================================
	# ATTACKING
	# =====================================================

	if attacking:

		velocity = Vector2.ZERO

		move_and_slide()

		return


	# =====================================================
	# ATTACK 1
	# =====================================================

	if Input.is_action_just_pressed(get_attack1_action()):

		start_attack("attack1")

		return


	# =====================================================
	# ATTACK 2
	# =====================================================

	if Input.is_action_just_pressed(get_attack2_action()):

		start_attack("attack2")

		return


	# =====================================================
	# ATTACK 3
	# =====================================================

	if Input.is_action_just_pressed(get_attack3_action()):

		start_attack("attack3")

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


	# =====================================================
	# FACE LEFT / RIGHT
	# =====================================================

	if direction.x < 0:

		animated_sprite.flip_h = true

	elif direction.x > 0:

		animated_sprite.flip_h = false


	# =====================================================
	# MOVEMENT ANIMATION
	# =====================================================

	if direction == Vector2.ZERO:

		animated_sprite.play("idle")

	else:

		animated_sprite.play("walk")


	move_and_slide()


# =========================================================
# START ATTACK
# =========================================================

func start_attack(animation_name: String):

	if attacking:
		return


	attacking = true

	current_attack = animation_name

	velocity = Vector2.ZERO


	print("PLAYER", player_id, "MAGE ATTACK:", animation_name)


	animated_sprite.stop()

	animated_sprite.animation = animation_name

	animated_sprite.frame = 0

	animated_sprite.play()


	await animated_sprite.animation_finished


	end_attack()


# =========================================================
# END ATTACK
# =========================================================

func end_attack():

	attacking = false

	current_attack = ""

	velocity = Vector2.ZERO


	if not dead:

		animated_sprite.play("idle")


	print("PLAYER", player_id, "MAGE ATTACK FINISHED")


# =========================================================
# GET ATTACK DAMAGE
# =========================================================

func get_attack_damage():

	if current_attack == "attack1":

		return attack1_damage


	if current_attack == "attack2":

		return attack2_damage


	if current_attack == "attack3":

		return attack3_damage


	return 0


# =========================================================
# TAKE DAMAGE
# =========================================================

func take_damage(damage: int):

	if dead:
		return


	health -= damage

	health = max(health, 0)


	print("PLAYER", player_id, "MAGE HIT")

	print("Damage:", damage)

	print("HP:", health, "/", max_health)


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

	velocity = Vector2.ZERO


	print("PLAYER", player_id, "MAGE DIED")


	animated_sprite.stop()

	animated_sprite.animation = "death"

	animated_sprite.frame = 0

	animated_sprite.play()
