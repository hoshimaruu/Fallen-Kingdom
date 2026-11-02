class_name Bishop
extends Boss

# Boss 2: The Bishop (necromancer look).
# Attach to a CharacterBody2D with an AnimatedSprite2D and a CollisionShape2D.
#
# Animations (all inside the one AnimatedSprite2D / SpriteFrames):
#   idle, walk, hurt, death
#   attack1         normal slash, close range
#   attack2         casting pose of the green fire
#   attack2_effect  the green fire falling and exploding (shown where it lands)
#   summon          casting pose of the chant and of the ultimate
#   summon_effect   the circle on the ground while he chants
#
# Moveset
#   Slash            attack1 when a player is close.
#   Green Fire       attack2: fire lands on a player's position and explodes
#                    after a delay (dodge it). Damage + poison.
#   Skeleton Chant   chants 3 s, then 4 skeletons appear in a + or x shape
#                    around him (alternating). Skeletons that touch a player
#                    immobilize him.
#   Dance of the Shadow  below half health: 5 sets of big shadow orbs spin
#                    around him like a vortex (+ and x sets), then all launch
#                    outward together. Damage + poison. Cooldown 60 s.
#
# Suggested Inspector values (Enemy section): max_health 700, move_speed 60,
# attack_damage 12 (slash), attack2_damage 22 (fire).
# attack1_hit_frame = frame the slash lands, attack2_hit_frame = frame of the
# cast animation where the fire appears.

signal ultimate_cast
signal skeletons_summoned(count: int)

# --- Quick balance knobs ---
# Scale everything at once: 0.5 = half damage, 1.5 = 50% more.
@export_range(0.1, 3.0) var cooldown_multiplier: float = 1.0   # above 1 = slower attacks
# (damage_multiplier is in the Boss section of the Inspector.)

# --- Behaviour ---
@export var slash_range: float = 70.0
@export var slash_behind: float = 10.0
@export var slash_cooldown: float = 3.0
# He walks closer until this far, and backs away when a player is nearer
# than keep_distance (but not while his slash is ready and the player is in range).
@export var cast_range: float = 300.0
@export var keep_distance: float = 110.0
@export_range(0.1, 1.0) var retreat_speed_multiplier: float = 0.7

# --- Green Fire (attack2) ---
@export var fire_effect_animation: StringName = &"attack2_effect"
@export var fire_effect_hit_frame: int = 6       # frame of the effect where it explodes
@export var fire_effect_offset: Vector2 = Vector2.ZERO
@export var fire_radius: float = 60.0
@export var fire_cooldown: float = 8.0
@export var fire_poison_damage: int = 2
@export var fire_poison_interval: float = 1.0
@export var fire_poison_duration: float = 4.0

# --- Skeleton Chant (summon) ---
@export var summon_animation: StringName = &"summon"
@export var summon_effect_animation: StringName = &"summon_effect"
# Offset of the circle under the Bishop himself (pixels).
@export var summon_effect_offset: Vector2 = Vector2.ZERO
# Show the circle on every spot where a skeleton will appear (4 at once, in the
# same + or x shape as the skeletons).
@export var summon_effect_at_spawn_points: bool = true
# Also keep one circle under the Bishop while chanting.
@export var summon_effect_at_caster: bool = false
# Nudge the 4 circles (pixels), for example to line them up with the ground.
@export var summon_effect_spawn_offset: Vector2 = Vector2.ZERO
# Drag your skeleton scene in here.
@export var skeleton_scene: PackedScene
@export var chant_time: float = 3.0
@export var chant_cooldown: float = 28.0
@export var skeletons_per_cast: int = 4
@export var max_skeletons: int = 4
@export var skeleton_spawn_radius: float = 90.0
@export var immobilize_time: float = 1.2
@export var skeleton_contact_radius: float = 45.0
# The summoned skeletons fall apart when the Bishop dies.
@export var skeletons_die_with_bishop: bool = true
# Seconds before the same player can be immobilized again.
@export var immobilize_recheck_time: float = 8.0

