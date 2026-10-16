// The ambient light, standing in for the three.js HemisphereLight the models' viewer uses
// (TheOutpostModels viewer/main.js): one colour above the horizon and another below.
//
// It is never seen: the background stays black, and the sky only feeds the ambient. A hard step at
// the horizon reproduces three.js's hemisphere response, because the light a tilted surface takes
// from a uniform upper half is exactly mix(ground, sky, 0.5 + 0.5 * normal.y), the formula three.js
// evaluates directly.
shader_type sky;

uniform vec3 sky_color : source_color = vec3(0.941, 0.957, 0.859);
uniform vec3 ground_color : source_color = vec3(0.349, 0.459, 0.494);

void sky() {
	COLOR = EYEDIR.y >= 0.0 ? sky_color : ground_color;
}
