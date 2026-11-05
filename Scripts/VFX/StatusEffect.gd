class_name StatusEffects
extends RefCounted

# Status effects any attack can put on a player (or anything with take_damage).
# Needs no changes to the target's script:
#   StatusEffects.apply_poison(target, 3, 1.0, 5.0)   # 3 dmg every 1 s for 5 s
#   StatusEffects.apply_root(target, 2.0)             # cannot move for 2 s
#   StatusEffects.apply_burn(target, 3, 0.5, 3.0)     # 3 dmg every 0.5 s for 3 s
# Applying the same effect again only refreshes it, it never stacks.


static func apply_poison(target, damage: int, interval: float, duration: float) -> void:
	if not is_instance_valid(target) or not target.has_method("take_damage"):
		return

	var existing = target.get_node_or_null("StatusPoison")

	if existing != null:
		existing.refresh(damage, interval, duration)
		return

	var node := PoisonNode.new()
	node.name = "StatusPoison"
	node.damage = damage
	node.interval = maxf(interval, 0.1)
	node.time_left = duration
	target.add_child(node)


static func apply_burn(target, damage: int, interval: float, duration: float) -> void:
	if not is_instance_valid(target) or not target.has_method("take_damage"):
		return

	var existing = target.get_node_or_null("StatusBurn")

	if existing != null:
		existing.refresh(damage, interval, duration)
		return

	var node := BurnNode.new()
	node.name = "StatusBurn"
	node.damage = damage
	node.interval = maxf(interval, 0.1)
	node.time_left = duration
	target.add_child(node)


# Zeroes the target's "speed" (and the archer's "dash_speed") for a while.
# Attacks still work; only movement is blocked.
static func apply_root(target, duration: float) -> void:
	if not is_instance_valid(target) or duration <= 0.0:
		return

	var existing = target.get_node_or_null("StatusRoot")

	if existing != null:
		existing.time_left = maxf(existing.time_left, duration)
		return

	var node := RootNode.new()
	node.name = "StatusRoot"
	node.time_left = duration
	target.add_child(node)


class PoisonNode extends Node2D:
	var damage: int = 3
	var interval: float = 1.0
	var time_left: float = 5.0
	var _tick: float = 0.0
	var _time: float = 0.0

	func refresh(new_damage: int, new_interval: float, duration: float) -> void:
		damage = maxi(damage, new_damage)
		interval = maxf(new_interval, 0.1)
		time_left = maxf(time_left, duration)

	func _process(delta: float) -> void:
		var host = get_parent()

		if not is_instance_valid(host) or host.get("dead") == true:
			queue_free()
			return

		time_left -= delta
		_tick += delta
		_time += delta

		if _tick >= interval:
			_tick = 0.0
			host.call("take_damage", damage)

		if time_left <= 0.0:
			queue_free()
			return

		queue_redraw()

	# Little green bubbles rising off the target.
	func _draw() -> void:
		for i in 3:
			var phase: float = fmod(_time * 0.9 + float(i) * 0.33, 1.0)
			var pos := Vector2((float(i) - 1.0) * 9.0, -8.0 - phase * 30.0)
			draw_circle(pos, 1.5 + 2.5 * (1.0 - phase), Color(0.45, 1.0, 0.35, 0.85 * (1.0 - phase)))


class BurnNode extends Node2D:
	var damage: int = 3
	var interval: float = 0.5
	var time_left: float = 3.0
	var _tick: float = 0.0
	var _time: float = 0.0

	func refresh(new_damage: int, new_interval: float, duration: float) -> void:
		damage = maxi(damage, new_damage)
		interval = maxf(new_interval, 0.1)
		time_left = maxf(time_left, duration)

	func _process(delta: float) -> void:
		var host = get_parent()

		if not is_instance_valid(host) or host.get("dead") == true:
			queue_free()
			return

		time_left -= delta
		_tick += delta
		_time += delta

		if _tick >= interval:
			_tick = 0.0
			host.call("take_damage", damage)

		if time_left <= 0.0:
			queue_free()
			return

		queue_redraw()

	# Little flames flickering up from the target.
	func _draw() -> void:
		for i in 4:
			var phase: float = fmod(_time * 1.6 + float(i) * 0.25, 1.0)
			var pos := Vector2((float(i) - 1.5) * 7.0, 4.0 - phase * 26.0)
			var size: float = 1.5 + 3.0 * (1.0 - phase)
			draw_circle(pos, size, Color(1.0, 0.45 + 0.4 * phase, 0.1, 0.9 * (1.0 - phase)))


class RootNode extends Node2D:
	var time_left: float = 2.0
	var _saved: Dictionary = {}

	func _ready() -> void:
		var host = get_parent()

		for property_name in ["speed", "dash_speed"]:
			var value = host.get(property_name)

			if value == null:
				continue

			_saved[property_name] = value
			host.set(property_name, 0 if typeof(value) == TYPE_INT else 0.0)

	func _exit_tree() -> void:
		var host = get_parent()

		if not is_instance_valid(host):
			return

		for property_name in _saved.keys():
			host.set(property_name, _saved[property_name])

	func _process(delta: float) -> void:
		time_left -= delta

		if time_left <= 0.0:
			queue_free()
			return

		queue_redraw()

	# A purple ring on the ground.
	func _draw() -> void:
		draw_arc(Vector2(0.0, 8.0), 15.0, 0.0, TAU, 24, Color(0.65, 0.3, 0.95, 0.9), 2.0)
