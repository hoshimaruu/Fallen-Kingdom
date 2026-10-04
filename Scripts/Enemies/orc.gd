extends CharacterBody2D


# =========================================================
# HEALTH
# =========================================================

@export var max_health: int = 100
@export var respawn_time: float = 3.0

var health: int = 0
var dead: bool = false


# =========================================================
# ATTACK
# =========================================================

@export var attack_damage: int = 10
@export var attack_range: float = 70.0
@export var attack_cooldown: float = 1.5

var can_attack: bool = true
var attacking: bool = false
var damage_dealt: bool = false


# =========================================================
# NODES
# =========================================================

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D


# =========================================================
# READY
# =========================================================

func _ready():
	add_to_group("enemies")

	health = max_health
	dead = false

	can_attack = true
	attacking = false
	damage_dealt = false

	collision_shape.set_deferred("disabled", false)

	animated_sprite.visible = true
	animated_sprite.play("idle")

	print("================================")
	print("ORC READY")
	print("HP:", health)
	print("COLLISION LAYER:", collision_layer)
	print("COLLISION MASK:", collision_mask)
	print("ANIMATIONS:", animated_sprite.sprite_frames.get_animation_names())
	print("================================")


# =========================================================
# PHYSICS
# =========================================================

func _physics_process(_delta):
	velocity = Vector2.ZERO

	if dead:
		return

	if attacking:
		return

	if not can_attack:
		return

	var target = find_nearest_player()

	if target == null:
		return

	var distance = global_position.distance_to(target.global_position)

	if distance <= attack_range:
		start_attack(target)


# =========================================================
# FIND NEAREST PLAYER
# =========================================================

func find_nearest_player():
	var players = get_tree().get_nodes_in_group("players")

	var nearest_player = null
	var nearest_distance = INF

	for player in players:
		if not is_instance_valid(player):
			continue

		if not player.has_method("take_damage"):
			continue

		if player.dead:
			continue

		var distance = global_position.distance_to(player.global_position)

		if distance < nearest_distance:
			nearest_distance = distance
			nearest_player = player

	return nearest_player


# =========================================================
# START ATTACK
# =========================================================

func start_attack(target):
	if dead:
		return

	if attacking:
		return

	if not can_attack:
		return

	if target == null:
		return

	attacking = true
	can_attack = false
	damage_dealt = false

	velocity = Vector2.ZERO

	# Face the player
	if target.global_position.x < global_position.x:
		animated_sprite.flip_h = true
	else:
		animated_sprite.flip_h = false

	# Start Attack 1
	animated_sprite.stop()
	animated_sprite.animation = "attack1"
	animated_sprite.frame = 0
	animated_sprite.play()

	print("================================")
	print("ORC ATTACK 1 START")
	print("TARGET:", target.name)
	print("================================")

	# Wait until the animation reaches frame 4
	await wait_for_attack_frame(4)

	if dead:
		return

	if not is_instance_valid(self):
		return

	# Deal damage on frame 4
	if not damage_dealt:
		deal_attack_damage()

	# Wait until attack animation finishes
	await animated_sprite.animation_finished

	if dead:
		return

	# Finish attack
	attacking = false
	damage_dealt = false

	animated_sprite.play("idle")

	print("ORC ATTACK 1 FINISHED")

	# Cooldown
	await get_tree().create_timer(attack_cooldown).timeout

	if dead:
		return

	attacking = false
	damage_dealt = false
	can_attack = true


# =========================================================
# WAIT FOR SPECIFIC ATTACK FRAME
# =========================================================

func wait_for_attack_frame(target_frame: int):
	while true:

		if dead:
			return

		if not attacking:
			return

		if animated_sprite.frame >= target_frame:
			return

		await get_tree().process_frame


# =========================================================
# DEAL ATTACK DAMAGE
# =========================================================

func deal_attack_damage():
	if dead:
		return

	if damage_dealt:
		return

	damage_dealt = true

	var target = find_nearest_player()

	if target == null:
		return

	var distance = global_position.distance_to(target.global_position)

	# Make sure the player is still close enough
	if distance > attack_range:
		print("ORC ATTACK MISSED")
		return

	if target.has_method("take_damage"):

		print("================================")
		print("ORC HIT:", target.name)
		print("ORC DAMAGE:", attack_damage)
		print("ATTACK FRAME:", animated_sprite.frame)
		print("================================")

		target.take_damage(attack_damage)


# =========================================================
# TAKE DAMAGE
# =========================================================

func take_damage(damage: int):
	if dead:
		return

	health -= damage
	health = max(health, 0)

	print("================================")
	print("ORC TOOK DAMAGE:", damage)
	print("ORC HP:", health)
	print("================================")

	# Death
	if health <= 0:
		die()
		return

	# Don't interrupt an attack with hurt
	if attacking:
		return

	animated_sprite.stop()
	animated_sprite.animation = "hurt"
	animated_sprite.frame = 0
	animated_sprite.play()

	# Wait for hurt animation
	await animated_sprite.animation_finished

	if dead:
		return

	animated_sprite.play("idle")


# =========================================================
# DEATH
# =========================================================

func die():
	if dead:
		return

	dead = true
	attacking = false
	can_attack = false
	damage_dealt = false

	velocity = Vector2.ZERO

	# Disable collision
	collision_shape.set_deferred("disabled", true)

	# Play death animation
	animated_sprite.stop()
	animated_sprite.animation = "death"
	animated_sprite.frame = 0
	animated_sprite.play()

	print("================================")
	print("ORC DIED")
	print("================================")

	# Wait for death animation
	await animated_sprite.animation_finished

	if not is_instance_valid(self):
		return

	animated_sprite.visible = false

	print("ORC DISAPPEARED")

	# Respawn timer
	await get_tree().create_timer(respawn_time).timeout

	if not is_instance_valid(self):
		return

	# Reset everything
	health = max_health
	dead = false
	attacking = false
	can_attack = true
	damage_dealt = false

	# Re-enable collision
	collision_shape.set_deferred("disabled", false)

	# Show Orc again
	animated_sprite.visible = true
	animated_sprite.play("idle")

	print("================================")
	print("ORC RESPAWNED")
	print("ORC HP:", health)
	print("================================")www
