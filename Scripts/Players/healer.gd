extends CharacterBody2D

# Emitted for HUDs, cameras and score keeping.
signal health_changed(current: int, maximum: int)
signal died(character)

# =========================================================
# MOVEMENT / HEALTH
# =========================================================

@export var speed: float = 180.0
@export var max_health: int = 100
@export var respawn_time: float = 3.0

# =========================================================
# ATTACK 1: TARGETED AOE
# =========================================================

@export var attack1_damage: int = 10
@export var aoe_effect_scene: PackedScene
@export var attack1_radius: float = 90.0
@export var attack1_size_multiplier: float = 1.4
@export var attack1_stagger: bool = true
@export var attack1_target_range: float = 400.0
@export var attack1_cast_frame: int = 2
@export var attack1_active_start_frame: int = 2
@export var attack1_active_end_frame: int = 5

# =========================================================
# ATTACK 2: HEAL
# =========================================================

@export var attack2_damage: int = 15
@export var heal_amount: int = 30
@export var heal_effect_scene: PackedScene
@export var heal_cast_frame: int = 2

# =========================================================
# ATTACK 3: SUMMON PALADIN
# =========================================================

@export var attack3_damage: int = 18
@export var paladin_scene: PackedScene
@export var paladin_cast_frame: int = 3
@export var paladin_lifetime: float = 15.0
@export var paladin_spawn_offset: float = 50.0
@export var paladin_cooldown: float = 20.0
@export var max_paladins: int = 1

# =========================================================
# ANIMATIONS
# =========================================================

@export var attack1_animation: StringName = &"attack1"
@export var heal_cast_animation: StringName = &"attack2"
@export var attack3_animation: StringName = &"attack3"
@export var hurt_animation: StringName = &"hurt"
@export var death_animation: StringName = &"death"
@export var idle_animation: StringName = &"idle"
@export var walk_animation: StringName = &"walk"

# =========================================================
# HIT FLASH
# =========================================================

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

# =========================================================
# STATE
# =========================================================

var player_id: int = 0
# False when no player is controlling this character (see CharacterSwitcher).
var controlled: bool = true
var health: int = 100

var dead: bool = false
var hurt: bool = false
var hurt_id: int = 0
var attacking: bool = false
var current_attack: String = ""
var attack_id: int = 0

var base_modulate: Color = Color.WHITE
var flash_tween: Tween

var last_direction: Vector2 = Vector2.RIGHT
var paladin_cooldown_remaining: float = 0.0

# Untyped on purpose: a typed array breaks when a summon was freed.
var active_paladins: Array = []

# =========================================================
# INPUT ACTIONS
# =========================================================

var act_up: String
var act_down: String
var act_left: String
var act_right: String
var act_attack1: String
var act_attack2: String
var act_attack3: String

# =========================================================
# NODES
# =========================================================

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var healthbar: Node = get_node_or_null("Healthbar")  # Added by Mortis


# =========================================================
# READY / SETUP
# =========================================================

func _ready() -> void:
	add_to_group("players")
	call_deferred("_ignore_other_players")
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING

	player_id = _detect_player_id()
	_setup_actions()
	_check_input_actions()

	health = max_health

	if healthbar != null:
		healthbar.init_health(health)

	base_modulate = animated_sprite.modulate
	collision_shape.set_deferred("disabled", false)

	for anim_name in [
		attack1_animation,
		heal_cast_animation,
		attack3_animation,
		hurt_animation,
		death_animation
	]:
		if _has_animation(anim_name):
			animated_sprite.sprite_frames.set_animation_loop(anim_name, false)

	if _has_animation(idle_animation):
		animated_sprite.play(idle_animation)

	print("HEALER READY | PLAYER ID: ", player_id, " | HP: ", health)
	print("ANIMATIONS: ", animated_sprite.sprite_frames.get_animation_names())

	if aoe_effect_scene == null:
		push_warning("Assign AoE Effect Scene in the Healer Inspector.")

	if heal_effect_scene == null:
		push_warning("Heal Effect Scene is not assigned.")

	if paladin_scene == null:
		push_warning("Assign Paladin Scene in the Healer Inspector.")


