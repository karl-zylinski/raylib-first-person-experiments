#version 330

in vec3 vertex_position;
in vec2 vertex_texcoord;
in vec3 vertex_normal;

uniform mat4 mvp_tf;
uniform mat4 model_tf;
uniform mat4 normal_tf;

out vec3 frag_world_pos;
out vec2 frag_texcoord;

void main() {
    frag_world_pos = vec3(model_tf*vec4(vertex_position, 1.0));
    frag_texcoord = vertex_texcoord;
    frag_normal = normalize(vec3(normal_tf*vec4(vertex_normal, 1.0)));
    gl_Position = mvp_tf*vec4(vertex_position, 1.0);
}