extends Camera3D

signal fire_started(position: Vector3)

@export var movement_speed: float = 40.0
@export var acceleration: float = 20.0
@export var mouse_sensitivity: float = 0.1
@export var speed_multiplier: float = 2.5

@export var terrain: Node3D

var _velocity: Vector3 = Vector3.ZERO
var _rotation: Vector2 = Vector2.ZERO

var _laser_mesh_instance: MeshInstance3D
var _is_firing_laser: bool = false

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_rotation = Vector2(rotation_degrees.y, rotation_degrees.x)
	
	# --- Setup Laser ---
	_laser_mesh_instance = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(0.05, 0.05, 1.0) # 1.0 on Z axis so we can scale it directly by distance
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.2, 0.0, 0.8)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.2, 0.0)
	mat.emission_energy_multiplier = 15.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	box_mesh.material = mat
	_laser_mesh_instance.mesh = box_mesh
	_laser_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_laser_mesh_instance.visible = false
	add_child(_laser_mesh_instance)
	_laser_mesh_instance.top_level = true # Make it ignore the camera's local transforms
	
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
	if terrain:
		var half_x = terrain.terrain_size.x / 2.0
		var half_z = terrain.terrain_size.y / 2.0
		global_position.x = clamp(global_position.x, -half_x, half_x)
		global_position.z = clamp(global_position.z, -half_z, half_z)
	
	# --- Ground Collision ---
	if terrain and terrain.macro_image:
		var terrain_height = terrain.get_height_at(global_position.x, global_position.z)
		var min_height = terrain_height + 2.0 # Keep camera 2 units above ground
		if global_position.y < min_height:
			global_position.y = min_height
			# If we hit the ground, kill vertical downward velocity to prevent "jitter"
			if _velocity.y < 0:
				_velocity.y = 0

	_process_laser()

func _process_laser() -> void:
	var f_pressed = Input.is_physical_key_pressed(KEY_F)
	
	var space_state = get_world_3d().direct_space_state
	var cam_forward = -global_transform.basis.z
	var ray_end = global_position + cam_forward * 5000.0
	var query = PhysicsRayQueryParameters3D.create(global_position, ray_end)
	query.collision_mask = 0xFFFFFFFF # Check against everything
	var result = space_state.intersect_ray(query)
	
	var hit_pos = ray_end
	if result:
		hit_pos = result.position
		
	if f_pressed:
		var distance = global_position.distance_to(hit_pos)
		_laser_mesh_instance.visible = true
		
		# Position mesh exactly halfway between camera and hit
		var mid_point = global_position.lerp(hit_pos, 0.5)
		_laser_mesh_instance.global_position = mid_point
		
		# Look at the hit point
		if not mid_point.is_equal_approx(hit_pos):
			var up_vec = Vector3.UP
			if abs(cam_forward.dot(Vector3.UP)) > 0.99:
				up_vec = Vector3.RIGHT
			_laser_mesh_instance.look_at(hit_pos, up_vec)
		
		# Scale the Z-axis based on distance (BoxMesh is natively aligned)
		_laser_mesh_instance.scale = Vector3(1, 1, distance)
		
		if not _is_firing_laser:
			print("Camera: Started painting fire at ", hit_pos, " (Distance: ", distance, ")")
			
		_is_firing_laser = true
		
		# Continuously paint fire
		emit_signal("fire_started", hit_pos)
	else:
		if _is_firing_laser:
			print("Camera: Stopped painting fire.")
			_is_firing_laser = false
			_laser_mesh_instance.visible = false
