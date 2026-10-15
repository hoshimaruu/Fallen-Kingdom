extends Node2D

# Root node of the summon scene: Node2D
# Child: AnimatedSprite2D with animations
#   idle    (looping)       required
#   walk    (looping)       optional, falls back to idle
#   attack  (not looping)   required for hits, falls back to instant hit
#   spawn   (not looping)   optional, plays once when summoned
#   death   (not looping)   optional, plays when time runs out, else it fades

@export var damage: int = 12
@export var lifetime: float = 12.0
@export var move_speed: float = 140.0
@export var detect_range: float = 350.0
@export var attack_range: float = 45.0
@export var attack_interval: float = 1.0
@export var attack_hit_frame: int = 2
@export var follow_distance: float = 70.0
@export var retarget_time: float = 0.25

var summoner: Node2D
var target: Node2D
var attacking: bool = false
var leaving: bool = false
var attack_timer: float = 0.0
var retarget_timer: float = 0.0

@onready var sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")


func _ready() -> void:
	add_to_group("summons")

	if sprite == null or sprite.sprite_frames == null:
		push_warning("[SUMMON] Needs an AnimatedSprite2D child with SpriteFrames.")
		return

	for anim in ["spawn", "attack", "death"]:
		if sprite.sprite_frames.has_animation(anim):
			sprite.sprite_frames.set_animation_loop(anim, false)

	for anim in ["idle", "walk"]:
		if sprite.sprite_frames.has_animation(anim):
			sprite.sprite_frames.set_animation_loop(anim, true)

	_intro()


func _intro() -> void:
	if _play("spawn", true):
		attacking = true
		await sprite.animation_finished

		if leaving or not is_inside_tree():
			return

		attacking = false

	_play("idle")


func _process(delta: float) -> void:
	if leaving:
		return

	lifetime -= delta

	if lifetime <= 0.0:
		dismiss()
		return

	attack_timer = maxf(attack_timer - delta, 0.0)

	if attacking:
		return

	retarget_timer -= delta

	if retarget_timer <= 0.0 or not _valid_target(target):
		retarget_timer = retarget_time
		target = _find_target()

	if target != null:
		var to_target: Vector2 = target.global_position - global_position
		_face(to_target.x)

		if to_target.length() > attack_range:
			_move(to_target.normalized(), delta)
		elif attack_timer <= 0.0:
			_attack(target)
		else:
			_play("idle")
	else:
		_follow_summoner(delta)


# =========================================================
# TARGETING / MOVEMENT
# =========================================================

func _valid_target(node: Node2D) -> bool:
	if node == null or not is_instance_valid(node):
		return false

	if "dead" in node and node.dead:
		return false

	return true


func _find_target() -> Node2D:
	var nearest: Node2D = null
	var nearest_distance: float = detect_range

	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not enemy is Node2D or not _valid_target(enemy):
			continue

		var distance: float = global_position.distance_to(enemy.global_position)

		if distance <= nearest_distance:
			nearest_distance = distance
			nearest = enemy

	return nearest


func _follow_summoner(delta: float) -> void:
	if summoner == null or not is_instance_valid(summoner):
		_play("idle")
		return

	var to_owner: Vector2 = summoner.global_position - global_position

	if to_owner.length() > follow_distance:
		_face(to_owner.x)
		_move(to_owner.normalized(), delta)
	else:
		_play("idle")


func _move(direction: Vector2, delta: float) -> void:
	global_position += direction * move_speed * delta

	if not _play("walk"):
		_play("idle")


func _face(x: float) -> void:
	if sprite != null and absf(x) > 1.0:
		sprite.flip_h = x < 0.0


# =========================================================
# ATTACK
# =========================================================

func _attack(victim: Node2D) -> void:
	attacking = true
	attack_timer = attack_interval

	var has_anim: bool = _play("attack", true)

	if has_anim:
		await _wait_for_frame(attack_hit_frame)

	if leaving or not is_inside_tree():
		return

	if _valid_target(victim) and victim.has_method("take_damage"):
		if global_position.distance_to(victim.global_position) <= attack_range * 1.5:
			victim.take_damage(damage)

	if has_anim:
		await sprite.animation_finished
	else:
		await get_tree().create_timer(0.3).timeout

	if leaving or not is_inside_tree():
		return

	attacking = false
	_play("idle")


func _wait_for_frame(target_frame: int) -> void:
	var last_frame: int = sprite.sprite_frames.get_frame_count("attack") - 1
	target_frame = mini(target_frame, last_frame)

	while sprite.animation == "attack" and sprite.frame < target_frame:
		await get_tree().process_frame

		if leaving or not is_inside_tree():
			return


# =========================================================
# LEAVE
# =========================================================

func dismiss() -> void:
	if leaving:
		return

	leaving = true
	attacking = false

	if _play("death", true):
		await sprite.animation_finished
		queue_free()
		return

	var tween: Tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.4)
	await tween.finished
	queue_free()


# =========================================================
# HELPERS
# =========================================================

func _play(anim_name: String, restart: bool = false) -> bool:
	if sprite == null or sprite.sprite_frames == null:
		return false

	if not sprite.sprite_frames.has_animation(anim_name):
		return false

	if restart:
		sprite.stop()
		sprite.animation = anim_name
		sprite.frame = 0
		sprite.play()
	elif sprite.animation != anim_name or not sprite.is_playing():
		sprite.play(anim_name)

	return true
