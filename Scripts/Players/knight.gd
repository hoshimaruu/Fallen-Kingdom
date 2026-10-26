extends CharacterBody2D

# Emitted for HUDs, cameras and score keeping.
signal health_changed(current: int, maximum: int)
signal died(character)

# --- Movement ---
@export var speed: float = 180.0

# --- Health ---
@export var max_health: int = 150
@export var respawn_time: float = 3.0

# --- Attack damage ---
@export var attack1_damage: int = 15
# Animation frame where the sword connects, and how long the hit stays active.
@export var attack1_hit_frame: int = 2
@export var attack1_hit_window: float = 0.2
# Sword reach box in front of the knight (pixels). Bigger = easier to hit.
@export var attack1_reach: float = 70.0
@export var attack1_height: float = 70.0
@export var attack1_behind: float = 10.0
@export var attack2_damage: int = 15

# --- Knight slash (attack2 projectile) ---
@export var slash_scene: PackedScene
@export var slash_release_frame: int = 8

# --- Block ---
@export var block_duration: float = 1.5
@export var block_damage_reduction: float = 0.8  # 0.8 = take 20%, 1.0 = take none

# --- Attack area ---
@export var attack_area_distance: float = 35.0

# --- Hit flash ---
@export var hit_flash_color: Color = Color(1.0, 0.25, 0.25, 1.0)
@export var hit_flash_time: float = 0.25

# --- Stagger ---
# Damage never interrupts movement or attacks. Only stagger() does
# (an enemy attack asks for it with take_damage(amount, true)).
# Turn this on for a character that should ignore stagger completely.
@export var stagger_immune: bool = false

# Overlapping bodies push each other apart, and players that spawn on the same
# spot can get shoved away fast. With this on, players walk through each other.
@export var players_ignore_each_other: bool = true

# --- State ---
var player_id: int = 0
# False when no player is controlling this character (see CharacterSwitcher).
var controlled: bool = true
var health: int
var dead: bool = false
var hurt: bool = false
var hurt_id: int = 0
var attacking: bool = false
var blocking: bool = false
var current_attack: String = ""
var attack_id: int = 0
var hit_targets: Array = []

var base_modulate: Color = Color.WHITE
var flash_tween: Tween

# --- Input action names (filled in by _setup_actions) ---
var act_up: String
var act_down: String
var act_left: String
var act_right: String
var act_attack1: String
var act_attack2: String
var act_attack3: String

# --- Nodes ---
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var attack_area: Area2D = $AttackArea
@onready var barrier: AnimatedSprite2D = $Barrier
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var healthbar: Node = get_node_or_null("Healthbar")  # optional


# =========================================================
# READY
# =========================================================

func _ready() -> void:
	add_to_group("players")
	call_deferred("_ignore_other_players")

	# Top-down game: Floating stops bodies being carried along like moving platforms
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING

	player_id = _detect_player_id()

	_setup_actions()

	if not InputMap.has_action(act_up):
		push_warning("Input action '%s' doesn't exist. Add the PlayerInput autoload (player_input.gd) or create the actions in the Input Map." % act_up)

	health = max_health
	dead = false
	hurt = false
	attacking = false
	blocking = false

	if healthbar != null:
		healthbar.init_health(health)

	base_modulate = animated_sprite.modulate

	attack_area.monitoring = false
	barrier.visible = false
	collision_shape.set_deferred("disabled", false)

	update_attack_area_direction()

	print("KNIGHT READY | PLAYER ID: ", player_id, " | HP: ", health)
	print("ANIMATIONS: ", animated_sprite.sprite_frames.get_animation_names())


func _detect_player_id() -> int:
	# Reads the number from the parent node name: Player1, Player2, Player3 or Player4
	var parent_name: String = String(get_parent().name)

	if parent_name.begins_with("Player") and parent_name.substr(6).is_valid_int():
		return clampi(parent_name.substr(6).to_int(), 1, 4)

	push_warning("%s is not under Player1 - Player4 (parent: %s), using Player 1 controls." % [name, parent_name])
	return 0


# Called by CharacterSwitcher. 1-4 = controlled by that player's input.
# 0 = nobody controls this character: it just stands there.
func set_controller(new_id: int) -> void:
	player_id = new_id
	controlled = new_id >= 1
	_setup_actions()


func _setup_actions() -> void:
	var prefix: String = "p%d_" % maxi(player_id, 1)

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

func _restart_animation(anim_name: String) -> void:
	animated_sprite.stop()
	animated_sprite.animation = anim_name
	animated_sprite.frame = 0
	animated_sprite.play()


