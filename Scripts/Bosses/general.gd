class_name General
extends Enemy

# Boss 1: The General.
# Attach to a CharacterBody2D that has an AnimatedSprite2D and a CollisionShape2D
# (same node names the Enemy base class needs).
#
# Animations used (names can be changed in the Inspector):
#   idle, walk       movement
#   attack1          normal slash, close range
#   attack2          the thrust = LANCE CHARGE (his basic attack)
#   attack3          shield bash on the ground = casts SPIKE SHIELD (ultimate)
#   hurt             only used if stagger_immune is turned off
#
# Moveset
#   Lance Charge  : lunges forward and thrusts the lance in a line.
#   Lance Dash    : fast dash. Closes distance, or evades after an attack.
#   Spike Shield  : below half health. Bash on the ground, then a spiked shield
#                   hurts anything touching him for 20 s while he does up to
#                   10 Lance Dashes. Cooldown 60 s, counted from the cast.
#
# Suggested Inspector values (Enemy section): max_health 600, move_speed 130,
# attack_damage 12 (slash), attack2_damage 20 (lance). Cooldowns are set below
# (slash_cooldown, lance_cooldown, dash_cooldown); attack_cooldown is not used.
# Set attack1_hit_frame / attack2_hit_frame / attack3_hit_frame to the frame
# where the weapon actually swings in each animation.

signal ultimate_cast
signal shield_ended

# --- Boss flags ---
@export var is_boss: bool = true            # true = never staggered
@export var freeze_immune: bool = false     # true = the mage's ice cannot lock him

# --- Slash (attack1) ---
@export var slash_range: float = 70.0
@export var slash_behind: float = 10.0
@export var slash_cooldown: float = 2.0

# --- Lance Charge (attack2) ---
@export var lance_trigger_range: float = 160.0   # starts the charge from this far
@export var lance_lunge_distance: float = 80.0
@export var lance_lunge_speed: float = 380.0
@export var lance_length: float = 110.0
@export var lance_half_width: float = 28.0
@export var lance_cooldown: float = 3.5

# --- Lance Dash (skill) ---
@export var dash_distance: float = 220.0
@export var dash_speed: float = 520.0
@export var dash_cooldown: float = 7.0
@export var dash_trigger_distance: float = 200.0   # dashes at targets farther than this
@export var dash_stop_distance: float = 55.0       # stops this close to the target
@export var dash_hit_reach: float = 55.0
@export var dash_hit_half_width: float = 35.0
@export var dash_damage: int = 0                   # normal dashes do no damage
@export var dash_animation_speed: float = 2.0
@export_range(0.0, 1.0) var evade_chance: float = 0.3

# --- Spike Shield (ultimate) ---
@export var ultimate_health_ratio: float = 0.5
@export var ultimate_cooldown: float = 60.0   # counted from the cast
@export var attack3_animation: StringName = &"attack3"
@export var attack3_hit_frame: int = 4
@export var bash_radius: float = 110.0
@export var bash_damage: int = 15
@export var shield_duration: float = 20.0
@export var shield_radius: float = 75.0
@export var shield_damage: int = 8
@export var shield_tick_time: float = 0.6          # seconds between hits on the same target
@export var shield_center_offset: Vector2 = Vector2.ZERO
@export var shield_color: Color = Color(0.85, 0.9, 1.0, 0.9)
@export var ultimate_dashes: int = 10
@export var ultimate_dash_damage: int = 12
# How far and how fast each ultimate dash is. Each dash lasts about
# distance / speed seconds (300 / 620 = roughly 0.5 s). Lower the speed or raise
# the distance to make every dash last longer.
@export var ultimate_dash_max_distance: float = 300.0
@export var ultimate_dash_speed: float = 620.0
# Pause between each dash of the ultimate (seconds). Bigger = easier to dodge.
@export var ultimate_dash_pause: float = 0.6

# --- Hit detection ---
# Extra pixels added around a target so thin hits are not missed.
@export var target_hit_slack: float = 16.0

# --- Death with no death animation ---
@export var death_fade_time: float = 1.0

# --- State ---
var attack_cd_left: float = 0.0
var dash_cd_left: float = 0.0
var ultimate_cd_left: float = 0.0

var dash_time_left: float = 0.0
var dash_dir: Vector2 = Vector2.RIGHT
var dash_speed_now: float = 0.0