# --- Dance of the Shadow (ultimate) ---
@export var ultimate_health_ratio: float = 0.5
@export var ultimate_cooldown: float = 60.0
@export var orb_sets: int = 5
@export var orbs_per_set: int = 4
@export var orb_start_radius: float = 70.0
@export var orb_radius_step: float = 32.0
@export var orb_size: float = 18.0
@export var orb_spin_speed: float = 2.4          # radians per second
@export var orb_set_delay: float = 0.35          # time between sets appearing
@export var orb_spin_time: float = 3.0           # full vortex spins this long before launch
@export var orb_launch_speed: float = 260.0
@export var orb_launch_distance: float = 280.0
@export var orb_damage: int = 10
@export var orb_hit_interval: float = 1.0
@export var orb_poison_damage: int = 2
@export var orb_poison_duration: float = 4.0
@export var orb_center_offset: Vector2 = Vector2.ZERO

# --- State ---
var fire_cd_left: float = 0.0
var chant_cd_left: float = 0.0
var ultimate_cd_left: float = 0.0

var chant_fxs: Array = []            # untyped on purpose: effects get freed
var chant_start_angle: float = 0.0
var vortex = null                    # untyped: may be freed
var chant_skeletons: Array = []      # untyped on purpose: skeletons get freed
var use_plus_pattern: bool = true
var immobilize_cooldowns: Dictionary = {}   # player instance id -> seconds left


# =========================================================
# SHADOW ORB VORTEX (drawn in code, no scene needed)
# =========================================================

class ShadowOrbs extends Node2D:
	signal finished

	var boss = null
	var sets: int = 5
	var orbs_per_set: int = 4
	var radius_start: float = 70.0
	var radius_step: float = 32.0
	var orb_radius: float = 18.0
	var spin_speed: float = 2.4
	var build_delay: float = 0.35
	var spin_time: float = 3.0
	var launch_speed: float = 320.0
	var launch_distance: float = 280.0
	var hit_interval: float = 0.7
	var hit_slack: float = 10.0

	var _time: float = 0.0
	var _spin_angle: float = 0.0
	var _launching: bool = false
	var _launch_offset: float = 0.0
	var _visible_sets: int = 0
	var _hit_cooldowns: Dictionary = {}

	func _physics_process(delta: float) -> void:
		_time += delta

		if not _launching:
			_spin_angle += spin_speed * delta
			_visible_sets = mini(sets, int(_time / build_delay) + 1)

			# Launch only once every set has appeared and spun for spin_time.
			if _time >= build_delay * float(sets - 1) + spin_time:
				_launching = true
		else:
			_launch_offset += launch_speed * delta

			if _launch_offset >= launch_distance:
				finished.emit()
				queue_free()
				return

		for key in _hit_cooldowns.keys():
			_hit_cooldowns[key] -= delta

			if _hit_cooldowns[key] <= 0.0:
				_hit_cooldowns.erase(key)

		_check_hits()
		queue_redraw()

	# Local position of every visible orb. Even sets sit on the + axes, odd
	# sets on the x axes, so the vortex is a mix of both.
	func _orb_positions() -> Array:
		var result: Array = []

		for set_index in _visible_sets:
			var base_angle: float = _spin_angle + (PI * 0.25 if set_index % 2 == 1 else 0.0)
			var ring: float = radius_start + radius_step * float(set_index) + _launch_offset

			for orb_index in orbs_per_set:
				var angle: float = base_angle + TAU * float(orb_index) / float(orbs_per_set)
				result.append(Vector2.from_angle(angle) * ring)

		return result

	func _check_hits() -> void:
		if not is_instance_valid(boss) or boss.get("dead") == true:
			return

		var positions: Array = _orb_positions()

		for target in boss._all_targets():
			var target_id: int = target.get_instance_id()

			if _hit_cooldowns.has(target_id):
				continue

			for local_pos in positions:
				if to_global(local_pos).distance_to(target.global_position) <= orb_radius + hit_slack:
					_hit_cooldowns[target_id] = hit_interval
					boss.vortex_hit(target)
					break

	func _draw() -> void:
		for pos in _orb_positions():
			draw_circle(pos, orb_radius + 7.0, Color(0.3, 1.0, 0.45, 0.22))
			draw_circle(pos, orb_radius, Color(0.12, 0.05, 0.2, 0.95))
			draw_arc(pos, orb_radius, 0.0, TAU, 24, Color(0.4, 1.0, 0.5, 0.9), 2.0)
			draw_circle(pos + Vector2(-5.0, -5.0), orb_radius * 0.28, Color(0.7, 1.0, 0.75, 0.8))