func _clear_combat_state() -> void:
	attack_id += 1
	attacking = false
	blocking = false
	current_attack = ""
	velocity = Vector2.ZERO
	attack_area.monitoring = false
	barrier.visible = false
	barrier.stop()


func update_attack_area_direction() -> void:
	attack_area.position.x = -abs(attack_area_distance) if animated_sprite.flip_h else abs(attack_area_distance)


# Runs deferred, so every character in the scene is already in the "players"
# group no matter which one is ready first.
func _ignore_other_players() -> void:
	if not players_ignore_each_other:
		return

	for other in get_tree().get_nodes_in_group("players"):
		if other == self or not other is PhysicsBody2D:
			continue

		add_collision_exception_with(other)
		other.add_collision_exception_with(self)


func flash_red() -> void:
	if flash_tween:
		flash_tween.kill()

	animated_sprite.modulate = hit_flash_color

	flash_tween = create_tween()
	flash_tween.tween_property(animated_sprite, "modulate", base_modulate, hit_flash_time)


# =========================================================
# PHYSICS
# =========================================================

func _physics_process(_delta: float) -> void:
	if dead or hurt:
		velocity = Vector2.ZERO
		return

	if blocking or attacking:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	# Nobody controls this character right now.
	if not controlled:
		velocity = Vector2.ZERO
		if animated_sprite.animation != "idle":
			animated_sprite.play("idle")
		return

	var direction := Input.get_vector(act_left, act_right, act_up, act_down)

	velocity = direction * speed
	move_and_slide()

	if direction.x != 0:
		animated_sprite.flip_h = direction.x < 0
		update_attack_area_direction()

	var wanted_anim := "walk" if direction != Vector2.ZERO else "idle"
	if animated_sprite.animation != wanted_anim:
		animated_sprite.play(wanted_anim)

	if Input.is_action_just_pressed(act_attack1):
		start_attack("attack1")
	elif Input.is_action_just_pressed(act_attack2):
		start_attack("attack2")
	elif Input.is_action_just_pressed(act_attack3):
		start_block()


# =========================================================
# ATTACKS
# =========================================================

func _attack_alive(id: int) -> bool:
	return is_inside_tree() and not dead and not hurt and id == attack_id


func start_attack(attack_name: String) -> void:
	if attacking or blocking or hurt or dead:
		return

	attack_id += 1
	var my_id: int = attack_id

	hit_targets.clear()
	attacking = true
	current_attack = attack_name
	velocity = Vector2.ZERO

	update_attack_area_direction()
	attack_area.monitoring = false

	_restart_animation(attack_name)

	if attack_name == "attack1":
		attack_area.monitoring = true

	await get_tree().physics_frame

	if not _attack_alive(my_id):
		return

	if attack_name == "attack1":
		await _melee_window(my_id)

		if not _attack_alive(my_id):
			return
	elif attack_name == "attack2":
		await wait_for_slash_frame(my_id)

		if not _attack_alive(my_id):
			return

		fire_slash()

	await animated_sprite.animation_finished

	if not _attack_alive(my_id):
		return

	attacking = false
	current_attack = ""
	attack_area.monitoring = false
	animated_sprite.play("idle")


# Checks the sword area over several physics frames. Area2D overlaps only
# update after a physics step, so a single check right after enabling the
# area can miss enemies that are standing inside it.
func _melee_window(id: int) -> void:
	var last_frame: int = animated_sprite.sprite_frames.get_frame_count("attack1") - 1
	var target_frame: int = mini(attack1_hit_frame, last_frame)

	while animated_sprite.frame < target_frame:
		await animated_sprite.frame_changed

		if not _attack_alive(id):
			return

	var time_left: float = attack1_hit_window

	while time_left > 0.0:
		do_melee_damage()
		await get_tree().physics_frame

		if not _attack_alive(id):
			return

		time_left -= get_physics_process_delta_time()


func do_melee_damage() -> void:
	# Two ways to find targets, so a swing does not depend on collision timing:
	# the AttackArea overlaps, plus a simple box test in front of the knight
	# against every enemy.
	var candidates: Array = attack_area.get_overlapping_bodies()

	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not candidates.has(enemy) and _in_melee_box(enemy):
			candidates.append(enemy)

	for body in candidates:
		if body == self:
			continue
		if not body.is_in_group("enemies"):
			continue
		if "dead" in body and body.dead:
			continue
		if body in hit_targets:
			continue
		if not body.has_method("take_damage"):
			continue

		hit_targets.append(body)
		body.take_damage(attack1_damage)


