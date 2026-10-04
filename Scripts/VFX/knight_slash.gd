extends Area2D


# =========================================================
# SLASH SETTINGS
# =========================================================

@export var speed: float = 450.0

@export var damage: int = 15

# Maximum distance the slash can travel
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

	body_entered.connect(_on_body_entered)


# =========================================================
# MOVEMENT
# =========================================================

func _physics_process(delta):

	var movement = direction * speed * delta

	global_position += movement

	distance_traveled += movement.length()


	# =====================================================
	# MAXIMUM RANGE
	# =====================================================

	if distance_traveled >= max_distance:

		queue_free()


# =========================================================
# HIT SOMETHING
# =========================================================

func _on_body_entered(body):

	if body.has_method("take_damage"):

		body.take_damage(damage)

		queue_free()