var shield_active: bool = false
var shield_time_left: float = 0.0
var shield_fx = null   # untyped: it may be freed
var shield_hit_cooldowns: Dictionary = {}   # instance id -> seconds left


# =========================================================
# SPIKE SHIELD VISUAL (drawn in code, no extra scene needed)
# =========================================================

class SpikeShieldFX extends Node2D:
	var radius: float = 75.0
	var spike_count: int = 12
	var spin_speed: float = 2.2
	var color: Color = Color(0.85, 0.9, 1.0, 0.9)

	func _process(delta: float) -> void:
		rotation += spin_speed * delta

	func _draw() -> void:
		draw_circle(Vector2.ZERO, radius, Color(color.r, color.g, color.b, 0.12))
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, color, 3.0)

		for i in spike_count:
			var angle: float = TAU * float(i) / float(spike_count)
			var dir := Vector2.from_angle(angle)
			var side := Vector2.from_angle(angle + PI * 0.5)
			var base: Vector2 = dir * radius
			var points := PackedVector2Array([
				base + side * 7.0,
				dir * (radius + 18.0),
				base - side * 7.0,
			])
			draw_colored_polygon(points, color)


# =========================================================
# HOOKS
# =========================================================

func _on_ready() -> void:
	if _has_animation(attack3_animation):
		animated_sprite.sprite_frames.set_animation_loop(attack3_animation, false)

	if is_boss:
		stagger_immune = true


func _on_death() -> void:
	_end_shield()
	dash_time_left = 0.0
	animated_sprite.speed_scale = 1.0

	# No death animation: leave a fading copy of the last frame behind.
	if not _has_animation(death_animation):
		_spawn_ghost(Color(1.0, 0.4, 0.4, 0.9), death_fade_time)


func apply_freeze(duration: float) -> void:
	if freeze_immune:
		return

	super.apply_freeze(duration)

	dash_time_left = 0.0
	animated_sprite.speed_scale = 1.0


# =========================================================
# MAIN LOOP
# =========================================================

func _physics_process(delta: float) -> void:
	_update_freeze(delta)

	attack_cd_left = maxf(attack_cd_left - delta, 0.0)
	dash_cd_left = maxf(dash_cd_left - delta, 0.0)
	ultimate_cd_left = maxf(ultimate_cd_left - delta, 0.0)

	velocity = Vector2.ZERO

	if dead:
		return

	_update_shield(delta)

	if frozen:
		return

	# Dashes and lunges move the body; the action coroutine handles the rest.
	if dash_time_left > 0.0:
		velocity = dash_dir * dash_speed_now
		move_and_slide()
		dash_time_left -= delta
		return

	if attacking or hurt:
		return

	var target: Node2D = find_nearest_target()

	if target == null:
		_play_if_not(idle_animation)
		return

	_face(target.global_position.x)

	var distance: float = global_position.distance_to(target.global_position)

	# 1) Ultimate, as soon as he is below half health and it is ready.
	if (
		ultimate_cd_left <= 0.0
		and health <= int(max_health * ultimate_health_ratio)
		and _has_animation(attack3_animation)
	):
		_do_ultimate(target)
		return

	# 2) Attacks.
	if attack_cd_left <= 0.0:
		if distance <= slash_range:
			_do_slash(target)
			return

		if distance <= lance_trigger_range:
			_do_lance_charge(target)
			return

	# 3) Lance Dash to close a big gap.
	if dash_cd_left <= 0.0 and distance >= dash_trigger_distance:
		_do_dash_action(global_position.direction_to(target.global_position), target, false)
		return

	# 4) Walk closer.
	if distance > slash_range * 0.8:
		velocity = global_position.direction_to(target.global_position) * move_speed
		move_and_slide()
		_play_if_not(walk_animation if _has_animation(walk_animation) else idle_animation)
	else:
		_play_if_not(idle_animation)


# =========================================================
# ACTION HELPERS
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


func _end_action(id: int, cooldown: float = -1.0) -> void:
	if id != attack_id:
		return

	attacking = false
	attack_target = null

	# Negative = leave the attack timer alone.
	if cooldown >= 0.0:
		attack_cd_left = cooldown

	_play_if_not(idle_animation)


