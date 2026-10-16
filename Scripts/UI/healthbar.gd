extends ProgressBar
@onready var damagebar: ProgressBar = $Damagebar
@onready var timer: Timer = $Timer


var health = 0 : set = _set_health

func _set_health(new_health):
	var prev_health = health
	health = min(max_value, new_health)
	value = health
	
	if health <= 0:
		queue_free()
	
	if health < prev_health:
		timer.start()
	else:
		damagebar.value = health
		
		
		
func init_health(health):
	health = health
	max_value = health
	value = health
	damagebar.max_value = health
	damagebar.value = health

func _on_timer_timeout():
	damagebar.value = health
