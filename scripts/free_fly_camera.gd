extends Camera3D

@export var movement_speed: float = 10.0
@export var acceleration: float = 5.0
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
	
	if Input.is_key_pressed(KEY_W): input_dir.z -= 1
	if Input.is_key_pressed(KEY_S): input_dir.z += 1
	if Input.is_key_pressed(KEY_A): input_dir.x -= 1
	if Input.is_key_pressed(KEY_D): input_dir.x += 1
	if Input.is_key_pressed(KEY_E): input_dir.y += 1
	if Input.is_key_pressed(KEY_Q): input_dir.y -= 1
	
	input_dir = input_dir.normalized()
	
	var multiplier = speed_multiplier if Input.is_key_pressed(KEY_SHIFT) else 1.0
	var target_velocity = (transform.basis * input_dir) * movement_speed * multiplier
	
	_velocity = _velocity.lerp(target_velocity, acceleration * delta)
	position += _velocity * delta
