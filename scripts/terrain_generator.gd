extends StaticBody3D

@export var terrain_material: ShaderMaterial
@export var mesh_instance: MeshInstance3D
@export var collision_shape: CollisionShape3D

func _ready() -> void:
	if not terrain_material or not mesh_instance or not collision_shape:
		return
		
	# Wait one frame to ensure textures are loaded
	await get_tree().process_frame
	
	_generate_collision_heightmap()

func _generate_collision_heightmap() -> void:
	var plane_mesh = mesh_instance.mesh as PlaneMesh
	if not plane_mesh:
		return
		
	var width = plane_mesh.subdivide_width + 2
	var depth = plane_mesh.subdivide_depth + 2
	
	var heightmap_shape = HeightMapShape3D.new()
	heightmap_shape.map_width = width
	heightmap_shape.map_depth = depth
	
	var macro_tex = terrain_material.get_shader_parameter("macro_noise") as NoiseTexture2D
	var micro_tex = terrain_material.get_shader_parameter("micro_noise") as NoiseTexture2D
	
	var height_scale = terrain_material.get_shader_parameter("height_scale") as float
	var terrain_scale = terrain_material.get_shader_parameter("terrain_scale") as float
	
	if not macro_tex or not macro_tex.noise or not micro_tex or not micro_tex.noise:
		return
		
	var macro_noise = macro_tex.noise
	var micro_noise = micro_tex.noise
	
	var map_data = PackedFloat32Array()
	map_data.resize(width * depth)
	
	var start_x = -plane_mesh.size.x / 2.0
	var start_z = -plane_mesh.size.y / 2.0
	var step_x = plane_mesh.size.x / (width - 1)
	var step_z = plane_mesh.size.y / (depth - 1)
	
	for z in range(depth):
		for x in range(width):
			var world_x = start_x + (x * step_x)
			var world_z = start_z + (z * step_z)
			
			var uv_macro_x = (world_x / terrain_scale) * 1024.0
			var uv_macro_z = (world_z / terrain_scale) * 1024.0
			
			var macro_h = (macro_noise.get_noise_2d(uv_macro_x, uv_macro_z) * 0.5) + 0.5
			macro_h = smoothstep(0.1, 0.95, macro_h)
			
			var total_height = macro_h * height_scale
			map_data[z * width + x] = total_height
			
	heightmap_shape.map_data = map_data
	collision_shape.shape = heightmap_shape