# =========================================================
# HOOKS
# =========================================================

func _on_ready() -> void:
	super._on_ready()

	# The effect animations live in this same SpriteFrames: the circle repeats
	# for as long as he chants, the fire plays once.
	if _has_animation(summon_animation):
		animated_sprite.sprite_frames.set_animation_loop(summon_animation, true)

	if _has_animation(summon_effect_animation):
		animated_sprite.sprite_frames.set_animation_loop(summon_effect_animation, true)

	if _has_animation(fire_effect_animation):
		animated_sprite.sprite_frames.set_animation_loop(fire_effect_animation, false)

	if skeleton_scene == null:
		push_warning("[Bishop] skeleton_scene is empty: Skeleton Chant will summon nothing.")


func _on_interrupted() -> void:
	_free_chant_fx()


func _on_death() -> void:
	super._on_death()
	_free_chant_fx()

	if is_instance_valid(vortex):
		vortex.queue_free()

	vortex = null

	if skeletons_die_with_bishop:
		for skeleton in chant_skeletons:
			if is_instance_valid(skeleton) and skeleton.has_method("die"):
				skeleton.call("die")


func _cd(seconds: float) -> float:
	return seconds * cooldown_multiplier


func _scaled(amount: int) -> int:
	return maxi(1, roundi(float(amount) * damage_multiplier))


# Called by the vortex for every target an orb touches.
func vortex_hit(target) -> void:
	_hurt(target, orb_damage)
	StatusEffects.apply_poison(target, _scaled(orb_poison_damage), fire_poison_interval, orb_poison_duration)


# =========================================================
# MAIN LOOP
# =========================================================

func _physics_process(delta: float) -> void:
	_update_freeze(delta)

	attack_cd_left = maxf(attack_cd_left - delta, 0.0)
	fire_cd_left = maxf(fire_cd_left - delta, 0.0)
	chant_cd_left = maxf(chant_cd_left - delta, 0.0)
	ultimate_cd_left = maxf(ultimate_cd_left - delta, 0.0)

	velocity = Vector2.ZERO

	if dead:
		return

	_update_skeleton_contact(delta)

	if frozen or attacking or hurt:
		return

	var target: Node2D = find_nearest_target()

	if target == null:
		_play_if_not(idle_animation)
		return

	_face(target.global_position.x)

	var distance: float = global_position.distance_to(target.global_position)

	# 1) Ultimate below half health.
	if (
		ultimate_cd_left <= 0.0
		and health <= int(max_health * ultimate_health_ratio)
		and _has_animation(summon_animation)
	):
		_do_ultimate(target)
		return

	# 2) Skeleton Chant.
	if chant_cd_left <= 0.0 and skeleton_scene != null and _alive_skeleton_count() < max_skeletons:
		_do_chant(target)
		return

	# 3) Slash up close, green fire from range.
	if attack_cd_left <= 0.0:
		if distance <= slash_range:
			_do_slash(target)
			return

		if distance <= cast_range and fire_cd_left <= 0.0:
			_do_fire(target)
			return

	# 4) Move: close in, hold position, or back away.
	if distance > cast_range * 0.85:
		velocity = global_position.direction_to(target.global_position) * move_speed
		move_and_slide()
		_play_if_not(walk_animation if _has_animation(walk_animation) else idle_animation)
	elif distance < keep_distance:
		velocity = target.global_position.direction_to(global_position) * move_speed * retreat_speed_multiplier
		move_and_slide()
		_play_if_not(walk_animation if _has_animation(walk_animation) else idle_animation)
	else:
		_play_if_not(idle_animation)


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

	_end_action(id, _cd(slash_cooldown))


