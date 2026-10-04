extends CharacterBody2D

# --- Health ---
@export var max_health: int = 100
@export var respawn_time: float = 3.0

var health: int = 0
var dead: bool = false
var hurt: bool = false

# --- Movement ---
@export var move_speed: float = 80.0

# --- Attack ---
@export var attack_damage: int = 10           # attack1 (normal)
@export var attack2_damage: int = 20          # attack2 (heavy, every Nth attack)
@export var heavy_attack_every: int = 3       # 3 = every third attack
@export var attack1_hit_frame: int = 4
@export var attack2_hit_frame: int = 4
@export var attack_range: float = 70.0
@export var attack_cooldown: float = 1.5

var can_attack: bool = true
var attacking: bool = false
var damage_dealt: bool = false
var attack_count: int = 0

# Target that the Orc locked onto when the attack started
var attack_target = null

# --- Nodes ---
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D


func _ready():
	add_to_group("enemies")

	health = max_health
	dead = false
	hurt = false

	can_attack = true
	attacking = false
	damage_dealt = false
	attack_count = 0
	attack_target = null

	collision_shape.set_deferred("disabled", false)

	animated_sprite.visible = true
	animated_sprite.play("idle")

	print("ORC READY | HP:", health)
	print("ANIMATIONS:", animated_sprite.sprite_frames.get_animation_names())


# =========================================================
# PHYSICS (CHASE + ATTACK)
# =========================================================

func _physics_process(_delta):
	velocity = Vector2.ZERO

	# Busy: don't override attack, hurt, or death animations
	if dead or attacking or hurt:
		return

	var target = find_nearest_player()

	# No living players
	if target == null:
		play_if_not("idle")
		return

	var distance = global_position.distance_to(target.global_position)

	# Always face the nearest player
	animated_sprite.flip_h = target.global_position.x < global_position.x

	if distance > attack_range:
		# Too far: chase player
		var direction = global_position.direction_to(target.global_position)

		velocity = direction * move_speed
		move_and_slide()

		play_if_not("walk")

	else:
		# Close enough: stop and attack
		play_if_not("idle")

		if can_attack:
			start_attack(target)


# =========================================================
# PLAY ANIMATION IF NOT ALREADY PLAYING
# =========================================================

func play_if_not(anim_name: String):
	if animated_sprite.animation != anim_name or not animated_sprite.is_playing():
		animated_sprite.play(anim_name)


# =========================================================
# FIND NEAREST PLAYER
# =========================================================

func find_nearest_player():
	var nearest_player = null
	var nearest_distance = INF

	for player in get_tree().get_nodes_in_group("players"):

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
# ATTACK
# =========================================================

func start_attack(target):
	if dead or attacking or not can_attack or target == null:
		return

	# Lock onto this player for the entire attack
	attack_target = target

	attacking = true
	can_attack = false
	damage_dealt = false

	velocity = Vector2.ZERO

	# Every Nth attack is the heavy attack
	attack_count += 1

	var heavy: bool = attack_count % heavy_attack_every == 0

	var anim_name: String = "attack2" if heavy else "attack1"
	var damage: int = attack2_damage if heavy else attack_damage
	var hit_frame: int = attack2_hit_frame if heavy else attack1_hit_frame

	# Face the locked target
	animated_sprite.flip_h = target.global_position.x < global_position.x

	# Start attack animation
	animated_sprite.stop()
	animated_sprite.animation = anim_name
	animated_sprite.frame = 0
	animated_sprite.play()

	print("================================")
	print("ORC ", anim_name.to_upper(), " START")
	print("ATTACK #:", attack_count)
	print("TARGET:", target.name)
	print("DAMAGE:", damage)
	print("HIT FRAME:", hit_frame)
	print("================================")

	# Wait until the correct damage frame
	await wait_for_attack_frame(hit_frame)

	if dead:
		return

	# Deal damage exactly once
	if not damage_dealt:
		deal_attack_damage(damage)

	# Wait for the attack animation to finish
	await animated_sprite.animation_finished

	if dead:
		return

	# End attack
	attacking = false
	damage_dealt = false
	attack_target = null

	animated_sprite.play("idle")

	print("ORC ", anim_name.to_upper(), " FINISHED")

	# Attack cooldown
	await get_tree().create_timer(attack_cooldown).timeout

	if dead:
		return

	attacking = false
	damage_dealt = false
	attack_target = null
	can_attack = true


# =========================================================
# WAIT FOR ATTACK FRAME
# =========================================================

func wait_for_attack_frame(target_frame: int):
	while true:

		if dead or not attacking:
			return

		if animated_sprite.frame >= target_frame:
			return

		await get_tree().process_frame


# =========================================================
# DEAL ATTACK DAMAGE
# =========================================================

func deal_attack_damage(damage: int):
	if dead or damage_dealt:
		return

	damage_dealt = true

	# Use the player that was locked when the attack started
	var target = attack_target

	# Target disappeared or became invalid
	if target == null or not is_instance_valid(target):
		print("ORC ATTACK MISSED: TARGET INVALID")
		return

	# Target died before the attack landed
	if target.dead:
		print("ORC ATTACK MISSED: TARGET DEAD")
		return

	# Make sure target is still within attack range
	var distance = global_position.distance_to(target.global_position)

	if distance > attack_range:
		print("ORC ATTACK MISSED: TARGET OUT OF RANGE")
		return

	if target.has_method("take_damage"):

		print("================================")
		print("ORC HIT:", target.name)
		print("DAMAGE:", damage)
		print("ATTACK FRAME:", animated_sprite.frame)
		print("================================")

		target.take_damage(damage)


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

	# Dead
	if health <= 0:
		die()
		return

	# Don't interrupt an attack with hurt
	if attacking:
		return

	hurt = true

	animated_sprite.stop()
	animated_sprite.animation = "hurt"
	animated_sprite.frame = 0
	animated_sprite.play()

	# Wait for hurt animation
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
	can_attack = false
	damage_dealt = false
	attack_target = null

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
	hurt = false
	attacking = false
	can_attack = true
	damage_dealt = false
	attack_count = 0
	attack_target = null

	# Re-enable collision
	collision_shape.set_deferred("disabled", false)

	# Show Orc again
	animated_sprite.visible = true
	animated_sprite.play("idle")

	print("================================")
	print("ORC RESPAWNED")
	print("ORC HP:", health)
	print("================================")
