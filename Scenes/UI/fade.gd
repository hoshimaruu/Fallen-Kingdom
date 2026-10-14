extends CanvasLayer

@onready var color_rect: ColorRect = $ColorRect

func _ready() -> void:
	layer = 10
	color_rect.color = Color.BLACK
	color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	color_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	color_rect.modulate.a = 0.0

func fade(target_alpha: float, duration: float = 0.3) -> Tween:
	var tween: Tween = create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(color_rect, "modulate:a", target_alpha, duration)
	return tween

func change_scene_with_fade(scene_path: String) -> Error:
	print("Fading to black...")
	await fade(1.0, 0.3).finished

	print("Changing scene...")
	var tree: SceneTree = get_tree()
	var error: Error = tree.change_scene_to_file(scene_path)

	if error != OK:
		push_error("Failed to change scene: " + str(error))
		await fade(0.0, 0.3).finished
		return error

	# Wait until Godot finishes processing the scene change.
	while tree.current_scene == null or tree.current_scene.scene_file_path != scene_path:
		await tree.process_frame

	print("Gameplay loaded. Fading in...")
	await fade(0.0, 0.3).finished

	print("Fade-in complete!")
	return OK
