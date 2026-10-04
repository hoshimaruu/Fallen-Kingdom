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

var health: int
var dead: bool = false


# =========================================================
# ATTACK DAMAGE
# =========================================================

@export var attack1_damage: int = 10
@export var attack2_damage: int = 15
@export var attack3_damage: int = 25


# =========================================================
# NODES
# =========================================================

@onready var animated_sprite = $AnimatedSprite2D
@onready var attack_area = $AttackArea


# =========================================================
# ATTACK VARIABLES
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

		print("WARNING: Knight is not under Player1 or Player2")


	health = max_health

	attack_area.monitoring = false


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

		attack_area.scale.x = -1

	elif direction.x > 0:

		animated_sprite.flip_h = false

		attack_area.scale.x = 1


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


	if dead:
		return


	attacking = true

	current_attack = animation_name

	velocity = Vector2.ZERO

	attack_area.monitoring = false


	print("================================")
	print("PLAYER", player_id, "KNIGHT ATTACK")
	print("Animation:", animation_name)
	print("================================")


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

	print("PLAYER", player_id, "ATTACK FINISHED:", current_attack)

	attack_area.monitoring = false

	attacking = false

	current_attack = ""

	velocity = Vector2.ZERO

	animated_sprite.play("idle")


# =========================================================
# ATTACK DAMAGE
# =========================================================

func perform_attack():

	if dead:
		return


	var damage = 0


	if current_attack == "attack1":

		damage = attack1_damage

	elif current_attack == "attack2":

		damage = attack2_damage

	elif current_attack == "attack3":

		damage = attack3_damage


	if damage <= 0:

		return


	print("PLAYER", player_id, "KNIGHT ATTACK HIT")

	print("Damage:", damage)


	var bodies = attack_area.get_overlapping_bodies()


	for body in bodies:

		if body == self:

			continue


		if body.has_method("take_damage"):

			body.take_damage(damage)

			print("Hit:", body.name)


# =========================================================
# TAKE DAMAGE
# =========================================================

func take_damage(damage: int):

	if dead:
		return


	health -= damage

	health = max(health, 0)


	print("PLAYER", player_id, "KNIGHT HIT")

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

	attack_area.monitoring = false


	print("PLAYER", player_id, "KNIGHT DIED")


	animated_sprite.stop()

	animated_sprite.animation = "death"

	animated_sprite.frame = 0

	animated_sprite.play()
