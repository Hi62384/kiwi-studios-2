// Stylized Sky
// Graphic stepped atmosphere with a clean flat sun for illustrated environments.
// Target: WorldEnvironment > Environment > Sky > sky_material. Not a mesh material.
shader_type sky;
void sky() {
    float h=max(EYEDIR.y,0.0);
    float bands=floor(h*5.0)/5.0;
    vec3 c=mix(vec3(0.95,0.72,0.5),vec3(0.16,0.25,0.52),bands);
    float sun=step(0.995,dot(EYEDIR,normalize(vec3(-0.5,0.3,-0.7))));
    COLOR=mix(c,vec3(1,0.92,0.66),sun);
}
