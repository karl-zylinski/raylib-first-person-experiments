#version 330

// Input vertex attributes (from vertex shader)
in vec3 fragPosition;
in vec2 fragTexCoord;
in vec4 fragColor;
in vec3 fragNormal;

// Output fragment color
out vec4 finalColor;

void main()
{
	vec3 dir = normalize(fragPosition);
	float upness = dot(dir, vec3(0, 1, 0));
	finalColor = vec4(vec3(0.5, 0.6, 0.9) + vec3(0.2, 0.2, 0.2) * upness, 1);
}
