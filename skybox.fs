#version 330

in vec3 frag_world_pos;
out vec4 out_color;

void main() {
	vec3 dir = normalize(frag_world_pos);
	float upness = dot(dir, vec3(0, 1, 0));
	out_color = vec4(vec3(0.5, 0.6, 0.9) + vec3(0.2, 0.2, 0.2) * upness, 1);
}
