shader_type canvas_item;
render_mode blend_disabled;

uniform sampler2D state_tex : filter_nearest, repeat_disable;
uniform vec2 ignite_pos = vec2(-1.0, -1.0);
uniform float ignite_radius = 0.002;

// Atmospheric Parameters for Propagation
uniform float current_temp = 20.0;
uniform float current_rh = 50.0;
uniform float current_wind = 2.0;
uniform float current_rain = 0.0;
uniform float current_moisture = 0.0;
uniform float sim_speed = 1.0;

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
        state = vec4(0.0, 0.0, 1.0, 0.0);
    }
    
    float fire = state.r;
    float char_lvl = state.g;
    float fuel = state.b;
    float heat = state.a;
    
    // --- 1. THE SHIELD (Spread Prevention) ---
    // Rain volume makes spread rapidly drop to zero.
    if (fuel > 0.0 && fire < 0.1) {
        vec2 texel = 1.0 / vec2(textureSize(state_tex, 0));
        float fire_up = texture(state_tex, uv + vec2(0.0, -texel.y)).r;
        float fire_down = texture(state_tex, uv + vec2(0.0, texel.y)).r;
        float fire_left = texture(state_tex, uv + vec2(-texel.x, 0.0)).r;
        float fire_right = texture(state_tex, uv + vec2(texel.x, 0.0)).r;
        float neighbor_fire = max(max(fire_up, fire_down), max(fire_left, fire_right));
        
        if (neighbor_fire > 0.5) {
            float p_base = 0.2;
            float m_temp = mix(0.5, 1.5, smoothstep(2.2, 33.3, current_temp));
            float m_rh;
            if (current_rh <= 30.0) m_rh = mix(2.0, 1.5, smoothstep(15.0, 30.0, current_rh));
            else if (current_rh >= 80.0) m_rh = mix(0.3, 0.1, smoothstep(80.0, 100.0, current_rh));
            else m_rh = mix(1.5, 0.3, smoothstep(30.0, 80.0, current_rh));
            
            float m_wind = mix(1.0, 2.5, smoothstep(0.4, 9.4, current_wind));
            
            // --- 1. THE MOISTURE SHIELD ---
            // The shield is now driven by current_moisture, which persists after rain stops.
            // 1.0 moisture = 100% shield (0% spread probability)
            float spread_shield = current_moisture; 
            float p_ignite = (p_base * m_temp * m_rh * m_wind) * (1.0 - spread_shield);
            
            float r = rand(uv * 100.0 + vec2(TIME));
            if (r < p_ignite * 0.02 * sim_speed) { 
                fire = 0.2; 
            }
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
            fire = min(1.0, fire + 0.02 * sim_speed);
            heat = min(1.0, heat + 0.01 * sim_speed);
        }
        
        // Rain Attack: Physically crushes intensity and heat
        // Heavier rain (up to 6.4mm) suppresses faster.
        float rain_attack = current_rain * 0.005 * sim_speed;
        fire = max(0.0, fire - rain_attack);
        heat = max(0.0, heat - (rain_attack * 0.5));
        
        // Burning consumption
        if (fire > 0.05) {
            fuel -= 0.0008 * sim_speed;
            char_lvl = min(1.0, char_lvl + 0.001 * sim_speed);
        }
        
        // Natural burnout or Premature Kill
        // If fire is killed by rain (fire <= 0.0) but fuel remains (> 0.0), it's preserved.
        if (fuel <= 0.0) {
            fuel = 0.0;
            fire = max(0.0, fire - 0.02 * sim_speed);
            heat = max(0.0, heat - 0.0005 * sim_speed);
        }
    }
    
    fire = clamp(fire, 0.0, 1.0);
    char_lvl = clamp(char_lvl, 0.0, 1.0);
    fuel = clamp(fuel, 0.0, 1.0);
    heat = clamp(heat, 0.0, 1.0);
    
    COLOR = vec4(fire, char_lvl, fuel, heat);
}
