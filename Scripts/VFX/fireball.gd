extends Area2D

@export var speed: float = 400.0
@export var damage: int = 20
@export var max_distance: float = 500.0
@export var explosion_start_frame: int = 4
@export var size_multiplier: float = 1.4
@export var faces_right: bool = true   # untick if your fireball art is drawn facing LEFT

var direction: Vector2 = Vector2.RIGHT
var distance_traveled: float = 0.0
var hit: bool = false
var exploding: bool = false

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	collision_layer = 4
	collision_mask = 2

	monitoring = true
	monitorable = true

	scale *= size_multiplier

	body_entered.connect(_on_body_entered)
	animated_sprite.frame_changed.connect(_on_frame_changed)
	animated_sprite.animation_finished.connect(_on_animation_finished)

	# Looping is handled in code: frames before the explosion loop while flying,
	# then the animation plays to the end once to finish the explosion
	animated_sprite.sprite_frames.set_animation_loop("Fireball", false)
	animated_sprite.animation = "Fireball"
	animated_sprite.frame = 0
	animated_sprite.play()

	_apply_facing()

	print("FIREBALL READY | DAMAGE: %d | SPEED: %s | RANGE: %s | SIZE: %s | LAYER: %d | MASK: %d" % [
		damage, speed, max_distance, size_multiplier, collision_layer, collision_mask
	])


func setup(new_direction: Vector2, new_damage: int) -> void:
	direction = new_direction.normalized()
	damage = new_damage

	_apply_facing()


# Flips the WHOLE fireball (sprite + hitbox) so both face the way it flies
func _apply_facing() -> void:
	var face_left := direction.x < 0.0

	if not faces_right:
		face_left = not face_left

	scale.x = -abs(scale.x) if face_left else abs(scale.x)


func _physics_process(delta: float) -> void:
	if hit or exploding:
		return

	var movement := direction * speed * delta

	global_position += movement
	distance_traveled += movement.length()

	if distance_traveled >= max_distance:
		start_explosion()


# While flying, never show the explosion frames
func _on_frame_changed() -> void:
	if not exploding and animated_sprite.frame >= explosion_start_frame:
		animated_sprite.frame = 0


func _on_animation_finished() -> void:
	if not exploding:
		animated_sprite.frame = 0
		animated_sprite.play()


func _on_body_entered(body: Node) -> void:
	if hit or exploding:
		return

	# Never damage players
	if body.is_in_group("players"):
		return

	if body.is_in_group("enemies"):
		if body.has_method("take_damage"):
			hit = true
			body.take_damage(damage)
			print("FIREBALL HIT ENEMY: %s | DAMAGE: %d" % [body.name, damage])
		else:
			print("ERROR: ENEMY HAS NO take_damage(): ", body.name)
	else:
		print("FIREBALL HIT OBSTACLE: ", body.name)

	start_explosion()


func start_explosion() -> void:
	if exploding:
		return

	exploding = true
	direction = Vector2.ZERO

	# Deferred: changing these during a physics callback is not allowed
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	collision_shape.set_deferred("disabled", true)

	animated_sprite.stop()
	animated_sprite.animation = "Fireball"
	animated_sprite.frame = explosion_start_frame
	animated_sprite.play()

	print("FIREBALL EXPLOSION")

	await animated_sprite.animation_finished

	print("FIREBALL DESTROYED")

	queue_free()