func _detect_player_id() -> int:
	var current_node: Node = self

	while current_node != null:
		var node_name: String = String(current_node.name)

		if node_name.begins_with("Player") and node_name.length() > 6:
			var id_text: String = node_name.substr(6)

			if id_text.is_valid_int():
				var detected_id: int = id_text.to_int()

				if detected_id >= 1 and detected_id <= 4:
					return detected_id

		current_node = current_node.get_parent()

	push_warning(
		"Healer '%s' could not find a Player1-Player4 ancestor. Using Player1 controls."
		% name
	)
	return 1


# Called by CharacterSwitcher. 1-4 = controlled by that player's input.
# 0 = nobody controls this character: it just stands there.
func set_controller(new_id: int) -> void:
	player_id = new_id
	controlled = new_id >= 1
	_setup_actions()


func _setup_actions() -> void:
	var prefix: String = "p%d_" % player_id

	act_up = prefix + "up"
	act_down = prefix + "down"
	act_left = prefix + "left"
	act_right = prefix + "right"
	act_attack1 = prefix + "attack1"
	act_attack2 = prefix + "attack2"
	act_attack3 = prefix + "attack3"


func _check_input_actions() -> void:
	for action_name in [
		act_up, act_down, act_left, act_right,
		act_attack1, act_attack2, act_attack3
	]:
		if not InputMap.has_action(action_name):
			push_warning(
				"Healer Player%d is missing Input Map action '%s'."
				% [player_id, action_name]
			)


# =========================================================
# HELPERS
# =========================================================

func _has_animation(anim_name: StringName) -> bool:
	return (
		animated_sprite.sprite_frames != null
		and animated_sprite.sprite_frames.has_animation(anim_name)
	)


func _restart_animation(anim_name: StringName) -> void:
	if not _has_animation(anim_name):
		push_warning("Missing Healer animation: " + str(anim_name))
		return

	animated_sprite.stop()
	animated_sprite.animation = anim_name
	animated_sprite.frame = 0
	animated_sprite.play()


func _spawn_container() -> Node:
	var container: Node = get_tree().current_scene

	if container == null:
		container = get_parent()

	return container


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
	if flash_tween and flash_tween.is_running():
		flash_tween.kill()

	animated_sprite.modulate = hit_flash_color

	flash_tween = create_tween()
	flash_tween.tween_property(
		animated_sprite,
		"modulate",
		base_modulate,
		hit_flash_time
	)


# =========================================================
# PHYSICS / INPUT
# =========================================================

func _physics_process(delta: float) -> void:
	# The cooldown keeps counting down even while dead or hurt.
	if paladin_cooldown_remaining > 0.0:
		paladin_cooldown_remaining = maxf(paladin_cooldown_remaining - delta, 0.0)

		if paladin_cooldown_remaining == 0.0:
			print("[HEALER] PALADIN SUMMON READY")

	if dead or hurt:
		velocity = Vector2.ZERO
		return

	if attacking:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	# Nobody controls this character right now.
	if not controlled:
		velocity = Vector2.ZERO
		if _has_animation(idle_animation) and animated_sprite.animation != idle_animation:
			animated_sprite.play(idle_animation)
		return

	if Input.is_action_just_pressed(act_attack1):
		start_attack1()
		return

	if Input.is_action_just_pressed(act_attack2):
		start_heal()
		return

	if Input.is_action_just_pressed(act_attack3):
		start_attack3()
		return

	var direction: Vector2 = Input.get_vector(
		act_left,
		act_right,
		act_up,
		act_down
	)

	velocity = direction * speed

	if direction != Vector2.ZERO:
		last_direction = direction.normalized()

	if direction.x != 0.0:
		animated_sprite.flip_h = direction.x < 0.0

	var wanted_animation: StringName = (
		walk_animation if direction != Vector2.ZERO else idle_animation
	)

	if _has_animation(wanted_animation):
		if (
			animated_sprite.animation != wanted_animation
			or not animated_sprite.is_playing()
		):
			animated_sprite.play(wanted_animation)

	move_and_slide()


# =========================================================
# ATTACK FLOW (shared by all three attacks)
# =========================================================

func _can_start_attack(anim_name: StringName) -> bool:
	if attacking or hurt or dead:
		return false

	if not _has_animation(anim_name):
		push_warning("Missing Healer animation: " + str(anim_name))
		return false

	return true


