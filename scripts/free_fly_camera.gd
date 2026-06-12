extends Camera3D

@export var movement_speed: float = 40.0
@export var acceleration: float = 20.0
@export var mouse_sensitivity: float = 0.1
@export var speed_multiplier: float = 2.5

@export var terrain: Node3D

var _velocity: Vector3 = Vector3.ZERO
var _rotation: Vector2 = Vector2.ZERO

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_rotation = Vector2(rotation_degrees.y, rotation_degrees.x)
	
	if terrain:
		if not terrain.macro_image:
			await terrain.terrain_ready
		
		var terrain_height = terrain.get_height_at(global_position.x, global_position.z)
		# Ensure camera is at least 30 units above the terrain
		if global_position.y < terrain_height + 30.0:
			global_position.y = terrain_height + 30.0
			print("Camera: Adjusted start height to ", global_position.y)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_rotation.x -= event.relative.y * mouse_sensitivity
		_rotation.y -= event.relative.x * mouse_sensitivity
		_rotation.x = clamp(_rotation.x, -89.0, 89.0)
		
		rotation_degrees.x = _rotation.x
		rotation_degrees.y = _rotation.y
	
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _process(delta: float) -> void:
	var input_dir = Vector3.ZERO
	
	input_dir.x = Input.get_axis("move_left", "move_right")
	input_dir.z = Input.get_axis("move_forward", "move_backward")
	input_dir.y = Input.get_axis("move_down", "move_up")
	
	input_dir = input_dir.normalized()
	
	var multiplier = speed_multiplier if Input.is_action_pressed("camera_speed") else 1.0
	var target_velocity = (transform.basis * input_dir) * movement_speed * multiplier
	
	_velocity = _velocity.lerp(target_velocity, acceleration * delta)
	position += _velocity * delta
	
	# --- Bounds Collision ---
	# Terrain is 1000x1000, centered at (0,0)
	var half_size = 500.0
	global_position.x = clamp(global_position.x, -half_size, half_size)
	global_position.z = clamp(global_position.z, -half_size, half_size)
	
	# --- Ground Collision ---
	if terrain and terrain.macro_image:
		var terrain_height = terrain.get_height_at(global_position.x, global_position.z)
		var min_height = terrain_height + 2.0 # Keep camera 2 units above ground
		if global_position.y < min_height:
			global_position.y = min_height
			# If we hit the ground, kill vertical downward velocity to prevent "jitter"
			if _velocity.y < 0:
				_velocity.y = 0
