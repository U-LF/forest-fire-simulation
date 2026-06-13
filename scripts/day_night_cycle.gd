extends Node

## The total duration of a full day-night cycle in seconds.
@export var day_duration: float = 60.0

@export_group("Nodes")
@export var sun_light: DirectionalLight3D
@export var moon_light: DirectionalLight3D
@export var world_environment: WorldEnvironment

@export_group("Day Colors")
@export var day_top_color: Color = Color(0.4, 0.6, 1.0) # Brighter, clearer blue
@export var day_bottom_color: Color = Color(0.8, 0.9, 1.0) # Soft horizon
@export var day_sun_scatter: Color = Color(0.4, 0.4, 0.4)

@export_group("Sunset Colors")
@export var sunset_top_color: Color = Color(0.2, 0.1, 0.3) # Deep purple
@export var sunset_bottom_color: Color = Color(1.0, 0.4, 0.2) # Vibrant orange matching the terrain's rock colors
@export var sunset_sun_scatter: Color = Color(1.0, 0.3, 0.1)

@export_group("Night Colors")
@export var night_top_color: Color = Color(0.02, 0.05, 0.1) # Indigo night
@export var night_bottom_color: Color = Color(0.05, 0.1, 0.2)
@export var night_sun_scatter: Color = Color(0.1, 0.1, 0.2)

@export_group("Feature Intensities")
@export var night_stars: float = 5.0
@export var night_clouds_light: Color = Color(0.1, 0.2, 0.4)
@export var day_clouds_light: Color = Color(1.0, 1.0, 1.0)

var _time: float = 0.0
var _sky_material: ShaderMaterial
var cloud_coverage: float = 0.0 # 0.0 to 1.0 (Managed by WeatherManager)
var rain_intensity: float = 0.0 # 0.0 to 1.0 (Managed by WeatherManager)

func _ready() -> void:
	if world_environment and world_environment.environment.sky:
		_sky_material = world_environment.environment.sky.sky_material
	
	# Start at dawn (0.25 progress = 6:00 AM)
	_time = 0.25 * day_duration 

func _process(delta: float) -> void:
	_time += delta
	if _time >= day_duration:
		_time = 0.0
	
	var progress = _time / day_duration
	
	_update_sun(progress)
	_update_sky(progress)

func _update_sun(progress: float) -> void:
	if not sun_light:
		return
	
	# Sunrise at 0.25, Midday at 0.5, Sunset at 0.75, Midnight at 0.0/1.0
	var angle = (progress * 2.0 * PI) - (PI / 2.0)
	sun_light.rotation.x = -angle
	
	var sun_height = sin(angle)
	
	# Light energy logic
	if sun_height > 0.0:
		sun_light.light_energy = smoothstep(0.0, 0.2, sun_height) * 1.2
	else:
		sun_light.light_energy = 0.0
		
	# Darken sun light based on cloud coverage
	sun_light.light_energy *= (1.0 - (cloud_coverage * 0.8))
	
	# Light color logic
	if sun_height > 0.0 and sun_height < 0.3:
		var t = sun_height / 0.3
		sun_light.light_color = Color(1.0, 0.4, 0.2).lerp(Color.WHITE, t)
	elif sun_height >= 0.3:
		sun_light.light_color = Color.WHITE

	# Update Moon
	if moon_light:
		moon_light.rotation.x = -angle + PI
		var moon_height = sin(angle - PI)
		if moon_height > 0.0:
			moon_light.light_energy = smoothstep(0.0, 0.2, moon_height) * 0.5
		else:
			moon_light.light_energy = 0.0
		
		# Darken moon light based on cloud coverage
		moon_light.light_energy *= (1.0 - (cloud_coverage * 0.9))

