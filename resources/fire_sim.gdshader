shader_type canvas_item;

uniform sampler2D state_tex : filter_nearest, repeat_disable;
uniform vec2 ignite_pos = vec2(-1.0, -1.0);
uniform float ignite_radius = 0.002; // Reduced back to 8m radius

// Pseudorandom generator for organic spread
float rand(vec2 co) {
    return fract(sin(dot(co.xy, vec2(12.9898, 78.233))) * 43758.5453);
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
        
        float neighbor_fire = max(max(fire_up, fire_down), max(fire_left, fire_right));
        
        // Organic, slow spread: Only jump to new tiles randomly
        if (neighbor_fire > 0.5) {
            float r = rand(uv + vec2(TIME));
            if (r < 0.01) { // 1% chance to catch fire per frame (Visibly creeping spread)
                fire += 0.05; 
            }
        }
        
        if (distance(uv, ignite_pos) < ignite_radius) {
            fire = 1.0; // Manual ignition
        }
    }
    
    // Burn logic
    if (fire > 0.0) {
        if (fire > 0.05 && fuel > 0.0) { 
            fire = min(1.0, fire + 0.01); // Gradual flare up rather than instant explosion
        }
        
        fuel -= 0.0005; // 2000 frames to burn out (~33 seconds)
        char_lvl += 0.001; 
        
        if (fuel <= 0.0) {
            fuel = 0.0;
            fire -= 0.01; // Die down smoothly
        }
    }
    
    fire = clamp(fire, 0.0, 1.0);
    char_lvl = clamp(char_lvl, 0.0, 1.0);
    
    COLOR = vec4(fire, char_lvl, fuel, 1.0);
}