#version 330

// Input vertex attributes (from vertex shader)
in vec3 fragPosition;
in vec2 fragTexCoord;
//in vec4 fragColor;
in vec3 fragNormal;

// Input uniform values
uniform sampler2D texture0;
uniform vec4 colDiffuse;

// Output fragment color
out vec4 finalColor;

// NOTE: Add here your custom variables

#define     MAX_LIGHTS              4
#define     LIGHT_DIRECTIONAL       0
#define     LIGHT_POINT             1

struct Light {
	int enabled;
	int type;
	vec3 position;
	vec3 target;
	vec4 color;
};

uniform mat4 lightVP; // Light source view-projection matrix
uniform sampler2D shadowMap;

// Input lighting values
uniform Light lights[MAX_LIGHTS];
uniform vec4 ambient;
uniform vec3 viewPos;

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
	// Texel color fetching from texture sampler
	vec4 texelColor = texture(texture0, fragTexCoord);

	texelColor = mix(vec4(1), texelColor, step(0, fragTexCoord.x));

	if (texelColor.a == 0.0) {
		discard;
	}

	vec3 lightDot = vec3(0.0);
	float directionalDot = 0;
	vec3 normal = normalize(fragNormal);
	vec3 viewD = normalize(viewPos - fragPosition);
	vec3 cA = vec3(84.0/255.0, 89.0/255.0, 161.0/255.0);
	vec3 cB = vec3(0.922,0.686,0.329);

	// NOTE: Implement here your fragment shader code
	vec3 l;

	float num_lights = 0;
	for (int i = 0; i < MAX_LIGHTS; i++)
	{
		if (lights[i].enabled == 1)
		{
			vec3 light = vec3(0.0);
			float falloff = 0;

			if (lights[i].type == LIGHT_DIRECTIONAL)
			{
				light = -normalize(lights[i].target - lights[i].position);
				l = light;
			}

			if (lights[i].type == LIGHT_POINT)
			{
				vec3 dir = lights[i].position - fragPosition;
				falloff = remap(length(dir), 0, 5, 0, 1);
				light = normalize(dir);
			}

			float lightRampVal = (dot(normal, light) + 1)/2;
			vec3 lightRamp = mix(cA, cB, lightRampVal);
			lightDot += lights[i].color.rgb*lightRamp*(1-falloff);
			num_lights += 1;
		}
	}


	 // Shadow calculations
    vec4 fragPosLightSpace = lightVP * vec4(fragPosition, 1);
    fragPosLightSpace.xyz /= fragPosLightSpace.w; // Perform the perspective division
    fragPosLightSpace.xyz = (fragPosLightSpace.xyz + 1.0f) / 2.0f; // Transform from [-1, 1] range to [0, 1] range
    vec2 sampleCoords = fragPosLightSpace.xy;
    float curDepth = fragPosLightSpace.z;
    // Slope-scale depth bias: depth biasing reduces "shadow acne" artifacts, where dark stripes appear all over the scene.
    // The solution is adding a small bias to the depth
    // In this case, the bias is proportional to the slope of the surface, relative to the light

    float bias = 0.00001 * tan(acos(dot(normal,l)));
    //float bias = 0.0001;
    //float bias = max(0.0001 * (1.0 - dot(normal, l)), 0.00002) + 0.00001;
    int shadowCounter = 0;
    const int numSamples = 9;
    // PCF (percentage-closer filtering) algorithm:
    // Instead of testing if just one point is closer to the current point,
    // we test the surrounding points as well.
    // This blurs shadow edges, hiding aliasing artifacts.
    vec2 texelSize = vec2(1.0f / 4096.0f);
    for (int x = -1; x <= 1; x++)
    {
        for (int y = -1; y <= 1; y++)
        {
            float sampleDepth = texture(shadowMap, sampleCoords + texelSize * vec2(x, y)).r;
            if (curDepth - bias > sampleDepth)
            {
                shadowCounter++;
            }
        }
    }
    float viewDLen = length(viewPos - fragPosition);

    float distance_darkening = remap(viewDLen, 2, 5, 0, 0.1);

    if (dot(normal, vec3(0, 1, 0)) > 0.5) {
    	lightDot *= 1 + distance_darkening+0.1;
    }

    lightDot = mix(lightDot, cA, float(shadowCounter) / float(numSamples));
	finalColor = texelColor*colDiffuse*vec4(lightDot, 1) - vec4(0, distance_darkening, distance_darkening, 0);
	// Gamma correction
	finalColor = pow(finalColor, vec4(1.0/2.2));
}