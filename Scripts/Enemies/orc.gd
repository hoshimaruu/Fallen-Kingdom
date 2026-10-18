extends Enemy

# The Orc is a plain Enemy: all behaviour lives in enemy.gd.
# The defaults there are the Orc's stats (80 speed, 10 / 20 damage,
# every 3rd attack is the heavy attack2), so nothing else is needed here.
#
# Tune this Orc in the Inspector, or override a hook for orc-only behaviour:
#
# func _on_damaged(_amount: int) -> void:
# 	pass
