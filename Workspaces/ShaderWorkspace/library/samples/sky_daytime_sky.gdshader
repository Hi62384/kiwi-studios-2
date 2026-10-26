// Daytime Sky
// Blue daytime atmosphere with a compact sun disk and broad warm aureole.
// Target: WorldEnvironment > Environment > Sky > sky_material. Not a mesh material.
shader_type sky;
uniform vec3 sun_direction=vec3(-0.3,0.55,-0.8);
void sky() {
    float y=max(EYEDIR.y,0.0);
    vec3 base=mix(vec3(0.62,0.8,0.95),vec3(0.07,0.27,0.65),pow(y,0.4));
    float sun=dot(EYEDIR,normalize(sun_direction));
    COLOR=base+vec3(1,0.88,0.65)*(pow(max(sun,0.0),800.0)*3.0+pow(max(sun,0.0),24.0)*0.25);
}
