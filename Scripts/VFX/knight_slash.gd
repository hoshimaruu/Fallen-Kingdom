extends Area2D

@export var speed: float = 450.0
@export var damage: int = 15
@export var max_distance: float = 350.0

# --- Piercing ---
# true = the slash keeps flying through enemies and hits each one once.
@export var pierce: bool = true
# 0 = unlimited. Otherwise it disappears after hitting this many enemies.
@export var max_pierce_hits: int = 0

# --- Burning ---
@export var burn_enabled: bool = true
@export var burn_damage: int = 3
@export var burn_interval: float = 0.5   # seconds between burn ticks
@export var burn_duration: float = 3.0   # total burn time

var direction: Vector2 = Vector2.RIGHT
var distance_traveled: float = 0.0
var oriented: bool = false

# Enemies this slash already hit, so each one is only hit once.
var hit_ids: Array = []

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
	if not body.is_in_group("enemies"):
		return

	if "dead" in body and body.dead:
		return

	if not body.has_method("take_damage"):
		return

	var body_id: int = body.get_instance_id()

	if hit_ids.has(body_id):
		return

	hit_ids.append(body_id)

	body.take_damage(damage)
	print("[SLASH] HIT %s | DAMAGE: %d" % [body.name, damage])

	if burn_enabled:
		StatusEffects.apply_burn(body, burn_damage, burn_interval, burn_duration)

	# Stop at the first enemy only when piercing is off (or the limit is reached).
	if not pierce or (max_pierce_hits > 0 and hit_ids.size() >= max_pierce_hits):
		queue_free()
