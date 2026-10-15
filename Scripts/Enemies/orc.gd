
extends CharacterBody2D

# --- Health ---
@export var max_health: int = 100
@export var respawn_time: float = 3.0

# --- Movement ---
@export var move_speed: float = 80.0

# --- Attack ---
@export var attack_damage: int = 10
@export var attack2_damage: int = 20
@export var heavy_attack_every: int = 3
@export var attack1_hit_frame: int = 4
@export var attack2_hit_frame: int = 4
@export var attack_range: float = 70.0
@export var attack_cooldown: float = 1.5

# --- Freeze ---
@export var freeze_tint: Color = Color(0.55, 0.85, 1.0, 1.0)

# --- Hit flash ---
@export var hit_flash_color: Color = Color(1.0, 0.25, 0.25, 1.0)
@export var hit_flash_time: float = 0.25

# --- State ---
var health: int = 0
var dead: bool = false
var hurt: bool = false

var frozen: bool = false
var freeze_time_left: float = 0.0

var can_attack: bool = true
var attacking: bool = false
var damage_dealt: bool = false
var attack_count: int = 0
var attack_target: Node2D = null

# Change whenever an attack / hurt is interrupted
var attack_id: int = 0
var hurt_id: int = 0

var base_modulate: Color = Color.WHITE
var flash_tween: Tween

# --- Nodes ---
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D


# =========================================================
# READY
# =========================================================

func _ready() -> void:
	add_to_group("enemies")

	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING

	health = max_health
	base_modulate = animated_sprite.modulate

	collision_shape.set_deferred("disabled", false)

	for anim_name in ["attack1", "attack2", "hurt", "death"]:
		if animated_sprite.sprite_frames.has_animation(anim_name):
			animated_sprite.sprite_frames.set_animation_loop(
				anim_name, false
			)

	animated_sprite.visible = true
	animated_sprite.play("idle")

	print("ORC READY | HP: ", health)
	print("ANIMATIONS: ", animated_sprite.sprite_frames.get_animation_names())


# =========================================================
# COLOUR
# =========================================================

func _rest_color() -> Color:
	return freeze_tint if frozen else base_modulate


func _refresh_color() -> void:
	if flash_tween and flash_tween.is_running():
		return

	animated_sprite.modulate = _rest_color()


func flash_red() -> void:
	if flash_tween:
		flash_tween.kill()

	animated_sprite.modulate = hit_flash_color

	flash_tween = create_tween()
	flash_tween.tween_method(
		_set_flash_blend,
		0.0,
		1.0,
		hit_flash_time
	)


func _set_flash_blend(amount: float) -> void:
	animated_sprite.modulate = hit_flash_color.lerp(
		_rest_color(), amount
	)


func _reset_color() -> void:
	if flash_tween:
		flash_tween.kill()

	animated_sprite.modulate = base_modulate


# =========================================================
# PHYSICS: CHASE + ATTACK
# =========================================================

func _physics_process(delta: float) -> void:
	update_freeze(delta)

	velocity = Vector2.ZERO

	if dead or frozen or attacking or hurt:
		return

	var target: Node2D = find_nearest_player()

	if target == null:
		play_if_not("idle")
		return

	var distance: float = global_position.distance_to(
		target.global_position
	)

	# Face the current target.
	animated_sprite.flip_h = (
		target.global_position.x < global_position.x
	)

	if distance > attack_range:
		velocity = global_position.direction_to(
			target.global_position
		) * move_speed

		move_and_slide()
		play_if_not("walk")
	else:
		play_if_not("idle")

		if can_attack:
			start_attack(target)


func play_if_not(anim_name: String) -> void:
	if (
		animated_sprite.animation != anim_name
		or not animated_sprite.is_playing()
	):
		animated_sprite.play(anim_name)


# =========================================================
# TARGETING: PLAYERS + SUMMONS
# =========================================================

func find_nearest_player() -> Node2D:
	var nearest_target: Node2D = null
	var nearest_distance: float = INF

	var candidates: Array = []
	candidates.append_array(
		get_tree().get_nodes_in_group("players")
	)
	candidates.append_array(
		get_tree().get_nodes_in_group("summons")
	)

	for candidate in candidates:
		if not is_instance_valid(candidate):
			continue

		if not candidate is Node2D:
			continue

		if candidate.is_queued_for_deletion():
			continue

		if not candidate.has_method("take_damage"):
			continue

		# Player death state.
		var is_dead = candidate.get("dead")

		if is_dead != null and is_dead:
			continue

		# Paladin dismissal/death state.
		var is_disappearing = candidate.get("disappearing")

		if is_disappearing != null and is_disappearing:
			continue

		# Ignore targets with no health remaining.
		var target_health = candidate.get("health")

		if target_health != null and target_health <= 0:
			continue

		var distance: float = global_position.distance_to(
			candidate.global_position
		)

		if distance < nearest_distance:
			nearest_distance = distance
			nearest_target = candidate

	return nearest_target


# =========================================================
# FREEZE
# =========================================================

func update_freeze(delta: float) -> void:
	if not frozen:
		return

	freeze_time_left -= delta

	if freeze_time_left <= 0.0:
		unfreeze()


func apply_freeze(duration: float) -> void:
	if dead or duration <= 0.0:
		return

	freeze_time_left = maxf(freeze_time_left, duration)

	if frozen:
		return

	frozen = true

	attack_id += 1
	hurt_id += 1

	hurt = false
	attacking = false
	can_attack = false
	damage_dealt = false
	attack_target = null
	velocity = Vector2.ZERO

	animated_sprite.stop()
	animated_sprite.animation = "idle"
	animated_sprite.frame = 0

	_refresh_color()

	print("ORC FROZEN | TIME: ", duration)


