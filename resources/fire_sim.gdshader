shader_type canvas_item;

uniform sampler2D state_tex : filter_nearest, repeat_disable;
uniform vec2 ignite_pos = vec2(-1.0, -1.0);
uniform float ignite_radius = 0.002; // Reduced back to 8m radius

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
    if (length(state.rgb) < 0.1) {
        state = vec4(0.0, 0.0, 1.0, 1.0); // Pure Fuel
    }
    
    float fire = state.r;
    float char_lvl = state.g;
    float fuel = state.b;
    
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
        
        float neighbor_fire_cross = max(max(fire_up, fire_down), max(fire_left, fire_right));
        float neighbor_fire_diag = max(max(fire_ul, fire_ur), max(fire_dl, fire_dr));
        float neighbor_fire = max(neighbor_fire_cross, neighbor_fire_diag);
        
        // Organic, perfectly isotropic spread using hash
        if (neighbor_fire > 0.5) {
            float r = rand(uv * 100.0 + vec2(TIME));
            if (r < 0.05) { // 5% chance to catch fire (5x faster spread)
                fire += 0.2; // Faster initial catch
            }
        }
        
        if (distance(uv, ignite_pos) < ignite_radius) {
            fire = 1.0; 
        }
    }
    
    // Fast burn logic for testing
    if (fire > 0.0) {
        if (fire > 0.05 && fuel > 0.0) { 
            fire = min(1.0, fire + 0.1); // Rapid flare up
        }
        
        fuel -= 0.005; // ~3.3 seconds to burn out
        char_lvl += 0.01; // Rapid charring
        
        if (fuel <= 0.0) {
            fuel = 0.0;
            fire -= 0.1; // Rapid die down
        }
    }    
    fire = clamp(fire, 0.0, 1.0);
    char_lvl = clamp(char_lvl, 0.0, 1.0);
    
    COLOR = vec4(fire, char_lvl, fuel, 1.0);
}