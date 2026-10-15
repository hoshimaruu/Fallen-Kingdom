extends Area2D

@export var speed: float = 450.0
@export var damage: int = 15
@export var max_distance: float = 350.0

var direction: Vector2 = Vector2.RIGHT
var distance_traveled: float = 0.0
var has_hit: bool = false
var oriented: bool = false

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	# Same layers as the arrows: slash is on layer 4 and hits enemies (layer 2).
	collision_layer = 4
	collision_mask = 2

	body_entered.connect(_on_body_entered)

	if animated_sprite != null and animated_sprite.sprite_frames != null:
		# Keep the 5-frame slash looping for as long as it is flying.
		animated_sprite.sprite_frames.set_animation_loop("default", true)
		animated_sprite.play("default")
	else:
		push_warning("[SLASH] AnimatedSprite2D or SpriteFrames is missing.")


# Optional helper so the knight can call slash.setup(dir, dmg).
func setup(new_direction: Vector2, new_damage: int) -> void:
	direction = new_direction.normalized()
	damage = new_damage
	_orient()


func _orient() -> void:
	# Direction is usually assigned AFTER add_child, so this runs on the
	# first physics frame as well. It sets scale instead of toggling it,
	# so it is safe even if the knight also sets slash.scale.x = -1.
	scale.x = -1.0 if direction.x < 0.0 else 1.0
	oriented = true


func _physics_process(delta: float) -> void:
	if not oriented:
		_orient()

	var movement := direction * speed * delta
	global_position += movement
	distance_traveled += movement.length()

	if distance_traveled >= max_distance:
		queue_free()


func _on_body_entered(body: Node) -> void:
	if has_hit:
		return

	if not body.is_in_group("enemies"):
		return

	if "dead" in body and body.dead:
		return

	if body.has_method("take_damage"):
		has_hit = true
		body.take_damage(damage)
		print("[SLASH] HIT %s | DAMAGE: %d" % [body.name, damage])
		queue_free()
