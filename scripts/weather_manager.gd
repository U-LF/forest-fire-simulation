extends Node3D

@export var day_night_cycle: Node
@export var rain_particles: GPUParticles3D
@export var lightning_light: DirectionalLight3D
@export var terrain: Node3D

@export_group("Atmospheric Parameters")
@export var temp_min: float = 2.2
@export var temp_max: float = 33.3
@export var rh_min: float = 15.0
@export var rh_max: float = 100.0
@export var wind_min: float = 0.4
@export var wind_max: float = 9.4
@export var rain_min: float = 0.0
@export var rain_max: float = 6.4
@export var rh_rain_threshold: float = 85.0
@export var time_scale: float = 10.0 # Time multiplier for noise progression

var _time_elapsed: float = 0.0
var _lightning_timer: float = 0.0

# 1D Simplex Noises for atmospheric progression
var noise_temp: FastNoiseLite
var noise_rh: FastNoiseLite
var noise_wind: FastNoiseLite
var noise_rain: FastNoiseLite

# Current atmospheric state
var current_temp: float = 20.0
var current_rh: float = 50.0
var current_wind: float = 2.0
var current_wind_dir: Vector2 = Vector2(1.0, 0.0)
var current_rain: float = 0.0
var current_moisture: float = 0.0 # 0.0 to 1.0 persistent saturation

# Tracks linear temperature drop during rain
var temp_drop_offset: float = 0.0

func _ready() -> void:
	if rain_particles:
		rain_particles.emitting = false
		rain_particles.local_coords = false # Prevent sliding
		rain_particles.visibility_aabb = AABB(
			Vector3(-2000.0, -200.0, -2000.0),
			Vector3(4000.0, 400.0, 4000.0)
		)

	if lightning_light:
		lightning_light.light_energy = 0.0
	
	# Setup continuous noise generators
	noise_temp = FastNoiseLite.new()
	noise_temp.seed = randi()
	noise_temp.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise_temp.frequency = 0.01

	noise_rh = FastNoiseLite.new()
	noise_rh.seed = randi()
	noise_rh.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise_rh.frequency = 0.015
	
	noise_wind = FastNoiseLite.new()
	noise_wind.seed = randi()
	noise_wind.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise_wind.frequency = 0.05 # Wind fluctuates faster

	noise_rain = FastNoiseLite.new()
	noise_rain.seed = randi()
	noise_rain.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise_rain.frequency = 0.02

func _process(delta: float) -> void:
	_time_elapsed += delta * time_scale
	
	# Sample noises (-1.0 to 1.0)
	var raw_temp = noise_temp.get_noise_1d(_time_elapsed)
	var raw_rh = noise_rh.get_noise_1d(_time_elapsed)
	var raw_wind = noise_wind.get_noise_1d(_time_elapsed)
	
	# Map values to real-world bounds
	var base_temp = remap(raw_temp, -1.0, 1.0, temp_min, temp_max)
	current_rh = remap(raw_rh, -1.0, 1.0, rh_min, rh_max)
	current_wind = remap(raw_wind, -1.0, 1.0, wind_min, wind_max)
	
	# Slowly rotate wind direction over time
	current_wind_dir = Vector2(cos(_time_elapsed * 0.02), sin(_time_elapsed * 0.02)).normalized()
	
	# Threshold-Driven State: Rain Trigger
	var is_raining = current_rh >= rh_rain_threshold
	if is_raining:
		var raw_rain = noise_rain.get_noise_1d(_time_elapsed)
		var target_rain = remap(raw_rain, -1.0, 1.0, rain_min, rain_max)
		# Continuous volume tracking toward the target
		current_rain = move_toward(current_rain, target_rain, delta * 2.0)
		
		# Rain state drops local temperature linearly over time
		temp_drop_offset -= delta * 1.5
	else:
		current_rain = move_toward(current_rain, 0.0, delta * 1.5)
		# Recover temperature smoothly when not raining
		temp_drop_offset = move_toward(temp_drop_offset, 0.0, delta * 0.5)
		
	# Final calculated temperature
	current_temp = clamp(base_temp + temp_drop_offset, temp_min, temp_max)
	
	# Derive visual cloud coverage from RH
	var cloud_coverage = remap(current_rh, 30.0, 100.0, 0.0, 1.0)
	cloud_coverage = clamp(cloud_coverage, 0.0, 1.0)
	
	# Update External Systems
	_handle_moisture(delta)
	
	if day_night_cycle:
		day_night_cycle.cloud_coverage = cloud_coverage
		day_night_cycle.rain_intensity = clamp(current_rain / rain_max, 0.0, 1.0)
	
	if rain_particles:
		if current_rain > 0.01 and not rain_particles.emitting:
			rain_particles.emitting = true
		elif current_rain <= 0.01 and rain_particles.emitting:
			rain_particles.emitting = false
			
		rain_particles.amount_ratio = clamp(current_rain / rain_max, 0.01, 1.0)
		
		# Wind-blown rain logic
		if rain_particles.process_material is ParticleProcessMaterial:
			var p_mat = rain_particles.process_material as ParticleProcessMaterial
			# Base downward direction (0, -1, 0)
			# Add wind influence (towards +X for consistency)
			var wind_influence = current_wind * 0.1
			p_mat.direction = Vector3(wind_influence, -1.0, 0.0).normalized()
			# Increase speed slightly with wind
			p_mat.initial_velocity_min = 30.0 + current_wind * 2.0
			p_mat.initial_velocity_max = 45.0 + current_wind * 3.0
	
	_handle_lightning(delta, is_raining)