# Plays the animation, runs on_cast at cast_frame, then ends the attack.
func _run_attack(
	attack_name: String,
	anim_name: StringName,
	cast_frame: int,
	on_cast: Callable
) -> void:
	attacking = true
	current_attack = attack_name
	velocity = Vector2.ZERO

	attack_id += 1
	var this_attack_id: int = attack_id

	_restart_animation(anim_name)

	if not await _wait_for_frame(anim_name, cast_frame, this_attack_id):
		return

	on_cast.call()

	if not await _wait_for_animation_end(anim_name, this_attack_id):
		return

	end_attack()


func _attack_is_valid(this_attack_id: int) -> bool:
	return (
		is_inside_tree()
		and not dead
		and not hurt
		and attacking
		and attack_id == this_attack_id
	)


func _wait_for_frame(
	anim_name: StringName,
	target_frame: int,
	this_attack_id: int
) -> bool:
	var frame_count: int = animated_sprite.sprite_frames.get_frame_count(anim_name)
	target_frame = clampi(target_frame, 0, frame_count - 1)

	while animated_sprite.frame < target_frame:
		await get_tree().process_frame

		if not _attack_is_valid(this_attack_id):
			return false

		if animated_sprite.animation != anim_name:
			return false

	return _attack_is_valid(this_attack_id)


func _wait_for_animation_end(
	anim_name: StringName,
	this_attack_id: int
) -> bool:
	if animated_sprite.animation == anim_name and animated_sprite.is_playing():
		await animated_sprite.animation_finished

	return _attack_is_valid(this_attack_id)


func end_attack() -> void:
	attacking = false
	current_attack = ""
	velocity = Vector2.ZERO

	if not dead and not hurt and is_inside_tree():
		if _has_animation(idle_animation):
			animated_sprite.play(idle_animation)


func get_attack_damage() -> int:
	match current_attack:
		"attack1":
			return attack1_damage
		"attack2":
			return attack2_damage
		"attack3":
			return attack3_damage

	return 0


# =========================================================
# ATTACK 1: TARGETED AOE
# =========================================================

func start_attack1() -> void:
	if not _can_start_attack(attack1_animation):
		return

	print("PLAYER ", player_id, " HEALER AOE ATTACK")

	_run_attack(
		"attack1",
		attack1_animation,
		attack1_cast_frame,
		_spawn_aoe_on_nearest_enemy
	)


func _find_nearest_enemy() -> Node2D:
	var nearest_enemy: Node2D = null
	var nearest_distance: float = attack1_target_range

	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy) or not enemy is Node2D:
			continue

		if enemy.get("dead") == true:
			continue

		var enemy_node: Node2D = enemy as Node2D
		var offset: Vector2 = enemy_node.global_position - global_position
		var distance: float = offset.length()

		if distance > attack1_target_range:
			continue

		# Only enemies in the direction the Healer is facing.
		if distance > 0.0 and offset.normalized().dot(last_direction) <= 0.0:
			continue

		if distance < nearest_distance:
			nearest_distance = distance
			nearest_enemy = enemy_node

	return nearest_enemy


func _spawn_aoe_on_nearest_enemy() -> void:
	if aoe_effect_scene == null:
		push_warning("Assign AoE Effect Scene in the Healer Inspector.")
		return

	var target: Node2D = _find_nearest_enemy()

	if target == null:
		print("[HEALER AOE] No enemy found in front.")
		return

	var effect: Node = aoe_effect_scene.instantiate()

	# Configure BEFORE add_child, because _ready runs when it is added.
	if effect.get("damage") != null:
		effect.set("damage", attack1_damage)

	if effect.get("radius") != null:
		effect.set("radius", attack1_radius)

	if effect.get("active_start_frame") != null:
		effect.set("active_start_frame", attack1_active_start_frame)

	if effect.get("active_end_frame") != null:
		effect.set("active_end_frame", attack1_active_end_frame)

	if effect.get("stagger") != null:
		effect.set("stagger", attack1_stagger)
	elif attack1_stagger:
		push_warning("AoE effect has no stagger property.")

	if effect is Node2D:
		(effect as Node2D).scale = Vector2.ONE * attack1_size_multiplier

	_spawn_container().add_child(effect)

	if effect is Node2D:
		(effect as Node2D).global_position = target.global_position

	print(
		"[HEALER AOE] SPAWNED ON: ", target.name,
		" | DAMAGE: ", attack1_damage,
		" | HIT RADIUS: ", attack1_radius * attack1_size_multiplier
	)


