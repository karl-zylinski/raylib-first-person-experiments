#version 330

in vec2 frag_texcoord;
uniform sampler2D tex_atlas;

void main() {
	vec4 tex_color = texture(tex_atlas, frag_texcoord);
	
	tex_color = mix(vec4(1), tex_color, step(0, frag_texcoord.x));

	if (tex_color.a == 0.0) {
		discard;
	}
}