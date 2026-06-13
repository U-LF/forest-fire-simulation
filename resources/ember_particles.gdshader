shader_type particles;

uniform sampler2D burn_map : filter_linear;
uniform sampler2D height_map : filter_linear;
uniform float terrain_size = 4000.0;
uniform float noise_scale = 1400.0;
uniform float height_scale = 120.0;
uniform vec3 world_offset = vec3(0.0);
uniform float spawn_radius = 600.0;

float rand(vec2 co){
    return fract(sin(dot(co.xy ,vec2(12.9898,78.233))) * 43758.5453);
}

void start() {
    float id = float(INDEX) + TIME;
    vec2 pos = vec2(0.0);
    bool found_char = false;
    
    // Stochastic Spawning: Find charred areas
    for (int i = 0; i < 30; i++) {
        float angle = rand(vec2(id, float(i))) * 6.28318;
        float r = sqrt(rand(vec2(id, float(i) + 0.5))) * spawn_radius;
        pos.x = world_offset.x + cos(angle) * r;
        pos.y = world_offset.z + sin(angle) * r;
        
        vec2 uv = (pos / terrain_size) + 0.5;
        vec4 state = texture(burn_map, uv);
        if (state.g > 0.3) { // Charred area
            found_char = true;
            break;
        }
    }
    
    CUSTOM.x = pos.x;
    CUSTOM.y = pos.y;
    CUSTOM.z = rand(vec2(id, 3.0)); // Random life phase
    
    if (!found_char) {
        CUSTOM.w = -1000.0; // Hide particle
    } else {
        CUSTOM.w = 1.0;
    }
}

void process() {
    if (CUSTOM.w < 0.0) {
        TRANSFORM[0][0] = 0.0;
        TRANSFORM[1][1] = 0.0;
        TRANSFORM[2][2] = 0.0;
    } else {
        vec2 uv_burn = (CUSTOM.xy / terrain_size) + 0.5;
        
        vec4 burn_state = textureLod(burn_map, uv_burn, 0.0);
        float char_lvl = burn_state.g;
        
        if (char_lvl > 0.3) {
            vec2 uv_noise = (CUSTOM.xy / noise_scale) + 0.5;
            float h = textureLod(height_map, uv_noise, 0.0).r;
            h = smoothstep(0.1, 0.95, h) * height_scale;
            
            float life = fract(TIME * 0.5 + CUSTOM.z);
            
            float s = char_lvl * 0.5; // Embers are small
            
            float y_offset = life * 3.0; // Drift upwards slowly
            float x_drift = sin(life * 6.28 + CUSTOM.z * 10.0) * 1.5;
            float z_drift = cos(life * 6.28 + CUSTOM.z * 10.0) * 1.5;
            
            TRANSFORM[3].xyz = vec3(CUSTOM.x + x_drift, h + y_offset + 0.5, CUSTOM.y + z_drift); // Global world position
            
            float current_s = s * sin(life * 3.1415); // Fade in and out
            TRANSFORM[0][0] = current_s;
            TRANSFORM[1][1] = current_s;
            TRANSFORM[2][2] = current_s;
        } else {
            TRANSFORM[0][0] = 0.0;
            TRANSFORM[1][1] = 0.0;
            TRANSFORM[2][2] = 0.0;
        }
    }
}