#version 330

// Input vertex attributes
layout(location=0) in vec3 vertexPosition;
layout(location=1) in vec2 vertexTexCoord;
layout(location=2) in vec3 vertexNormal;
layout(location=3)//in vec4 vertexColor;

layout(location=6) in mat4 instanceTransform;
layout(location=10)in vec4 instanceUVRemap;

// Input uniform values
uniform mat4 mvp;
uniform mat4 matView;
uniform mat4 matNormal;

// Output vertex attributes (to fragment shader)
out vec3 fragPosition;
out vec2 fragTexCoord;
out vec4 fragColor;
out vec3 fragNormal;

// NOTE: Add here your custom variables

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
    // Send vertex attributes to fragment shader
    fragPosition = vec3(instanceTransform*vec4(vertexPosition, 1.0));
    fragTexCoord.x = remap(vertexTexCoord.x, 0, 1, instanceUVRemap.x, instanceUVRemap.y);
    fragTexCoord.y = remap(vertexTexCoord.y, 0, 1, instanceUVRemap.z, instanceUVRemap.w);

    mat4 mn = transpose(inverse(instanceTransform));

    //fragColor = vertexColor;
    fragNormal = normalize(vec3(mn*vec4(vertexNormal, 1.0)));

    // Calculate final vertex position
    gl_Position = mvp*instanceTransform*vec4(vertexPosition, 1.0);
}