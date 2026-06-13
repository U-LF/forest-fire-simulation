extends StaticBody3D

signal terrain_ready

@export var terrain_material: ShaderMaterial
@export var mesh_instance: MeshInstance3D
@export var collision_shape: CollisionShape3D
@export var terrain_size: Vector2 = Vector2(2000, 2000)
@export var terrain_scale: float = 1400.0
@export var height_scale: float = 120.0

var macro_image: Image
var image_width: int = 1024
var image_height: int = 1024

func _ready() -> void:
	randomize() # Ensure different results each launch
	
	if not terrain_material:
		push_error("TerrainGenerator: terrain_material is null!")
		emit_signal("terrain_ready")
		return
		
	if not mesh_instance or not collision_shape:
		push_error("TerrainGenerator: mesh_instance or collision_shape is missing!")
		emit_signal("terrain_ready")
		return

	# Sync Mesh dimensions
	if mesh_instance.mesh is PlaneMesh:
		mesh_instance.mesh.size = terrain_size
	
	# Sync Shader parameters
	terrain_material.set_shader_parameter("terrain_scale", terrain_scale)
	terrain_material.set_shader_parameter("height_scale", height_scale)
		
	var macro_tex = terrain_material.get_shader_parameter("macro_noise")
	var micro_tex = terrain_material.get_shader_parameter("micro_noise")
	
	# Randomize seeds for variety
	if macro_tex is NoiseTexture2D and macro_tex.noise:
		macro_tex.noise.seed = randi()
	if micro_tex is NoiseTexture2D and micro_tex.noise:
		micro_tex.noise.seed = randi()
		
	if macro_tex is NoiseTexture2D:
		macro_image = macro_tex.get_image()
		if not macro_image:
			# If not ready immediately, wait for the texture to finish generating
			await macro_tex.changed
			macro_image = macro_tex.get_image()
			
		if macro_image:
			image_width = macro_image.get_width()
			image_height = macro_image.get_height()
		else:
			push_error("TerrainGenerator: Failed to get image from macro_noise texture after waiting!")
			
	_generate_collision_heightmap()
	
	# Signal to the forest generator that it's safe to read the heightmap
	emit_signal("terrain_ready")

func get_height_at(world_x: float, world_z: float) -> float:
	if not macro_image:
		return 0.0
		
	# Correct UV mapping: Map world [-500, 500] to UV [0, 1]
	# This avoids the mirroring issue and matches standard texture mapping
	var uv_x = (world_x / terrain_scale) + 0.5
	var uv_y = (world_z / terrain_scale) + 0.5
	
	# Clamp to 0..1 to handle edges if needed, though wrap is safer for seamless
	uv_x = wrapf(uv_x, 0.0, 1.0)
	uv_y = wrapf(uv_y, 0.0, 1.0)
	
	# Convert to pixel coordinates for Bilinear Interpolation
	var x = uv_x * image_width - 0.5
	var y = uv_y * image_height - 0.5
	
	var x0 = int(floor(x))
	var y0 = int(floor(y))
	var x1 = x0 + 1
	var y1 = y0 + 1
	
	var frac_x = x - x0
	var frac_y = y - y0
	
	var px0 = wrapi(x0, 0, image_width)
	var px1 = wrapi(x1, 0, image_width)
	var py0 = wrapi(y0, 0, image_height)
	var py1 = wrapi(y1, 0, image_height)
	
	var c00 = macro_image.get_pixel(px0, py0).r
	var c10 = macro_image.get_pixel(px1, py0).r
	var c01 = macro_image.get_pixel(px0, py1).r
	var c11 = macro_image.get_pixel(px1, py1).r
	
	# Interpolate X
	var c0 = lerp(c00, c10, frac_x)
	var c1 = lerp(c01, c11, frac_x)
	
	# Interpolate Y
	var macro_h = lerp(c0, c1, frac_y)
	
	# Apply final shaping
	macro_h = smoothstep(0.1, 0.95, macro_h)
	
	return macro_h * height_scale

func get_normal_at(world_x: float, world_z: float) -> Vector3:
	var e = 1.0
	var hL = get_height_at(world_x - e, world_z)
	var hR = get_height_at(world_x + e, world_z)
	var hD = get_height_at(world_x, world_z - e)
	var hU = get_height_at(world_x, world_z + e)
	
	var n = Vector3(hL - hR, 2.0 * e, hD - hU)
	return n.normalized()

func _generate_collision_heightmap() -> void:
	var plane_mesh = mesh_instance.mesh as PlaneMesh
	if not plane_mesh or not macro_image:
		return
		
	var width = plane_mesh.subdivide_width + 2
	var depth = plane_mesh.subdivide_depth + 2
	
	var heightmap_shape = HeightMapShape3D.new()
	heightmap_shape.map_width = width
	heightmap_shape.map_depth = depth
	
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
			
			map_data[z * width + x] = get_height_at(world_x, world_z)
			
	heightmap_shape.map_data = map_data
	collision_shape.shape = heightmap_shape
	
	# Also update GPU Particles Collision if it exists
	var gp_col = get_node_or_null("GPUParticlesCollisionHeightField3D")
	if gp_col is GPUParticlesCollisionHeightField3D:
		gp_col.size = Vector3(plane_mesh.size.x, height_scale, plane_mesh.size.y)
		# Position the heightfield so its base is at Y=0 and it grows upward
		gp_col.position.y = height_scale / 2.0
