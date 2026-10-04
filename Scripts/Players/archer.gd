extends CharacterBody2D


# =========================================================
# MOVEMENT
# =========================================================

@export var speed: float = 180.0


# =========================================================
# DASH
# =========================================================

@export var dash_speed: float = 600.0
@export var dash_duration: float = 0.15

var dashing: bool = false
var dash_direction: float = 1.0
var dash_timer: float = 0.0


# =========================================================
# HEALTH
# =========================================================

@export var max_health: int = 80

var health: int
var dead: bool = false


# =========================================================
# ATTACK DAMAGE
# =========================================================

@export var attack1_damage: int = 15
@export var attack2_damage: int = 25


# =========================================================
# NODES
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

	health = max_health

	print("ARCHER READY")
	print("HP:", health)

	print("AVAILABLE ANIMATIONS:")
	print(animated_sprite.sprite_frames.get_animation_names())


# =========================================================
# MAIN LOOP
# =========================================================

func _physics_process(delta):

	# =====================================================
	# DEAD
	# =====================================================

	if dead:

		velocity = Vector2.ZERO

		return


	# =====================================================
	# DASHING
	# =====================================================

	if dashing:

		velocity = Vector2(
			dash_direction * dash_speed,
			0
		)

		dash_timer -= delta

		move_and_slide()

		if dash_timer <= 0:

			end_dash()

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

	if Input.is_action_just_pressed("attack1"):

		start_attack("attack1")

		return


	# =====================================================
	# ATTACK 2
	# =====================================================

	if Input.is_action_just_pressed("attack2"):

		start_attack("attack2")

		return


	# =====================================================
	# ATTACK 3 = DASH
	# =====================================================

	if Input.is_action_just_pressed("attack3"):

		start_dash()

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
# START DASH
# =========================================================

func start_dash():

	if dashing:
		return


	dashing = true

	dash_timer = dash_duration

	velocity = Vector2.ZERO


	# =====================================================
	# DASH DIRECTION
	# =====================================================

	if animated_sprite.flip_h:

		dash_direction = -1.0

	else:

		dash_direction = 1.0


	print("ARCHER DASH")


# =========================================================
# END DASH
# =========================================================

func end_dash():

	dashing = false

	velocity = Vector2.ZERO

	print("DASH FINISHED")


# =========================================================
# START ATTACK
# =========================================================

func start_attack(animation_name: String):

	if attacking:
		return


	attacking = true

	current_attack = animation_name

	velocity = Vector2.ZERO


	print("ARCHER ATTACK:", animation_name)


	# =====================================================
	# PLAY ATTACK ANIMATION
	# =====================================================

	animated_sprite.stop()

	animated_sprite.animation = animation_name

	animated_sprite.frame = 0

	animated_sprite.play()


	# Wait until attack animation finishes

	await animated_sprite.animation_finished


	end_attack()


# =========================================================
# END ATTACK
# =========================================================

func end_attack():

	attacking = false

	current_attack = ""

	velocity = Vector2.ZERO

	animated_sprite.play("idle")


	print("ATTACK FINISHED")


# =========================================================
# GET ATTACK DAMAGE
# =========================================================

func get_attack_damage():

	if current_attack == "attack1":

		return attack1_damage


	if current_attack == "attack2":

		return attack2_damage


	return 0


# =========================================================
# TAKE DAMAGE
# =========================================================

func take_damage(damage: int):

	if dead:
		return


	health -= damage

	health = max(health, 0)


	print("ARCHER HIT")

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

	dashing = false

	velocity = Vector2.ZERO


	print("ARCHER DIED")


	animated_sprite.stop()

	animated_sprite.animation = "death"

	animated_sprite.frame = 0

	animated_sprite.play()