func _in_melee_box(enemy) -> bool:
	if not is_instance_valid(enemy) or not (enemy is Node2D):
		return false

	var offset: Vector2 = enemy.global_position - global_position
	var facing: float = -1.0 if animated_sprite.flip_h else 1.0
	var forward: float = offset.x * facing

	return forward >= -attack1_behind and forward <= attack1_reach and absf(offset.y) <= attack1_height * 0.5


func wait_for_slash_frame(id: int) -> void:
	# Never wait for a frame the animation doesn't have
	var last_frame: int = animated_sprite.sprite_frames.get_frame_count("attack2") - 1
	var target_frame: int = mini(slash_release_frame, last_frame)

	while animated_sprite.frame < target_frame:
		await animated_sprite.frame_changed

		if not _attack_alive(id):
			return


func fire_slash() -> void:
	if slash_scene == null:
		print("ERROR: SLASH SCENE IS NOT ASSIGNED")
		return

	var slash = slash_scene.instantiate()
	var container: Node = get_parent().get_parent()

	if container == null:
		container = get_tree().current_scene

	container.add_child(slash)

	var facing_direction := -1.0 if animated_sprite.flip_h else 1.0

	slash.global_position = global_position + Vector2(facing_direction * 35.0, 0)
	slash.direction = Vector2(facing_direction, 0)

	if facing_direction < 0:
		slash.scale.x = -1


# =========================================================
# BLOCK
# =========================================================

func start_block() -> void:
	if attacking or blocking or hurt or dead:
		return

	attack_id += 1
	var my_id: int = attack_id

	blocking = true
	velocity = Vector2.ZERO
	attack_area.monitoring = false

	_restart_animation("attack3")

	barrier.visible = true
	barrier.play()

	await animated_sprite.animation_finished

	if not _attack_alive(my_id):
		return

	# Hold the last frame of the block animation
	animated_sprite.stop()
	animated_sprite.frame = animated_sprite.sprite_frames.get_frame_count("attack3") - 1

	await get_tree().create_timer(block_duration).timeout

	if not _attack_alive(my_id):
		return

	blocking = false
	barrier.visible = false
	barrier.stop()
	animated_sprite.play("idle")


# =========================================================
# DAMAGE / DEATH / RESPAWN
# =========================================================

func _update_healthbar() -> void:
	health_changed.emit(health, max_health)

	if healthbar != null:
		healthbar.health = health


# Public: heal effects and any future healing source should call this, so the
# health bar and signals stay in sync. Returns how much was really healed.
func heal(amount: int) -> int:
	if dead or amount <= 0:
		return 0

	var old_health: int = health
	health = mini(health + amount, max_health)
	_update_healthbar()

	return health - old_health


# Damage never interrupts movement or attacks. Pass do_stagger = true (or call
# stagger()) for enemy attacks that should.
func take_damage(damage: int, do_stagger: bool = false) -> void:
	if dead:
		return

	var was_blocking := blocking

	if was_blocking:
		damage = int(damage * (1.0 - block_damage_reduction))
		print("KNIGHT BLOCKED! REDUCED DAMAGE: ", damage)

	health = max(health - damage, 0)
	print("KNIGHT HP: ", health, "/", max_health)
	_update_healthbar()

	# Red flash, even while attacking or blocking (skipped if fully blocked)
	if damage > 0:
		flash_red()

	if health <= 0:
		die()
		return

	# The shield absorbs stagger too
	if do_stagger and not was_blocking:
		stagger()


func stagger(duration: float = 0.0) -> void:
	if dead or stagger_immune or blocking:
		return

	hurt = true
	hurt_id += 1
	var my_hurt: int = hurt_id

	_clear_combat_state()
	_restart_animation("hurt")

	if duration > 0.0:
		await get_tree().create_timer(duration).timeout
	else:
		await animated_sprite.animation_finished

	if dead or my_hurt != hurt_id:
		return

	hurt = false
	animated_sprite.play("idle")


func die() -> void:
	if dead:
		return

	dead = true
	hurt = false
	hurt_id += 1
	_clear_combat_state()

	collision_shape.set_deferred("disabled", true)
	_restart_animation("death")

	print("KNIGHT DIED")
	died.emit(self)

	await animated_sprite.animation_finished
	await get_tree().create_timer(respawn_time).timeout

	if not is_inside_tree():
		return

	respawn()


func respawn() -> void:
	health = max_health
	_update_healthbar()
	dead = false
	hurt = false
	hurt_id += 1
	_clear_combat_state()

	if flash_tween:
		flash_tween.kill()
	animated_sprite.modulate = base_modulate

	collision_shape.set_deferred("disabled", false)
	animated_sprite.play("idle")

	print("KNIGHT RESPAWNED | PLAYER ID: ", player_id, " | HP: ", health)