# =========================================================
# ATTACK 2: HEAL TEAMMATE
# =========================================================

func start_heal() -> void:
	if not _can_start_attack(heal_cast_animation):
		return

	print("PLAYER ", player_id, " HEALER CASTING HEAL")

	_run_attack(
		"attack2",
		heal_cast_animation,
		heal_cast_frame,
		heal_other_player
	)


func heal_other_player() -> void:
	var target: Node = _find_heal_target()

	if target == null:
		print("[HEALER] No living teammate to heal.")
		return

	print(
		"[HEALER] Heal target: ", target.name,
		" | HP: ", target.get("health"), "/", target.get("max_health")
	)

	_spawn_heal_effect(target)


# Heals the living teammate with the LOWEST health percentage
# (ties go to the closest one). Never targets the Healer itself.
func _find_heal_target() -> Node:
	var best: Node = null
	var best_ratio: float = INF
	var best_distance: float = INF

	for player in get_tree().get_nodes_in_group("players"):
		if player == self or not is_instance_valid(player):
			continue

		if not player is Node2D or player.get("dead") == true:
			continue

		var player_health: Variant = player.get("health")
		var player_max: Variant = player.get("max_health")

		if player_health == null or player_max == null or int(player_max) <= 0:
			continue

		var ratio: float = float(int(player_health)) / float(int(player_max))
		var distance: float = global_position.distance_to(
			(player as Node2D).global_position
		)

		var lower_health: bool = ratio < best_ratio - 0.001
		var same_health_but_closer: bool = (
			absf(ratio - best_ratio) <= 0.001
			and distance < best_distance
		)

		if lower_health or same_health_but_closer:
			best = player
			best_ratio = ratio
			best_distance = distance

	return best


func _spawn_heal_effect(target: Node) -> void:
	# No effect scene: heal directly.
	if heal_effect_scene == null:
		if target.has_method("heal"):
			print("[HEALER] Healed teammate by ", target.call("heal", heal_amount))
		else:
			target.set("health", mini(int(target.get("health")) + heal_amount, int(target.get("max_health"))))

		return

	var effect: Node = heal_effect_scene.instantiate()

	if effect.has_method("configure"):
		effect.call("configure", target, heal_amount)
	elif effect.get("heal_amount") != null:
		effect.set("heal_amount", heal_amount)

	# Parented to the teammate so the effect follows them.
	target.add_child(effect)

	if effect is Node2D:
		(effect as Node2D).position = Vector2.ZERO

	print("[HEALER] Healing effect spawned on ", target.name)


# =========================================================
# ATTACK 3: SUMMON PALADIN
# =========================================================

func start_attack3() -> void:
	if paladin_cooldown_remaining > 0.0:
		print(
			"[HEALER] PALADIN SUMMON BLOCKED | COOLDOWN: %.1fs"
			% paladin_cooldown_remaining
		)
		return

	if paladin_scene == null:
		push_warning("Assign Paladin Scene in the Healer Inspector.")
		return

	if not _can_start_attack(attack3_animation):
		return

	print("PLAYER ", player_id, " SUMMONING PALADIN")

	_run_attack(
		"attack3",
		attack3_animation,
		paladin_cast_frame,
		_cast_paladin
	)


func _cast_paladin() -> void:
	# The cooldown only starts if the Paladin was really summoned.
	if _summon_paladin():
		paladin_cooldown_remaining = paladin_cooldown
		print("[HEALER] PALADIN COOLDOWN STARTED: %.1f seconds" % paladin_cooldown)


func _prune_paladins() -> void:
	var alive: Array = []

	for paladin in active_paladins:
		if is_instance_valid(paladin) and not paladin.is_queued_for_deletion():
			alive.append(paladin)

	active_paladins = alive


