extends Area2D

@export var speed: float = 325.0
@export var damage: int = 25
@export var max_distance: float = 600.0
@export var size_multiplier: float = 2.0

# --- Wind / afterimage trail ---
@export var wind_effect: bool = true
@export var wind_interval: float = 0.035
@export var wind_fade_time: float = 0.25
@export var wind_scale: float = 1.0
@export var wind_alpha: float = 0.35
@export var wind_color: Color = Color(0.7, 0.9, 1.0, 1.0)

var direction: Vector2 = Vector2.RIGHT
var distance_traveled: float = 0.0
var hit: bool = false
var wind_timer: float = 0.0

# The arrow's visible sprite (found automatically, Sprite2D or AnimatedSprite2D)
var sprite_node: Sprite2D = null
var anim_node: AnimatedSprite2D = null


func _ready() -> void:
	# Player attack collision
	collision_layer = 4
	collision_mask = 2

	monitoring = true
	monitorable = true

	scale *= size_multiplier

	_find_visual()

	body_entered.connect(_on_body_entered)

	print("ARROW 2 (HEAVY) READY | DAMAGE: %d | SPEED: %s | RANGE: %s | SCALE: %s | LAYER: %d | MASK: %d" % [
		damage, speed, max_distance, scale, collision_layer, collision_mask
	])

	if wind_effect and sprite_node == null and anim_node == null:
		print("ARROW 2 WARNING: no Sprite2D / AnimatedSprite2D child found, wind trail disabled")


func _find_visual() -> void:
	for child in get_children():
		if child is Sprite2D:
			sprite_node = child
			return
		if child is AnimatedSprite2D:
			anim_node = child
			return


func setup(new_direction: Vector2, new_damage: int) -> void:
	direction = new_direction.normalized()
	damage = new_damage


func _physics_process(delta: float) -> void:
	if hit:
		return

	var movement: Vector2 = direction * speed * delta

	global_position += movement
	distance_traveled += movement.length()

	if wind_effect:
		wind_timer -= delta

		if wind_timer <= 0.0:
			spawn_wind_effect()
			wind_timer = wind_interval

	if distance_traveled >= max_distance:
		print("ARROW 2 REACHED MAX DISTANCE")
		queue_free()


func spawn_wind_effect() -> void:
	var ghost := Sprite2D.new()
	var source: Node2D

	# Copy whatever the arrow is currently showing
	if sprite_node != null:
		if sprite_node.texture == null:
			return

		source = sprite_node
		ghost.texture = sprite_node.texture
		ghost.hframes = sprite_node.hframes
		ghost.vframes = sprite_node.vframes
		ghost.frame = sprite_node.frame
		ghost.region_enabled = sprite_node.region_enabled
		ghost.region_rect = sprite_node.region_rect
		ghost.centered = sprite_node.centered
		ghost.offset = sprite_node.offset
		ghost.flip_h = sprite_node.flip_h
		ghost.flip_v = sprite_node.flip_v

	elif anim_node != null:
		var texture := anim_node.sprite_frames.get_frame_texture(anim_node.animation, anim_node.frame)

		if texture == null:
			return

		source = anim_node
		ghost.texture = texture
		ghost.centered = anim_node.centered
		ghost.offset = anim_node.offset
		ghost.flip_h = anim_node.flip_h
		ghost.flip_v = anim_node.flip_v

	else:
		ghost.queue_free()
		return

	ghost.modulate = Color(wind_color.r, wind_color.g, wind_color.b, wind_alpha)

	# Add next to the arrow, drawn just behind it
	var parent := get_parent()
	parent.add_child(ghost)
	parent.move_child(ghost, get_index())

	# Same position, rotation, size and facing as the arrow's sprite
	ghost.global_transform = source.global_transform
	ghost.scale *= wind_scale

	# Fade out while stretching along the flight direction and thinning out
	var end_scale := Vector2(ghost.scale.x * 1.4, ghost.scale.y * 0.5)

	var tween := ghost.create_tween()
	tween.set_parallel(true)
	tween.tween_property(ghost, "modulate:a", 0.0, wind_fade_time)
	tween.tween_property(ghost, "scale", end_scale, wind_fade_time)
	tween.chain().tween_callback(ghost.queue_free)


func _on_body_entered(body: Node) -> void:
	# Never hit players (or hit twice)
	if hit or body.is_in_group("players"):
		return

	hit = true

	if body.is_in_group("enemies"):
		if body.has_method("take_damage"):
			body.take_damage(damage)
			print("ARROW 2 HIT ENEMY: %s | DAMAGE: %d" % [body.name, damage])
		else:
			print("ERROR: ENEMY HAS NO take_damage(): ", body.name)
	else:
		print("ARROW 2 HIT OBSTACLE: ", body.name)

	queue_free()
