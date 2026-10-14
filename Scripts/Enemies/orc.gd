extends CharacterBody2D

# --- Health ---
@export var max_health: int = 100
@export var respawn_time: float = 3.0

# --- Movement ---
@export var move_speed: float = 80.0

# --- Attack ---
@export var attack_damage: int = 10           # attack1 (normal)
@export var attack2_damage: int = 20          # attack2 (heavy)
@export var heavy_attack_every: int = 3       # 3 = every third attack
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
var attack_target = null     # player locked onto when the attack started

# Change whenever an attack / hurt is interrupted, so old coroutines stop safely
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

	# Top-down game: Floating stops bodies being carried along like moving platforms
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING

	health = max_health
	base_modulate = animated_sprite.modulate

	collision_shape.set_deferred("disabled", false)

	# These must play once and finish, otherwise the orc can get stuck waiting for them
	for anim_name in ["attack1", "attack2", "hurt", "death"]:
		if animated_sprite.sprite_frames.has_animation(anim_name):
			animated_sprite.sprite_frames.set_animation_loop(anim_name, false)

	animated_sprite.visible = true
	animated_sprite.play("idle")

	print("ORC READY | HP: ", health)
	print("ANIMATIONS: ", animated_sprite.sprite_frames.get_animation_names())


# =========================================================
# COLOUR (freeze tint + hit flash)
# =========================================================

# The colour the orc goes back to after a hit flash
func _rest_color() -> Color:
	return freeze_tint if frozen else base_modulate


# Used when freezing / unfreezing (a running flash blends to the right colour by itself)
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
# PHYSICS (CHASE + ATTACK)
# =========================================================

func _physics_process(delta: float) -> void:
	update_freeze(delta)

	velocity = Vector2.ZERO

	# Busy: stay still (frozen keeps its frozen pose)
	if dead or frozen or attacking or hurt:
		return

	var target = find_nearest_player()

	# No living players
	if target == null:
		play_if_not("idle")
		return

	var distance := global_position.distance_to(target.global_position)

	# Always face the nearest player
	animated_sprite.flip_h = target.global_position.x < global_position.x

	if distance > attack_range:
		# Too far: chase
		velocity = global_position.direction_to(target.global_position) * move_speed
		move_and_slide()

		play_if_not("walk")
	else:
		# Close enough: stop and attack
		play_if_not("idle")

		if can_attack:
			start_attack(target)


func play_if_not(anim_name: String) -> void:
	if animated_sprite.animation != anim_name or not animated_sprite.is_playing():
		animated_sprite.play(anim_name)


func find_nearest_player():
	var nearest_player = null
	var nearest_distance := INF

	for player in get_tree().get_nodes_in_group("players"):
		if not is_instance_valid(player):
			continue

		if not player.has_method("take_damage"):
			continue

		if player.dead:
			continue

		var distance := global_position.distance_to(player.global_position)

		if distance < nearest_distance:
			nearest_distance = distance
			nearest_player = player

	return nearest_player


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

	# Already frozen: just refresh the time
	freeze_time_left = maxf(freeze_time_left, duration)

	if frozen:
		return

	frozen = true

	# Interrupt whatever the orc was doing (this also cancels a pending hurt / attack)
	attack_id += 1
	hurt_id += 1

	hurt = false
	attacking = false
	can_attack = false
	damage_dealt = false
	attack_target = null
	velocity = Vector2.ZERO

	# Hold a still "idle" pose while frozen
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

	# Make sure nothing is left over from before the freeze
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
# STAGGER (interrupts the orc and plays the hurt animation)
# =========================================================

func stagger() -> void:
	if dead or frozen:
		return

	if attacking:
		# Cancel the swing so its damage frame never lands.
		# can_attack is released here: `hurt` keeps the orc from attacking until the animation ends.
		attack_id += 1
		attacking = false
		can_attack = true
		damage_dealt = false
		attack_target = null

	hurt = true
	hurt_id += 1
	var my_hurt := hurt_id

	velocity = Vector2.ZERO

	animated_sprite.stop()
	animated_sprite.animation = "hurt"
	animated_sprite.frame = 0
	animated_sprite.play()

	print("ORC STAGGERED")

	await animated_sprite.animation_finished

	# Skipped if the stagger was interrupted (frozen, died, staggered again...)
	if dead or my_hurt != hurt_id:
		return

	hurt = false
	animated_sprite.play("idle")


# =========================================================
# ATTACK
# =========================================================

func start_attack(target) -> void:
	if dead or frozen or attacking or not can_attack or target == null:
		return

	attack_id += 1
	var my_id := attack_id

	# Lock onto this player for the whole attack
	attack_target = target

	attacking = true
	can_attack = false
	damage_dealt = false
	velocity = Vector2.ZERO

	# Every Nth attack is the heavy one
	attack_count += 1

	var heavy := attack_count % heavy_attack_every == 0
	var anim_name := "attack2" if heavy else "attack1"
	var damage := attack2_damage if heavy else attack_damage
	var hit_frame := attack2_hit_frame if heavy else attack1_hit_frame

	animated_sprite.flip_h = target.global_position.x < global_position.x

	animated_sprite.stop()
	animated_sprite.animation = anim_name
	animated_sprite.frame = 0
	animated_sprite.play()

	print("ORC %s | ATTACK #%d | TARGET: %s | DAMAGE: %d" % [anim_name.to_upper(), attack_count, target.name, damage])

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

	# Cooldown before the next attack
	await get_tree().create_timer(attack_cooldown).timeout

	if dead or my_id != attack_id:
		return

	can_attack = true


func wait_for_attack_frame(target_frame: int, id: int) -> void:
	# Never wait for a frame the animation doesn't have
	var last_frame := animated_sprite.sprite_frames.get_frame_count(animated_sprite.animation) - 1
	target_frame = mini(target_frame, last_frame)

	while animated_sprite.frame < target_frame:
		await get_tree().process_frame

		if dead or id != attack_id:
			return


func deal_attack_damage(damage: int) -> void:
	if dead or frozen or damage_dealt:
		return

	damage_dealt = true

	var target = attack_target

	if target == null or not is_instance_valid(target):
		return

	if target.dead:
		return

	if global_position.distance_to(target.global_position) > attack_range:
		print("ORC ATTACK MISSED: OUT OF RANGE")
		return

	if target.has_method("take_damage"):
		print("ORC HIT: %s | DAMAGE: %d" % [target.name, damage])
		target.take_damage(damage)


# =========================================================
# TAKE DAMAGE
# =========================================================

func take_damage(damage: int) -> void:
	if dead:
		return

	health = max(health - damage, 0)

	print("ORC TOOK DAMAGE: %d | HP: %d" % [damage, health])

	if health <= 0:
		die()
		flash_red()   # after die(), so its colour reset doesn't cancel the flash
		return

	# Red flash, even while attacking or frozen
	flash_red()

	# Don't interrupt an attack or a freeze with the hurt animation
	if attacking or frozen:
		return

	hurt = true
	hurt_id += 1
	var my_hurt := hurt_id

	animated_sprite.stop()
	animated_sprite.animation = "hurt"
	animated_sprite.frame = 0
	animated_sprite.play()

	await animated_sprite.animation_finished

	# Skipped if the hurt was interrupted (frozen, died, hit again...)
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

	if not is_instance_valid(self):
		return

	animated_sprite.visible = false

	await get_tree().create_timer(respawn_time).timeout

	if not is_instance_valid(self):
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
