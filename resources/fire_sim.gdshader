shader_type canvas_item;
render_mode blend_disabled;

uniform sampler2D state_tex : filter_nearest, repeat_disable;
uniform vec2 ignite_pos = vec2(-1.0, -1.0);
uniform float ignite_radius = 0.002; // Reduced back to 8m radius

// Atmospheric Parameters for Propagation
uniform float current_temp = 20.0;
uniform float current_rh = 50.0;
uniform float current_wind = 2.0;
uniform float current_rain = 0.0;
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
    
    // Aggressive initialization: if we are close to pure black (empty viewport), flood it with Fuel (Blue)
    if (length(state.rgb) < 0.1 && state.a < 0.1) {
        state = vec4(0.0, 0.0, 1.0, 0.0); // Pure Fuel, 0 Heat
    }
    
    float fire = state.r;
    float char_lvl = state.g;
    float fuel = state.b;
    float heat = state.a;
    
    // Spread logic
    if (fuel > 0.0) {
        vec2 texel = 1.0 / vec2(textureSize(state_tex, 0));
        float fire_up = texture(state_tex, uv + vec2(0.0, -texel.y)).r;
        float fire_down = texture(state_tex, uv + vec2(0.0, texel.y)).r;
        float fire_left = texture(state_tex, uv + vec2(-texel.x, 0.0)).r;
        float fire_right = texture(state_tex, uv + vec2(texel.x, 0.0)).r;
        float fire_ul = texture(state_tex, uv + vec2(-texel.x, -texel.y)).r;
        float fire_ur = texture(state_tex, uv + vec2(texel.x, -texel.y)).r;
        float fire_dl = texture(state_tex, uv + vec2(-texel.x, texel.y)).r;
        float fire_dr = texture(state_tex, uv + vec2(texel.x, texel.y)).r;
        
        float fire_cross = max(max(fire_up, fire_down), max(fire_left, fire_right));
        float fire_diag = max(max(fire_ul, fire_ur), max(fire_dl, fire_dr));
        float neighbor_fire = max(fire_cross, fire_diag);
        
        // --- Realistic Propagation Logic ---
        if (neighbor_fire > 0.5) {
            // 1. Base Probability (20%)
            float p_base = 0.2;
            
            // 2. Temperature Modifier (2.2°C to 33.3°C -> 0.5x to 1.5x)
            float m_temp = mix(0.5, 1.5, smoothstep(2.2, 33.3, current_temp));
            
            // 3. Humidity Modifier (Inverse Relationship)
            // Low (15-30%): Bone dry, acts as accelerant (1.5x to 2.0x)
            // High (80-100%): Saturated, acts as dampener (0.1x to 0.3x)
            float m_rh;
            if (current_rh <= 30.0) {
                m_rh = mix(2.0, 1.5, smoothstep(15.0, 30.0, current_rh));
            } else if (current_rh >= 80.0) {
                m_rh = mix(0.3, 0.1, smoothstep(80.0, 100.0, current_rh));
            } else {
                // Linear transition in the middle (30% to 80% -> 1.5x to 0.3x)
                m_rh = mix(1.5, 0.3, smoothstep(30.0, 80.0, current_rh));
            }
            
            // 4. Wind Modifier (0.4 to 9.4 km/h -> 1.0x to 2.5x)
            float m_wind = mix(1.0, 2.5, smoothstep(0.4, 9.4, current_wind));
            
            // 5. Rain Penalty (subtract up to 40%)
            float r_penalty = smoothstep(0.0, 6.4, current_rain) * 0.4;
            
            // Final Probability Calculation
            float p_ignite = (p_base * m_temp * m_rh * m_wind) - r_penalty;
            
            // Roll the dice
            float r = rand(uv * 100.0 + vec2(TIME));
            // Normalized for the high simulation framerate and scaled by sim_speed
            // Reduced spread frequency (0.02) to feel more "heavy"
            if (r < p_ignite * 0.02 * sim_speed) { 
                fire += 0.2; 
            }
        }
        
        if (distance(uv, ignite_pos) < ignite_radius) {
            fire = 1.0; 
        }
    }
    
    // Realistic burn logic for testing with explicit Heat lifecycle
    if (fire > 0.0 || heat > 0.0) {
        if (fire > 0.05 && fuel > 0.0) { 
            fire = min(1.0, fire + 0.02 * sim_speed); // Slower flare up
            heat = min(1.0, heat + 0.01 * sim_speed); // Slower heat up
        }
        
        if (fire > 0.0) {
            fuel -= 0.0008 * sim_speed; // ~1250 frames (approx 20 real seconds at 1x)
            char_lvl += 0.001 * sim_speed; // Slower charring
        }
        
        if (fuel <= 0.0) {
            fuel = 0.0;
            fire -= 0.02 * sim_speed; // Slower die down
            heat -= 0.0005 * sim_speed; // Slower cooling
        }
    }    
    fire = clamp(fire, 0.0, 1.0);
    char_lvl = clamp(char_lvl, 0.0, 1.0);
    fuel = clamp(fuel, 0.0, 1.0);
    heat = clamp(heat, 0.0, 1.0);
    
    COLOR = vec4(fire, char_lvl, fuel, heat);
}
