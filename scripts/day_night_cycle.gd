extends Node

## The total duration of a full day-night cycle in seconds.
@export var day_duration: float = 60.0

@export_group("Nodes")
@export var sun_light: DirectionalLight3D
@export var world_environment: WorldEnvironment

@export_group("Day Colors")
@export var day_top_color: Color = Color(0.2, 0.45, 1.0)
@export var day_bottom_color: Color = Color(0.5, 0.7, 1.0)
@export var day_sun_scatter: Color = Color(0.3, 0.3, 0.3)

@export_group("Sunset Colors")
@export var sunset_top_color: Color = Color(0.1, 0.2, 0.4)
@export var sunset_bottom_color: Color = Color(1.0, 0.5, 0.2)
@export var sunset_sun_scatter: Color = Color(1.0, 0.4, 0.1)

@export_group("Night Colors")
@export var night_top_color: Color = Color(0.01, 0.02, 0.05)
@export var night_bottom_color: Color = Color(0.02, 0.04, 0.1)
@export var night_sun_scatter: Color = Color(0.1, 0.1, 0.2)

@export_group("Feature Intensities")
@export var night_stars: float = 5.0
@export var night_clouds_light: Color = Color(0.1, 0.2, 0.4)
@export var day_clouds_light: Color = Color(1.0, 1.0, 1.0)

var _time: float = 0.0
var _sky_material: ShaderMaterial
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
		sun_light.light_energy = smoothstep(0.0, 0.2, sun_height) * 1.5
	else:
		sun_light.light_energy = 0.0
		
	# Darken sun light during rain
	sun_light.light_energy *= (1.0 - (rain_intensity * 0.8))
	
	# Light color logic
	if sun_height > 0.0 and sun_height < 0.3:
		var t = sun_height / 0.3
		sun_light.light_color = Color(1.0, 0.4, 0.2).lerp(Color.WHITE, t)
	elif sun_height >= 0.3:
		sun_light.light_color = Color.WHITE

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

	# Apply Rain Overrides (Darkening and Graying out the sky)
	var rain_darken = Color(0.3, 0.3, 0.4)
	current_top = current_top.lerp(rain_darken, rain_intensity * 0.8)
	current_bottom = current_bottom.lerp(rain_darken, rain_intensity * 0.8)
	current_scatter = current_scatter.lerp(Color(0.2, 0.2, 0.2), rain_intensity)

	_sky_material.set_shader_parameter("top_color", current_top)
	_sky_material.set_shader_parameter("bottom_color", current_bottom)
	_sky_material.set_shader_parameter("sun_scatter", current_scatter)
	
	# Feature weights
	var day_weight = smoothstep(-0.2, 0.2, sun_height)
	var night_weight = 1.0 - day_weight
	
	_sky_material.set_shader_parameter("stars_intensity", night_weight * night_stars * (1.0 - rain_intensity))
	_sky_material.set_shader_parameter("shooting_stars_intensity", night_weight * 4.0 * (1.0 - rain_intensity))
	
	var base_clouds_light = night_clouds_light.lerp(day_clouds_light, day_weight)
	_sky_material.set_shader_parameter("clouds_light_color", base_clouds_light.lerp(Color(0.2, 0.2, 0.2), rain_intensity))
	
	_sky_material.set_shader_parameter("astro_intensity", lerp(1.2, 3.0, day_weight) * (1.0 - rain_intensity * 0.8))
	
	# Cloud Density Adjustments for heavy rain
	var target_density = lerp(0.4, 0.9, rain_intensity)
	var target_high_density = lerp(0.0, 1.0, rain_intensity)
	_sky_material.set_shader_parameter("clouds_density", target_density)
	_sky_material.set_shader_parameter("high_clouds_density", target_high_density)
