extends CharacterBody2D


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

	health = max_health

	# Attack hitbox starts disabled
	attack_area.monitoring = false

	print("PLAYER READY")
	print("HP:", health)

	print("AVAILABLE ANIMATIONS:")
	print(animated_sprite.sprite_frames.get_animation_names())


# =========================================================
# MAIN LOOP
# =========================================================

func _physics_process(_delta):

	# =====================================================
	# DEAD
	# =====================================================

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
	# ATTACK INPUT
	# =====================================================

	if Input.is_action_just_pressed("attack1"):
		start_attack("attack1")
		return

	if Input.is_action_just_pressed("attack2"):
		start_attack("attack2")
		return

	if Input.is_action_just_pressed("attack3"):
		start_attack("attack3")
		return


	# =====================================================
	# MOVEMENT
	# =====================================================

	var direction = Input.get_vector(
		"move_left",
		"move_right",
		"move_up",
		"move_down"
	)


	velocity = direction * speed


	# =====================================================
	# FACE LEFT / RIGHT
	# =====================================================

	if direction.x < 0:

		animated_sprite.flip_h = true

		# AttackArea faces left
		attack_area.scale.x = -1


	elif direction.x > 0:

		animated_sprite.flip_h = false

		# AttackArea faces right
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

	# Disable hitbox before attack
	attack_area.monitoring = false


	print("================================")
	print("ATTACK START")
	print("Animation:", animation_name)
	print("================================")


	# Make absolutely sure the animation starts
	animated_sprite.stop()
	animated_sprite.animation = animation_name
	animated_sprite.frame = 0
	animated_sprite.play()


	# Wait for animation to finish
	await animated_sprite.animation_finished


	# Attack is finished
	end_attack()


# =========================================================
# END ATTACK
# =========================================================

func end_attack():

	print("ATTACK FINISHED:", current_attack)

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


	print("ATTACK HIT")
	print("Damage:", damage)


	# Check everything inside AttackArea
	var bodies = attack_area.get_overlapping_bodies()


	for body in bodies:

		# Don't damage yourself
		if body == self:
			continue


		# Check if the enemy has take_damage()
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


	print("PLAYER HIT")
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


	print("PLAYER DIED")


	animated_sprite.stop()
	animated_sprite.animation = "death"
	animated_sprite.frame = 0
	animated_sprite.play()
