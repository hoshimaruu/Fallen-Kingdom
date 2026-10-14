extends Node2D

@export var heal_amount: int = 30
@export var effect_animation: StringName = &"default"
@export var heal_frame: int = 1

var target: Node2D
var finished: bool = false
var healing_applied: bool = false

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D


# The Healer calls this BEFORE adding the effect to the scene.
func configure(new_target: Node2D, amount: int) -> void:
	target = new_target
	heal_amount = amount


func _ready() -> void:
	var frames := animated_sprite.sprite_frames
	if frames == null or frames.get_animation_names().is_empty():
		push_error("[HEAL EFFECT] No SpriteFrames assigned.")
		queue_free()
		return

	if not frames.has_animation(effect_animation):
		effect_animation = frames.get_animation_names()[0]

	# Never wait for a frame the animation doesn't have
	heal_frame = mini(heal_frame, frames.get_frame_count(effect_animation) - 1)

	# Play once, then disappear
	frames.set_animation_loop(effect_animation, false)
	animated_sprite.animation = effect_animation
	animated_sprite.frame = 0

	animated_sprite.animation_finished.connect(_on_animation_finished)
	animated_sprite.play()

	print("[HEAL EFFECT] STARTED ON ", target.name if is_instance_valid(target) else "(no target yet)")


func _process(_delta: float) -> void:
	if finished or healing_applied:
		return

	# No target (configure() was never called, or the target was freed)
	if not is_instance_valid(target):
		queue_free()
		return

	if animated_sprite.frame >= heal_frame:
		apply_healing()


func apply_healing() -> void:
	if healing_applied:
		return

	healing_applied = true

	if not is_instance_valid(target):
		return

	if target.get("dead") == true:
		print("[HEAL EFFECT] TARGET IS DEAD")
		return

	var current_health: Variant = target.get("health")
	var maximum_health: Variant = target.get("max_health")

	if current_health == null or maximum_health == null:
		push_warning("[HEAL EFFECT] Target has no health properties.")
		return

	var old_health := int(current_health)
	var new_health := mini(old_health + heal_amount, int(maximum_health))

	target.set("health", new_health)

	print(
		"[HEAL EFFECT] ", target.name,
		" HEALED: ", new_health - old_health,
		" | HP: ", new_health, "/", int(maximum_health)
	)


func _on_animation_finished() -> void:
	# Safety net: if the heal frame was somehow never reached, heal now
	if not healing_applied:
		apply_healing()

	finished = true
	queue_free()
