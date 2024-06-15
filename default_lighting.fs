#version 330

in vec3 frag_world_pos;
in vec2 frag_texcoord;
in vec3 frag_normal;

out vec4 out_color;

#define     MAX_LIGHTS              4
#define     LIGHT_NONE              0
#define     LIGHT_DIRECTIONAL       1
#define     LIGHT_POINT             2

struct Light {
	int type;
	vec3 position;
	vec3 target;
	vec4 color;
};

uniform mat4 transf_light_vp; // Light source view-projection matrix
uniform sampler2D tex_shadow_map;
uniform vec3 position_camera;
uniform Light lights[MAX_LIGHTS];
uniform sampler2D tex_atlas;

const vec3 COLOR_SHADOW = vec3(0.329, 0.349, 0.631);
const vec3 COLOR_LIGHT = vec3(0.922, 0.686, 0.329);

float remap(float old_value, float old_min, float old_max, float new_min, float new_max) {
	float old_range = old_max - old_min;
	float new_range = new_max - new_min;
	if (old_range == 0) {
		return new_range / 2;
	}
	return clamp(((old_value - old_min) / old_range) * new_range + new_min, new_min, new_max);
}

void main() {
	vec4 tex_color = texture(tex_atlas, frag_texcoord);

	tex_color = mix(vec4(1), tex_color, step(0, frag_texcoord.x));

	if (tex_color.a == 0.0) {
		discard;
	}

	vec3 light_color = vec3(0.0);
	vec3 normal = normalize(frag_normal);
	vec3 directional_light_dir;

	float num_lights = 0;
	for (int i = 0; i < MAX_LIGHTS; i++) {
		if (lights[i].type != LIGHT_NONE) {
			vec3 light = vec3(0.0);
			float falloff = 0;

			if (lights[i].type == LIGHT_DIRECTIONAL) {
				light = -normalize(lights[i].target - lights[i].position);
				directional_light_dir = light;
			}

			if (lights[i].type == LIGHT_POINT) {
				vec3 dir = lights[i].position - frag_world_pos;
				falloff = remap(length(dir), 0, 5, 0, 1);
				light = normalize(dir);
			}

			float light_ramp_param = (dot(normal, light) + 1)/2;
			vec3 light_ramp_color = mix(COLOR_SHADOW, COLOR_LIGHT, light_ramp_param);
			light_color += lights[i].color.rgb*light_ramp_color*(1-falloff);
			num_lights += 1;
		}
	}

    vec4 world_pos_light_space = transf_light_vp * vec4(frag_world_pos, 1);
    world_pos_light_space.xyz /= world_pos_light_space.w; // Perform the perspective division
    world_pos_light_space.xyz = (world_pos_light_space.xyz + 1.0f) / 2.0f; // Transform from [-1, 1] range to [0, 1] range
    vec2 shadow_map_coords = world_pos_light_space.xy;
    float depth_light_space = world_pos_light_space.z;

    // Bias using normal to make less noisy.
    float bias = 0.00001 * tan(acos(dot(normal, directional_light_dir))); // Alternatives: float bias = 0.0001; or perhaps float bias = max(0.0001 * (1.0 - dot(normal, l)), 0.00002) + 0.00001;
    
    const int NUM_SHADOW_SAMPLES = 9; // 3*3 samples

    // TODO: Make the 4096 come from outside if we change lightmap res
    const vec2 TEXEL_SIZE = vec2(1.0f / 4096.0f);

    int shadow_counter = 0;

    // This is apparently called "Percentage Closer Filter" (PCF), i.e. a multi-tap AA.
    for (int x = -1; x <= 1; x++) {
        for (int y = -1; y <= 1; y++) {
            float shadow_map_depth = texture(tex_shadow_map, shadow_map_coords + TEXEL_SIZE * vec2(x, y)).r;

            if (depth_light_space - bias > shadow_map_depth) {
                shadow_counter++;
            }
        }
    }

    float distance_to_camera = length(position_camera - frag_world_pos);
    float distance_darkening = remap(distance_to_camera, 2, 5, 0, 0.2);

    if (dot(normal, vec3(0, 1, 0)) > 0.5) {
    	light_color *= 1 + distance_darkening+0.1;
    }

    light_color = mix(light_color, COLOR_SHADOW, float(shadow_counter) / float(NUM_SHADOW_SAMPLES));
	out_color = tex_color*vec4(light_color, 1) - vec4(0, distance_darkening, distance_darkening, 0);

	// Gamma correction
	out_color = pow(out_color, vec4(1.0/2.2));
}