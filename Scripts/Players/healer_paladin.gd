
extends Node2D

# =========================================================
# STATS
# =========================================================

@export var max_health: int = 120
@export var damage: int = 18
@export var lifetime: float = 15.0
@export var move_speed: float = 160.0

@export var detect_range: float = 400.0
@export var attack_range: float = 55.0
@export var attack_interval: float = 1.2
@export var attack_hit_frame: int = 3

@export var follow_distance: float = 75.0
@export var retarget_time: float = 0.25

# =========================================================
# ANIMATIONS
# =========================================================

@export var idle_animation: StringName = &"idle"
@export var move_animation: StringName = &"walk"

@export var attack1_animation: StringName = &"attack1"
@export var attack2_animation: StringName = &"attack2"
@export var attack3_animation: StringName = &"attack3"

@export var hurt_animation: StringName = &"hurt"
@export var death_animation: StringName = &"death"

# =========================================================
# STATE
# =========================================================

var health: int = 120
var summoner: Node2D
var target: Node2D

var attacking: bool = false
var hurt: bool = false
var disappearing: bool = false

var attack_cooldown: float = 0.0
var retarget_timer: float = 0.0
var remaining_lifetime: float = 0.0

var attack_number: int = 0
var action_token: int = 0

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D


# =========================================================
# READY
# =========================================================

func _ready() -> void:
	add_to_group("summons")

	health = max_health
	remaining_lifetime = lifetime

	if animated_sprite.sprite_frames == null:
		push_error("[PALADIN] No SpriteFrames assigned.")
		queue_free()
		return

	_set_loop(idle_animation, true)
	_set_loop(move_animation, true)

	_set_loop(attack1_animation, false)
	_set_loop(attack2_animation, false)
	_set_loop(attack3_animation, false)
	_set_loop(hurt_animation, false)
	_set_loop(death_animation, false)

	_play_if_available(idle_animation)

	print(
		"[PALADIN] Summoned | HP: ", health,
		" | Damage: ", damage,
		" | Lifetime: ", lifetime
	)


# =========================================================
# PROCESS
# =========================================================

func _process(delta: float) -> void:
	if disappearing:
		return

	remaining_lifetime -= delta
	attack_cooldown = maxf(attack_cooldown - delta, 0.0)
	retarget_timer -= delta

	if remaining_lifetime <= 0.0:
		dismiss()
		return

	if retarget_timer <= 0.0:
		target = _find_target()
		retarget_timer = retarget_time

	if attacking or hurt:
		return

	if _valid_target(target):
		var distance: float = global_position.distance_to(
			target.global_position
		)

		if distance <= attack_range:
			if attack_cooldown <= 0.0:
				_start_attack()
			else:
				_play_if_available(idle_animation)
			return

		_move_toward(target.global_position)
		return

	_follow_summoner()


# =========================================================
# TARGETING
# =========================================================

func _find_target() -> Node2D:
	var nearest: Node2D = null
	var nearest_distance: float = detect_range

	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not enemy is Node2D:
			continue

		var enemy_node := enemy as Node2D

		if not _valid_target(enemy_node):
			continue

		var distance: float = global_position.distance_to(
			enemy_node.global_position
		)

		if distance < nearest_distance:
			nearest_distance = distance
			nearest = enemy_node

	return nearest


func _valid_target(candidate: Node2D) -> bool:
	if not is_instance_valid(candidate):
		return false

	if candidate.is_queued_for_deletion():
		return false

	if candidate.get("dead") == true:
		return false

	return true


# =========================================================
# MOVEMENT
# =========================================================

func _move_toward(destination: Vector2) -> void:
	var offset: Vector2 = destination - global_position

	if offset.length() > 2.0:
		global_position += (
			offset.normalized()
			* move_speed
			* get_process_delta_time()
		)

		if offset.x != 0.0:
			animated_sprite.flip_h = offset.x < 0.0

		_play_if_available(move_animation)


func _follow_summoner() -> void:
	if not is_instance_valid(summoner):
		_play_if_available(idle_animation)
		return

	var distance: float = global_position.distance_to(
		summoner.global_position
	)

	if distance > follow_distance:
		_move_toward(summoner.global_position)
	else:
		_play_if_available(idle_animation)


# =========================================================
# ATTACKS
# THRUST -> SLASH -> DOUBLE SLASH
# =========================================================

