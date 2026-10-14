extends TextureButton

func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	button_down.connect(_on_button_down)
	button_up.connect(_on_button_up)

func _on_mouse_entered() -> void:
	self_modulate = Color(0.7, 0.7, 0.7) # Dim when hovering

func _on_mouse_exited() -> void:
	self_modulate = Color(1.0, 1.0, 1.0) # Normal state

func _on_button_down() -> void:
	self_modulate = Color(0.4, 0.4, 0.4) # Darker when pressed

func _on_button_up() -> void:
	self_modulate = Color(0.7, 0.7, 0.7) # Return to hover dim when released
