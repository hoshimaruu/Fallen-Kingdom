extends CharacterBody2D

# --- Movement ---
@export var speed: float = 180.0

# --- Dash ---
@export var dash_speed: float = 600.0
@export var dash_duration: float = 0.15
@export var dash_cooldown: float = 4.0
@export var dash_immunity_time: float = 0.4    # immune this long from dash start (never less than dash_duration)
@export var dash_anim_speed: float = 2.5
@export var dash_tint: Color = Color(0.7, 0.85, 1.0, 0.7)
@export var afterimage_interval: float = 0.03
@export var afterimage_fade_time: float = 0.25

# --- Health ---
@export var max_health: int = 80
@export var respawn_time: float = 3.0

# --- Hit flash ---
@export var hit_flash_color: Color = Color(1.0, 0.25, 0.25, 1.0)
@export var hit_flash_time: float = 0.25

# --- Attacks ---
@export var attack1_damage: int = 15
@export var attack2_damage: int = 25
@export var attack1_release_frame: int = 6     # attack1 animation: frames 0-8
@export var attack2_release_frame: int = 11    # attack2 animation: frames 0-11
@export var attack1_cooldown: float = 0.0
@export var attack2_cooldown: float = 10.0

# --- Arrows (assign both scenes in the Inspector!) ---
@export var arrow1_scene: PackedScene
@export var arrow2_scene: PackedScene
@export var arrow_spawn_offset: float = 40.0   # attack1 arrow distance in front of the archer
@export var arrow2_spawn_offset: float = 70.0  # attack2 (heavy) arrow distance in front of the archer
@export var arrow_spawn_height: float = 0.0    # move arrows up (negative) or down (positive) to match the bow

# --- State ---
var player_id: int = 0
var health: int
var dead: bool = false
var hurt: bool = false
var attacking: bool = false
var current_attack: String = ""
var arrow_fired: bool = false

var dashing: bool = false
var dash_direction: float = 1.0
var dash_timer: float = 0.0
var afterimage_timer: float = 0.0
var immunity_timer: float = 0.0

# Remaining cooldown per ability
var cooldowns: Dictionary = {"attack1": 0.0, "attack2": 0.0, "dash": 0.0}

# --- Input action names ---
var act_up: String
var act_down: String
var act_left: String
var act_right: String
var act_attack1: String
var act_attack2: String
var act_attack3: String   # dash

# --- Nodes ---
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var base_modulate: Color = Color.WHITE
var flash_tween: Tween


# =========================================================
# SETUP
# =========================================================

func _ready() -> void:
	add_to_group("players")

	match get_parent().name:
		"Player1":
			player_id = 1
		"Player2":
			player_id = 2
		_:
			print("WARNING: Archer is not under Player1 or Player2")

	_setup_actions()

	health = max_health
	base_modulate = animated_sprite.modulate

	collision_shape.set_deferred("disabled", false)

	animated_sprite.visible = true
	animated_sprite.speed_scale = 1.0
	animated_sprite.play("idle")

	_log("READY | HP: %d | SPEED: %s" % [health, speed])
	_log("DASH: speed %s, cooldown %ss, immunity %ss | ATTACK1: %d dmg | ATTACK2: %d dmg (cd %ss)" % [
		dash_speed, dash_cooldown, maxf(dash_immunity_time, dash_duration),
		attack1_damage, attack2_damage, attack2_cooldown
	])
	_log("RELEASE FRAMES | ATTACK1: %d | ATTACK2: %d" % [attack1_release_frame, attack2_release_frame])
	_log("ANIMATIONS: %s" % [animated_sprite.sprite_frames.get_animation_names()])

	# Arrows can't spawn if these slots are empty, so say so right at the start
	if arrow1_scene == null:
		_log("WARNING: 'Arrow1 Scene' is NOT assigned in the Inspector, attack1 can't fire")
	if arrow2_scene == null:
		_log("WARNING: 'Arrow2 Scene' is NOT assigned in the Inspector, attack2 can't fire")


