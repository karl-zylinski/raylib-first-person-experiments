#version 330

layout(location=0) in vec3 vertex_position;

uniform mat4 mvp;

out vec3 frag_world_pos;

void main() {
    // TODO: This probably needs to be untranslated from player_pos and be sent
    // down to frag shader as some kind of local space coord. Frag shader just uses it
    // for direction where it assumes box is at origin.
    frag_world_pos = vertex_position;
    gl_Position = mvp*vec4(vertex_position, 1.0);
}