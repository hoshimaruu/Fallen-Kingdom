class_name Enemy
extends CharacterBody2D

# Generic melee enemy, built from the Orc. Attach it to any enemy scene that has:
#   - an AnimatedSprite2D child named "AnimatedSprite2D"
#   - a CollisionShape2D child named "CollisionShape2D"
# Then give each enemy its own SpriteFrames and Inspector stats.
# Dead enemies stay dead: they never respawn.

signal died(enemy: Enemy)
signal damaged(enemy: Enemy, amount: int)

# --- Health ---
@export var max_health: int = 100

# --- Movement ---
@export var move_speed: float = 80.0
# 0 = chases the nearest target anywhere on the map.
@export var aggro_range: float = 0.0

# --- Attack ---
@export var attack_damage: int = 10
@export var attack2_damage: int = 20
# Every Nth attack is the heavy attack2. 0 = never use attack2.
@export var heavy_attack_every: int = 3
@export var attack1_hit_frame: int = 4
@export var attack2_hit_frame: int = 4
@export var attack_range: float = 70.0
@export var attack_cooldown: float = 1.5

# --- Targets ---
@export var target_groups: Array[StringName] = [&"players", &"summons"]

# --- Death ---
# 0 = the body stays on the ground forever. Above 0 = it fades out after
# that many seconds and is removed.
@export var corpse_lifetime: float = 0.0

# --- Special ---
# Bosses: ignore stagger and the hurt animation.
@export var stagger_immune: bool = false
# How long a stagger lasts when the enemy has no hurt animation.
@export var stagger_fallback_time: float = 0.35
# True if the art faces right (flipped when the target is on the left).
@export var sprite_faces_right: bool = true

# --- Animations ---
@export var idle_animation: StringName = &"idle"
@export var walk_animation: StringName = &"walk"
@export var attack1_animation: StringName = &"attack1"
@export var attack2_animation: StringName = &"attack2"
@export var hurt_animation: StringName = &"hurt"
@export var death_animation: StringName = &"death"

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

# Untyped on purpose: the target may be freed mid-attack, and a freed object
# cannot be stored in a typed variable.
var attack_target = null

# Change whenever an attack / hurt is interrupted.
var attack_id: int = 0
var hurt_id: int = 0

var base_modulate: Color = Color.WHITE
var flash_tween: Tween

# --- Nodes ---
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D


# =========================================================
# HOOKS: override these in a subclass (extends Enemy)
# =========================================================

# Runs at the end of _ready().
func _on_ready() -> void:
	pass


# Runs on the attack's hit frame. Override for projectiles, AoE, and so on.
func _on_attack_hit(damage: int) -> void:
	_deal_attack_damage(damage)


# Runs after every hit that did not kill the enemy.
func _on_damaged(_amount: int) -> void:
	pass


# Runs once when the enemy dies.
func _on_death() -> void:
	pass


# =========================================================
# READY
# =========================================================

func _ready() -> void:
	add_to_group("enemies")
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING

	health = max_health
	base_modulate = animated_sprite.modulate
	collision_shape.set_deferred("disabled", false)

	for anim_name in [
		attack1_animation,
		attack2_animation,
		hurt_animation,
		death_animation
	]:
		if _has_animation(anim_name):
			animated_sprite.sprite_frames.set_animation_loop(anim_name, false)

	animated_sprite.visible = true
	_play_if_not(idle_animation)

	_log("READY | HP: %d" % health)
	_on_ready()


func _log(message: String) -> void:
	print("[%s] %s" % [name, message])


# =========================================================
# ANIMATION HELPERS
# =========================================================

func _has_animation(anim_name: StringName) -> bool:
	return (
		animated_sprite.sprite_frames != null
		and animated_sprite.sprite_frames.has_animation(anim_name)
	)


func _play_if_not(anim_name: StringName) -> void:
	if not _has_animation(anim_name):
		return

	if animated_sprite.animation != anim_name or not animated_sprite.is_playing():
		animated_sprite.play(anim_name)


func _restart_animation(anim_name: StringName) -> void:
	if not _has_animation(anim_name):
		return

	animated_sprite.stop()
	animated_sprite.animation = anim_name
	animated_sprite.frame = 0
	animated_sprite.play()


func _face(target_x: float) -> void:
	var target_is_left: bool = target_x < global_position.x
	animated_sprite.flip_h = target_is_left if sprite_faces_right else not target_is_left


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
	flash_tween.tween_method(_set_flash_blend, 0.0, 1.0, hit_flash_time)


func _set_flash_blend(amount: float) -> void:
	animated_sprite.modulate = hit_flash_color.lerp(_rest_color(), amount)


func _reset_color() -> void:
	if flash_tween:
		flash_tween.kill()

	animated_sprite.modulate = base_modulate


# =========================================================
# PHYSICS: CHASE + ATTACK
# =========================================================

func _physics_process(delta: float) -> void:
	_update_freeze(delta)

	velocity = Vector2.ZERO

	if dead or frozen or attacking or hurt:
		return

	var target: Node2D = find_nearest_target()

	if target == null:
		_play_if_not(idle_animation)
		return

	_face(target.global_position.x)

	var distance: float = global_position.distance_to(target.global_position)

	if distance > attack_range:
		velocity = global_position.direction_to(target.global_position) * move_speed
		move_and_slide()
		_play_if_not(walk_animation if _has_animation(walk_animation) else idle_animation)
	else:
		_play_if_not(idle_animation)

		if can_attack:
			start_attack(target)


# =========================================================
# TARGETING
# =========================================================

