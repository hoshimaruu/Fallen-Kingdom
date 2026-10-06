extends Area2D

@export var speed: float = 325.0
@export var damage: int = 25
@export var max_distance: float = 600.0
@export var size_multiplier: float = 1.4   # heavy arrow is bigger

var direction: Vector2 = Vector2.RIGHT
var distance_traveled: float = 0.0
var hit: bool = false


func _ready() -> void:
	# Player attack collision
	collision_layer = 4
	collision_mask = 2

	monitoring = true
	monitorable = true

	scale *= size_multiplier

	body_entered.connect(_on_body_entered)

	print("ARROW 2 (HEAVY) READY | DAMAGE: %d | SPEED: %s | RANGE: %s | SCALE: %s | LAYER: %d | MASK: %d" % [
		damage, speed, max_distance, scale, collision_layer, collision_mask
	])


func setup(new_direction: Vector2, new_damage: int) -> void:
	direction = new_direction.normalized()
	damage = new_damage


func _physics_process(delta: float) -> void:
	if hit:
		return

	var movement: Vector2 = direction * speed * delta

	global_position += movement
	distance_traveled += movement.length()

	if distance_traveled >= max_distance:
		print("ARROW 2 REACHED MAX DISTANCE")
		queue_free()


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
