// Sunset Sky
// Warm horizon extinction, violet upper atmosphere and a low setting sun.
// Target: WorldEnvironment > Environment > Sky > sky_material. Not a mesh material.
shader_type sky;
void sky() {
    float y=max(EYEDIR.y,0.0);
    vec3 c=mix(vec3(1,0.27,0.06),vec3(0.1,0.035,0.26),pow(y,0.45));
    float sun=dot(EYEDIR,normalize(vec3(-0.6,0.08,-0.8)));
    COLOR=c+vec3(1,0.6,0.18)*smoothstep(0.997,0.999,sun)*2.0;
}
