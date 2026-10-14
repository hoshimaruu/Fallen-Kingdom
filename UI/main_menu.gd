extends Control
@onready var canvas_layer: CanvasLayer = $CanvasLayer


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func _on_texture_button_pressed() -> void:
	var error: Error = await Fade.change_scene_with_fade("res://Scenes/main.tscn")

	if error != OK:
		push_error("Scene transition failed: " + str(error))
