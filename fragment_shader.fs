#version 330

// Input vertex attributes (from vertex shader)
in vec3 fragPosition;
in vec2 fragTexCoord;
in vec4 fragColor;
in vec3 fragNormal;

// Input uniform values
uniform sampler2D texture0;
uniform vec4 colDiffuse;

// Output fragment color
out vec4 finalColor;

void main()
{
    vec3 normal = normalize(fragNormal);
    /*vec3 light = -normalize(vec3(4, 3, 2));
    
    float d = max(dot(normal, light), 0.0);
    finalColor = vec4(d,d,d,1);*/

    // Texel color fetching from texture sampler
    vec4 texelColor = vec4(1,1,1,1);
    
  //  vec3 viewD = normalize(viewPos - fragPosition);
    //vec3 specular = vec3(0.0);

    // NOTE: Implement here your fragment shader code

    vec3 light = -normalize(vec3(100, 200, 300));

    float NdotL = max(dot(normal, light), 0.0);
    vec3 lightDot = vec3(1,1,1)*NdotL;

    //float specCo = 0.0;
    //if (NdotL > 0.0) specCo = pow(max(0.0, dot(viewD, reflect(-(light), normal))), 16.0); // 16 refers to shine
    //specular += specCo;

    finalColor = (texelColor*((vec4(1,0.9,0.9,1))*vec4(lightDot, 1.0)));
    finalColor += texelColor*(vec4(0.2, 0.2, 0.3, 1)/10.0)*colDiffuse;
    //finalColor = vec4(0,1,0,1);

    // Gamma correction
    finalColor = pow(finalColor, vec4(1.0/2.2));
}
