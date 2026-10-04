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
# ATTACK STATE
# =========================================================

var attacking: bool = false
var current_attack: String = ""

var hit_targets: Array = []


# =========================================================
# KNIGHT SLASH
# =========================================================

@export var slash_scene: PackedScene
@export var slash_release_frame: int = 8


# =========================================================
# BLOCK
# =========================================================

var blocking: bool = false

@export var block_duration: float = 1.5
@export var block_damage_reduction: float = 0.8


# =========================================================
# ATTACK AREA
# =========================================================

@export var attack_area_distance: float = 35.0


# =========================================================
# NODES
# =========================================================

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var attack_area: Area2D = $AttackArea
@onready var barrier: AnimatedSprite2D = $Barrier
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

		print("WARNING: Knight is not under Player1 or Player2")


	health = max_health

	dead = false
	hurt = false
	attacking = false
	blocking = false


	attack_area.monitoring = false

	barrier.visible = false


	collision_shape.set_deferred(
		"disabled",
		false
	)


	update_attack_area_direction()


	print("================================")
	print("KNIGHT READY")
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


	if blocking:

		velocity = Vector2.ZERO

		move_and_slide()

		return


	if attacking:

		velocity = Vector2.ZERO

		move_and_slide()

		return


	var direction = Input.get_vector(
		get_left_action(),
		get_right_action(),
		get_up_action(),
		get_down_action()
	)


	velocity = direction * speed

	move_and_slide()


	if direction.x < 0:

		animated_sprite.flip_h = true

		update_attack_area_direction()

	elif direction.x > 0:

		animated_sprite.flip_h = false

		update_attack_area_direction()


	if direction != Vector2.ZERO:

		if animated_sprite.animation != "walk":

			animated_sprite.play("walk")

	else:

		if animated_sprite.animation != "idle":

			animated_sprite.play("idle")


	if Input.is_action_just_pressed(
		get_attack1_action()
	):

		start_attack("attack1")

	elif Input.is_action_just_pressed(
		get_attack2_action()
	):

		start_attack("attack2")

	elif Input.is_action_just_pressed(
		get_attack3_action()
	):

		start_block()


# =========================================================
# UPDATE ATTACK AREA
# =========================================================

func update_attack_area_direction():

	if animated_sprite.flip_h:

		attack_area.position.x = -abs(
			attack_area_distance
		)

	else:

		attack_area.position.x = abs(
			attack_area_distance
		)


# =========================================================
# START ATTACK
# =========================================================

func start_attack(attack_name: String):

	if attacking or blocking or hurt or dead:

		return


	hit_targets.clear()

	attacking = true

	current_attack = attack_name

	velocity = Vector2.ZERO


	update_attack_area_direction()

	attack_area.monitoring = false


	animated_sprite.stop()

	animated_sprite.animation = attack_name

	animated_sprite.frame = 0

	animated_sprite.play()


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


# =========================================================
# ATTACK 1
# =========================================================

func do_melee_damage():

	var bodies = attack_area.get_overlapping_bodies()


	for body in bodies:

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


# =========================================================
# WAIT FOR SLASH FRAME
# =========================================================

func wait_for_slash_frame():

	while animated_sprite.frame < slash_release_frame:

		await animated_sprite.frame_changed

		if dead or hurt:

			return


# =========================================================
# FIRE SLASH
# =========================================================

func fire_slash():

	if slash_scene == null:

		print("ERROR: SLASH SCENE IS NOT ASSIGNED")

		return


	var slash = slash_scene.instantiate()

	get_parent().get_parent().add_child(slash)


	var facing_direction := 1.0


	if animated_sprite.flip_h:

		facing_direction = -1.0


	slash.global_position = global_position + Vector2(
		facing_direction * 35.0,
		0
	)


	slash.direction = Vector2(
		facing_direction,
		0
	)


	if facing_direction < 0:

		slash.scale.x = -1


	print("KNIGHT FIRED RED SLASH")


# =========================================================
# BLOCK
# =========================================================

func start_block():

	if attacking or blocking or hurt or dead:

		return


	blocking = true

	velocity = Vector2.ZERO

	attack_area.monitoring = false


	animated_sprite.stop()

	animated_sprite.animation = "attack3"

	animated_sprite.frame = 0

	animated_sprite.play()


	barrier.visible = true

	barrier.play()


	await animated_sprite.animation_finished


	if dead or hurt:

		return


	animated_sprite.stop()

	animated_sprite.frame = (
		animated_sprite.sprite_frames.get_frame_count(
			"attack3"
		) - 1
	)


	await get_tree().create_timer(
		block_duration
	).timeout


	if dead or hurt:

		return


	blocking = false

	barrier.visible = false

	barrier.stop()

	animated_sprite.play("idle")


# =========================================================
# TAKE DAMAGE
# =========================================================

func take_damage(damage: int):

	if dead:

		return


	if blocking:

		damage = int(
			damage * (1.0 - block_damage_reduction)
		)

		print("KNIGHT BLOCKED!")
		print("REDUCED DAMAGE:", damage)


	health -= damage

	health = max(health, 0)


	print("KNIGHT TOOK DAMAGE:", damage)

	print(
		"KNIGHT HP:",
		health,
		"/",
		max_health
	)


	if health <= 0:

		die()

		return


	hurt = true

	attacking = false

	blocking = false

	current_attack = ""

	velocity = Vector2.ZERO

	attack_area.monitoring = false

	barrier.visible = false

	barrier.stop()


	animated_sprite.stop()

	animated_sprite.animation = "hurt"

	animated_sprite.frame = 0

	animated_sprite.play()


	print("KNIGHT HURT")


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

	blocking = false

	current_attack = ""

	velocity = Vector2.ZERO

	attack_area.monitoring = false

	barrier.visible = false

	barrier.stop()


	collision_shape.set_deferred(
		"disabled",
		true
	)


	animated_sprite.stop()

	animated_sprite.animation = "death"

	animated_sprite.frame = 0

	animated_sprite.play()


	print("KNIGHT DIED")


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

	blocking = false

	current_attack = ""

	velocity = Vector2.ZERO


	collision_shape.set_deferred(
		"disabled",
		false
	)


	barrier.visible = false

	barrier.stop()


	animated_sprite.play("idle")


	print("================================")
	print("KNIGHT RESPAWNED")
	print("PLAYER ID:", player_id)
	print("HP:", health)
	print("================================")