func _start_attack() -> void:
	if attacking or hurt or disappearing:
		return

	attacking = true
	attack_cooldown = attack_interval
	action_token += 1

	var this_token: int = action_token
	var selected_animation: StringName

	match attack_number:
		0:
			selected_animation = attack1_animation
		1:
			selected_animation = attack2_animation
		_:
			selected_animation = attack3_animation

	attack_number = (attack_number + 1) % 3

	# Fall back to another available attack if needed.
	if not _has_animation(selected_animation):
		if _has_animation(attack1_animation):
			selected_animation = attack1_animation
		elif _has_animation(attack2_animation):
			selected_animation = attack2_animation
		elif _has_animation(attack3_animation):
			selected_animation = attack3_animation
		else:
			attacking = false
			push_warning("[PALADIN] No attack animations are assigned.")
			return

	animated_sprite.stop()
	animated_sprite.animation = selected_animation
	animated_sprite.frame = 0
	animated_sprite.play()

	var frame_count: int = animated_sprite.sprite_frames.get_frame_count(
		selected_animation
	)

	var hit_frame: int = clampi(
		attack_hit_frame,
		0,
		frame_count - 1
	)

	while (
		animated_sprite.animation == selected_animation
		and animated_sprite.frame < hit_frame
		and animated_sprite.is_playing()
	):
		await get_tree().process_frame

		if not is_inside_tree() or disappearing:
			return

		if this_token != action_token:
			return

		if hurt:
			return

	_apply_attack_damage()

	if (
		animated_sprite.animation == selected_animation
		and animated_sprite.is_playing()
	):
		await animated_sprite.animation_finished

	if not is_inside_tree() or disappearing:
		return

	if this_token != action_token:
		return

	attacking = false
	_play_if_available(idle_animation)


func _apply_attack_damage() -> void:
	if not _valid_target(target):
		return

	var distance: float = global_position.distance_to(
		target.global_position
	)

	if distance > attack_range * 1.5:
		return

	if target.has_method("take_damage"):
		target.call("take_damage", damage)

		print(
			"[PALADIN] Hit ", target.name,
			" for ", damage, " damage."
		)


# =========================================================
# DAMAGE / HURT
# =========================================================

func take_damage(amount: int) -> void:
	if disappearing or amount <= 0:
		return

	health = maxi(health - amount, 0)

	print(
		"[PALADIN] Took ", amount,
		" damage | HP: ", health, "/", max_health
	)

	if health <= 0:
		die()
		return

	# Interrupt the current action and play hurt.
	action_token += 1
	attacking = false
	hurt = true

	if _has_animation(hurt_animation):
		animated_sprite.stop()
		animated_sprite.animation = hurt_animation
		animated_sprite.frame = 0
		animated_sprite.play()

		await animated_sprite.animation_finished

	if not is_inside_tree() or disappearing:
		return

	hurt = false
	_play_if_available(idle_animation)


# =========================================================
# DEATH / DISMISS
# =========================================================

func die() -> void:
	if disappearing:
		return

	print("[PALADIN] DEFEATED")
	_remove_paladin()


func dismiss() -> void:
	if disappearing:
		return

	print("[PALADIN] DISMISSED")
	_remove_paladin()


func _remove_paladin() -> void:
	disappearing = true
	attacking = false
	hurt = false
	action_token += 1

	if _has_animation(death_animation):
		animated_sprite.stop()
		animated_sprite.animation = death_animation
		animated_sprite.frame = 0
		animated_sprite.play()

		await animated_sprite.animation_finished

	if is_inside_tree():
		queue_free()


# =========================================================
# ANIMATION HELPERS
# =========================================================

func _has_animation(anim_name: StringName) -> bool:
	return (
		animated_sprite.sprite_frames != null
		and anim_name != &""
		and animated_sprite.sprite_frames.has_animation(anim_name)
	)


func _set_loop(
	anim_name: StringName,
	should_loop: bool
) -> void:
	if _has_animation(anim_name):
		animated_sprite.sprite_frames.set_animation_loop(
			anim_name,
			should_loop
		)


func _play_if_available(anim_name: StringName) -> void:
	if not _has_animation(anim_name):
		return

	if (
		animated_sprite.animation != anim_name
		or not animated_sprite.is_playing()
	):
		animated_sprite.play(anim_name)
