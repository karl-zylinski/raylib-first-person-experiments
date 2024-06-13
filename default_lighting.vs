#version 330

in vec3 vertex_position;
in vec2 vertex_texcoord;
in vec3 vertex_normal;

uniform mat4 mvp;
uniform mat4 mat_model;
uniform mat4 mat_normal;

out vec3 frag_world_pos;
out vec2 frag_texcoord;

void main() {
    frag_world_pos = vec3(mat_model*vec4(vertex_position, 1.0));
    frag_texcoord = vertex_texcoord;
    frag_normal = normalize(vec3(mat_normal*vec4(vertex_normal, 1.0)));
    gl_Position = mvp*vec4(vertex_position, 1.0);
}