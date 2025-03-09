@header package game
@header import sg "sokol/gfx"
@ctype mat4 Mat4

@vs vs
layout(binding=0) uniform vs_params {
    mat4 mvp;
    mat4 model;
    vec3 sun;
};

layout(location=0) in vec4 pos;
layout(location=1) in vec3 normal;
layout(location=2) in vec2 texcoord;
layout(location=3) in vec4 color0;

out vec2 uv;
out vec3 fs_normal;
out vec3 world_pos;

void main() {
    world_pos = (model * pos).xyz;
    gl_Position = mvp * pos;
    uv = texcoord;
    fs_normal = (model * vec4(normal, 0)).xyz;
}
@end

@fs fs
layout(binding=1) uniform fs_params {
    vec3 sun;
    vec4 model_color;
};


in vec2 uv;
in vec3 fs_normal;
in vec3 world_pos;
out vec4 frag_color;

void main() {
    vec3 sun_dir = normalize(sun - world_pos);
    float l = max(dot(normalize(fs_normal), sun_dir), 0.4);
    vec3 l3 = vec3(l, l*0.9, l*0.9);
    frag_color = vec4(model_color.rgb*l3,1);
}
@end

@program texcube vs fs
