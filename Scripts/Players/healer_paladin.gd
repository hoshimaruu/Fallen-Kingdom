extends Node2D

# Root node of the Paladin scene: Node2D, with an AnimatedSprite2D child.
# The Healer sets damage, lifetime and summoner before adding it to the scene.

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

# Attacks are used in order: thrust -> slash -> double slash.
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
var attack_target: Node2D

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
# READY / PROCESS
# =========================================================

func _ready() -> void:
	add_to_group("summons")

	health = max_health
	remaining_lifetime = lifetime

	if animated_sprite.sprite_frames == null:
		push_error("[PALADIN] No SpriteFrames assigned.")
		queue_free()
		return

	for anim_name in [idle_animation, move_animation]:
		_set_loop(anim_name, true)

	for anim_name in [
		attack1_animation,
		attack2_animation,
		attack3_animation,
		hurt_animation,
		death_animation
	]:
		_set_loop(anim_name, false)

	_play_if_available(idle_animation)

	print(
		"[PALADIN] Summoned | HP: ", health,
		" | Damage: ", damage,
		" | Lifetime: ", lifetime
	)


func _process(delta: float) -> void:
	if disappearing:
		return

	remaining_lifetime -= delta

	if remaining_lifetime <= 0.0:
		dismiss()
		return

	attack_cooldown = maxf(attack_cooldown - delta, 0.0)

	if attacking or hurt:
		return

	retarget_timer -= delta

	if retarget_timer <= 0.0 or not _valid_target(target):
		target = _find_target()
		retarget_timer = retarget_time

	if not _valid_target(target):
		_follow_summoner(delta)
		return

	var offset: Vector2 = target.global_position - global_position
	_face(offset.x)

	if offset.length() > attack_range:
		_move_toward(target.global_position, delta)
	elif attack_cooldown <= 0.0:
		_start_attack(target)
	else:
		_play_if_available(idle_animation)


# =========================================================
# TARGETING
# =========================================================

# Untyped on purpose: a freed enemy cannot be passed to a typed parameter.
func _valid_target(candidate) -> bool:
	if not is_instance_valid(candidate) or not candidate is Node2D:
		return false

	if candidate.is_queued_for_deletion():
		return false

	return candidate.get("dead") != true


func _find_target() -> Node2D:
	var nearest: Node2D = null
	var nearest_distance: float = detect_range

	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not _valid_target(enemy):
			continue

		var distance: float = global_position.distance_to(enemy.global_position)

		if distance < nearest_distance:
			nearest_distance = distance
			nearest = enemy

	return nearest


# =========================================================
# MOVEMENT
# =========================================================

func _face(x: float) -> void:
	if absf(x) > 1.0:
		animated_sprite.flip_h = x < 0.0


func _move_toward(destination: Vector2, delta: float) -> void:
	_face(destination.x - global_position.x)
	global_position = global_position.move_toward(destination, move_speed * delta)
	_play_if_available(move_animation)


func _follow_summoner(delta: float) -> void:
	if (
		is_instance_valid(summoner)
		and global_position.distance_to(summoner.global_position) > follow_distance
	):
		_move_toward(summoner.global_position, delta)
	else:
		_play_if_available(idle_animation)


# =========================================================
# ATTACKS
# =========================================================

# Next available attack animation in the combo (skips missing ones).
func _next_attack_animation() -> StringName:
	var combo: Array[StringName] = [
		attack1_animation,
		attack2_animation,
		attack3_animation
	]

	for i in combo.size():
		var index: int = (attack_number + i) % combo.size()

		if _has_animation(combo[index]):
			attack_number = (index + 1) % combo.size()
			return combo[index]

	return &""


func _action_valid(token: int) -> bool:
	return (
		is_inside_tree()
		and not disappearing
		and not hurt
		and token == action_token
	)


func _start_attack(victim: Node2D) -> void:
	if attacking or hurt or disappearing:
		return

	var attack_animation: StringName = _next_attack_animation()

	if attack_animation == &"":
		push_warning("[PALADIN] No attack animations are assigned.")
		return

	attacking = true
	attack_cooldown = attack_interval
	attack_target = victim

	action_token += 1
	var this_token: int = action_token

	_restart_animation(attack_animation)

	var frame_count: int = animated_sprite.sprite_frames.get_frame_count(attack_animation)
	var hit_frame: int = clampi(attack_hit_frame, 0, frame_count - 1)

	while animated_sprite.frame < hit_frame:
		await get_tree().process_frame

		if not _action_valid(this_token) or animated_sprite.animation != attack_animation:
			return

	_apply_attack_damage()

	if animated_sprite.animation == attack_animation and animated_sprite.is_playing():
		await animated_sprite.animation_finished

	if not _action_valid(this_token):
		return

	attacking = false
	_play_if_available(idle_animation)


func _apply_attack_damage() -> void:
	# Hits the enemy the attack started on, even if the nearest one changed.
	if not _valid_target(attack_target):
		return

	if global_position.distance_to(attack_target.global_position) > attack_range * 1.5:
		return

	if attack_target.has_method("take_damage"):
		attack_target.call("take_damage", damage)
		print("[PALADIN] Hit ", attack_target.name, " for ", damage, " damage.")


# =========================================================
# DAMAGE / HURT
# =========================================================

func take_damage(amount: int) -> void:
	if disappearing or amount <= 0:
		return

	health = maxi(health - amount, 0)

	print("[PALADIN] Took ", amount, " damage | HP: ", health, "/", max_health)

	if health <= 0:
		die()
		return

	# Interrupt the current action and play hurt.
	action_token += 1
	attacking = false

	if not _has_animation(hurt_animation):
		return

	hurt = true
	var this_token: int = action_token

	_restart_animation(hurt_animation)

	await animated_sprite.animation_finished

	# A newer hit or the end of the Paladin took over.
	if not is_inside_tree() or disappearing or this_token != action_token:
		return

	hurt = false
	_play_if_available(idle_animation)


# =========================================================
# DEATH / DISMISS
# =========================================================

func die() -> void:
	_remove_paladin("DEFEATED")


func dismiss() -> void:
	_remove_paladin("DISMISSED")


func _remove_paladin(reason: String) -> void:
	if disappearing:
		return

	print("[PALADIN] ", reason)

	disappearing = true
	attacking = false
	hurt = false
	action_token += 1

	if _has_animation(death_animation):
		_restart_animation(death_animation)
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


func _set_loop(anim_name: StringName, should_loop: bool) -> void:
	if _has_animation(anim_name):
		animated_sprite.sprite_frames.set_animation_loop(anim_name, should_loop)


func _restart_animation(anim_name: StringName) -> void:
	animated_sprite.stop()
	animated_sprite.animation = anim_name
	animated_sprite.frame = 0
	animated_sprite.play()


func _play_if_available(anim_name: StringName) -> void:
	if not _has_animation(anim_name):
		return

	if animated_sprite.animation != anim_name or not animated_sprite.is_playing():
		animated_sprite.play(anim_name)