# Starts an animation. Returns false if it does not exist, so callers can
# fall back to timers instead of waiting for a signal that never comes.
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
# DAMAGE HELPERS
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

	_log("HIT: %s | DAMAGE: %d" % [target.name, amount])

	# Players take (damage, do_stagger). Summons only take damage.
	if target.is_in_group("players"):
		target.call("take_damage", amount, do_stagger)
	else:
		target.call("take_damage", amount)


# A line / box in front of him: used by the lance and by dashes.
func _hit_in_box(
	direction: Vector2,
	reach: float,
	half_width: float,
	amount: int,
	hit_ids: Array,
	do_stagger: bool = false
) -> void:
	for target in _all_targets():
		var target_id: int = target.get_instance_id()

		if hit_ids.has(target_id):
			continue

		var offset: Vector2 = target.global_position - global_position
		var forward: float = offset.dot(direction)
		var side: float = absf(offset.x * direction.y - offset.y * direction.x)

		if (
			forward >= -target_hit_slack
			and forward <= reach + target_hit_slack
			and side <= half_width + target_hit_slack
		):
			hit_ids.append(target_id)
			_hurt(target, amount, do_stagger)


# =========================================================
# MOVEMENT: LANCE DASH
# =========================================================

# Moves him along `direction`. Used by the Lance Dash, the evade and the
# lunge of the Lance Charge. Returns when the movement is finished.
func _dash(
	direction: Vector2,
	distance: float,
	speed: float,
	amount: int,
	reach: float,
	half_width: float,
	use_walk_anim: bool,
	stop_near_target: bool,
	id: int
) -> void:
	dash_dir = direction.normalized()
	dash_speed_now = speed
	dash_time_left = distance / maxf(speed, 1.0)

	if absf(dash_dir.x) > 0.05:
		_face(global_position.x + dash_dir.x * 100.0)

	if use_walk_anim and _has_animation(walk_animation):
		animated_sprite.speed_scale = dash_animation_speed
		_play_if_not(walk_animation)

	var hit_ids: Array = []
	var ghost_timer: float = 0.0

	while dash_time_left > 0.0:
		if amount > 0:
			_hit_in_box(dash_dir, reach, half_width, amount, hit_ids)

		if use_walk_anim:
			ghost_timer -= get_physics_process_delta_time()

			if ghost_timer <= 0.0:
				ghost_timer = 0.045
				_spawn_ghost(Color(0.7, 0.8, 1.0, 0.55), 0.3)

		await get_tree().physics_frame

		if _aborted(id):
			break

		if (
			stop_near_target
			and _is_valid_target(attack_target)
			and global_position.distance_to(attack_target.global_position) <= dash_stop_distance
		):
			dash_time_left = 0.0

	dash_time_left = 0.0
	animated_sprite.speed_scale = 1.0


# Afterimage: a fading copy of the current frame.
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


# A Lance Dash used as its own action (gap closer or evade).
func _do_dash_action(direction: Vector2, target, evading: bool) -> void:
	var id: int = _begin_action(target)
	dash_cd_left = dash_cooldown

	await _dash(
		direction, dash_distance, dash_speed,
		dash_damage, dash_hit_reach, dash_hit_half_width,
		true, not evading, id
	)

	if _aborted(id):
		return

	# Attack right after a gap-closing dash; do not restart the attack timer.
	_end_action(id)


func _try_evade(target) -> void:
	if dash_cd_left > 0.0 or not _is_valid_target(target):
		return

	if randf() >= evade_chance:
		return

	var away: Vector2 = target.global_position.direction_to(global_position)
	away = away.rotated(randf_range(-0.6, 0.6))

	_do_dash_action(away, target, true)


# =========================================================
# ATTACK 1: SLASH
# =========================================================

func _do_slash(target) -> void:
	var id: int = _begin_action(target)
	var has_anim: bool = _start_anim(attack1_animation)

	_log("SLASH")

	await _wait_hit_frame(attack1_hit_frame, id, has_anim)

	if _aborted(id):
		return

	var facing: float = _facing_x()

	for candidate in _all_targets():
		var offset: Vector2 = candidate.global_position - global_position

		if offset.length() <= slash_range + target_hit_slack and offset.x * facing >= -slash_behind:
			_hurt(candidate, attack_damage)

	await _wait_anim_end(has_anim)

	if _aborted(id):
		return

	_end_action(id, slash_cooldown)
	_try_evade(target)


