// Atmospheric Horizon
// Exponential haze wraps the horizon and transitions naturally into ground color.
// Target: WorldEnvironment > Environment > Sky > sky_material. Not a mesh material.
shader_type sky;
uniform vec4 zenith : source_color=vec4(0.04,0.15,0.4,1);
uniform vec4 horizon : source_color=vec4(0.65,0.8,0.95,1);
uniform vec4 ground : source_color=vec4(0.13,0.16,0.2,1);
uniform float falloff : hint_range(1,16)=6;
void sky() {
    float horizon_haze=exp(-abs(EYEDIR.y)*falloff);
    vec3 c=mix(zenith.rgb,horizon.rgb,horizon_haze);
    if(EYEDIR.y<0.0) {
        c=mix(c,ground.rgb,1.0-exp(EYEDIR.y*8.0));
    }
    COLOR=c;
}
