extends CanvasLayer

@export var weather_manager: Node3D
@export var day_night_cycle: Node

@onready var temp_big: Label = $Margin/Panel/Padding/MainVBox/CurrentHBox/LeftCol/TempBig
@onready var condition_big: Label = $Margin/Panel/Padding/MainVBox/CurrentHBox/LeftCol/ConditionBig
@onready var rh_label: Label = $Margin/Panel/Padding/MainVBox/CurrentHBox/RightCol/RHLabel
@onready var wind_label: Label = $Margin/Panel/Padding/MainVBox/CurrentHBox/RightCol/WindLabel
@onready var rain_label: Label = $Margin/Panel/Padding/MainVBox/CurrentHBox/RightCol/RainLabel
@onready var fire_progress_bar: ProgressBar = $Margin/Panel/Padding/MainVBox/FireRiskBox/FireProgressBar
@onready var fire_factors_label: Label = $Margin/Panel/Padding/MainVBox/FireRiskBox/FactorsLabel

@onready var total_trees_label: Label = $Margin/Panel/Padding/MainVBox/TreeStatsBox/TotalTreesLabel
@onready var healthy_trees_label: Label = $Margin/Panel/Padding/MainVBox/TreeStatsBox/HealthyTreesLabel
@onready var damaged_trees_label: Label = $Margin/Panel/Padding/MainVBox/TreeStatsBox/DamagedTreesLabel
@onready var burnt_trees_label: Label = $Margin/Panel/Padding/MainVBox/TreeStatsBox/BurntTreesLabel

@onready var forecast_list: VBoxContainer = $Margin/Panel/Padding/MainVBox/ForecastList

var forecast_rows: Array[HBoxContainer] = []

func update_tree_stats(total: int, healthy: int, damaged: int, burnt: int) -> void:
	total_trees_label.text = "Total Trees: %d" % total
	healthy_trees_label.text = "Healthy: %d" % healthy
	damaged_trees_label.text = "Damaged: %d" % damaged
	burnt_trees_label.text = "Burnt: %d" % burnt


func _ready() -> void:
	if not weather_manager:
		weather_manager = get_node_or_null("../WeatherManager")
		if not weather_manager:
			weather_manager = get_node_or_null("/root/Main/WeatherManager")
	if not day_night_cycle:
		day_night_cycle = get_node_or_null("../DayNightCycle")
		if not day_night_cycle:
			day_night_cycle = get_node_or_null("/root/Main/DayNightCycle")
			
	var fire_manager = get_node_or_null("../FireManager")
	if not fire_manager:
		fire_manager = get_node_or_null("/root/Main/FireManager")
	if fire_manager and fire_manager.has_signal("tree_stats_updated"):
		fire_manager.tree_stats_updated.connect(update_tree_stats)
			
	# Handle dynamic resolution scaling
	get_viewport().size_changed.connect(_on_viewport_resized)
	_on_viewport_resized()
			
	# Initialize 7 forecast rows dynamically so they align perfectly
	for i in range(7):
		var row = HBoxContainer.new()
		
		var day_lbl = Label.new()
		day_lbl.custom_minimum_size = Vector2(60, 0)
		day_lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
		day_lbl.add_theme_font_size_override("font_size", 14)
		
		var cond_lbl = Label.new()
		cond_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cond_lbl.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
		cond_lbl.add_theme_font_size_override("font_size", 14)
		
		var details_lbl = Label.new()
		details_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		details_lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
		details_lbl.add_theme_font_size_override("font_size", 14)
		
		row.add_child(day_lbl)
		row.add_child(cond_lbl)
		row.add_child(details_lbl)
		forecast_list.add_child(row)
		forecast_rows.append(row)

func _on_viewport_resized() -> void:
	var viewport_size = get_viewport().get_visible_rect().size
	var base_size = Vector2(1928.0, 1080.0)
	
	# Scale based on the smallest ratio to ensure it fits perfectly regardless of aspect ratio
	var scale_factor = min(viewport_size.x / base_size.x, viewport_size.y / base_size.y)
	
	$Margin.scale = Vector2(scale_factor, scale_factor)
	
	# Keep it anchored to the top right of the actual screen
	# The UI's base width is 340. We shift it left by 340 * scale_factor.
	$Margin.position.x = viewport_size.x - (340.0 * scale_factor)
	$Margin.position.y = 0.0

func _get_cardinal_direction(dir: Vector2) -> String:
	var deg = rad_to_deg(dir.angle())
	if deg < 0:
		deg += 360.0
	
	# In meteorological terms, wind direction is usually where it's blowing FROM.
	# But in games, players usually care about where it's blowing TO (where the fire goes).
	# Adding an arrow makes the visual direction completely unambiguous.
	if deg >= 337.5 or deg < 22.5: return "→ E"
	if deg >= 22.5 and deg < 67.5: return "↘ SE"
	if deg >= 67.5 and deg < 112.5: return "↓ S"
	if deg >= 112.5 and deg < 157.5: return "↙ SW"
	if deg >= 157.5 and deg < 202.5: return "← W"
	if deg >= 202.5 and deg < 247.5: return "↖ NW"
	if deg >= 247.5 and deg < 292.5: return "↑ N"
	if deg >= 292.5 and deg < 337.5: return "↗ NE"
	return ""

