extends Node2D
class_name ZoneVisual

var zone_position := Vector2.ZERO
var radius := 50.0


func set_zone(new_position: Vector2) -> void:
	zone_position = new_position
	queue_redraw()


func _draw() -> void:
	draw_circle(zone_position, radius + 8.0, Color(1.0, 0.73, 0.12, 0.18))
	draw_arc(zone_position, radius, 0.0, TAU, 64, Color(1.0, 0.86, 0.2, 0.95), 3.0)
	draw_arc(zone_position, radius - 8.0, 0.0, TAU, 64, Color(1.0, 0.55, 0.05, 0.5), 2.0)
