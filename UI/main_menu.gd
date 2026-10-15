extends Control
@onready var canvas_layer: CanvasLayer = $CanvasLayer
@onready var main_buttons: HBoxContainer = $MainButtons
@onready var options: Panel = $Options

# Called when the node enters the scene tree for the first time.
func _ready():
	main_buttons.visible = true
	options.visible = false

func _on_texture_button_pressed() -> void:
	var error: Error = await Fade.change_scene_with_fade("res://Scenes/main.tscn")

	if error != OK:
		push_error("Scene transition failed: " + str(error))

func _on_texture_button_options_pressed() -> void:
	print("settings pressed!")
	main_buttons.visible = false
	options.visible = true

func _on_options_exit_pressed() -> void:
	_ready()
