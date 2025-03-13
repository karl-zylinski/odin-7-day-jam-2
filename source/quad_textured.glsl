@header package game
@header import sg "sokol/gfx"

@vs vs
in vec4 position;
in vec2 texcoord0;
out vec4 color;
out vec2 texcoord;

void main() {
    gl_Position = position;
    texcoord = texcoord0;
}
@end

@fs fs
in vec4 color;
in vec2 texcoord;
out vec4 frag_color;
layout(binding=0) uniform texture2D tex;
layout(binding=0) uniform sampler smp;

float decode_depth(vec4 rgba) {
    return dot(rgba, vec4(1.0, 1.0/255.0, 1.0/65025.0, 1.0/16581375.0));
}

void main() {
    vec4 c = texture(sampler2D(tex, smp), texcoord);
    float d = decode_depth(c);


    d -= 0.8;
    d *= 10;

    frag_color = vec4(d,d,d,1);
}
@end

@program quad_textured vs fs