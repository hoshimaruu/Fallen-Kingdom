class_name Boss
extends Enemy

# Shared helpers for boss enemies (the Bishop uses this; the General has its
# own copy of the same helpers and does not need it).
# Bosses never stagger by default and use their own cooldown timers.

# true = players can never stagger him.
@export var is_boss: bool = true
# true = the mage's ice cannot lock him.
@export var freeze_immune: bool = false
# Scales every hit this boss deals: 0.5 = half damage, 1.5 = 50% more.
@export_range(0.1, 3.0) var damage_multiplier: float = 1.0
# Extra pixels added around a target so thin hits are not missed.
@export var target_hit_slack: float = 16.0
# Death with no death animation: a copy of his last frame fades out.
@export var death_fade_time: float = 1.0

# Gap between actions (slash and fire), counted down by the boss.
var attack_cd_left: float = 0.0


# =========================================================
# HOOKS
# =========================================================

func _on_ready() -> void:
	if is_boss:
		stagger_immune = true


# Runs when the boss is frozen or otherwise interrupted from outside.
func _on_interrupted() -> void:
	pass


func _on_death() -> void:
	animated_sprite.speed_scale = 1.0

	if not _has_animation(death_animation):
		_spawn_ghost(Color(1.0, 0.4, 0.4, 0.9), death_fade_time)


func apply_freeze(duration: float) -> void:
	if freeze_immune:
		return

	super.apply_freeze(duration)
	animated_sprite.speed_scale = 1.0
	_on_interrupted()


# =========================================================
# ACTIONS
# =========================================================

func _begin_action(target) -> int:
	attack_id += 1
	attacking = true
	damage_dealt = false
	velocity = Vector2.ZERO
	attack_target = target

	if is_instance_valid(target):
		_face(target.global_position.x)

	return attack_id


func _aborted(id: int) -> bool:
	return dead or frozen or id != attack_id


# cooldown < 0 leaves the attack timer alone.
func _end_action(id: int, cooldown: float = -1.0) -> void:
	if id != attack_id:
		return

	attacking = false
	attack_target = null

	if cooldown >= 0.0:
		attack_cd_left = cooldown

	_play_if_not(idle_animation)


# Starts an animation. Returns false if it does not exist, so callers can fall
# back to timers instead of waiting for a signal that never comes.
func _start_anim(anim_name: StringName) -> bool:
	if not _has_animation(anim_name):
		return false

	_restart_animation(anim_name)
	return true


func _wait_hit_frame(frame: int, id: int, has_anim: bool) -> void:
	if has_anim:
		await _wait_for_attack_frame(frame, id)
	else:
		await get_tree().create_timer(0.2).timeout


func _wait_anim_end(has_anim: bool) -> void:
	if not has_anim:
		await get_tree().create_timer(0.3).timeout
	elif animated_sprite.is_playing():
		await animated_sprite.animation_finished


func _facing_x() -> float:
	var looking_left: bool = animated_sprite.flip_h if sprite_faces_right else not animated_sprite.flip_h
	return -1.0 if looking_left else 1.0


# =========================================================
# DAMAGE
# =========================================================

func _all_targets() -> Array:
	var result: Array = []

	for group_name in target_groups:
		for candidate in get_tree().get_nodes_in_group(group_name):
			if _is_valid_target(candidate) and not result.has(candidate):
				result.append(candidate)

	return result


func _hurt(target, amount: int, do_stagger: bool = false) -> void:
	if amount <= 0 or not _is_valid_target(target):
		return

	amount = maxi(1, roundi(float(amount) * damage_multiplier))

	_log("HIT: %s | DAMAGE: %d" % [target.name, amount])

	# Players take (damage, do_stagger). Summons only take damage.
	if target.is_in_group("players"):
		target.call("take_damage", amount, do_stagger)
	else:
		target.call("take_damage", amount)


# Everything within `radius` of a world position. Returns the targets it hit.
func _hit_circle(center: Vector2, radius: float, amount: int, do_stagger: bool = false) -> Array:
	var hit: Array = []

	for candidate in _all_targets():
		if center.distance_to(candidate.global_position) <= radius + target_hit_slack:
			hit.append(candidate)
			_hurt(candidate, amount, do_stagger)

	return hit


# =========================================================
# VISUALS
# =========================================================

# A fading copy of the current frame (also used for the death fade).
func _spawn_ghost(tint: Color, fade_time: float) -> void:
	var parent_node: Node = get_parent()

	if parent_node == null or not _has_animation(animated_sprite.animation):
		return

	var texture: Texture2D = animated_sprite.sprite_frames.get_frame_texture(
		animated_sprite.animation, animated_sprite.frame
	)

	if texture == null:
		return

	var ghost := Sprite2D.new()
	ghost.texture = texture
	ghost.centered = animated_sprite.centered
	ghost.offset = animated_sprite.offset
	ghost.flip_h = animated_sprite.flip_h
	ghost.modulate = tint
	ghost.z_index = -1

	parent_node.add_child(ghost)
	ghost.global_position = animated_sprite.global_position
	ghost.global_scale = animated_sprite.global_scale

	var fade: Tween = ghost.create_tween()
	fade.tween_property(ghost, "modulate:a", 0.0, maxf(fade_time, 0.05))
	fade.tween_callback(ghost.queue_free)


# Plays an animation from the boss's own SpriteFrames as a separate effect at a
# world position (used for effect animations that live in the boss's frames).
func _spawn_effect(
	anim_name: StringName,
	world_pos: Vector2,
	keep_looping: bool = false
) -> AnimatedSprite2D:
	var parent_node: Node = get_parent()

	if parent_node == null or not _has_animation(anim_name):
		return null

	var fx := AnimatedSprite2D.new()
	fx.sprite_frames = animated_sprite.sprite_frames
	fx.animation = anim_name
	fx.z_index = animated_sprite.z_index

	parent_node.add_child(fx)
	fx.global_position = world_pos
	fx.global_scale = animated_sprite.global_scale
	fx.play(anim_name)

	if not keep_looping:
		fx.animation_finished.connect(fx.queue_free)

	return fx