func _setup_actions() -> void:
	var prefix := "p1_" if player_id == 1 else "p2_"

	act_up = prefix + "up"
	act_down = prefix + "down"
	act_left = prefix + "left"
	act_right = prefix + "right"
	act_attack1 = prefix + "attack1"
	act_attack2 = prefix + "attack2"
	act_attack3 = prefix + "attack3"


# =========================================================
# HELPERS
# =========================================================

func _log(message: String) -> void:
	print("[P%d ARCHER] %s" % [player_id, message])


func _restart_animation(anim_name: String) -> void:
	animated_sprite.stop()
	animated_sprite.animation = anim_name
	animated_sprite.frame = 0
	animated_sprite.play()


func flash_red() -> void:
	if flash_tween:
		flash_tween.kill()

	animated_sprite.modulate = hit_flash_color

	flash_tween = create_tween()
	flash_tween.tween_property(animated_sprite, "modulate", base_modulate, hit_flash_time)


func is_on_cooldown(ability: String) -> bool:
	return cooldowns[ability] > 0.0


func start_cooldown(ability: String, duration: float) -> void:
	if duration > 0.0:
		cooldowns[ability] = duration


func tick_cooldowns(delta: float) -> void:
	for ability in cooldowns:
		if cooldowns[ability] > 0.0:
			cooldowns[ability] = maxf(cooldowns[ability] - delta, 0.0)

			if cooldowns[ability] == 0.0:
				_log("%s COOLDOWN READY" % ability.to_upper())


func is_immune() -> bool:
	return dashing or immunity_timer > 0.0


func tick_immunity(delta: float) -> void:
	if immunity_timer <= 0.0:
		return

	immunity_timer -= delta

	if immunity_timer <= 0.0:
		immunity_timer = 0.0
		animated_sprite.modulate = base_modulate
		_log("IMMUNITY ENDED")


# =========================================================
# PHYSICS
# =========================================================

func _physics_process(delta: float) -> void:
	tick_cooldowns(delta)
	tick_immunity(delta)

	if dead or hurt:
		velocity = Vector2.ZERO
		return

	if dashing:
		velocity = Vector2(dash_direction * dash_speed, 0)
		move_and_slide()

		afterimage_timer -= delta
		if afterimage_timer <= 0.0:
			spawn_afterimage()
			afterimage_timer = afterimage_interval

		dash_timer -= delta
		if dash_timer <= 0.0:
			end_dash()

		return

	if attacking:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	# --- Ability input ---
	if Input.is_action_just_pressed(act_attack1):
		start_attack("attack1")
		return

	if Input.is_action_just_pressed(act_attack2):
		start_attack("attack2")
		return

	if Input.is_action_just_pressed(act_attack3):
		start_dash()
		return

	# --- Movement ---
	var direction := Input.get_vector(act_left, act_right, act_up, act_down)

	velocity = direction * speed

	# Only horizontal movement changes facing
	if direction.x != 0:
		animated_sprite.flip_h = direction.x < 0

	var wanted_anim := "walk" if direction != Vector2.ZERO else "idle"

	if animated_sprite.animation != wanted_anim:
		animated_sprite.play(wanted_anim)

	move_and_slide()


# =========================================================
# DASH
# =========================================================

