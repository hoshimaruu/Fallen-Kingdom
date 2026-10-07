extends CharacterBody2D

@export var max_health: int = 100
@export var respawn_time: float = 3.0

@export var move_speed: float = 80.0

@export var attack_damage: int = 10
@export var attack2_damage: int = 20
@export var heavy_attack_every: int = 3
@export var attack1_hit_frame: int = 4
@export var attack2_hit_frame: int = 4
@export var attack_range: float = 70.0
@export var attack_cooldown: float = 1.5

# Freeze
@export var freeze_tint: Color = Color(0.55, 0.85, 1.0, 1.0)

var health: int = 0

var dead: bool = false
var hurt: bool = false

var frozen: bool = false
var freeze_time_left: float = 0.0

var can_attack: bool = true
var attacking: bool = false
var damage_dealt: bool = false

var attack_count: int = 0
var attack_target = null

var base_modulate: Color = Color.WHITE

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	add_to_group("enemies")

	health = max_health
	dead = false
	hurt = false

	frozen = false
	freeze_time_left = 0.0

	can_attack = true
	attacking = false
	damage_dealt = false

	attack_count = 0
	attack_target = null

	base_modulate = animated_sprite.modulate

	collision_shape.set_deferred("disabled", false)

	animated_sprite.visible = true
	animated_sprite.modulate = base_modulate
	animated_sprite.play("idle")

	print("================================")
	print("ORC READY")
	print("HP:", health)
	print("================================")
	print("ANIMATIONS:", animated_sprite.sprite_frames.get_animation_names())


func _physics_process(delta: float) -> void:
	update_freeze(delta)

	velocity = Vector2.ZERO

	if dead:
		return

	if frozen:
		velocity = Vector2.ZERO
		animated_sprite.play("idle")
		return

	if hurt:
		return

	if attacking:
		return

	var target = find_nearest_player()

	if target == null:
		play_if_not("idle")
		return

	var distance: float = global_position.distance_to(target.global_position)

	animated_sprite.flip_h = target.global_position.x < global_position.x

	if distance > attack_range:
		var direction: Vector2 = global_position.direction_to(target.global_position)

		velocity = direction * move_speed
		move_and_slide()

		play_if_not("walk")
	else:
		play_if_not("idle")

		if can_attack:
			start_attack(target)


# ============================================================
# FREEZE
# ============================================================

func update_freeze(delta: float) -> void:
	if not frozen:
		return

	freeze_time_left -= delta

	if freeze_time_left <= 0.0:
		unfreeze()
	else:
		animated_sprite.modulate = freeze_tint


func apply_freeze(duration: float) -> void:
	if dead:
		return

	if duration <= 0.0:
		return

	freeze_time_left = maxf(freeze_time_left, duration)

	if not frozen:
		frozen = true

	attacking = false
	hurt = false
	damage_dealt = false
	attack_target = null
	can_attack = false

	velocity = Vector2.ZERO

	animated_sprite.stop()
	animated_sprite.animation = "idle"
	animated_sprite.frame = 0
	animated_sprite.modulate = freeze_tint

	print("================================")
	print("ORC FROZEN")
	print("FREEZE TIME:", freeze_time_left)
	print("================================")


func unfreeze() -> void:
	if not frozen:
		return

	frozen = false
	freeze_time_left = 0.0

	# Fully reset combat state
	hurt = false
	attacking = false
	damage_dealt = false
	attack_target = null
	can_attack = true

	velocity = Vector2.ZERO

	animated_sprite.modulate = base_modulate
	animated_sprite.stop()
	animated_sprite.animation = "idle"
	animated_sprite.frame = 0
	animated_sprite.play()

	print("================================")
	print("ORC UNFROZEN")
	print("ORC CAN MOVE AGAIN")
	print("================================")


# ============================================================
# ANIMATION
# ============================================================

func play_if_not(anim_name: String) -> void:
	if animated_sprite.animation != anim_name or not animated_sprite.is_playing():
		animated_sprite.play(anim_name)


# ============================================================
# FIND PLAYER
# ============================================================

func find_nearest_player():
	var nearest_player = null
	var nearest_distance: float = INF

	for player in get_tree().get_nodes_in_group("players"):
		if not is_instance_valid(player):
			continue

		if not player.has_method("take_damage"):
			continue

		if player.dead:
			continue

		var distance: float = global_position.distance_to(player.global_position)

		if distance < nearest_distance:
			nearest_distance = distance
			nearest_player = player

	return nearest_player


# ============================================================
# ATTACK
# ============================================================

