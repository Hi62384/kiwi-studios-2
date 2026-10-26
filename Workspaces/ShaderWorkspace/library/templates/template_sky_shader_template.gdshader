// Sky Shader Template
// Valid directional sky starter with clear coordinate guidance.
// Target: WorldEnvironment > Environment > Sky > sky_material. Not a mesh material.
shader_type sky;
uniform vec4 zenith : source_color=vec4(0.04,0.15,0.4,1);
uniform vec4 horizon : source_color=vec4(0.65,0.8,0.95,1);
uniform float falloff : hint_range(0.1,4)=0.6;
void sky() {
    // EYEDIR is a unit direction. SKY_COORDS can address an equirectangular panorama.
    float up=clamp(EYEDIR.y,0.0,1.0);
    COLOR=mix(horizon.rgb,zenith.rgb,pow(up,falloff));
}
