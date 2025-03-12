@header package game
@header import sg "sokol/gfx"
@ctype mat4 Mat4

@vs vs
layout(binding=0) uniform vs_params {
	mat4 mvp;
	mat4 model;
};

layout(location=0) in vec3 pos;
layout(location=1) in vec3 normal;
layout(location=2) in vec2 texcoord;
layout(location=3) in vec4 color0;

out vec2 uv;
out vec3 fs_normal;
out vec3 world_pos;

void main() {
	float thing = color0.x * 0.00001;
	world_pos = (model * vec4(pos, 1)).xyz;
	gl_Position = mvp * vec4(pos, 1);
	uv = texcoord;
	fs_normal = (model * vec4(normal, 0)).xyz + thing;
}
@end

@fs fs
layout(binding=1) uniform fs_params {
	vec3 sun_position;
	vec3 camera_pos;
	vec4 model_color;
	mat4 shadowcaster_vp;
};

layout(binding=2) uniform texture2D tex_shadow_map;
layout(binding=3) uniform sampler smp_shadow_map;

in vec2 uv;
in vec3 fs_normal;
in vec3 world_pos;
out vec4 frag_color;


float remap(float old_value, float old_min, float old_max, float new_min, float new_max) {
	float old_range = old_max - old_min;
	float new_range = new_max - new_min;
	if (old_range == 0) {
		return new_range / 2;
	}
	return clamp(((old_value - old_min) / old_range) * new_range + new_min, new_min, new_max);
}

float decodeDepth(vec4 rgba) {
    return dot(rgba, vec4(1.0, 1.0/255.0, 1.0/65025.0, 1.0/16581375.0));
}

void main() {
	float l = max(dot(normalize(fs_normal), normalize(sun_position)), 0.4);
	vec3 l3 = vec3(l, l*0.9, l*0.9);

	vec4 world_pos_light_space = shadowcaster_vp * vec4(world_pos, 1);
	world_pos_light_space.xyz /= world_pos_light_space.w; // Perform the perspective division
	vec2 shadow_map_coords;
	#if SOKOL_GLSL
	shadow_map_coords.x = (world_pos_light_space.x + 1)/2.0;
	shadow_map_coords.y = (world_pos_light_space.y + 1)/2.0;
	#else
	shadow_map_coords.x = world_pos_light_space.x / 2.0 + 0.5f;
	shadow_map_coords.y = -world_pos_light_space.y / 2.0 + 0.5f;
	#endif
	//shadow_map_coords.y = 1-shadow_map_coords.y;
	float depth_light_space = world_pos_light_space.z;

	// Bias using normal to make less noisy.

	float bias = 0.00002 * tan(acos(clamp(dot(normalize(fs_normal), normalize(sun_position)), 0, 1))); // Alternatives: float bias = 0.0001; or perhaps float bias = max(0.0001 * (1.0 - dot(normal, l)), 0.00002) + 0.00001;
	
	const vec2 TEXEL_SIZE = vec2(1.0f / 4096.0f);
	const int NUM_SHADOW_SAMPLES = 9; // 3*3 samples
	int shadow_counter = 0;

	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			float shadow_map_depth = decodeDepth(texture(sampler2D(tex_shadow_map, smp_shadow_map), shadow_map_coords + TEXEL_SIZE * vec2(x, y)));

			if (depth_light_space - bias > shadow_map_depth) {
				shadow_counter++;
			}
		}
	}

	vec3 light_color = vec3(1.0, 0.95, 1.0);
	vec3 shadow_color = vec3(0.5, 0.5, 0.7);

	float distance_to_camera = length(camera_pos - world_pos);
	float distance_darkening = remap(distance_to_camera, 2, 10, 0, 0.1);

	if (dot(fs_normal, vec3(0, 1, 0)) > 0.5) {
	   // light_color *= 1 + distance_darkening+0.1;
	}

	float fog_factor = (clamp((50-abs(distance_to_camera))/(50-5), 0, 1)) ;

	light_color = mix(light_color, shadow_color, float(shadow_counter) / float(NUM_SHADOW_SAMPLES));
	frag_color = vec4(model_color.rgb*l3*light_color,1) - vec4(0, distance_darkening, distance_darkening, 0);
	frag_color = pow(frag_color, vec4(1.0/2.2));
	frag_color.rgb = fog_factor * frag_color.rgb + (1-fog_factor)*vec3(0.7, 0.48, 0.6);
	
  //  frag_color = vec4(shadow_map_coords.xy, 0, 1);
}
@end

@program texcube vs fs