# =========================================================
# ATTACK 2: GREEN FIRE
# =========================================================

func _do_fire(target) -> void:
	var id: int = _begin_action(target)
	var has_anim: bool = _start_anim(attack2_animation)

	fire_cd_left = _cd(fire_cooldown)

	_log("GREEN FIRE")

	await _wait_hit_frame(attack2_hit_frame, id, has_anim)

	if _aborted(id):
		return

	# The fire lands where the player stands right now. It explodes a moment
	# later, so a moving player can dodge it.
	if _is_valid_target(target):
		_launch_fire(target.global_position + fire_effect_offset)

	await _wait_anim_end(has_anim)

	if _aborted(id):
		return

	_end_action(id, _cd(slash_cooldown))


func _launch_fire(world_pos: Vector2) -> void:
	var fx: AnimatedSprite2D = _spawn_effect(fire_effect_animation, world_pos)

	if fx == null:
		# No effect animation: explode right away.
		_explode_fire(world_pos - fire_effect_offset)
		return

	_watch_fire(fx, world_pos - fire_effect_offset)


# Waits for the explosion frame of the effect, then damages whoever is inside.
func _watch_fire(fx: AnimatedSprite2D, blast_center: Vector2) -> void:
	var last_frame: int = animated_sprite.sprite_frames.get_frame_count(fire_effect_animation) - 1
	var hit_frame: int = clampi(fire_effect_hit_frame, 0, maxi(last_frame, 0))

	while is_instance_valid(fx) and fx.frame < hit_frame:
		await fx.frame_changed

	if dead:
		return

	_explode_fire(blast_center)


func _explode_fire(center: Vector2) -> void:
	for victim in _hit_circle(center, fire_radius, attack2_damage):
		StatusEffects.apply_poison(victim, _scaled(fire_poison_damage), fire_poison_interval, fire_poison_duration)


# =========================================================
# SKILL: SKELETON CHANT
# =========================================================

func _do_chant(target) -> void:
	var id: int = _begin_action(target)
	var has_anim: bool = _start_anim(summon_animation)

	chant_cd_left = _cd(chant_cooldown)

	_log("SKELETON CHANT")

	# Alternates between a + shape and an x shape each time.
	chant_start_angle = 0.0 if use_plus_pattern else PI * 0.25
	use_plus_pattern = not use_plus_pattern

	_spawn_chant_effects()

	await get_tree().create_timer(chant_time).timeout

	_free_chant_fx()

	if _aborted(id):
		return

	_spawn_skeletons()

	# The summon animation loops while chanting; settle back to idle now.
	if has_anim:
		_play_if_not(idle_animation)

	_end_action(id, _cd(slash_cooldown))


func _spawn_skeletons() -> void:
	if skeleton_scene == null:
		return

	_prune_skeletons()

	var start_angle: float = chant_start_angle
	var spawned: int = 0

	for i in skeletons_per_cast:
		if chant_skeletons.size() >= max_skeletons:
			break

		var skeleton = skeleton_scene.instantiate()
		var angle: float = start_angle + TAU * float(i) / float(maxi(skeletons_per_cast, 1))

		get_parent().add_child(skeleton)
		skeleton.global_position = global_position + Vector2.from_angle(angle) * skeleton_spawn_radius

		chant_skeletons.append(skeleton)
		spawned += 1

	_log("SKELETONS SUMMONED: %d" % spawned)
	skeletons_summoned.emit(spawned)


