#version 330

// Input vertex attributes
in vec3 vertexPosition;
in vec2 vertexTexCoord;
in vec3 vertexNormal;
//in vec4 vertexColor;

in mat4 instanceTransform;
//in vec4 instanceUVRemap;

// Input uniform values
uniform mat4 mvp;
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
    //fragTexCoord.x = remap(vertexTexCoord.x, 0, 1, instanceUVRemap.x, instanceUVRemap.y);
    //fragTexCoord.y = remap(vertexTexCoord.y, 0, 1, instanceUVRemap.z, instanceUVRemap.w);
    fragTexCoord = vertexTexCoord;
    //fragColor = vertexColor;
    fragNormal = normalize(vec3(matNormal*vec4(vertexNormal, 1.0)));

    // Calculate final vertex position
    gl_Position = mvp*instanceTransform*vec4(vertexPosition, 1.0);
}