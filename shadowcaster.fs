#version 330

in vec2 fragTexCoord;
uniform sampler2D texture0;

void main()
{
	vec4 texelColor = texture(texture0, fragTexCoord);
	
	texelColor = mix(vec4(1), texelColor, step(0, fragTexCoord.x));

	if (texelColor.a == 0.0) {
		discard;
	}
}