func _spawn_chant_effects() -> void:
	_free_chant_fx()

	if summon_effect_at_caster:
		_add_chant_fx(global_position + summon_effect_offset)

	if summon_effect_at_spawn_points:
		for i in skeletons_per_cast:
			var angle: float = chant_start_angle + TAU * float(i) / float(maxi(skeletons_per_cast, 1))
			var spot: Vector2 = global_position + Vector2.from_angle(angle) * skeleton_spawn_radius

			_add_chant_fx(spot + summon_effect_spawn_offset)


func _add_chant_fx(world_pos: Vector2) -> void:
	var fx = _spawn_effect(summon_effect_animation, world_pos, true)

	if fx != null:
		chant_fxs.append(fx)


func _free_chant_fx() -> void:
	for fx in chant_fxs:
		if is_instance_valid(fx):
			fx.queue_free()

	chant_fxs.clear()


func _prune_skeletons() -> void:
	var alive: Array = []

	for skeleton in chant_skeletons:
		if is_instance_valid(skeleton) and not skeleton.is_queued_for_deletion() and skeleton.get("dead") != true:
			alive.append(skeleton)

	chant_skeletons = alive


func _alive_skeleton_count() -> int:
	_prune_skeletons()
	return chant_skeletons.size()


# A summoned skeleton touching a player immobilizes that player.
func _update_skeleton_contact(delta: float) -> void:
	for key in immobilize_cooldowns.keys():
		immobilize_cooldowns[key] -= delta

		if immobilize_cooldowns[key] <= 0.0:
			immobilize_cooldowns.erase(key)

	if chant_skeletons.is_empty():
		return

	_prune_skeletons()

	for skeleton in chant_skeletons:
		for player in get_tree().get_nodes_in_group("players"):
			if not _is_valid_target(player):
				continue

			var player_id: int = player.get_instance_id()

			if immobilize_cooldowns.has(player_id):
				continue

			# Skeletons stop at their attack range, so count that as touching.
			var reach: float = skeleton_contact_radius
			var skeleton_range = skeleton.get("attack_range")

			if skeleton_range != null:
				reach = maxf(reach, float(skeleton_range))

			if skeleton.global_position.distance_to(player.global_position) <= reach:
				immobilize_cooldowns[player_id] = immobilize_recheck_time
				StatusEffects.apply_root(player, immobilize_time)
				_log("IMMOBILIZED: %s" % player.name)


# =========================================================
# ULTIMATE: DANCE OF THE SHADOW
# =========================================================

func _do_ultimate(target) -> void:
	var id: int = _begin_action(target)
	var has_anim: bool = _start_anim(summon_animation)

	ultimate_cd_left = _cd(ultimate_cooldown)

	_log("DANCE OF THE SHADOW")
	ultimate_cast.emit()

	_free_chant_fx()
	_add_chant_fx(global_position + summon_effect_offset)

	var orbs := ShadowOrbs.new()
	orbs.boss = self
	orbs.sets = orb_sets
	orbs.orbs_per_set = orbs_per_set
	orbs.radius_start = orb_start_radius
	orbs.radius_step = orb_radius_step
	orbs.orb_radius = orb_size
	orbs.spin_speed = orb_spin_speed
	orbs.build_delay = orb_set_delay
	orbs.spin_time = orb_spin_time
	orbs.launch_speed = orb_launch_speed
	orbs.launch_distance = orb_launch_distance
	orbs.hit_interval = orb_hit_interval
	orbs.position = orb_center_offset

	add_child(orbs)
	vortex = orbs

	await orbs.finished

	_free_chant_fx()

	if _aborted(id):
		return

	vortex = null

	if has_anim:
		_play_if_not(idle_animation)

	_end_action(id, _cd(slash_cooldown))