func unfreeze() -> void:
	if not frozen:
		return

	frozen = false
	freeze_time_left = 0.0

	hurt = false
	attacking = false
	can_attack = true
	damage_dealt = false
	attack_target = null
	velocity = Vector2.ZERO

	_refresh_color()
	animated_sprite.play("idle")

	print("ORC UNFROZEN")


# =========================================================
# STAGGER
# =========================================================

func stagger() -> void:
	if dead or frozen:
		return

	if attacking:
		attack_id += 1
		attacking = false
		can_attack = true
		damage_dealt = false
		attack_target = null

	hurt = true
	hurt_id += 1

	var my_hurt: int = hurt_id

	velocity = Vector2.ZERO

	animated_sprite.stop()
	animated_sprite.animation = "hurt"
	animated_sprite.frame = 0
	animated_sprite.play()

	print("ORC STAGGERED")

	await animated_sprite.animation_finished

	if dead or my_hurt != hurt_id:
		return

	hurt = false
	animated_sprite.play("idle")


# =========================================================
# ATTACK
# =========================================================

func start_attack(target: Node2D) -> void:
	if dead or frozen or attacking or not can_attack:
		return

	if not is_instance_valid(target):
		return

	attack_id += 1
	var my_id: int = attack_id

	attack_target = target

	attacking = true
	can_attack = false
	damage_dealt = false
	velocity = Vector2.ZERO

	attack_count += 1

	var heavy: bool = (
		attack_count % maxi(heavy_attack_every, 1) == 0
	)

	var anim_name: String = "attack2" if heavy else "attack1"
	var damage: int = attack2_damage if heavy else attack_damage
	var hit_frame: int = (
		attack2_hit_frame if heavy else attack1_hit_frame
	)

	animated_sprite.flip_h = (
		target.global_position.x < global_position.x
	)

	animated_sprite.stop()
	animated_sprite.animation = anim_name
	animated_sprite.frame = 0
	animated_sprite.play()

	print(
		"ORC %s | ATTACK #%d | TARGET: %s | DAMAGE: %d"
		% [anim_name.to_upper(), attack_count, target.name, damage]
	)

	await wait_for_attack_frame(hit_frame, my_id)

	if dead or my_id != attack_id:
		return

	if not damage_dealt:
		deal_attack_damage(damage)

	await animated_sprite.animation_finished

	if dead or my_id != attack_id:
		return

	attacking = false
	damage_dealt = false
	attack_target = null

	animated_sprite.play("idle")

	await get_tree().create_timer(attack_cooldown).timeout

	if dead or my_id != attack_id:
		return

	can_attack = true


func wait_for_attack_frame(target_frame: int, id: int) -> void:
	var last_frame: int = (
		animated_sprite.sprite_frames.get_frame_count(
			animated_sprite.animation
		) - 1
	)

	target_frame = clampi(target_frame, 0, maxi(last_frame, 0))

	while animated_sprite.frame < target_frame:
		await get_tree().process_frame

		if dead or id != attack_id:
			return


func deal_attack_damage(damage: int) -> void:
	if dead or frozen or damage_dealt:
		return

	damage_dealt = true

	var target: Node2D = attack_target

	if not is_instance_valid(target):
		return

	if target.is_queued_for_deletion():
		return

	var is_dead = target.get("dead")
	var is_disappearing = target.get("disappearing")

	if is_dead != null and is_dead:
		return

	if is_disappearing != null and is_disappearing:
		return

	var target_health = target.get("health")

	if target_health != null and target_health <= 0:
		return

	if global_position.distance_to(
		target.global_position
	) > attack_range:
		print("ORC ATTACK MISSED: OUT OF RANGE")
		return

	if target.has_method("take_damage"):
		print(
			"ORC HIT: %s | DAMAGE: %d"
			% [target.name, damage]
		)

		target.call("take_damage", damage)


# =========================================================
# TAKE DAMAGE
# =========================================================

func take_damage(damage: int) -> void:
	if dead or damage <= 0:
		return

	health = maxi(health - damage, 0)

	print(
		"ORC TOOK DAMAGE: %d | HP: %d"
		% [damage, health]
	)

	if health <= 0:
		die()
		flash_red()
		return

	flash_red()

	if attacking or frozen:
		return

	hurt = true
	hurt_id += 1

	var my_hurt: int = hurt_id

	animated_sprite.stop()
	animated_sprite.animation = "hurt"
	animated_sprite.frame = 0
	animated_sprite.play()

	await animated_sprite.animation_finished

	if dead or my_hurt != hurt_id:
		return

	hurt = false
	animated_sprite.play("idle")


# =========================================================
# DEATH / RESPAWN
# =========================================================

func die() -> void:
	if dead:
		return

	dead = true

	attack_id += 1
	hurt_id += 1

	hurt = false
	frozen = false
	freeze_time_left = 0.0
	attacking = false
	can_attack = false
	damage_dealt = false
	attack_target = null
	velocity = Vector2.ZERO

	_reset_color()

	collision_shape.set_deferred("disabled", true)

	animated_sprite.stop()
	animated_sprite.animation = "death"
	animated_sprite.frame = 0
	animated_sprite.play()

	print("ORC DIED")

	await animated_sprite.animation_finished

	if not is_inside_tree():
		return

	animated_sprite.visible = false

	await get_tree().create_timer(respawn_time).timeout

	if not is_inside_tree():
		return

	respawn()


func respawn() -> void:
	health = max_health

	attack_id += 1
	hurt_id += 1

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

	_reset_color()

	collision_shape.set_deferred("disabled", false)

	animated_sprite.visible = true
	animated_sprite.play("idle")

	print("ORC RESPAWNED | HP: ", health)