func start_attack(target) -> void:
	if dead:
		return

	if frozen:
		return

	if hurt:
		return

	if attacking:
		return

	if not can_attack:
		return

	if target == null:
		return

	attack_target = target

	attacking = true
	can_attack = false
	damage_dealt = false

	velocity = Vector2.ZERO

	attack_count += 1

	var heavy: bool = (attack_count % heavy_attack_every == 0)

	var anim_name: String
	var damage: int
	var hit_frame: int

	if heavy:
		anim_name = "attack2"
		damage = attack2_damage
		hit_frame = attack2_hit_frame
	else:
		anim_name = "attack1"
		damage = attack_damage
		hit_frame = attack1_hit_frame

	animated_sprite.flip_h = target.global_position.x < global_position.x

	animated_sprite.stop()
	animated_sprite.animation = anim_name
	animated_sprite.frame = 0
	animated_sprite.play()

	print("================================")
	print("ORC ATTACK:", anim_name)
	print("ATTACK #:", attack_count)
	print("TARGET:", target.name)
	print("DAMAGE:", damage)
	print("HIT FRAME:", hit_frame)
	print("================================")

	await wait_for_attack_frame(hit_frame)

	if dead or frozen:
		return

	if not damage_dealt:
		deal_attack_damage(damage)

	await animated_sprite.animation_finished

	if dead or frozen:
		return

	attacking = false
	damage_dealt = false
	attack_target = null

	animated_sprite.play("idle")

	await get_tree().create_timer(attack_cooldown).timeout

	if dead or frozen:
		return

	attacking = false
	damage_dealt = false
	attack_target = null
	can_attack = true


func wait_for_attack_frame(target_frame: int) -> void:
	while true:
		if dead:
			return

		if frozen:
			return

		if not attacking:
			return

		if animated_sprite.frame >= target_frame:
			return

		await get_tree().process_frame


func deal_attack_damage(damage: int) -> void:
	if dead:
		return

	if frozen:
		return

	if damage_dealt:
		return

	damage_dealt = true

	var target = attack_target

	if target == null:
		return

	if not is_instance_valid(target):
		return

	if target.dead:
		return

	var distance: float = global_position.distance_to(target.global_position)

	if distance > attack_range:
		print("ORC ATTACK MISSED: OUT OF RANGE")
		return

	if target.has_method("take_damage"):
		print("================================")
		print("ORC HIT:", target.name)
		print("DAMAGE:", damage)
		print("ATTACK FRAME:", animated_sprite.frame)
		print("================================")

		target.take_damage(damage)


# ============================================================
# DAMAGE
# ============================================================

func take_damage(damage: int) -> void:
	if dead:
		return

	health -= damage
	health = max(health, 0)

	print("================================")
	print("ORC TOOK DAMAGE:", damage)
	print("ORC HP:", health)
	print("================================")

	if health <= 0:
		die()
		return

	if frozen:
		return

	if attacking:
		return

	hurt = true
	velocity = Vector2.ZERO

	animated_sprite.stop()
	animated_sprite.animation = "hurt"
	animated_sprite.frame = 0
	animated_sprite.play()

	await animated_sprite.animation_finished

	if dead:
		return

	if frozen:
		return

	hurt = false
	animated_sprite.play("idle")


# ============================================================
# DEATH
# ============================================================

func die() -> void:
	if dead:
		return

	dead = true

	hurt = false
	frozen = false
	freeze_time_left = 0.0

	attacking = false
	can_attack = false

	damage_dealt = false
	attack_target = null

	velocity = Vector2.ZERO

	animated_sprite.modulate = base_modulate

	collision_shape.set_deferred("disabled", true)

	animated_sprite.stop()
	animated_sprite.animation = "death"
	animated_sprite.frame = 0
	animated_sprite.play()

	print("================================")
	print("ORC DIED")
	print("================================")

	await animated_sprite.animation_finished

	if not is_instance_valid(self):
		return

	animated_sprite.visible = false

	print("ORC DISAPPEARED")

	await get_tree().create_timer(respawn_time).timeout

	if not is_instance_valid(self):
		return

	respawn()


# ============================================================
# RESPAWN
# ============================================================

func respawn() -> void:
	health = max_health

	dead = false
	hurt = false

	frozen = false
	freeze_time_left = 0.0

	attacking = false
	can_attack = true

	damage_dealt = false
	attack_count = 0
	attack_target = null

	velocity = Vector2.ZERO

	animated_sprite.modulate = base_modulate

	collision_shape.set_deferred("disabled", false)

	animated_sprite.visible = true
	animated_sprite.stop()
	animated_sprite.animation = "idle"
	animated_sprite.frame = 0
	animated_sprite.play()

	print("================================")
	print("ORC RESPAWNED")
	print("ORC HP:", health)
	print("================================")