func _handle_moisture(delta: float) -> void:
	# 1. Charging (Rain Suffix)
	# Moisture increases rapidly when it's actually raining.
	if current_rain > 0.1:
		# Saturates to 100% (1.0) quickly in heavy rain
		var charge_rate = remap(current_rain, 0.0, rain_max, 0.05, 0.2)
		current_moisture = move_toward(current_moisture, 1.0, delta * charge_rate * time_scale)
	else:
		# 2. Drying Process (Evaporation)
		# Factors: High Temp, Low RH, High Wind
		
		# Temp Factor (2.2 to 33.3 -> 0.2x to 1.5x speed)
		var f_temp = remap(current_temp, temp_min, temp_max, 0.2, 1.5)
		# RH Factor (15 to 100 -> 1.5x down to 0.1x speed) - dry air pulls moisture
		var f_rh = remap(current_rh, rh_min, rh_max, 1.5, 0.1)
		# Wind Factor (0.4 to 9.4 -> 1.0x to 2.5x speed)
		var f_wind = remap(current_wind, wind_min, wind_max, 1.0, 2.5)
		
		# Base evaporation rate (approx 5-10 real minutes to dry at 1x time_scale)
		var base_drying_rate = 0.01 
		var drying_speed = base_drying_rate * f_temp * f_rh * f_wind
		
		current_moisture = move_toward(current_moisture, 0.0, delta * drying_speed * time_scale)

func trigger_lightning_intervention() -> void:
	if lightning_light:
		lightning_light.rotation.x = -PI/2.0 + randf_range(-0.5, 0.5)
		lightning_light.rotation.y = randf_range(0, 2.0 * PI)
		lightning_light.light_energy = randf_range(5.0, 15.0)
	_spawn_lightning_strike()

func _handle_lightning(delta: float, is_raining: bool) -> void:
	# Lightning occurs mostly during heavy rain naturally
	if not is_raining or current_rain < (rain_max * 0.5):
		if lightning_light and lightning_light.light_energy > 0.0:
			lightning_light.light_energy = lerp(lightning_light.light_energy, 0.0, delta * 15.0)
		return
		
	_lightning_timer -= delta
	
	# Fade out existing flash
	if lightning_light and lightning_light.light_energy > 0.0:
		lightning_light.light_energy = lerp(lightning_light.light_energy, 0.0, delta * 15.0)
	
	# Regular interval trigger based on storm severity
	if _lightning_timer <= 0.0:
		var frequency_modifier = 1.0 - (current_rain / rain_max)
		_lightning_timer = randf_range(3.0, 8.0 + (frequency_modifier * 15.0)) 
		trigger_lightning_intervention()

func _spawn_lightning_strike() -> void:
	var range_x = 40.0
	var range_z = 40.0
	
	if terrain:
		range_x = terrain.terrain_size.x / 2.0
		range_z = terrain.terrain_size.y / 2.0
		
	# Chooses a random coordinate on the active Terrain
	var strike_pos = Vector3(randf_range(-range_x, range_x), 0, randf_range(-range_z, range_z))
	
	if terrain:
		strike_pos.y = terrain.get_height_at(strike_pos.x, strike_pos.z)
		
	var start_pos = strike_pos + Vector3(0, 100, 0) # Start high in the clouds
	
	# Generate jagged points
	var points = PackedVector3Array()
	points.append(start_pos)
	
	var current_pos = start_pos
	var segments = randi_range(8, 15)
	var segment_length = 100.0 / segments
	
	for i in range(segments):
		if i == segments - 1:
			points.append(strike_pos) # Guarantee it hits the ground target
		else:
			var jitter_x = randf_range(-10.0, 10.0)
			var jitter_z = randf_range(-10.0, 10.0)
			current_pos -= Vector3(jitter_x, segment_length, jitter_z)
			points.append(current_pos)
	
	# Create a Path3D and CSGPolygon3D for a volumetric lightning bolt
	var path = Path3D.new()
	var curve = Curve3D.new()
	for p in points:
		curve.add_point(p)
	path.curve = curve
	add_child(path)
	
	var csg = CSGPolygon3D.new()
	csg.mode = CSGPolygon3D.MODE_PATH
	csg.path_node = csg.get_path_to(path)
	# A simple square profile provides a robust 3D volume
	var thickness = 0.5
	csg.polygon = PackedVector2Array([
		Vector2(-thickness, -thickness), 
		Vector2(thickness, -thickness), 
		Vector2(thickness, thickness), 
		Vector2(-thickness, thickness)
	])
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.9, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.8, 0.9, 1.0)
	mat.emission_energy_multiplier = 15.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	csg.material = mat
	path.add_child(csg)
	
	var omni = OmniLight3D.new()
	omni.light_color = Color(0.8, 0.9, 1.0)
	omni.light_energy = 20.0
	omni.omni_range = 50.0
	omni.position = strike_pos + Vector3(0, 2, 0)
	add_child(omni)
	
	# Fade out animation
	var tween = create_tween()
	tween.tween_interval(0.05)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.2)
	tween.parallel().tween_property(omni, "light_energy", 0.0, 0.2)
	tween.tween_callback(path.queue_free)
	tween.tween_callback(omni.queue_free)
