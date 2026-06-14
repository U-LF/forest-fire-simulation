shader_type particles;

uniform sampler2D burn_map : filter_linear;
uniform sampler2D height_map : filter_linear;
uniform float terrain_size = 4000.0;
uniform float noise_scale = 1400.0;
uniform float height_scale = 120.0;
uniform vec3 world_offset = vec3(0.0);
uniform float spawn_radius = 500.0;

// High-quality Spatial Hash (Dave Hoskins hash12)
// Completely eliminates grid banding and center-stacking artifacts
float rand(vec2 p) {
    vec3 p3  = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

void start() {
    vec2 base_seed = vec2(float(INDEX), TIME);
    vec2 pos = vec2(0.0);
    bool found_fire = false;

    // Stochastic Spawning: Find areas on fire but NOT yet fully charred
    for (int i = 0; i < 40; i++) {
        // High-quality random distribution to absolutely prevent banding/stacking
        float u = rand(base_seed + vec2(float(i) * 1.34, 12.1));
        float v = rand(base_seed + vec2(float(i) * 3.71, 55.4));
        float angle = u * 6.2831853;
        float r = sqrt(v) * spawn_radius;
        
        pos.x = world_offset.x + cos(angle) * r;
        pos.y = world_offset.z + sin(angle) * r;

        vec2 uv = (pos / terrain_size) + 0.5;
        vec4 state = texture(burn_map, uv);

        if (state.r > 0.1 && state.g < 0.85) {
            found_fire = true;
            break;
        }
    }

    // Store fixed world position in CUSTOM.xy
    CUSTOM.x = pos.x;
    CUSTOM.y = pos.y;

    // Store height in CUSTOM.z
    vec2 uv_noise = (pos / noise_scale) + 0.5;
    float h = textureLod(height_map, uv_noise, 0.0).r;
    CUSTOM.z = smoothstep(0.1, 0.95, h) * height_scale;

    // Store random seed for life phase in CUSTOM.w (using positive/negative for visibility)
    float seed = rand(base_seed + vec2(3.0, 3.0));
    
    TRANSFORM[0] = vec4(0.0);
    TRANSFORM[1] = vec4(0.0);
    TRANSFORM[2] = vec4(0.0);
    
    if (!found_fire) {
        CUSTOM.w = -seed - 100.0; // Negative means hidden
        // CRITICAL: Push instantly underground so Billboard material doesn't draw a 1-frame ghost
        TRANSFORM[3] = vec4(0.0, -1000.0, 0.0, 1.0);
    } else {
        CUSTOM.w = seed;
        TRANSFORM[3] = vec4(CUSTOM.x, CUSTOM.z, CUSTOM.y, 1.0);
    }
}

void process() {
    if (CUSTOM.w < 0.0) {
        TRANSFORM[0] = vec4(0.0);
        TRANSFORM[1] = vec4(0.0);
        TRANSFORM[2] = vec4(0.0);
        TRANSFORM[3] = vec4(0.0, -1000.0, 0.0, 1.0);
    } else {
        vec2 uv_burn = (CUSTOM.xy / terrain_size) + 0.5;
        vec4 burn_state = textureLod(burn_map, uv_burn, 0.0);
        float fire = burn_state.r;
        float char_lvl = burn_state.g;

        // Kill fire particles as soon as the area is mostly charred
        if (fire > 0.05 && char_lvl < 0.9) {
            float seed = CUSTOM.w;
            float life = fract(TIME * 0.5 + seed); // Slower, more stable life

            // Organic Scaling: Taller than wide, with random variation per particle
            float base_width = (fire * 2.0) + (rand(vec2(seed, 1.0)) * 3.0); // Width: 2.0 to 5.0
            float h_stretch = 1.5 + (rand(vec2(seed, 2.0)) * 1.5); // Height multiplier: 1.5x to 3.0x
            
            float base_height = base_width * h_stretch;
            float y_offset = base_height * 0.45; // Offset based on actual scaled height to keep grounded

            float current_s = base_width * (0.8 + 0.2 * sin(life * 3.1415)); // Pulse effect
            
            // Apply scale to TRANSFORM: Scale Y independently to stretch the flame
            TRANSFORM[0] = vec4(current_s, 0.0, 0.0, 0.0);
            TRANSFORM[1] = vec4(0.0, current_s * h_stretch, 0.0, 0.0);
            TRANSFORM[2] = vec4(0.0, 0.0, current_s, 0.0);
            TRANSFORM[3] = vec4(CUSTOM.x, CUSTOM.z + y_offset, CUSTOM.y, 1.0);
        } else {
            TRANSFORM[0] = vec4(0.0);
            TRANSFORM[1] = vec4(0.0);
            TRANSFORM[2] = vec4(0.0);
            TRANSFORM[3] = vec4(0.0, -1000.0, 0.0, 1.0);
        }
    }
}