# =========================================================
# ATTACK 2: LANCE CHARGE (basic attack)
# =========================================================

func _do_lance_charge(target) -> void:
	var id: int = _begin_action(target)
	var has_anim: bool = _start_anim(attack2_animation)
	var aim: Vector2 = global_position.direction_to(target.global_position)

	_log("LANCE CHARGE")

	await _wait_hit_frame(attack2_hit_frame, id, has_anim)

	if _aborted(id):
		return

	# Lunge forward with the lance out. Everything in the line gets hit once.
	await _dash(
		aim, lance_lunge_distance, lance_lunge_speed,
		attack2_damage, lance_length, lance_half_width,
		false, false, id
	)

	if _aborted(id):
		return

	await _wait_anim_end(has_anim)

	if _aborted(id):
		return

	_end_action(id, lance_cooldown)
	_try_evade(target)


# =========================================================
# ULTIMATE: SPIKE SHIELD
# =========================================================

func _do_ultimate(target) -> void:
	var id: int = _begin_action(target)
	var has_anim: bool = _start_anim(attack3_animation)

	ultimate_cd_left = ultimate_cooldown

	_log("SPIKE SHIELD")
	ultimate_cast.emit()

	await _wait_hit_frame(attack3_hit_frame, id, has_anim)

	if _aborted(id):
		return

	# Shield bash on the ground: shockwave, then the shield comes up.
	for candidate in _all_targets():
		if global_position.distance_to(candidate.global_position) <= bash_radius:
			_hurt(candidate, bash_damage, true)

	_start_shield()

	await _wait_anim_end(has_anim)

	# Up to N Lance Dashes while the shield is up.
	for i in ultimate_dashes:
		if _aborted(id) or not shield_active:
			break

		var next_target: Node2D = find_nearest_target()

		if next_target == null:
			break

		attack_target = next_target

		var to_target: Vector2 = next_target.global_position - global_position
		var length: float = clampf(to_target.length(), 60.0, ultimate_dash_max_distance)

		await _dash(
			to_target.normalized(), length, ultimate_dash_speed,
			ultimate_dash_damage, dash_hit_reach, dash_hit_half_width,
			true, true, id
		)

		if _aborted(id):
			return

		_play_if_not(idle_animation)
		await get_tree().create_timer(ultimate_dash_pause).timeout

	if _aborted(id):
		return

	_end_action(id, lance_cooldown)


func _start_shield() -> void:
	shield_active = true
	shield_time_left = shield_duration
	shield_hit_cooldowns.clear()

	if not is_instance_valid(shield_fx):
		var fx := SpikeShieldFX.new()
		fx.radius = shield_radius
		fx.color = shield_color
		fx.position = shield_center_offset
		fx.z_index = 1
		add_child(fx)
		shield_fx = fx

	shield_fx.modulate.a = 1.0


func _end_shield() -> void:
	if is_instance_valid(shield_fx):
		shield_fx.queue_free()

	shield_fx = null

	if shield_active:
		shield_active = false
		shield_time_left = 0.0
		shield_hit_cooldowns.clear()
		shield_ended.emit()
		_log("SPIKE SHIELD ENDED")


func _update_shield(delta: float) -> void:
	if not shield_active:
		return

	shield_time_left -= delta

	if shield_time_left <= 0.0:
		_end_shield()
		return

	# Blink during the last 3 seconds as a warning.
	if is_instance_valid(shield_fx) and shield_time_left < 3.0:
		shield_fx.modulate.a = 0.55 + 0.45 * sin(shield_time_left * 14.0)

	# Per-target cooldowns, so one touch is one hit and not one hit per frame.
	for key in shield_hit_cooldowns.keys():
		shield_hit_cooldowns[key] -= delta

		if shield_hit_cooldowns[key] <= 0.0:
			shield_hit_cooldowns.erase(key)

	if frozen:
		return

	var center: Vector2 = global_position + shield_center_offset

	for candidate in _all_targets():
		var target_id: int = candidate.get_instance_id()

		if shield_hit_cooldowns.has(target_id):
			continue

		if center.distance_to(candidate.global_position) <= shield_radius + target_hit_slack:
			shield_hit_cooldowns[target_id] = shield_tick_time
			_hurt(candidate, shield_damage)
