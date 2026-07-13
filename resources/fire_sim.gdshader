shader_type canvas_item;
render_mode blend_disabled;

uniform sampler2D state_tex : filter_nearest, repeat_disable;
uniform sampler2D fuel_map : filter_nearest, repeat_disable;
uniform vec2 ignite_pos = vec2(-1.0, -1.0);
uniform float ignite_radius = 0.002;

// Atmospheric Parameters for Propagation
uniform float current_temp = 20.0;
uniform float current_rh = 50.0;
uniform float current_wind = 2.0;
uniform vec2 current_wind_dir = vec2(1.0, 0.0);
uniform float current_rain = 0.0;
uniform float current_moisture = 0.0;
uniform float sim_speed = 1.0;
uniform float delta_time = 0.0166;
uniform float global_time = 0.0;

// High-quality Spatial Hash (Dave Hoskins hash12)
float rand(vec2 p) {
    vec3 p3  = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
    vec2 uv = UV;
    vec4 state = texture(state_tex, uv);
    
    // Initialization: Red=Fire, Green=Char, Blue=Fuel, Alpha=Heat
    if (length(state.rgb) < 0.01 && state.a < 0.01) {
        // Fetch the initial fuel from the procedurally generated fuel map
        state = vec4(0.0, 0.0, texture(fuel_map, uv).r, 0.0);
    }
    
    float fire = state.r;
    float char_lvl = state.g;
    float fuel = state.b;
    float heat = state.a;
    
    // --- 1. THE SPREAD (Heat Accumulation & Directional Wind) ---
    if (fuel > 0.0 && fire < 0.1) {
        vec2 texel = 1.0 / vec2(textureSize(state_tex, 0));
        
        vec4 s_up = texture(state_tex, uv + vec2(0.0, -texel.y));
        vec4 s_down = texture(state_tex, uv + vec2(0.0, texel.y));
        vec4 s_left = texture(state_tex, uv + vec2(-texel.x, 0.0));
        vec4 s_right = texture(state_tex, uv + vec2(texel.x, 0.0));
        
        float incoming_heat = 0.0;
        float rad_base = 5.0; // INCREASED: Base heat radiation per second (Real fires spread fast)
        
        // Directional Wind Multipliers
        // Wind blows FROM neighbor TO us.
        // In Godot 2D Texture Space: +X is Right, +Y is Down.
        vec2 dir_from_up = vec2(0.0, 1.0);
        vec2 dir_from_down = vec2(0.0, -1.0);
        vec2 dir_from_left = vec2(1.0, 0.0);
        vec2 dir_from_right = vec2(-1.0, 0.0);
        
        if (s_up.r > 0.05) {
            float wind_dot = dot(current_wind_dir, dir_from_up);
            float w_factor = 1.0 + max(0.0, wind_dot) * current_wind * 2.0 - max(0.0, -wind_dot) * (current_wind * 0.5);
            incoming_heat += s_up.r * s_up.b * rad_base * w_factor;
        }
        if (s_down.r > 0.05) {
            float wind_dot = dot(current_wind_dir, dir_from_down);
            float w_factor = 1.0 + max(0.0, wind_dot) * current_wind * 2.0 - max(0.0, -wind_dot) * (current_wind * 0.5);
            incoming_heat += s_down.r * s_down.b * rad_base * w_factor;
        }
        if (s_left.r > 0.05) {
            float wind_dot = dot(current_wind_dir, dir_from_left);
            float w_factor = 1.0 + max(0.0, wind_dot) * current_wind * 2.0 - max(0.0, -wind_dot) * (current_wind * 0.5);
            incoming_heat += s_left.r * s_left.b * rad_base * w_factor;
        }
        if (s_right.r > 0.05) {
            float wind_dot = dot(current_wind_dir, dir_from_right);
            float w_factor = 1.0 + max(0.0, wind_dot) * current_wind * 2.0 - max(0.0, -wind_dot) * (current_wind * 0.5);
            incoming_heat += s_right.r * s_right.b * rad_base * w_factor;
        }
        
        // Accumulate incoming heat
        heat += incoming_heat * delta_time * sim_speed;
        
        // Environmental Cooling (Dissipates heat over time)
        float cooling = 0.5; // LOWERED: Base cooling per second
        cooling += smoothstep(30.0, 100.0, current_rh) * 1.5; 
        cooling -= smoothstep(15.0, 35.0, current_temp) * 0.5; 
        cooling += current_moisture * 10.0; 
        cooling += current_rain * 5.0; 
        
        heat -= cooling * delta_time * sim_speed;
        heat = max(0.0, heat);
        
        // Absolute Dew Point / Dampness Cutoff
        if (current_rh > 85.0 && current_wind < 4.0) {
            heat = 0.0; // Too damp to ever ignite naturally
        }
        
        // Ignition Threshold
        // Grass (0.4 fuel) needs ~0.16 heat. Tree (1.0 fuel) needs 0.4 heat.
        float threshold = fuel * 0.4; // LOWERED: Trees ignite at lower heat loads
        if (heat > threshold && fuel > 0.0 && incoming_heat > 0.0) {
            fire = 0.2; // IGNITE
        }
    }
    
    // External Ignition (Laser/Lightning)
    if (distance(uv, ignite_pos) < ignite_radius) {
        fire = 1.0; 
    }
    
    // --- 2. THE ATTACK & 3. THE EXTINGUISHMENT (Suppression) ---
    if (fire > 0.0 || heat > 0.0) {
        // Flare up logic
        if (fire > 0.05 && fire < 1.0 && fuel > 0.0) {
            fire = min(1.0, fire + 1.2 * delta_time * sim_speed);
            heat = min(1.0, heat + 0.6 * delta_time * sim_speed);
        }
        
        // Rain Attack: Physically crushes intensity and heat
        // Heavier rain (up to 6.4mm) suppresses faster.
        float rain_attack = current_rain * 0.3 * delta_time * sim_speed;
        fire = max(0.0, fire - rain_attack);
        heat = max(0.0, heat - (rain_attack * 0.5));
        
        // Burning consumption (Takes ~21s to burn 1.0 fuel at 60fps)
        if (fire > 0.05) {
            fuel -= 0.048 * delta_time * sim_speed;
            char_lvl = min(1.0, char_lvl + 0.06 * delta_time * sim_speed);
        }
        
        // Natural burnout or Premature Kill
        // If fire is killed by rain (fire <= 0.0) but fuel remains (> 0.0), it's preserved.
        if (fuel <= 0.0) {
            fuel = 0.0;
            fire = max(0.0, fire - 1.2 * delta_time * sim_speed);
            heat = max(0.0, heat - 0.03 * delta_time * sim_speed);
        }
    }
    
    fire = clamp(fire, 0.0, 1.0);
    char_lvl = clamp(char_lvl, 0.0, 1.0);
    fuel = clamp(fuel, 0.0, 1.0);
    heat = clamp(heat, 0.0, 1.0);
    
    COLOR = vec4(fire, char_lvl, fuel, heat);
}