func find_nearest_target() -> Node2D:
	var nearest_target: Node2D = null
	var nearest_distance: float = INF

	if aggro_range > 0.0:
		nearest_distance = aggro_range

	for group_name in target_groups:
		for candidate in get_tree().get_nodes_in_group(group_name):
			if not _is_valid_target(candidate):
				continue

			var distance: float = global_position.distance_to(candidate.global_position)

			if distance < nearest_distance:
				nearest_distance = distance
				nearest_target = candidate

	return nearest_target


# Untyped on purpose: candidates can be freed objects.
func _is_valid_target(candidate) -> bool:
	if not is_instance_valid(candidate) or not candidate is Node2D:
		return false

	if candidate.is_queued_for_deletion() or not candidate.has_method("take_damage"):
		return false

	# Dead players, dismissed summons and anything with no health left.
	if candidate.get("dead") == true or candidate.get("disappearing") == true:
		return false

	var target_health = candidate.get("health")

	if target_health != null and target_health <= 0:
		return false

	return true


# =========================================================
# FREEZE
# =========================================================

func _update_freeze(delta: float) -> void:
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

	if _has_animation(idle_animation):
		animated_sprite.stop()
		animated_sprite.animation = idle_animation
		animated_sprite.frame = 0

	_refresh_color()

	_log("FROZEN | TIME: %.1f" % duration)


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
	_play_if_not(idle_animation)

	_log("UNFROZEN")


# =========================================================
# STAGGER
# =========================================================

# Damage alone never interrupts an enemy: it keeps moving and attacking.
# Only stagger() does. Call it from attacks that should interrupt (the
# Healer's AoE does), or use take_damage(amount, true).
# duration <= 0 lasts as long as the hurt animation, or stagger_fallback_time
# when the enemy has no hurt animation.

func stagger(duration: float = 0.0) -> void:
	if dead or frozen or stagger_immune:
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
	_restart_animation(hurt_animation)

	if _has_animation(hurt_animation) and duration <= 0.0:
		await animated_sprite.animation_finished
	else:
		var wait_time: float = duration if duration > 0.0 else stagger_fallback_time
		await get_tree().create_timer(wait_time).timeout

	if dead or my_hurt != hurt_id:
		return

	hurt = false
	_play_if_not(idle_animation)


# =========================================================
# ATTACK
# =========================================================

func start_attack(target: Node2D) -> void:
	if dead or frozen or attacking or not can_attack:
		return

	if not is_instance_valid(target) or not _has_animation(attack1_animation):
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
		heavy_attack_every > 0
		and attack_count % heavy_attack_every == 0
		and _has_animation(attack2_animation)
	)

	var anim_name: StringName = attack2_animation if heavy else attack1_animation
	var damage: int = attack2_damage if heavy else attack_damage
	var hit_frame: int = attack2_hit_frame if heavy else attack1_hit_frame

	_face(target.global_position.x)
	_restart_animation(anim_name)

	_log("%s | ATTACK #%d | TARGET: %s | DAMAGE: %d" % [
		String(anim_name).to_upper(), attack_count, target.name, damage
	])

	await _wait_for_attack_frame(hit_frame, my_id)

	if dead or my_id != attack_id:
		return

	if not damage_dealt:
		_on_attack_hit(damage)

	await animated_sprite.animation_finished

	if dead or my_id != attack_id:
		return

	attacking = false
	damage_dealt = false
	attack_target = null

	_play_if_not(idle_animation)

	await get_tree().create_timer(attack_cooldown).timeout

	if dead or my_id != attack_id:
		return

	can_attack = true


func _wait_for_attack_frame(target_frame: int, id: int) -> void:
	var last_frame: int = animated_sprite.sprite_frames.get_frame_count(
		animated_sprite.animation
	) - 1

	target_frame = clampi(target_frame, 0, maxi(last_frame, 0))

	while animated_sprite.frame < target_frame:
		await get_tree().process_frame

		if dead or id != attack_id:
			return


func _deal_attack_damage(damage: int) -> void:
	if dead or frozen or damage_dealt:
		return

	damage_dealt = true

	if not _is_valid_target(attack_target):
		return

	if global_position.distance_to(attack_target.global_position) > attack_range:
		_log("ATTACK MISSED: OUT OF RANGE")
		return

	_log("HIT: %s | DAMAGE: %d" % [attack_target.name, damage])
	attack_target.call("take_damage", damage)


# =========================================================
# TAKE DAMAGE
# =========================================================

# Damage never interrupts movement or attacks by itself. Pass do_stagger = true
# (or call stagger()) for attacks that should.
func take_damage(damage: int, do_stagger: bool = false) -> void:
	if dead or damage <= 0:
		return

	health = maxi(health - damage, 0)

	_log("TOOK DAMAGE: %d | HP: %d/%d" % [damage, health, max_health])

	damaged.emit(self, damage)

	if health <= 0:
		die()
		flash_red()
		return

	flash_red()
	_on_damaged(damage)

	if do_stagger:
		stagger()


# =========================================================
# DEATH (permanent)
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

	# Nothing can target or hit a dead enemy any more.
	remove_from_group("enemies")
	collision_shape.set_deferred("disabled", true)
	set_physics_process(false)

	died.emit(self)
	_log("DIED")
	_on_death()

	var has_death_animation: bool = _has_animation(death_animation)

	if has_death_animation:
		_restart_animation(death_animation)
		await animated_sprite.animation_finished

	if not is_inside_tree():
		return

	# No death animation means there is no corpse to show.
	if not has_death_animation:
		queue_free()
		return

	# The death animation is not looping, so the body stays on its last frame.
	if corpse_lifetime <= 0.0:
		return

	await get_tree().create_timer(corpse_lifetime).timeout

	if not is_inside_tree():
		return

	var fade: Tween = create_tween()
	fade.tween_property(animated_sprite, "modulate:a", 0.0, 0.5)
	await fade.finished

	queue_free()
