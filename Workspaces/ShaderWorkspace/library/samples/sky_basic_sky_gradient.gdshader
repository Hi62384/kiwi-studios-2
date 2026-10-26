// Basic Sky Gradient
// Two-color hemispherical atmosphere with an adjustable horizon and zenith.
// Target: WorldEnvironment > Environment > Sky > sky_material. Not a mesh material.
shader_type sky;
uniform vec4 zenith : source_color=vec4(0.04,0.15,0.4,1);
uniform vec4 horizon : source_color=vec4(0.65,0.8,0.95,1);
void sky() {
    float h=pow(clamp(EYEDIR.y,0.0,1.0),0.6);
    COLOR=mix(horizon.rgb,zenith.rgb,h);
}
