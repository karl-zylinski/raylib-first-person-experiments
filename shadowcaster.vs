#version 330

in vec3 vertexPosition;
in vec2 vertexTexCoord;

in mat4 instanceTransform;
uniform mat4 mvp;

out vec2 fragTexCoord;

void main()
{
	fragTexCoord = vertexTexCoord;
	gl_Position = mvp*instanceTransform*vec4(vertexPosition, 1.0);
}