func start_dash() -> void:
	if dashing or dead or hurt or attacking:
		return

	if is_on_cooldown("dash"):
		_log("DASH BLOCKED | COOLDOWN: %.2fs" % cooldowns["dash"])
		return

	dashing = true
	dash_timer = dash_duration
	afterimage_timer = 0.0
	immunity_timer = maxf(dash_immunity_time, dash_duration)
	velocity = Vector2.ZERO

	start_cooldown("dash", dash_cooldown)

	# Dash in the facing direction
	dash_direction = -1.0 if animated_sprite.flip_h else 1.0

	# Stop any leftover hit flash so it can't wash out the dash tint
	if flash_tween:
		flash_tween.kill()

	animated_sprite.play("walk")
	animated_sprite.speed_scale = dash_anim_speed
	animated_sprite.modulate = dash_tint

	_log("DASH %s | %ss at speed %s | IMMUNE FOR %.2fs | cooldown %ss" % [
		"LEFT" if dash_direction < 0 else "RIGHT",
		dash_duration, dash_speed, immunity_timer, dash_cooldown
	])


func end_dash() -> void:
	if not dashing:
		return

	dashing = false
	velocity = Vector2.ZERO

	# The tint stays until immunity ends, so the player can see they're still protected
	animated_sprite.speed_scale = 1.0

	_log("DASH FINISHED")

	if not dead and not hurt:
		animated_sprite.play("idle")


func reset_dash_visuals() -> void:
	if flash_tween:
		flash_tween.kill()

	animated_sprite.speed_scale = 1.0
	animated_sprite.modulate = base_modulate


func spawn_afterimage() -> void:
	var texture := animated_sprite.sprite_frames.get_frame_texture(
		animated_sprite.animation,
		animated_sprite.frame
	)

	if texture == null:
		return

	var ghost := Sprite2D.new()
	ghost.texture = texture
	ghost.flip_h = animated_sprite.flip_h
	ghost.centered = animated_sprite.centered
	ghost.offset = animated_sprite.offset
	ghost.scale = animated_sprite.global_scale
	ghost.modulate = Color(dash_tint.r, dash_tint.g, dash_tint.b, 0.5)

	# Add next to the archer, drawn just behind it
	var parent := get_parent()
	parent.add_child(ghost)
	parent.move_child(ghost, get_index())
	ghost.global_position = animated_sprite.global_position

	var tween := ghost.create_tween()
	tween.tween_property(ghost, "modulate:a", 0.0, afterimage_fade_time)
	tween.tween_callback(ghost.queue_free)


# =========================================================
# ATTACKS
# =========================================================

func start_attack(animation_name: String) -> void:
	if attacking or dashing or hurt or dead:
		return

	if is_on_cooldown(animation_name):
		_log("%s BLOCKED | COOLDOWN: %.2fs" % [animation_name.to_upper(), cooldowns[animation_name]])
		return

	var is_attack1 := animation_name == "attack1"

	attacking = true
	current_attack = animation_name
	arrow_fired = false
	velocity = Vector2.ZERO

	start_cooldown(animation_name, attack1_cooldown if is_attack1 else attack2_cooldown)

	_log("%s | FACING: %s" % [
		animation_name.to_upper(),
		"LEFT" if animated_sprite.flip_h else "RIGHT"
	])

	_restart_animation(animation_name)

	await wait_for_attack_frame(attack1_release_frame if is_attack1 else attack2_release_frame)

	if dead or hurt:
		return

	if not arrow_fired:
		fire_arrow()

	await animated_sprite.animation_finished

	if dead or hurt:
		return

	end_attack()


func wait_for_attack_frame(target_frame: int) -> void:
	# Never wait for a frame the animation doesn't have (that would block the arrow forever)
	var last_frame := animated_sprite.sprite_frames.get_frame_count(animated_sprite.animation) - 1
	target_frame = mini(target_frame, last_frame)

	while true:
		if dead or hurt or not attacking:
			return

		if animated_sprite.frame >= target_frame:
			return

		await get_tree().process_frame


