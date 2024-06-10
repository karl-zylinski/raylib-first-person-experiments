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

// Input lighting values
uniform Light lights[MAX_LIGHTS];
uniform vec4 ambient;
uniform vec3 viewPos;

vec3 hsv2rgb(vec3 c)
{
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

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
	vec3 lightDot = vec3(0.0);
	float directionalDot = 0;
	vec3 normal = normalize(fragNormal);
	vec3 viewD = normalize(viewPos - fragPosition);
	vec3 cA = vec3(84.0/255.0, 89.0/255.0, 161.0/255.0);
	vec3 cB = vec3(0.922,0.686,0.329);

	// NOTE: Implement here your fragment shader code

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

	finalColor = texelColor*colDiffuse*vec4(lightDot, 1);

	// Gamma correction
	finalColor = pow(finalColor, vec4(1.0/2.2));
}