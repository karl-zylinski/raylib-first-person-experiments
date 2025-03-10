#version 330

layout(location=0) in vec3 vertex_position;
layout(location=1) in vec2 vertex_texcoord;

layout(location=6) in mat4 instance_transform;
layout(location=10)in vec4 instance_uv_remap;
uniform mat4 transf_mvp;

out vec2 frag_texcoord;

float remap(float old_value, float old_min, float old_max, float new_min, float new_max) {
    float old_range = old_max - old_min;
    float new_range = new_max - new_min;
    if (old_range == 0) {
        return new_range / 2;
    }
    return clamp(((old_value - old_min) / old_range) * new_range + new_min, new_min, new_max);
}

void main()
{
    frag_texcoord.x = remap(vertex_texcoord.x, 0, 1, instance_uv_remap.x, instance_uv_remap.y);
    frag_texcoord.y = remap(vertex_texcoord.y, 0, 1, instance_uv_remap.z, instance_uv_remap.w);
	gl_Position = transf_mvp*instance_transform*vec4(vertex_position, 1.0);
}