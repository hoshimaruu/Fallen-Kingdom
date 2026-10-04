extends CharacterBody2D


# =========================
# MOVEMENT
# =========================

@export var speed: float = 180.0


# =========================
# HEALTH
# =========================

@export var max_health: int = 100

var health: int
var dead: bool = false


# =========================
# ATTACK DAMAGE
# =========================

@export var attack1_damage: int = 10
@export var attack2_damage: int = 15


# =========================
# HEAL
# =========================

@export var heal_amount: int = 30


# =========================
# NODE
# =========================

@onready var animated_sprite = $AnimatedSprite2D


# =========================
# ATTACK STATE
# =========================

var attacking: bool = false
var current_attack: String = ""


# =========================
# READY
# =========================

func _ready():
	health = max_health

	print("HEALER READY")
	print("HP:", health)
	print("AVAILABLE ANIMATIONS:")
	print(animated_sprite.sprite_frames.get_animation_names())


# =========================
# MAIN
# =========================

func _physics_process(_delta):

	if dead:
		velocity = Vector2.ZERO
		return


	# =========================
	# ATTACKING
	# =========================

	if attacking:
		velocity = Vector2.ZERO
		move_and_slide()
		return


	# =========================
	# ATTACK 1
	# =========================

	if Input.is_action_just_pressed("attack1"):
		start_attack("attack1")
		return


	# =========================
	# ATTACK 2
	# =========================

	if Input.is_action_just_pressed("attack2"):
		start_attack("attack2")
		return


	# =========================
	# ATTACK 3 = HEAL
	# =========================

	if Input.is_action_just_pressed("attack3"):
		start_heal()
		return


	# =========================
	# MOVEMENT
	# =========================

	var direction = Input.get_vector(
		"move_left",
		"move_right",
		"move_up",
		"move_down"
	)

	velocity = direction * speed


	# =========================
	# FACE LEFT / RIGHT
	# =========================

	if direction.x < 0:
		animated_sprite.flip_h = true
	elif direction.x > 0:
		animated_sprite.flip_h = false


	# =========================
	# MOVEMENT ANIMATION
	# =========================

	if direction == Vector2.ZERO:
		animated_sprite.play("idle")
	else:
		animated_sprite.play("walk")

	move_and_slide()


# =========================
# ATTACK 1 / ATTACK 2
# =========================

func start_attack(animation_name: String):

	if attacking:
		return

	attacking = true
	current_attack = animation_name
	velocity = Vector2.ZERO

	print("HEALER ATTACK:", animation_name)

	animated_sprite.stop()
	animated_sprite.animation = animation_name
	animated_sprite.frame = 0
	animated_sprite.play()

	await animated_sprite.animation_finished

	end_attack()


# =========================
# HEAL
# =========================

func start_heal():

	if attacking:
		return

	attacking = true
	current_attack = "heal"
	velocity = Vector2.ZERO

	print("HEALER HEAL")

	# Use the actual "heal" animation
	animated_sprite.stop()
	animated_sprite.animation = "heal"
	animated_sprite.frame = 0
	animated_sprite.play()

	await animated_sprite.animation_finished

	heal(heal_amount)

	end_attack()


# =========================
# HEAL FUNCTION
# =========================

func heal(amount: int):

	health += amount
	health = min(health, max_health)

	print("HEALED:", amount)
	print("HP:", health, "/", max_health)


# =========================
# ATTACK DAMAGE
# =========================

func get_attack_damage():

	if current_attack == "attack1":
		return attack1_damage

	if current_attack == "attack2":
		return attack2_damage

	return 0


# =========================
# END ATTACK
# =========================

func end_attack():

	attacking = false
	current_attack = ""
	velocity = Vector2.ZERO

	if not dead:
		animated_sprite.play("idle")


# =========================
# TAKE DAMAGE
# =========================

func take_damage(damage: int):

	if dead:
		return

	health -= damage
	health = max(health, 0)

	print("HEALER HIT")
	print("Damage:", damage)
	print("HP:", health, "/", max_health)

	if health <= 0:
		die()


# =========================
# DEATH
# =========================

func die():

	if dead:
		return

	dead = true
	attacking = false
	velocity = Vector2.ZERO

	print("HEALER DIED")

	animated_sprite.stop()
	animated_sprite.animation = "death"
	animated_sprite.frame = 0
	animated_sprite.play()
