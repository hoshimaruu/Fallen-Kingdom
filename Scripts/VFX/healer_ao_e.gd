extends Area2D

@export var damage: int = 10
@export var radius: float = 90.0

@export var effect_animation: StringName = &"default"
@export var active_start_frame: int = 2
@export var active_end_frame: int = 5

# When true, enemies that have a stagger() method are interrupted and play their hurt animation.
@export var stagger: bool = false

var hit_targets: Array[Node] = []
var active: bool = false
var finished: bool = false

# active_start_frame / active_end_frame limited to the frames the animation really has
var first_active_frame: int = 0
var last_active_frame: int = 0

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	# Player attack collision
	collision_layer = 4
	collision_mask = 2

	monitoring = true
	monitorable = true

	if collision_shape.shape == null:
		# The scene's CollisionShape2D has no shape assigned, so create one
		var circle := CircleShape2D.new()
		circle.radius = radius
		collision_shape.shape = circle
		print("[HEALER AOE] CollisionShape2D had no shape, created a CircleShape2D (radius ", radius, ")")
	elif collision_shape.shape is CircleShape2D:
		# Duplicate so changing the radius doesn't affect the scene's shared resource
		collision_shape.shape = collision_shape.shape.duplicate()
		(collision_shape.shape as CircleShape2D).radius = radius
	else:
		print("[HEALER AOE] CollisionShape2D uses a ", collision_shape.shape.get_class(),
			", its radius setting is ignored (the radius check below still applies).")

	# The hitbox only turns on during the active frames
	collision_shape.set_deferred("disabled", true)

	var frames := animated_sprite.sprite_frames
	if frames == null or frames.get_animation_names().is_empty():
		push_error("[HEALER AOE] No SpriteFrames assigned.")
		queue_free()
		return

	if not frames.has_animation(effect_animation):
		effect_animation = frames.get_animation_names()[0]

	# An active frame past the end of the animation would never be reached (= no damage ever)
	var last_frame: int = frames.get_frame_count(effect_animation) - 1
	first_active_frame = mini(active_start_frame, last_frame)
	last_active_frame = maxi(first_active_frame, mini(active_end_frame, last_frame))

	# Play once, then disappear
	frames.set_animation_loop(effect_animation, false)
	animated_sprite.animation = effect_animation
	animated_sprite.frame = 0

	body_entered.connect(_try_hit)
	animated_sprite.animation_finished.connect(_on_animation_finished)

	animated_sprite.play()

	print("[HEALER AOE] STARTED | DAMAGE: ", damage, " | RADIUS: ", radius, " | SCALE: ", scale.x,
		" | ANIMATION: ", effect_animation, " (", last_frame + 1, " frames)",
		" | ACTIVE FRAMES: ", first_active_frame, "-", last_active_frame)


func _physics_process(_delta: float) -> void:
	if finished:
		return

	var frame := animated_sprite.frame
	var should_be_active := frame >= first_active_frame and frame <= last_active_frame

	if should_be_active != active:
		active = should_be_active
		collision_shape.set_deferred("disabled", not active)

		if active:
			print("[HEALER AOE] ACTIVE | HIT RADIUS: ", _hit_radius(),
				" | ENEMIES IN GROUP: ", get_tree().get_nodes_in_group("enemies").size())
		else:
			print("[HEALER AOE] INACTIVE")

	if not active:
		return

	# 1) Bodies the physics engine reports inside the hitbox
	for body in get_overlapping_bodies():
		_try_hit(body)

	# 2) Enemies inside the radius. This doesn't depend on collision layers or on the
	#    hitbox having been switched on yet, so a nearby enemy can't be missed.
	var hit_radius := _hit_radius()

	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy is Node2D and global_position.distance_to((enemy as Node2D).global_position) <= hit_radius:
			_try_hit(enemy)


# The real radius in pixels (the effect can be scaled up by the Healer)
func _hit_radius() -> float:
	return radius * maxf(absf(scale.x), absf(scale.y))


func _try_hit(body: Node) -> void:
	if finished or not active:
		return
	if not is_instance_valid(body):
		return
	if body.is_in_group("players"):
		return
	if not body.is_in_group("enemies"):
		return
	if body in hit_targets:
		return
	if not body.has_method("take_damage"):
		return
	if body.get("dead") == true:
		return

	# Each enemy is hit once per AoE
	hit_targets.append(body)
	body.take_damage(damage)

	# Interrupt the enemy and play its hurt animation (skipped if the damage killed it)
	if stagger and is_instance_valid(body) and body.has_method("stagger"):
		body.call("stagger")

	print("[HEALER AOE] HIT ", body.name, " FOR ", damage, " | STAGGER: ", stagger)


func _on_animation_finished() -> void:
	if finished:
		return

	finished = true
	active = false

	collision_shape.set_deferred("disabled", true)
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)

	if hit_targets.is_empty():
		print("[HEALER AOE] FINISHED WITHOUT HITTING ANYONE")
	else:
		print("[HEALER AOE] FINISHED | HIT ", hit_targets.size())

	queue_free()
