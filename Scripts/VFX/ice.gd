extends Area2D

@export var damage: int = 30
@export var active_start_frame: int = 2
@export var active_end_frame: int = 6
@export var size_multiplier: float = 1.3
@export var freeze_duration: float = 2.0
@export var faces_right: bool = true

var direction: Vector2 = Vector2.RIGHT
var target: Node2D = null

var hit_targets: Array = []

var active: bool = false
var finished: bool = false
var damage_dealt: bool = false

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	collision_layer = 4
	collision_mask = 18

	monitoring = true
	monitorable = true

	scale *= size_multiplier

	body_entered.connect(_on_body_entered)
	animated_sprite.animation_finished.connect(finish_ice)

	animated_sprite.sprite_frames.set_animation_loop("ice", false)

	animated_sprite.animation = "ice"
	animated_sprite.frame = 0
	animated_sprite.play()

	collision_shape.set_deferred("disabled", true)

	_apply_facing()

	print("================================")
	print("ICE READY")
	print("DAMAGE:", damage)
	print("FREEZE:", freeze_duration)
	print("ACTIVE FRAMES:", active_start_frame, "-", active_end_frame)
	print("SIZE:", size_multiplier)
	print("LAYER:", collision_layer)
	print("MASK:", collision_mask)
	print("================================")


func setup(new_direction: Vector2, new_damage: int) -> void:
	direction = new_direction.normalized()
	damage = new_damage

	_apply_facing()


func set_target(new_target: Node2D) -> void:
	target = new_target

	if is_instance_valid(target):
		print("ICE TARGET SET:", target.name)


func _apply_facing() -> void:
	var face_left: bool = direction.x < 0.0

	if not faces_right:
		face_left = not face_left

	if face_left:
		scale.x = -abs(scale.x)
	else:
		scale.x = abs(scale.x)


func _physics_process(_delta: float) -> void:
	if finished:
		return

	var current_frame: int = animated_sprite.frame

	var should_be_active: bool = (
		current_frame >= active_start_frame
		and current_frame <= active_end_frame
	)

	if should_be_active != active:
		active = should_be_active

		collision_shape.set_deferred(
			"disabled",
			not active
		)

		if active:
			print("ICE ACTIVE")
		else:
			print("ICE INACTIVE")

	if active:
		check_target()
		check_overlapping_enemies()


func check_target() -> void:
	if damage_dealt:
		return

	if target == null:
		return

	if not is_instance_valid(target):
		return

	if not target.is_inside_tree():
		return

	if "dead" in target and target.dead:
		return

	var distance: float = global_position.distance_to(
		target.global_position
	)

	if distance <= 90.0:
		hit_enemy(target)


func check_overlapping_enemies() -> void:
	if not active:
		return

	if damage_dealt:
		return

	for body in get_overlapping_bodies():
		_on_body_entered(body)

		if damage_dealt:
			return


func _on_body_entered(body: Node) -> void:
	if finished:
		return

	if not active:
		return

	if damage_dealt:
		return

	if body.is_in_group("players"):
		return

	if not body.is_in_group("enemies"):
		return

	hit_enemy(body)


func hit_enemy(enemy: Node) -> void:
	if damage_dealt:
		return

	if enemy == null:
		return

	if not is_instance_valid(enemy):
		return

	if enemy in hit_targets:
		return

	if "dead" in enemy and enemy.dead:
		return

	hit_targets.append(enemy)

	damage_dealt = true

	print("================================")
	print("ICE HIT ENEMY:", enemy.name)
	print("DAMAGE:", damage)
	print("FREEZE:", freeze_duration)
	print("================================")

	if enemy.has_method("take_damage"):
		enemy.take_damage(damage)

	if enemy.has_method("apply_freeze"):
		enemy.apply_freeze(freeze_duration)
	else:
		print(
			"WARNING: ",
			enemy.name,
			"does not have apply_freeze()"
		)


func finish_ice() -> void:
	if finished:
		return

	finished = true
	active = false

	collision_shape.set_deferred("disabled", true)

	set_deferred("monitoring", false)
	set_deferred("monitorable", false)

	print("ICE FINISHED")

	queue_free()