func _process(_delta: float) -> void:
	if not weather_manager or not day_night_cycle:
		return
		
	# Update Current Weather
	var temp = weather_manager.current_temp
	var rh = weather_manager.current_rh
	var wind = weather_manager.current_wind
	var wind_dir = Vector2(1, 0)
	if "current_wind_dir" in weather_manager:
		wind_dir = weather_manager.current_wind_dir
	var rain = weather_manager.current_rain
	
	var current_condition = "Clear"
	var cond_color = Color(0.6, 0.9, 0.6) # Sunny/Clear color
	if rain > 3.0: 
		current_condition = "Heavy Rain"
		cond_color = Color(0.4, 0.5, 0.8)
	elif rain > 0.0: 
		current_condition = "Rain"
		cond_color = Color(0.5, 0.7, 0.9)
	elif rh > 70.0: 
		current_condition = "Cloudy"
		cond_color = Color(0.7, 0.7, 0.75)
	elif rh > 45.0: 
		current_condition = "Partly Cloudy"
		cond_color = Color(0.8, 0.8, 0.7)
		
	temp_big.text = "%.1f°" % temp
	condition_big.text = current_condition
	condition_big.add_theme_color_override("font_color", cond_color)
	
	rh_label.text = "💧 %d %%" % int(rh)
	wind_label.text = "💨 %.1f km/h %s" % [wind, _get_cardinal_direction(wind_dir)]
	if rain > 0:
		rain_label.text = "☔ %.1f mm" % rain
		rain_label.show()
	else:
		rain_label.hide()
	
	# Update Ignition Probability (Fire Risk)
	var p_base = 0.2
	var m_temp = remap(clamp(temp, 2.2, 33.3), 2.2, 33.3, 0.5, 1.5)
	
	var m_rh: float
	if (rh <= 30.0):
		m_rh = remap(clamp(rh, 15.0, 30.0), 15.0, 30.0, 2.0, 1.5)
	elif (rh >= 80.0):
		m_rh = remap(clamp(rh, 80.0, 100.0), 80.0, 100.0, 0.3, 0.1)
	else:
		m_rh = remap(clamp(rh, 30.0, 80.0), 30.0, 80.0, 1.5, 0.3)
		
	var m_wind = remap(clamp(wind, 0.4, 9.4), 0.4, 9.4, 1.0, 2.5)
	
	# Update Rain Shield Logic (Uses persistent moisture)
	var moisture = 0.0
	if "current_moisture" in weather_manager:
		moisture = weather_manager.current_moisture
		
	var rain_shield = moisture
	var p_ignite = (p_base * m_temp * m_rh * m_wind) * (1.0 - rain_shield)
	p_ignite = clamp(p_ignite, 0.0, 1.0)
	
	fire_progress_bar.value = p_ignite * 100.0
	fire_factors_label.text = "Factors: T:%.1fx  RH:%.1fx  W:%.1fx  Shield:%d%%" % [
		m_temp, m_rh, m_wind, int(rain_shield * 100.0)
	]
	
	# Update Forecast
	# A full day in _time_elapsed units is exactly the day_duration (60.0)
	var day_offset = day_night_cycle.day_duration
	var current_day_idx = floor(weather_manager._time_elapsed / day_offset)
	
	for i in range(7):
		var target_day = current_day_idx + i
		var time_eval = (target_day + 0.5) * day_offset
		
		var raw_temp = weather_manager.noise_temp.get_noise_1d(time_eval)
		var raw_rh = weather_manager.noise_rh.get_noise_1d(time_eval)
		var raw_wind = weather_manager.noise_wind.get_noise_1d(time_eval)
		
		var f_temp = remap(raw_temp, -1.0, 1.0, weather_manager.temp_min, weather_manager.temp_max)
		var f_rh = remap(raw_rh, -1.0, 1.0, weather_manager.rh_min, weather_manager.rh_max)
		
		var condition = "Clear"
		var f_cond_color = Color(0.6, 0.9, 0.6)
		if f_rh >= weather_manager.rh_rain_threshold:
			var raw_rain = weather_manager.noise_rain.get_noise_1d(time_eval)
			var f_rain = remap(raw_rain, -1.0, 1.0, weather_manager.rain_min, weather_manager.rain_max)
			if f_rain > 3.0: 
				condition = "Heavy Rain"
				f_cond_color = Color(0.4, 0.5, 0.8)
			else: 
				condition = "Rain"
				f_cond_color = Color(0.5, 0.7, 0.9)
		elif f_rh > 70.0:
			condition = "Cloudy"
			f_cond_color = Color(0.7, 0.7, 0.75)
		elif f_rh > 45.0:
			condition = "Partly Cloudy"
			f_cond_color = Color(0.8, 0.8, 0.7)
		
		var row = forecast_rows[i]
		var day_lbl = row.get_child(0) as Label
		var cond_lbl = row.get_child(1) as Label
		var details_lbl = row.get_child(2) as Label
		
		day_lbl.text = "Today" if i == 0 else "Day %d" % target_day
		
		cond_lbl.text = condition
		cond_lbl.add_theme_color_override("font_color", f_cond_color)
		
		details_lbl.text = "%.1f°  %d%%" % [f_temp, int(f_rh)]