# Untyped on purpose: an expired Paladin is already freed, and a freed
# object cannot be passed to a typed parameter.
func _dismiss_paladin(paladin) -> void:
	if not is_instance_valid(paladin):
		return

	if paladin.has_method("dismiss"):
		paladin.call("dismiss")
	else:
		paladin.queue_free()


func _summon_paladin() -> bool:
	_prune_paladins()

	# Stay under the limit: the oldest Paladin leaves first.
	while active_paladins.size() >= maxi(max_paladins, 1):
		_dismiss_paladin(active_paladins.pop_front())

	var paladin_instance: Node = paladin_scene.instantiate()

	if not paladin_instance is Node2D:
		push_error("Paladin scene root must inherit Node2D.")
		paladin_instance.free()
		return false

	var paladin: Node2D = paladin_instance as Node2D

	# Configure BEFORE add_child, because _ready runs when it is added.
	paladin.set("damage", attack3_damage)
	paladin.set("lifetime", paladin_lifetime)
	paladin.set("summoner", self)

	_spawn_container().add_child(paladin)

	var facing: Vector2 = Vector2.LEFT if animated_sprite.flip_h else Vector2.RIGHT
	paladin.global_position = global_position + facing * paladin_spawn_offset

	active_paladins.append(paladin)

	print(
		"[HEALER] PALADIN SUMMONED | Damage: ", attack3_damage,
		" | Lifetime: ", paladin_lifetime,
		" | Active: ", active_paladins.size()
	)

	return true


func _clear_paladins() -> void:
	for paladin in active_paladins:
		_dismiss_paladin(paladin)

	active_paladins.clear()


# =========================================================
# DAMAGE / HURT
# =========================================================

# Damage never interrupts movement or casting. Pass do_stagger = true (or call
# stagger()) for enemy attacks that should.
func take_damage(damage: int, do_stagger: bool = false) -> void:
	if dead or damage <= 0:
		return

	health = maxi(health - damage, 0)

	print(
		"PLAYER ", player_id,
		" HEALER TOOK DAMAGE: ", damage,
		" | HP: ", health, "/", max_health
	)

	flash_red()
	_update_healthbar()

	if health <= 0:
		die()
		return

	if do_stagger:
		stagger()


func stagger(duration: float = 0.0) -> void:
	if dead or stagger_immune:
		return

	# Interrupt the current cast.
	attack_id += 1
	attacking = false
	current_attack = ""
	velocity = Vector2.ZERO

	hurt = true
	hurt_id += 1
	var my_hurt: int = hurt_id

	var has_animation: bool = _has_animation(hurt_animation)

	if has_animation:
		_restart_animation(hurt_animation)

	print("HEALER STAGGERED")

	if has_animation and duration <= 0.0:
		await animated_sprite.animation_finished
	else:
		await get_tree().create_timer(duration if duration > 0.0 else 0.3).timeout

	if dead or not is_inside_tree() or my_hurt != hurt_id:
		return

	hurt = false

	if _has_animation(idle_animation):
		animated_sprite.play(idle_animation)


# =========================================================
# DEATH / RESPAWN
# =========================================================

func die() -> void:
	if dead:
		return

	attack_id += 1
	hurt_id += 1
	dead = true
	hurt = false
	attacking = false
	current_attack = ""
	velocity = Vector2.ZERO

	_clear_paladins()
	collision_shape.set_deferred("disabled", true)

	print("PLAYER ", player_id, " HEALER DIED")
	died.emit(self)

	if _has_animation(death_animation):
		_restart_animation(death_animation)
		await animated_sprite.animation_finished

	if not is_inside_tree():
		return

	await get_tree().create_timer(respawn_time).timeout

	if not is_inside_tree():
		return

	respawn()


func respawn() -> void:
	health = max_health
	_update_healthbar()
	hurt_id += 1
	dead = false
	hurt = false
	attacking = false
	current_attack = ""
	velocity = Vector2.ZERO
	attack_id += 1

	if flash_tween and flash_tween.is_running():
		flash_tween.kill()

	animated_sprite.modulate = base_modulate
	collision_shape.set_deferred("disabled", false)

	if _has_animation(idle_animation):
		animated_sprite.play(idle_animation)

	print("HEALER RESPAWNED | PLAYER ID: ", player_id, " | HP: ", health)
