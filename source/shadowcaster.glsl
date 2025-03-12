@header package game
@header import sg "sokol/gfx"
@ctype mat4 Mat4

@vs vs
layout(binding=0) uniform shadowcaster_vs_params {
    mat4 mvp;
};

layout(location=0) in vec4 pos;
layout(location=1) in vec3 normal;
layout(location=2) in vec2 texcoord;
layout(location=3) in vec4 color0;

void main() {
    float thing = normal.x * texcoord.x * color0.x;

    gl_Position = mvp * pos + thing*0.000001;
}
@end

@fs fs

out vec4 frag_color;

void main() {
    frag_color = vec4(1,1,1,1);
}
@end

@program shadowcaster vs fs
