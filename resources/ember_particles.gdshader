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
    bool found_source = false;

    // Stochastic Spawning: Find areas that are heavily charred but still "hot"
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
        float char_lvl = state.g;
        float heat = state.a; // Explicit heat channel

        // --- Delayed & Cooling Logic ---
        // Spawn based on explicit heat channel
        if (char_lvl > 0.6 && heat > 0.05) {
            if (rand(base_seed + vec2(float(i) * 2.1, 0.7)) < (0.1 + heat * 0.9)) {
                found_source = true;
                break;
            }
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

    if (!found_source) {
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
        float char_lvl = burn_state.g;
        float heat = burn_state.a;

        // Embers persist in charred areas but scale/intensity depends on explicit "heat"
        if (char_lvl > 0.5 && heat > 0.01) {
            float seed = CUSTOM.w;

            float life_speed = 0.2 + (seed * 0.3); 
            float life = fract(TIME * life_speed + seed);

            // Rising air slows down as it cools
            float lift = pow(life, 0.7) * (5.0 + heat * 10.0); 

            float freq = 6.0 + seed * 4.0;
            float jitter_x = sin(TIME * 1.5 + life * freq + seed * 100.0) * (0.4 + heat * 0.4);
            float jitter_z = cos(TIME * 1.2 + life * freq + seed * 150.0) * (0.4 + heat * 0.4);

            // Size shrinks as heat decays
            float s_base = (0.05 + heat * 0.15) + (seed * 0.1); 
            float s_curve = sin(life * 3.1415);
            float s = s_base * s_curve;

            TRANSFORM[0] = vec4(s, 0.0, 0.0, 0.0);
            TRANSFORM[1] = vec4(0.0, s, 0.0, 0.0);
            TRANSFORM[2] = vec4(0.0, 0.0, s, 0.0);
            // Use locked CUSTOM.x/y/z for base position
            TRANSFORM[3] = vec4(CUSTOM.x + jitter_x, CUSTOM.z + lift + 0.5, CUSTOM.y + jitter_z, 1.0);
            
        } else {
            TRANSFORM[0] = vec4(0.0);
            TRANSFORM[1] = vec4(0.0);
            TRANSFORM[2] = vec4(0.0);
            TRANSFORM[3] = vec4(0.0, -1000.0, 0.0, 1.0);
        }
    }
}