func fire_arrow() -> void:
	if arrow_fired:
		return

	arrow_fired = true

	var arrow_scene: PackedScene
	var damage: int
	var arrow_name: String
	var spawn_offset: float

	match current_attack:
		"attack1":
			arrow_scene = arrow1_scene
			damage = attack1_damage
			arrow_name = "ARROW 1"
			spawn_offset = arrow_spawn_offset
		"attack2":
			arrow_scene = arrow2_scene
			damage = attack2_damage
			arrow_name = "ARROW 2 (HEAVY)"
			spawn_offset = arrow2_spawn_offset
		_:
			_log("ERROR: UNKNOWN ATTACK '%s'" % current_attack)
			return

	if arrow_scene == null:
		_log("ERROR: %s SCENE IS NOT ASSIGNED (select the archer node, set it in the Inspector)" % arrow_name)
		return

	var arrow = arrow_scene.instantiate()

	# Add the arrow to the Main scene (falls back to the current scene)
	var container: Node = get_parent().get_parent()
	if container == null:
		container = get_tree().current_scene

	container.add_child(arrow)

	var facing_direction := -1.0 if animated_sprite.flip_h else 1.0

	arrow.global_position = global_position + Vector2(facing_direction * spawn_offset, arrow_spawn_height)

	# Give the arrow its direction and damage
	if arrow.has_method("setup"):
		arrow.setup(Vector2(facing_direction, 0), damage)
	else:
		if "direction" in arrow:
			arrow.direction = Vector2(facing_direction, 0)
		if "damage" in arrow:
			arrow.damage = damage

	# Flip arrow when facing left
	if facing_direction < 0:
		arrow.scale.x = -abs(arrow.scale.x)

	_log("FIRED %s | DAMAGE: %d | DIRECTION: %s | OFFSET: %s | ARCHER AT: %s | ARROW AT: %s | PARENT: %s" % [
		arrow_name, damage, "LEFT" if facing_direction < 0 else "RIGHT", spawn_offset,
		global_position, arrow.global_position, container.name
	])


func end_attack() -> void:
	attacking = false
	current_attack = ""
	arrow_fired = false
	velocity = Vector2.ZERO

	if not dead and not hurt:
		animated_sprite.play("idle")


# =========================================================
# DAMAGE / DEATH / RESPAWN
# =========================================================

func take_damage(damage: int) -> void:
	if dead:
		return

	# Immune for the whole dash (and a little after, see dash_immunity_time)
	if is_immune():
		_log("DAMAGE BLOCKED | IMMUNE (%.2fs left)" % immunity_timer)
		return

	health = max(health - damage, 0)

	_log("TOOK %d DAMAGE | HP: %d/%d" % [damage, health, max_health])

	if health <= 0:
		die()
		flash_red()   # after die(), so its visual reset doesn't cancel the flash
		return

	hurt = true
	attacking = false
	current_attack = ""
	arrow_fired = false
	velocity = Vector2.ZERO

	reset_dash_visuals()
	flash_red()       # after the reset, even while an animation is playing
	_restart_animation("hurt")

	_log("HURT")

	await animated_sprite.animation_finished

	if dead:
		return

	hurt = false
	animated_sprite.play("idle")


func die() -> void:
	if dead:
		return

	dead = true
	hurt = false
	attacking = false
	dashing = false
	current_attack = ""
	arrow_fired = false
	velocity = Vector2.ZERO

	reset_dash_visuals()
	collision_shape.set_deferred("disabled", true)
	_restart_animation("death")

	_log("DIED")

	await animated_sprite.animation_finished
	await get_tree().create_timer(respawn_time).timeout

	if not is_inside_tree():
		return

	respawn()


func respawn() -> void:
	health = max_health

	dead = false
	hurt = false
	attacking = false
	dashing = false
	current_attack = ""
	arrow_fired = false

	dash_timer = 0.0
	afterimage_timer = 0.0
	immunity_timer = 0.0
	velocity = Vector2.ZERO

	for ability in cooldowns:
		cooldowns[ability] = 0.0

	reset_dash_visuals()
	collision_shape.set_deferred("disabled", false)

	animated_sprite.visible = true
	animated_sprite.play("idle")

	_log("RESPAWNED | HP: %d" % health)