func _update_sky(progress: float) -> void:
	if not _sky_material:
		return
	
	var angle = (progress * 2.0 * PI) - (PI / 2.0)
	var sun_height = sin(angle)
	
	var current_top: Color
	var current_bottom: Color
	var current_scatter: Color
	
	# Transition Logic
	if sun_height > 0.2:
		# Full Day
		var t = smoothstep(0.2, 0.5, sun_height)
		current_top = sunset_top_color.lerp(day_top_color, t)
		current_bottom = sunset_bottom_color.lerp(day_bottom_color, t)
		current_scatter = sunset_sun_scatter.lerp(day_sun_scatter, t)
	elif sun_height > -0.2:
		# Sunset/Sunrise Transition
		# 0.0 is the horizon. We want the peak "sunset" look right at 0.0
		var t = abs(sun_height) / 0.2 # 0.0 at horizon, 1.0 at 0.2/-0.2 height
		if sun_height > 0.0:
			current_top = sunset_top_color.lerp(sunset_top_color, t) # Stay sunset-ish
			current_bottom = sunset_bottom_color.lerp(sunset_bottom_color, t)
			current_scatter = sunset_sun_scatter
		else:
			current_top = sunset_top_color.lerp(night_top_color, t)
			current_bottom = sunset_bottom_color.lerp(night_bottom_color, t)
			current_scatter = sunset_sun_scatter.lerp(night_sun_scatter, t)
	else:
		# Night
		current_top = night_top_color
		current_bottom = night_bottom_color
		current_scatter = night_sun_scatter

	# Apply Overcast/Rain Overrides (Darkening and Graying out the sky) based on clouds
	var cloud_darken = Color(0.3, 0.3, 0.4)
	current_top = current_top.lerp(cloud_darken, cloud_coverage * 0.8)
	current_bottom = current_bottom.lerp(cloud_darken, cloud_coverage * 0.8)
	current_scatter = current_scatter.lerp(Color(0.2, 0.2, 0.2), cloud_coverage)

	# Update Ambient Light and Fog in WorldEnvironment
	if world_environment:
		var env = world_environment.environment
		# Lerp ambient color from warm to a cooler, dimmer stormy color
		var base_ambient = Color(0.5, 0.4, 0.35) # Matches your current stylized base
		var stormy_ambient = Color(0.25, 0.25, 0.3)
		env.ambient_light_color = base_ambient.lerp(stormy_ambient, cloud_coverage)
		# Slightly reduce ambient energy when cloudy
		env.ambient_light_energy = lerp(0.4, 0.25, cloud_coverage)
		
		# Sync fog color with sky bottom color
		env.fog_light_color = current_bottom.lerp(cloud_darken, cloud_coverage * 0.5)
		
		# Dynamic Fog Density
		# Fog is very thin on clear days, and thickens with clouds/rain
		env.fog_density = lerp(0.00005, 0.002, cloud_coverage)
		# Remove the thick permanent height fog unless it's cloudy
		env.fog_height_density = lerp(0.0, 0.8, cloud_coverage)

	_sky_material.set_shader_parameter("top_color", current_top)
	_sky_material.set_shader_parameter("bottom_color", current_bottom)
	_sky_material.set_shader_parameter("sun_scatter", current_scatter)
	
	# Feature weights
	var day_weight = smoothstep(-0.2, 0.2, sun_height)
	var night_weight = 1.0 - day_weight
	
	# Hide stars when cloudy
	_sky_material.set_shader_parameter("stars_intensity", night_weight * night_stars * (1.0 - cloud_coverage))
	_sky_material.set_shader_parameter("shooting_stars_intensity", night_weight * 4.0 * (1.0 - cloud_coverage))
	
	var base_clouds_light = night_clouds_light.lerp(day_clouds_light, day_weight)
	_sky_material.set_shader_parameter("clouds_light_color", base_clouds_light.lerp(Color(0.2, 0.2, 0.2), cloud_coverage))
	
	# Dim the sun/moon when cloudy
	_sky_material.set_shader_parameter("astro_intensity", lerp(1.2, 3.0, day_weight) * (1.0 - cloud_coverage * 0.9))
	
	# Cloud Density Adjustments
	var target_density = lerp(0.4, 0.9, cloud_coverage)
	var target_high_density = lerp(0.0, 1.0, cloud_coverage)
	_sky_material.set_shader_parameter("clouds_density", target_density)
	_sky_material.set_shader_parameter("high_clouds_density", target_high_density)
