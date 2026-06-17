extends Node3D

@export var terrain: StaticBody3D
@export var grass_scene: PackedScene
@export var particle_count: int = 150000 # Balanced count for performance

var _particles: GPUParticles3D
var _process_material: ShaderMaterial
var _wind_material: ShaderMaterial

func _ready() -> void:
	if not terrain:
		push_error("GrassManager: No terrain assigned!")
		return
	if not grass_scene:
		push_error("GrassManager: No grass scene assigned!")
		return
		
	if not terrain.terrain_ready:
		await terrain.terrain_ready
		
	_setup_particles_gpu()

func _setup_particles_gpu() -> void:
	# 1. Extract mesh and material from the grass asset
	var temp_node = grass_scene.instantiate()
	var mesh_inst = _find_first_mesh_instance(temp_node)
	if not mesh_inst:
		temp_node.queue_free()
		return
	var grass_mesh = mesh_inst.mesh
	var orig_mat = mesh_inst.get_active_material(0)
	temp_node.queue_free()

	# 2. Setup Particle Material (Placement Shader)
	_process_material = ShaderMaterial.new()
	_process_material.shader = load("res://resources/grass_particle.gdshader")
	
	var noise_tex = terrain.terrain_material.get_shader_parameter("macro_noise")
	_process_material.set_shader_parameter("terrain_heightmap", noise_tex)
	_process_material.set_shader_parameter("terrain_scale", terrain.terrain_scale)
	_process_material.set_shader_parameter("height_scale", terrain.height_scale)

	# 3. Setup Grass Visual Shader (Wind Shader)
	_wind_material = ShaderMaterial.new()
	_wind_material.shader = load("res://resources/grass_visual.gdshader")
	
	if orig_mat:
		var tex = null
		var color = Color.WHITE
		if "albedo_texture" in orig_mat: tex = orig_mat.albedo_texture
		if "albedo_color" in orig_mat: color = orig_mat.albedo_color
		_wind_material.set_shader_parameter("albedo_texture", tex)
		_wind_material.set_shader_parameter("albedo_color", color)

	var fire_mgr = get_parent().get_node_or_null("FireManager")
	if fire_mgr:
		if not fire_mgr.vp_a:
			await fire_mgr.ready
		_wind_material.set_shader_parameter("burn_map", fire_mgr.get_burn_map())

	# 4. Create GPUParticles3D
	_particles = GPUParticles3D.new()
	_particles.amount = particle_count
	_particles.process_material = _process_material
	
	var mesh_duplicate = grass_mesh.duplicate()
	mesh_duplicate.surface_set_material(0, _wind_material)
	_particles.draw_pass_1 = mesh_duplicate
	
	_particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_particles.lifetime = 1000.0 
	_particles.explosiveness = 1.0
	_particles.visibility_aabb = AABB(Vector3(-2000, -100, -2000), Vector3(4000, 300, 4000))
	_particles.fixed_fps = 0 
	_particles.local_coords = false 
	
	add_child(_particles)

func _process(_delta: float) -> void:
	var cam = get_viewport().get_camera_3d()
	if not cam or not _process_material: return
	_process_material.set_shader_parameter("world_offset", cam.global_position)
	
	var weather_mgr = get_parent().get_node_or_null("WeatherManager")
	if weather_mgr and "current_wind" in weather_mgr:
		var wind = weather_mgr.current_wind
		# Grass is lighter, so it reacts more intensely to wind
		_wind_material.set_shader_parameter("wind_speed", wind * 0.6)
		_wind_material.set_shader_parameter("wind_strength", wind * 0.12)

func _find_first_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D: return node
	for child in node.get_children():
		var found = _find_first_mesh_instance(child)
		if found: return found
	return null
