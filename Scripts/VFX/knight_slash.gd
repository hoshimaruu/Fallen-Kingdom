extends Area2D


# =========================================================
# SETTINGS
# =========================================================

@export var speed: float = 450.0
@export var damage: int = 15
@export var max_distance: float = 350.0


# =========================================================
# VARIABLES
# =========================================================

var direction: Vector2 = Vector2.RIGHT
var distance_traveled: float = 0.0


# =========================================================
# READY
# =========================================================

func _ready():

	print("================================")
	print("SLASH READY")
	print("LAYER:", collision_layer)
	print("MASK:", collision_mask)
	print("MONITORING:", monitoring)
	print("MONITORABLE:", monitorable)
	print("================================")


	body_entered.connect(_on_body_entered)


# =========================================================
# MOVEMENT
# =========================================================

func _physics_process(delta):

	var movement = direction * speed * delta

	global_position += movement

	distance_traveled += movement.length()


	if distance_traveled >= max_distance:

		print("SLASH REACHED MAX DISTANCE")

		queue_free()


# =========================================================
# HIT
# =========================================================

func _on_body_entered(body):

	print("SLASH DETECTED:", body.name)


	# Ignore anything that isn't an enemy.
	if not body.is_in_group("enemies"):

		print("SLASH IGNORED:", body.name)

		return


	print("SLASH HIT ENEMY:", body.name)


	if body.has_method("take_damage"):

		body.take_damage(damage)

		print("SLASH DAMAGE:", damage)


	queue_free()
